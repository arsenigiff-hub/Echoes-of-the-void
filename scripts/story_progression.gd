extends Node

const REPAIR_SCRIPT := preload("res://scripts/story_repair_interactable.gd")
const SHORT_UI_FONT := preload("res://assetss/ui/fonts/RussoOne-Regular.ttf")
const READABLE_UI_FONT := preload("res://assetss/ui/fonts/CascadiaMono.ttf")
const OXYGEN_GENERATOR := preload("res://scripts/oxygen_generator.gd")
const REPAIR_HANDS_SCENE := preload("res://assetss/first_person_arms/drillimpact_psx/arms_rig.glb")
const REPAIR_GLOVE_TEXTURE := preload("res://assetss/first_person_arms/drillimpact_psx/arms_suit_gloves.png")
const REPAIR_HANDS_SHADER := preload("res://shaders/repair_hands_suit.gdshader")
const SOLAR_WINGS_PREVIEW_SCENE := "res://scenes/solar_wing_placement_preview.tscn"
const SOLAR_WING_REPAIR := preload("res://scripts/solar_wing_repair.gd")
const EVENTS_FILE := "res://data/story_events.json"

# The two large wings are separate interactive targets; the layout of each wing
# lives in scripts/solar_cell_grid.gd.
# Service wall in the passage, opposite the bunk. The generator front faces +X,
# so the player can work from the passage without entering the bunk furniture.
const OXYGEN_POSITION := Vector3(-0.73, 0.024, 3.68)
const REPAIR_SECONDS := {"oxygen": 5.0}

var stage := 0
var _player: Player
var _eva: Node
var _interior: Node3D
var _environment: WorldEnvironment
var _solar_visual: Node3D
var _solar_wings: Array[Node] = []
var _active_solar_wing: Node = null
var _operating_solar_wing: Node = null
var _oxygen: StaticBody3D
var _navigation: StaticBody3D
var _sleep_station: StaticBody3D
var _active_target: StaticBody3D
var _active_player: Player
var _action_mode := ""
var _repair_hands: Node3D
var _repair_hands_animation: AnimationPlayer
var _repair_elapsed := 0.0
var _oxygen_repair_step := 0
var _oxygen_pressure_index := 0
var _oxygen_generator: Node3D
var _canvas: CanvasLayer
var _status: Label
var _meter: ProgressBar
var _controls_hint: Label
var _event_timer := 0.0
var _event_data: Dictionary = {}
var _journal_entries: Array[String] = []
var _journal_panel: PanelContainer
var _journal_text: TextEdit
var journal_open := false
var _navigation_panel: PanelContainer
var _navigation_text: Label
var _nav_items: Array[Dictionary] = []
var _nav_index := 0
var _transition_canvas: CanvasLayer
var _transition_rect: ColorRect
var _space_stage: Node
var _run_recorded := false
var _profile_db: Node


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	await get_tree().process_frame
	var host := get_parent()
	_player = host.get_node_or_null("Player") as Player
	await _setup_repair_hands()
	_eva = host.get_node_or_null("EVA")
	_interior = host.get_node_or_null("ShipInterior") as Node3D
	_environment = host.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_profile_db = get_node_or_null("/root/ProfileDB")
	_space_stage = host.get_node_or_null("SpaceStage")
	_load_story_data()
	_create_solar_array(host)
	var interaction_parent: Node = _interior if _interior != null else host
	_create_oxygen_station(interaction_parent)
	_create_navigation_console(interaction_parent)
	_create_sleep_station(interaction_parent)
	_build_ui()
	var is_resume := _profile_db != null and bool(_profile_db.get("resume_requested")) and int(_profile_db.get("active_profile_id")) > 0
	if is_resume:
		_restore_profile_progress()
	else:
		stage = 0
		_journal_entries.clear()
		if _profile_db != null:
			_profile_db.set("session_playtime", 0.0)
	if stage >= 1 and _eva != null and _eva.has_method("stop_emergency_alarm"):
		_eva.call("stop_emergency_alarm", 0.0)
	_apply_power(mini(stage, 2))
	_update_targets()
	if _journal_entries.is_empty():
		_add_journal_entry("power_failure")
	_save_progress()
	if _profile_db != null:
		_profile_db.set("resume_requested", false)
	if not is_resume:
		call_deferred("_play_wake_intro")
	else:
		call_deferred("_show_controls_hint")


func _process(delta: float) -> void:
	if _profile_db != null and int(_profile_db.get("active_profile_id")) > 0:
		var previous_time := float(_profile_db.get("session_playtime"))
		var current_time := previous_time + delta
		_profile_db.set("session_playtime", current_time)
		if int(current_time) % 60 == 0 and int(previous_time) % 60 != 0:
			_save_progress()
	_update_targets()
	if _active_target != null and _action_mode == "repair" \
			and String(_active_target.get("repair_id")) not in ["solar", "oxygen"]:
		_repair_elapsed += delta
		var repair_duration := _repair_duration(String(_active_target.get("repair_id")))
		_meter.value = 100.0 * _repair_elapsed / repair_duration
		_status.text = "РАБОТА…  %02d%%     E — ПРЕРВАТЬ" % int(_meter.value)
		if _repair_elapsed >= repair_duration:
			_complete_repair()
	elif _event_timer > 0.0:
		_event_timer -= delta
		if _event_timer <= 0.0:
			_status.text = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_progress()


func _repair_duration(repair_id: String) -> float:
	var base := float(REPAIR_SECONDS.get(repair_id, 5.0))
	match String(_profile_db.get("difficulty")) if _profile_db != null else "standard":
		"calm": return base * 0.7
		"tense": return base * 1.4
	return base


func _setup_repair_hands() -> void:
	if _player == null or _player.camera == null:
		return
	_repair_hands = REPAIR_HANDS_SCENE.instantiate() as Node3D
	if _repair_hands == null:
		push_error("Could not instantiate the first-person repair hands")
		return
	_repair_hands.name = "RepairHandsViewmodel"
	_player.camera.add_child(_repair_hands)
	await get_tree().process_frame

	var skeleton := _repair_hands.find_child("Skeleton3D", true, false) as Skeleton3D
	var mesh := _repair_hands.find_child("ArmsMesh", true, false) as MeshInstance3D
	_repair_hands_animation = _repair_hands.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if skeleton == null or mesh == null or _repair_hands_animation == null:
		push_error("The first-person repair hands are missing their skeleton, mesh or animation player")
		_repair_hands.queue_free()
		_repair_hands = null
		return
	var camera_bone := skeleton.find_bone("camera")
	if camera_bone < 0:
		push_error("The first-person repair hands are missing their camera alignment bone")
		_repair_hands.queue_free()
		_repair_hands = null
		_repair_hands_animation = null
		return

	var material := ShaderMaterial.new()
	material.shader = REPAIR_HANDS_SHADER
	material.set_shader_parameter("source_texture", REPAIR_GLOVE_TEXTURE)
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The imported rig has a nonstandard camera-bone basis; align by its origin only.
	var bone_in_model := _repair_hands.global_transform.affine_inverse() \
			* skeleton.global_transform * skeleton.get_bone_global_pose(camera_bone)
	var viewmodel := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.50), Vector3.ZERO)
	viewmodel.origin = -(viewmodel.basis * bone_in_model.origin) + Vector3(0.0, 0.06, -0.50)
	_repair_hands.transform = viewmodel
	_repair_hands.visible = false
	_repair_hands_animation.animation_finished.connect(_on_repair_hands_animation_finished)


func _show_repair_hands() -> void:
	if _repair_hands == null or _repair_hands_animation == null:
		return
	_repair_hands.visible = true
	if _repair_hands_animation.has_animation("relax"):
		_repair_hands_animation.play("relax", 0.10)


func _play_repair_hands_action(animation_name: String) -> void:
	if _repair_hands == null or _repair_hands_animation == null:
		return
	_repair_hands.visible = true
	if not _repair_hands_animation.has_animation(animation_name):
		return
	if _repair_hands_animation.current_animation == animation_name \
			and _repair_hands_animation.is_playing():
		return
	_repair_hands_animation.play(animation_name, 0.12)


func _hide_repair_hands() -> void:
	if _repair_hands_animation != null and _repair_hands_animation.is_playing():
		_repair_hands_animation.stop()
	if _repair_hands != null:
		_repair_hands.visible = false


func _on_repair_hands_animation_finished(_animation_name: StringName) -> void:
	if _repair_hands == null or _repair_hands_animation == null:
		return
	if _action_mode == "repair" and _active_target != null \
			and String(_active_target.get("repair_id")) == "oxygen":
		_repair_hands_animation.play("relax", 0.10)
	else:
		_repair_hands.visible = false


func toggle_repair(repair_id: String, target: StaticBody3D, player_body: CharacterBody3D) -> void:
	if _active_target != null:
		if _action_mode == "navigation":
			_confirm_navigation()
		elif _action_mode == "solar_repair":
			if _operating_solar_wing != null:
				_operating_solar_wing.call("confirm")
		elif _action_mode == "repair":
			if String(_active_target.get("repair_id")) == "oxygen":
				_advance_oxygen_repair()
			else:
				cancel_repair()
		return
	if _player == null or player_body != _player or not _is_target_available(repair_id):
		return
	if repair_id == "solar":
		var wing := _solar_wing_for_target(target)
		if wing == null:
			return
		if not bool(wing.call("can_repair_from", _player.camera.global_position)):
			_player.interacting_object = null
			_status.text = "ОБОЙДИТЕ КРЫЛО · ДОСТУП С ОБРАТНОЙ СТОРОНЫ"
			_event_timer = 2.5
			return
		_active_target = target
		_action_mode = "solar_repair"
		_active_player = _player
		_operating_solar_wing = wing
		_repair_elapsed = 0.0
		_event_timer = 0.0
		_active_player.is_interacting = true
		_active_player.set("interacting_object", target)
		_player.camera_position_managed = true
		_meter.hide()
		if not bool(wing.call("begin", _player.camera)):
			cancel_repair()
		return
	if repair_id == "navigation":
		_begin_navigation(target)
		return
	if repair_id == "sleep":
		_begin_sleep(target)
		return
	_active_target = target
	_action_mode = "repair"
	_active_player = _player
	_repair_elapsed = 0.0
	_event_timer = 0.0
	_active_player.is_interacting = true
	_active_player.set("interacting_object", target)
	if repair_id == "oxygen":
		_show_repair_hands()
		_oxygen_repair_step = 0
		_oxygen_pressure_index = 0
		_meter.hide()
		if _oxygen_generator != null:
			_oxygen_generator.call("reset_repair")
			_oxygen_generator.call("set_fan_speed", 140.0)
		_update_oxygen_repair_prompt()
	else:
		_meter.show()
		_status.text = "РЕМОНТ НАЧАТ…  E — ПРЕРВАТЬ"


func _solar_wing_for_target(target: StaticBody3D) -> Node:
	for wing in _solar_wings:
		if wing != null and wing.get("target") == target:
			return wing
	return null


func set_status(text: String, seconds: float = 0.0) -> void:
	if _status == null:
		return
	_status.text = text
	_event_timer = seconds


func save_solar_progress() -> void:
	_save_progress()


func on_solar_wing_completed(_completed_wing_id: String) -> void:
	_end_solar_session()
	_active_solar_wing = _next_incomplete_solar_wing()
	_update_targets()
	if _active_solar_wing == null:
		stage = 1
		_apply_power(stage)
		_update_targets()
		if _eva != null and _eva.has_method("stop_emergency_alarm"):
			_eva.call("stop_emergency_alarm")
		_show_event("solar_power", 7.0)
	else:
		_status.text = "КРЫЛО ВОССТАНОВЛЕНО · ПЕРЕЙДИТЕ КО ВТОРОМУ"
		_event_timer = 5.0
	_save_progress()


func _next_incomplete_solar_wing() -> Node:
	for wing in _solar_wings:
		if wing != null and not bool(wing.call("is_complete")):
			return wing
	return null


func _end_solar_session() -> void:
	if _active_player != null:
		_active_player.is_interacting = false
		_active_player.interacting_object = null
		_active_player.camera_position_managed = false
		_active_player = null
	_operating_solar_wing = null
	_active_target = null
	_action_mode = ""
	_repair_elapsed = 0.0
	_meter.value = 0.0
	_meter.hide()


func _advance_oxygen_repair() -> void:
	match _oxygen_repair_step:
		0:
			_play_repair_hands_action("grab_R")
			_oxygen_repair_step = 1
			if _oxygen_generator != null:
				_oxygen_generator.call("set_valve_closed", true)
			_update_oxygen_repair_prompt()
		1:
			if _oxygen_pressure_index != 2:
				_status.text = "ДАВЛЕНИЕ ВНЕ ДОПУСКА  ·  A/D — ОТРЕГУЛИРОВАТЬ"
				return
			if _oxygen_generator != null:
				_oxygen_generator.call("set_gauge_color", Color(0.44, 0.58, 0.38))
			_play_repair_hands_action("push_R")
			_oxygen_repair_step = 2
			_update_oxygen_repair_prompt()
		2:
			_play_repair_hands_action("grab_L")
			_oxygen_repair_step = 3
			if _oxygen_generator != null:
				_oxygen_generator.call("remove_filter")
			_update_oxygen_repair_prompt()
		3:
			_play_repair_hands_action("grab_R")
			_oxygen_repair_step = 4
			if _oxygen_generator != null:
				_oxygen_generator.call("insert_filter")
				_oxygen_generator.call("set_valve_closed", false)
			_update_oxygen_repair_prompt()
		4:
			_complete_repair()


func _update_oxygen_repair_prompt() -> void:
	match _oxygen_repair_step:
		0:
			_status.text = "КИСЛОРОДНЫЙ КОНТУР  ·  E — ПЕРЕКРЫТЬ ПОДАЧУ"
		1:
			var settings := ["НИЖЕ", "НИЗКО", "НОРМА", "ВЫСОКО", "ВЫШЕ"]
			_status.text = "НАСТРОИТЬ ДАВЛЕНИЕ: %s  ·  A/D — РЕГУЛЯТОР  ·  E — ПРОВЕРИТЬ" % settings[_oxygen_pressure_index]
		2:
			_status.text = "ФИЛЬТР ЗАСОРЁН  ·  E — ИЗВЛЕЧЬ КАРТРИДЖ"
		3:
			_status.text = "УСТАНОВИТЬ ЗАПАСНОЙ ФИЛЬТР  ·  E — ЗАФИКСИРОВАТЬ"
		4:
			_status.text = "ПРОДУТЬ КОНТУР  ·  E — ВОЗОБНОВИТЬ ПОДАЧУ"


func _adjust_oxygen_pressure(direction: int) -> void:
	_oxygen_pressure_index = posmod(_oxygen_pressure_index + direction, 5)
	_play_repair_hands_action("grab_R")
	if _oxygen_generator != null:
		_oxygen_generator.call("set_gauge_index", _oxygen_pressure_index)
	_update_oxygen_repair_prompt()


func cancel_repair() -> void:
	if _operating_solar_wing != null:
		_operating_solar_wing.call("cancel")
		_end_solar_session()
		_status.text = "РЕМОНТ ПРЕРВАН"
		_event_timer = 2.0
		return
	if _active_target != null and String(_active_target.get("repair_id")) == "oxygen":
		_oxygen_repair_step = 0
		_oxygen_pressure_index = 0
		if _oxygen_generator != null:
			_oxygen_generator.call("reset_repair")
			_oxygen_generator.call("set_fan_speed", 90.0)
	if _active_player != null:
		_active_player.is_interacting = false
		_active_player.interacting_object = null
		_active_player = null
	_hide_repair_hands()
	_active_target = null
	_action_mode = ""
	_repair_elapsed = 0.0
	_meter.value = 0.0
	_meter.hide()
	_status.text = "РЕМОНТ ПРЕРВАН"
	_event_timer = 2.0


func reset_incomplete_eva_repair() -> void:
	if _operating_solar_wing == null:
		return
	_operating_solar_wing.call("reset_incomplete")
	_end_solar_session()


func notify_eva_oxygen_depleted() -> void:
	_status.text = "O2 ИСЧЕРПАН · ВОЗВРАТ К ШЛЮЗУ"
	_event_timer = 4.0


func _complete_repair() -> void:
	var completed := String(_active_target.get("repair_id"))
	if completed == "oxygen":
		_play_repair_hands_action("push_R")
	if _active_player != null:
		_active_player.is_interacting = false
		_active_player.interacting_object = null
	_active_player = null
	_active_target = null
	_action_mode = ""
	_repair_elapsed = 0.0
	_meter.value = 0.0
	_meter.hide()
	stage += 1
	_apply_power(stage)
	_update_targets()
	_show_event("oxygen_repaired", 6.0)
	_save_progress()


func _is_target_available(repair_id: String) -> bool:
	if repair_id == "solar":
		return stage == 0 and _eva != null and bool(_eva.get("is_outside")) \
			and _active_solar_wing != null \
			and not bool(_active_solar_wing.call("is_complete"))
	if repair_id == "oxygen":
		return stage == 1 and _eva != null and not bool(_eva.get("is_outside"))
	if repair_id == "navigation":
		return stage == 3 and _eva != null and not bool(_eva.get("is_outside"))
	if repair_id == "sleep":
		return stage == 4 and _eva != null and not bool(_eva.get("is_outside"))
	return false


func _update_targets() -> void:
	if _oxygen == null or _navigation == null or _sleep_station == null:
		return
	var is_outside := _eva != null and bool(_eva.get("is_outside"))
	var oxygen_available := stage == 1 and _eva != null and not bool(_eva.get("is_outside"))
	# Wings stay visible outside after repair, but only the current incomplete
	# wing accepts the interaction ray.
	if _solar_visual != null:
		_solar_visual.visible = is_outside
	for wing in _solar_wings:
		if wing == null:
			continue
		var wing_target := wing.get("target") as StaticBody3D
		if wing_target == null:
			continue
		var wing_available := stage == 0 and is_outside and wing == _active_solar_wing \
			and not bool(wing.call("is_complete"))
		wing_target.collision_layer = 2 if wing_available else 0
	_oxygen.visible = oxygen_available
	_oxygen.collision_layer = 2 if oxygen_available else 0
	var navigation_available := stage == 3 and _eva != null and not bool(_eva.get("is_outside"))
	_navigation.visible = navigation_available
	_navigation.collision_layer = 2 if navigation_available else 0
	var sleep_available := stage == 4 and _eva != null and not bool(_eva.get("is_outside"))
	_sleep_station.visible = sleep_available
	_sleep_station.collision_layer = 2 if sleep_available else 0


func _apply_power(power_stage: int) -> void:
	var fraction := 0.0 if power_stage == 0 else (0.36 if power_stage == 1 else 1.0)
	if _interior != null and _interior.has_method("set_story_power"):
		_interior.call("set_story_power", fraction)
	if _eva != null:
		_eva.call("set_indoor_ambient", get_indoor_ambient())
	elif _environment != null and _environment.environment != null:
		_environment.environment.ambient_light_energy = get_indoor_ambient()


func get_indoor_ambient() -> float:
	return 0.035 if stage == 0 else (0.075 if stage == 1 else 0.16)


func _save_progress() -> void:
	if _profile_db == null or int(_profile_db.get("active_profile_id")) <= 0:
		return
	var found_signals := 1 if stage >= 3 else 0
	_profile_db.call("save_progress", 0, stage, float(_profile_db.get("session_playtime")), found_signals,
		{
			"journal": _journal_entries.duplicate(),
			"run_recorded": _run_recorded,
			"solar_repaired": _solar_repaired_state(),
		})


func _solar_repaired_state() -> Dictionary:
	var state := {}
	for wing in _solar_wings:
		if wing == null:
			continue
		state[String(wing.get("wing_id"))] = wing.call("repaired_keys")
	return state


func _restore_profile_progress() -> void:
	if _profile_db == null:
		return
	var saved: Dictionary = _profile_db.call("load_progress")
	if saved.is_empty():
		_profile_db.set("resume_requested", false)
		return
	stage = clampi(int(saved.get("story_stage", 0)), 0, 5)
	_profile_db.set("difficulty", String(saved.get("difficulty", _profile_db.get("difficulty"))))
	var payload: Dictionary = saved.get("payload", {})
	var journal: Variant = payload.get("journal", [])
	_journal_entries.clear()
	if journal is Array:
		for entry in journal:
			_journal_entries.append(String(entry))
	_run_recorded = bool(payload.get("run_recorded", false))
	var solar_state: Variant = payload.get("solar_repaired", {})
	if stage >= 1:
		for wing in _solar_wings:
			if wing != null:
				wing.call("force_complete")
	elif solar_state is Dictionary:
		for wing in _solar_wings:
			if wing == null:
				continue
			var keys: Variant = (solar_state as Dictionary).get(String(wing.get("wing_id")), [])
			if keys is Array:
				wing.call("restore", keys)
	_active_solar_wing = _next_incomplete_solar_wing()
	if stage == 0 and _active_solar_wing == null:
		# Defensive: a save with every cell repaired but stage 0 still means the
		# power repair is done.
		stage = 1
	if stage >= 5 and _space_stage != null and _space_stage.has_method("set_stage"):
		_space_stage.call("set_stage", 1, true)


func _show_event(event_id: String, duration: float) -> void:
	var event: Dictionary = _event_data.get(event_id, {})
	_status.text = String(event.get("notice", "СИСТЕМА ОБНОВЛЕНА"))
	_add_journal_entry(event_id)
	_event_timer = duration


func _begin_navigation(target: StaticBody3D) -> void:
	_active_target = target
	_action_mode = "navigation"
	_active_player = _player
	_active_player.is_interacting = true
	_active_player.set("interacting_object", target)
	var course: Dictionary = _event_data.get("course", {})
	_nav_items = [
		{"label": "АЗИМУТ", "value": 90, "target": int(course.get("heading", 120)), "step": 10, "unit": "°"},
		{"label": "НАКЛОН", "value": 0, "target": int(course.get("pitch", 8)), "step": 1, "unit": "°"},
		{"label": "ИМПУЛЬС", "value": 0, "target": int(course.get("burn_seconds", 40)), "step": 5, "unit": " С"},
	]
	_nav_index = 0
	_update_navigation_text()
	_navigation_panel.show()
	_status.text = "КООРДИНАТЫ ЦУП // ПЕРЕДАЧА УСТАРЕЛА"


func _update_navigation_text() -> void:
	var matched := 0
	for item in _nav_items:
		if int(item["value"]) == int(item["target"]):
			matched += 1
	var lines := [
		"НАВИГАЦИОННЫЙ БЛОК  //  ПРИЁМ ПАКЕТА ЦУП",
		"СОВМЕСТИ ТЕКУЩЕЕ ЗНАЧЕНИЕ С ПАКЕТОМ И НАЖМИ E",
		"СОГЛАСОВАНО: %d / %d" % [matched, _nav_items.size()],
		"",
	]
	for i in _nav_items.size():
		var item: Dictionary = _nav_items[i]
		var marker := ">" if i == _nav_index else " "
		var is_match := int(item["value"]) == int(item["target"])
		var state := "СОВПАДАЕТ" if is_match else "НЕ СОВПАДАЕТ"
		lines.append("%s  %-8s  ТЕКУЩ: %03d%s     ПАКЕТ: %03d%s     %s" % [
			marker, item["label"], item["value"], item["unit"],
			item["target"], item["unit"], state])
	lines.append("")
	lines.append("W/S — выбрать  ·  A/D — изменить  ·  E — подтвердить  ·  Esc — выйти")
	if matched == _nav_items.size():
		lines.append("ПАКЕТ ПРИНЯТ — ПОДТВЕРДИ ПОСЛЕДНИЙ ПАРАМЕТР.")
	_navigation_text.text = "\n".join(lines)


func focus_story_target(target_id: String, event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
		if _action_mode == "navigation":
			_cancel_navigation()
		elif _action_mode in ["repair", "solar_repair"]:
			cancel_repair()
		return
	if _action_mode == "solar_repair" and target_id == "solar":
		var direction := Vector2i.ZERO
		if _is_key(key, KEY_W) or _is_key(key, KEY_UP):
			direction = Vector2i.UP
		elif _is_key(key, KEY_S) or _is_key(key, KEY_DOWN):
			direction = Vector2i.DOWN
		elif _is_key(key, KEY_A) or _is_key(key, KEY_LEFT):
			direction = Vector2i.LEFT
		elif _is_key(key, KEY_D) or _is_key(key, KEY_RIGHT):
			direction = Vector2i.RIGHT
		if direction != Vector2i.ZERO and _operating_solar_wing != null:
			_operating_solar_wing.call("move_selection", direction)
		return
	if _action_mode == "repair" and target_id == "oxygen":
		if _oxygen_repair_step == 1:
			if _is_key(key, KEY_D) or _is_key(key, KEY_RIGHT):
				_adjust_oxygen_pressure(1)
			elif _is_key(key, KEY_A) or _is_key(key, KEY_LEFT):
				_adjust_oxygen_pressure(-1)
		return
	if _action_mode != "navigation" or target_id != "navigation":
		return
	if _is_key(key, KEY_W) or _is_key(key, KEY_UP):
		_nav_index = posmod(_nav_index - 1, _nav_items.size())
	elif _is_key(key, KEY_S) or _is_key(key, KEY_DOWN):
		_nav_index = posmod(_nav_index + 1, _nav_items.size())
	elif _is_key(key, KEY_D) or _is_key(key, KEY_RIGHT):
		_change_navigation_value(1)
	elif _is_key(key, KEY_A) or _is_key(key, KEY_LEFT):
		_change_navigation_value(-1)
	_update_navigation_text()


func _change_navigation_value(direction: int) -> void:
	var item: Dictionary = _nav_items[_nav_index]
	var value := int(item["value"]) + direction * int(item["step"])
	match _nav_index:
		0: item["value"] = posmod(value, 360)
		1: item["value"] = clampi(value, -90, 90)
		2: item["value"] = clampi(value, 0, 600)
	_nav_items[_nav_index] = item


func _confirm_navigation() -> void:
	var item: Dictionary = _nav_items[_nav_index]
	if int(item["value"]) != int(item["target"]):
		_status.text = "ПАРАМЕТР НЕ СОВПАДАЕТ С ПРИНЯТЫМ ПАКЕТОМ"
		return
	_nav_index += 1
	if _nav_index >= _nav_items.size():
		_complete_navigation()
	else:
		_update_navigation_text()


func _complete_navigation() -> void:
	_navigation_panel.hide()
	_active_target = null
	_action_mode = ""
	if _active_player != null:
		_active_player.is_interacting = false
		_active_player.interacting_object = null
	_active_player = null
	stage = 4
	_update_targets()
	_show_event("course_entered", 7.0)
	_save_progress()


func _cancel_navigation() -> void:
	_navigation_panel.hide()
	_active_target = null
	_action_mode = ""
	if _active_player != null:
		_active_player.is_interacting = false
		_active_player.interacting_object = null
	_active_player = null
	_status.text = "ВВОД КУРСА ОТМЕНЁН"
	_event_timer = 3.0


func _begin_sleep(target: StaticBody3D) -> void:
	_active_target = target
	_action_mode = "sleep"
	_active_player = _player
	_active_player.is_interacting = true
	_active_player.set("interacting_object", target)
	_show_event("sleep_started", 4.0)
	call_deferred("_sleep_sequence")


func _sleep_sequence() -> void:
	await _fade_screen(1.0, 2.0)
	await get_tree().create_timer(2.8).timeout
	if _space_stage != null and _space_stage.has_method("set_stage"):
		_space_stage.call("set_stage", 1)
	await get_tree().create_timer(1.4).timeout
	stage = 5
	_active_target = null
	_action_mode = ""
	if _active_player != null:
		_active_player.is_interacting = false
		_active_player.interacting_object = null
	_active_player = null
	_update_targets()
	_show_event("ftl_wake", 10.0)
	if not _run_recorded and _profile_db != null and int(_profile_db.get("active_profile_id")) > 0:
		_profile_db.call("add_completion_record", float(_profile_db.get("session_playtime")), 1 if stage >= 3 else 0)
		_run_recorded = true
	_save_progress()
	await _fade_screen(0.0, 2.8)


func _fade_screen(alpha: float, duration: float) -> void:
	if _transition_canvas == null:
		_transition_canvas = CanvasLayer.new()
		_transition_canvas.name = "StoryTransition"
		_transition_canvas.layer = 120
		_transition_rect = ColorRect.new()
		_transition_rect.color = Color.BLACK
		_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_transition_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_transition_rect.modulate.a = 0.0
		_transition_canvas.add_child(_transition_rect)
		add_child(_transition_canvas)
	var tween := create_tween()
	tween.tween_property(_transition_rect, "modulate:a", alpha, duration)
	await tween.finished


func _is_key(event: InputEventKey, key: Key) -> bool:
	return event.keycode == key or event.physical_keycode == key


func on_first_radio_packet() -> void:
	if stage != 2:
		return
	stage = 3
	_show_event("earth_first_packet", 8.0)
	_save_progress()


func toggle_journal() -> void:
	if _active_target != null:
		return
	if _player != null and _player.is_interacting and _player.interacting_object != null:
		return
	journal_open = not journal_open
	_journal_panel.visible = journal_open
	if _player != null:
		_player.interacting_object = null
		_player.is_interacting = journal_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if journal_open else Input.MOUSE_MODE_CAPTURED


func _load_story_data() -> void:
	if not FileAccess.file_exists(EVENTS_FILE):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_FILE))
	if parsed is Dictionary:
		_event_data = parsed as Dictionary


func _add_journal_entry(event_id: String) -> void:
	var event: Dictionary = _event_data.get(event_id, {})
	var text := String(event.get("journal", ""))
	if text.is_empty():
		return
	_journal_entries.append("[%02d] %s" % [_journal_entries.size(), text])
	if _journal_text != null:
		_journal_text.text = "\n\n".join(_journal_entries)
		_journal_text.scroll_vertical = _journal_text.get_line_count()


func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "StoryHUD"
	_canvas.layer = 80
	add_child(_canvas)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(root)
	_status = Label.new()
	_status.anchor_left = 0.035
	_status.anchor_right = 0.8
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_top = -112.0
	_status.offset_bottom = -82.0
	_status.add_theme_font_override("font", READABLE_UI_FONT)
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(0.65, 0.72, 0.68, 0.85))
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_status.add_theme_constant_override("shadow_offset_x", 1)
	_status.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(_status)
	_meter = ProgressBar.new()
	_meter.anchor_left = 0.035
	_meter.anchor_right = 0.035
	_meter.anchor_top = 1.0
	_meter.anchor_bottom = 1.0
	_meter.offset_top = -72.0
	_meter.offset_bottom = -67.0
	_meter.offset_right = 220.0
	_meter.max_value = 100.0
	_meter.value = 0.0
	_meter.show_percentage = false
	_meter.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	var meter_fill := StyleBoxFlat.new()
	meter_fill.bg_color = Color(0.58, 0.68, 0.63, 0.72)
	_meter.add_theme_stylebox_override("fill", meter_fill)
	root.add_child(_meter)
	_meter.hide()
	_controls_hint = Label.new()
	_controls_hint.text = "WASD — движение     мышь — обзор     E — действие     F — фонарь     Tab — журнал"
	_controls_hint.anchor_left = 0.035
	_controls_hint.anchor_right = 0.85
	_controls_hint.anchor_top = 1.0
	_controls_hint.anchor_bottom = 1.0
	_controls_hint.offset_top = -44.0
	_controls_hint.offset_bottom = -20.0
	_controls_hint.add_theme_font_override("font", READABLE_UI_FONT)
	_controls_hint.add_theme_font_size_override("font_size", 13)
	_controls_hint.add_theme_color_override("font_color", Color(0.72, 0.76, 0.73, 0.88))
	_controls_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_controls_hint.add_theme_constant_override("shadow_offset_x", 1)
	_controls_hint.add_theme_constant_override("shadow_offset_y", 1)
	_controls_hint.modulate.a = 0.0
	root.add_child(_controls_hint)
	var journal_hint := Label.new()
	journal_hint.text = "TAB — БОРТОВОЙ ЖУРНАЛ"
	journal_hint.anchor_left = 1.0
	journal_hint.anchor_right = 1.0
	journal_hint.offset_left = -310.0
	journal_hint.offset_right = -24.0
	journal_hint.offset_top = 22.0
	journal_hint.offset_bottom = 46.0
	journal_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	journal_hint.add_theme_font_override("font", READABLE_UI_FONT)
	journal_hint.add_theme_font_size_override("font_size", 13)
	journal_hint.add_theme_color_override("font_color", Color(0.58, 0.68, 0.62, 0.8))
	journal_hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	journal_hint.add_theme_constant_override("shadow_offset_x", 1)
	journal_hint.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(journal_hint)
	_journal_panel = PanelContainer.new()
	_journal_panel.position = Vector2(350, 140)
	_journal_panel.custom_minimum_size = Vector2(620, 460)
	_journal_panel.visible = false
	var journal_panel_style := StyleBoxFlat.new()
	journal_panel_style.bg_color = Color(0.012, 0.022, 0.020, 0.92)
	journal_panel_style.set_border_width_all(1)
	journal_panel_style.border_color = Color(0.20, 0.34, 0.29, 0.9)
	journal_panel_style.set_corner_radius_all(4)
	journal_panel_style.set_content_margin_all(24)
	_journal_panel.add_theme_stylebox_override("panel", journal_panel_style)
	_canvas.add_child(_journal_panel)
	var journal_stack := VBoxContainer.new()
	journal_stack.add_theme_constant_override("separation", 10)
	_journal_panel.add_child(journal_stack)
	var journal_title := Label.new()
	journal_title.text = "БОРТОВОЙ ЖУРНАЛ  //  TAB — ЗАКРЫТЬ"
	journal_title.add_theme_font_override("font", SHORT_UI_FONT)
	journal_title.add_theme_font_size_override("font_size", 22)
	journal_title.add_theme_color_override("font_color", Color(0.78, 0.90, 0.84))
	journal_stack.add_child(journal_title)
	_journal_text = TextEdit.new()
	_journal_text.editable = false
	_journal_text.custom_minimum_size = Vector2(570, 370)
	_journal_text.add_theme_font_override("font", READABLE_UI_FONT)
	_journal_text.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_journal_text.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_journal_text.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	_journal_text.add_theme_font_size_override("font_size", 18)
	_journal_text.add_theme_color_override("font_color", Color(0.72, 0.80, 0.75))
	journal_stack.add_child(_journal_text)
	_navigation_panel = PanelContainer.new()
	_navigation_panel.position = Vector2(250, 220)
	_navigation_panel.custom_minimum_size = Vector2(860, 320)
	_navigation_panel.visible = false
	var navigation_panel_style := StyleBoxFlat.new()
	navigation_panel_style.bg_color = Color(0.010, 0.024, 0.020, 0.92)
	navigation_panel_style.set_border_width_all(1)
	navigation_panel_style.border_color = Color(0.18, 0.42, 0.32, 0.95)
	navigation_panel_style.set_corner_radius_all(4)
	navigation_panel_style.set_content_margin_all(26)
	_navigation_panel.add_theme_stylebox_override("panel", navigation_panel_style)
	_canvas.add_child(_navigation_panel)
	_navigation_text = Label.new()
	_navigation_text.add_theme_font_override("font", READABLE_UI_FONT)
	_navigation_text.add_theme_font_size_override("font_size", 20)
	_navigation_text.add_theme_color_override("font_color", Color(0.72, 0.90, 0.80))
	_navigation_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_navigation_panel.add_child(_navigation_text)


func _show_controls_hint() -> void:
	await get_tree().create_timer(3.0).timeout
	if not is_instance_valid(_controls_hint):
		return
	var tween := create_tween()
	tween.tween_property(_controls_hint, "modulate:a", 0.72, 0.35)
	tween.tween_interval(3.0)
	tween.tween_property(_controls_hint, "modulate:a", 0.0, 1.4)


func _play_wake_intro() -> void:
	if _player == null or not is_instance_valid(_player.head) or not is_instance_valid(_player.camera):
		return
	var head := _player.head
	var camera := _player.camera
	var standing_head := head.position
	var standing_camera_rotation := camera.rotation
	_player.is_interacting = true
	_player.interacting_object = null
	_player.velocity = Vector3.ZERO
	_player.flashlight.visible = false
	_player.flashlight_flag = false
	head.position = Vector3(0.0, 0.30, 0.0)
	head.rotation = Vector3(0.0, 0.0, deg_to_rad(-7.0))
	camera.rotation = Vector3(deg_to_rad(-61.0), 0.0, 0.0)
	# A few diminishing roll jolts sell the impact and disorientation without
	# turning the shot into a camera-shake effect that obscures the room.
	var groggy := create_tween()
	groggy.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	groggy.tween_property(head, "rotation:z", deg_to_rad(2.2), 0.14)
	groggy.tween_property(head, "rotation:z", deg_to_rad(-1.5), 0.19)
	groggy.tween_property(head, "rotation:z", deg_to_rad(0.8), 0.23)
	groggy.tween_property(head, "rotation:z", 0.0, 0.32)
	await get_tree().create_timer(1.35).timeout
	var rise := create_tween().set_parallel(true)
	rise.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	rise.tween_property(head, "position", Vector3(0.0, 0.92, 0.0), 1.45)
	rise.tween_property(camera, "rotation", Vector3(deg_to_rad(-20.0), 0.0, 0.0), 1.45)
	rise.tween_property(head, "rotation", Vector3.ZERO, 1.45)
	await rise.finished
	var settle := create_tween().set_parallel(true)
	settle.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	settle.tween_property(head, "position", standing_head, 1.2)
	settle.tween_property(camera, "rotation", standing_camera_rotation, 1.2)
	await settle.finished
	_player.is_interacting = false
	call_deferred("_show_controls_hint")


func _create_solar_array(host: Node) -> void:
	_solar_wings.clear()
	_solar_visual = _make_solar_visual(host)
	if _solar_visual == null:
		return
	_solar_visual.visible = false
	var surfaces := {
		"fore": _solar_visual.find_child("solar-array-wing-deployed_3_001", true, false) as MeshInstance3D,
		"aft": _solar_visual.find_child("solar-array-wing-deployed_3_002", true, false) as MeshInstance3D,
	}
	for wing_id in ["fore", "aft"]:
		var surface := surfaces[wing_id] as MeshInstance3D
		if surface == null:
			push_warning("Solar wing surface missing: " + String(wing_id))
			continue
		var aabb := surface.mesh.get_aabb()
		var solar_target := StaticBody3D.new()
		solar_target.set_script(REPAIR_SCRIPT)
		solar_target.name = "SolarArrayRepair_" + String(wing_id)
		solar_target.set("repair_id", "solar")
		solar_target.set("progression", self)
		solar_target.collision_layer = 0
		solar_target.collision_mask = 0
		host.add_child(solar_target)
		solar_target.global_transform = Transform3D(
			surface.global_basis.orthonormalized(),
			surface.to_global(aabb.get_center()))
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(
			aabb.size.x * surface.global_basis.x.length() + 0.4,
			0.8,
			aabb.size.z * surface.global_basis.z.length() + 0.4)
		collision.shape = shape
		solar_target.add_child(collision)
		var wing := SOLAR_WING_REPAIR.new()
		wing.name = "SolarWingRepair_" + String(wing_id)
		host.add_child(wing)
		wing.call("setup", String(wing_id), self, solar_target, surface)
		_solar_wings.append(wing)
	_active_solar_wing = _next_incomplete_solar_wing()


func _make_solar_visual(host: Node) -> Node3D:
	var packed := load(SOLAR_WINGS_PREVIEW_SCENE) as PackedScene
	if packed == null:
		push_warning("Не удалось загрузить сцену расстановки солнечных крыльев: " + SOLAR_WINGS_PREVIEW_SCENE)
		return null
	var composition := packed.instantiate() as Node3D
	var visual := composition.get_node_or_null("SolarWings") as Node3D
	if visual == null:
		composition.queue_free()
		push_warning("В сцене предпросмотра нет узла SolarWings")
		return null
	composition.remove_child(visual)
	composition.queue_free()
	visual.name = "SolarWingsVisual"
	visual.owner = null
	host.add_child(visual)
	return visual


func _create_oxygen_station(host: Node) -> void:
	_oxygen = StaticBody3D.new()
	_oxygen.set_script(REPAIR_SCRIPT)
	_oxygen.name = "OxygenServiceInteractable"
	_oxygen.set("repair_id", "oxygen")
	_oxygen.set("progression", self)
	_oxygen.position = OXYGEN_POSITION
	_oxygen.rotation_degrees.y = 90.0
	_oxygen.collision_layer = 0
	_oxygen.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.3, 1.5, 1.2)
	collision.shape = shape
	collision.position.y = 0.75
	_oxygen.add_child(collision)
	_oxygen_generator = OXYGEN_GENERATOR.new()
	_oxygen_generator.name = "OxygenGeneratorAssembly"
	_oxygen.add_child(_oxygen_generator)
	host.add_child(_oxygen)
	_oxygen.visible = false


func _create_navigation_console(host: Node) -> void:
	_navigation = StaticBody3D.new()
	_navigation.set_script(REPAIR_SCRIPT)
	_navigation.name = "NavigationConsoleInteractable"
	_navigation.set("repair_id", "navigation")
	_navigation.set("progression", self)
	_navigation.position = Vector3(2.64, 0.024, -14.64)
	_navigation.collision_layer = 0
	_navigation.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	# Match the authored console footprint; the old shallow box let the player
	# stand inside the model and clip through its front controls.
	shape.size = Vector3(0.95, 1.55, 1.40)
	collision.shape = shape
	collision.position.y = 0.80
	_navigation.add_child(collision)
	var console_scene := load("res://assetss/rooms/navigation_console/navigation_console_v2.glb") as PackedScene
	if console_scene != null:
		var model := console_scene.instantiate() as Node3D
		model.name = "NavigationConsoleModel"
		_navigation.add_child(model)
		_apply_pixel_texture_filter(model)
	else:
		# Safety fallback if the authored asset is missing.
		var shell_mat := _material(Color(0.20, 0.23, 0.24), 0.68, 0.55)
		var screen_mat := StandardMaterial3D.new()
		screen_mat.albedo_color = Color(0.015, 0.05, 0.045)
		screen_mat.emission_enabled = true
		screen_mat.emission = Color(0.08, 0.44, 0.30)
		screen_mat.emission_energy_multiplier = 0.45
		_add_box(_navigation, Vector3(0.92, 0.78, 0.22), Vector3(0, 0.46, 0), shell_mat)
		_add_box(_navigation, Vector3(0.78, 0.45, 0.03), Vector3(0, 0.88, -0.13), screen_mat)
		_add_box(_navigation, Vector3(0.16, 0.05, 0.04), Vector3(-0.31, 0.22, -0.14), screen_mat)
	host.add_child(_navigation)
	_navigation.visible = false


func _apply_pixel_texture_filter(root_node: Node) -> void:
	for mesh_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material == null:
				continue
			var pixelated := material.duplicate() as StandardMaterial3D
			pixelated.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mesh.set_surface_override_material(surface, pixelated)


func _create_sleep_station(host: Node) -> void:
	_sleep_station = StaticBody3D.new()
	_sleep_station.set_script(REPAIR_SCRIPT)
	_sleep_station.name = "SleepStationInteractable"
	_sleep_station.set("repair_id", "sleep")
	_sleep_station.set("progression", self)
	_sleep_station.position = Vector3(-1.35, 0.605, -3.45)
	_sleep_station.collision_layer = 0
	_sleep_station.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 0.62, 1.45)
	collision.shape = shape
	collision.position.y = 0.22
	_sleep_station.add_child(collision)
	var indicator := StandardMaterial3D.new()
	indicator.albedo_color = Color(0.36, 0.08, 0.035)
	indicator.emission_enabled = true
	indicator.emission = Color(0.8, 0.08, 0.025)
	indicator.emission_energy_multiplier = 0.6
	var panel_shell := _material(Color(0.12, 0.14, 0.13), 0.5, 0.72)
	var bracket := _add_box(_sleep_station, Vector3(0.05, 0.58, 0.05),
		Vector3(0.42, 0.19, -0.64), panel_shell)
	bracket.name = "SleepPanelBracket"
	var base := _add_box(_sleep_station, Vector3(0.16, 0.03, 0.16),
		Vector3(0.42, -0.10, -0.64), panel_shell)
	base.name = "SleepPanelBase"
	var panel := _add_box(_sleep_station, Vector3(0.20, 0.26, 0.05),
		Vector3(0.42, 0.48, -0.64), panel_shell)
	panel.name = "SleepPanelHousing"
	_add_box(_sleep_station, Vector3(0.09, 0.09, 0.02),
		Vector3(0.42, 0.48, -0.672), indicator)
	host.add_child(_sleep_station)
	_sleep_station.visible = false


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.material_override = material
	mesh_node.position = pos
	parent.add_child(mesh_node)
	return mesh_node


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
