extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	await process_frame
	var interior := main.get_node("ShipInterior") as Node3D
	var space := main.get_node("SpaceStage") as Node3D
	var gas := main.find_child("SpaceGasGiant", true, false) as Node3D
	var ring := main.find_child("SpaceRing", true, false) as MeshInstance3D
	var black_hole := main.find_child("SpaceBlackHole", true, false) as Node3D
	var sun := main.find_child("Sun", true, false) as Node3D
	var accretion_disk := main.find_child("CanaryAccretionDisk", true, false) as MeshInstance3D
	var selected_model := main.find_child("CanaryBlackHole", true, false) as Node3D
	var ship_in_model := selected_model.find_child("Nave_2", true, false) as Node3D if selected_model != null else null
	var model_animation := selected_model.find_child("AnimationPlayer", true, false) as AnimationPlayer if selected_model != null else null
	assert(interior != null and gas != null and ring != null and black_hole != null and sun != null,
		"Bridge or space objects are missing")
	assert(accretion_disk != null and accretion_disk.mesh != null,
		"Selected black-hole asset must have a generated accretion disk")
	assert(accretion_disk.material_override is ShaderMaterial,
		"Accretion disk must use the authored animated material")
	assert(selected_model != null and ship_in_model != null and not ship_in_model.visible,
		"The selected black-hole model must not show its embedded spacecraft")
	assert(model_animation != null and is_equal_approx(model_animation.speed_scale, 0.1),
		"The selected black-hole animation must remain at the reviewed 0.1x speed")
	assert(model_animation.is_playing() and model_animation.current_animation == "Take 001",
		"The selected black-hole animation must be active in the gameplay scene")
	var animation_start := model_animation.current_animation_position
	await create_timer(0.2).timeout
	assert(model_animation.current_animation_position > animation_start,
		"The selected black-hole animation must advance while the scene runs")
	var eye := interior.to_global(Vector3(2.94, 0.0, -13.79)) + Vector3.UP * 1.65
	var target := interior.to_global(Vector3(3.14, 1.4, -17.09))
	var forward := (target - eye).normalized()
	assert(forward.dot((gas.global_position - eye).normalized()) > 0.995,
		"Starting planet is outside the bridge window sightline")
	var sun_angle := rad_to_deg(acos(clampf(
		(gas.global_position - eye).normalized().dot((sun.global_position - eye).normalized()),
		-1.0, 1.0)))
	assert(sun_angle >= 5.0,
		"The Sun should sit visibly apart from the planet instead of hiding behind it")
	assert(ring.global_position.distance_to(gas.global_position) < 0.01,
		"Planet ring detached from the gas giant")
	assert(ring.mesh != null and ring.mesh.get_surface_count() == 1,
		"Planet ring must use a generated annulus, not the old full quad")
	assert(ring.material_override is StandardMaterial3D
		and (ring.material_override as StandardMaterial3D).vertex_color_use_as_albedo,
		"Planet ring must use robust opaque vertex colors for the VHS viewport")
	var vertices := ring.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var colors := ring.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	assert(vertices.size() == 65 * 257 and colors.size() == vertices.size(),
		"Planet ring mesh has an unexpected vertex/color count")
	var min_radius := INF
	var max_radius := 0.0
	for vertex in vertices:
		var radius := Vector2(vertex.x, vertex.y).length()
		min_radius = minf(min_radius, radius)
		max_radius = maxf(max_radius, radius)
	assert(absf(min_radius - 49.0) < 0.01 and absf(max_radius - 68.0) < 0.01,
		"Planet ring radii do not match the reviewed profile")
	assert(not black_hole.visible, "The black hole must stay hidden before the first FTL jump")
	assert(gas.scale.x < 20.0 and ring.scale.x < 0.4,
		"Planet and ring should fit inside the bridge viewport")
	var sun_start := sun.global_position
	space.call("set_stage", 1, true)
	assert(black_hole.visible, "The distant black hole must appear after the first FTL jump")
	assert(sun.global_position.distance_to(sun_start) > 1000.0 and sun.scale.x < 1.0,
		"The Sun should recede from the bridge window during the first FTL transition")
	assert(absf(eye.distance_to(black_hole.global_position) - 1200.0) < 0.1,
		"The distant black hole is not positioned on its reviewed bridge-window distance")
	assert(forward.dot((black_hole.global_position - eye).normalized()) > 0.999,
		"The distant black hole is outside the bridge window sightline")
	space.call("set_stage", 2, true)
	assert(not gas.visible and not ring.visible, "The gas giant should leave the window at the final stage")
	assert(absf(eye.distance_to(black_hole.global_position) - 550.0) < 0.1,
		"The final black hole did not advance to its close stage")
	assert(forward.dot((black_hole.global_position - eye).normalized()) > 0.999,
		"The close black hole is outside the bridge window sightline")
	print("SPACE_STAGE_WINDOW_OK planet viewport fit, annulus, receding Sun, Canary disk, far/near stages")
	for node in main.find_children("*", "AudioStreamPlayer", true, false):
		var audio_player := node as AudioStreamPlayer
		audio_player.stop()
		audio_player.stream = null
	main.free()
	await process_frame
	await process_frame
	quit(0)
