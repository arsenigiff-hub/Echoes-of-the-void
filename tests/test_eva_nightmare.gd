extends SceneTree
## Real hull proximity, safe idle/tether/grip cases, and an animated recovery cycle.

const EVA := preload("res://scripts/shuttle_eva.gd")
const RECOVERY := preload("res://scripts/eva_nightmare.gd")
var ship: Node3D
var eva: EVA
var recovery: RECOVERY
var player: Player
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _wait_phase(wanted: EVA.Phase, limit := 600) -> bool:
	for frame in limit:
		if eva.phase == wanted:
			return true
		await physics_frame
	return false


func _run() -> void:
	ship = (load("res://scenes/shuttle_blockout.tscn") as PackedScene).instantiate()
	root.add_child(ship)
	current_scene = ship
	player = ship.get_node("Player") as Player
	eva = ship.get_node("ShuttleEVA") as EVA
	recovery = eva.nightmare
	eva.cycle_speed = 8.0
	recovery.cinematic_speed = 12.0
	ship.call("set_powered", true)
	var instance := ship.get_instance_id()
	var reactor_ready: bool = ship.get("_reactor_ready")
	var initial_fov := player.camera.fov
	player.position = Vector3(-1.64, 0.06, eva.port_z)
	_check(eva.request_exit(), "could not begin real EVA before nightmare test")
	if not await _wait_phase(EVA.Phase.OUTSIDE):
		_check(false, "exit failed")
		_finish()
		return
	_check(not recovery.is_lost(), "standing on the platform triggered panic")
	# This surface is at the opposite end of the whole authored ship, far from the hatch.
	var hull := eva.get("_hull_root") as MeshInstance3D
	var faces := hull.mesh.get_faces()
	var bow := Vector3.INF
	var normal := Vector3.UP
	for i in range(0, faces.size(), 3):
		var point := hull.global_transform * ((faces[i] + faces[i+1] + faces[i+2]) / 3.0)
		if point.z < bow.z:
			bow = point
			normal = hull.global_basis * (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).normalized()
	player.global_position = bow + normal * 2.0 - Vector3.UP * 0.92
	eva.drift = normal * 2.0
	_check(not recovery.is_lost(), "hull exploration used distance from the hatch instead of the surface")
	var far := Vector3(-20, 0.5, eva.port_z - 4)
	player.global_position = far
	eva.drift = Vector3.ZERO
	for frame in 240:
		await physics_frame
	_check(eva.phase == EVA.Phase.OUTSIDE and not recovery.active \
		and player.global_position.distance_to(far) < 0.001, "idle free-floating player was treated as lost after a timeout")
	eva.drift = Vector3.RIGHT * 2.0
	_check(not recovery.is_lost(), "movement back toward the ship triggered panic")
	eva.drift = Vector3.UP
	_check(not recovery.is_lost(), "sideways movement was treated as outward drift")
	eva.drift = Vector3.LEFT * 2.0
	eva.gripping = true
	_check(not recovery.is_lost(), "attached hand did not suppress panic")
	eva.gripping = false
	eva.tether_attached = true
	_check(not recovery.is_lost(), "attached rope did not suppress panic")
	eva.tether_attached = false
	_check(recovery.is_lost(), "unattached outward drift more than eight metres away was not detected")
	for frame in 60:
		if recovery.active:
			break
		await physics_frame
	_check(recovery.active and eva.phase == EVA.Phase.NIGHTMARE and player.is_interacting,
		"loss did not start the cinematic and lock normal controls")
	_check(not (ship.get_node("Hud") as CanvasLayer).visible, "ordinary gameplay hints remained over the nightmare")
	var head := player.head.rotation
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(300, -200)
	root.push_input(motion, true)
	_check(player.head.rotation.is_equal_approx(head), "mouse input fought the authored panic animation")
	for frame in 120:
		if recovery.blackout >= 0.999:
			break
		await physics_frame
	_check(recovery.blackout >= 0.999, "panic did not reach a full black frame")
	_check(not player.eva_mode and not player.eva_mouse_only and not eva.tether_attached \
		and (ship.get_node("EvaHatch") as StaticBody3D).collision_layer == 1,
		"full blackout did not reset the space state and close the hatch")
	for frame in 120:
		if recovery.stage == RECOVERY.Stage.WAKING:
			break
		await physics_frame
	_check(recovery.stage == RECOVERY.Stage.WAKING and player.camera.global_position.x < -0.8,
		"opening eyes did not place the view inside the sleep capsule")
	for frame in 240:
		if not recovery.active:
			break
		await physics_frame
	_check(not recovery.active and recovery.recovery_count == 1 and eva.phase == EVA.Phase.INTERIOR,
		"waking did not finish once inside the ship")
	_check((ship.get_node("Hud") as CanvasLayer).visible, "waking did not restore the game interface")
	_check(not player.is_interacting and not player.camera_position_managed \
		and player.camera.position.length() < 0.03 and absf(player.camera.fov - initial_fov) < 0.01,
		"waking did not restore normal camera and walking controls")
	_check(ship.get_instance_id() == instance and bool(ship.get("powered")) \
		and bool(ship.get("_reactor_ready")) == reactor_ready, "nightmare reloaded the scene or lost repair/power progress")
	_check(not player.test_move(player.global_transform, Vector3(0, 0, 0.6)), "player woke inside furniture and cannot walk away")
	player.position = Vector3(-1.64, 0.06, eva.port_z)
	_check(eva.request_exit(), "another EVA could not start after recovery")
	_check(await _wait_phase(EVA.Phase.OUTSIDE), "airlock did not work on the next EVA")
	eva.call("_arrive")
	_check(await _wait_phase(EVA.Phase.INTERIOR), "normal airlock return failed after a nightmare")
	_finish()


func _finish() -> void:
	for message in failures:
		print("FAIL: ", message)
	print("EVA_NIGHTMARE ", "OK" if failures.is_empty() else "FAIL", " failures=", failures.size())
	ship.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
