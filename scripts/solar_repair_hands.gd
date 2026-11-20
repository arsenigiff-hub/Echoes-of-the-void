extends Node3D

const GLOVES := "res://assetss/first_person_arms/trellis/eva_gloves_pair.glb"
const SUIT_SHADER := preload("res://shaders/repair_hands_suit.gdshader")

var _left: Node3D
var _right: Node3D
var _left_rest := Vector3.ZERO
var _right_rest := Vector3.ZERO
var _left_rotation := Vector3.ZERO
var _right_rotation := Vector3.ZERO
var _gesture: Tween


func _ready() -> void:
	hide()
	var packed := load(GLOVES) as PackedScene
	if packed == null:
		return
	var pose := packed.instantiate() as Node3D
	# Convert the approved Blender preview's camera space to the viewmodel space.
	pose.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.52, 0.52)) 		.looking_at(Vector3(0.0, 0.06, 0.02), Vector3.UP).affine_inverse()
	add_child(pose)
	_left = pose.find_child("EVA_Left", true, false) as Node3D
	_right = pose.find_child("EVA_Right", true, false) as Node3D
	if _left == null or _right == null:
		return
	_left_rest = _left.position
	_right_rest = _right.position
	_left_rotation = _left.rotation_degrees
	_right_rotation = _right.rotation_degrees
	for node in pose.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var source := mesh.get_active_material(0) as StandardMaterial3D
		if source != null and source.albedo_texture != null:
			var suit := ShaderMaterial.new()
			suit.shader = SUIT_SHADER
			suit.set_shader_parameter("source_texture", source.albedo_texture)
			mesh.material_override = suit
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func begin() -> void:
	if _left == null or _right == null:
		return
	show()
	_left.position = _left_rest + Vector3(-0.03, -0.12, 0.10)
	_right.position = _right_rest + Vector3(0.03, -0.12, 0.10)
	_set_pose(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 0.32)


func gesture(action: String, contact: int = 1) -> void:
	if not visible:
		return
	match action:
		"open":
			_set_pose(Vector3(0.025, 0.025, -0.035), Vector3(0.025, 0.065, -0.035),
				Vector3(-5, 0, 0), Vector3(-16, 0, 5), 0.25)
		"align":
			var offset := float(contact - 1) * 0.038
			_set_pose(Vector3(0.025, 0.025, -0.035), Vector3(offset - 0.044, 0.01, -0.068),
				Vector3(-5, 0, 0), Vector3(6, 0, 0), 0.16)
		"clamp":
			_set_pose(Vector3(0.036, 0.016, -0.038), Vector3(-0.041, -0.005, -0.086),
				Vector3(-5, 0, 0), Vector3(14, 0, 0), 0.22)
		"close":
			_set_pose(Vector3(-0.02, -0.035, 0.03), Vector3(-0.017, -0.032, -0.055),
				Vector3(4, 0, 0), Vector3(17, 0, -4), 0.26)


func stop() -> void:
	if _gesture != null and _gesture.is_valid():
		_gesture.kill()
	hide()


func _set_pose(left_offset: Vector3, right_offset: Vector3, left_angle: Vector3,
		right_angle: Vector3, duration: float) -> void:
	if _gesture != null and _gesture.is_valid():
		_gesture.kill()
	_gesture = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_gesture.tween_property(_left, "position", _left_rest + left_offset, duration)
	_gesture.tween_property(_right, "position", _right_rest + right_offset, duration)
	_gesture.tween_property(_left, "rotation_degrees", _left_rotation + left_angle, duration)
	_gesture.tween_property(_right, "rotation_degrees", _right_rotation + right_angle, duration)
