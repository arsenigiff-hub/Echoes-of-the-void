extends Interactable

@onready var camera_target: Camera3D = $"../CameraTarget"
@onready var Radio_TuningKnob: Node3D = $"../Radio_TuningKnob_001"
	
var knob_angle: float = 0.0
var original_camera_transform: Transform3D
var original_speed: float
var is_at_radio := false
var is_moving := false


func focus_input(event: InputEvent) -> void:
	Radio_TuningKnob.rotate_object_local(Vector3.UP,deg_to_rad(60))
		


func interact(player: CharacterBody3D) -> void:
	if is_moving:
		return

	var player_camera: Camera3D = player.get_node("Head/Camera3D")

	var target_transform: Transform3D

	if not is_at_radio:
		# Сохраняем положение камеры и скорость до перемещения
		original_camera_transform = player_camera.global_transform
		original_speed = player.speed

		player.speed = 0
		player.is_interacting = true

		target_transform = camera_target.global_transform
		is_at_radio = true

		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
		if Input.is_key_pressed(KEY_D):
			Radio_TuningKnob
			
		
	else:
		# Возвращаемся ровно туда, где камера была раньше
		target_transform = original_camera_transform
		is_at_radio = false

	is_moving = true

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		player_camera,
		"global_transform",
		target_transform,
		0.5
	)

	await tween.finished

	is_moving = false

	if not is_at_radio:
		player.speed = original_speed
		player.is_interacting = false

		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
