extends Node3D

# Collision and practical lamps belong to this interior, so EVA can disable
# both the visible geometry and its physics together.
var _shapes: Array[CollisionShape3D] = []
var _power_lights: Array[Light3D] = []
var _light_energy: Dictionary = {}
var _power_emitters: Array[StandardMaterial3D] = []
var _emitter_energy: Dictionary = {}
var _emitter_albedo: Dictionary = {}

func _ready() -> void:
	_build_bridge_connector()
	var used: Dictionary = preload("res://scripts/ship_pixel_materials.gd").apply_to(self)
	print("[ShipMaterials] pixel_textures=",used.size())
	_add_collision($Rooms)
	_add_collision($Bridge)
	_add_collision(get_node("BridgeConnector/Structure"))
	# Fine clutter pieces and wall-mounted labels are visual set dressing.
	# Building a trimesh collider for every detail made the narrow EVA route snag.
	_add_collision($CrewWasteBin)
	_create_airlock_door()
	_ceiling_lamp("CommonA", Vector3(0,2.48,-1.2), 0.85, 3.8)
	_ceiling_lamp("CommonB", Vector3(0,2.48,1.2), 0.85, 3.8, false)
	_ceiling_lamp("QuartersA", Vector3(0,2.48,-5.2), 0.65, 3.2, false)
	_ceiling_lamp("QuartersB", Vector3(0,2.48,-2.8), 0.65, 3.2, false)
	_ceiling_lamp("AirlockA", Vector3(0,2.48,2.8), 0.8, 3.6)
	_ceiling_lamp("AirlockB", Vector3(0,2.48,5.2), 0.8, 3.6, false)
	_ceiling_lamp("AirlockTunnel", Vector3(3.48,2.07,5.45), 0.34, 2.2, false)
	_ceiling_lamp("Passage", Vector3(4.5,2.48,0.5), 0.8, 3.1, false)
	_ceiling_lamp("Bend", Vector3(5.7,2.48,-3.2), 0.9, 3.6)
	_ceiling_lamp("Bridge", Vector3(3.14,2.31,-15.32), 1.7, 5.5)
	for pos in [Vector3(0,1.8,0),Vector3(0,1.8,-4),Vector3(0,1.8,4),Vector3(3.14,1.8,-15.72),Vector3(5.7,1.8,-2)]:
		_accent("ReflectedLight", pos, Color(0.6,0.72,0.75), 0.12, 3.5)
	_accent("RadioWorkLight", Vector3(4.19,1.85,-16.09), Color(0.65,0.8,0.79), 0.28, 1.75)
	_accent("BridgeCRT", Vector3(2.16,1.55,-16.94), Color(0.2,0.9,0.51), 0.07, 1.5)
	_accent("BridgeUtility", Vector3(4.45,1.85,-17.84), Color(1,0.49,0.18), 0.12, 2.3)
	_accent("AirlockUtility", Vector3(-1.25,1.65,5.55), Color(1,0.32,0.13), 0.16, 2.0)
	_sign("МОСТИК", Vector3(3.14,2.28,-13.18), 0)
	_sign("ШЛЮЗ", Vector3(0,2.28,1.90), 180)
	_sign("КАЮТА", Vector3(0,2.28,-1.90), 0)
	_sign("ТЕХНИЧЕСКИЙ ПРОХОД", Vector3(1.87,2.28,0), -90)
	_create_bridge_connector_lights()
	_cache_power_lights(self)
	_cache_power_emitters(self)


func set_story_power(fraction: float) -> void:
	var power := clampf(fraction, 0.0, 1.0)
	for light in _power_lights:
		if is_instance_valid(light):
			light.light_energy = float(_light_energy.get(light, light.light_energy)) * power
	for material in _power_emitters:
		if not is_instance_valid(material):
			continue
		material.emission_energy_multiplier = float(_emitter_energy.get(material, 0.0)) * power
		material.albedo_color = Color(0.018, 0.022, 0.028).lerp(
			_emitter_albedo.get(material, Color.WHITE), power)


func _cache_power_lights(node: Node) -> void:
	for child in node.get_children():
		if child is Light3D:
			var light := child as Light3D
			_power_lights.append(light)
			_light_energy[light] = light.light_energy
		_cache_power_lights(child)

func _cache_power_emitters(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in mesh_node.mesh.get_surface_count():
				var source := mesh_node.get_surface_override_material(surface) as StandardMaterial3D
				if source == null:
					source = mesh_node.mesh.surface_get_material(surface) as StandardMaterial3D
				if source == null or source.resource_name != "lamp_diffuser":
					continue
				var powered := source.duplicate() as StandardMaterial3D
				mesh_node.set_surface_override_material(surface, powered)
				_power_emitters.append(powered)
				_emitter_energy[powered] = source.emission_energy_multiplier
				_emitter_albedo[powered] = source.albedo_color
	for child in node.get_children():
		_cache_power_emitters(child)

func _add_collision(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		mesh_node.create_trimesh_collision()
		for body in mesh_node.get_children():
			if body is StaticBody3D:
				for shape in body.get_children():
					if shape is CollisionShape3D:
						_shapes.append(shape)
	for child in node.get_children():
		if not child is StaticBody3D:
			_add_collision(child)


func _create_airlock_door() -> void:
	var frame := (load("res://assetss/rooms/airlock/airlock_pressure_frame.glb") as PackedScene).instantiate() as Node3D
	frame.name = "AirlockPressureFrame"
	frame.position = Vector3(1.83, 0.0, 5.0)
	frame.rotation.y = -PI * 0.5
	add_child(frame)

	var door := AnimatableBody3D.new()
	door.name = "airlock_door"
	door.position = Vector3(1.83, 1.10, 5.0)
	door.collision_layer = 1
	door.collision_mask = 0

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.17, 2.08, 1.46)
	collision.shape = shape
	door.add_child(collision)
	_shapes.append(collision)

	var leaf := (load("res://assetss/rooms/airlock/airlock_pressure_leaf.glb") as PackedScene).instantiate() as Node3D
	leaf.name = "PressureDoorLeaf"
	leaf.position.y = -1.10
	leaf.rotation.y = -PI * 0.5
	door.add_child(leaf)
	add_child(door)
	_create_airlock_door_pocket()


func _create_airlock_door_pocket() -> void:
	var pocket := Node3D.new()
	pocket.name = "AirlockDoorPocket"
	add_child(pocket)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.11, 0.13, 0.14)
	steel.metallic = 0.55
	steel.roughness = 0.80
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.045, 0.050, 0.054)
	dark.roughness = 0.88
	# The pocket terminates at the jamb and leaves the bench clear on its room side.
	_door_pocket_piece(pocket, "Backing", Vector3(1.947, 1.10, 3.46), Vector3(0.035, 2.13, 1.53), dark)
	_door_pocket_piece(pocket, "UpperGuide", Vector3(1.779, 2.15, 3.46), Vector3(0.37, 0.12, 1.57), steel)
	_door_pocket_piece(pocket, "LowerGuide", Vector3(1.779, 0.055, 3.46), Vector3(0.37, 0.07, 1.57), steel)
	_door_pocket_piece(pocket, "EndStop", Vector3(1.779, 1.1025, 2.673), Vector3(0.37, 2.16, 0.07), steel)


func _door_pocket_piece(parent: Node3D, label: String, material_position: Vector3, size: Vector3,
		material: Material) -> void:
	var piece := MeshInstance3D.new()
	piece.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.material_override = material
	piece.position = material_position
	parent.add_child(piece)


func set_active(active: bool) -> void:
	visible = active
	for shape in _shapes:
		shape.set_deferred("disabled", not active)

func _ceiling_lamp(label: String, pos: Vector3, energy: float, distance: float, shadows: bool = true) -> void:
	var lamp := SpotLight3D.new()
	lamp.name = label + "Light"
	lamp.position = pos
	lamp.rotation_degrees.x = -90
	lamp.light_color = Color(0.72,0.82,0.78)
	lamp.light_energy = energy
	lamp.spot_range = distance
	lamp.spot_angle = 68
	lamp.shadow_enabled = shadows
	lamp.shadow_bias = 0.15
	lamp.shadow_normal_bias = 1.2
	add_child(lamp)

func _accent(label: String, pos: Vector3, color: Color, energy: float, distance: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = label
	lamp.position = pos
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = distance
	add_child(lamp)

func _sign(text: String, pos: Vector3, yaw: float) -> void:
	var text_mesh := TextMesh.new()
	text_mesh.text = text
	text_mesh.font = load("res://assetss/ui/fonts/RussoOne-Regular.ttf")
	text_mesh.font_size = 32
	text_mesh.pixel_size = 0.003
	text_mesh.depth = 0.01
	text_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sign_node := MeshInstance3D.new()
	sign_node.mesh = text_mesh
	sign_node.material_override = StandardMaterial3D.new()
	(sign_node.material_override as StandardMaterial3D).albedo_color = Color(0.57,0.65,0.61)
	(sign_node.material_override as StandardMaterial3D).roughness = 0.9
	(sign_node.material_override as StandardMaterial3D).emission_enabled = false
	sign_node.position = pos + Vector3(0, 0, 0.012).rotated(Vector3.UP, deg_to_rad(yaw))
	sign_node.rotation_degrees.y = yaw
	sign_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sign_node)


func _build_bridge_connector() -> void:
	# Swept octagonal passage: gradual bend, open ends, no box-shaped filler.
	var connector := Node3D.new()
	connector.name = "BridgeConnector"
	add_child(connector)
	var structure := Node3D.new()
	structure.name = "Structure"
	connector.add_child(structure)
	var visuals := Node3D.new()
	visuals.name = "Visuals"
	connector.add_child(visuals)
	var material_names := ["wall_technical", "deck_plate", "structural_graphite"]
	var materials: Array[StandardMaterial3D] = []
	for material_name in material_names:
		var material := StandardMaterial3D.new()
		material.resource_name = material_name
		material.albedo_color = Color(0.55, 0.58, 0.56)
		material.roughness = 0.9
		material.metallic = 0.16
		materials.append(material)
	var profile: Array[Vector2] = [
		Vector2(-1.15, 0.24), Vector2(-0.96, 0.06), Vector2(0.96, 0.06),
		Vector2(1.15, 0.24), Vector2(1.15, 2.12), Vector2(0.98, 2.43),
		Vector2(-0.98, 2.43), Vector2(-1.15, 2.12)
	]
	var segments := 36
	var centers: Array[Vector3] = []
	var sides: Array[Vector3] = []
	for index in range(segments + 1):
		var t := float(index) / float(segments)
		centers.append(_connector_center(t))
	for index in range(segments + 1):
		var before := centers[maxi(0, index - 1)]
		var after := centers[mini(segments, index + 1)]
		var tangent := (after - before).normalized()
		sides.append(tangent.cross(Vector3.UP).normalized())
	var tools: Array[SurfaceTool] = []
	for material in materials:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(material)
		tools.append(tool)
	for index in range(segments):
		for edge in range(profile.size()):
			var next_edge := (edge + 1) % profile.size()
			var surface_index := 0
			if edge == 1:
				surface_index = 1 # textured non-slip deck
			elif edge == 5:
				surface_index = 2 # dark recessed ceiling
			elif edge in [4, 6]:
				surface_index = 0 # technical side walls
			else:
				surface_index = 2
			var a := centers[index] + sides[index] * profile[edge].x + Vector3.UP * profile[edge].y
			var b := centers[index] + sides[index] * profile[next_edge].x + Vector3.UP * profile[next_edge].y
			var c := centers[index + 1] + sides[index + 1] * profile[next_edge].x + Vector3.UP * profile[next_edge].y
			var d := centers[index + 1] + sides[index + 1] * profile[edge].x + Vector3.UP * profile[edge].y
			# Godot uses clockwise front faces. The passage is seen and
			# collided with from the inside, so reverse the swept shell.
			_add_surface_quad(tools[surface_index], a, b, c, d,
				Vector2(index * 0.35, edge), Vector2(index * 0.35, edge + 1), true)
	for surface_index in range(tools.size()):
		tools[surface_index].generate_normals()
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "CorridorShell_%02d" % surface_index
		mesh_instance.mesh = tools[surface_index].commit()
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		structure.add_child(mesh_instance)
	# A dedicated smooth ramp collider keeps the player from snagging on the
	# thin trimesh bevels as the connector rises into the bridge threshold.
	for index in range(segments):
		if index < 23:
			continue
		var travel := (centers[index + 1] - centers[index]).normalized()
		var side := (sides[index] + sides[index + 1]).normalized()
		var up := side.cross(travel).normalized()
		var basis := Basis(side, up, -travel).orthonormalized()
		var floor_a := centers[index] + up * 0.06
		var floor_b := centers[index + 1] + up * 0.06
		var ramp := StaticBody3D.new()
		ramp.name = "ThresholdRamp_%02d" % index
		ramp.transform = Transform3D(basis, (floor_a + floor_b) * 0.5)
		ramp.collision_layer = 1
		ramp.collision_mask = 0
		var ramp_collision := CollisionShape3D.new()
		var ramp_shape := BoxShape3D.new()
		ramp_shape.size = Vector3(1.92, 0.16, floor_a.distance_to(floor_b) + 0.03)
		ramp_collision.shape = ramp_shape
		ramp_collision.position.y = -0.08
		ramp.add_child(ramp_collision)
		structure.add_child(ramp)
	var rib_material := StandardMaterial3D.new()
	rib_material.resource_name = "brushed_edges"
	rib_material.albedo_color = Color(0.44, 0.48, 0.47)
	rib_material.metallic = 0.35
	rib_material.roughness = 0.72
	var rib_tool := SurfaceTool.new()
	rib_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	rib_tool.set_material(rib_material)
	for station in range(3, segments, 4):
		var t0 := maxf(0.0, float(station) / float(segments) - 0.008)
		var t1 := minf(1.0, float(station) / float(segments) + 0.008)
		var c0 := _connector_center(t0)
		var c1 := _connector_center(t1)
		var s0 := _connector_side(centers, sides, t0)
		var s1 := _connector_side(centers, sides, t1)
		for edge in range(profile.size()):
			var next_edge := (edge + 1) % profile.size()
			var p0 := Vector3(profile[edge].x * 0.965, lerpf(profile[edge].y, 1.24, 0.03), 0.0)
			var p1 := Vector3(profile[next_edge].x * 0.965, lerpf(profile[next_edge].y, 1.24, 0.03), 0.0)
			var a := c0 + s0 * p0.x + Vector3.UP * p0.y
			var b := c0 + s0 * p1.x + Vector3.UP * p1.y
			var c := c1 + s1 * p1.x + Vector3.UP * p1.y
			var d := c1 + s1 * p0.x + Vector3.UP * p0.y
			_add_surface_quad(rib_tool, a, b, c, d, Vector2.ZERO, Vector2.ONE)
	rib_tool.generate_normals()
	var ribs := MeshInstance3D.new()
	ribs.name = "PressureRibs"
	ribs.mesh = rib_tool.commit()
	ribs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visuals.add_child(ribs)
	var red_pipe := _make_connector_pipe(centers, sides, -0.78, 2.02, 0.035, "detail_pipe_red", Color(0.57, 0.24, 0.18))
	red_pipe.name = "ReturnLine"
	visuals.add_child(red_pipe)
	var dark_pipe := _make_connector_pipe(centers, sides, 0.78, 2.02, 0.045, "black_rubber", Color(0.12, 0.15, 0.16))
	dark_pipe.name = "PowerConduit"
	visuals.add_child(dark_pipe)


func _add_surface_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		uv_a: Vector2, uv_b: Vector2, reverse: bool = false) -> void:
	var points := [a, b, c, d]
	var uvs := [uv_a, Vector2(uv_b.x, uv_a.y), uv_b, Vector2(uv_a.x, uv_b.y)]
	var indices := [0, 2, 1, 0, 3, 2] if reverse else [0, 1, 2, 0, 2, 3]
	for index in indices:
		tool.set_uv(uvs[index])
		tool.add_vertex(points[index])


func _connector_center(t: float) -> Vector3:
	var smoothed := t * t * (3.0 - 2.0 * t)
	# Match both room decks at the seam. The corridor deck is 0.06 m
	# above this centreline; a small offset avoids coincident surfaces.
	var deck_blend := maxf(1.0 - smoothstep(0.0, 0.12, t), smoothstep(0.62, 1.0, t))
	var floor_center := lerpf(-0.11, -0.032, deck_blend)
	return Vector3(lerpf(5.70, 3.075, smoothed), floor_center, lerpf(-5.90, -13.44, t))


func _connector_side(centers: Array[Vector3], sides: Array[Vector3], t: float) -> Vector3:
	return sides[clampi(roundi(t * float(centers.size() - 1)), 0, centers.size() - 1)]


func _make_connector_pipe(centers: Array[Vector3], sides: Array[Vector3], side_offset: float,
		height_offset: float, radius: float, material_name: String, tint: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.resource_name = material_name
	material.albedo_color = tint
	material.roughness = 0.75
	material.metallic = 0.2
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(material)
	for index in range(centers.size() - 1):
		for radial in range(6):
			var next_radial := (radial + 1) % 6
			var a0 := TAU * float(radial) / 6.0
			var a1 := TAU * float(next_radial) / 6.0
			var c0 := centers[index] + sides[index] * side_offset + Vector3.UP * height_offset
			var c1 := centers[index + 1] + sides[index + 1] * side_offset + Vector3.UP * height_offset
			var p00 := c0 + sides[index] * cos(a0) * radius + Vector3.UP * sin(a0) * radius
			var p01 := c0 + sides[index] * cos(a1) * radius + Vector3.UP * sin(a1) * radius
			var p11 := c1 + sides[index + 1] * cos(a1) * radius + Vector3.UP * sin(a1) * radius
			var p10 := c1 + sides[index + 1] * cos(a0) * radius + Vector3.UP * sin(a0) * radius
			_add_surface_quad(tool, p00, p10, p11, p01, Vector2(index, radial), Vector2(index + 1, radial + 1))
	tool.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = tool.commit()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance


func _create_bridge_connector_lights() -> void:
	var visuals := get_node("BridgeConnector/Visuals") as Node3D
	for index in range(3, 34, 12):
		var t := float(index) / 36.0
		var center := _connector_center(t)
		var light := OmniLight3D.new()
		light.name = "ConnectorLight_%02d" % index
		light.position = center + Vector3.UP * 2.18
		light.light_color = Color(0.50, 0.72, 0.70)
		light.light_energy = 0.28
		light.omni_range = 2.7
		visuals.add_child(light)
		var lens_material := StandardMaterial3D.new()
		lens_material.resource_name = "lamp_diffuser"
		lens_material.albedo_color = Color(0.27, 0.38, 0.34)
		lens_material.emission_enabled = true
		lens_material.emission = Color(0.3, 0.56, 0.42)
		lens_material.emission_energy_multiplier = 0.22
		var lens_mesh := SphereMesh.new()
		lens_mesh.radius = 0.12
		lens_mesh.height = 0.08
		var lens := MeshInstance3D.new()
		lens.name = "RecessedLens_%02d" % index
		lens.mesh = lens_mesh
		lens.material_override = lens_material
		lens.scale = Vector3(1.55, 0.5, 1.35)
		lens.position = center + Vector3.UP * 2.37
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visuals.add_child(lens)
