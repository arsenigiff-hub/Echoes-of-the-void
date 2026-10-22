extends Interactable

# Радио. Отвечает за три вещи:
#   1) подтянуть ТЕЛО игрока к прибору (не камеру — тело, вместе с камерой);
#   2) развернуть взгляд игрока на прибор;
#   3) пока игрок у прибора — двигать ползунки и крутить диск.
#
# Ключевая мысль: мы двигаем ровно те свойства, которыми игра управляет сама
# (позиция тела, yaw головы, pitch камеры). Поэтому после выхода мышь
# продолжает работать как ни в чём не бывало: мы вернули всё на место,
# а не "переставили камеру куда-то в сторону".
#
# ВАЖНО: камера всегда приезжает в ОДНУ И ТУ ЖЕ точку — узел CameraTarget
# внутри Radio. Поэтому кадр не зависит от того, с какой стороны и как далеко
# игрок подошёл: подтягивается тело, а камера встаёт ровно по этому узлу.
# Хочешь другой ракурс — просто подвинь CameraTarget в редакторе.
#
# Этот скрипт висит на узле Radio типа StaticBody3D — именно по нему
# попадает луч игрока, и именно поэтому у узла есть CollisionShape3D.

@export_group("Анимация фокуса")
## Сколько длится подъезд тела.
@export var move_time: float = 0.6
## Сколько длится доворот головы и камеры.
@export var look_time: float = 0.45

@export_group("Ползунки")
## Шаг одного нажатия в локальных единицах модели (0.05 * 0.3 = 1.5 см в мире).
@export var slider_step: float = 0.05
## Границы хода ползунков по локальному Y (внутри передней панели).
@export var slider_min_y: float = -2.20
@export var slider_max_y: float = -1.86
@export var slider_time: float = 0.15

@export_group("Диск")
@export var dial_step_deg: float = 60.0
@export var dial_time: float = 0.3

# Единственная точка фокуса. Камера приезжает РОВНО сюда, поэтому вид всегда
# одинаковый, с какой бы стороны игрок ни подошёл. Узел лежит внутри Radio,
# так что ракурс можно поправить прямо в редакторе, двигая CameraTarget.
@onready var camera_target: Camera3D = $CameraTarget

# Ползунки ищем по имени, а не четырьмя жёсткими путями: в модели Blockbench
# все четыре называются "slider_knob", и Godot сам добавил им номера 2, 3, 4.
# При реэкспорте модели номера могут поменяться — тогда скрипт просто найдёт
# их заново, а не сломается.
@onready var sliders: Array[Node3D] = _find_sliders()

# Диск — это "шляпка" крутилки. Ось у неё локальная Z (перпендикуляр
# к передней панели), а не UP, как было у старой модели радио.
@onready var dial: Node3D = $controls/dial_cap

var is_at_radio := false   # игрок сейчас у прибора
var is_moving := false     # проигрывается анимация — новые нажатия не берём
var slider_value := 0.0    # текущее положение ползунков (локальный Y)
var dial_angle := 0.0      # текущий угол диска в градусах

var _move_tween: Tween
var _slider_tween: Tween
var _dial_tween: Tween

# Что запомнили, чтобы вернуть игрока ровно туда, где он был.
var _saved_position := Vector3.ZERO
var _saved_head_yaw := 0.0
var _saved_camera_pitch := 0.0
var _saved_speed := 0.0


func _ready() -> void:
	# Берём стартовое положение ползунков из самой модели, а не из головы:
	# первое нажатие должно отсчитываться от того места, где они нарисованы.
	if not sliders.is_empty():
		slider_value = clampf(sliders[0].position.y, slider_min_y, slider_max_y)


func interact(player: CharacterBody3D) -> void:
	# Пока едет анимация, новые нажатия игнорируем: иначе два твина начнут
	# одновременно писать в одну и ту же позицию и тело задрожит.
	if is_moving:
		return

	var head := player.get_node_or_null("Head") as Node3D
	var camera := player.get_node_or_null("Head/Camera3D") as Camera3D
	if head == null or camera == null:
		push_warning("У игрока нет Head/Camera3D — фокус невозможен")
		return

	if is_at_radio:
		_exit(player, head, camera)
	else:
		_enter(player, head, camera)


func _enter(player: CharacterBody3D, head: Node3D, camera: Camera3D) -> void:
	if camera_target == null:
		push_error("Radio: нет узла CameraTarget — некуда ставить камеру")
		return

	# 1. Запоминаем то, что сейчас изменим, чтобы было чем вернуть.
	_saved_position = player.global_position
	_saved_head_yaw = head.rotation.y
	_saved_camera_pitch = camera.rotation.x
	_saved_speed = player.speed

	# 2. Забираем игрока себе: скорость в ноль плюс флаг, который
	#    останавливает его физику и обзор мышью.
	player.speed = 0.0
	player.is_interacting = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# 3. Куда встать телом. Поза фокуса одна и та же — её задаёт CameraTarget.
	#    Камера висит на голове, поэтому тело ставим так, чтобы камера
	#    оказалась ровно в точке фокуса: из позиции CameraTarget вычитаем
	#    мировой сдвиг головы (у стоящего игрока это просто 1.5 м вверх).
	var eye_offset: Vector3 = head.global_position - player.global_position
	var target_position: Vector3 = camera_target.global_position - eye_offset

	# 4. Направление взгляда берём из поворота CameraTarget: камера смотрит
	#    вдоль своей локальной -Z. Базис ортонормируем, потому что Radio
	#    отмасштабирован на 0.3, а нам нужны чистые оси без масштаба.
	var look_dir: Vector3 = -camera_target.global_transform.basis.orthonormalized().z

	# Формула перевода направления в углы этой игры. В Godot камера смотрит
	# вдоль своей -Z, поэтому:
	#   pitch — наклон вверх/вниз, живёт на Camera3D;
	#   yaw   — поворот вокруг вертикали, живёт на Head;
	#   Head повёрнут ВНУТРИ тела, поэтому из мирового угла вычитаем
	#   поворот тела, иначе при повторном входе взгляд уедет.
	var pitch := asin(clampf(look_dir.y, -1.0, 1.0))
	var target_yaw := atan2(-look_dir.x, -look_dir.z) - player.rotation.y
	# head.rotation.y — не «угол в градусах», а накопленный поворот: игрок
	# может накрутить его хоть на 720°. Берём ближайший эквивалент целевого
	# угла, чтобы твин не пошёл длинным путём и камера не делала лишний круг.
	var yaw := _nearest_equivalent_angle(head.rotation.y, target_yaw)

	# 5. Один твин на три свойства сразу. parallel() означает "и это тоже,
	#    одновременно с первым", а не "после него".
	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(player, "global_position", target_position, move_time)
	_move_tween.parallel().tween_property(head, "rotation:y", yaw, look_time)
	_move_tween.parallel().tween_property(camera, "rotation:x", pitch, look_time)

	is_at_radio = true
	is_moving = true
	await _move_tween.finished
	is_moving = false


func _exit(player: CharacterBody3D, head: Node3D, camera: Camera3D) -> void:
	# Возвращаем взгляд к сохранённому углу тоже по короткому пути: после
	# фокуса head.rotation.y мог накопиться, и «в лоб» камера снова
	# прокрутилась бы лишний круг.
	var return_yaw := _nearest_equivalent_angle(head.rotation.y, _saved_head_yaw)

	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(player, "global_position", _saved_position, move_time)
	_move_tween.parallel().tween_property(head, "rotation:y", return_yaw, look_time)
	_move_tween.parallel().tween_property(camera, "rotation:x", _saved_camera_pitch, look_time)

	is_at_radio = false
	is_moving = true
	await _move_tween.finished
	is_moving = false

	# Управление возвращаем только после того, как тело доехало: иначе физика
	# начнёт спорить с твином за одну и ту же позицию.
	player.speed = _saved_speed
	player.is_interacting = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func focus_input(event: InputEvent) -> void:
	if not is_at_radio or is_moving:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	# W/S — ползунки вверх/вниз, A/D — диск влево/вправо.
	if _is_key(key_event, KEY_W) or _is_key(key_event, KEY_UP):
		_move_sliders(1.0)
	elif _is_key(key_event, KEY_S) or _is_key(key_event, KEY_DOWN):
		_move_sliders(-1.0)
	elif _is_key(key_event, KEY_D) or _is_key(key_event, KEY_RIGHT):
		_turn_dial(1.0)
	elif _is_key(key_event, KEY_A) or _is_key(key_event, KEY_LEFT):
		_turn_dial(-1.0)


## Ползунки ходят вверх-вниз по локальному Y. Держим ОДНО число — положение
## прибора, а не позиции четырёх узлов: узлы лишь отражают это число.
## Поэтому они всегда согласованы между собой, и не важно, сколько их.
func _move_sliders(direction: float) -> void:
	var target: float = clampf(slider_value + direction * slider_step, slider_min_y, slider_max_y)
	if is_equal_approx(target, slider_value):
		return

	slider_value = target

	# Убиваем прошлый твин: два твина на одно и то же свойство дерутся
	# за него, и движение получается рваным.
	if _slider_tween != null:
		_slider_tween.kill()

	_slider_tween = create_tween()
	_slider_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for slider in sliders:
		_slider_tween.parallel().tween_property(slider, "position:y", target, slider_time)


func _turn_dial(direction: float) -> void:
	var target: float = clampf(dial_angle + direction * dial_step_deg, -360.0, 360.0)
	if is_equal_approx(target, dial_angle):
		return

	dial_angle = target

	if _dial_tween != null:
		_dial_tween.kill()

	_dial_tween = create_tween()
	_dial_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Ось диска — локальная Z (панель вертикальная), поэтому rotation:z.
	# Если диск крутится не в ту сторону — поменяй знак у direction.
	_dial_tween.tween_property(dial, "rotation:z", deg_to_rad(dial_angle), dial_time)


func _find_sliders() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in $controls.get_children():
		if child is Node3D and String(child.name).begins_with("slider_knob"):
			result.append(child as Node3D)
	return result


func _is_key(event: InputEventKey, key: Key) -> bool:
	return event.keycode == key or event.physical_keycode == key


## Возвращает угол, эквивалентный `to` (то же направление взгляда), но
## ближайший к `from`. Нужен потому, что head.rotation.y — накопленный
## поворот: 0.1 и 0.1 + 2π смотрят одинаково, а твин между ними крутит
## камеру на полный оборот.
func _nearest_equivalent_angle(from: float, to: float) -> float:
	return to + TAU * roundf((from - to) / TAU)
