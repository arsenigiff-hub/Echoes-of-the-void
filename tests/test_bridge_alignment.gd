extends SceneTree

var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	await create_timer(4.2).timeout
	var interior := main.get_node("ShipInterior") as Node3D
	var player := main.get_node("Player") as Player
	var inner_glass := _find_material_bounds(interior.get_node("Bridge"), "viewport_glass")
	var outer_glass := _find_material_bounds(main.get_node("ShipExterior"), "glass_grime")
	checks["interior_window_found"] = not inner_glass.size.is_zero_approx()
	checks["exterior_window_found"] = not outer_glass.size.is_zero_approx()
	var inner_center := inner_glass.get_center()
	var outer_center := outer_glass.get_center()
	checks["window_center_distance"] = inner_center.distance_to(outer_center)
	checks["windows_aligned"] = inner_center.distance_to(outer_center) <= 0.65
	checks["connector_present"] = interior.has_node("BridgeConnector/Structure")
	checks["cabin_sign_is_physical_text"] = _has_non_emissive_text_mesh(interior, "КАЮТА")
	var bounds_interior := _world_bounds(interior)
	var bounds_hull := _world_bounds(main.get_node("ShipExterior"))
	checks["interior_inside_hull"] = _contained(bounds_hull, bounds_interior, 0.0)
	var bridge := interior.get_node("Bridge") as Node3D
	var radio := main.get_node("Radio") as Node3D
	checks["radio_inside_bridge"] = _contains(_world_bounds(bridge), radio.global_position, 0.2)
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	player.global_position = interior.to_global(Vector3(0.0, 0.13, 0.4))
	player.velocity = Vector3.ZERO
	await physics_frame
	var points: Array[Vector3] = [
		Vector3(3.4, 0.13, 0.4), Vector3(4.5, 0.13, 0.5),
		Vector3(5.7, 0.13, -3.2), Vector3(5.68, 0.13, -5.6),
		Vector3(5.48, 0.13, -7.7), Vector3(4.52, 0.13, -9.62),
		Vector3(3.41, 0.13, -12.42), Vector3(3.14, 0.13, -13.3),
		Vector3(3.14, 0.13, -14.0), Vector3(2.64, 0.13, -14.64),
		Vector3(2.64, 0.13, -15.25), Vector3(2.64, 0.13, -15.78),
	]
	checks["walkable_rooms_to_bridge"] = await _walk_route(player, interior, points, "in")
	points.reverse()
	points.append(Vector3(0.0, 0.13, 0.4))
	checks["walkable_bridge_to_rooms"] = await _walk_route(player, interior, points, "out")
	print("BRIDGE_ALIGNMENT_CHECKS ", JSON.stringify(checks))
	var failed := false
	for key in ["interior_window_found", "exterior_window_found", "windows_aligned",
		"connector_present", "cabin_sign_is_physical_text", "interior_inside_hull",
		"radio_inside_bridge", "walkable_rooms_to_bridge", "walkable_bridge_to_rooms"]:
		if checks.get(key) != true:
			failed = true
	for node in main.find_children("*", "AudioStreamPlayer", true, false):
		var audio_player := node as AudioStreamPlayer
		audio_player.stop()
		audio_player.stream = null
	current_scene = null
	main.free()
	await process_frame
	await process_frame
	quit(1 if failed else 0)


func _find_material_bounds(root_node: Node, material_name: String) -> AABB:
	for mesh_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material != null and material.resource_name == material_name:
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				if vertices.is_empty():
					continue
				var bounds := AABB(mesh.global_transform * vertices[0], Vector3.ZERO)
				for vertex_index in range(1, vertices.size()):
					bounds = bounds.expand(mesh.global_transform * vertices[vertex_index])
				return bounds
	return AABB()


func _has_non_emissive_text_mesh(root_node: Node, expected_text: String) -> bool:
	for mesh_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh is not TextMesh or (mesh.mesh as TextMesh).text != expected_text:
			continue
		var material := mesh.get_active_material(0) as StandardMaterial3D
		return material != null and not material.emission_enabled
	return false


func _world_bounds(root_node: Node) -> AABB:
	var result := AABB()
	var found := false
	for mesh_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var bounds := mesh.global_transform * mesh.get_aabb()
		if not found:
			result = bounds
			found = true
		else:
			result = result.merge(bounds)
	return result


func _contained(outer: AABB, inner: AABB, margin: float) -> bool:
	return inner.position.x >= outer.position.x + margin \
		and inner.position.y >= outer.position.y + margin \
		and inner.position.z >= outer.position.z + margin \
		and inner.end.x <= outer.end.x - margin \
		and inner.end.y <= outer.end.y - margin \
		and inner.end.z <= outer.end.z - margin


func _contains(bounds: AABB, point: Vector3, margin: float) -> bool:
	return point.x >= bounds.position.x + margin and point.x <= bounds.end.x - margin \
		and point.y >= bounds.position.y + margin and point.y <= bounds.end.y - margin \
		and point.z >= bounds.position.z + margin and point.z <= bounds.end.z - margin


func _walk_route(body: Player, interior: Node3D, points: Array[Vector3], label: String) -> bool:
	for index in range(points.size()):
		var reached := await _walk_to(body, interior, points[index])
		checks["route_%s_%02d" % [label, index]] = reached
		if not reached:
			return false
	return true


func _walk_to(body: Player, interior: Node3D, target: Vector3) -> bool:
	var world_target := interior.to_global(target)
	var delta := 1.0 / Engine.physics_ticks_per_second
	for _frame in range(300):
		await physics_frame
		var offset := world_target - body.global_position
		offset.y = 0.0
		if interior.to_local(body.global_position).y < -0.25:
			return false
		if offset.length() <= 0.045 and body.is_on_floor():
			return true
		var horizontal := offset.normalized() * minf(body.speed, offset.length() / delta)
		body.velocity.x = horizontal.x
		body.velocity.z = horizontal.z
		if not body.is_on_floor():
			body.velocity.y -= body.gravity * delta
		body.move_and_slide()
	return false
