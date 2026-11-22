extends SceneTree
## Production regression for the upper deck: alignment, open atrium, solid
## window, and a real player walk from the old lower common to the upper rooms.
## No teleports along the route: the player starts at the stair foot and is
## moved only by move_and_slide.

const CHECK := "UPPER_DECK_ROUTE"
const FRAME_STEP := 1.0 / 60.0

var main: Node3D
var interior: Node3D
var upper: Node3D
var player: Player
var space: PhysicsDirectSpaceState3D
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	await create_timer(5.2).timeout
	interior = main.get_node("ShipInterior") as Node3D
	upper = interior.get_node("UpperDeck") as Node3D
	player = main.get_node("Player") as Player
	space = main.get_world_3d().direct_space_state

	_check_hull_alignment()
	_check_atrium_floor()
	_check_window_collision()
	await _check_player_route()

	for failure in failures:
		print("FAIL: ", failure)
	print(CHECK, " ", "FAIL" if not failures.is_empty() else "OK",
		" failures=", failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _fail(text: String) -> void:
	failures.append(text)


func _bounds(node: Node) -> AABB:
	var result := AABB()
	var has := false
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null or _inside_subviewport(mi):
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		if not has:
			result = box
			has = true
		else:
			result = result.merge(box)
	return result


func _inside_subviewport(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is SubViewport:
			return true
		parent = parent.get_parent()
	return false


func _check_hull_alignment() -> void:
	var upper_box := _bounds(upper)
	var hull_box := _bounds(main.get_node("ShipExterior"))
	var inside := upper_box.position.x >= hull_box.position.x - 0.03 \
		and upper_box.position.z >= hull_box.position.z - 0.03 \
		and upper_box.end.x <= hull_box.end.x + 0.03 \
		and upper_box.end.z <= hull_box.end.z + 0.03
	if not inside:
		_fail("upper AABB outside the exterior hull: upper=%s hull=%s" % [upper_box, hull_box])
	var shift := (upper.position - Vector3(2.1, 0.0, 2.0)).length()
	if shift > 0.01:
		_fail("UpperDeck offset is %.3f, expected (2.1, 0, 2.0)" % shift)


func _check_atrium_floor() -> void:
	for point in [Vector2(-2.0, -1.5), Vector2(-2.5, -1.5),
			Vector2(-2.0, -0.5), Vector2(-3.0, -1.5)]:
		var from := upper.to_global(Vector3(point.x, 5.0, point.y))
		var to := upper.to_global(Vector3(point.x, -1.0, point.y))
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			_fail("atrium ray at %s hits nothing" % point)
			continue
		var local := upper.to_local(hit.position)
		if local.y > 2.2:
			_fail("atrium ray at %s hits y=%.2f, expected the lower room, not the old ceiling" % [point, local.y])


func _check_window_collision() -> void:
	var from := upper.to_global(Vector3(-1.9, 4.2, -6.0))
	var to := upper.to_global(Vector3(-8.0, 4.2, -6.0))
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_fail("observation window has no collision; the player can step into space")
	elif not String(hit.collider.name).contains("UpperDeckCollision"):
		_fail("observation window ray hit %s, expected the glass collider" % hit.collider.name)


func _walk_to(target: Vector3, frames: int = 240) -> bool:
	for _frame in frames:
		var offset := target - player.global_position
		offset.y = 0.0
		if offset.length() <= 0.08:
			player.velocity = Vector3.ZERO
			await physics_frame
			return true
		var direction := offset.normalized()
		player.velocity.x = direction.x * 2.6
		player.velocity.z = direction.z * 2.6
		if not player.is_on_floor():
			player.velocity.y -= 9.8 * FRAME_STEP
		else:
			player.velocity.y = 0.0
		player.move_and_slide()
		await physics_frame
	return false


func _check_player_route() -> void:
	player.set_physics_process(false)
	# Start on the lower common floor, walk around the old bench to the wide side
	# ramp, then climb the flight. This is the real lower-deck connection.
	player.global_position = upper.to_global(Vector3(-2.20, 0.20, 1.00))
	await physics_frame
	var targets := [
		["door approach", Vector3(-2.20, 0.20, -0.15)],
		["door", Vector3(-2.62, 0.30, -0.15)],
		["stair foot", Vector3(-3.40, 0.60, -0.15)],
		["stair top", Vector3(-3.60, 2.95, -3.35)],
		["back walkway", Vector3(-2.00, 2.95, -3.50)],
		["east walkway", Vector3(-0.50, 2.95, -2.30)],
		["cabin door", Vector3(-0.40, 2.95, 0.00)],
		["cabin", Vector3(-2.00, 2.95, 2.00)],
		["cabin door out", Vector3(-0.40, 2.95, 0.00)],
		["east walkway 2", Vector3(-0.50, 2.95, -2.80)],
		["observation door", Vector3(-0.40, 2.95, -4.00)],
		["observation", Vector3(-2.00, 2.95, -6.00)],
		["observation door out", Vector3(-0.40, 2.95, -4.00)],
		["east walkway 3", Vector3(-0.50, 2.95, -1.70)],
		["tech door", Vector3(0.60, 2.95, -1.70)],
		["tech storage", Vector3(2.00, 2.95, -1.30)],
	]
	for entry in targets:
		var label: String = entry[0]
		var target := upper.to_global(entry[1])
		var reached := await _walk_to(target)
		var local := upper.to_local(player.global_position)
		if not reached:
			_fail("route stopped before '%s' at upper-local (%.2f, %.2f, %.2f)" % [
				label, local.x, local.y, local.z])
			return
		if local.y < 2.55 and not ["door approach", "door", "stair foot"].has(label):
			_fail("route reached '%s' but player y=%.2f is below the upper deck" % [label, local.y])
			return
	print("route final upper-local=", upper.to_local(player.global_position))
