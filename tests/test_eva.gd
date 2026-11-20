extends SceneTree

# Визуальные кадры физического шлюза. Проходимость и переход EVA проверяет
# test_ship_layout_b.gd через настоящий Player.move_and_slide().
const OUT := "res://.codex_qa/eva"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(2.0).timeout
	var eva := main.get_node("EVA")
	var interior := main.get_node("ShipInterior") as Node3D
	var camera := Camera3D.new()
	camera.fov = 72.0
	main.add_child(camera)
	camera.current = true
	
	await _capture(camera, "eva_01_inside_airlock",
		interior.to_global(Vector3(0.8, 1.62, 3.55)),
		interior.to_global(Vector3(2.3, 1.18, 5.0)))
	eva.call("_spin_door_open")
	await create_timer(1.2).timeout
	await _capture(camera, "eva_02_inner_door_open",
		interior.to_global(Vector3(0.8, 1.62, 3.55)),
		interior.to_global(Vector3(2.8, 1.25, 5.1)))
	eva.call("_set_exterior_visible", true)
	eva.call("_set_outer_hatch_open", true)
	await create_timer(1.5).timeout
	await _capture(camera, "eva_03_open_passage_from_inside",
		interior.to_global(Vector3(3.3, 1.62, 5.4)), Vector3(-8.47, 3.3, 11.9))
	# The next camera is outside the hull. Simulate crossing the outer trigger so
	# the screenshot uses the same ambient and EVA light state as live gameplay.
	var player := main.get_node("Player") as Player
	player.velocity.x = -0.2
	eva.call("_on_outer_threshold", player)
	await process_frame
	assert(eva.get("is_outside") == true, "The exterior screenshot must simulate the EVA threshold crossing")
	await create_timer(1.15).timeout
	var world := main.get_node("WorldEnvironment") as WorldEnvironment
	assert(world.environment.ambient_light_energy > 1.2, "The exterior screenshot must use outdoor ambient light")
	await _capture(camera, "eva_04_outer_hatch_open",
		Vector3(-12.4, 5.2, 15.4), Vector3(-8.48, 3.3, 11.9))
	eva.call("_set_outer_hatch_open", false)
	await create_timer(1.2).timeout
	await _capture(camera, "eva_05_outer_hatch_closed",
		Vector3(-12.4, 5.2, 15.4), Vector3(-8.48, 3.3, 11.9))
	print("EVA_VISUAL_FRAMES ", OUT)
	main.queue_free()
	await process_frame
	quit()

func _capture(camera: Camera3D, name: String, position: Vector3, target: Vector3) -> void:
	camera.global_position = position
	camera.look_at(target, Vector3.UP)
	camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")
	print("SAVED ", name)
