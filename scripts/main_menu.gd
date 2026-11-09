extends Node3D

## Главное меню в стиле референса:
## шипастый заголовок-картинка по центру сверху, слева — меню Tektur
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


func _ready() -> void:
	for child in menu.get_children():
		if child is Button:
			_rows.append(child as Button)
	for i in _rows.size():
		_rows[i].focus_entered.connect(_set_active.bind(i))
		_rows[i].mouse_entered.connect(_set_active.bind(i))
	menu.mouse_exited.connect(_restore_focus_active)
	notice.hide()
	settings_overlay.hide()
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
	_show_notice("// СОХРАНЕНИЙ НЕ НАЙДЕНО")


func _on_settings_button_pressed() -> void:
	_open_settings()


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_back_button_pressed() -> void:
	_close_settings()


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
