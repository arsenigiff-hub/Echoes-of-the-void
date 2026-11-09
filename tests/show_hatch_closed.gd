extends SceneTree

# Кадр закрытого люка снаружи: как в эталоне пользователя.
# Запуск: godot --path D:\4 --resolution 1680x1050 --script res://tests/show_hatch_closed.gd
# Кадры складываются в .codex_qa/eva/ (черновики вне git). Копия из .codex_qa/eva.

var main: Node3D
var player: Player
var head: Node3D
var camera: Camera3D


func _initialize() -> void:
	_run()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(1.6).timeout
	player = main.get_node("Player") as Player
	head = player.get_node("Head") as Node3D
	camera = player.get_node("Head/Camera3D") as Camera3D
	player.set_process_unhandled_input(false)

	# показать корабль и люк, спрятать интерьер (как в EVA)
	var interior := main.get_node_or_null("ShipInterior") as Node3D
	var ship := main.get_node_or_null("ShipExterior") as Node3D
	var hatch := main.get_node_or_null("AirlockExterior") as Node3D
	if interior != null:
		interior.visible = false
	if ship != null:
		ship.visible = true
	if hatch != null:
		hatch.visible = true
	for n in ["EVAShipLight", "EVAHatchLight"]:
		var l := main.get_node_or_null(n) as OmniLight3D
		if l != null:
			l.visible = true
	var we := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.ambient_light_energy = 1.3
	await create_timer(0.6).timeout

	_place(Vector3(-13.6, 3.5, 11.9), Vector3(-8.47, 3.3, 11.9))
	await _shoot("hatch_closed_wide")
	_place(Vector3(-11.4, 3.4, 11.9), Vector3(-8.56, 3.3, 11.9))
	await _shoot("hatch_closed_close")
	print("=== done ===")
	quit()


func _place(pos: Vector3, look: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	var direction: Vector3 = (look - (pos + Vector3(0, 1.5, 0))).normalized()
	head.rotation.y = atan2(-direction.x, -direction.z)
	camera.rotation.x = asin(clampf(direction.y, -1.0, 1.0))


func _shoot(shot_name: String) -> void:
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.codex_qa/eva/%s.png" % shot_name)
	print("saved ", shot_name)
