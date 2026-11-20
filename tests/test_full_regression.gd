extends SceneTree

# Full regression pass requested by the author: scene/model integrity, route
# clearance, airlock logic, character physics and space-stage behaviour.
# Every check prints PASS/FAIL; the process exits non-zero if anything fails.

var main: Node3D
var player: Player
var eva: Node
var interior: Node3D
var space_stage: Node3D
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var space_state: PhysicsDirectSpaceState3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	await create_timer(4.2).timeout
	player = main.get_node("Player") as Player
	eva = main.get_node("EVA")
	interior = main.get_node("ShipInterior") as Node3D
	space_stage = main.get_node("SpaceStage") as Node3D
	player.set_process_unhandled_input(false)
	eva.call("_set_exterior_shell_visible", true)
	await physics_frame
	await physics_frame
	space_state = main.get_world_3d().direct_space_state

	_scene_checks()
	_geometry_checks()
	await _logic_checks()
	await _physics_checks()
	_space_checks()
	_ui_checks()
	_finish()


func _check(label: String, condition: bool) -> void:
	checks.append({"label": label, "ok": condition})
	if condition:
		print("PASS ", label)
	else:
		failures.append(label)
		print("FAIL ", label)


func _scene_checks() -> void:
	_check("scene/main", main != null)
	_check("scene/player", player != null)
	_check("scene/eva", eva != null)
	_check("scene/interior", interior != null)
	_check("scene/exterior", main.get_node_or_null("ShipExterior") != null)
	_check("scene/hatch", main.get_node_or_null("AirlockExterior") != null)
	_check("scene/environment", main.get_node_or_null("WorldEnvironment") != null)
	_check("scene/radio", main.get_node_or_null("Radio") != null)
	_check("scene/space", space_stage != null)
	_check("scene/story", main.get_node_or_null("StoryProgression") != null)
	_check("player/capsule", player.get_node_or_null("CollisionShape3D") != null)
	_check("player/camera", player.get_node_or_null("Head/Camera3D") != null)
	_check("player/flashlight", player.get_node_or_null("Head/Camera3D/SpotLight3D") != null)
	_check("eva/hull_collider", eva.get("_hull_body") != null)
	_check("eva/platform_collider", main.get_node_or_null("EVA_PlatformCollider") != null)
	_check("eva/hatch_collider", eva.get("_hatch_leaf_body") != null)
	_check("eva/inner_door", eva.get("interior_door") != null)
	_check("eva/outer_hatch", eva.get("exterior_hatch") != null)
	_check("eva/tunnel_light", eva.get("_tunnel_light") != null)
	_check("eva/inner_lamp_fixture", main.get_node_or_null("AirlockInnerPressureLampFixture") != null)
	_check("eva/outer_lamp_fixture", main.get_node_or_null("AirlockOuterPressureLampFixture") != null)
	_check("eva/steam_inner", eva.get("_steam_inner") != null)
	_check("eva/steam_outer", eva.get("_steam_outer") != null)
	_check("eva/audio_hiss", (eva.get("_cycle_hiss") as AudioStreamPlayer).stream != null)
	_check("eva/audio_groan", (eva.get("_cycle_groan") as AudioStreamPlayer).stream != null)
	_check("eva/audio_rumble", (eva.get("_cycle_rumble") as AudioStreamPlayer).stream != null)


func _geometry_checks() -> void:
	var interior_bounds := _world_bounds(interior)
	var hull_bounds := _world_bounds(main.get_node("ShipExterior"))
	_check("geometry/interior_inside_hull", _contained(hull_bounds, interior_bounds, 0.0))
	var bridge := interior.get_node("Bridge") as Node3D
	var radio := main.get_node("Radio") as Node3D
	_check("geometry/radio_inside_bridge", _contains(_world_bounds(bridge), radio.global_position, 0.2))
	var inner_glass := _material_bounds(interior.get_node("Bridge"), "viewport_glass")
	var outer_glass := _material_bounds(main.get_node("ShipExterior"), "glass_grime")
	_check("geometry/window_found", not inner_glass.size.is_zero_approx() and not outer_glass.size.is_zero_approx())
	_check("geometry/window_aligned", inner_glass.get_center().distance_to(outer_glass.get_center()) <= 0.65)

	var inner_door := eva.get("interior_door") as Node3D
	var frame := interior.get_node_or_null("AirlockPressureFrame") as Node3D
	var hatch := main.get_node("AirlockExterior") as Node3D
	var door_bounds := _world_bounds(inner_door)
	var frame_bounds := _world_bounds(frame)
	var hatch_bounds := _world_bounds(hatch)
	_check("geometry/inner_door_in_frame", inner_door != null and frame != null
		and _expanded(frame_bounds, 0.25).intersects(door_bounds))
	_check("geometry/hatch_module_size", hatch_bounds.size.y > 2.0 and hatch_bounds.size.z > 1.8)

	var platform := main.get_node("EVA_PlatformCollider") as StaticBody3D
	_check("geometry/platform_has_shape", platform.get_child_count() > 0)
	var platform_bounds := _box_collision_bounds(platform)
	_check("geometry/platform_covers_landing", platform_bounds.has_point(Vector3(-10.2, 2.19, 11.9)))
	_check("geometry/platform_under_hatch", platform_bounds.has_point(Vector3(-8.8, 2.19, 11.9)))

	var inner_fixture := main.get_node("AirlockInnerPressureLampFixture") as Node3D
	var outer_fixture := main.get_node("AirlockOuterPressureLampFixture") as Node3D
	_check("geometry/inner_fixture_mount", _fixture_ordered(inner_fixture))
	_check("geometry/outer_fixture_mount", _fixture_ordered(outer_fixture))
	_check("geometry/inner_lamp_outside_door", inner_door != null
		and not door_bounds.intersects(_node_bounds(inner_fixture.get_node("Lens"))))
	var hatch_leaf := hatch.find_child("HatchLeaf", true, false)
	_check("geometry/outer_lamp_outside_hatch", hatch_leaf != null
		and not _world_bounds(hatch_leaf).intersects(_node_bounds(outer_fixture.get_node("Lens"))))

	var capsule_center := interior.to_global(Vector3(0.0, 1.03, 4.6))
	_check("geometry/spawn_capsule_clear", _capsule_free(capsule_center))
	_check("geometry/spawn_outside_door", not door_bounds.has_point(capsule_center))

	var route: Array = [
		["spawn", interior.to_global(Vector3(0.0, 0.13, 0.4))],
		["quarters", interior.to_global(Vector3(0.0, 0.13, -4.0))],
		["common", interior.to_global(Vector3(0.0, 0.13, 0.0))],
		["airlock", interior.to_global(Vector3(0.0, 0.13, 4.5))],
		["tunnel_door", interior.to_global(Vector3(3.4, 0.13, 5.0))],
		["tunnel_mid", interior.to_global(Vector3(3.4, 0.13, 5.4))],
		["bend", interior.to_global(Vector3(5.7, 0.13, -3.2))],
		["bridge_entry", interior.to_global(Vector3(3.14, 0.13, -13.3))],
		["bridge", interior.to_global(Vector3(3.14, 0.13, -14.0))],
		["eva_tunnel", Vector3(-7.5, 2.25, 11.5)],
		["eva_hatch", Vector3(-8.0, 2.25, 11.9)],
		["eva_platform", Vector3(-10.2, 2.25, 11.9)],
	]
	for entry in route:
		var label := String(entry[0])
		var point := entry[1] as Vector3
		var floor_hit := _ray_down(point + Vector3.UP * 2.0, point - Vector3.UP * 2.0)
		_check("route/%s/floor" % label,
			not floor_hit.is_empty() and absf((floor_hit["position"] as Vector3).y - point.y) <= 0.45)
		var ceiling_hit := _ray_down(point + Vector3.UP * 0.1, point + Vector3.UP * 2.0)
		_check("route/%s/headroom" % label,
			ceiling_hit.is_empty() or ((ceiling_hit["position"] as Vector3).y - point.y) >= 1.9)
		_check("route/%s/capsule" % label, _capsule_free(point + Vector3.UP * 0.9))


func _logic_checks() -> void:
	_check("logic/default_cycle_4s", is_equal_approx(float(eva.get("cycle_seconds")), 4.0))
	_check("logic/initial_sealed", String(eva.get("_airlock_state")) == "sealed")
	_check("logic/initial_doors_closed",
		not bool(eva.get("_interior_door_open")) and not bool(eva.get("_outer_hatch_open")))
	_check("logic/inner_lamp_green", _lamp_is_green(eva.get("_inner_lamp_material")))
	_check("logic/outer_lamp_red", _lamp_is_red(eva.get("_outer_lamp_material")))
	_check("logic/no_cycle_textmesh", _textmesh_count(eva) == 0)
	_check("logic/steam_one_shot", (eva.get("_steam_inner") as CPUParticles3D).one_shot)
	_check("logic/steam_amount", (eva.get("_steam_inner") as CPUParticles3D).amount >= 12)

	eva.set("cycle_seconds", 0.25)
	eva.set("_airlock_state", "sealed")
	eva.set("_interior_door_open", false)
	eva.set("_outer_hatch_open", false)
	eva.set("is_outside", false)
	player.set_eva_mode(false)

	eva.call("_interact_inner_door")
	_check("logic/inner_open_by_e", bool(eva.get("_interior_door_open")))
	eva.call("_interact_inner_door")
	_check("logic/inner_closed_by_e", not bool(eva.get("_interior_door_open")))

	eva.call("_interact_outer_hatch")
	_check("logic/venting_started", String(eva.get("_airlock_state")) == "venting")
	_check("logic/venting_hatch_closed", not bool(eva.get("_outer_hatch_open")))
	_check("logic/venting_lamps", _lamp_is_red(eva.get("_inner_lamp_material"))
		and _lamp_is_red(eva.get("_outer_lamp_material")))
	eva.call("_finish_venting")
	_check("logic/vacuum_reached", String(eva.get("_airlock_state")) == "vacuum")
	_check("logic/vacuum_hatch_stays_closed", not bool(eva.get("_outer_hatch_open")))
	_check("logic/vacuum_lamps", _lamp_is_red(eva.get("_inner_lamp_material"))
		and _lamp_is_green(eva.get("_outer_lamp_material")))

	eva.call("_interact_outer_hatch")
	_check("logic/hatch_open_by_e", bool(eva.get("_outer_hatch_open")))
	eva.call("_interact_outer_hatch")
	_check("logic/exit_sets_eva", bool(eva.get("is_outside")) and player.eva_mode)
	eva.call("_interact_outer_hatch")
	_check("logic/enter_restores_walk", not bool(eva.get("is_outside")) and not player.eva_mode)
	_check("logic/enter_filling", String(eva.get("_airlock_state")) == "filling"
		and not bool(eva.get("_outer_hatch_open")))
	eva.call("_finish_filling")
	_check("logic/filled_sealed", String(eva.get("_airlock_state")) == "sealed")
	_check("logic/filled_inner_closed", not bool(eva.get("_interior_door_open")))
	eva.call("_interact_inner_door")
	_check("logic/inner_open_after_fill", bool(eva.get("_interior_door_open")))

	player.global_position = (eva.get("inside_trigger") as Node3D).global_position
	eva.set("_prompt_hold_until", 0)
	eva.call("_update_status", "")
	_check("logic/inner_prompt", (eva.get("_prompt") as Label).text.contains("ВНУТРЕННИЙ"))
	player.global_position = (eva.get("outside_trigger") as Node3D).global_position
	eva.set("_prompt_hold_until", 0)
	eva.call("_update_status", "")
	_check("logic/outer_prompt", (eva.get("_prompt") as Label).text != "")
	player.global_position = Vector3(0, 2, 0)
	eva.call("_update_status", "")
	_check("logic/no_pressure_number", not (eva.get("_prompt") as Label).text.contains("0.0"))

	_check("logic/oxygen_duration_positive", float(eva.call("_oxygen_duration_for_profile")) > 0.0)
	eva.call("_refill_eva_oxygen")
	_check("logic/oxygen_refilled", float(eva.get("oxygen_remaining_seconds")) > 0.0)
	eva.call("_start_eva_oxygen")
	_check("logic/oxygen_label_visible", (eva.get("_oxygen_label") as Label).visible)
	eva.call("_refill_eva_oxygen")
	_check("logic/oxygen_label_hidden", not (eva.get("_oxygen_label") as Label).visible)


func _physics_checks() -> void:
	# Gravity probe in the cabin.
	var cabin_floor := interior.to_global(Vector3(0.0, 0.13, 0.4))
	var probe := _make_probe(cabin_floor + Vector3.UP * 2.4)
	await _drop_probe(probe, 90)
	_check("physics/cabin_gravity_lands", probe.is_on_floor()
		and probe.global_position.y > cabin_floor.y - 0.2)
	probe.queue_free()
	await physics_frame

	# EVA should not pull the body down.
	player.is_interacting = false
	player.set_physics_process(true)
	player.set_eva_mode(true)
	player.global_position = Vector3(-13.0, 6.0, 16.0)
	player.velocity = Vector3.ZERO
	await create_timer(0.6).timeout
	_check("physics/eva_no_gravity", absf(player.global_position.y - 6.0) < 0.3)
	player.set_eva_mode(false)
	player.global_position = cabin_floor
	player.velocity = Vector3.ZERO

	# Landing platform survives the hull collider switch-off, and the explicit
	# E enter action restores walking.
	eva.set("_airlock_state", "vacuum")
	eva.set("_outer_hatch_open", true)
	eva.set("is_outside", true)
	player.set_eva_mode(true)
	player.global_position = Vector3(-10.2, 2.5, 11.9)
	player.velocity = Vector3.ZERO
	eva.call("_enter_airlock_from_space")
	await physics_frame
	_check("physics/enter_restores_gravity", not bool(eva.get("is_outside"))
		and not player.eva_mode)
	var hull := eva.get("_hull_body") as StaticBody3D
	_check("physics/enter_turns_hull_off", hull != null and hull.collision_layer == 0)
	var deck_probe := _make_probe(Vector3(-10.2, 3.25, 11.9))
	await _drop_probe(deck_probe, 90)
	_check("physics/platform_lands_after_return", deck_probe.is_on_floor()
		and deck_probe.global_position.y > 2.9)
	var deck_ray := _ray_down(Vector3(-10.2, 5.0, 11.9), Vector3(-10.2, 0.5, 11.9))
	_check("physics/platform_collider_ray", not deck_ray.is_empty()
		and String((deck_ray["collider"] as Node).name) == "EVA_PlatformCollider")
	deck_probe.queue_free()
	await physics_frame

	# Closed inner door blocks a floating probe; open door lets it through.
	var inner_door := eva.get("interior_door") as Node3D
	eva.call("_set_inner_door_open", false)
	await create_timer(1.1).timeout
	var door_probe := _make_probe(interior.to_global(Vector3(0.6, 1.0, 5.0)))
	door_probe.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var local_forward := (interior.to_global(Vector3(1.0, 1.0, 5.0))
		- interior.to_global(Vector3(0.0, 1.0, 5.0))).normalized()
	for _frame in range(60):
		door_probe.velocity = local_forward * 2.0
		door_probe.move_and_slide()
		await physics_frame
	var blocked_x := interior.to_local(door_probe.global_position).x
	_check("physics/closed_inner_door_blocks", blocked_x < 1.70)
	eva.call("_set_inner_door_open", true)
	await create_timer(1.2).timeout
	for _frame in range(60):
		door_probe.velocity = local_forward * 2.0
		door_probe.move_and_slide()
		await physics_frame
	var open_x := interior.to_local(door_probe.global_position).x
	_check("physics/open_inner_door_passes", open_x > 2.0)
	door_probe.queue_free()
	await physics_frame

	# Closed outer hatch blocks; open hatch lets a probe out.
	eva.call("_set_inner_door_open", false)
	if bool(eva.get("_outer_hatch_open")):
		eva.call("_set_outer_hatch_open", false)
		await create_timer(1.5).timeout
	eva.set("_airlock_state", "sealed")
	eva.set("_outer_hatch_open", false)
	if eva.get("_hatch_leaf_body") != null:
		(eva.get("_hatch_leaf_body") as AnimatableBody3D).collision_layer = 1
	player.global_position = interior.to_global(Vector3(0.0, 0.13, 0.4))
	player.velocity = Vector3.ZERO
	var hatch_probe := _make_probe(Vector3(-7.7, 3.3, 11.9))
	hatch_probe.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	for _frame in range(60):
		hatch_probe.velocity = Vector3(-2.0, 0.0, 0.0)
		hatch_probe.move_and_slide()
		await physics_frame
	_check("physics/closed_outer_hatch_blocks", hatch_probe.global_position.x > -8.95)
	eva.call("_set_outer_hatch_open", true)
	await create_timer(1.5).timeout
	for _frame in range(60):
		hatch_probe.velocity = Vector3(-2.0, 0.0, 0.0)
		hatch_probe.move_and_slide()
		await physics_frame
	_check("physics/open_outer_hatch_passes", hatch_probe.global_position.x < -9.1)
	hatch_probe.queue_free()
	await physics_frame

	# Tether pulls back beyond the soft limit.
	eva.set("is_outside", true)
	player.set_eva_mode(true)
	player.global_position = (eva.get("exit_pos") as Vector3) + Vector3(38.0, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	eva.call("_tether", 0.016)
	var toward_exit := ((eva.get("exit_pos") as Vector3) - player.global_position).normalized()
	_check("physics/tether_pulls_back", player.velocity.length() > 0.01
		and player.velocity.normalized().dot(toward_exit) > 0.5)
	player.set_eva_mode(false)
	eva.set("is_outside", false)

	# Flashlight and oxygen UI are still operational.
	var flashlight := player.get_node("Head/Camera3D/SpotLight3D") as SpotLight3D
	var was_visible := flashlight.visible
	player.call("_toggle_flashlight")
	_check("physics/flashlight_toggles", flashlight.visible != was_visible)
	player.call("_toggle_flashlight")


func _space_checks() -> void:
	var gas := main.find_child("SpaceGasGiant", true, false) as Node3D
	var ring := main.find_child("SpaceRing", true, false) as Node3D
	var black_hole := main.find_child("SpaceBlackHole", true, false) as Node3D
	var sun := main.find_child("Sun", true, false) as Node3D
	var disk := main.find_child("CanaryAccretionDisk", true, false) as MeshInstance3D
	var model := main.find_child("CanaryBlackHole", true, false) as Node3D
	var embedded_ship := model.find_child("Nave_2", true, false) as Node3D if model != null else null
	var animation := model.find_child("AnimationPlayer", true, false) as AnimationPlayer if model != null else null
	var center := space_stage.get("orbit_center") as Vector3
	_check("space/gas_exists", gas != null)
	_check("space/ring_exists", ring != null)
	_check("space/blackhole_exists", black_hole != null)
	_check("space/disk_shader", disk != null and disk.material_override is ShaderMaterial)
	_check("space/animation_speed", animation != null and is_equal_approx(animation.speed_scale, 0.1))
	_check("space/embedded_ship_hidden", embedded_ship != null and not embedded_ship.visible)
	_check("space/ring_follows", ring.global_position.distance_to(gas.global_position) < 0.01)
	_check("space/initial_radius", absf(Vector2(gas.global_position.x - center.x,
		gas.global_position.z - center.z).length() - 332.0) < 1.0)
	space_stage.call("_process", 3600.0)
	_check("space/orbit_stable", absf(Vector2(gas.global_position.x - center.x,
		gas.global_position.z - center.z).length() - 332.0) < 1.0)
	_check("space/blackhole_hidden", not black_hole.visible)
	var eye := interior.to_global(Vector3(2.94, 0.0, -13.79)) + Vector3.UP * 1.65
	var target := interior.to_global(Vector3(3.14, 1.4, -17.09))
	var forward := (target - eye).normalized()
	var sun_start := sun.global_position
	space_stage.call("set_stage", 1, true)
	_check("space/stage1_blackhole_visible", black_hole.visible)
	_check("space/stage1_blackhole_1200", absf(eye.distance_to(black_hole.global_position) - 1200.0) < 0.2)
	_check("space/stage1_blackhole_sightline", forward.dot((black_hole.global_position - eye).normalized()) > 0.999)
	_check("space/stage1_sun_recedes", sun.global_position.distance_to(sun_start) > 1000.0)
	space_stage.call("set_stage", 2, true)
	_check("space/stage2_gas_hidden", not gas.visible and not ring.visible)
	_check("space/stage2_blackhole_550", absf(eye.distance_to(black_hole.global_position) - 550.0) < 0.2)
	_check("space/planet_scale", gas.scale.x < 20.0 and ring.scale.x < 0.4)


func _ui_checks() -> void:
	_check("ui/status_label", eva.get("_status") is Label)
	_check("ui/prompt_label", eva.get("_prompt") is Label)
	_check("ui/oxygen_label", eva.get("_oxygen_label") is Label)
	_check("ui/fade_overlay", eva.get("_fade") is ColorRect)
	_check("ui/no_eva_textmesh", _textmesh_count(eva) == 0)
	_check("ui/physical_signs_matte", _all_textmesh_matte(interior))
	_check("ui/no_pressure_digits", not _any_label_has_pressure_number(eva))
	var labels := (eva.get("_ui") as CanvasLayer).find_children("*", "Label", true, false)
	_check("ui/labels_have_font", labels.size() > 0 and (labels[0] as Label).get_theme_font("font") != null)


func _finish() -> void:
	var passed := checks.size() - failures.size()
	print("REGRESSION_SUMMARY total=", checks.size(), " passed=", passed, " failed=", failures.size())
	if not failures.is_empty():
		print("REGRESSION_FAILURES ", JSON.stringify(failures))
	for node in main.find_children("*", "AudioStreamPlayer", true, false):
		var audio_player := node as AudioStreamPlayer
		audio_player.stop()
		audio_player.stream = null
	main.free()
	await process_frame
	await process_frame
	quit(1 if not failures.is_empty() else 0)


# ---------------------------------------------------------------- helpers ---

func _ray_down(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	if player != null:
		query.exclude = [player.get_rid()]
	return space_state.intersect_ray(query)


func _capsule_free(center: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.33
	shape.height = 1.7
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = 1
	if player != null:
		query.exclude = [player.get_rid()]
	return space_state.intersect_shape(query, 1).is_empty()


func _make_probe(pos: Vector3) -> CharacterBody3D:
	var probe := CharacterBody3D.new()
	probe.name = "RegressionProbe"
	probe.collision_layer = 0
	probe.collision_mask = 1
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	collision.shape = capsule
	probe.add_child(collision)
	main.add_child(probe)
	probe.global_position = pos
	return probe


func _drop_probe(probe: CharacterBody3D, frames: int) -> void:
	for _frame in range(frames):
		probe.velocity.y -= 9.8 / 60.0
		probe.move_and_slide()
		await physics_frame


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


func _node_bounds(node: Node) -> AABB:
	if node is VisualInstance3D:
		var visual := node as VisualInstance3D
		return visual.global_transform * visual.get_aabb()
	return AABB()


func _box_collision_bounds(body: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for child in body.get_children():
		var collision := child as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var box := collision.shape as BoxShape3D
		var bounds := AABB(collision.global_position - box.size * 0.5, box.size)
		if not found:
			result = bounds
			found = true
		else:
			result = result.merge(bounds)
	return result


func _expanded(bounds: AABB, amount: float) -> AABB:
	return bounds.grow(amount)


func _contained(outer: AABB, inner: AABB, margin: float) -> bool:
	return inner.position.x >= outer.position.x + margin \
		and inner.position.y >= outer.position.y + margin \
		and inner.position.z >= outer.position.z + margin \
		and inner.end.x <= outer.end.x - margin \
		and inner.end.y <= outer.end.y - margin \
		and inner.end.z <= outer.end.z - margin


func _contains(bounds: AABB, point: Vector3, margin: float) -> bool:
	return point.x >= bounds.position.x + margin and point.x <= bounds.end.x - margin \
		and point.y >= bounds.position.y + margin and point.y <= bounds.end.y - margin \
		and point.z >= bounds.position.z + margin and point.z <= bounds.end.z - margin


func _material_bounds(root_node: Node, material_name: String) -> AABB:
	for mesh_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material != null and material.resource_name == material_name:
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				if vertices.is_empty():
					continue
				var bounds := AABB(mesh.global_transform * vertices[0], Vector3.ZERO)
				for vertex_index in range(1, vertices.size()):
					bounds = bounds.expand(mesh.global_transform * vertices[vertex_index])
				return bounds
	return AABB()


func _lamp_is_green(material: Variant) -> bool:
	if not material is StandardMaterial3D:
		return false
	var emission := (material as StandardMaterial3D).emission
	return emission.g > 0.7 and emission.r < 0.35


func _lamp_is_red(material: Variant) -> bool:
	if not material is StandardMaterial3D:
		return false
	var emission := (material as StandardMaterial3D).emission
	return emission.r > 0.7 and emission.g < 0.35


func _fixture_ordered(fixture: Node3D) -> bool:
	if fixture == null:
		return false
	var base := fixture.get_node_or_null("Base") as Node3D
	var stem := fixture.get_node_or_null("Stem") as Node3D
	var cup := fixture.get_node_or_null("Cup") as Node3D
	var lens := fixture.get_node_or_null("Lens") as Node3D
	if base == null or stem == null or cup == null or lens == null:
		return false
	return base.position.y > stem.position.y and stem.position.y > cup.position.y \
		and cup.position.y > lens.position.y


func _textmesh_count(root_node: Node) -> int:
	var count := 0
	for mesh_node in root_node.find_children("*", "MeshInstance3D", true, false):
		if (mesh_node as MeshInstance3D).mesh is TextMesh:
			count += 1
	return count


func _all_textmesh_matte(root_node: Node) -> bool:
	for mesh_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh is not TextMesh:
			continue
		var material := mesh.get_active_material(0) as StandardMaterial3D
		if material == null or material.emission_enabled:
			return false
	return true


func _any_label_has_pressure_number(root_node: Node) -> bool:
	var ui := root_node.get("_ui") as CanvasLayer
	if ui == null:
		return false
	for label in ui.find_children("*", "Label", true, false):
		var text := (label as Label).text
		if text.contains("ДАВЛЕНИЕ") and text.to_lower() != text.to_upper():
			for digit in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]:
				if text.contains(digit):
					return true
	return false
