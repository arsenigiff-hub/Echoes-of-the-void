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
	_check(player.interaction_ray.get_collider() in [hatch, eva.get("_outer_body")],
		"the sealed outer aperture must have a reachable collider")
	_check(_ray_hits_hatch(), "closed hatch leaf has no physical collision")
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
		var environment := player.camera.environment
		_check(environment.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED \
			and environment.ambient_light_energy == 0.0 \
			and environment.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED \
			and not environment.fog_enabled, "empty space still supplies ambient, sky reflection or lit fog")
		_check(eva.find_children("*", "DirectionalLight3D", true, false).is_empty(), "EVA still has an invisible sun")
		_check(not player.flashlight.visible and player.camera.get_node_or_null("EVAHelmetLight") == null,
			"exit enabled an automatic helmet light")
		var flashlight := InputEventKey.new()
		flashlight.physical_keycode = KEY_F
		flashlight.pressed = true
		root.push_input(flashlight, true)
		_check(player.flashlight.visible, "F cannot enable the flashlight in EVA")
		root.push_input(flashlight, true)
		_check(not player.flashlight.visible, "F cannot disable the flashlight in EVA")
		_check(_ray_hits_hatch(), "open hatch leaf lost its physical collision")
		_test_hatch_body()
		var floor_ray := PhysicsRayQueryParameters3D.create(outside_start + Vector3.UP * 0.3,
			outside_start - Vector3.UP * 0.3, 1)
		var floor_hit := player.get_world_3d().direct_space_state.intersect_ray(floor_ray)
		_check(floor_hit.get("collider") == eva.get("_platform_body"), "exit does not finish above a solid platform")
		await _frames(30)
		_check(player.global_position.distance_to(outside_start) < 0.01, "player drifted off platform immediately after exit")
		_check(outside_start.x < -4.3 and player.eva_mouse_only and hatch.collision_layer == 0,
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
	# Isolate free momentum from hull contact; travel must exceed the old rope radius.
	player.collision_mask = 0
	player.global_position = outside_start
	eva.drift = Vector3.UP
	for tick in 30:
		eva.call("_apply_drift", 1.0 / 60.0)
	_check(eva.drift.is_equal_approx(Vector3.UP), "free drift lost momentum")
	player.global_position = outside_start
	eva.drift = Vector3.LEFT * 4.0
	for tick in 300:
		eva.call("_apply_drift", 1.0 / 60.0)
	_check(player.global_position.distance_to(outside_start + Vector3.LEFT * 20.0) < 0.02 \
		and eva.drift.is_equal_approx(Vector3.LEFT * 4.0), "an invisible tether still limits free travel")
	await _test_full_hull()
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


func _ray_hits_hatch() -> bool:
	var leaf := (eva.get("_outer") as Node3D).find_child("OuterLeafArt", true, false) as MeshInstance3D
	var center := leaf.global_transform * leaf.get_aabb().get_center()
	var normal := leaf.global_basis.x.normalized()
	var ray := PhysicsRayQueryParameters3D.create(center + normal * 0.45, center - normal * 0.45, 1)
	return player.get_world_3d().direct_space_state.intersect_ray(ray).get("collider") == eva.get("_outer_body")


func _test_hatch_body() -> void:
	var saved := player.global_position
	var leaf := (eva.get("_outer") as Node3D).find_child("OuterLeafArt", true, false) as MeshInstance3D
	var center := leaf.global_transform * leaf.get_aabb().get_center()
	var normal := leaf.global_basis.x.normalized()
	player.global_position = center + normal * 0.85 - Vector3.UP * 0.9
	var collision := player.move_and_collide(-normal * 1.3)
	_check(collision != null and collision.get_collider() == eva.get("_outer_body"),
		"player capsule can pass through the open hatch leaf")
	player.global_position = saved


func _test_full_hull() -> void:
	var hull := eva.get("_hull_root") as MeshInstance3D
	var faces := hull.mesh.get_faces()
	var ends := [Vector3.INF, -Vector3.INF]
	var normals := [Vector3.ZERO, Vector3.ZERO]
	for i in range(0, faces.size(), 3):
		var center := hull.global_transform * ((faces[i] + faces[i+1] + faces[i+2]) / 3.0)
		var normal := hull.global_basis * (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).normalized()
		if normal.length_squared() < 0.5:
			continue
		for end in 2:
			if (end == 0 and center.z < ends[end].z) or (end == 1 and center.z > ends[end].z):
				ends[end] = center
				normals[end] = normal
	for end in 2:
		eva.drift = Vector3.ZERO
		var eye_offset := player.camera.global_position - player.global_position
		player.global_position = ends[end] + normals[end] * 1.3 - eye_offset
		_aim(ends[end])
		await _frames(2)
		var hit: Dictionary = eva.call("_aim_surface")
		_check(not hit.is_empty(), "hull end %d cannot be grabbed away from the hatch" % end)
		if hit.is_empty():
			continue
		eva.call("_grab", hit["position"], hit["normal"])
		var start := player.global_position
		var tangent: Vector3 = player.camera.global_basis.x.slide(hit["normal"]).normalized()
		eva.set("_pull", tangent * 0.08)
		eva.call("_apply_pull", 1.0 / 60.0)
		_check(player.global_position.distance_to(start) > 0.01 and player.global_position.distance_to(start) < 0.12,
			"grabbing a distant hull section snapped player toward the hatch")
		eva.call("_stop_grip")
		eva.drift = Vector3.ZERO
