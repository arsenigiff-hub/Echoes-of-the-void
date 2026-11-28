extends SceneTree
## Tests live ray hits, press/drag/release, interlocked gates and mouse-only return.

const EVA := preload("res://scripts/shuttle_eva.gd")
var shuttle: Node3D
var player: Player
var eva: EVA
var failures: Array[String] = []
var captures := false
var outside_start := Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _wait_for_phase(wanted: EVA.Phase) -> bool:
	for frame in range(450):
		if eva.phase == wanted:
			return true
		await physics_frame
	return false


func _aim(target: Vector3) -> void:
	var direction := (target - player.camera.global_position).normalized()
	player.head.rotation.y = atan2(-direction.x, -direction.z)
	player.camera.rotation = Vector3(asin(direction.y), 0, 0)
	player.interaction_ray.force_raycast_update()


func _click(down: bool) -> void:
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.pressed = down
	root.push_input(input, true)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _photo(name: String) -> void:
	if captures:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.codex_qa/shuttle_eva/" + name + ".png")


func _run() -> void:
	captures = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	shuttle = (load("res://scenes/shuttle_blockout.tscn") as PackedScene).instantiate()
	root.add_child(shuttle)
	current_scene = shuttle
	player = shuttle.get_node("Player") as Player
	eva = shuttle.get_node("ShuttleEVA") as EVA
	eva.cycle_speed = 4.0
	player.position = Vector3(-1.64, 0.06, eva.port_z)
	_aim(Vector3(-3.78, 1.14, eva.port_z))
	await _frames(4)
	var hatch := shuttle.get_node("EvaHatch") as StaticBody3D
	_check(player.interaction_ray.get_collider() == hatch, "the sealed outer aperture must have a reachable collider")
	_check(not eva.request_exit(), "blackout must block the outer hatch")
	shuttle.call("set_powered", true)
	await _photo("01_closed")
	# Use the regular interaction entry point in headless mode (no OS capture),
	# and the actual left mouse click in the pictured game.
	if captures:
		_click(true)
		_click(false)
	else:
		shuttle.call("on_interact", "hatch", player)
	await _frames(25)
	var inner := eva.get_node("PortInnerGate") as AnimatableBody3D
	_check(eva.phase == EVA.Phase.DEPARTING and inner.position.x > -0.3 \
		and hatch.collision_layer == 1, "outer hatch released before the inner doors interlocked")
	if not await _wait_for_phase(EVA.Phase.OUTSIDE):
		_check(false, "exit cycle did not reach vacuum")
	else:
		outside_start = player.global_position
		_check(outside_start.x < -5.1 and player.eva_mouse_only and hatch.collision_layer == 0,
			"player did not move through the outer hatch into mouse-only EVA")
		await _photo("02_outside")
		await _test_grip()
		var ready := await _wait_for_phase(EVA.Phase.INTERIOR)
		_check(ready and not player.eva_mouse_only and not player.eva_mode and not player.is_interacting \
			and player.global_position.x > -2.28 and hatch.collision_layer == 1,
			"return did not restore the sealed, walkable airlock")
		if ready:
			await _photo("04_return")
	for message in failures:
		print("FAIL: ", message)
	print("SHUTTLE_EVA ", "OK" if failures.is_empty() else "FAIL", " failures=", failures.size())
	shuttle.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _test_grip() -> void:
	_aim(player.camera.global_position + Vector3(-8.0, 0.12, 0.0))
	_click(true)
	await _frames(4)
	_check(not eva.gripping, "clicking open space grabbed nothing")
	_click(false)
	var hit := {}
	for p in [Vector3(-3.95, 1.29, -0.83), Vector3(-3.72, 1.23, -1.16), Vector3(-3.50, 1.58, -1.40),
			Vector3(-3.73, 0.69, -0.76), Vector3(-3.70, 2.15, -1.0)]:
		_aim(Vector3(p.x, p.y, eva.port_z + p.z))
		await physics_frame
		hit = eva.call("_aim_surface")
		if not hit.is_empty() and not eva.call("_aim_at_door"):
			break
	_check(not hit.is_empty(), "no hull surface in reach from the exit")
	_click(true)
	await _frames(5)
	_check(eva.gripping and (eva.get("_hand") as TextureRect).visible, "press on the hull did not show the glove")
	var expected := Vector3.ZERO
	if eva.gripping:
		await _photo("03_grip")
		var eye := player.camera.global_basis
		var start := player.global_position
		var dx := Vector2(72, -39)
		expected = (-eye.x * dx.x + eye.y * dx.y).slide(hit["normal"]).normalized()
		var motion := InputEventMouseMotion.new()
		motion.relative = dx
		motion.screen_relative = dx
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await _frames(4)
		_check((player.global_position - start).dot(expected) > 0.03,
			"held-mouse drag did not pull the player opposite the cursor along the surface")
		_check(player.camera.global_basis.is_equal_approx(eye), "held drag also moved camera aim")
	_click(false)
	var released := player.global_position
	await _frames(10)
	_check(not eva.gripping and not (eva.get("_hand") as TextureRect).visible, "releasing mouse did not release grip")
	_check((player.global_position - released).dot(expected) > 0.11,
		"letting go after a fast pull lost the imparted inertia")
	await _test_momentum(hit)
	_aim(Vector3(-3.78, 1.16, eva.port_z))
	_click(true)
	await _frames(4)
	_click(false)
	_check(eva.phase == EVA.Phase.RETURNING or eva.phase == EVA.Phase.INTERIOR, "outer aperture cannot be clicked to return")


func _test_momentum(hit: Dictionary) -> void:
	var saved := player.global_position
	var mask := player.collision_mask
	# Isolate momentum and line constraints from hull contact.
	player.collision_mask = 0
	var pin: Vector3 = eva.call("_tether_pin") - Vector3.UP * 0.89
	player.global_position = pin + Vector3.LEFT
	eva.drift = Vector3.UP
	for tick in 30:
		eva.call("_apply_drift", 1.0 / 60.0)
	_check(eva.drift.is_equal_approx(Vector3.UP), "free drift lost momentum inside tether slack")
	player.global_position = pin + Vector3.LEFT * (EVA.TETHER_LENGTH - 0.01)
	eva.drift = Vector3.LEFT * 4.0
	eva.call("_apply_drift", 1.0 / 60.0)
	_check(player.global_position.distance_to(pin) <= EVA.TETHER_LENGTH + 0.001,
		"safety tether allowed travel beyond its length")
	_check(absf(eva.drift.x) < 0.001, "taut tether retained outward speed or bounced player")
	player.collision_mask = mask
	player.global_position = outside_start
	eva.drift = Vector3.ZERO
	if not hit.is_empty():
		_aim(hit["position"])
		await _frames(2)
		# A press, flick and release may all arrive before the next physics tick.
		_click(true)
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(28, -18)
		motion.screen_relative = motion.relative
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		_click(false)
		await _frames(2)
		_check(not eva.gripping and eva.drift.length() > 0.1,
			"a complete flick between physics ticks lost release momentum")
		eva.call("_grab", hit["position"], hit["normal"])
		var held := player.global_position
		await _frames(5)
		_check(player.global_position.distance_to(held) < 0.005 and eva.drift.is_zero_approx(),
			"a fresh grip failed to arrest free drift")
		motion.relative = Vector2(500, -250)
		motion.screen_relative = motion.relative
		root.push_input(motion, true)
		await _frames(2)
		held = player.global_position
		await _frames(5)
		_check(player.global_position.distance_to(held) < 0.005,
			"a flick continued replaying queued travel after the mouse stopped")
		eva.call("_notification", Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		_check(not eva.gripping, "losing window focus left the hand attached")
	player.global_position = saved
	eva.drift = Vector3.ZERO
