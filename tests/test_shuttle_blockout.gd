extends SceneTree
## Walks the new linear shuttle blockout from the galley to the stern airlock and
## then all the way to the cockpit through every pressure hatch (no teleports).

const FRAME_STEP := 1.0 / 60.0
const REACTOR_HOLD_SECONDS := 4.0
const WIRING := preload("res://scripts/reactor_wiring.gd")
var scene: Node3D
var player: Player
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _walk_to(target: Vector3, frames: int = 1800) -> bool:
	for _frame in frames:
		var offset := target - player.global_position
		offset.y = 0.0
		if offset.length() <= 0.1:
			player.velocity = Vector3.ZERO
			await physics_frame
			return true
		var direction := offset.normalized()
		player.velocity.x = direction.x * 2.4
		player.velocity.z = direction.z * 2.4
		if not player.is_on_floor():
			player.velocity.y -= 9.8 * FRAME_STEP
		else:
			player.velocity.y = 0.0
		player.move_horizontal_with_step(FRAME_STEP)
		await physics_frame
	return false


func _press(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	player.call("_unhandled_input", event)


func _aim_at(target: Node3D) -> bool:
	var camera := player.get_node("Head/Camera3D") as Camera3D
	camera.look_at(target.global_position)
	player.interaction_ray.force_raycast_update()
	return player.interaction_ray.get_collider() == target


func _start_reactor() -> bool:
	var control := scene.find_child("ReactorStarterControl", true, false) as Node3D
	if control == null or not (control is Interactable) or scene.get_node("TripoReactorBody") is Interactable:
		failures.append("only the physical startup control should be interactable")
		return false
	if not await _walk_to(Vector3(-0.13, player.global_position.y, control.global_position.z)) or not _aim_at(control):
		failures.append("could not reach and aim at the starter from the aisle")
		return false
	var panel := scene.get_node("Hud/ReactorStartup") as Control
	_press(KEY_E)
	if not player.is_interacting or not panel.visible:
		failures.append("reactor interaction did not open the regulator")
		return false
	var timer := panel.get("_timer") as Label
	if timer == null or timer.text != ("0.0 / %.1f с" % REACTOR_HOLD_SECONDS):
		failures.append("the reactor timer does not show the four-second target")
	panel.set_process(false)
	for i in range(30):
		panel.call("advance", 0.05, 1.0)
	if scene.get("_reactor_ready") or float(panel.get("held_seconds")) > 0.0:
		failures.append("overshooting the working zone did not reset stabilization")
	_press(KEY_ESCAPE)
	if player.is_interacting or panel.visible or scene.get("_reactor_ready"):
		failures.append("Esc did not cancel the reactor startup")
		return false

	var zone_rng: RandomNumberGenerator = panel.get("_zone_rng")
	zone_rng.seed = 47
	_aim_at(control)
	_press(KEY_E)
	panel.set_process(false)
	var travel := 0.0
	var needle := scene.find_child("StarterNeedle", true, false) as Node3D
	var arc := scene.find_child("StarterZone", true, false) as Node3D
	for i in range(900):
		var level: float = panel.get("level")
		var zone: float = panel.get("zone_center")
		var error := zone - level
		panel.call("advance", FRAME_STEP, signf(error) if absf(error) > 0.012 else 0.0)
		travel += absf(float(panel.get("zone_center")) - zone)
		if i == 60:
			var needle_angle := deg_to_rad(lerpf(110.0, -110.0, panel.get("level")))
			var zone_angle := deg_to_rad(lerpf(110.0, -110.0, panel.get("zone_center")))
			if needle == null or arc == null or not is_equal_approx(needle.rotation.z, needle_angle) \
					or not is_equal_approx(arc.rotation.z, zone_angle):
				failures.append("the physical dial does not match the moving HUD")
		if not panel.visible:
			break
	var held: float = panel.get("held_seconds")
	if travel < 1.0 or held < REACTOR_HOLD_SECONDS or held > REACTOR_HOLD_SECONDS + FRAME_STEP + 0.0001 \
			or panel.visible or player.is_interacting or not scene.get("_reactor_ready"):
		failures.append("startup did not complete after four seconds of tracking the moving zone")
		return false
	return true


func _mouse_at(position: Vector2, pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = position
	click.pressed = pressed
	root.push_input(click, true)


func _drag_wire(wiring: WIRING, left: int, right: int) -> void:
	var camera := root.get_camera_3d()
	var source: Vector3 = wiring.call("_rest_tip", left)
	var socket: Vector3 = wiring.call("_socket", right)
	socket.x = 0.265 # Dropping over the engraved tile is allowed, not just the small socket.
	var first := camera.unproject_position(wiring.to_global(source))
	var last := camera.unproject_position(wiring.to_global(socket))
	_mouse_at(first, true)
	var motion := InputEventMouseMotion.new()
	motion.position = last
	motion.relative = last - first
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	var wire := wiring.get_node("Wire_%s" % WIRING.LEFT[left]) as MeshInstance3D
	var tip := wire.get_node("Tip") as MeshInstance3D
	if tip.position.x < 0.18 or wire.mesh == null or wire.mesh.get_surface_count() != 1:
		failures.append("pointer drag did not move a 3D wire to the right terminal")
	_mouse_at(last, false)


func _repair_breaker(breaker: Node3D) -> bool:
	var wiring := scene.get_node("ReactorBreakerCabinet") as WIRING
	_press(KEY_E)
	await create_timer(0.60).timeout
	var hinge := wiring.find_child("DoorPivot", true, false) as Node3D
	if not wiring.is_focused() or not player.is_interacting or root.get_camera_3d() == player.camera \
			or hinge == null or hinge.rotation_degrees.y > -90.0 or scene.get("powered"):
		failures.append("breaker repair did not open the physical door and take camera focus in blackout")
		return false
	_drag_wire(wiring, 7, 7) # Moon -> cross is the mismatch on the generated art reference.
	await create_timer(0.25).timeout
	var moon_tip := wiring.get_node("Wire_moon/Tip") as MeshInstance3D
	if wiring.connected_count != 0 or moon_tip.position.x > 0.0:
		failures.append("wrong symbol was accepted or the loose wire did not retreat")
	_drag_wire(wiring, 7, 8) # Moon -> moon.
	var leave := InputEventKey.new()
	leave.keycode = KEY_ESCAPE
	leave.pressed = true
	root.push_input(leave, true)
	await create_timer(0.55).timeout
	if wiring.connected_count != 1 or not is_zero_approx(hinge.rotation.y) or wiring.is_focused() \
			or player.is_interacting or root.get_camera_3d() != player.camera or not _aim_at(breaker):
		failures.append("Esc lost the matched pair or did not return the camera and movement")
		return false
	_press(KEY_E)
	await create_timer(0.60).timeout
	# Explicit order by symbol, independent of the controller's matching table.
	var destinations := [2, 7, 3, 0, 9, 1, 5, 8, 4, 6]
	for left in destinations.size():
		if left == 7:
			continue
		_drag_wire(wiring, left, destinations[left])
		if left < 9 and scene.get("powered"):
			failures.append("board power returned before all ten wires were connected")
	await create_timer(0.9).timeout
	if wiring.connected_count != 10 or not wiring.is_repaired() or player.is_interacting or wiring.is_focused():
		failures.append("repair did not commit all ten pairs and leave the panel")
		return false
	return _aim_at(breaker)


func _test_power(reactor: Vector2, beam: SpotLight3D) -> void:
	var environment: Environment = scene.get("_environment")
	var med_light := scene.get_node("MedTube") as OmniLight3D
	var fixture := scene.get_node("MedLamp").get_child(0) as MeshInstance3D
	var glow := fixture.material_override as BaseMaterial3D
	var machinery := scene.get_node("Reactor_Loop") as AudioStreamPlayer3D
	if scene.get("powered") or environment.ambient_light_energy != 0.0 or glow.emission_enabled:
		failures.append("the shuttle is not in blackout at startup")
	if machinery.playing or not is_zero_approx(float(scene.get("_rotor_speed"))):
		failures.append("reactor machinery runs without power")
	if beam != null and (beam.is_visible_in_tree() or beam.light_energy != 0.0):
		failures.append("the exam lamp is lit without power")

	_press(KEY_F)
	if not player.flashlight.is_visible_in_tree():
		failures.append("the personal flashlight cannot be used during the blackout")
	if not await _walk_to(Vector3(0.0, player.global_position.y, reactor.x + 0.38)):
		failures.append("could not reach the breaker during the blackout")
		return
	var breaker := scene.get_node("BreakerPanel") as Node3D
	if not _aim_at(breaker):
		failures.append("could not aim at the breaker from the aisle")
		return

	_press(KEY_E)
	var objective := scene.get_node("Hud/PowerObjective") as Label
	if scene.get("powered") or objective.text != "Запустите реактор":
		failures.append("the cold reactor was bypassed or the breaker did not give a next step")
	if not await _start_reactor():
		return
	if scene.get("powered") or machinery.playing or not is_zero_approx(environment.ambient_light_energy) \
			or objective.text != "Подайте питание на щите":
		failures.append("starting the reactor should only prepare the breaker")
	if not await _walk_to(Vector3(0.0, player.global_position.y, reactor.x + 0.38)) or not _aim_at(breaker):
		failures.append("could not return to the breaker after stabilization")
		return

	if not await _repair_breaker(breaker):
		failures.append("could not complete the in-world breaker repair")
		return
	if not scene.get("powered") or not is_equal_approx(environment.ambient_light_energy, 0.35) or objective.visible:
		failures.append("the breaker did not restore the authored ambient light")
	if not glow.emission_enabled or not med_light.is_visible_in_tree() or not is_equal_approx(med_light.light_energy, 0.7):
		failures.append("the breaker did not restore the original medbay tube")
	if beam != null and (not beam.is_visible_in_tree() or not is_equal_approx(beam.light_energy, 1.25)):
		failures.append("the breaker did not turn on the exam lamp")
	await create_timer(0.1).timeout
	if not machinery.playing or float(scene.get("_rotor_speed")) <= 0.0:
		failures.append("reactor machinery did not start with power")

	_press(KEY_E)
	if scene.get("powered") or glow.emission_enabled or med_light.is_visible_in_tree() or machinery.playing or not objective.visible:
		failures.append("turning the breaker off did not shut down the shuttle")
	if not is_zero_approx(float(scene.get("_rotor_speed"))) or not player.flashlight.is_visible_in_tree():
		failures.append("the rotor and the personal flashlight did not respond independently")
	_press(KEY_E)
	if not scene.get("powered") or player.is_interacting:
		failures.append("turning a repaired breaker back on incorrectly required another repair")
	_press(KEY_E)
	_press(KEY_F)


func _run() -> void:
	scene = (load("res://scenes/shuttle_blockout.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.0).timeout
	player = scene.get_node("Player") as Player
	player.set_physics_process(false)
	await physics_frame
	var length: float = scene.call("total_length")
	if length < 30.0 or length > 36.0:
		failures.append("shuttle length %.2f outside 30-36 m" % length)
	var ranges: Dictionary = scene.get("compartment_ranges")
	var beam := scene.get_node_or_null("MedbayExamLamp/ExamBeam") as SpotLight3D
	await _test_power(ranges["Reactor"], beam)
	var order := ["Airlock", "Cockpit"]
	for label in order:
		var span: Vector2 = ranges[label]
		var target := Vector3(0.0, player.global_position.y, (span.x + span.y) * 0.5)
		var ok: bool = await _walk_to(target)
		if not ok:
			failures.append("could not walk to %s (stopped at %s)" % [label, player.global_position])
			break
		if player.global_position.y > 0.4 or player.global_position.y < -0.2:
			failures.append("%s: unexpected height %.2f" % [label, player.global_position.y])
	# Interaction hooks: props remain Interactables in the dark.
	for label in ["BreakerPanel", "NavConsole", "RadioDesk", "SleepCapsule", "EvaHatch", "ExamTable"]:
		var node := scene.get_node_or_null(label)
		if node == null or not (node is Interactable):
			failures.append("%s is not an Interactable" % label)
	var exam_model := scene.get_node_or_null("TripoExamTable") as Node3D
	if exam_model == null or not exam_model.is_visible_in_tree():
		failures.append("medbay exam table model is missing or hidden")
	if scene.has_node("SheetDent"):
		failures.append("obsolete sheet block is still above the medbay exam table")
	var medbay: Vector2 = ranges["Medbay"]
	var cushion := Vector3(-1.1, 0.88, medbay.x + 2.10)
	if beam == null:
		failures.append("medbay exam lamp has no spotlight")
	else:
		var offset := cushion - beam.global_position
		if (-beam.global_basis.z).normalized().dot(offset.normalized()) < 0.99 or offset.length() >= beam.spot_range:
			failures.append("medbay exam lamp does not reach the cushion")
	# Every sound file referenced by the shuttle must load.
	var sound_files: Array = []
	for group in scene.get("GROUPS").values():
		sound_files.append_array(group)
	for loop_info in scene.get("LOOPS").values():
		sound_files.append(loop_info[0])
	sound_files.append_array(["hatch_pass.ogg", "breaker.ogg", "switch.ogg", "powerup.ogg"])
	for file in sound_files:
		if scene.call("_stream", file) == null:
			failures.append("sound failed to load: %s" % file)
	for failure in failures:
		print("FAIL: ", failure)
	print("SHUTTLE_BLOCKOUT ", "FAIL" if not failures.is_empty() else "OK",
		" length=%.2f failures=%d" % [length, failures.size()])
	scene.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
