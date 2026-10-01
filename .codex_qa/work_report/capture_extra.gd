extends SceneTree

const OUT = "D:/godot/GodotGame-main/.codex_qa/work_report/screens/"

func _initialize() -> void:
	call_deferred("run")

func shot(name: String) -> void:
	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")

func run() -> void:
	root.size = Vector2i(1680, 1050)
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	menu.get_node("earth/Atmosphere").set_process(false)
	await shot("12_menu_dither_on")
	menu.get_node("CanvasLayer/ColorRect").hide()
	await shot("13_menu_dither_off")
	menu.queue_free()
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var player = main.get_node("Player")
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var camera = player.get_node("Head/Camera3D")
	camera.make_current()
	for i in range(120):
		player._physics_process(1.0 / 60.0)
	camera.look_at(Vector3(26.65, 3.5, -10.0))
	var lamp = player.get_node("Head/Camera3D/SpotLight3D")
	lamp.visible = false
	await shot("14_flashlight_off")
	lamp.visible = true
	await shot("15_flashlight_on")
	quit()
