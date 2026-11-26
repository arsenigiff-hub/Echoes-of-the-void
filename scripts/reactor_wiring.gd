extends Node3D
## In-world breaker repair. Each cable is a lit tube mesh in cabinet space;
## only the mouse ray/plane intersection and hit testing use screen input.

signal focus_changed
signal terminal_connected
signal repaired

enum Focus { IDLE, ENTERING, ACTIVE, LEAVING }

# Physical order of the engraved terminals in the exported cabinet.
const LEFT := ["circle", "cross", "star", "triangle", "square", "diamond", "plus", "moon", "bars", "down"]
const RIGHT := ["triangle", "diamond", "circle", "star", "bars", "plus", "down", "cross", "moon", "square"]
const COLORS := [
	Color("#ac2d22"), Color("#394aa8"), Color("#ccac29"), Color("#a83a7e"), Color("#4c853b"),
	Color("#c97528"), Color("#9b9689"), Color("#7d40a1"), Color("#98643d"), Color("#c1b194"),
]
const OPEN_ANGLE := -96.0 # Keep the opened door clear of the oxygen unit.
const FOCUS_FOV := 48.0
const INPUT_DEPTH := 0.224
const WIRE_RADIUS := 0.008
const SIDES := 8
const SEGMENTS := 22

var connected_count := 0
var _state := Focus.IDLE
var _latched := PackedByteArray()
var _depths := PackedInt32Array()
var _cables: Array[MeshInstance3D] = []
var _tips: Array[MeshInstance3D] = []
var _grabbed := -1
var _camera: Camera3D
var _door: Node3D
var _service_light: SpotLight3D
var _operator: Player
var _mouse_before := Input.MOUSE_MODE_CAPTURED
var _transition: Tween
var _returning := -1
var _return_tween: Tween
var _hint: Label
var _feedback := ""
var _feedback_tween: Tween


func _ready() -> void:
	_door = find_child("DoorPivot", true, false) as Node3D
	assert(_door != null, "Cabinet export needs its hinge pivot")
	_camera = Camera3D.new()
	_camera.name = "RepairCamera"
	_camera.fov = FOCUS_FOV
	_camera.near = 0.03
	add_child(_camera)
	get_viewport().size_changed.connect(_fit_active_camera)
	_service_light = SpotLight3D.new()
	_service_light.name = "InspectionLight"
	_service_light.light_energy = 0.0
	_service_light.light_color = Color(1.0, 0.93, 0.79)
	_service_light.spot_range = 1.1
	_service_light.spot_angle = 54.0
	_service_light.position = Vector3(-0.11, 0.72, 0.73)
	_service_light.rotation_degrees.x = -25.0
	add_child(_service_light)
	_make_hint()
	_latched.resize(LEFT.size())
	_depths.resize(LEFT.size())
	var copper := StandardMaterial3D.new()
	copper.albedo_color = Color("#ae693d")
	copper.metallic = 0.34
	copper.roughness = 0.64
	var ferrule := CylinderMesh.new()
	ferrule.top_radius = 0.0043
	ferrule.bottom_radius = 0.0055
	ferrule.height = 0.015
	ferrule.radial_segments = 8
	ferrule.rings = 0
	ferrule.material = copper
	for i in LEFT.size():
		# Give crossing pairs separate depths, while noncrossing pairs reuse a lane.
		for j in i:
			if RIGHT.find(LEFT[j]) > RIGHT.find(LEFT[i]):
				_depths[i] = maxi(_depths[i], _depths[j] + 1)
		var insulation := StandardMaterial3D.new()
		insulation.albedo_color = COLORS[i]
		insulation.roughness = 0.83
		var cable := MeshInstance3D.new()
		cable.name = "Wire_%s" % LEFT[i]
		cable.mesh = ImmediateMesh.new()
		cable.material_override = insulation
		add_child(cable)
		_cables.append(cable)
		var tip := MeshInstance3D.new()
		tip.name = "Tip"
		tip.mesh = ferrule
		cable.add_child(tip)
		_tips.append(tip)
		_draw_wire(i, _rest_tip(i))


func is_focused() -> bool:
	return _state != Focus.IDLE


func is_repaired() -> bool:
	return connected_count == LEFT.size()


func begin(operator: Player) -> void:
	if is_focused() or is_repaired() or not is_instance_valid(operator):
		return
	_operator = operator
	_operator.is_interacting = true
	_mouse_before = Input.mouse_mode
	_state = Focus.ENTERING
	_camera.global_transform = _operator.camera.global_transform
	_camera.fov = _operator.camera.fov
	_camera.make_current()
	_feedback = ""
	_refresh_hint()
	_hint.show()
	focus_changed.emit()
	_transition = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_transition.tween_property(_door, "rotation:y", deg_to_rad(OPEN_ANGLE), 0.43)
	_transition.tween_property(_camera, "global_transform", _view_transform(), 0.50)
	_transition.tween_property(_camera, "fov", FOCUS_FOV, 0.50)
	_transition.tween_property(_service_light, "light_energy", 0.95 if _operator.flashlight.visible else 1.35, 0.38)
	_transition.chain().tween_callback(_activate)


func _activate() -> void:
	_state = Focus.ACTIVE
	_fit_active_camera()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func finish(latched_all := false) -> void:
	if _state == Focus.IDLE or _state == Focus.LEAVING:
		return
	_cancel_drag()
	_stop_return()
	_state = Focus.LEAVING
	if _transition != null:
		_transition.kill()
	_transition = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if latched_all:
		_transition.tween_interval(0.35)
	_transition.tween_property(_door, "rotation:y", 0.0, 0.4)
	_transition.parallel().tween_property(_service_light, "light_energy", 0.0, 0.4)
	if is_instance_valid(_operator):
		_transition.parallel().tween_property(_camera, "global_transform", _operator.camera.global_transform, 0.4)
		_transition.parallel().tween_property(_camera, "fov", _operator.camera.fov, 0.4)
	_transition.tween_callback(_restore_player)


func _restore_player() -> void:
	if is_instance_valid(_operator):
		_operator.camera.make_current()
		_operator.is_interacting = false
		_operator.interacting_object = null
	_operator = null
	_state = Focus.IDLE
	Input.mouse_mode = _mouse_before
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	_hint.hide()
	focus_changed.emit()


func _exit_tree() -> void:
	if is_focused():
		Input.mouse_mode = _mouse_before
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if is_instance_valid(_operator):
			_operator.is_interacting = false
			_operator.interacting_object = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and _state == Focus.ACTIVE:
		_cancel_drag()


func _view_transform() -> Transform3D:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var depth := maxf(1.16, 0.85 / (2.0 * tan(deg_to_rad(FOCUS_FOV * 0.5)) * maxf(aspect, 0.1)))
	var eye := to_global(Vector3(0.016, 0.447, INPUT_DEPTH + depth))
	return Transform3D(Basis.IDENTITY, eye).looking_at(to_global(Vector3(0.016, 0.447, 0.17)))


func _fit_active_camera() -> void:
	if _state == Focus.ACTIVE:
		_camera.global_transform = _view_transform()


func _input(event: InputEvent) -> void:
	if not is_focused():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_E, KEY_ESCAPE] or event.keycode in [KEY_E, KEY_ESCAPE]:
			finish()
	elif _state == Focus.ACTIVE:
		if event is InputEventMouseMotion:
			_move_pointer(event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pick_wire(event.position)
			elif _grabbed >= 0:
				_drop_wire(event.position)
	get_viewport().set_input_as_handled()


func _on_plane(screen_point: Vector2) -> Vector3:
	var origin := to_local(_camera.project_ray_origin(screen_point))
	var direction := global_basis.inverse() * _camera.project_ray_normal(screen_point)
	return origin + direction * ((INPUT_DEPTH - origin.z) / direction.z)


func _pick_wire(screen_point: Vector2) -> void:
	if _grabbed >= 0:
		return
	var i := _wire_at(_on_plane(screen_point))
	if i < 0:
		return
	_stop_return()
	_grabbed = i
	_move_pointer(screen_point)


func _wire_at(p: Vector3) -> int:
	for i in LEFT.size():
		var lead := _rest_tip(i)
		if _latched[i] == 0 and absf(p.y - lead.y) <= 0.029 and p.x >= -0.256 and p.x <= lead.x + 0.033:
			return i
	return -1


func _move_pointer(screen_point: Vector2) -> void:
	var p := _on_plane(screen_point)
	if _grabbed < 0:
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if _wire_at(p) >= 0 else Input.CURSOR_ARROW)
		return
	Input.set_default_cursor_shape(Input.CURSOR_DRAG)
	var target := Vector3(clampf(p.x, -0.196, 0.267), clampf(p.y, 0.106, 0.787), INPUT_DEPTH)
	_draw_wire(_grabbed, target)


func _drop_wire(screen_point: Vector2) -> void:
	var i := _grabbed
	_grabbed = -1
	var point := _on_plane(screen_point)
	var row := -1
	if point.x >= 0.172 and point.x <= 0.299:
		for j in RIGHT.size():
			if absf(point.y - _row_y(j)) <= 0.033:
				row = j
				break
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if row < 0 or RIGHT[row] != LEFT[i]:
		_return_wire(i)
		if row >= 0:
			_show_feedback("Символы не совпадают")
		return
	_latched[i] = 1
	connected_count += 1
	_draw_wire(i, _socket(row))
	_feedback = ""
	_refresh_hint()
	terminal_connected.emit()
	if is_repaired():
		finish(true)
		repaired.emit()


func _cancel_drag() -> void:
	if _grabbed >= 0:
		_draw_wire(_grabbed, _rest_tip(_grabbed))
		_grabbed = -1
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _return_wire(i: int) -> void:
	_stop_return()
	_returning = i
	var from := _tips[i].position - _tips[i].basis.y * 0.004
	_return_tween = create_tween()
	_return_tween.tween_method(func(end: Vector3) -> void: _draw_wire(i, end), from, _rest_tip(i), 0.19)
	_return_tween.tween_callback(func() -> void: _returning = -1)


func _stop_return() -> void:
	if _returning >= 0:
		_return_tween.kill()
		_draw_wire(_returning, _rest_tip(_returning))
		_returning = -1


func _row_y(index: int) -> float:
	return 0.756 - 0.069 * index


func _rest_tip(i: int) -> Vector3:
	return Vector3(-0.145 + 0.007 * (i % 3), _row_y(i) - 0.006, 0.198)


func _socket(index: int) -> Vector3:
	return Vector3(0.202, _row_y(index), 0.17)


func _draw_wire(i: int, end: Vector3) -> void:
	var start := Vector3(-0.212, _row_y(i), 0.17)
	var reach := clampf((end.x - start.x) * 0.40, 0.024, 0.17)
	var first := start + Vector3(reach, -0.008, 0.0)
	var last := end - Vector3(reach, -0.006, 0.0)
	var latched := _latched[i] != 0
	var rings: Array[Vector3] = []
	for ring in SEGMENTS + 1:
		var t := float(ring) / SEGMENTS
		var center := start.bezier_interpolate(first, last, end, t)
		var arch := pow(maxf(0.0, sin(PI * t)), 0.75)
		if latched:
			center.z += (0.132 + 0.019 * _depths[i] - 0.17) * arch
		else:
			center.y -= minf(0.022, reach * 0.55) * arch
		rings.append(center)
	var mesh := _cables[i].mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for ring in rings.size():
		var tangent := (rings[mini(ring + 1, SEGMENTS)] - rings[maxi(0, ring - 1)]).normalized()
		var u := tangent.cross(Vector3.BACK).normalized()
		if u.is_zero_approx():
			u = tangent.cross(Vector3.UP).normalized()
		var v := tangent.cross(u)
		for side in SIDES:
			var angle := TAU * side / SIDES
			var normal := u * cos(angle) + v * sin(angle)
			vertices.append(rings[ring] + normal * WIRE_RADIUS)
			normals.append(normal)
	for ring in SEGMENTS:
		for side in SIDES:
			var a := ring * SIDES + side
			var b := ring * SIDES + (side + 1) % SIDES
			var normal := (normals[a] + normals[b] + normals[a + SIDES] + normals[b + SIDES]).normalized()
			for index in [a, a + SIDES, b, b, a + SIDES, b + SIDES]:
				mesh.surface_set_normal(normal)
				mesh.surface_add_vertex(vertices[index])
	mesh.surface_end()
	var direction := (rings[SEGMENTS] - rings[SEGMENTS - 1]).normalized()
	var tip := _tips[i]
	tip.position = end + direction * 0.004
	tip.quaternion = Quaternion(Vector3.UP, direction)


func _make_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 111
	add_child(layer)
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -54
	_hint.offset_bottom = -15
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 21)
	_hint.add_theme_color_override("font_color", Color(0.89, 0.87, 0.78))
	_hint.add_theme_color_override("font_outline_color", Color(0.035, 0.031, 0.024))
	_hint.add_theme_constant_override("outline_size", 6)
	layer.add_child(_hint)
	_hint.hide()


func _show_feedback(message: String) -> void:
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback = message
	_refresh_hint()
	_feedback_tween = create_tween()
	_feedback_tween.tween_interval(1.1)
	_feedback_tween.tween_callback(func() -> void:
		_feedback = ""
		_refresh_hint()
	)


func _refresh_hint() -> void:
	var instruction := "ЛКМ — перетащите провод к такому же символу     Esc — выйти"
	if is_repaired():
		instruction = "Цепь собрана"
	elif not _feedback.is_empty():
		instruction = _feedback
	_hint.text = "%s    ·    %d / %d" % [instruction, connected_count, LEFT.size()]
