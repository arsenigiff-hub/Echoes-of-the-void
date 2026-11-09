class_name Player
extends CharacterBody3D

# Игрок отвечает ровно за три вещи:
#   1) движение по полу и гравитация;
#   2) обзор мышью;
#   3) решение "на что я смотрю и можно ли это использовать".
#
# Всё, что происходит ПОСЛЕ входа в предмет (камера, ползунки, диск),
# игрока не касается: это дело самого предмета. Игрок только выставляет
# флаг is_interacting и отдаёт предмету клавиши.

@export var speed: float = 3.0
@export var gravity: float = 9.8
@export var mouse_sensetivity: float = 0.003

@export_group("EVA (невесомость)")
## Тяга скафандра, м/с².
@export var eva_thrust: float = 7.0
## Торможение (вязкость среды), 1/с.
@export var eva_damping: float = 1.1
## Максимальная скорость в невесомости, м/с.
@export var eva_max_speed: float = 7.5

## Режим свободного полёта в космосе (гравитация и пол отключены).
var eva_mode: bool = false

@export_group("Камера: дыхание и шаг")
## Включить покачивание/дыхание камеры (атмосфера, «живой» игрок).
@export var bob_enabled: bool = true
## Амплитуда покачивания при ходьбе (метры).
@export var bob_amplitude: float = 0.020
## Амплитуда дыхания в покое (метры).
@export var breathe_amplitude: float = 0.006

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: RayCast3D = $Head/Camera3D/RayCast3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/SpotLight3D

var flashlight_flag: bool = false
var is_interacting: bool = false
var interacting_object: Interactable = null

var _bob_time: float = 0.0
var _breathe_time: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Фонарь в сцене может быть включён по умолчанию — приводим его к флагу,
	# иначе первое нажатие F ничего не меняет (и на старте светло).
	flashlight.visible = flashlight_flag


func _process(delta: float) -> void:
	# Камера «дышит» и покачивается при ходьбе. Меняем только локальную
	# позицию камеры: вращение (мышь) и фокус на предметах не затрагиваются.
	if not bob_enabled or is_interacting or eva_mode:
		camera.position = Vector3.ZERO
		_bob_time = 0.0
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.15:
		_bob_time += delta * (5.0 + horizontal_speed * 1.6)
		var strength := clampf(horizontal_speed / maxf(speed, 0.001), 0.0, 1.0)
		var bob_y := sin(_bob_time * 2.0) * bob_amplitude * strength
		var bob_x := cos(_bob_time) * bob_amplitude * 0.55 * strength
		camera.position = Vector3(bob_x, bob_y, 0.0)
	else:
		_bob_time = 0.0
		_breathe_time += delta
		var breathe := sin(_breathe_time * 1.15) * breathe_amplitude \
				+ sin(_breathe_time * 0.41 + 1.7) * breathe_amplitude * 0.5
		camera.position = Vector3(0.0, breathe, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey

		# Нас интересуют только настоящие нажатия. echo = true — это
		# автоповтор, который система присылает, ПОКА клавишу держат.
		# Без этой проверки удержание E превратилось бы в очередь
		# из входов и выходов, потому что автоповтор идёт десятками
		# событий в секунду.
		if not key_event.pressed or key_event.echo:
			return

		if _is_key(key_event, KEY_F):
			_toggle_flashlight()
			return

		if _is_key(key_event, KEY_E):
			_interact_pressed()
			return

		# Всё остальное, пока игрок в предмете, отдаём предмету.
		# Игрок не знает, что это за клавиши: решает предмет.
		if is_interacting and interacting_object != null:
			interacting_object.focus_input(key_event)
		return

	# Мышь работает только в обычном режиме. Пока игрок в предмете, курсор
	# отпущен (MOUSE_MODE_VISIBLE), а обзор заблокирован флагом, поэтому
	# камера смотрит ровно туда, куда её поставил предмет.
	if event is InputEventMouseMotion \
			and not is_interacting \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * mouse_sensetivity)
		camera.rotate_x(-event.relative.y * mouse_sensetivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))


func _toggle_flashlight() -> void:
	flashlight_flag = not flashlight_flag
	flashlight.visible = flashlight_flag


func _interact_pressed() -> void:
	if is_interacting:
		# ВЫХОД. Ищем не лучом, а тем же объектом, что и при входе.
		# Тело и камера уже уехали к прибору, и луч может смотреть куда
		# угодно — если проверять луч, игрок застрянет в фокусе.
		if interacting_object != null:
			interacting_object.interact(self)
		return

	# ВХОД. Условие ровно одно: луч смотрит на предмет.
	if not interaction_ray.is_colliding():
		return
	var target := interaction_ray.get_collider() as Interactable
	if target == null:
		return
	interacting_object = target
	target.interact(self)


func _physics_process(delta: float) -> void:
	# Пока предмет управляет игроком, физику не трогаем вообще.
	# Если звать move_and_slide, он начнёт "прилипать" к полу и
	# расталкивать капсулу, споря с твином, который двигает тело.
	if is_interacting:
		velocity = Vector3.ZERO
		return

	if eva_mode:
		_eva_physics(delta)
		return

	var input_dir := Vector2.ZERO

	if is_on_floor() and Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = 4.5

	if not is_on_floor():
		velocity.y -= gravity * delta

	# is_physical_key_pressed — это позиция клавиши, а не символ раскладки.
	# На русской раскладке is_key_pressed(KEY_W) не сработал бы, потому что
	# клавиша даёт символ "ц".
	if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
	if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
	if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1
	input_dir = input_dir.normalized()

	var direction: Vector3 = (head.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()


## Одна и та же клавиша приходит в двух видах: keycode — символ, который она
## даёт в текущей раскладке (на русской это кириллица), physical_keycode —
## всегда физическая позиция клавиши. Проверяем оба, чтобы управление
## не зависело от раскладки.
func _is_key(event: InputEventKey, key: Key) -> bool:
	return event.keycode == key or event.physical_keycode == key


# ------------------------------------------------------------- невесомость --

## Переключение режима скафандра (EVA). Вызывает контроллер шлюза.
func set_eva_mode(enabled: bool) -> void:
	eva_mode = enabled
	velocity = Vector3.ZERO
	if camera != null:
		camera.position = Vector3.ZERO
	if head != null and enabled:
		# тело больше не должно «прилипать» к полу — сбрасываем скольжение
		velocity = Vector3.ZERO


## Полёт в невесомости: тяга относительно взгляда, инерция, торможение.
func _eva_physics(delta: float) -> void:
	var thrust := Vector3.ZERO
	var basis := camera.global_transform.basis
	if Input.is_physical_key_pressed(KEY_W):
		thrust -= basis.z
	if Input.is_physical_key_pressed(KEY_S):
		thrust += basis.z
	if Input.is_physical_key_pressed(KEY_D):
		thrust += basis.x
	if Input.is_physical_key_pressed(KEY_A):
		thrust -= basis.x
	if Input.is_physical_key_pressed(KEY_SPACE):
		thrust += basis.y
	if Input.is_physical_key_pressed(KEY_CTRL):
		thrust -= basis.y
	if thrust.length_squared() > 0.0:
		velocity += thrust.normalized() * eva_thrust * delta
	velocity *= maxf(0.0, 1.0 - eva_damping * delta)
	velocity = velocity.limit_length(eva_max_speed)
	move_and_slide()
