extends SceneTree

# QA выхода в космос: кадры «шлюз → выход → корабль снаружи → возврат».
# Запуск: godot --path D:\4 --resolution 1680x1050 --script res://tests/test_eva.gd
# Кадры складываются в .codex_qa/eva/ (черновики вне git). Копия из .codex_qa/eva.

const OUT := "res://.codex_qa/eva"

var main: Node3D
var player: Player
var eva: Node
var head: Node3D
var camera: Camera3D


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(1.6).timeout

	player = main.get_node("Player") as Player
	eva = main.get_node_or_null("EVA")
	head = player.get_node("Head") as Node3D
	camera = player.get_node("Head/Camera3D") as Camera3D
	player.set_process_unhandled_input(false)
	var spawn_y := player.global_position.y

	if eva == null:
		print("НЕТ EVA")
		quit()
		return

	_place(Vector3(-5.1, spawn_y, 11.9), Vector3(-7.7, 3.2, 11.9))
	await _shoot("eva_01_inside_airlock")

	eva.request_airlock(player)
	await create_timer(4.6).timeout
	print("after_exit eva_mode=", player.eva_mode, " pos=", player.global_position)
	await _shoot("eva_02_exit")

	player.global_position = Vector3(-11.8, 3.2, 11.9)
	_look(Vector3(-8.2, 3.2, 11.9))
	await create_timer(0.5).timeout
	await _shoot("eva_05_hatch")

	player.global_position = Vector3(-25.0, 8.5, 4.0)
	_look(Vector3(2.5, 5.0, 11.9))
	await create_timer(0.6).timeout
	await _shoot("eva_03_ship_outside")

	player.global_position = eva.exit_pos
	await create_timer(0.3).timeout
	eva.request_airlock(player)
	await create_timer(4.6).timeout
	print("after_enter eva_mode=", player.eva_mode)
	await _shoot("eva_04_back_inside")

	print("=== done ===")
	quit()


func _place(pos: Vector3, look: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	_look(look)


func _look(target: Vector3) -> void:
	var pos := player.global_position + Vector3(0, 1.5, 0)
	var direction: Vector3 = (target - pos).normalized()
	head.rotation.y = atan2(-direction.x, -direction.z)
	camera.rotation.x = asin(clampf(direction.y, -1.0, 1.0))


func _shoot(shot_name: String) -> void:
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
