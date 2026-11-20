extends SceneTree

var checks: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(4.2).timeout
	var player := main.get_node("Player") as Player
	var eva := main.get_node("EVA")
	eva.set("cycle_seconds", 0.2)
	var interior := main.get_node("ShipInterior") as Node3D
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	var outbound := [
		Vector3(0.0, 0.13, 5.0), Vector3(3.4, 0.13, 5.0),
		Vector3(3.4, 0.13, 5.5), Vector3(3.4875, 0.13, 5.5)
	]
	checks["walk_to_inner_door"] = await _walk_to(player, interior.to_global(outbound[0]))
	if checks["walk_to_inner_door"] != true:
		_print_and_exit(main, false)
		return
	checks["inner_door_opened"] = bool(eva.call("try_interact_airlock", player))
	await create_timer(1.3).timeout
	checks["inner_door_open_state"] = bool(eva.get("_interior_door_open"))
	for index in range(1, outbound.size()):
		var point: Vector3 = outbound[index]
		checks["walk_out_" + str(index)] = await _walk_to(player, interior.to_global(point))
		if checks["walk_out_" + str(index)] != true:
			break
	var hatch_distance: float = player.global_position.distance_to(Vector3(-8.47, 2.33, 11.9))
	checks["outer_door_reachable"] = hatch_distance <= 2.0
	if checks["outer_door_reachable"]:
		checks["outer_vent_started"] = bool(eva.call("try_interact_airlock", player)) \
			and String(eva.get("_airlock_state")) == "venting"
		await create_timer(0.35).timeout
		checks["outer_vacuum_hatch_closed"] = String(eva.get("_airlock_state")) == "vacuum" \
			and not bool(eva.get("_outer_hatch_open"))
		checks["outer_door_opened"] = bool(eva.call("try_interact_airlock", player)) \
			and bool(eva.get("_outer_hatch_open"))
		await create_timer(1.5).timeout
		var leaf := eva.get("_hatch_leaf_body") as AnimatableBody3D
		# The leaf is solid while fully open; only the doorway is passable.
		checks["outer_leaf_collision_solid"] = leaf != null and leaf.collision_layer == 1
	checks["exit_to_space_by_e"] = bool(eva.call("try_interact_airlock", player)) \
		and bool(player.eva_mode) and bool(eva.get("is_outside"))
	checks["outbound_position"] = [snappedf(player.global_position.x,0.01), snappedf(player.global_position.y,0.01), snappedf(player.global_position.z,0.01)]
	var enter_result := bool(eva.call("try_interact_airlock", player))
	checks["enter_by_e"] = enter_result \
		and not bool(player.eva_mode) and not bool(eva.get("is_outside"))
	checks["enter_starts_fill"] = String(eva.get("_airlock_state")) == "filling"
	await create_timer(0.35).timeout
	checks["filled_sealed"] = String(eva.get("_airlock_state")) == "sealed"
	player.global_position = (eva.get("inside_trigger") as Node3D).global_position
	checks["inner_open_after_fill"] = bool(eva.call("try_interact_airlock", player)) \
		and bool(eva.get("_interior_door_open"))
	await create_timer(1.2).timeout
	checks["walk_inside"] = await _walk_to(player, interior.to_global(Vector3(0.0, 0.13, 5.0)))
	eva.call("_set_inner_door_open", false)
	await create_timer(1.3).timeout
	checks["inbound_crossing_restores_walk"] = not bool(player.eva_mode) and not bool(eva.get("is_outside"))
	checks["outer_door_closed_after_return"] = not bool(eva.get("_outer_hatch_open"))
	checks["shell_hidden_after_return"] = not (main.get_node("ShipExterior") as Node3D).visible
	checks["inner_door_closed_after_return"] = not bool(eva.get("_interior_door_open"))
	print("WALKTHROUGH_CHECKS ", JSON.stringify(checks))
	var failed := false
	for key in ["walk_to_inner_door", "inner_door_opened", "inner_door_open_state",
		"outer_door_reachable", "outer_vent_started", "outer_vacuum_hatch_closed",
		"outer_door_opened", "outer_leaf_collision_solid", "exit_to_space_by_e",
		"enter_by_e", "enter_starts_fill", "filled_sealed", "inner_open_after_fill",
		"inbound_crossing_restores_walk", "outer_door_closed_after_return",
		"shell_hidden_after_return", "inner_door_closed_after_return"]:
		if checks.get(key) != true:
			failed = true
	for key in checks.keys():
		if String(key).begins_with("walk_") and checks[key] != true:
			failed = true
	main.queue_free()
	await process_frame
	quit(1 if failed else 0)

func _print_and_exit(main: Node3D, result: bool) -> void:
	print("WALKTHROUGH_CHECKS ", JSON.stringify(checks))
	main.queue_free()
	await process_frame
	quit(0 if result else 1)

func _walk_to(body: CharacterBody3D, target: Vector3) -> bool:
	var last_collision := "none"
	for _frame in range(240):
		var offset := target - body.global_position
		offset.y = 0.0
		if offset.length() <= 0.035:
			body.velocity = Vector3.ZERO
			await physics_frame
			return true
		var step := offset.normalized() * minf(3.0 / 60.0, offset.length())
		body.velocity = step.normalized() * 3.0
		body.move_and_slide()
		if body.get_slide_collision_count() > 0:
			var slide := body.get_slide_collision(0)
			var collider := slide.get_collider() as Node
			last_collision = "%s normal=%s at=%s" % [collider.name if collider != null else "unknown",
				slide.get_normal(), slide.get_position()]
		await physics_frame
	print("WALK_TIMEOUT pos=", body.global_position, " target=", target,
		" distance=", body.global_position.distance_to(target), " last_collision=", last_collision)
	return false
