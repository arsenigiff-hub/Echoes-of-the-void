extends Node3D
## Camera framing for a solar wing repair. The cell selection and its cursor are
## owned by SolarWingRepair; this node only reads the surface and moves the camera.

const SERVICE_FACE_MIN_DISTANCE := 0.20
# Face-on repair view: the camera sits on the panel normal and keeps the wing
# centered. The closer distance fills the frame like the author's reference shot.
const VIEW_DISTANCE := 4.2
const REPAIR_VIEW_FOV := 77.0

var _panel_center := Vector3.ZERO
var _panel_right := Vector3(0, 0, 1)
var _panel_up := Vector3(-0.61968, 0.78486, 0)
var _panel_normal := Vector3(0.78486, 0.61968, 0)
var _panel_half_width := 3.68
var _panel_half_height := 2.8
var _surface_bound := false

var _camera: Camera3D
var _rest := Transform3D.IDENTITY
var _rest_fov := 75.0
var _tween: Tween
var _goal_eye := Vector3.ZERO
var _goal_target := Vector3.ZERO
var _goal_up := Vector3(0.0, 0.0, 1.0)


func bind_surface(surface: MeshInstance3D) -> void:
	if surface == null or surface.mesh == null:
		push_warning("Solar repair: missing the solar cell surface")
		return
	var bounds := surface.mesh.get_aabb()
	var basis := surface.global_basis
	_panel_center = to_local(surface.to_global(bounds.get_center()))
	_panel_right = (global_basis.inverse() * basis.x).normalized()
	_panel_up = (global_basis.inverse() * basis.z).normalized()
	_panel_normal = (global_basis.inverse() * basis.y).normalized()
	_panel_half_width = bounds.size.x * basis.x.length() * 0.5
	_panel_half_height = bounds.size.z * basis.z.length() * 0.5
	_surface_bound = true


func is_surface_bound() -> bool:
	return _surface_bound


func can_repair_from(eye: Vector3) -> bool:
	return _surface_bound and (eye - to_global(_panel_center)).dot(_panel_normal) > SERVICE_FACE_MIN_DISTANCE


func begin(camera: Camera3D) -> void:
	_camera = camera
	_rest = camera.transform
	_rest_fov = camera.fov
	var center := to_global(_panel_center)
	_goal_eye = center + _panel_normal * VIEW_DISTANCE
	_goal_target = center
	_goal_up = _panel_up
	_move_camera(_goal_eye, _goal_target, maxf(_rest_fov, REPAIR_VIEW_FOV), 0.43)


## +1 when increasing the column index moves the highlight right on screen.
func column_screen_step() -> int:
	var goal := Transform3D(Basis.IDENTITY, _goal_eye).looking_at(_goal_target, _goal_up)
	return 1 if _panel_right.dot(goal.basis.x) > 0.0 else -1


## +1 when increasing the row index moves the highlight down on screen.
func row_screen_step() -> int:
	# The camera up vector is the panel's long axis, so row 0 is always on top.
	return 1


func reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if is_instance_valid(_camera):
		_camera.transform = _rest
		_camera.fov = _rest_fov
	_camera = null


func _move_camera(eye: Vector3, target: Vector3, fov: float, duration: float) -> void:
	if not is_instance_valid(_camera):
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var start := _camera.global_transform
	var goal := Transform3D(Basis.IDENTITY, eye).looking_at(target, _goal_up)
	var start_fov := _camera.fov
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(func(fraction: float) -> void:
		_camera.global_transform = start.interpolate_with(goal, fraction)
		_camera.fov = lerpf(start_fov, fov, fraction),
		0.0, 1.0, duration)
