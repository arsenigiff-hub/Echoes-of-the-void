extends SceneTree

const OUT = "D:/godot/GodotGame-main/.codex_qa/work_report/screens"
var checks: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func frames(n: int = 5) -> void:
	for i in range(n):
		await process_frame
	await RenderingServer.frame_post_draw

func shot(name: String) -> void:
	await frames()
	var img = root.get_texture().get_image()
	checks[name + "_save"] = img.save_png(OUT + "/" + name + ".png")

func open_scene(path: String) -> Node:
	var s = load(path).instantiate()
	root.add_child(s)
	current_scene = s
	return s

func close_scene(s: Node) -> void:
	s.queue_free()
	await process_frame

func key(code: int) -> InputEventKey:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size = Vector2i(1680, 1050)
	var menu = open_scene("res://scenes/main_menu.tscn")
	checks["menu_animation"] = menu.get_node("AnimationPlayer").has_animation("new_animation")
	await shot("01_menu")
	menu.get_node("AnimationPlayer").play("new_animation")
	menu.get_node("AnimationPlayer").seek(0.3, true)
	menu.get_node("AnimationPlayer").pause()
	menu.get_node("CanvasLayer/MenuButtons").hide()
	await shot("02_menu_transition")
	await close_scene(menu)
	var intro = open_scene("res://scenes/intro_cutscene.tscn")
	checks["intro_takeoff_exists"] = intro.get_node("AnimationPlayer").has_animation("takeoff")
	checks["intro_animations"] = intro.get_node("AnimationPlayer").get_animation_list()
	checks["intro_audio_playing"] = intro.get_node("EngineSound").playing
	await shot("03_intro")
	await close_scene(intro)
	var main = open_scene("res://scenes/main.tscn")
	var player = main.get_node("Player")
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var camera = player.get_node("Head/Camera3D")
	camera.make_current()
	var radio = main.get_node("Level/radio_v03/StaticBody3D")
	var lamp = player.get_node("Head/Camera3D/SpotLight3D")
	checks["player_start_position"] = str(player.global_position)
	checks["flashlight_initial_visible"] = lamp.visible
	checks["flashlight_initial_flag"] = player.flashlight_flag
	checks["scene_camera_current"] = str(root.get_camera_3d().get_path())
	checks["collision_bodies"] = []
	for n in main.find_children("*", "CollisionObject3D", true, false):
		checks["collision_bodies"].append(str(n.get_path()))
	await shot("04_main_start")
	lamp.visible = false
	camera.look_at(Vector3(26.65, 3.6, -10.0))
	await shot("05_interior_no_flashlight")
	player._unhandled_input(key(KEY_F))
	checks["flashlight_first_press_visible"] = lamp.visible
	await shot("06_interior_flashlight")
	player._unhandled_input(key(KEY_F))
	checks["flashlight_second_press_visible"] = lamp.visible
	var saved_pos = player.global_position
	for i in range(120):
		player._physics_process(1.0 / 60.0)
	checks["player_position_after_two_seconds"] = str(player.global_position)
	checks["floor_after_two_seconds"] = player.is_on_floor()
	camera.look_at(Vector3(26.65, 3.5, -10.0))
	lamp.visible = false
	await shot("09_main_after_landing")
	var diag_cam = Camera3D.new()
	main.add_child(diag_cam)
	diag_cam.global_position = Vector3(26.7, 3.7, -0.4)
	diag_cam.look_at(Vector3(26.7, 3.6, -10.0))
	diag_cam.make_current()
	await shot("10_corridor_overview")
	diag_cam.global_position = Vector3(26.7, 3.6, -10.5)
	diag_cam.look_at(Vector3(26.7, 3.7, -1.0))
	await shot("11_corridor_reverse")
	camera.make_current()
	diag_cam.queue_free()
	player.global_position = saved_pos
	player.velocity = Vector3.ZERO
	camera.look_at(radio.get_node("CollisionShape3D").global_position)
	var ray = player.get_node("Head/Camera3D/RayCast3D")
	ray.force_raycast_update()
	checks["ray_collision_before_interaction"] = ray.is_colliding()
	checks["ray_collider_before_interaction"] = str(ray.get_collider())
	player._try_interact()
	checks["interaction_entered_via_ray"] = player.is_interacting
	if not player.is_interacting:
		player.interacting_object = radio
		radio.interact(player)
		checks["radio_direct_call_for_capture"] = true
	await create_timer(0.7).timeout
	checks["radio_enter_state"] = player.is_interacting
	checks["radio_enter_speed"] = player.speed
	await shot("07_radio_focus")
	var knob = main.get_node("Level/radio_v03/Radio_TuningKnob_001")
	checks["knob_before"] = str(knob.rotation)
	player._unhandled_input(key(KEY_D))
	checks["knob_after"] = str(knob.rotation)
	await shot("08_radio_knob")
	ray.force_raycast_update()
	checks["ray_collision_at_radio"] = ray.is_colliding()
	checks["ray_collider_at_radio"] = str(ray.get_collider())
	player._unhandled_input(key(KEY_E))
	await create_timer(0.7).timeout
	checks["radio_exited_via_e"] = not player.is_interacting
	if player.is_interacting:
		radio.interact(player)
		await create_timer(0.7).timeout
	checks["radio_restored_speed"] = player.speed
	checks["radio_restored_state"] = player.is_interacting
	player.global_position = Vector3(27.3, 2.2, -5.7)
	camera.look_at(radio.get_node("CollisionShape3D").global_position)
	ray.force_raycast_update()
	checks["controlled_ray_colliding"] = ray.is_colliding()
	checks["controlled_ray_collider_is_radio"] = ray.get_collider() == radio
	player._unhandled_input(key(KEY_E))
	await create_timer(0.7).timeout
	checks["controlled_e_enters_radio"] = player.is_interacting
	if player.is_interacting:
		radio.interact(player)
		await create_timer(0.7).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await close_scene(main)
	var f = FileAccess.open("D:/godot/GodotGame-main/.codex_qa/work_report/checks.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(checks, "\t"))
	f.close()
	quit()
