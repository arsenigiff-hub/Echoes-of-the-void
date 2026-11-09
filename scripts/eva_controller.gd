extends Node

# Контроллер выхода в открытый космос (EVA).
#
# Ответственность:
#   1) триггеры у внутренней двери шлюза и у внешнего люка;
#   2) анимация цикла шлюза (затемнение/глитч, шипение, открытие створок);
#   3) перевод игрока в режим невесомости и обратно;
#   4) подсказки и граница полёта (страховочный трос).
#
# Физика невесомости живёт в scripts/player.gd (eva_mode).

const FONT_PATH := "res://assetss/ui/fonts/CascadiaMono.ttf"
const CLUNK := "res://assetss/audio/intro/clunk.wav"
const HISS := "res://assetss/audio/intro/hull_groan.wav"
const ALARM := "res://assetss/audio/intro/alarm_loop.wav"

## Где появляется игрок, выйдя из шлюза (снаружи, у люка).
@export var exit_pos := Vector3(-10.4, 3.15, 11.9)
## Радиус страховочного троса от точки выхода.
@export var tether_length := 34.0
## После этой дистанции трос мягко тянет назад.
@export var hard_tether := 52.0

var player: Player = null
var camera: Camera3D = null
var interior_door: Node3D = null
var exterior_hatch: Node3D = null

var inside_trigger: Node3D = null
var outside_trigger: Node3D = null

var _ship_ext: Node3D = null
var _interior: Node3D = null
var _ship_light: OmniLight3D = null
var _hatch_light: OmniLight3D = null
var _env: WorldEnvironment = null
var _env_ambient := 0.36
var _ext_hatch: Node3D = null
var _hatch_pivot: Node3D = null
var _hull_body: StaticBody3D = null

var busy := false
var is_outside := false
var _inside_sum := 0

var _ui: CanvasLayer
var _fade: ColorRect
var _prompt: Label
var _status: Label
var _clunk: AudioStreamPlayer
var _hiss: AudioStreamPlayer
var _alarm: AudioStreamPlayer

var _interior_door_rest := Vector3.ZERO
var _hatch_rest_rot := Vector3.ZERO
var _hatch_rest_pos := Vector3.ZERO


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	player = get_parent().get_node_or_null("Player") as Player
	if player == null:
		push_warning("EVA: не найден Player")
		return
	camera = player.get_node_or_null("Head/Camera3D") as Camera3D
	interior_door = _find_named("airlock_door")
	if interior_door != null:
		_interior_door_rest = interior_door.position
	exterior_hatch = _find_named("AirlockExterior")
	if exterior_hatch != null:
		_hatch_pivot = exterior_hatch
		for c in exterior_hatch.get_children():
			if c is Node3D:
				_hatch_pivot = c as Node3D
				break
		_hatch_rest_rot = _hatch_pivot.rotation_degrees
		_hatch_rest_pos = _hatch_pivot.position

	_make_trigger("EVA_InsideTrigger", Vector3(-7.32, 3.28, 11.9),
			Vector3(0.18, 1.7, 1.7), false)
	_make_trigger("EVA_OutsideTrigger", exit_pos + Vector3(0.55, 0.0, 0.0),
			Vector3(0.35, 2.0, 2.0), true)

	_ship_ext = get_parent().get_node_or_null("ShipExterior") as Node3D
	_interior = get_parent().get_node_or_null("ShipInterior") as Node3D
	_ext_hatch = get_parent().get_node_or_null("AirlockExterior") as Node3D
	_ship_light = get_parent().get_node_or_null("EVAShipLight") as OmniLight3D
	_hatch_light = get_parent().get_node_or_null("EVAHatchLight") as OmniLight3D
	_env = get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _env != null and _env.environment != null:
		_env_ambient = _env.environment.ambient_light_energy
	_set_exterior_visible(false)
	_make_hull_collider()

	# Луч игрока должен видеть слой триггеров (2), тело — нет.
	var ray := player.get_node_or_null("Head/Camera3D/RayCast3D") as RayCast3D
	if ray != null:
		ray.collision_mask |= 2

	_build_ui()
	_build_audio()


func _process(delta: float) -> void:
	if player == null or busy:
		_update_status("")
		return
	if is_outside:
		_update_status(_outside_status())
		_tether(delta)
	else:
		_update_status("")


func _outside_status() -> String:
	var d := player.global_position.distance_to(exit_pos)
	if d > tether_length:
		return "ТРОС: НАТЯНУТ"
	return ""

# ------------------------------------------------------------- триггеры ----

func _make_trigger(node_name: String, pos: Vector3, size: Vector3, outside: bool) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.set_script(load("res://scripts/airlock_hatch.gd"))
	body.set("controller", self)
	body.set("outside_hatch", outside)
	get_parent().add_child(body)
	if outside:
		outside_trigger = body
	else:
		inside_trigger = body

# ------------------------------------------------------------------ API ----

func request_airlock(_player: CharacterBody3D) -> void:
	if busy or player == null:
		return
	if is_outside:
		_sequence_enter()
	else:
		_sequence_exit()

# --------------------------------------------------------------- циклы -----

func _sequence_exit() -> void:
	busy = true
	_play(_clunk, 0.2)
	await _fade_to(1.0, 0.9)
	if interior_door != null:
		_spin_door_open()
	await get_tree().create_timer(0.9).timeout
	var head := player.get_node_or_null("Head") as Node3D
	player.global_position = exit_pos
	player.velocity = Vector3.ZERO
	if head != null:
		head.rotation = Vector3(0.0, deg_to_rad(-90.0), 0.0)
	if camera != null:
		camera.rotation = Vector3.ZERO
	player.set_eva_mode(true)
	_set_exterior_visible(true)
	is_outside = true
	_open_hatch(true)
	_play(_hiss, 0.5)
	await get_tree().create_timer(0.4).timeout
	await _fade_to(0.0, 1.3)
	_update_status("")
	busy = false


func _sequence_enter() -> void:
	busy = true
	_play(_clunk, 0.2)
	await _fade_to(1.0, 0.8)
	player.set_eva_mode(false)
	var head := player.get_node_or_null("Head") as Node3D
	player.global_position = Vector3(-6.3, 2.1486 + 0.02, 11.9)
	player.velocity = Vector3.ZERO
	if head != null:
		head.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	if camera != null:
		camera.rotation = Vector3.ZERO
	is_outside = false
	_open_hatch(false)
	_ship_light = get_parent().get_node_or_null("EVAShipLight") as OmniLight3D
	_hatch_light = get_parent().get_node_or_null("EVAHatchLight") as OmniLight3D
	_env = get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if _env != null and _env.environment != null:
		_env_ambient = _env.environment.ambient_light_energy
	_set_exterior_visible(false)
	if interior_door != null:
		_spin_door_close()
	await get_tree().create_timer(0.9).timeout
	await _fade_to(0.0, 0.9)
	busy = false

# -------------------------------------------------------------- анимации ---

func _spin_door_open() -> void:
	if interior_door == null:
		return
	var t := create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_SINE)
	t.tween_property(interior_door, "position", _interior_door_rest + Vector3(-1.25, 0, 0), 1.1)
	t.tween_property(interior_door, "rotation_degrees",
			interior_door.rotation_degrees + Vector3(360, 0, 0), 1.1)


func _spin_door_close() -> void:
	if interior_door == null:
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(interior_door, "position", _interior_door_rest, 1.0)
	t.tween_property(interior_door, "rotation_degrees",
			interior_door.rotation_degrees - Vector3(360, 0, 0), 1.0)


func _open_hatch(open: bool) -> void:
	if _hatch_pivot == null:
		return
	var t := create_tween()
	t.set_trans(Tween.TRANS_CUBIC)
	var target_rot := _hatch_rest_rot + Vector3(0.0, 95.0, 0.0) if open else _hatch_rest_rot
	t.tween_property(_hatch_pivot, "rotation_degrees", target_rot, 1.4)

# ------------------------------------------------------------------ трос ---

func _tether(delta: float) -> void:
	var offset := player.global_position - exit_pos
	var dist := offset.length()
	if dist <= tether_length or dist < 0.01:
		return
	# мягко тянем к шлюзу, чем дальше — тем сильнее
	var pull := clampf((dist - tether_length) / (hard_tether - tether_length), 0.0, 1.0)
	player.velocity -= offset.normalized() * (1.5 + 6.0 * pull) * delta
	if dist > hard_tether:
		player.global_position = exit_pos + offset.normalized() * tether_length
		player.velocity *= 0.2

# ------------------------------------------------------------------- UI ----

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "EVA_UI"
	_ui.layer = 40
	get_parent().add_child(_ui)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 1)
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)

	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null

	_prompt = Label.new()
	_prompt.text = ""
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.offset_top = -140.0
	_prompt.offset_bottom = -100.0
	_prompt.add_theme_color_override("font_color", Color(0.83, 0.95, 0.84))
	if font != null:
		_prompt.add_theme_font_override("font", font)
		_prompt.add_theme_font_size_override("font_size", 22)
	root.add_child(_prompt)

	_status = Label.new()
	_status.text = ""
	_status.anchor_left = 0.03
	_status.anchor_right = 0.6
	_status.offset_top = 26.0
	_status.offset_bottom = 58.0
	_status.add_theme_color_override("font_color", Color(0.72, 0.86, 0.72))
	if font != null:
		_status.add_theme_font_override("font", font)
		_status.add_theme_font_size_override("font_size", 18)
	root.add_child(_status)


func _update_status(top: String) -> void:
	if _status != null:
		_status.text = top
	if _prompt == null or player == null or busy:
		if _prompt != null:
			_prompt.text = ""
		return
	var target := outside_trigger if is_outside else inside_trigger
	if target == null:
		_prompt.text = ""
		return
	var dist := player.global_position.distance_to(target.global_position)
	if dist > 3.2:
		_prompt.text = ""
		return
	var to_target := (target.global_position - (player.global_position + Vector3(0, 1.5, 0))).normalized()
	var look := -camera.global_transform.basis.z if camera != null else Vector3.FORWARD
	if look.dot(to_target) < 0.35:
		_prompt.text = ""
		return
	_prompt.text = "[E] ВОЙТИ В ШЛЮЗ" if is_outside else "[E] ОТКРЫТЬ ШЛЮЗ"


func _fade_to(alpha: float, seconds: float) -> void:
	if _fade == null:
		return
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", alpha, seconds)
	await t.finished

# ---------------------------------------------------------------- аудио ----

func _build_audio() -> void:
	_clunk = _audio(CLUNK, -8.0)
	_hiss = _audio(HISS, -6.0)
	_alarm = _audio(ALARM, -20.0)
	if _alarm != null:
		_alarm.play()


func _audio(path: String, db: float) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	get_parent().add_child(p)
	return p


func _play(p: AudioStreamPlayer, from: float = 0.0) -> void:
	if p == null:
		return
	p.play(from)

# --------------------------------------------------------------- утилиты ---

func _find_named(part: String) -> Node3D:
	var found: Node3D = null
	var stack: Array[Node] = [get_parent()]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is Node3D and String(node.name).to_lower().contains(part.to_lower()):
			found = node as Node3D
			break
		for c in node.get_children():
			stack.push_back(c)
	return found


# ------------------------------------------------- внешний корпус корабля ---

func _make_hull_collider() -> void:
	_hull_body = StaticBody3D.new()
	_hull_body.name = "EVA_HullCollider"
	_hull_body.position = Vector3(3.75, 4.1, 10.24)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(26.3, 6.8, 8.96)
	cs.shape = box
	_hull_body.add_child(cs)
	_hull_body.collision_layer = 0
	get_parent().add_child(_hull_body)


func _set_exterior_visible(v: bool) -> void:
	if _ship_ext != null:
		_ship_ext.visible = v
	if _ext_hatch != null:
		_ext_hatch.visible = v
	if _hull_body != null:
		_hull_body.collision_layer = 1 if v else 0
	if _interior != null:
		_interior.visible = not v
	if _ship_light != null:
		_ship_light.visible = v
	if _hatch_light != null:
		_hatch_light.visible = v
	if _env != null and _env.environment != null:
		_env.environment.ambient_light_energy = 1.3 if v else _env_ambient
