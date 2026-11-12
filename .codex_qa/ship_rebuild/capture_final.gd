extends SceneTree

# Финальные кадры нового корабля (от лица игрока) + замер fps.
# Запуск: godot --path D:\4 --resolution 1680x1050 --script res://.codex_qa/ship_rebuild/capture_final.gd

const OUT := "res://.codex_qa/ship_rebuild"

var main: Node3D
var player: CharacterBody3D
var radio: Node3D
var head: Node3D
var camera: Camera3D
var ray: RayCast3D


func _initialize() -> void:
	_run()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(1.4).timeout

	player = main.get_node("Player") as CharacterBody3D
	radio = main.get_node("Radio") as Node3D
	head = player.get_node("Head") as Node3D
	camera = player.get_node("Head/Camera3D") as Camera3D
	ray = player.get_node("Head/Camera3D/RayCast3D") as RayCast3D
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var floor_y: float = player.global_position.y

	# 1. коридор от спавна
	_place(Vector3(3.18, floor_y, 12.48), Vector3(10.0, 3.25, 11.9))
	await _shoot("final_01_corridor_forward")

	# 2. назад: дверь B-3 в тумане
	_place(Vector3(3.18, floor_y, 12.48), Vector3(-6.0, 3.2, 11.9))
	await _shoot("final_02_corridor_b3")

	# 3. мостик: панорамные окна и консоли
	_place(Vector3(9.8, floor_y, 11.9), Vector3(14.8, 4.0, 11.9))
	await _shoot("final_03_bridge")

	# 4. ближе к окну: планета за стеклом
	_place(Vector3(12.4, floor_y, 11.9), Vector3(16.0, 4.0, 11.4))
	await _shoot("final_04_bridge_planet")

	# 5. радио крупным планом (через фокус)
	_place(Vector3(4.73, floor_y, 11.95), Vector3(4.73, 3.22, 13.0))
	ray.force_raycast_update()
	if ray.get_collider() == radio:
		player._unhandled_input(_key(KEY_E))
		await create_timer(1.2).timeout
	await _shoot("final_05_radio")
	# выходим из фокуса
	player._unhandled_input(_key(KEY_E))
	await create_timer(1.2).timeout

	# 6. вид в шлюзовую часть (закрытая дверь B-3)
	_place(Vector3(-1.6, floor_y, 11.9), Vector3(-7.6, 3.2, 11.9))
	await _shoot("final_06_b3_door")

	# 10. койка крупно
	_place(Vector3(4.35, floor_y, 9.85), Vector3(5.15, 3.25, 7.9))
	await _shoot("final_10_bunk")

	# 9. дверь B-3 крупно
	_place(Vector3(-2.1, floor_y, 11.9), Vector3(-3.72, 3.35, 11.9))
	await _shoot("final_09_b3_close")

	# 11. новый шлюз
	_place(Vector3(-4.6, floor_y, 11.9), Vector3(-7.7, 3.2, 11.9))
	await _shoot("final_11_airlock")

	# 7-8. каюта экипажа
	_place(Vector3(5.0, floor_y, 11.6), Vector3(4.9, 3.2, 8.2))
	await _shoot("final_07_quarters_door")
	_place(Vector3(4.0, floor_y, 9.7), Vector3(6.3, 3.1, 7.5))
	await _shoot("final_08_quarters_inside")

	# fps
	_place(Vector3(0.0, floor_y, 11.9), Vector3(12.0, 3.2, 11.9))
	var frames := 0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 3500:
		await process_frame
		frames += 1
	print("fps ~ ", snappedf(frames / ((Time.get_ticks_msec() - start) / 1000.0), 0.1))

	print("=== done ===")
	quit()


func _place(pos: Vector3, look_at: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	var direction: Vector3 = (look_at - (pos + Vector3(0, 1.5, 0))).normalized()
	head.rotation.y = atan2(-direction.x, -direction.z) - player.rotation.y
	camera.rotation.x = asin(clampf(direction.y, -1.0, 1.0))


func _shoot(shot_name: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.physical_keycode = code
	return event
