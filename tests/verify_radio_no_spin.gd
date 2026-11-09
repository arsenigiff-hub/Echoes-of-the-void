extends SceneTree

# Проверка: при фокусе на радио камера не должна делать лишний оборот,
# с какой бы стороны игрок ни стоял и куда бы ни был накручен head.rotation.y.
# Запуск: godot --headless --path D:\4 --script res://tests/verify_radio_no_spin.gd
# Канонический регресс из AGENTS.md/AI_CHAT_RULES.md §6. Копия из .codex_qa/radio_focus.

var checks := {}
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
	await create_timer(1.2).timeout

	player = main.get_node("Player") as CharacterBody3D
	radio = main.get_node("Radio") as Node3D
	head = player.get_node("Head") as Node3D
	camera = player.get_node("Head/Camera3D") as Camera3D
	ray = player.get_node("Head/Camera3D/RayCast3D") as RayCast3D

	var floor_y: float = player.global_position.y
	var radio_pos := radio.global_position

	# «слева» и «справа» от радио, обе точки — перед прибором.
	var spots := {
		"left": Vector3(radio_pos.x - 1.85, floor_y, radio_pos.z - 0.85),
		"right": Vector3(radio_pos.x + 1.85, floor_y, radio_pos.z - 0.85),
	}

	for side in spots:
		var spot: Vector3 = spots[side]
		player.global_position = spot
		player.velocity = Vector3.ZERO
		await create_timer(0.4).timeout

		_aim_at_radio()
		# Имитируем игрока, который до этого крутился мышью: тот же взгляд,
		# но накопленный yaw отличается на полный оборот.
		head.rotation.y += TAU
		ray.force_raycast_update()
		checks["%s_ray_hits" % side] = ray.get_collider() == radio
		checks["%s_start_yaw_deg" % side] = snappedf(rad_to_deg(head.rotation.y), 0.1)

		# --- вход ---
		player._unhandled_input(_key(KEY_E))
		var enter := await _measure(1.2)
		checks["%s_enter" % side] = radio.get("is_at_radio") == true
		checks["%s_enter_yaw_travel_deg" % side] = snappedf(rad_to_deg(enter["travel"]), 0.1)
		checks["%s_enter_max_step_deg" % side] = snappedf(rad_to_deg(enter["max_step"]), 0.1)
		checks["%s_no_spin_enter" % side] = enter["travel"] < 4.0

		# --- выход ---
		player._unhandled_input(_key(KEY_E))
		var exit := await _measure(1.2)
		checks["%s_exit" % side] = radio.get("is_at_radio") == false
		checks["%s_exit_yaw_travel_deg" % side] = snappedf(rad_to_deg(exit["travel"]), 0.1)
		checks["%s_exit_max_step_deg" % side] = snappedf(rad_to_deg(exit["max_step"]), 0.1)
		checks["%s_no_spin_exit" % side] = exit["travel"] < 4.0

		await _wait_idle()

	print("=== CHECKS ===")
	print(JSON.stringify(checks, "  "))
	quit()


## Считает, сколько всего градусов повернулась голова за реальное время.
func _measure(seconds: float) -> Dictionary:
	var prev: float = head.rotation.y
	var travel := 0.0
	var max_step := 0.0
	var start_ms := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start_ms < int(seconds * 1000.0):
		await process_frame
		var now: float = head.rotation.y
		var step := absf(now - prev)
		travel += step
		max_step = maxf(max_step, step)
		prev = now
	return {"travel": travel, "max_step": max_step}


func _wait_idle() -> void:
	while (radio.get("is_moving") as bool) or (radio.get("is_at_radio") as bool):
		await process_frame


func _aim_at_radio() -> void:
	var aim: Vector3 = (radio.get_node("CollisionShape3D") as Node3D).global_position
	var eye: Vector3 = player.global_position + Vector3(0, 1.5, 0)
	var dir: Vector3 = (aim - eye).normalized()
	head.rotation.y = atan2(-dir.x, -dir.z) - player.rotation.y
	camera.rotation.x = asin(clampf(dir.y, -1.0, 1.0))
	ray.force_raycast_update()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	event.physical_keycode = code
	return event
