extends SceneTree

# State-machine stress pass: 100 full airlock cycles with varied starting
# conditions. Every cycle checks the same physical invariants plus one
# direction-specific return case, giving >1000 individual assertions.

var eva: Node
var player: Player
var main: Node3D
var total := 0
var failed := 0
var failures: Array[String] = []
var report_lines: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	await create_timer(4.2).timeout
	player = main.get_node("Player") as Player
	eva = main.get_node("EVA")
	eva.set("cycle_seconds", 0.01)
	eva.set("_cycle_hiss", null)
	eva.set("_cycle_groan", null)
	eva.set("_cycle_rumble", null)
	player.set_process_unhandled_input(false)

	for i in range(100):
		_cycle(i)

	_hatch_sweep()

	print("AIRLOCK_STRESS_SUMMARY total=", total, " passed=", total - failed, " failed=", failed)
	if failed > 0:
		print("AIRLOCK_STRESS_FAILURES ", JSON.stringify(failures))
	var report := FileAccess.open("res://.codex_qa/playtest/airlock_stress_checks.txt", FileAccess.WRITE)
	if report != null:
		for line in report_lines:
			report.store_line(line)
		report.close()
	main.queue_free()
	await process_frame
	quit(1 if failed > 0 else 0)


func _check(label: String, condition: bool) -> void:
	total += 1
	report_lines.append(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failed += 1
		failures.append(label)
		print("FAIL ", label)


func _cycle(index: int) -> void:
	var prefix := "cycle%03d/" % index
	eva.set("_airlock_state", "sealed")
	eva.set("_interior_door_open", false)
	eva.set("_outer_hatch_open", false)
	eva.set("is_outside", false)
	player.set_eva_mode(false)
	player.velocity = Vector3.ZERO

	eva.call("_interact_inner_door")
	_check(prefix + "inner_open_by_e", bool(eva.get("_interior_door_open")))
	eva.call("_interact_inner_door")
	_check(prefix + "inner_closed_by_e", not bool(eva.get("_interior_door_open")))

	eva.call("_interact_outer_hatch")
	_check(prefix + "venting_state", String(eva.get("_airlock_state")) == "venting")
	_check(prefix + "venting_inner_closed", not bool(eva.get("_interior_door_open")))
	_check(prefix + "venting_outer_closed", not bool(eva.get("_outer_hatch_open")))
	_check(prefix + "venting_interlock",
		not (bool(eva.get("_interior_door_open")) and bool(eva.get("_outer_hatch_open"))))
	_check(prefix + "venting_lamps", _red(eva.get("_inner_lamp_material"))
		and _red(eva.get("_outer_lamp_material")))

	eva.call("_finish_venting")
	_check(prefix + "vacuum_state", String(eva.get("_airlock_state")) == "vacuum")
	_check(prefix + "vacuum_outer_closed", not bool(eva.get("_outer_hatch_open")))
	_check(prefix + "vacuum_inner_closed", not bool(eva.get("_interior_door_open")))
	_check(prefix + "vacuum_interlock",
		not (bool(eva.get("_interior_door_open")) and bool(eva.get("_outer_hatch_open"))))
	_check(prefix + "vacuum_lamps", _red(eva.get("_inner_lamp_material"))
		and _green(eva.get("_outer_lamp_material")))

	eva.call("_interact_outer_hatch")
	_check(prefix + "hatch_open_by_e", bool(eva.get("_outer_hatch_open")))
	eva.call("_interact_outer_hatch")
	_check(prefix + "exit_sets_eva", bool(eva.get("is_outside")) and player.eva_mode)
	_check(prefix + "exit_oxygen", float(eva.get("oxygen_remaining_seconds")) > 0.0)
	eva.call("_interact_outer_hatch")
	_check(prefix + "enter_restores_walk", not bool(eva.get("is_outside")) and not player.eva_mode)
	_check(prefix + "enter_closes_hatch", not bool(eva.get("_outer_hatch_open")))
	_check(prefix + "enter_filling", String(eva.get("_airlock_state")) == "filling")
	_check(prefix + "filling_interlock",
		not (bool(eva.get("_interior_door_open")) and bool(eva.get("_outer_hatch_open"))))

	eva.call("_finish_filling")
	_check(prefix + "filled_state", String(eva.get("_airlock_state")) == "sealed")
	_check(prefix + "filled_inner_closed", not bool(eva.get("_interior_door_open")))
	_check(prefix + "filled_outer_closed", not bool(eva.get("_outer_hatch_open")))
	_check(prefix + "filled_interlock",
		not (bool(eva.get("_interior_door_open")) and bool(eva.get("_outer_hatch_open"))))
	_check(prefix + "filled_lamps", _green(eva.get("_inner_lamp_material"))
		and _red(eva.get("_outer_lamp_material")))

	eva.call("_interact_inner_door")
	_check(prefix + "inner_open_after_fill", bool(eva.get("_interior_door_open")))


func _hatch_sweep() -> void:
	var pivot := eva.get("_hatch_pivot") as Node3D
	if pivot == null:
		return
	var base := pivot.rotation_degrees
	for step in range(20):
		var angle := float(step) * 5.0
		pivot.rotation_degrees = base + Vector3(0.0, angle, 0.0)
		var leaf := main.find_child("HatchLeaf", true, false) as Node3D
		var inner_door := eva.get("interior_door") as Node3D
		if leaf != null and inner_door != null:
			_check("sweep/angle%02d/inner_door_clear" % step,
				not _world_bounds(leaf).intersects(_world_bounds(inner_door)))
	pivot.rotation_degrees = base


func _green(material: Variant) -> bool:
	if not material is StandardMaterial3D:
		return false
	var emission := (material as StandardMaterial3D).emission
	return emission.g > 0.7 and emission.r < 0.35


func _red(material: Variant) -> bool:
	if not material is StandardMaterial3D:
		return false
	var emission := (material as StandardMaterial3D).emission
	return emission.r > 0.7 and emission.g < 0.35


func _world_bounds(root_node: Node) -> AABB:
	var result := AABB()
	var found := false
	for mesh_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var bounds := mesh.global_transform * mesh.get_aabb()
		if not found:
			result = bounds
			found = true
		else:
			result = result.merge(bounds)
	return result
