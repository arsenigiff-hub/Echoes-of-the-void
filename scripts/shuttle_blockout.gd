extends Node3D
## New linear crew shuttle "Ariadna": one deck, one straight passage, five
## compartments separated by pressure hatches. Nose is at z=0, the stern at
## z=+LENGTH, floor top is y=0. Boxes and cylinders only (no textures yet) so the
## layout, the mundane set dressing and the lighting can be judged first.
##
## Mood reference: small realistic "found place" horror. Nothing is staged to
## scare; the crew was here a minute ago, the lights are tired, and the long
## straight view through five hatches does the rest.

const WIDTH := 4.8          # inner width (x from -2.4 to +2.4)
const HEIGHT := 2.5         # floor to ceiling
const WALL := 0.15
const BULKHEAD := 0.30
const HATCH_W := 0.95
const HATCH_H := 1.95       # player capsule is 1.82 m tall
const SILL := 0.03          # visual lip only: the player cannot climb solid steps under a lintel

# Compartments from the nose: [name, inner length]
const COMPARTMENTS := [
	["Cockpit", 4.0],
	["CrewBay", 4.7],
	["Galley", 4.7],
	["Medbay", 4.0],
	["Cargo", 5.0],
	["Reactor", 4.7],
	["Airlock", 4.0],
]
const LABELS := {
	"Cockpit": "ПИЛОТСКАЯ", "CrewBay": "ЭКИПАЖ", "Galley": "КАМБУЗ",
	"Medbay": "МЕДОТСЕК", "Cargo": "ГРУЗ", "Reactor": "РЕАКТОР", "Airlock": "ШЛЮЗ",
}
# Props were authored for a 3.6 m wide hull; X() pushes wall-side items out
# to the new walls while keeping the centre line where it was.
const DX := (WIDTH - 3.6) * 0.5

var compartment_ranges: Dictionary = {}   # name -> Vector2(z_start, z_end)
var hatch_z: Array[float] = []            # bulkhead centres
var _materials: Dictionary = {}

# Palette: cold grey-green hull, dirty cream panels, brown seat vinyl.
const C_FLOOR := Color(0.20, 0.21, 0.21)
const C_WALL := Color(0.40, 0.42, 0.40)
const C_CEIL := Color(0.27, 0.29, 0.29)
const C_BULK := Color(0.46, 0.46, 0.43)
const C_RIB := Color(0.25, 0.27, 0.27)
const C_METAL := Color(0.34, 0.36, 0.37)
const C_SEAT := Color(0.26, 0.18, 0.15)
const C_GREEN := Color(0.17, 0.24, 0.20)
const C_PAPER := Color(0.72, 0.70, 0.60)
const C_HAZARD := Color(0.62, 0.52, 0.12)


func _ready() -> void:
	_build_environment()
	var z := 0.0
	for index in COMPARTMENTS.size():
		var label: String = COMPARTMENTS[index][0]
		var length: float = COMPARTMENTS[index][1]
		compartment_ranges[label] = Vector2(z, z + length)
		_build_compartment_shell(label, z, length)
		_build_ribs_and_runs(label, z, length)
		z += length
		if index < COMPARTMENTS.size() - 1:
			_build_bulkhead(z, COMPARTMENTS[index + 1][0])
			hatch_z.append(z + BULKHEAD * 0.5)
			z += BULKHEAD
	_build_end_walls(z)
	_build_window_view()
	_build_cockpit()
	_build_crew_bay()
	_build_galley()
	_build_medbay()
	_build_cargo()
	_build_reactor()
	_build_airlock()
	_build_lights()
	_build_traces()
	_build_tripo_props()
	_build_interactions()
	_build_ambience()
	_apply_textures()
	_build_postfx()
	_setup_power()
	var player := get_node_or_null("Player") as Node3D
	if player != null:
		var galley: Vector2 = compartment_ranges["Galley"]
		player.position = Vector3(0.0, 0.05, (galley.x + galley.y) * 0.5)


func X(value: float) -> float:
	return value + signf(value) * DX if absf(value) > 0.5 else value


func total_length() -> float:
	var length := 0.0
	for entry in COMPARTMENTS:
		length += entry[1]
	return length + BULKHEAD * (COMPARTMENTS.size() - 1)


# ------------------------------------------------------------------ helpers --

func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), rough]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = rough
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_materials[key] = material
	return material


func _emit(color: Color, energy := 1.4) -> StandardMaterial3D:
	var key := "emit|%s|%.2f" % [color.to_html(), energy]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = material
	return material


func _box(label: String, size: Vector3, pos: Vector3, color: Color, solid := true,
		rot := Vector3.ZERO, material: Material = null) -> Node3D:
	var body: Node3D
	if solid:
		body = StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		shape.shape = box_shape
		body.add_child(shape)
	else:
		body = Node3D.new()
	body.name = label
	body.position = pos
	body.rotation_degrees = rot
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material if material != null else _mat(color)
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	add_child(body)
	return body


func _cyl(label: String, radius: float, length: float, pos: Vector3, color: Color,
		axis := "z", solid := false, material: Material = null) -> Node3D:
	var body: Node3D
	if solid:
		body = StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl_shape := CylinderShape3D.new()
		cyl_shape.radius = radius
		cyl_shape.height = length
		shape.shape = cyl_shape
		body.add_child(shape)
	else:
		body = Node3D.new()
	body.name = label
	body.position = pos
	var mesh_node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.material = material if material != null else _mat(color, 0.6)
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	match axis:
		"z":
			body.rotation_degrees.x = 90.0
		"x":
			body.rotation_degrees.z = 90.0
	add_child(body)
	return body


func _label(text: String, pos: Vector3, yaw: float, size := 0.05, color := Color(0.62, 0.60, 0.46)) -> void:
	var node := Label3D.new()
	node.text = text
	node.position = pos
	node.rotation_degrees.y = yaw
	node.pixel_size = size / 24.0
	node.font_size = 24
	node.modulate = color
	node.double_sided = false
	node.shaded = true
	node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(node)


func _prop(label: String, size: Vector3, x: float, z: float, color: Color, y_bottom := 0.0) -> Node3D:
	return _box(label, size, Vector3(x, y_bottom + size.y * 0.5, z), color)


func _deco(label: String, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> Node3D:
	return _box(label, size, pos, color, false, rot)


# -------------------------------------------------------------------- hull --

var _environment: Environment
var _planet: Node3D


func _build_environment() -> void:
	_environment = Environment.new()
	# Real star panorama behind the cockpit window instead of flat black.
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = load("res://assetss/space/starfield_pano.png")
	sky_material.energy_multiplier = 0.9
	var sky := Sky.new()
	sky.sky_material = sky_material
	_environment.sky = sky
	_environment.background_mode = Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.20, 0.24, 0.28)
	_environment.ambient_light_energy = 0.35
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.04, 0.05, 0.06)
	_environment.fog_density = 0.035
	_environment.fog_sky_affect = 0.0
	var world := WorldEnvironment.new()
	world.environment = _environment
	add_child(world)


func _process(delta: float) -> void:
	# The shuttle drifts: stars and the gas giant creep past the cockpit window.
	if _environment != null:
		_environment.sky_rotation.y += delta * 0.004
	if _planet != null:
		_planet.rotation.y += delta * 0.01
	_update_prompt(delta)
	_update_audio(delta)
	_animate_oxygen(delta)


func _build_window_view() -> void:
	# Window glass: nearly transparent, with a faint film of grime on the inside.
	var glass := get_node_or_null("NoseWall_Glass")
	if glass != null:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.55, 0.65, 0.75, 0.07)
		mat.roughness = 0.1
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		for found in glass.find_children("*", "MeshInstance3D", true, false):
			(found as MeshInstance3D).material_override = mat
		var grime := MeshInstance3D.new()
		grime.name = "WindowGrime"
		var quad := QuadMesh.new()
		quad.size = Vector2(3.4, 1.2)
		var grime_mat := StandardMaterial3D.new()
		grime_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		grime_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		grime_mat.albedo_texture = load("res://assetss/space/glass_grime.png")
		grime_mat.albedo_color = Color(0.45, 0.55, 0.65, 0.22)
		grime_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		grime.mesh = quad
		grime.material_override = grime_mat
		grime.position = Vector3(0, 1.4, 0.08)
		grime.rotation_degrees.y = 180.0
		add_child(grime)
	# A gas giant with rings far ahead and to the right, bigger than the window.
	_planet = Node3D.new()
	_planet.name = "WindowPlanet"
	_planet.position = Vector3(70.0, 12.0, -300.0)
	var sphere := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 45.0
	sphere_mesh.height = 90.0
	sphere_mesh.radial_segments = 32
	sphere_mesh.rings = 16
	var planet_mat := StandardMaterial3D.new()
	planet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	planet_mat.albedo_texture = load("res://assetss/space/planet_gas.png")
	planet_mat.albedo_color = Color(0.85, 0.78, 0.68)
	planet_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	planet_mat.disable_fog = true
	sphere_mesh.material = planet_mat
	sphere.mesh = sphere_mesh
	_planet.add_child(sphere)
	add_child(_planet)
	var ring := MeshInstance3D.new()
	ring.name = "WindowPlanetRing"
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_texture = load("res://assetss/space/planet_ring.png")
	ring_mat.albedo_color = Color(0.8, 0.78, 0.74, 0.9)
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.disable_fog = true
	ring_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# A real flat annulus: texture U runs from the inner to the outer edge, V around.
	ring.mesh = _ring_mesh(58.0, 100.0, 96)
	ring.material_override = ring_mat
	ring.position = _planet.position
	ring.rotation_degrees = Vector3(-14.0, 0.0, 14.0)
	add_child(ring)


func _ring_mesh(inner: float, outer: float, segments: int) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in segments:
		var a0 := TAU * index / segments
		var a1 := TAU * (index + 1) / segments
		var v0 := float(index) / segments
		var v1 := float(index + 1) / segments
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var o0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var o1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		tool.set_uv(Vector2(0.0, v0)); tool.add_vertex(i0)
		tool.set_uv(Vector2(1.0, v0)); tool.add_vertex(o0)
		tool.set_uv(Vector2(0.0, v1)); tool.add_vertex(i1)
		tool.set_uv(Vector2(1.0, v0)); tool.add_vertex(o0)
		tool.set_uv(Vector2(1.0, v1)); tool.add_vertex(o1)
		tool.set_uv(Vector2(0.0, v1)); tool.add_vertex(i1)
	return tool.commit()


func _wheel_model(label: String, pos: Vector3, yaw: float) -> Node3D:
	# Hand wheel modelled in Blender (tools/blender/valve_wheel.py): rim, six spokes, hub, grip.
	var packed := load("res://assetss/blender/hatch_wheel.glb") as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	node.name = label
	node.position = pos
	node.rotation_degrees.y = yaw
	add_child(node)
	return node


func _build_compartment_shell(label: String, z0: float, length: float) -> void:
	var zc := z0 + length * 0.5
	_box(label + "_Floor", Vector3(WIDTH + 2.0 * WALL, 0.15, length), Vector3(0, -0.075, zc), C_FLOOR)
	_box(label + "_Ceiling", Vector3(WIDTH + 2.0 * WALL, 0.15, length), Vector3(0, HEIGHT + 0.075, zc), C_CEIL)
	_box(label + "_WallL", Vector3(WALL, HEIGHT, length), Vector3(-(WIDTH + WALL) * 0.5, HEIGHT * 0.5, zc), C_WALL)
	_box(label + "_WallR", Vector3(WALL, HEIGHT, length), Vector3((WIDTH + WALL) * 0.5, HEIGHT * 0.5, zc), C_WALL)
	# Chamfered wall/ceiling corners: the cabin reads as a tube, not a box.
	for side in [-1.0, 1.0]:
		_box(label + "_Chamfer", Vector3(0.42, 0.42, length),
			Vector3(side * (WIDTH * 0.5 - 0.08), HEIGHT - 0.08, zc), C_CEIL, true, Vector3(0, 0, 45.0))


func _build_ribs_and_runs(label: String, z0: float, length: float) -> void:
	var zc := z0 + length * 0.5
	# Hull frames every metre: they carry the scale of the ship.
	var count := int(floor(length))
	for index in count:
		var z := z0 + 0.5 + index * (length - 1.0) / maxf(float(count - 1), 1.0)
		if label == "Reactor" and index == 0:
			# Leave the recessed breaker bay clear of this wall rib.
			_deco(label + "_RibL", Vector3(0.10, 0.75, 0.12), Vector3(-WIDTH * 0.5 + 0.05, 0.425, z), C_RIB)
			_deco(label + "_RibL", Vector3(0.10, 0.75, 0.12), Vector3(-WIDTH * 0.5 + 0.05, 2.075, z), C_RIB)
		else:
			_deco(label + "_RibL", Vector3(0.10, HEIGHT - 0.1, 0.12), Vector3(-WIDTH * 0.5 + 0.05, HEIGHT * 0.5, z), C_RIB)
		_deco(label + "_RibR", Vector3(0.10, HEIGHT - 0.1, 0.12), Vector3(WIDTH * 0.5 - 0.05, HEIGHT * 0.5, z), C_RIB)
		_deco(label + "_RibTop", Vector3(WIDTH - 0.5, 0.10, 0.12), Vector3(0, HEIGHT - 0.05, z), C_RIB)
	# Floor plate seams and a cable tray along the left wall.
	var seam := 0.0
	while seam < length:
		_deco(label + "_Seam", Vector3(WIDTH, 0.004, 0.02), Vector3(0, 0.003, z0 + seam), Color(0.10, 0.10, 0.10))
		seam += 0.75
	_deco(label + "_Tray", Vector3(0.12, 0.08, length), Vector3(-WIDTH * 0.5 + 0.06, 0.22, zc), Color(0.12, 0.12, 0.12))
	_cyl(label + "_Cable", 0.025, length, Vector3(-WIDTH * 0.5 + 0.08, 0.30, zc), Color(0.05, 0.05, 0.05))
	# Ceiling duct on the right with a pipe on the left.
	_deco(label + "_Duct", Vector3(0.34, 0.24, length - 0.1), Vector3(1.05, HEIGHT - 0.2, zc), C_METAL)
	_cyl(label + "_Pipe", 0.045, length - 0.1, Vector3(-1.1, HEIGHT - 0.12, zc), Color(0.30, 0.30, 0.28))


func _build_bulkhead(z_start: float, next_label: String) -> void:
	# Bulkhead with a centred hatch opening: two side slabs, a lintel and a lip.
	var zc := z_start + BULKHEAD * 0.5
	var side := (WIDTH - HATCH_W) * 0.5
	var base := "Bulkhead_%d" % int(z_start * 10.0)
	_box(base + "_L", Vector3(side, HEIGHT, BULKHEAD), Vector3(-(HATCH_W + side) * 0.5, HEIGHT * 0.5, zc), C_BULK)
	_box(base + "_R", Vector3(side, HEIGHT, BULKHEAD), Vector3((HATCH_W + side) * 0.5, HEIGHT * 0.5, zc), C_BULK)
	_box(base + "_Lintel", Vector3(HATCH_W, HEIGHT - HATCH_H, BULKHEAD),
		Vector3(0, HATCH_H + (HEIGHT - HATCH_H) * 0.5, zc), C_BULK)
	_box(base + "_Sill", Vector3(HATCH_W, SILL, BULKHEAD), Vector3(0, SILL * 0.5, zc), C_HAZARD, false)
	# Raised coaming on both faces so the opening reads as a pressure door.
	var frame := Color(0.52, 0.52, 0.48)
	for dz in [-BULKHEAD * 0.5 - 0.04, BULKHEAD * 0.5 + 0.04]:
		_deco(base + "_FrameL", Vector3(0.12, HATCH_H, 0.08), Vector3(-HATCH_W * 0.5 - 0.06, HATCH_H * 0.5, zc + dz), frame)
		_deco(base + "_FrameR", Vector3(0.12, HATCH_H, 0.08), Vector3(HATCH_W * 0.5 + 0.06, HATCH_H * 0.5, zc + dz), frame)
		_deco(base + "_FrameT", Vector3(HATCH_W + 0.24, 0.12, 0.08), Vector3(0, HATCH_H + 0.06, zc + dz), frame)
	# Hatch wheel and a compartment sign on the face towards the nose and stern.
	for face in [-1.0, 1.0]:
		var zf: float = zc + face * (BULKHEAD * 0.5 + 0.09)
		_wheel_model(base + "_Wheel", Vector3(0.74, 1.1, zf), 0.0 if face > 0.0 else 180.0)
		_deco(base + "_SignPlate", Vector3(0.62, 0.14, 0.02), Vector3(0, HATCH_H + 0.17, zf), Color(0.14, 0.14, 0.12))
	_label(LABELS[next_label], Vector3(0, HATCH_H + 0.17, zc + BULKHEAD * 0.5 + 0.105), 0.0, 0.09)
	_label("→", Vector3(0, HATCH_H + 0.17, zc - BULKHEAD * 0.5 - 0.105), 180.0, 0.09)
	# Dirty tape on the floor at every hatch.
	_deco(base + "_Tape", Vector3(HATCH_W + 0.4, 0.004, 0.06), Vector3(0, 0.004, zc + BULKHEAD * 0.5 + 0.2), C_HAZARD)


func _build_end_walls(z_end: float) -> void:
	# Nose wall with a window, stern wall with the EVA hatch.
	var win_w := 3.4
	var win_low := 1.0
	var win_high := HEIGHT - 0.3
	var win_h := win_high - win_low
	var win_mid := (win_low + win_high) * 0.5
	var pillar_w := (WIDTH + 2.0 * WALL - win_w) * 0.5
	_box("NoseWall_Low", Vector3(WIDTH + 2.0 * WALL, win_low, WALL), Vector3(0, win_low * 0.5, -WALL * 0.5), C_WALL)
	_box("NoseWall_High", Vector3(WIDTH + 2.0 * WALL, HEIGHT - win_high, WALL),
		Vector3(0, win_high + (HEIGHT - win_high) * 0.5, -WALL * 0.5), C_WALL)
	for side in [-1.0, 1.0]:
		_box("NoseWall_Pillar", Vector3(pillar_w, win_h, WALL),
			Vector3(side * (win_w * 0.5 + pillar_w * 0.5), win_mid, -WALL * 0.5), C_WALL)
	_box("NoseWall_Glass", Vector3(win_w, win_h, 0.04), Vector3(0, win_mid, -0.02), Color(0.02, 0.03, 0.06))
	# Window frame and mullions.
	var frame := Color(0.20, 0.21, 0.21)
	_deco("WinFrameT", Vector3(win_w + 0.2, 0.10, 0.10), Vector3(0, win_high, 0.05), frame)
	_deco("WinFrameB", Vector3(win_w + 0.2, 0.10, 0.10), Vector3(0, win_low, 0.05), frame)
	_deco("WinFrameL", Vector3(0.10, win_h, 0.10), Vector3(-win_w * 0.5, win_mid, 0.05), frame)
	_deco("WinFrameR", Vector3(0.10, win_h, 0.10), Vector3(win_w * 0.5, win_mid, 0.05), frame)
	for mull in [-win_w / 6.0, win_w / 6.0]:
		_deco("WinMullion", Vector3(0.07, win_h, 0.08), Vector3(mull, win_mid, 0.05), frame)
	_box("SternWall", Vector3(WIDTH + 2.0 * WALL, HEIGHT, WALL), Vector3(0, HEIGHT * 0.5, z_end + WALL * 0.5), C_WALL)


# --------------------------------------------------------------- cockpit ----

func _build_cockpit() -> void:
	var c: Vector2 = compartment_ranges["Cockpit"]
	_prop("NavConsole", Vector3(3.8, 0.9, 0.55), X(0.0), c.x + 0.55, C_METAL)
	# Slanted dash with three dead-ish screens and a row of switches.
	_deco("DashSlope", Vector3(3.7, 0.06, 0.5), Vector3(X(0), 0.96, c.x + 0.58), Color(0.18, 0.19, 0.20), Vector3(-25, 0, 0))
	var screens := [Color(0.10, 0.55, 0.30), Color(0.55, 0.38, 0.10), Color(0.04, 0.10, 0.14)]
	for index in 3:
		var sx := -1.1 + index * 1.1
		_deco("DashScreen%d" % index, Vector3(0.55, 0.32, 0.02),
			Vector3(sx, 1.04, c.x + 0.50), screens[index], Vector3(-25, 0, 0)).get_child(0).set("material_override", _emit(screens[index], 1.1))
	for index in 9:
		_deco("Switch%d" % index, Vector3(0.04, 0.06, 0.04), Vector3(-1.5 + index * 0.37, 1.0, c.x + 0.78),
			Color(0.55, 0.5, 0.4) if index % 3 else Color(0.5, 0.12, 0.1), Vector3(-25, 0, 0))
	# Overhead panel with breakers.
	_deco("OverheadPanel", Vector3(1.6, 0.06, 0.7), Vector3(X(0), HEIGHT - 0.32, c.x + 1.2), Color(0.16, 0.17, 0.17), Vector3(18, 0, 0))
	for index in 12:
		_deco("Breaker%d" % index, Vector3(0.05, 0.05, 0.03),
			Vector3(-0.65 + index * 0.118, HEIGHT - 0.30, c.x + 1.0), Color(0.55, 0.5, 0.42) if index != 7 else Color(0.5, 0.1, 0.08))
	# Two pilot seats with headrests; the left one is turned a little as if just left.
	for side in [-1.0, 1.0]:
		var name_side := "L" if side < 0.0 else "R"
		var seat := _prop("PilotSeat" + name_side, Vector3(0.6, 0.45, 0.6), side * 0.95, c.x + 1.75, C_SEAT)
		_prop("PilotSeat%s_Back" % name_side, Vector3(0.6, 0.85, 0.14), side * 0.95, c.x + 2.08, C_SEAT, 0.45)
		_deco("PilotSeat%s_Head" % name_side, Vector3(0.32, 0.22, 0.12), Vector3(side * 0.95, 1.45, c.x + 2.1), C_SEAT)
		_deco("PilotSeat%s_Belt" % name_side, Vector3(0.05, 0.5, 0.02), Vector3(side * 0.95 - 0.18, 0.72, c.x + 1.98), Color(0.06, 0.06, 0.06), Vector3(0, 0, 8))
		seat.rotation_degrees.y = -14.0 if side < 0.0 else 0.0
	# Things on the console: mug, clipboard, crumpled foil, a pen.
	_cyl("Mug", 0.045, 0.10, Vector3(X(0.95), 1.0, c.x + 0.62), Color(0.55, 0.55, 0.5))
	_deco("Clipboard", Vector3(0.24, 0.015, 0.32), Vector3(X(-1.2), 0.94, c.x + 0.7), C_PAPER, Vector3(0, 20, 0))
	_deco("Pen", Vector3(0.14, 0.012, 0.012), Vector3(X(-1.05), 0.955, c.x + 0.72), Color(0.1, 0.1, 0.35), Vector3(0, 70, 0))


# ----------------------------------------------------------------- crew bay -

func _build_crew_bay() -> void:
	var c: Vector2 = compartment_ranges["CrewBay"]
	_prop("RadioDesk", Vector3(0.6, 0.95, 1.5), X(1.4), c.x + 1.5, C_METAL)
	_deco("RadioSet", Vector3(0.38, 0.30, 0.46), Vector3(X(1.45), 1.10, c.x + 1.35), Color(0.16, 0.18, 0.15), Vector3(0, -6, 0))
	_deco("RadioScreen", Vector3(0.02, 0.12, 0.2), Vector3(X(1.255), 1.15, c.x + 1.35), Color(0.1, 0.8, 0.4)).get_child(0).set("material_override", _emit(Color(0.1, 0.8, 0.4), 1.3))
	for index in 4:
		_cyl("RadioKnob%d" % index, 0.025, 0.03, Vector3(X(1.255), 1.03, c.x + 1.2 + index * 0.07), Color(0.1, 0.1, 0.1), "x")
	_deco("RadioWire", Vector3(0.03, 0.03, 0.9), Vector3(X(1.0), 0.06, c.x + 1.8), Color(0.04, 0.04, 0.04), Vector3(0, 12, 0))
	_deco("Headset", Vector3(0.18, 0.04, 0.2), Vector3(X(1.45), 0.97, c.x + 0.95), Color(0.08, 0.08, 0.08), Vector3(0, 30, 0))
	_deco("LogBook", Vector3(0.22, 0.03, 0.3), Vector3(X(1.45), 0.965, c.x + 2.0), Color(0.18, 0.22, 0.30), Vector3(0, -15, 0))
	for index in 3:
		var z := c.x + 0.8 + index * 0.9
		_prop("JumpSeat%d" % index, Vector3(0.5, 0.5, 0.55), X(-1.45), z, C_SEAT)
		_prop("JumpSeat%d_Back" % index, Vector3(0.12, 0.75, 0.55), X(-1.7), z, C_SEAT, 0.5)
	# A jacket thrown over the middle seat and a thermos under the desk.
	_cyl("Thermos", 0.05, 0.24, Vector3(X(1.0), 0.12, c.x + 2.1), Color(0.35, 0.36, 0.34))
	# Wall locker with a half-open door.
	_prop("CrewLocker", Vector3(0.5, 1.8, 0.7), X(-1.5), c.x + 3.2, C_GREEN)
	_deco("LockerDoor", Vector3(0.04, 1.7, 0.34), Vector3(X(-1.2), 0.95, c.x + 2.98), Color(0.20, 0.27, 0.22), Vector3(0, 55, 0))
	_label("СВЯЗЬ", Vector3(X(1.72), 1.65, c.x + 1.5), -90.0, 0.06, Color(0.45, 0.55, 0.5))


# ------------------------------------------------------------------- galley -

func _build_galley() -> void:
	var c: Vector2 = compartment_ranges["Galley"]
	_prop("SleepCapsule", Vector3(0.95, 0.75, 2.1), X(-1.25), c.x + 1.5, Color(0.50, 0.50, 0.46), 0.25)
	_deco("CapsuleLid", Vector3(0.95, 0.06, 1.9), Vector3(X(-1.45), 1.62, c.x + 1.5), Color(0.55, 0.55, 0.5), Vector3(0, 0, 58))
	_deco("Mattress", Vector3(0.8, 0.12, 1.9), Vector3(X(-1.25), 1.06, c.x + 1.5), Color(0.28, 0.30, 0.34))
	_deco("Blanket", Vector3(0.78, 0.08, 1.0), Vector3(X(-1.25), 1.14, c.x + 1.15), Color(0.22, 0.26, 0.20), Vector3(0, 0, 3))
	_deco("Pillow", Vector3(0.4, 0.12, 0.3), Vector3(X(-1.25), 1.18, c.x + 0.7), Color(0.55, 0.54, 0.48))
	# Taped-up personal things above the capsule: a photo and a child's drawing.
	_deco("Photo", Vector3(0.015, 0.16, 0.12), Vector3(X(-1.77), 1.62, c.x + 1.2), Color(0.55, 0.45, 0.35), Vector3(4, 0, 0))
	_deco("Drawing", Vector3(0.012, 0.24, 0.3), Vector3(X(-1.77), 1.55, c.x + 1.6), Color(0.62, 0.58, 0.30), Vector3(-3, 0, 0))
	_deco("DrawingSun", Vector3(0.014, 0.07, 0.07), Vector3(X(-1.765), 1.60, c.x + 1.55), Color(0.70, 0.30, 0.10))
	_prop("GalleyCounter", Vector3(0.6, 0.95, 1.8), X(1.4), c.x + 1.1, C_METAL)
	_deco("Sink", Vector3(0.4, 0.04, 0.5), Vector3(X(1.4), 0.96, c.x + 0.7), Color(0.12, 0.12, 0.12))
	_cyl("Tap", 0.015, 0.2, Vector3(X(1.6), 1.08, c.x + 0.7), Color(0.5, 0.5, 0.5), "y")
	for index in 2:
		_cyl("Cup%d" % index, 0.04, 0.09, Vector3(X(1.35), 1.0, c.x + 1.2 + index * 0.18), Color(0.58, 0.57, 0.5))
	_deco("FoodPack1", Vector3(0.18, 0.04, 0.26), Vector3(X(1.5), 0.97, c.x + 1.6), Color(0.55, 0.25, 0.15), Vector3(0, 15, 0))
	_deco("FoodPack2", Vector3(0.16, 0.04, 0.22), Vector3(X(1.3), 0.97, c.x + 1.75), Color(0.25, 0.45, 0.30), Vector3(0, -20, 0))
	_prop("FoodLocker", Vector3(0.6, 1.6, 0.8), X(1.4), c.x + 2.6, C_GREEN)
	_deco("FoodLockerDoor", Vector3(0.04, 1.5, 0.35), Vector3(X(1.12), 0.85, c.x + 2.15), Color(0.20, 0.27, 0.22), Vector3(0, -50, 0))
	_label("КАМБУЗ", Vector3(X(1.72), 1.55, c.x + 1.1), -90.0, 0.06, Color(0.45, 0.55, 0.5))


# ------------------------------------------------------------------ medbay --

const MEDBAY_EXAM_LAMP := preload("res://assetss/blender/medbay_exam_lamp/medbay_exam_lamp.glb")


func _build_medbay() -> void:
	var c: Vector2 = compartment_ranges["Medbay"]
	# Exam table, floor lamp, wall cabinet and work counter.
	_prop("ExamTable", Vector3(0.9, 0.55, 2.0), -1.1, c.x + 2.0, Color(0.50, 0.52, 0.50), 0.35)
	_cyl("ExamTableLeg", 0.07, 0.4, Vector3(-1.1, 0.2, c.x + 2.0), Color(0.3, 0.3, 0.3), "y")
	_deco("ExamMat", Vector3(0.8, 0.06, 1.9), Vector3(-1.1, 0.93, c.x + 2.0), Color(0.34, 0.40, 0.40))
	_deco("ExamSheet", Vector3(0.8, 0.03, 1.1), Vector3(-1.1, 0.97, c.x + 2.3), Color(0.55, 0.57, 0.55), Vector3(0, 4, 0))
	_build_medbay_exam_lamp(c.x)
	_prop("MedCabinet", Vector3(0.5, 1.9, 1.4), X(-1.5), c.x + 1.2, Color(0.55, 0.56, 0.54))
	_deco("MedCross", Vector3(0.02, 0.3, 0.1), Vector3(X(-1.2), 1.5, c.x + 1.2), Color(0.55, 0.1, 0.1))
	_deco("MedCrossH", Vector3(0.02, 0.1, 0.3), Vector3(X(-1.2), 1.5, c.x + 1.2), Color(0.55, 0.1, 0.1))
	_prop("MedCounter", Vector3(0.6, 0.95, 1.6), X(1.4), c.x + 2.8, C_METAL)
	_deco("SurgeryLampArm", Vector3(0.04, 0.04, 1.0), Vector3(-1.1, HEIGHT - 0.4, c.x + 2.0), Color(0.4, 0.4, 0.4))
	_deco("SurgeryLamp", Vector3(0.5, 0.08, 0.5), Vector3(-1.1, HEIGHT - 0.55, c.x + 2.0), Color(0.5, 0.52, 0.5))
	_deco("Syringe", Vector3(0.12, 0.015, 0.015), Vector3(X(1.4), 0.965, c.x + 2.6), Color(0.7, 0.7, 0.7), Vector3(0, 35, 0))
	_deco("MedNote", Vector3(0.2, 0.012, 0.28), Vector3(X(1.4), 0.96, c.x + 3.1), C_PAPER, Vector3(0, -25, 0))
	_label("МЕДИЦИНА", Vector3(X(1.72), 1.65, c.x + 2.8), -90.0, 0.06, Color(0.45, 0.55, 0.5))


func _build_medbay_exam_lamp(start_z: float) -> void:
	var lamp := MEDBAY_EXAM_LAMP.instantiate() as Node3D
	lamp.name = "MedbayExamLamp"
	lamp.position = Vector3(-0.56, 0.0, start_z + 0.92)
	add_child(lamp)
	var visual := lamp.find_child("LampMesh", true, false) as MeshInstance3D
	if visual != null and visual.mesh != null:
		for surface in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	var socket := lamp.find_child("BeamSocket", true, false) as Node3D
	var target := lamp.find_child("BeamTarget", true, false) as Node3D
	if socket == null or target == null:
		push_error("Medbay exam lamp is missing its Blender beam markers.")
		return
	var beam := SpotLight3D.new()
	beam.name = "ExamBeam"
	beam.position = lamp.to_local(socket.global_position)
	beam.light_color = Color(0.79, 0.90, 0.92)
	beam.light_energy = 1.25
	beam.spot_range = 2.15
	beam.spot_angle = 25.0
	beam.spot_angle_attenuation = 1.1
	beam.shadow_enabled = true
	lamp.add_child(beam)
	beam.look_at(target.global_position)


# ------------------------------------------------------------------- cargo --

const CARGO_EQUIPMENT := preload("res://assetss/blender/cargo_equipment/cargo_equipment.glb")


func _build_cargo() -> void:
	var c: Vector2 = compartment_ranges["Cargo"]
	# Keep the existing collision bodies; the cargo kit supplies only the visuals.
	var crate := Color(0.34, 0.28, 0.20)
	_prop("CargoCrateA", Vector3(1.0, 0.9, 1.0), -1.85, c.x + 1.0, crate)
	_prop("CargoCrateB", Vector3(1.0, 0.9, 1.0), -1.85, c.x + 1.0, crate, 0.9)
	_prop("CargoCrateC", Vector3(1.0, 0.7, 1.4), -1.75, c.x + 2.4, Color(0.30, 0.31, 0.28))
	_prop("CargoCrateD", Vector3(0.8, 0.8, 0.8), -2.0, c.x + 3.6, crate)
	_prop("CargoContainer", Vector3(1.4, 1.5, 2.2), 1.7, c.x + 2.0, Color(0.28, 0.32, 0.34))
	_prop("SmallBox", Vector3(0.5, 0.35, 0.4), 2.0, c.x + 3.6, crate)
	for label in ["CargoContainer", "SmallBox"]:
		_hide_mesh(label)
	var kit := CARGO_EQUIPMENT.instantiate() as Node3D
	kit.name = "CargoEquipment"
	kit.position = Vector3(WIDTH * 0.5, 0.0, c.x + 2.0)
	kit.rotation_degrees.y = -90.0
	add_child(kit)
	for child in kit.find_children("*", "MeshInstance3D", true, false):
		var visual := child as MeshInstance3D
		for surface in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_label("ГРУЗ", Vector3(X(1.72), 1.9, c.x + 2.0), -90.0, 0.08, Color(0.6, 0.55, 0.3))


# ------------------------------------------------------------------ reactor -

func _build_reactor() -> void:
	var c: Vector2 = compartment_ranges["Reactor"]
	_prop("ReactorBlock", Vector3(1.3, 1.8, 2.0), X(1.1), c.x + 1.75, Color(0.30, 0.26, 0.25))
	_cyl("ReactorCore", 0.34, 1.2, Vector3(X(0.62), 1.0, c.x + 1.75), Color(0.35, 0.3, 0.28), "x")
	# Hot glow strips on the reactor block and warning stripes on the floor.
	_deco("ReactorGlow", Vector3(0.02, 0.1, 1.5), Vector3(X(0.44), 1.5, c.x + 1.75), Color(1.0, 0.45, 0.12)).get_child(0).set("material_override", _emit(Color(1.0, 0.45, 0.12), 1.0))
	for index in 6:
		_deco("FloorHazard%d" % index, Vector3(0.18, 0.004, 0.5), Vector3(X(0.15), 0.005, c.x + 0.8 + index * 0.4), C_HAZARD, Vector3(0, 35, 0))
	_prop("OxygenUnit", Vector3(0.6, 1.4, 1.35), X(-1.45), c.x + 1.55, C_GREEN)
	_cyl("OxygenGaugeA", 0.07, 0.04, Vector3(X(-1.14), 1.15, c.x + 1.35), Color(0.75, 0.74, 0.66), "x")
	_cyl("OxygenGaugeB", 0.07, 0.04, Vector3(X(-1.14), 1.15, c.x + 1.75), Color(0.75, 0.74, 0.66), "x")
	_cyl("OxygenValve", 0.12, 0.04, Vector3(X(-1.14), 0.7, c.x + 1.55), Color(0.55, 0.12, 0.10), "x")
	_prop("PipeCabinet", Vector3(0.5, 1.9, 0.7), X(-1.5), c.x + 2.6, Color(0.32, 0.34, 0.35))


# ------------------------------------------------------------------ airlock -

const AIRLOCK_EQUIPMENT := preload("res://assetss/blender/airlock_equipment/airlock_equipment.glb")


func _build_airlock() -> void:
	var c: Vector2 = compartment_ranges["Airlock"]
	_prop("AirlockBench", Vector3(0.45, 0.45, 1.8), X(-1.5), c.x + 1.2, C_SEAT)
	_prop("SuitLocker", Vector3(0.6, 1.9, 0.9), X(1.45), c.x + 1.0, C_GREEN)
	_prop("SuitLocker2", Vector3(0.6, 1.9, 0.9), X(1.45), c.x + 2.0, C_GREEN)
	for label in ["AirlockBench", "SuitLocker", "SuitLocker2"]:
		_hide_mesh(label)
	_mount_airlock_equipment(c.x)
	# Round EVA hatch on the stern wall with a wheel and a green status lamp.
	_cyl("EvaHatch", 0.58, 0.10, Vector3(X(0), 1.0, c.y - 0.06), Color(0.36, 0.36, 0.32), "z", true)
	_cyl("EvaHatchRim", 0.66, 0.06, Vector3(X(0), 1.0, c.y - 0.04), Color(0.22, 0.22, 0.20), "z")
	_cyl("EvaWheel", 0.2, 0.05, Vector3(X(0), 1.0, c.y - 0.14), Color(0.5, 0.46, 0.34), "z")
	_deco("EvaWheelBarA", Vector3(0.46, 0.04, 0.04), Vector3(X(0), 1.0, c.y - 0.17), Color(0.5, 0.46, 0.34))
	_deco("EvaWheelBarB", Vector3(0.04, 0.46, 0.04), Vector3(X(0), 1.0, c.y - 0.17), Color(0.5, 0.46, 0.34))
	_deco("EvaLamp", Vector3(0.1, 0.1, 0.03), Vector3(X(0.9), 1.7, c.y - 0.05), Color(0.2, 0.9, 0.3)).get_child(0).set("material_override", _emit(Color(0.2, 0.9, 0.3), 1.6))
	_label("ВЫХОД В КОСМОС", Vector3(X(0), 1.85, c.y - 0.03), 180.0, 0.07, Color(0.6, 0.55, 0.3))
	_label("ДАВЛЕНИЕ", Vector3(X(0.9), 1.6, c.y - 0.03), 180.0, 0.04, Color(0.45, 0.55, 0.5))


func _mount_airlock_equipment(start_z: float) -> void:
	var kit := AIRLOCK_EQUIPMENT.instantiate() as Node3D
	kit.name = "AirlockEquipment"
	add_child(kit)
	# The .blend shows the four mounts side by side; in the ship the lockers
	# still face the bench across the aisle.
	for entry in [["SuitMount", -1.0, 2.3], ["BenchMount", -1.0, 1.2],
			["HooksMount", -1.0, 0.725], ["LockersMount", 1.0, 1.0]]:
		var anchor := kit.find_child(entry[0], true, false) as Node3D
		var side: float = entry[1]
		anchor.position = Vector3(side * WIDTH * 0.5, 0.0, start_z + float(entry[2]))
		anchor.rotation_degrees.y = -side * 90.0
	for child in kit.find_children("*", "MeshInstance3D", true, false):
		var visual := child as MeshInstance3D
		for surface in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST


# ------------------------------------------------------------------- light --

# ------------------------------------------------------------- tripo models --
# Hero props generated in Tripo3D (assetss/tripo/*.glb, origin at the bottom centre,
# front towards +Z). They replace the grey placeholder boxes visually; the old boxes
# keep their collision.

const TRIPO := "res://assetss/tripo/"
const REACTOR_STARTER_MODEL := preload("res://assetss/blender/reactor_starter/reactor_starter.glb")
const REACTOR_BREAKER_MODEL := preload("res://assetss/blender/reactor_wiring/reactor_wiring.glb")
const REACTOR_WIRING := preload("res://scripts/reactor_wiring.gd")
const REACTOR_CONTROL_LAYER := 2

var _oxygen_unit: Node3D
var _oxygen_base := Vector3.ZERO
var _rotor_pivot: Node3D
var _rotor_speed := 0.0


func _animate_oxygen(delta: float) -> void:
	# The oxygen generator: the rotor spins up when the ship has power, the cabinet
	# trembles with it. Repairs will later drive the target speed and stalling.
	if _rotor_pivot == null:
		return
	var target := 8.0 if powered else 0.0
	_rotor_speed = lerpf(_rotor_speed, target, clampf(delta * 0.8, 0.0, 1.0))
	_rotor_pivot.rotate_object_local(Vector3.BACK, _rotor_speed * delta)
	if _oxygen_unit != null:
		var shake := 0.0025 * clampf(_rotor_speed / 8.0, 0.0, 1.0)
		_oxygen_unit.position = _oxygen_base + Vector3(sin(Time.get_ticks_msec() * 0.09) * shake, 0.0,
			cos(Time.get_ticks_msec() * 0.11) * shake)


func _place_model(file: String, label: String, factor: float, pos: Vector3, yaw: float) -> Node3D:
	var packed := load(TRIPO + file) as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	node.name = label
	node.scale = Vector3.ONE * factor
	node.position = pos
	node.rotation_degrees.y = yaw
	add_child(node)
	return node


func _solid_box(label: String, size: Vector3, pos: Vector3) -> void:
	# Invisible collision box for a Tripo model (the model itself has no collision).
	var body := StaticBody3D.new()
	body.name = label
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


func _hide_mesh(label: String) -> void:
	var node := get_node_or_null(label)
	if node == null:
		return
	for found in node.find_children("*", "MeshInstance3D", true, false):
		(found as MeshInstance3D).visible = false


func _build_tripo_props() -> void:
	var c0: Vector2 = compartment_ranges["Cockpit"]
	# Pilot seats (face the window, the left one turned as if its pilot just left).
	for side in ["L", "R"]:
		var x := -0.95 if side == "L" else 0.95
		for part in ["", "_Back", "_Head", "_Belt"]:
			_hide_mesh("PilotSeat" + side + part)
		_place_model("shuttle_pilot_seat.glb", "TripoPilotSeat" + side, 1.1,
			Vector3(x, 0.0, c0.x + 1.9), 180.0 + (-14.0 if side == "L" else 0.0))
	# Two CRT console units on the navigation desk instead of the flat dash.
	for part in ["DashSlope", "DashScreen0", "DashScreen1", "DashScreen2"]:
		_hide_mesh(part)
	for index in 9:
		_hide_mesh("Switch%d" % index)
	for x in [-1.1, 1.1]:
		_place_model("shuttle_crt_console.glb", "TripoConsole%d" % (0 if x < 0 else 1), 0.62,
			Vector3(x, 0.9, c0.x + 0.55), 0.0)
	# The field radio on the radio operator's desk.
	var c1: Vector2 = compartment_ranges["CrewBay"]
	for part in ["RadioSet", "RadioScreen", "Headset", "RadioKnob0", "RadioKnob1", "RadioKnob2", "RadioKnob3"]:
		_hide_mesh(part)
	_place_model("shuttle_radio.glb", "TripoRadio", 0.5, Vector3(X(1.4), 0.95, c1.x + 1.4), -90.0)
	# Crew bay: a real locker instead of the grey box (stretched to 1.9 m tall).
	for part in ["CrewLocker", "LockerDoor"]:
		_hide_mesh(part)
	var locker := _place_model("shuttle_crew_locker.glb", "TripoLocker", 1.0,
		Vector3(X(-1.5), 0.0, c1.x + 3.2), 90.0)
	if locker != null:
		locker.scale = Vector3(0.97, 1.94, 0.99)
	# Galley: the sleep capsule with its open lid and a chest of drawers.
	var c2: Vector2 = compartment_ranges["Galley"]
	for part in ["CapsuleLid", "Mattress", "Blanket", "Pillow", "SleepCapsule"]:
		_hide_mesh(part)
	_place_model("shuttle_sleep_capsule.glb", "TripoCapsule", 1.6, Vector3(-1.55, 0.0, c2.x + 1.5), 0.0)
	_place_model("shuttle_dresser.glb", "TripoDresser", 1.0, Vector3(X(-1.5), 0.0, c2.x + 3.7), 90.0)
	_solid_box("TripoDresserBody", Vector3(0.85, 1.0, 0.8), Vector3(X(-1.5), 0.5, c2.x + 3.7))
	# Galley: the real kitchen unit on the right wall replaces the counter and its clutter.
	for part in ["GalleyCounter", "Sink", "Tap", "Cup0", "Cup1", "FoodPack1", "FoodPack2", "WetCup", "WetRing"]:
		_hide_mesh(part)
	var galley_unit := _place_model("shuttle_galley_unit.glb", "TripoGalleyUnit", 1.0,
		Vector3(WIDTH * 0.5 - 0.28, 0.0, c2.x + 1.4), -90.0)
	if galley_unit != null:
		galley_unit.scale = Vector3(1.9, 1.9, 1.1)
	# The grey food locker with its floating half-open door becomes the same real locker as in the
	# crew bay, standing against the right wall facing the aisle (the old body stays as collider).
	for part in ["FoodLocker", "FoodLockerDoor"]:
		_hide_mesh(part)
	var food_locker := _place_model("shuttle_crew_locker.glb", "TripoFoodLocker", 1.0,
		Vector3(WIDTH * 0.5 - 0.3, 0.0, c2.x + 2.75), -90.0)
	if food_locker != null:
		food_locker.scale = Vector3(0.97, 1.75, 0.99)
	# Cargo: stacked crates and a loaded shelf rack on the left, instead of the grey boxes.
	var cg: Vector2 = compartment_ranges["Cargo"]
	for part in ["CargoCrateA", "CargoCrateB", "CargoCrateC", "CargoCrateD"]:
		_hide_mesh(part)
	_place_model("shuttle_cargo_crates.glb", "TripoCrates", 1.5, Vector3(-1.75, 0.0, cg.x + 1.1), 90.0)
	var shelf := _place_model("shuttle_shelf_rack.glb", "TripoShelf", 1.0, Vector3(-WIDTH * 0.5 + 0.3, 0.0, cg.x + 3.1), 90.0)
	if shelf != null:
		shelf.scale = Vector3(1.9, 2.04, 1.8)
	# Medbay: the glass-front medical cabinet hangs on the wall; its old box keeps a small collider.
	var cm2: Vector2 = compartment_ranges["Medbay"]
	for part in ["MedCabinet", "MedCross", "MedCrossH"]:
		_hide_mesh(part)
	var med_body := get_node_or_null("MedCabinet") as StaticBody3D
	if med_body != null:
		for child in med_body.get_children():
			if child is CollisionShape3D:
				var box := (child as CollisionShape3D).shape as BoxShape3D
				if box != null:
					box.size = Vector3(0.35, 1.0, 1.0)
					(child as CollisionShape3D).position = Vector3(WIDTH * -0.5 + 0.2 - med_body.position.x, 1.55 - med_body.position.y, 0.0)
	_place_model("shuttle_med_cabinet.glb", "TripoMedCabinet", 1.0, Vector3(-WIDTH * 0.5 + 0.24, 1.0, cm2.x + 1.2), 90.0)
	# Medbay: a real exam table instead of the grey slab (its old body stays as the collider).
	for part in ["ExamTable", "ExamTableLeg", "ExamMat", "ExamSheet", "SurgeryLamp", "SurgeryLampArm"]:
		_hide_mesh(part)
	var exam := _place_model("shuttle_exam_table.glb", "TripoExamTable", 1.0, Vector3(-1.1, 0.0, cm2.x + 2.0), 0.0)
	if exam != null:
		exam.scale = Vector3(1.4, 1.75, 2.04)
	# Reactor: the Tripo unit (round core hatch, gauges, pipes) replaces the grey block with
	# its floating orange strip; it faces the aisle from the right wall.
	for part in ["ReactorBlock", "ReactorCore", "ReactorGlow"]:
		_hide_mesh(part)
	var old_reactor := get_node_or_null("ReactorBlock")
	if old_reactor != null:
		old_reactor.queue_free()
	var rc: Vector2 = compartment_ranges["Reactor"]
	var reactor_scale := 2.2   # ~2.15 m tall, ~1.95 m wide: a real machine, not a lone box
	var reactor_x := WIDTH * 0.5 - 0.874 * reactor_scale * 0.5 - 0.2   # a hand clear of the wall
	var reactor := _place_model("shuttle_reactor.glb", "TripoReactor", reactor_scale,
		Vector3(reactor_x, 0.0, rc.x + 2.1), -90.0)
	_solid_box("TripoReactorBody", Vector3(1.85, 2.1, 1.9), Vector3(reactor_x, 1.05, rc.x + 2.1))
	if reactor != null:
		_mount_reactor_starter(reactor, reactor_scale)
	# Airlock: the EVA hatch from the reference art (octagonal hazard frame, wheel, lamps)
	# replaces the old cylinder/wheel primitives; the old solid body stays as its collider.
	var ca: Vector2 = compartment_ranges["Airlock"]
	for part in ["EvaHatch", "EvaHatchRim", "EvaWheel", "EvaWheelBarA", "EvaWheelBarB", "EvaLamp"]:
		_hide_mesh(part)
	var eva_hatch := _place_model("shuttle_eva_hatch.glb", "TripoEvaHatch", 1.7,
		Vector3(X(0), 0.42, ca.y - 0.13), 180.0)
	if eva_hatch != null:
		eva_hatch.scale = Vector3(1.7, 1.7, 0.5)
	# Keep the interaction body separate from the visible cabinet and its hinge.
	_breaker_wiring = REACTOR_WIRING.new()
	_breaker_wiring.name = "ReactorBreakerCabinet"
	_breaker_wiring.position = Vector3(-WIDTH * 0.5, 0.81, rc.x + 0.45)
	_breaker_wiring.rotation_degrees.y = 90.0
	_breaker_wiring.add_child(REACTOR_BREAKER_MODEL.instantiate())
	_breaker_wiring.focus_changed.connect(_on_breaker_focus_changed)
	_breaker_wiring.terminal_connected.connect(_play_one.bind("switch.ogg", -16.0))
	_breaker_wiring.repaired.connect(_set_breaker_power.bind(true))
	add_child(_breaker_wiring)
	for child in _breaker_wiring.find_children("*", "MeshInstance3D", true, false):
		var visual := child as MeshInstance3D
		for surface in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# Reactor: the oxygen generator on the left wall with a spinning rotor in its hatch.
	var c3: Vector2 = compartment_ranges["Reactor"]
	for part in ["OxygenUnit", "OxygenGaugeA", "OxygenGaugeB", "OxygenValve"]:
		_hide_mesh(part)
	# The grey pipe cabinet box becomes the same green locker as in the crew bay (old body = collider).
	_hide_mesh("PipeCabinet")
	var pipe_locker := _place_model("shuttle_crew_locker.glb", "TripoPipeLocker", 1.0,
		Vector3(X(-1.5), 0.0, c3.x + 2.6), 90.0)
	if pipe_locker != null:
		pipe_locker.scale = Vector3(0.97, 1.94, 0.99)
	# The generator is its own scene (scenes/oxygen_generator.tscn): open it in the editor and move
	# the RotorPivot / FanRotor nodes in the 3D view to seat the fan; the game just spins the pivot.
	var generator_scene := load("res://scenes/oxygen_generator.tscn") as PackedScene
	if generator_scene != null:
		_oxygen_unit = generator_scene.instantiate() as Node3D
		_oxygen_unit.name = "TripoOxygenGenerator"
		_oxygen_unit.scale = Vector3.ONE * 1.7
		_oxygen_unit.position = Vector3(-WIDTH * 0.5 + 0.85, 0.0, c3.x + 1.55)
		_oxygen_unit.rotation_degrees.y = 90.0
		add_child(_oxygen_unit)
		_oxygen_base = _oxygen_unit.position
		# Spin the fan about ITS OWN centre and axis, wherever it was placed in the scene (a fan that
		# sits off the pivot axis would otherwise orbit it and drift sideways).
		var pivot_node := _oxygen_unit.get_node("RotorPivot") as Node3D
		var fan := pivot_node.get_node("FanRotor") as Node3D
		var old_transform := fan.transform
		var fan_centre := old_transform * Vector3(0.0, 0.4886, 0.0)   # the model origin is bottom-centre
		var spin := Node3D.new()
		spin.name = "FanSpin"
		spin.transform = Transform3D(old_transform.basis.orthonormalized(), fan_centre)
		pivot_node.add_child(spin)
		pivot_node.remove_child(fan)
		spin.add_child(fan)
		fan.transform = spin.transform.affine_inverse() * old_transform
		_rotor_pivot = spin


func _mount_reactor_starter(reactor: Node3D, reactor_scale: float) -> void:
	var starter := REACTOR_STARTER_MODEL.instantiate() as Node3D
	starter.name = "ReactorStarter"
	starter.position = Vector3(-0.615, 1.133, 0.666) / reactor_scale
	starter.scale = Vector3.ONE / reactor_scale
	reactor.add_child(starter)
	_reactor_needle = starter.find_child("StarterNeedle", true, false) as Node3D
	_reactor_zone = starter.find_child("StarterZone", true, false) as Node3D
	_set_reactor_dial(REACTOR_STARTUP.START_LEVEL, REACTOR_STARTUP.REST_ZONE_CENTER)
	for child in starter.find_children("*", "MeshInstance3D", true, false):
		var visual := child as MeshInstance3D
		for surface in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	# Aiming sees the panel just ahead of the reactor's coarse hull collider.
	# It is on a ray-only layer so the equipment does not narrow the aisle.
	_reactor_control = StaticBody3D.new()
	_reactor_control.name = "ReactorStarterControl"
	_reactor_control.collision_layer = 0
	_reactor_control.set_collision_layer_value(REACTOR_CONTROL_LAYER, true)
	_reactor_control.collision_mask = 0
	_reactor_control.position = Vector3(0.0, 0.153, 0.231)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.347, 0.321, 0.142)
	collider.shape = box
	_reactor_control.add_child(collider)
	starter.add_child(_reactor_control)


# ------------------------------------------------------------------ traces --
# Small signs of people (docs/SHUTTLE_LEVEL_DESIGN.md §3): the ship was built for
# four, one is aboard, and the rest left in a hurry. Boxes and labels for now;
# real props from Tripo replace the boxes later.

func _build_traces() -> void:
	var tape := Color(0.14, 0.14, 0.13)
	var c0: Vector2 = compartment_ranges["Cockpit"]
	_label("ЭХО 1/4", Vector3(0, 0.62, c0.x + 0.84), 0.0, 0.06, Color(0.55, 0.5, 0.3))

	# Crew bay: nameplates on the three fold-down seats, two taped over, a calendar.
	var c1: Vector2 = compartment_ranges["CrewBay"]
	for index in 3:
		var z := c1.x + 0.8 + index * 0.9
		var x := X(-1.7) + 0.07
		_deco("NamePlate%d" % index, Vector3(0.02, 0.1, 0.34), Vector3(x, 0.95, z), Color(0.5, 0.48, 0.4))
		if index == 1:
			_label("ВЕТРОВ А.", Vector3(x + 0.015, 0.95, z), 90.0, 0.045, Color(0.12, 0.12, 0.1))
		else:
			_deco("NameTape%d" % index, Vector3(0.025, 0.12, 0.4), Vector3(x + 0.004, 0.95, z), tape, Vector3(0, 0, 4))
	_deco("Calendar", Vector3(0.02, 0.4, 0.3), Vector3(X(1.76), 1.5, c1.x + 3.4), C_PAPER)
	for day in 12:
		_deco("CalendarCross%d" % day, Vector3(0.025, 0.012, 0.03),
			Vector3(X(1.75), 1.62 - (day / 4) * 0.08, c1.x + 3.29 + (day % 4) * 0.07), Color(0.5, 0.1, 0.08))

	# Galley: the second cup on the drying rack is still wet.
	var c2: Vector2 = compartment_ranges["Galley"]
	_cyl("WetCup", 0.04, 0.09, Vector3(X(1.4), 1.0, c2.x + 1.38), Color(0.4, 0.4, 0.38))
	_deco("WetRing", Vector3(0.16, 0.003, 0.16), Vector3(X(1.4), 0.953, c2.x + 1.38), Color(0.06, 0.07, 0.08))
	_deco("SlippersL", Vector3(0.12, 0.05, 0.28), Vector3(-0.6, 0.025, c2.x + 2.6), Color(0.35, 0.28, 0.2), Vector3(0, 20, 0))
	_deco("SlippersR", Vector3(0.12, 0.05, 0.28), Vector3(-0.4, 0.025, c2.x + 2.7), Color(0.35, 0.28, 0.2), Vector3(0, 8, 0))

	# Medbay: a bloodstained cloth on the counter.
	var cm: Vector2 = compartment_ranges["Medbay"]
	_deco("BloodCloth", Vector3(0.14, 0.01, 0.2), Vector3(X(1.4), 0.965, cm.x + 3.4), Color(0.33, 0.2, 0.2), Vector3(0, 40, 0))

	# Reactor: an oil puddle under the breaker cabinet. The old red "do not switch on"
	# tag is gone: the real cabinet carries its own stencils.
	var c3: Vector2 = compartment_ranges["Reactor"]
	_deco("OilPuddle", Vector3(0.7, 0.003, 0.5), Vector3(0.1, 0.004, c3.x + 3.5), Color(0.03, 0.03, 0.03), Vector3(0, 25, 0))

	# Airlock: note about the seal beside the modeled equipment.
	var c4: Vector2 = compartment_ranges["Airlock"]
	_deco("SealNote", Vector3(0.012, 0.22, 0.16), Vector3(X(1.76), 1.35, c4.x + 3.0), C_PAPER, Vector3(2, 0, 5))
	_label("ПРОВЕРИТЬ УПЛОТНЕНИЕ", Vector3(X(1.75), 1.35, c4.x + 3.0), -90.0, 0.03, Color(0.15, 0.15, 0.12))


# ------------------------------------------------------------- interaction --
# First gameplay hooks, all placeholders from docs/SHUTTLE_LEVEL_DESIGN.md. Real
# repairs, radio packets and the sleep sequence will replace these texts.

const INTERACTABLE_SCRIPT := preload("res://scripts/shuttle_interactable.gd")
const REACTOR_STARTUP := preload("res://scripts/shuttle_reactor_startup.gd")
const HUD_FONT := preload("res://assetss/ui/fonts/CascadiaMono.ttf")
# node name -> [action id, prompt]
const INTERACTABLES := {
	"BreakerPanel": ["breaker", "[E] Щит автоматов"],
	"NavConsole": ["nav", "[E] Навигация"],
	"RadioDesk": ["radio", "[E] Радиоприёмник"],
	"SleepCapsule": ["capsule", "[E] Капсула сна"],
	"JumpSeat1": ["nameplate", "[E] Табличка"],
	"ExamTable": ["exam", "[E] Кушетка"],
	"MedCabinet": ["meds", "[E] Аптечка"],
	"OxygenUnit": ["oxygen", "[E] Кислородный узел"],
	"EvaHatch": ["hatch", "[E] Люк"],
}

var _hud_message: Label
var _hud_prompt: Label
var _hud_objective: Label
var _flashlight_hint: Label
var _message_timer := 0.0
var _player: Node
var _reactor_panel: REACTOR_STARTUP
var _reactor_operator: Player
var _reactor_control: StaticBody3D
var _reactor_needle: Node3D
var _reactor_zone: Node3D
var _reactor_ready := false
var _power_task_seen := false
var _breaker_wiring: REACTOR_WIRING


func _build_interactions() -> void:
	var c: Vector2 = compartment_ranges["Reactor"]
	# A dedicated breaker panel on the reactor wall by the hatch.
	_box("BreakerPanel", Vector3(0.24, 0.88, 0.69), Vector3(-WIDTH * 0.5 + 0.12, 1.25, c.x + 0.45), Color(0.18, 0.2, 0.19))
	_hide_mesh("BreakerPanel")
	for label in INTERACTABLES:
		var body := get_node_or_null(label) as StaticBody3D
		if body != null:
			_bind_interactable(body, INTERACTABLES[label][0], INTERACTABLES[label][1])
	if _reactor_control != null:
		_bind_interactable(_reactor_control, "reactor", "[E] Ручной пуск реактора")
		var player := get_node_or_null("Player") as Player
		if player != null:
			player.interaction_ray.set_collision_mask_value(REACTOR_CONTROL_LAYER, true)
	_build_hud()


func _bind_interactable(body: StaticBody3D, action: String, prompt: String) -> void:
	body.set_script(INTERACTABLE_SCRIPT)
	body.set("action_id", action)
	body.set("prompt", prompt)
	body.set("hub", self)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	# Above PostFX (layer 100) so the pixel filter does not smear the text.
	layer.layer = 110
	_hud_message = Label.new()
	_hud_message.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hud_message.offset_left = -520.0
	_hud_message.offset_right = 520.0
	_hud_message.offset_top = -190.0
	_hud_message.offset_bottom = -110.0
	_hud_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_message.add_theme_font_size_override("font_size", 26)
	_hud_message.add_theme_color_override("font_color", Color(0.85, 0.96, 0.88))
	_hud_message.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud_message.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hud_message)
	_hud_prompt = Label.new()
	_hud_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_hud_prompt.offset_left = -300.0
	_hud_prompt.offset_right = 300.0
	_hud_prompt.offset_top = 40.0
	_hud_prompt.offset_bottom = 80.0
	_hud_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_prompt.add_theme_font_size_override("font_size", 22)
	_hud_prompt.add_theme_color_override("font_color", Color(0.8, 0.85, 0.75))
	_hud_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud_prompt.add_theme_constant_override("outline_size", 5)
	layer.add_child(_hud_prompt)
	_hud_objective = _make_corner_hint("PowerObjective", "Найдите включатель", false)
	layer.add_child(_hud_objective)
	_flashlight_hint = _make_corner_hint("FlashlightHint", "Нажмите F чтобы включить фонарик", true)
	layer.add_child(_flashlight_hint)
	_reactor_panel = REACTOR_STARTUP.new()
	_reactor_panel.name = "ReactorStartup"
	_reactor_panel.stabilized.connect(_on_reactor_stabilized)
	_reactor_panel.dial_changed.connect(_set_reactor_dial)
	layer.add_child(_reactor_panel)
	add_child(layer)
	_player = get_node_or_null("Player")
	var hint_tween := create_tween()
	hint_tween.tween_interval(5.0)
	hint_tween.tween_property(_flashlight_hint, "modulate:a", 0.0, 0.65) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	hint_tween.tween_callback(_flashlight_hint.hide)


func _make_corner_hint(node_name: String, text: String, bottom: bool) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT if bottom else Control.PRESET_TOP_LEFT)
	label.offset_left = 40.0
	label.offset_right = 660.0
	label.offset_top = -76.0 if bottom else 35.0
	label.offset_bottom = -37.0 if bottom else 74.0
	label.add_theme_font_override("font", HUD_FONT)
	label.add_theme_font_size_override("font_size", 22 if bottom else 24)
	label.add_theme_color_override("font_color", Color(0.82, 0.88, 0.84))
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	label.add_theme_constant_override("outline_size", 4)
	return label


func show_message(text: String, seconds := 5.0) -> void:
	if _hud_message == null:
		return
	_hud_message.text = text
	_message_timer = seconds


func on_interact(action: String, operator: CharacterBody3D = null) -> void:
	if action != "breaker" and powered:
		_play_one("switch.ogg", -14.0)
	match action:
		"breaker":
			if _breaker_wiring.is_focused():
				_breaker_wiring.finish()
				return
			_power_task_seen = true
			if not powered and not _reactor_ready:
				_sync_power_hud()
				show_message("ЩИТ БЕЗ ПИТАНИЯ. СНАЧАЛА ЗАПУСТИТЕ РЕАКТОР НАПРОТИВ КИСЛОРОДНОГО УЗЛА.")
				return
			if powered or _breaker_wiring.is_repaired():
				_set_breaker_power(not powered)
			else:
				_breaker_wiring.begin(operator as Player)
		"reactor":
			_interact_reactor(operator as Player)
		"nav":
			show_message("КУРС: ПОДТВ. // ЗЕМЛЯ — 4.2 СВ.МИН // ПОСЛЕДНЯЯ КОРРЕКЦИЯ: АВТО." if powered
				else "КОНСОЛЬ ОБЕСТОЧЕНА. ЭКРАНЫ ТЁМНЫЕ.")
		"radio":
			show_message("ПРИЁМНИК: ЭФИР ПУСТ. 145.80 МГц — ШУМ." if powered
				else "ПРИЁМНИК НЕ ПОЛУЧАЕТ ПИТАНИЯ.")
		"capsule":
			show_message("КАПСУЛА СНА. РЕМНИ ПОТЁРТЫ. ТАЙМЕР НЕ ЗАДАН.")
		"nameplate":
			show_message("ТАБЛИЧКА: «ВЕТРОВ А. — КОМАНДИР ЭКИПАЖА». НА СОСЕДНИХ КРЕСЛАХ ФАМИЛИИ ЗАКЛЕЕНЫ ИЗОЛЕНТОЙ.", 7.0)
		"exam":
			show_message("ПРОСТЫНЯ ВМЯТА. КТО-ТО ЗДЕСЬ ЛЕЖАЛ.")
		"meds":
			show_message("АПТЕЧКА. НЕ ХВАТАЕТ ОБЕЗБОЛИВАЮЩЕГО И БИНТА.")
		"oxygen":
			show_message("КИСЛОРОД: ДАВЛЕНИЕ В НОРМЕ. ФИЛЬТР — 14%." if powered
				else "КИСЛОРОДНЫЙ УЗЕЛ: ИНДИКАТОРЫ ПОГАШЕНЫ.")
		"hatch":
			show_message("ЛЮК: ВЫХОД НЕ РАЗРЕШЁН. ПАНЕЛЬ №2 ТРЕБУЕТ РЕМОНТА." if powered
				else "ЛЮК ЗАБЛОКИРОВАН. НЕТ ПИТАНИЯ.")


func _on_breaker_focus_changed() -> void:
	_hud_prompt.text = ""
	var focused := _breaker_wiring.is_focused()
	if focused:
		_hud_message.text = ""
	# The PSX effect stays present, but the tiny stamped symbols must read.
	_psx_material.set_shader_parameter("pixel_size", 2.0 if focused else 4.0)
	_psx_material.set_shader_parameter("dither", 0.45 if focused else 0.8)
	_psx_material.set_shader_parameter("grain", 0.023 if focused else 0.035)
	_sync_power_hud()


func _set_breaker_power(value: bool) -> void:
	set_powered(value)
	_play_one("breaker.ogg", -6.0)
	if value:
		_play_one("powerup.ogg", -12.0)
	show_message("ЩИТ: АВТОМАТЫ ВКЛЮЧЕНЫ. БОРТОВАЯ СЕТЬ — ПИТАНИЕ ЕСТЬ." if value
		else "ЩИТ: АВТОМАТЫ ОТКЛЮЧЕНЫ. СЕТЬ БЕЗ ПИТАНИЯ.")


func _interact_reactor(operator: Player) -> void:
	if _reactor_operator != null:
		_exit_reactor_startup()
	elif _reactor_ready or powered:
		show_message("РЕАКТОР НА РАБОЧЕМ РЕЖИМЕ." if powered else "РЕАКТОР ГОТОВ. ПОДАЙТЕ ПИТАНИЕ НА ЩИТЕ.")
	elif operator != null:
		_power_task_seen = true
		_reactor_operator = operator
		operator.is_interacting = true
		_hud_message.text = ""
		_hud_prompt.text = ""
		_reactor_panel.begin()
		_sync_power_hud()


func reactor_focus_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _reactor_operator != null and key != null and (key.physical_keycode == KEY_ESCAPE or key.keycode == KEY_ESCAPE):
		_exit_reactor_startup()


func _exit_reactor_startup() -> void:
	_reactor_panel.cancel()
	if is_instance_valid(_reactor_operator):
		_reactor_operator.is_interacting = false
		_reactor_operator.interacting_object = null
	_reactor_operator = null
	if not _reactor_ready:
		_set_reactor_dial(REACTOR_STARTUP.START_LEVEL, REACTOR_STARTUP.REST_ZONE_CENTER)
	_sync_power_hud()


func _on_reactor_stabilized() -> void:
	_reactor_ready = true
	_exit_reactor_startup()
	_play_one("switch.ogg", -12.0)
	show_message("РЕАКТОР ГОТОВ. ПОДАЙТЕ ПИТАНИЕ НА ЩИТЕ.")


func _set_reactor_dial(needle: float, band: float) -> void:
	if _reactor_needle != null:
		_reactor_needle.rotation.z = deg_to_rad(lerpf(110.0, -110.0, needle))
	if _reactor_zone != null:
		_reactor_zone.rotation.z = deg_to_rad(lerpf(110.0, -110.0, band))


func _sync_power_hud() -> void:
	_hud_objective.visible = not powered and _reactor_operator == null and not _breaker_wiring.is_focused()
	if _reactor_ready:
		_hud_objective.text = "Подайте питание на щите"
	elif _power_task_seen:
		_hud_objective.text = "Запустите реактор"
	var breaker := get_node_or_null("BreakerPanel")
	if breaker != null:
		var prompt := "[E] Щит автоматов"
		if powered:
			prompt = "[E] Отключить питание"
		elif _breaker_wiring.is_repaired():
			prompt = "[E] Подать питание"
		elif _reactor_ready:
			prompt = "[E] Восстановить цепь"
		breaker.set("prompt", prompt)
	if _reactor_control != null:
		_reactor_control.set("prompt", "[E] Реактор" if _reactor_ready or powered else "[E] Ручной пуск реактора")


func _update_prompt(delta: float) -> void:
	if _hud_message != null and _message_timer > 0.0:
		_message_timer -= delta
		if _message_timer <= 0.0:
			_hud_message.text = ""
	if _hud_prompt == null or _player == null or _reactor_operator != null or _breaker_wiring.is_focused():
		return
	var ray := _player.get_node_or_null("Head/Camera3D/RayCast3D") as RayCast3D
	var text := ""
	if ray != null and ray.is_colliding():
		var target := ray.get_collider() as Interactable
		if target != null:
			text = String(target.get("prompt")) if target.get("prompt") != null else "[E]"
	_hud_prompt.text = text


# ----------------------------------------------------------------- ambience --
# All sounds are free CC0 / CC-BY recordings from OpenGameArt (see
# assetss/audio/shuttle/CREDITS.md). Every compartment has its own looping room tone
# plus random quiet events (creaks, drips, relay clicks, clanks); footsteps follow
# the player and the hatches thud softly when crossed.

const SND := "res://assetss/audio/shuttle/"
# compartment -> [file, volume_db, pitch]
const LOOPS := {
	"Cockpit": ["hum_cockpit.mp3", -20.0, 1.3],
	"CrewBay": ["loop_crew.ogg", -14.0, 1.0],
	"Galley": ["loop_galley.ogg", -27.0, 0.9],
	"Medbay": ["loop_med.ogg", -16.0, 1.1],
	"Cargo": ["loop_cargo.ogg", -22.0, 0.85],
	"Reactor": ["loop_reactor.ogg", -6.0, 0.8],
	"Airlock": ["loop_airlock.ogg", -20.0, 0.9],
}
# compartment -> list of [sound group, min seconds, max seconds, volume_db]
const EVENTS := {
	"Cockpit": [["relay", 7.0, 18.0, -16.0], ["creak", 25.0, 50.0, -22.0]],
	"CrewBay": [["creak", 20.0, 40.0, -20.0], ["relay", 15.0, 35.0, -22.0]],
	"Galley": [["drip", 4.0, 9.0, -18.0], ["creak", 30.0, 60.0, -24.0]],
	"Medbay": [["drip", 8.0, 16.0, -20.0], ["relay", 12.0, 30.0, -20.0], ["air", 20.0, 40.0, -22.0]],
	"Cargo": [["clank", 14.0, 40.0, -18.0], ["creak", 18.0, 35.0, -20.0]],
	"Reactor": [["clank", 18.0, 45.0, -16.0], ["air", 12.0, 26.0, -18.0]],
	"Airlock": [["creak", 15.0, 35.0, -18.0], ["drip", 14.0, 30.0, -22.0]],
}
const GROUPS := {
	"step": ["step_01.wav", "step_02.wav", "step_03.wav", "step_04.wav", "step_05.wav",
		"step_06.wav", "step_07.wav", "step_08.wav", "step_09.wav", "step_10.wav"],
	"creak": ["creak_01.ogg", "creak_02.ogg", "creak_03.ogg", "creak_04.ogg", "creak_05.ogg", "creak_06.ogg"],
	"drip": ["drip_01.ogg", "drip_02.ogg"],
	"relay": ["relay_01.ogg", "relay_02.ogg", "relay_03.ogg"],
	"clank": ["clank_01.ogg", "clank_02.ogg", "clank_03.ogg"],
	"air": ["air_01.ogg", "air_02.ogg"],
}
const POWERED_ROOM_EVENTS := ["relay", "air"]

var _stream_cache: Dictionary = {}
var _room_loops: Array[AudioStreamPlayer3D] = []
var _event_state: Array = []
var _event_players: Dictionary = {}
var _active_room_events: Dictionary = {}
var _step_player: AudioStreamPlayer
var _step_timer := 0.0
var _last_player_z := 0.0
var _rng := RandomNumberGenerator.new()


func _stream(file: String, loop := false) -> AudioStream:
	var key := "%s|%s" % [file, loop]
	if _stream_cache.has(key):
		return _stream_cache[key]
	var stream: AudioStream = load(SND + file)
	if stream != null and loop:
		stream = stream.duplicate()
		if "loop" in stream:
			stream.set("loop", true)
	_stream_cache[key] = stream
	return stream


func _build_ambience() -> void:
	_rng.randomize()
	# A touch of reverb on the master bus: the ship is a metal tube.
	if AudioServer.get_bus_effect_count(0) == 0:
		var reverb := AudioEffectReverb.new()
		reverb.room_size = 0.35
		reverb.damping = 0.6
		reverb.wet = 0.12
		reverb.dry = 0.95
		AudioServer.add_bus_effect(0, reverb)
	for label in compartment_ranges:
		var span: Vector2 = compartment_ranges[label]
		var centre := Vector3(0, 1.4, (span.x + span.y) * 0.5)
		var loop_info: Array = LOOPS.get(label, [])
		if not loop_info.is_empty():
			var loop_player := AudioStreamPlayer3D.new()
			loop_player.name = label + "_Loop"
			loop_player.stream = _stream(loop_info[0], true)
			loop_player.volume_db = loop_info[1]
			loop_player.pitch_scale = loop_info[2]
			loop_player.unit_size = 3.5
			loop_player.max_distance = 16.0
			loop_player.position = centre
			add_child(loop_player)
			_room_loops.append(loop_player)
		var event_player := AudioStreamPlayer3D.new()
		event_player.name = label + "_Events"
		event_player.unit_size = 3.0
		event_player.max_distance = 18.0
		event_player.position = centre
		add_child(event_player)
		_event_players[label] = event_player
		for entry in EVENTS.get(label, []):
			_event_state.append({
				"compartment": label, "group": entry[0], "min": entry[1],
				"max": entry[2], "volume": entry[3],
				"next": _rng.randf_range(entry[1] * 0.3, entry[2]),
			})
	_step_player = AudioStreamPlayer.new()
	_step_player.name = "Steps"
	_step_player.volume_db = -8.0
	add_child(_step_player)


func _play_group(group: String, player: Node, volume_db: float, pitch_low := 0.9, pitch_high := 1.1) -> void:
	var files: Array = GROUPS.get(group, [])
	if files.is_empty() or player == null:
		return
	player.set("stream", _stream(files[_rng.randi() % files.size()]))
	player.set("volume_db", volume_db)
	player.set("pitch_scale", _rng.randf_range(pitch_low, pitch_high))
	player.call("play")


func _play_one(file: String, volume_db: float, at: Vector3 = Vector3.INF) -> void:
	var stream := _stream(file)
	if stream == null:
		return
	var node: Node
	if at == Vector3.INF:
		var flat := AudioStreamPlayer.new()
		flat.stream = stream
		flat.volume_db = volume_db
		node = flat
	else:
		var spatial := AudioStreamPlayer3D.new()
		spatial.stream = stream
		spatial.volume_db = volume_db
		spatial.unit_size = 3.0
		spatial.position = at
		node = spatial
	add_child(node)
	node.call("play")
	node.connect("finished", node.queue_free)


func _update_audio(delta: float) -> void:
	if _step_player == null:
		return
	# Random room events.
	for state in _event_state:
		if not powered and state.group in POWERED_ROOM_EVENTS:
			continue
		state.next -= delta
		if state.next <= 0.0:
			state.next = _rng.randf_range(state.min, state.max)
			var span: Vector2 = compartment_ranges[state.compartment]
			var player: AudioStreamPlayer3D = _event_players[state.compartment]
			player.position = Vector3(_rng.randf_range(-1.6, 1.6), _rng.randf_range(0.3, 2.0),
				_rng.randf_range(span.x + 0.3, span.y - 0.3))
			_play_group(state.group, player, state.volume)
			_active_room_events[player] = state.group
	# Footsteps and hatch thuds follow the player.
	var body := _player as CharacterBody3D
	if body == null:
		return
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	if body.is_on_floor() and speed > 0.6:
		_step_timer -= delta * (speed / 3.0)
		if _step_timer <= 0.0:
			_step_timer = 0.52
			_play_group("step", _step_player, -9.0, 0.92, 1.05)
	else:
		_step_timer = minf(_step_timer, 0.15)
	var z := body.global_position.z
	for hatch in hatch_z:
		if (_last_player_z - hatch) * (z - hatch) < 0.0:
			_play_one("hatch_pass.ogg", -14.0, Vector3(0, 1.2, hatch))
	_last_player_z = z


# ---------------------------------------------------------------- textures --
# Textures were generated in ChatGPT (see assetss/shuttle_textures/raw), made
# seamless without mirroring and quantised to 5 bits per channel. They are
# applied in world-space triplanar so a box of any size tiles at the same scale.

const TEX_DIR := "res://assetss/shuttle_textures/"
const WALL_TEXTURE := {
	"Cockpit": "wall_quarters", "CrewBay": "wall_quarters", "Galley": "wall_quarters",
	"Medbay": "medbay_tile", "Cargo": "wall_technical", "Reactor": "wall_technical",
	"Airlock": "wall_technical",
}


func _tmat(file: String, tiles_per_meter: float, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "tex|%s|%.2f|%s" % [file, tiles_per_meter, tint.to_html()]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(TEX_DIR + file + ".png")
	material.albedo_color = tint
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * tiles_per_meter
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.95
	_materials[key] = material
	return material


func _apply_textures() -> void:
	for child in get_children():
		var label := String(child.name)
		var material: Material = null
		if label.ends_with("_Floor"):
			material = _tmat("floor_deck", 0.5)
		elif label.ends_with("_Ceiling") or label.ends_with("_Chamfer"):
			material = _tmat("ceiling", 0.4)
		elif label.ends_with("_WallL") or label.ends_with("_WallR"):
			material = _tmat(WALL_TEXTURE.get(label.split("_")[0], "wall_technical"), 0.45)
		elif label.begins_with("Bulkhead_") and (label.ends_with("_L") or label.ends_with("_R") or label.ends_with("_Lintel")):
			material = _tmat("wall_technical", 0.45)
		elif (label.begins_with("NoseWall_") and label != "NoseWall_Glass") or label == "SternWall":
			material = _tmat("wall_quarters", 0.45)
		elif label.begins_with("PilotSeat") or label.begins_with("JumpSeat") or label == "AirlockBench":
			material = _tmat("seat_vinyl", 1.4)
		elif label.begins_with("CargoCrate") or label == "SmallBox" or label == "CargoContainer":
			material = _tmat("crate", 1.0)
		elif label in ["GalleyCounter", "MedCounter", "RadioDesk", "NavConsole", "ExamTable"]:
			material = _tmat("steel_counter", 1.4)
		elif label == "Blanket":
			material = _tmat("blanket", 1.6)
		elif label.begins_with("FloorHazard") or label.ends_with("_Tape") or label.ends_with("_Sill"):
			material = _tmat("hazard", 2.0)
		elif label == "EvaHatch":
			material = _tmat("hatch_door", 0.9)
		if material == null:
			continue
		for found in child.find_children("*", "MeshInstance3D", true, false):
			(found as MeshInstance3D).material_override = material


# Snapshot the authored lighting once so restoring power does not recolor or brighten it.
var _board_lights: Dictionary = {} # Light3D -> [visible, energy, processing]
var _board_glows: Dictionary = {} # local BaseMaterial3D -> [emission enabled, shading mode]
var _normal_ambient_energy: float
var _normal_reflection_source: Environment.ReflectionSource
var _normal_fog_color: Color
var _psx_material: ShaderMaterial
var powered := false


func _setup_power() -> void:
	_normal_ambient_energy = _environment.ambient_light_energy
	_normal_reflection_source = _environment.reflected_light_source
	_normal_fog_color = _environment.fog_light_color
	var player := get_node_or_null("Player")
	for child in find_children("*", "Light3D", true, false):
		var light := child as Light3D
		# The player's flashlight and repair inspection light are independent of board power.
		if not _breaker_wiring.is_ancestor_of(light) and (player == null or not player.is_ancestor_of(light)):
			_board_lights[light] = [light.visible, light.light_energy, light.is_processing()]

	var copies: Dictionary = {}
	var planet_ring := get_node_or_null("WindowPlanetRing")
	for child in find_children("*", "MeshInstance3D", true, false):
		var visual := child as MeshInstance3D
		if visual.mesh == null or visual == planet_ring or _breaker_wiring.is_ancestor_of(visual) \
				or (_planet != null and _planet.is_ancestor_of(visual)):
			continue
		if visual.material_override != null:
			var power_override := _power_material(visual.material_override as BaseMaterial3D, copies)
			if power_override != null:
				visual.material_override = power_override
			continue
		for surface in visual.mesh.get_surface_count():
			var material := _power_material(visual.get_active_material(surface) as BaseMaterial3D, copies)
			if material != null:
				visual.set_surface_override_material(surface, material)
	set_powered(false)


func _power_material(authored: BaseMaterial3D, copies: Dictionary) -> BaseMaterial3D:
	if authored == null or (not authored.emission_enabled and authored.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED):
		return null
	if not copies.has(authored):
		# The imported resource may also be used by another shuttle instance.
		var material := authored.duplicate() as BaseMaterial3D
		copies[authored] = material
		_board_glows[material] = [authored.emission_enabled, authored.shading_mode]
	return copies[authored] as BaseMaterial3D


## The breaker switches instantly. The second argument is kept for existing QA scripts.
func set_powered(value: bool, _seconds := 0.0) -> void:
	powered = value
	_environment.ambient_light_energy = _normal_ambient_energy if value else 0.0
	_environment.reflected_light_source = _normal_reflection_source if value else Environment.REFLECTION_SOURCE_DISABLED
	_environment.fog_light_color = _normal_fog_color if value else Color.BLACK
	_psx_material.set_shader_parameter("protect_black", not value)
	for light: Light3D in _board_lights:
		var authored: Array = _board_lights[light]
		light.visible = value and authored[0]
		light.light_energy = authored[1] if value else 0.0
		light.set_process(value and authored[2])
	for material: BaseMaterial3D in _board_glows:
		var authored: Array = _board_glows[material]
		material.emission_enabled = value and authored[0]
		material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			if not value and authored[1] == BaseMaterial3D.SHADING_MODE_UNSHADED else authored[1]
	for loop_player in _room_loops:
		if value and not loop_player.playing:
			loop_player.play()
		elif not value and loop_player.playing:
			loop_player.stop()
	if not value:
		_rotor_speed = 0.0
		for event_player: AudioStreamPlayer3D in _active_room_events:
			if _active_room_events[event_player] in POWERED_ROOM_EVENTS:
				event_player.stop()
	_sync_power_hud()


func _lamp(label: String, pos: Vector3, color: Color, energy: float, range_m: float,
		flicker := false, dropout := 0.05) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = label
	light.position = pos
	light.omni_range = range_m
	light.light_energy = energy
	light.light_color = color
	add_child(light)
	if flicker:
		var script: Script = load("res://scripts/light_flicker.gd")
		light.set_script(script)
		light.set("flicker_amount", 0.35)
		light.set("dropout_chance", dropout)
	return light


func _lamp_mesh(label: String, pos: Vector3, size: Vector3, color: Color, on := true) -> void:
	_deco(label, size, pos, color).get_child(0).set("material_override",
		_emit(color, 1.4) if on else _mat(Color(0.12, 0.12, 0.12)))


func _build_lights() -> void:
	var top := HEIGHT - 0.03
	# Cockpit: no ceiling light at all, only the cold glow of the dash.
	var c0: Vector2 = compartment_ranges["Cockpit"]
	_lamp_mesh("CockpitLampDead", Vector3(X(0), top, c0.x + 1.6), Vector3(0.7, 0.05, 0.25), Color(0.6, 0.65, 0.7), false)
	_lamp("CockpitDash", Vector3(0, 1.25, c0.x + 0.9), Color(0.3, 0.85, 0.65), 0.55, 3.2)
	# Crew bay: one tired fluorescent tube that drops out now and then.
	var c1: Vector2 = compartment_ranges["CrewBay"]
	_lamp_mesh("CrewLamp", Vector3(X(0), top, (c1.x + c1.y) * 0.5), Vector3(0.9, 0.05, 0.22), Color(0.75, 0.88, 0.95))
	_lamp("CrewTube", Vector3(0, HEIGHT - 0.25, (c1.x + c1.y) * 0.5), Color(0.72, 0.86, 0.95), 0.9, 4.8, true, 0.18)
	# Galley: a small warm lamp by the capsule, the rest is dark.
	var c2: Vector2 = compartment_ranges["Galley"]
	_lamp_mesh("GalleyLampDead", Vector3(X(0), top, c2.x + 0.9), Vector3(0.7, 0.05, 0.25), Color(0.6, 0.6, 0.55), false)
	_lamp("GalleyWarm", Vector3(-0.9, 1.5, c2.x + 1.5), Color(1.0, 0.68, 0.38), 0.5, 3.0)
	# Medbay: a sick green-white tube, flickering.
	var cm: Vector2 = compartment_ranges["Medbay"]
	_lamp_mesh("MedLamp", Vector3(0, top, (cm.x + cm.y) * 0.5), Vector3(0.9, 0.05, 0.22), Color(0.72, 0.95, 0.82))
	_lamp("MedTube", Vector3(0, HEIGHT - 0.3, (cm.x + cm.y) * 0.5), Color(0.7, 0.95, 0.8), 0.7, 4.5, true, 0.12)
	# Cargo: nearly dark, a single yellow work lamp far from the hatch.
	var cg: Vector2 = compartment_ranges["Cargo"]
	_lamp_mesh("CargoLamp", Vector3(X(1.0), top, cg.y - 1.0), Vector3(0.6, 0.05, 0.2), Color(1.0, 0.8, 0.35))
	_lamp("CargoWork", Vector3(1.0, HEIGHT - 0.3, cg.y - 1.0), Color(1.0, 0.78, 0.35), 0.55, 4.0)
	# Reactor: low red emergency light plus the orange glow of the core.
	var c3: Vector2 = compartment_ranges["Reactor"]
	_lamp_mesh("ReactorStripL", Vector3(X(-1.2), top, (c3.x + c3.y) * 0.5), Vector3(0.12, 0.05, 2.4), Color(0.9, 0.12, 0.08))
	_lamp("ReactorRed", Vector3(-0.8, HEIGHT - 0.3, (c3.x + c3.y) * 0.5), Color(1.0, 0.16, 0.1), 0.85, 4.5, true, 0.08)
	_lamp("ReactorGlow", Vector3(0.1, 1.5, c3.x + 1.75), Color(1.0, 0.5, 0.2), 0.35, 2.4)
	# Airlock: dim lamp and the green status light of the hatch.
	var c4: Vector2 = compartment_ranges["Airlock"]
	_lamp_mesh("AirlockLamp", Vector3(X(0), top, c4.x + 1.2), Vector3(0.7, 0.05, 0.25), Color(0.8, 0.9, 0.9))
	_lamp("AirlockDim", Vector3(0, HEIGHT - 0.25, c4.x + 1.2), Color(0.8, 0.9, 0.9), 0.35, 3.6)
	_lamp("AirlockGreen", Vector3(0.9, 1.7, c4.y - 0.3), Color(0.3, 1.0, 0.4), 0.25, 1.8)


func _build_postfx() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PostFX"
	layer.layer = 100
	var rect := ColorRect.new()
	rect.name = "Atmosphere"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_psx_material = ShaderMaterial.new()
	_psx_material.shader = load("res://shaders/pixel_psx.gdshader")
	rect.material = _psx_material
	layer.add_child(rect)
	add_child(layer)
