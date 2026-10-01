class_name Player
extends CharacterBody3D

var flashlight_flag: bool = false
var interacting_object: Interactable = null

@export var speed: float = 10.0
@export var gravity: float = 9.8
@export var mouse_sensetivity: float = 0.003

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: RayCast3D = $Head/Camera3D/RayCast3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/SpotLight3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
func _try_interact() -> void:
	print("Я нажал E")
	if interaction_ray.is_colliding():
		print("Луч что то нашел")
		var target = interaction_ray.get_collider()
		print(target)
		print("Это Interactable", target is Interactable)
		if target is Interactable:
			interacting_object = target
			target.interact(self)
	
func _unhandled_input(event: InputEvent) -> void:
	if is_interacting:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_D:
			interacting_object.focus_input(event)
			return
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_A:
			interacting_object.focus_input(event)
		
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * mouse_sensetivity)
		
		camera.rotate_x(-event.relative.y * mouse_sensetivity)
		
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		_try_interact()
		
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		if flashlight_flag == false: 
			flashlight_flag = true
			flashlight.visible = true
			return
		if flashlight_flag == true:
			flashlight_flag = false
			flashlight.visible = false
			return
	
	
var is_interacting: bool = false

func _unhandled_key_input(event: InputEvent) -> void:
	if is_interacting:
		return
	
	
func _physics_process(delta: float) -> void:
	if is_interacting:
		velocity = Vector3.ZERO
		move_and_slide()
		return
		
	var input_dir: Vector2 = Vector2.ZERO
	
	if is_on_floor() and Input.is_key_pressed(KEY_SPACE):
		velocity.y = 4.5
		 
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_S): input_dir.y += 1
	if Input.is_key_pressed(KEY_W): input_dir.y -= 1
	input_dir = input_dir.normalized()
	
	var direction: Vector3 = (head.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()
