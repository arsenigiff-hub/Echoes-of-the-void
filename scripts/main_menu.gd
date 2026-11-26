extends Node3D

## Главное меню в стиле референса:
## шипастый заголовок-картинка по центру сверху, слева — меню Russo One
## в тонких рамках, «>» у выбранного пункта.

const INDENT_IDLE := 25.0
const INDENT_ACTIVE := 39.0

@export var row_normal_style: StyleBoxFlat
@export var row_active_style: StyleBoxFlat

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var ui_root: Control = $CanvasLayer/UI
@onready var menu: VBoxContainer = $CanvasLayer/UI/MenuList
@onready var notice: Label = $CanvasLayer/UI/Notice
@onready var settings_overlay: Control = $CanvasLayer/UI/SettingsOverlay
@onready var back_button: Button = $CanvasLayer/UI/SettingsOverlay/Panel/BackButton

var _rows: Array[Button] = []
var _active := 0
var _settings_open := false
var _transition := false
var _notice_tween: Tween
var _profile_overlay: Control
var _profile_picker: OptionButton
var _profile_name: LineEdit
var _profile_password: LineEdit
var _profile_difficulty: OptionButton
var _profile_message: Label
var _profile_management_actions: Array[Button] = []
var _account_button: Button
var _profile_intent := "new"
var _profile_font: Font
var _profile_heading_font: Font
var _profile_db: Node


func _ready() -> void:
	_profile_db = get_node_or_null("/root/ProfileDB")
	for child in menu.get_children():
		if child is Button:
			_rows.append(child as Button)
	for i in _rows.size():
		_rows[i].focus_entered.connect(_set_active.bind(i))
		_rows[i].mouse_entered.connect(_set_active.bind(i))
	menu.mouse_exited.connect(_restore_focus_active)
	notice.hide()
	settings_overlay.hide()
	_profile_font = load("res://assetss/ui/fonts/CascadiaMono.ttf") as Font
	_profile_heading_font = load("res://assetss/ui/fonts/RussoOne-Regular.ttf") as Font
	_build_profile_overlay()
	_build_account_button()
	_set_active(0)
	if not _rows.is_empty():
		_rows[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _settings_open and event.is_action_pressed("ui_cancel"):
		_close_settings()
		get_viewport().set_input_as_handled()


# --- выбор пункта -----------------------------------------------------------

func _set_active(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_active = index
	for i in _rows.size():
		var row := _rows[i]
		var is_active := i == index
		var marker := row.get_node_or_null("Marker") as Line2D
		if marker:
			marker.visible = is_active
		var text := row.get_node_or_null("Text") as Label
		if text:
			text.offset_left = INDENT_ACTIVE if is_active else INDENT_IDLE
		if row_normal_style and row_active_style:
			row.add_theme_stylebox_override("normal", row_active_style if is_active else row_normal_style)


func _restore_focus_active() -> void:
	for i in _rows.size():
		if _rows[i].has_focus():
			_set_active(i)
			return
	_set_active(0)


# --- пункты меню ------------------------------------------------------------

func _on_play_button_pressed() -> void:
	if _transition:
		return
	_open_profiles("new")


func _start_new_game_flow() -> void:
	_transition = true
	_hide_notice()
	for row in _rows:
		row.disabled = true
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(ui_root, "modulate:a", 0.0, 0.45)
	tween.tween_callback(_start_new_game)


func _start_new_game() -> void:
	anim_player.play("new_animation")


func _on_continue_button_pressed() -> void:
	_open_profiles("continue")


func _on_settings_button_pressed() -> void:
	_open_settings()


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_back_button_pressed() -> void:
	_close_settings()


func _build_profile_overlay() -> void:
	_profile_overlay = Control.new()
	_profile_overlay.name = "ProfileOverlay"
	_profile_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_profile_overlay.hide()
	_profile_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(_profile_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.009, 0.016, 0.86)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_profile_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_profile_overlay.add_child(center)
	var panel := PanelContainer.new()
	# Let the form size itself to the visible actions. A fixed 700 px card left
	# a large dead area on the login/register flow, where management actions are hidden.
	panel.custom_minimum_size = Vector2(570, 0)
	panel.add_theme_stylebox_override("panel", _profile_panel_style())
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "ПРОФИЛЬ ЭКИПАЖА"
	title.add_theme_font_size_override("font_size", 24)
	_apply_profile_heading_font(title)
	column.add_child(title)
	var hint := Label.new()
	hint.text = "ЛОКАЛЬНЫЙ ДОСТУП // БЕЗ СЕТИ"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.57, 0.68, 0.74)
	_apply_profile_font(hint)
	column.add_child(hint)
	_profile_picker = OptionButton.new()
	_profile_picker.custom_minimum_size.y = 42
	_profile_picker.add_theme_font_size_override("font_size", 15)
	_apply_profile_font(_profile_picker)
	column.add_child(_profile_picker)
	_profile_name = LineEdit.new()
	_profile_name.placeholder_text = "Имя профиля — для нового или переименования"
	_profile_name.custom_minimum_size.y = 42
	_profile_name.max_length = 20
	_apply_profile_font(_profile_name)
	column.add_child(_profile_name)
	_profile_password = LineEdit.new()
	_profile_password.placeholder_text = "Пароль (не менее 6 символов)"
	_profile_password.secret = true
	_profile_password.custom_minimum_size.y = 42
	_profile_password.max_length = 128
	_apply_profile_font(_profile_password)
	column.add_child(_profile_password)
	var difficulty_label := Label.new()
	difficulty_label.text = "УРОВЕНЬ СЛОЖНОСТИ"
	difficulty_label.add_theme_font_size_override("font_size", 13)
	difficulty_label.modulate = Color(0.72, 0.79, 0.82)
	_apply_profile_heading_font(difficulty_label)
	column.add_child(difficulty_label)
	_profile_difficulty = OptionButton.new()
	_profile_difficulty.add_item("СТАНДАРТНЫЙ", 0)
	_profile_difficulty.add_item("СПОКОЙНЫЙ", 1)
	_profile_difficulty.add_item("НАПРЯЖЁННЫЙ", 2)
	_profile_difficulty.custom_minimum_size.y = 40
	_apply_profile_font(_profile_difficulty)
	column.add_child(_profile_difficulty)
	_profile_message = Label.new()
	_profile_message.custom_minimum_size.y = 0
	_profile_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_message.add_theme_font_size_override("font_size", 13)
	_apply_profile_font(_profile_message)
	column.add_child(_profile_message)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 8)
	column.add_child(actions)
	_add_profile_button(actions, "ВОЙТИ", _profile_login)
	_add_profile_button(actions, "СОЗДАТЬ", _profile_register)
	_profile_management_actions.append(_add_profile_button(actions, "ПЕРЕИМЕНОВАТЬ", _profile_rename))
	_profile_management_actions.append(_add_profile_button(actions, "УДАЛИТЬ", _profile_delete))
	_profile_management_actions.append(_add_profile_button(actions, "ТАБЛИЦА РЕЗУЛЬТАТОВ", _show_leaderboard))
	_add_profile_button(actions, "НАЗАД", _close_profiles)


func _profile_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.021, 0.03, 0.97)
	style.border_color = Color(0.58, 0.72, 0.79, 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _add_profile_button(parent: Container, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.add_theme_font_size_override("font_size", 13)
	_apply_profile_heading_font(button)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_account_button() -> void:
	_account_button = Button.new()
	_account_button.name = "AccountButton"
	_account_button.text = "ПРОФИЛЬ"
	_account_button.flat = true
	_account_button.anchor_left = 0.0
	_account_button.anchor_top = 1.0
	_account_button.anchor_right = 0.0
	_account_button.anchor_bottom = 1.0
	_account_button.offset_left = 48.0
	_account_button.offset_top = -62.0
	_account_button.offset_right = 250.0
	_account_button.offset_bottom = -22.0
	_account_button.add_theme_font_size_override("font_size", 13)
	_apply_profile_heading_font(_account_button)
	_account_button.add_theme_color_override("font_color", Color(0.62, 0.72, 0.76, 0.8))
	_account_button.add_theme_color_override("font_hover_color", Color(0.86, 0.91, 0.9))
	_account_button.pressed.connect(func() -> void: _open_profiles("manage"))
	ui_root.add_child(_account_button)


func _apply_profile_font(control: Control) -> void:
	if _profile_font != null:
		control.add_theme_font_override("font", _profile_font)


func _apply_profile_heading_font(control: Control) -> void:
	if _profile_heading_font != null:
		control.add_theme_font_override("font", _profile_heading_font)


func _open_profiles(intent: String) -> void:
	_profile_intent = intent
	_profile_message.text = ""
	_profile_name.text = ""
	_profile_password.text = ""
	var current_difficulty := String(_profile_db.get("difficulty")) if _profile_db != null else "standard"
	_profile_difficulty.select(0 if current_difficulty == "standard" else (1 if current_difficulty == "calm" else 2))
	_refresh_profile_list()
	for button in _profile_management_actions:
		button.visible = intent == "manage"
	_account_button.hide()
	_profile_overlay.show()
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _refresh_profile_list() -> void:
	_profile_picker.clear()
	var profiles: Array = _profile_db.call("list_profiles") if _profile_db != null else []
	for profile in profiles:
		_profile_picker.add_item(String(profile.username))
		_profile_picker.set_item_metadata(_profile_picker.item_count - 1, int(profile.id))
	if profiles.is_empty():
		_profile_picker.add_item("НЕТ СОЗДАННЫХ ПРОФИЛЕЙ")
		_profile_picker.set_item_disabled(0, true)


func _selected_profile_id() -> int:
	if _profile_picker.item_count == 0 or _profile_picker.is_item_disabled(_profile_picker.selected):
		return 0
	return int(_profile_picker.get_item_metadata(_profile_picker.selected))


func _profile_login() -> void:
	var username := _profile_name.text.strip_edges()
	if username.is_empty() and _selected_profile_id() != 0:
		username = _profile_picker.get_item_text(_profile_picker.selected)
	if _profile_db == null:
		_profile_message.text = "БАЗА ПРОФИЛЕЙ НЕ ЗАГРУЖЕНА"
		return
	var result: Dictionary = _profile_db.call("login", username, _profile_password.text)
	if not result.ok:
		_profile_message.text = String(result.error)
		return
	_apply_selected_difficulty()
	_profile_message.text = "ДОСТУП ПОДТВЕРЖДЁН // " + String(_profile_db.get("active_username"))
	_profile_authenticated()


func _profile_register() -> void:
	if _profile_db == null:
		_profile_message.text = "БАЗА ПРОФИЛЕЙ НЕ ЗАГРУЖЕНА"
		return
	var result: Dictionary = _profile_db.call("register_profile", _profile_name.text, _profile_password.text)
	if not result.ok:
		_profile_message.text = String(result.error)
		return
	_apply_selected_difficulty()
	_profile_message.text = "ПРОФИЛЬ СОЗДАН // " + String(_profile_db.get("active_username"))
	_profile_authenticated()


func _profile_rename() -> void:
	var selected_id := _selected_profile_id()
	if _profile_db == null:
		_profile_message.text = "БАЗА ПРОФИЛЕЙ НЕ ЗАГРУЖЕНА"
		return
	if selected_id > 0 and selected_id != int(_profile_db.get("active_profile_id")):
		var selected_name := _profile_picker.get_item_text(_profile_picker.selected)
		var login_result: Dictionary = _profile_db.call("login", selected_name, _profile_password.text)
		if not login_result.ok:
			_profile_message.text = String(login_result.error)
			return
	var result: Dictionary = _profile_db.call("rename_profile", _profile_name.text)
	_profile_message.text = "ИМЯ ПРОФИЛЯ ОБНОВЛЕНО" if result.ok else String(result.error)
	_refresh_profile_list()


func _profile_delete() -> void:
	var result: Dictionary = _profile_db.call("delete_profile", _selected_profile_id(), _profile_password.text) if _profile_db != null else {"ok": false, "error": "БАЗА ПРОФИЛЕЙ НЕ ЗАГРУЖЕНА"}
	_profile_message.text = "ПРОФИЛЬ И ЕГО ДАННЫЕ УДАЛЕНЫ" if result.ok else String(result.error)
	_refresh_profile_list()


func _apply_selected_difficulty() -> void:
	if _profile_db != null:
		_profile_db.set("difficulty", ["standard", "calm", "tense"][_profile_difficulty.selected])


func _profile_authenticated() -> void:
	await get_tree().create_timer(0.35).timeout
	_profile_overlay.hide()
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	if _account_button != null and _profile_db != null:
		_account_button.text = "ПРОФИЛЬ  //  " + String(_profile_db.get("active_username"))
	if _profile_intent == "manage":
		_account_button.show()
		return
	if _profile_intent == "continue":
		_account_button.show()
		_continue_profile()
	else:
		_start_new_game_flow()


func _continue_profile() -> void:
	if _profile_db == null:
		_show_notice("// БАЗА ПРОФИЛЕЙ НЕ ЗАГРУЖЕНА")
		return
	var save_data: Dictionary = _profile_db.call("load_progress")
	if save_data.is_empty():
		_show_notice("// СОХРАНЕНИЙ НЕ НАЙДЕНО")
		return
	_profile_db.set("difficulty", String(save_data.get("difficulty", _profile_db.get("difficulty"))))
	_profile_db.set("resume_requested", true)
	_profile_db.set("session_playtime", float(save_data.get("playtime_seconds", 0.0)))
	get_tree().change_scene_to_file("res://scenes/shuttle_blockout.tscn")


func _show_leaderboard() -> void:
	var rows: Array = _profile_db.call("leaderboard") if _profile_db != null else []
	if rows.is_empty():
		_profile_message.text = "ТАБЛИЦА ПОКА ПУСТА"
		return
	var lines: PackedStringArray = ["РЕКОРДЫ // ВРЕМЯ • СИГНАЛЫ"]
	for index in mini(rows.size(), 6):
		var row: Dictionary = rows[index]
		lines.append("%02d  %s  %s  %d СИГН." % [index + 1, row.username, _format_time(float(row.playtime_seconds)), int(row.signals_found)])
	_profile_message.text = "\n".join(lines)


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


func _close_profiles() -> void:
	_profile_overlay.hide()
	_account_button.show()
	menu.mouse_filter = Control.MOUSE_FILTER_STOP


func _unhandled_key_input(event: InputEvent) -> void:
	if _profile_overlay != null and _profile_overlay.visible and event.is_action_pressed("ui_cancel"):
		_close_profiles()
		get_viewport().set_input_as_handled()


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "new_animation":
		get_tree().change_scene_to_file("res://scenes/intro_cutscene.tscn")


# --- заглушка экрана настроек ----------------------------------------------

func _open_settings() -> void:
	_settings_open = true
	_hide_notice()
	for row in _rows:
		row.focus_mode = Control.FOCUS_NONE
	settings_overlay.show()
	back_button.grab_focus()


func _close_settings() -> void:
	_settings_open = false
	settings_overlay.hide()
	for row in _rows:
		row.focus_mode = Control.FOCUS_ALL
	if _active >= 0 and _active < _rows.size():
		_rows[_active].grab_focus()


# --- всплывающая заметка ----------------------------------------------------

func _show_notice(text: String) -> void:
	notice.text = text
	notice.modulate.a = 1.0
	notice.show()
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_interval(1.8)
	_notice_tween.tween_property(notice, "modulate:a", 0.0, 0.5)
	_notice_tween.tween_callback(notice.hide)


func _hide_notice() -> void:
	if _notice_tween != null and _notice_tween.is_valid():
		_notice_tween.kill()
	notice.hide()
	notice.modulate.a = 1.0
