extends Node3D
## Production upper deck for ECHOES OF THE VOID.
## Sits in the local space of ship_interior_b.tscn on top of the existing lower
## deck. Reuses the old ship's wall/pixel palette and its furniture models.
## The GLB on disk is untouched: only the common-room ceiling over the atrium
## and stair opening is removed at runtime.

const PIXEL := preload("res://scripts/ship_pixel_materials.gd")
const BUNK := preload("res://assetss/rooms/quarters/bunk_bed.glb")
const LOCKER := preload("res://assetss/rooms/quarters/locker.glb")
const SHELF := preload("res://assetss/rooms/quarters/shelf_rack.glb")
const TABLE := preload("res://assetss/rooms/quarters/table_small.glb")
const CHAIR := preload("res://assetss/rooms/quarters/chair_folded.glb")
const NAV_CONSOLE := preload("res://assetss/rooms/navigation_console/navigation_console_v2.glb")
const BENCH := preload("res://assetss/rooms/airlock/airlock_bench.glb")
const TRASH := preload("res://assetss/ship_clutter_external/trash_bin_lowpoly.glb")
const PIPES := preload("res://assetss/rooms/quarters/wall_pipes_small.glb")
const VENT := preload("res://assetss/rooms/quarters/vent_grille.glb")

const OLD_CEIL := 2.60
const FLOOR := 2.82
const CEIL := 5.42
const ROOF := 5.62
const SLAB := 2.62
const WALL_T := 0.12
const X0 := -4.10
const X1 := 0.0
const TECH_X1 := 4.50
const TECH_Z0 := -2.70
const CABIN_Z1 := 4.0
const HALL_Z0 := -4.0
const OBS_Z0 := -8.0
const ATRIUM_X0 := -3.10
const ATRIUM_X1 := -1.00
const ATRIUM_Z0 := -3.00
const ATRIUM_Z1 := 0.0
const STEP_COUNT := 13
const STAIR_RUN := 3.00
const STAIR_RISE := FLOOR

var roof_nodes: Array = []
var _materials := {}
var _collision_shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	_cut_old_ceiling()
	_build_floors()
	_build_walls()
	_build_stairs()
	_build_railings()
	_build_atrium_fascia()
	_build_ceilings()
	_build_lights()
	_build_props()
	_build_signs()
	var used := PIXEL.apply_to(self)
	_build_collision()
	print("[UpperDeck] pixel_textures=", used.keys())


func get_collision_shapes() -> Array:
	return _collision_shapes


func set_roof_visible(value: bool) -> void:
	for node in roof_nodes:
		if is_instance_valid(node):
			(node as Node3D).visible = value


func _material(label: String, color: Color, metallic := 0.2, roughness := 0.82,
		uv := Vector3.ONE) -> StandardMaterial3D:
	var key := "%s|%s" % [label, str(uv)]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.resource_name = label
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.uv1_scale = uv
	_materials[key] = material
	return material


func _box(size: Vector3, pos: Vector3, material: Material, node_name := "",
		is_roof := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	node.mesh = mesh
	node.position = pos
	if not node_name.is_empty():
		node.name = node_name
	add_child(node)
	if is_roof:
		roof_nodes.append(node)
	return node


func _sloped(size: Vector3, pos: Vector3, material: Material, pitch: float,
		node_name := "") -> MeshInstance3D:
	var node := _box(size, pos, material, node_name)
	node.rotation.x = pitch
	return node


func _cut_old_ceiling() -> void:
	var rooms := get_node_or_null("../Rooms")
	if rooms == null:
		push_warning("[UpperDeck] Rooms not found, atrium ceiling stays closed")
		return
	# GLB import names mesh nodes "<object> <material>", e.g.
	# "common structural_graphite". Cut the top faces of both the outer shell
	# and the bulkhead liner inside the atrium/stair opening.
	for node in rooms.find_children("common *", "MeshInstance3D", true, false):
		_cut_mesh_top(node as MeshInstance3D)
	for node in rooms.find_children("bulkhead *", "MeshInstance3D", true, false):
		_cut_mesh_top(node as MeshInstance3D)


func _cut_mesh_top(mesh_node: MeshInstance3D) -> void:
	var source := mesh_node.mesh
	var result := ArrayMesh.new()
	var changed := false
	var removed := 0
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			continue
		var kept: Array[int] = []
		for index in range(0, indices.size(), 3):
			var ia := indices[index]
			var ib := indices[index + 1]
			var ic := indices[index + 2]
			var a := mesh_node.transform * vertices[ia]
			var b := mesh_node.transform * vertices[ib]
			var c := mesh_node.transform * vertices[ic]
			if a.y > 2.50 and b.y > 2.50 and c.y > 2.50:
				var centroid := (a + b + c) / 3.0
				if centroid.x > X0 - 0.05 and centroid.x < ATRIUM_X1 + 0.05 \
						and centroid.z > ATRIUM_Z0 - 0.05 and centroid.z < ATRIUM_Z1 + 0.05:
					changed = true
					removed += 1
					continue
			kept.append(ia)
			kept.append(ib)
			kept.append(ic)
		var new_arrays := arrays.duplicate(true)
		new_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(kept)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
		result.surface_set_material(result.get_surface_count() - 1,
			source.surface_get_material(surface))
	if changed:
		mesh_node.mesh = result
		print("[UpperDeck] ceiling cut ", mesh_node.name, " removed=", removed)


func _build_floors() -> void:
	var plate := _material("deck_plate", Color(0.38, 0.39, 0.37), 0.35, 0.72,
		Vector3(3, 3, 1))
	var slab_y := (SLAB + FLOOR) * 0.5
	_box(Vector3(X1 - X0, FLOOR - SLAB, CABIN_Z1),
		Vector3((X0 + X1) * 0.5, slab_y, CABIN_Z1 * 0.5), plate, "CabinFloor")
	_box(Vector3(X1 - X0, FLOOR - SLAB, HALL_Z0 - OBS_Z0),
		Vector3((X0 + X1) * 0.5, slab_y, (OBS_Z0 + HALL_Z0) * 0.5),
		plate, "ObservationFloor")
	_box(Vector3(TECH_X1 - X1, FLOOR - SLAB, -TECH_Z0),
		Vector3((X1 + TECH_X1) * 0.5, slab_y, TECH_Z0 * 0.5), plate, "TechFloor")
	# Landing around the open atrium.
	_box(Vector3(X1 - X0, FLOOR - SLAB, ATRIUM_Z0 - HALL_Z0),
		Vector3((X0 + X1) * 0.5, slab_y, (HALL_Z0 + ATRIUM_Z0) * 0.5),
		plate, "BackWalkway")
	_box(Vector3(X1 - ATRIUM_X1, FLOOR - SLAB, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3((ATRIUM_X1 + X1) * 0.5, slab_y, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5),
		plate, "EastWalkway")


func _build_walls() -> void:
	var cabin := _material("wall_quarters", Color(0.74, 0.68, 0.58), 0.1, 0.92,
		Vector3(3, 1.2, 1))
	var hall := _material("wall_common", Color(0.62, 0.68, 0.62), 0.1, 0.92,
		Vector3(3, 1.2, 1))
	var tech := _material("wall_technical", Color(0.58, 0.62, 0.58), 0.12, 0.9,
		Vector3(3, 1.2, 1))
	var trim := _material("brushed_edges", Color(0.62, 0.64, 0.62), 0.55, 0.55)
	var height := CEIL - FLOOR
	var mid := (FLOOR + CEIL) * 0.5
	# Cabin shell.
	_box(Vector3(X1 - X0, height, WALL_T), Vector3((X0 + X1) * 0.5, mid, CABIN_Z1 + WALL_T * 0.5),
		cabin, "CabinBack")
	_box(Vector3(WALL_T, height, CABIN_Z1), Vector3(X0 - WALL_T * 0.5, mid, CABIN_Z1 * 0.5),
		cabin, "CabinOuter")
	_box(Vector3(WALL_T, height, CABIN_Z1), Vector3(X1 + WALL_T * 0.5, mid, CABIN_Z1 * 0.5),
		cabin, "CabinInner")
	# Cabin / hall wall, door at x -0.8..0 on the east walkway.
	_box(Vector3(ATRIUM_X1 - X0, height, WALL_T),
		Vector3((X0 + ATRIUM_X1) * 0.5, mid, -WALL_T * 0.5), cabin, "CabinHallWall")
	_box(Vector3(X1 - ATRIUM_X1, CEIL - 4.92, WALL_T),
		Vector3((ATRIUM_X1 + X1) * 0.5, (4.92 + CEIL) * 0.5, -WALL_T * 0.5),
		cabin, "CabinDoorHeader")
	# Observation shell and window opening.
	_box(Vector3(X1 - X0, height, WALL_T), Vector3((X0 + X1) * 0.5, mid, OBS_Z0 - WALL_T * 0.5),
		cabin, "ObservationBack")
	_box(Vector3(WALL_T, height, HALL_Z0 - OBS_Z0),
		Vector3(X1 + WALL_T * 0.5, mid, (OBS_Z0 + HALL_Z0) * 0.5), cabin, "ObservationInner")
	_box(Vector3(WALL_T, height, 0.8), Vector3(X0 - WALL_T * 0.5, mid, -7.6),
		cabin, "ObservationOuterFore")
	_box(Vector3(WALL_T, height, 0.8), Vector3(X0 - WALL_T * 0.5, mid, -4.4),
		cabin, "ObservationOuterAft")
	_box(Vector3(WALL_T, 0.70, 2.40), Vector3(X0 - WALL_T * 0.5, FLOOR + 0.35, -6.0),
		cabin, "ObservationSill")
	_box(Vector3(WALL_T, CEIL - 5.12, 2.40),
		Vector3(X0 - WALL_T * 0.5, (5.12 + CEIL) * 0.5, -6.0), cabin, "ObservationHeader")
	# Observation / hall wall, door at x -0.8..0.
	_box(Vector3(ATRIUM_X1 - X0, height, WALL_T),
		Vector3((X0 + ATRIUM_X1) * 0.5, mid, HALL_Z0 - WALL_T * 0.5),
		cabin, "ObservationHallWall")
	_box(Vector3(X1 - ATRIUM_X1, CEIL - 4.92, WALL_T),
		Vector3((ATRIUM_X1 + X1) * 0.5, (4.92 + CEIL) * 0.5, HALL_Z0 - WALL_T * 0.5),
		cabin, "ObservationDoorHeader")
	# Hall outer wall along the stair flight.
	_box(Vector3(WALL_T, height, ATRIUM_Z1 - HALL_Z0),
		Vector3(X0 - WALL_T * 0.5, mid, (HALL_Z0 + ATRIUM_Z1) * 0.5),
		hall, "HallOuterWall")
	# Hall / tech wall, door at z -2.2..-1.2, plus outer piece aft of the store.
	_box(Vector3(WALL_T, height, 1.2), Vector3(X1 + WALL_T * 0.5, mid, -0.6),
		hall, "HallTechWallFore")
	_box(Vector3(WALL_T, height, 0.5), Vector3(X1 + WALL_T * 0.5, mid, -2.45),
		hall, "HallTechWallAft")
	_box(Vector3(WALL_T, CEIL - 4.92, 1.0), Vector3(X1 + WALL_T * 0.5, (4.92 + CEIL) * 0.5, -1.7),
		hall, "TechDoorHeader")
	_box(Vector3(WALL_T, height, -TECH_Z0), Vector3(X1 + WALL_T * 0.5, mid, -3.35),
		hall, "HallOuterAft")
	# Tech storage shell.
	_box(Vector3(WALL_T, height, -TECH_Z0), Vector3(TECH_X1 + WALL_T * 0.5, mid, TECH_Z0 * 0.5),
		tech, "TechOuter")
	_box(Vector3(TECH_X1 - X1, height, WALL_T),
		Vector3((X1 + TECH_X1) * 0.5, mid, TECH_Z0 - WALL_T * 0.5), tech, "TechBack")
	_box(Vector3(TECH_X1 - X1, height, WALL_T),
		Vector3((X1 + TECH_X1) * 0.5, mid, WALL_T * 0.5), tech, "TechFront")
	# Heavy frames around each opening.
	_frame_x(-0.8, 0.0, -WALL_T * 0.5, trim)
	_frame_x(-0.8, 0.0, HALL_Z0 - WALL_T * 0.5, trim)
	_frame_z(-2.2, -1.2, X1 + WALL_T * 0.5, trim)
	# Base trim on the visible outer walls.
	var base := _material("brushed_edges", Color(0.62, 0.64, 0.62), 0.55, 0.55)
	_box(Vector3(0.04, 0.06, CABIN_Z1), Vector3(X0 + 0.02, FLOOR + 0.03, CABIN_Z1 * 0.5), base)
	_box(Vector3(0.04, 0.06, HALL_Z0 - OBS_Z0),
		Vector3(X0 + 0.02, FLOOR + 0.03, (OBS_Z0 + HALL_Z0) * 0.5), base)
	_box(Vector3(0.04, 0.06, -TECH_Z0), Vector3(TECH_X1 - 0.02, FLOOR + 0.03, TECH_Z0 * 0.5), base)
	# Hazard thresholds.
	var hazard := _material("detail_hazard", Color(0.82, 0.62, 0.10), 0.2, 0.6)
	_box(Vector3(0.84, 0.02, 0.14), Vector3(-0.4, FLOOR + 0.011, -0.07), hazard)
	_box(Vector3(0.84, 0.02, 0.14), Vector3(-0.4, FLOOR + 0.011, HALL_Z0 + 0.07), hazard)
	_box(Vector3(0.14, 0.02, 1.04), Vector3(X1 - 0.07, FLOOR + 0.011, -1.7), hazard)


func _frame_x(x0: float, x1: float, z: float, material: Material) -> void:
	_box(Vector3(0.06, 2.1, 0.17), Vector3(x0 - 0.03, FLOOR + 1.05, z), material)
	_box(Vector3(0.06, 2.1, 0.17), Vector3(x1 + 0.03, FLOOR + 1.05, z), material)
	_box(Vector3(x1 - x0 + 0.12, 0.08, 0.17),
		Vector3((x0 + x1) * 0.5, FLOOR + 2.14, z), material)


func _frame_z(z0: float, z1: float, x: float, material: Material) -> void:
	_box(Vector3(0.17, 2.1, 0.06), Vector3(x, FLOOR + 1.05, z0 - 0.03), material)
	_box(Vector3(0.17, 2.1, 0.06), Vector3(x, FLOOR + 1.05, z1 + 0.03), material)
	_box(Vector3(0.17, 0.08, z1 - z0 + 0.12),
		Vector3(x, FLOOR + 2.14, (z0 + z1) * 0.5), material)


func _build_stairs() -> void:
	var tread := _material("deck_plate", Color(0.40, 0.41, 0.39), 0.35, 0.72)
	var riser := _material("structural_graphite", Color(0.34, 0.36, 0.34), 0.4, 0.66)
	var hazard := _material("detail_hazard", Color(0.82, 0.62, 0.10), 0.2, 0.6)
	var run := STAIR_RUN / float(STEP_COUNT)
	var rise := STAIR_RISE / float(STEP_COUNT)
	for i in STEP_COUNT:
		var z0 := -float(i) * run
		var z1 := z0 - run
		var top := float(i + 1) * rise
		_box(Vector3(1.0, 0.05, run + 0.005),
			Vector3(-3.6, top - 0.025, (z0 + z1) * 0.5), tread, "StairTread_%02d" % i)
		_box(Vector3(1.0, rise, 0.04),
			Vector3(-3.6, float(i) * rise + rise * 0.5, z0 - 0.02), riser, "StairRiser_%02d" % i)
		_box(Vector3(1.0, 0.018, 0.04),
			Vector3(-3.6, top + 0.009, z0 - 0.02), hazard, "StairNose_%02d" % i)
	var length := sqrt(STAIR_RUN * STAIR_RUN + STAIR_RISE * STAIR_RISE)
	var pitch := atan2(STAIR_RISE, STAIR_RUN)
	for x in [-4.04, -3.16]:
		_sloped(Vector3(0.06, 0.18, length), Vector3(x, STAIR_RISE * 0.5, -STAIR_RUN * 0.5),
			riser, pitch, "StairStringer")
	_box(Vector3(1.0, 0.02, 0.18), Vector3(-3.6, 0.011, 0.12), hazard, "StairThreshold")


func _build_railings() -> void:
	var rail := _material("brushed_edges", Color(0.66, 0.68, 0.66), 0.6, 0.48)
	var post := Vector3(0.04, 0.95, 0.04)
	# East walkway edge.
	for z in [-0.4, -1.2, -2.0, -2.8]:
		_box(post, Vector3(ATRIUM_X1, FLOOR + 0.475, z), rail)
	_box(Vector3(0.05, 0.05, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X1, FLOOR + 0.95, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), rail)
	# Back walkway edge.
	for x in [-2.80, -2.00, -1.20]:
		_box(post, Vector3(x, FLOOR + 0.475, ATRIUM_Z0), rail)
	_box(Vector3(ATRIUM_X1 - ATRIUM_X0, 0.05, 0.05),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, FLOOR + 0.95, ATRIUM_Z0), rail)
	_box(post, Vector3(ATRIUM_X1, FLOOR + 0.475, ATRIUM_Z0), rail)
	# Sloped rail on the open side of the flight.
	var length := sqrt(STAIR_RUN * STAIR_RUN + STAIR_RISE * STAIR_RISE)
	var pitch := atan2(STAIR_RISE, STAIR_RUN)
	_sloped(Vector3(0.05, 0.05, length), Vector3(ATRIUM_X0, STAIR_RISE * 0.5 + 0.95, -STAIR_RUN * 0.5),
		rail, pitch, "StairRail")
	for i in range(0, STEP_COUNT, 2):
		var z := -float(i) * (STAIR_RUN / float(STEP_COUNT)) - 0.12
		var y := float(i + 1) * (STAIR_RISE / float(STEP_COUNT)) + 0.45
		_box(post, Vector3(ATRIUM_X0, y, z), rail)


func _build_atrium_fascia() -> void:
	var fascia := _material("structural_graphite", Color(0.30, 0.32, 0.31), 0.4, 0.68)
	var trim := _material("brushed_edges", Color(0.60, 0.62, 0.60), 0.55, 0.52)
	var h := 0.30
	var y := OLD_CEIL + h * 0.5
	_box(Vector3(0.08, h, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X0, y, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), fascia, "AtriumFasciaWest")
	_box(Vector3(0.08, h, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X1, y, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), fascia, "AtriumFasciaEast")
	_box(Vector3(ATRIUM_X1 - ATRIUM_X0, h, 0.08),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, y, ATRIUM_Z0), fascia, "AtriumFasciaBack")
	_box(Vector3(ATRIUM_X1 - ATRIUM_X0, h, 0.08),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, y, ATRIUM_Z1), fascia, "AtriumFasciaFront")
	# Top trim outlining the void.
	_box(Vector3(0.10, 0.04, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X0, OLD_CEIL + h + 0.02, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), trim)
	_box(Vector3(0.10, 0.04, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X1, OLD_CEIL + h + 0.02, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), trim)
	_box(Vector3(ATRIUM_X1 - ATRIUM_X0, 0.04, 0.10),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, OLD_CEIL + h + 0.02, ATRIUM_Z0), trim)


func _build_ceilings() -> void:
	var roof_mat := _material("structural_graphite", Color(0.28, 0.30, 0.29), 0.4, 0.68)
	var beam := _material("brushed_edges", Color(0.54, 0.56, 0.54), 0.55, 0.52)
	var lamp := StandardMaterial3D.new()
	lamp.resource_name = "lamp_diffuser"
	lamp.albedo_color = Color(0.45, 0.50, 0.44)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.82, 0.58)
	lamp.emission_energy_multiplier = 1.1
	# Roof slabs.
	_box(Vector3(X1 - X0, ROOF - CEIL, CABIN_Z1 - OBS_Z0),
		Vector3((X0 + X1) * 0.5, (CEIL + ROOF) * 0.5, (OBS_Z0 + CABIN_Z1) * 0.5),
		roof_mat, "UpperRoof", true)
	_box(Vector3(TECH_X1 - X1, ROOF - CEIL, -TECH_Z0),
		Vector3((X1 + TECH_X1) * 0.5, (CEIL + ROOF) * 0.5, TECH_Z0 * 0.5),
		roof_mat, "TechRoof", true)
	# Beams and recessed light panels.
	for z in [1.0, 2.0, 3.0]:
		_box(Vector3(X1 - X0, 0.08, 0.08), Vector3((X0 + X1) * 0.5, CEIL - 0.04, z),
			beam, "", true)
	for z in [-5.0, -6.0, -7.0]:
		_box(Vector3(X1 - X0, 0.08, 0.08), Vector3((X0 + X1) * 0.5, CEIL - 0.04, z),
			beam, "", true)
	for z in [-0.8, -1.8, -2.8]:
		_box(Vector3(ATRIUM_X1 - ATRIUM_X0, 0.08, 0.08),
			Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, CEIL - 0.04, z), beam, "", true)
	for x in [1.2, 2.4, 3.6]:
		_box(Vector3(0.08, 0.08, -TECH_Z0), Vector3(x, CEIL - 0.04, TECH_Z0 * 0.5),
			beam, "", true)
	# Lamps.
	_ceiling_panel(lamp, Vector3(-2.05, CEIL - 0.03, 2.0), Vector3(0.55, 0.02, 1.0))
	_ceiling_panel(lamp, Vector3(-2.05, CEIL - 0.03, -6.0), Vector3(0.55, 0.02, 1.0))
	_ceiling_panel(lamp, Vector3(-1.95, CEIL - 0.03, -1.55), Vector3(0.70, 0.02, 0.70))
	_ceiling_panel(lamp, Vector3(1.05, CEIL - 0.03, -1.35), Vector3(0.55, 0.02, 1.0))
	_ceiling_panel(lamp, Vector3(3.45, CEIL - 0.03, -1.35), Vector3(0.55, 0.02, 1.0))


func _ceiling_panel(material: Material, pos: Vector3, size: Vector3) -> void:
	_box(size, pos, material, "", true)


func _build_lights() -> void:
	_spot("CabinLight", Vector3(-2.05, CEIL - 0.10, 2.0), Color(1.0, 0.80, 0.56), 1.7, 4.6)
	_spot("ObservationLight", Vector3(-2.05, CEIL - 0.10, -6.0), Color(0.60, 0.76, 0.94), 1.6, 5.0)
	_spot("HallLight", Vector3(-1.95, CEIL - 0.10, -1.55), Color(1.0, 0.78, 0.52), 2.2, 6.0)
	_spot("TechLight", Vector3(1.05, CEIL - 0.10, -1.35), Color(0.58, 0.88, 0.68), 1.4, 4.4)
	_spot("TechLightB", Vector3(3.45, CEIL - 0.10, -1.35), Color(0.58, 0.88, 0.68), 1.2, 4.0)
	_omni("StairFill", Vector3(-3.55, 3.90, -1.60), Color(1.0, 0.80, 0.56), 0.7, 3.2)
	_omni("StairFoot", Vector3(-3.55, 1.25, -0.15), Color(1.0, 0.80, 0.56), 0.45, 2.2)
	_omni("WindowGlow", Vector3(-3.95, 4.20, -6.0), Color(0.32, 0.52, 0.80), 0.5, 2.6)
	_omni("AtriumFill", Vector3(-2.0, 4.60, -1.50), Color(1.0, 0.78, 0.52), 1.8, 6.0)
	_omni("AtriumLower", Vector3(-2.0, 3.40, -1.50), Color(1.0, 0.78, 0.52), 2.5, 5.0)
	_spot("AtriumShaft", Vector3(-2.0, 3.45, -1.50), Color(1.0, 0.78, 0.52), 2.5, 3.8)


func _spot(name: String, pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var light := SpotLight3D.new()
	light.name = name
	light.position = pos
	light.rotation_degrees.x = -90
	light.light_color = color
	light.light_energy = energy
	light.spot_range = range_m
	light.spot_angle = 72.0
	light.shadow_enabled = true
	light.shadow_bias = 0.15
	light.shadow_normal_bias = 1.2
	add_child(light)


func _omni(name: String, pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var light := OmniLight3D.new()
	light.name = name
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	add_child(light)


func _build_props() -> void:
	_build_window()
	var wood := _material("detail_laminate", Color(0.46, 0.38, 0.28), 0.05, 0.9)
	# Cabin.
	_prop(BUNK, "CabinBunk", Vector3(-3.55, FLOOR, 2.20), 90.0)
	_prop(LOCKER, "CabinLocker", Vector3(-3.55, FLOOR, 3.65), 180.0)
	_prop(TABLE, "CabinTable", Vector3(-0.45, FLOOR, 3.20), 0.0)
	_prop(CHAIR, "CabinChair", Vector3(-1.15, FLOOR, 2.45), 0.0)
	_prop(PIPES, "CabinPipes", Vector3(-3.99, 4.75, 2.00), -90.0)
	# Observation.
	_prop(NAV_CONSOLE, "ObservationConsole", Vector3(-2.05, FLOOR, -7.35), 0.0)
	_prop(CHAIR, "ObservationChair", Vector3(-2.05, FLOOR, -6.05), 180.0)
	_prop(BENCH, "ObservationBench", Vector3(-0.45, FLOOR, -5.20), 90.0)
	_prop(TABLE, "ObservationTable", Vector3(-0.45, FLOOR, -7.30), 0.0)
	_prop(VENT, "ObservationVent", Vector3(-0.06, 4.30, -5.20), 90.0)
	# Tech storage.
	_prop(SHELF, "TechShelf", Vector3(4.20, FLOOR, -1.30), 90.0)
	_prop(LOCKER, "TechLocker", Vector3(3.70, FLOOR, -0.42), 180.0)
	_prop(TABLE, "TechTable", Vector3(2.00, FLOOR, -2.28), 0.0)
	_prop(TRASH, "TechBin", Vector3(3.25, FLOOR, -2.30), 0.0)
	_prop(PIPES, "TechPipes", Vector3(2.50, 4.05, -2.62), 0.0)
	# Crates on the floor.
	var crate := _material("detail_cardboard", Color(0.55, 0.45, 0.32), 0.0, 0.9)
	_box(Vector3(0.62, 0.50, 0.62), Vector3(0.95, FLOOR + 0.25, -2.18), crate, "CrateA")
	_box(Vector3(0.62, 0.50, 0.62), Vector3(0.95, FLOOR + 0.75, -2.18), crate, "CrateB")
	_box(Vector3(0.52, 0.42, 0.52), Vector3(0.35, FLOOR + 0.21, -0.60), crate, "CrateC")
	# Hall dressing.
	_prop(VENT, "HallVent", Vector3(-0.06, 4.30, -3.35), -90.0)
	_prop(PIPES, "HallPipes", Vector3(-0.06, 4.75, -0.60), -90.0)
	# A small worktop at the cabin door is omitted: the visible decals/labels come next.


func _prop(scene: PackedScene, name: String, pos: Vector3, yaw: float) -> Node3D:
	var node := scene.instantiate() as Node3D
	node.name = name
	node.position = pos
	node.rotation_degrees.y = yaw
	add_child(node)
	return node


func _build_signs() -> void:
	_sign("ДОП. КАЮТА", Vector3(-0.40, 4.72, -0.01), 180.0)
	_sign("ОБЗОР", Vector3(-0.40, 4.72, HALL_Z0 + 0.01), 0.0)
	_sign("ТЕХСКЛАД", Vector3(X1 - 0.01, 4.72, -1.70), -90.0)
	_sign("ВЕРХНЯЯ ПАЛУБА", Vector3(-3.10, 2.18, -0.04), 180.0)
	# A small warm lens over the lower stair sign, matching the old lamp style.
	var lamp := _material("lamp_diffuser", Color(0.35, 0.40, 0.35), 0.0, 0.8)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.78, 0.52)
	lamp.emission_energy_multiplier = 0.9
	_box(Vector3(0.52, 0.02, 0.08), Vector3(-3.10, 2.44, -0.04), lamp)
	_omni("StairSignFill", Vector3(-3.10, 2.24, -0.35), Color(1.0, 0.80, 0.56), 0.5, 2.0)


func _sign(text: String, pos: Vector3, yaw: float) -> void:
	var text_mesh := TextMesh.new()
	text_mesh.text = text
	text_mesh.font = load("res://assetss/ui/fonts/RussoOne-Regular.ttf")
	text_mesh.font_size = 28
	text_mesh.pixel_size = 0.003
	text_mesh.depth = 0.008
	text_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sign := MeshInstance3D.new()
	sign.mesh = text_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.57, 0.65, 0.61)
	material.roughness = 0.9
	sign.material_override = material
	sign.position = pos
	sign.rotation_degrees.y = yaw
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sign)


func _build_window() -> void:
	var frame := _material("brushed_edges", Color(0.52, 0.55, 0.53), 0.6, 0.48)
	var glass := StandardMaterial3D.new()
	glass.resource_name = "observation_glass"
	glass.albedo_color = Color(0.008, 0.016, 0.035)
	glass.albedo_texture = load("res://assetss/space/starfield_pano.png")
	glass.emission_enabled = true
	glass.emission = Color(0.75, 0.85, 1.0)
	glass.emission_texture = load("res://assetss/space/starfield_pano.png")
	glass.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	glass.emission_energy_multiplier = 1.6
	glass.roughness = 0.08
	glass.uv1_scale = Vector3(0.5, 0.5, 1.0)
	_box(Vector3(0.03, 1.60, 2.40), Vector3(X0 - 0.02, FLOOR + 1.50, -6.0),
		glass, "ObservationGlass")
	# Frame and mullions.
	_box(Vector3(0.10, 1.72, 0.10), Vector3(X0 + 0.04, FLOOR + 1.50, -7.20), frame)
	_box(Vector3(0.10, 1.72, 0.10), Vector3(X0 + 0.04, FLOOR + 1.50, -4.80), frame)
	_box(Vector3(0.10, 0.10, 2.50), Vector3(X0 + 0.04, FLOOR + 2.30, -6.0), frame)
	_box(Vector3(0.10, 0.10, 2.50), Vector3(X0 + 0.04, FLOOR + 0.70, -6.0), frame)
	_box(Vector3(0.06, 1.64, 0.06), Vector3(X0 + 0.05, FLOOR + 1.50, -6.0), frame)
	_box(Vector3(0.06, 0.06, 2.40), Vector3(X0 + 0.05, FLOOR + 1.50, -6.0), frame)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "UpperDeckCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for label in ["CabinFloor", "ObservationFloor", "TechFloor", "BackWalkway",
			"EastWalkway", "CabinBack", "CabinOuter", "CabinInner", "CabinHallWall",
			"CabinDoorHeader", "ObservationBack", "ObservationInner",
			"ObservationOuterFore", "ObservationOuterAft", "ObservationSill",
			"ObservationHeader", "ObservationHallWall", "ObservationDoorHeader",
			"HallOuterWall", "HallTechWallFore", "HallTechWallAft", "TechDoorHeader",
			"HallOuterAft", "TechOuter", "TechBack", "TechFront",
			"CrateA", "CrateB", "CrateC"]:
		_collide_named(body, label)
	# Invisible barriers along the open atrium. The visual railings sit on them.
	_add_box(body, Vector3(0.08, 1.0, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X1, FLOOR + 0.5, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5))
	_add_box(body, Vector3(ATRIUM_X1 - ATRIUM_X0, 1.0, 0.08),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, FLOOR + 0.5, ATRIUM_Z0))
	_add_box(body, Vector3(0.08, FLOOR + 1.0, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X0, (FLOOR + 1.0) * 0.5, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5))
	# Smooth ramp collider over the visual treads.
	var run := sqrt(STAIR_RUN * STAIR_RUN + STAIR_RISE * STAIR_RISE)
	var ramp := _add_box(body, Vector3(1.0, 0.20, run),
		Vector3(-3.60, STAIR_RISE * 0.5 - 0.10, -STAIR_RUN * 0.5))
	ramp.rotation.x = atan2(STAIR_RISE, STAIR_RUN)
	for prop_name in ["CabinBunk", "CabinLocker", "CabinTable", "CabinChair",
			"ObservationConsole", "ObservationChair", "ObservationBench",
			"ObservationTable", "TechShelf", "TechLocker", "TechTable", "TechBin"]:
		var prop := find_child(prop_name, true, false) as Node3D
		if prop != null:
			_add_prop_collision(prop)


func _collide_named(body: StaticBody3D, label: String) -> void:
	var node := find_child(label, true, false) as MeshInstance3D
	if node == null or not (node.mesh is BoxMesh):
		return
	var mesh := node.mesh as BoxMesh
	_add_box(body, mesh.size, node.position, node.rotation)


func _add_box(body: StaticBody3D, size: Vector3, pos: Vector3,
		rot := Vector3.ZERO) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation = rot
	body.add_child(shape)
	_collision_shapes.append(shape)
	return shape


func _add_prop_collision(prop: Node3D) -> void:
	for node in prop.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		mesh_node.create_trimesh_collision()
		for child in mesh_node.get_children():
			if child is StaticBody3D:
				var body := child as StaticBody3D
				body.collision_layer = 1
				body.collision_mask = 0
				for shape in body.get_children():
					if shape is CollisionShape3D:
						_collision_shapes.append(shape)
