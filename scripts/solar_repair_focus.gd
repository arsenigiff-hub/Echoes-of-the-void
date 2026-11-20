extends Node3D

const GRID := Vector2i(3, 2)
const DAMAGED := Vector2i(1, 0)
const EDGE_INSET := 0.075
const RAIL_INSET := 0.080
const SERVICE_FACE_MIN_DISTANCE := 0.20

var _panel_center := Vector3.ZERO
var _panel_right := Vector3(0, 0, 1)
var _panel_up := Vector3(-0.61968, 0.78486, 0)
var _panel_normal := Vector3(0.78486, 0.61968, 0)
var _panel_half_width := 3.68
var _panel_half_height := 2.8
var _rail_half_height := 0.16
var _surface_lift := 0.034
var _surface_bound := false

var selected := Vector2i(0, 1)
var _cursor: MeshInstance3D
var _grid: MeshInstance3D
var _camera: Camera3D
var _rest := Transform3D.IDENTITY
var _rest_fov := 75.0
var _tween: Tween


func _ready() -> void:
	_grid = _make_wire("SolarSectorGrid", Color(0.41, 0.62, 0.68), 0.33)
	_cursor = _make_wire("SelectedSolarSector", Color(0.77, 0.91, 0.86), 1.0)
	hide()


func bind_surface(surface: MeshInstance3D) -> void:
	if surface == null or surface.mesh == null:
		push_warning("Solar repair: missing the solar cell surface for sector selection")
		return
	var bounds := surface.mesh.get_aabb()
	var basis := surface.global_basis
	_panel_center = to_local(surface.to_global(bounds.get_center()))
	_panel_right = (global_basis.inverse() * basis.x).normalized()
	_panel_up = (global_basis.inverse() * basis.z).normalized()
	_panel_normal = (global_basis.inverse() * basis.y).normalized()
	_panel_half_width = bounds.size.x * basis.x.length() * 0.5
	_panel_half_height = bounds.size.z * basis.z.length() * 0.5
	_surface_lift = bounds.size.y * basis.y.length() * 0.5 + 0.065
	var center_z := bounds.get_center().z
	var nearest_edge := bounds.size.z * 0.5
	for surface_index in surface.mesh.get_surface_count():
		var points := surface.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for point in points:
			nearest_edge = minf(nearest_edge, absf(point.z - center_z))
	_rail_half_height = nearest_edge * basis.z.length()
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
	selected = Vector2i(GRID.x - 1, GRID.y - 1)
	_draw_grid()
	_update_cursor()
	show()
	# From the service face, moving away from the panel keeps the camera outside it.
	var distance := maxf(5.6, (camera.global_position - center).dot(_panel_normal) + 0.8)
	_move_camera(center + _panel_normal * distance, center,
		maxf(_rest_fov, 77.0), 0.43)


func move_selection(screen_delta: Vector2i) -> void:
	# Positive panel U points toward the left edge of the service-side view.
	selected.x = clampi(selected.x - screen_delta.x, 0, GRID.x - 1)
	selected.y = clampi(selected.y + screen_delta.y, 0, GRID.y - 1)
	_update_cursor()


func is_damaged_selected() -> bool:
	return selected == DAMAGED


func displayed_sector() -> int:
	var column := GRID.x - 1 - selected.x
	return 1 + selected.y * GRID.x + column


func focus_fault(point: Vector3) -> void:
	hide()
	_move_camera(point + _panel_normal * 1.22 + _panel_up * 0.12, point, 56.0, 0.35)


func reset() -> void:
	hide()
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
	var goal := Transform3D(Basis.IDENTITY, eye).looking_at(target, _panel_up)
	var start_fov := _camera.fov
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(func(fraction: float) -> void:
		_camera.global_transform = start.interpolate_with(goal, fraction)
		_camera.fov = lerpf(start_fov, fov, fraction),
		0.0, 1.0, duration)


func _make_wire(label: String, tint: Color, alpha: float) -> MeshInstance3D:
	var wire := MeshInstance3D.new()
	wire.name = label
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(tint, alpha)
	wire.material_override = material
	add_child(wire)
	return wire


func _sector_rect(column: int, row: int) -> Rect2:
	var width := _panel_half_width - EDGE_INSET
	var column_width := width * 2.0 / GRID.x
	var low := _rail_half_height + RAIL_INSET if row == 0 else -_panel_half_height + EDGE_INSET
	var high := _panel_half_height - EDGE_INSET if row == 0 else -_rail_half_height - RAIL_INSET
	return Rect2(-width + column_width * column, low, column_width, high - low)


func _draw_grid() -> void:
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(GRID.y):
		var first := _sector_rect(0, row)
		var last := _sector_rect(GRID.x - 1, row)
		_add_outline(lines, Rect2(first.position, last.end - first.position), 0.014, 0.0)
		for column in range(1, GRID.x):
			var x := _sector_rect(column, row).position.x
			_add_line(lines, Vector2(x, first.position.y), Vector2(x, first.end.y), 0.014, 0.0)
	_grid.mesh = lines.commit()


func _update_cursor() -> void:
	var lines := SurfaceTool.new()
	lines.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_outline(lines, _sector_rect(selected.x, selected.y).grow(-0.042), 0.031, 0.006)
	_cursor.mesh = lines.commit()


func _add_outline(tool: SurfaceTool, area: Rect2, width: float, lift: float) -> void:
	var a := area.position
	var b := Vector2(area.end.x, a.y)
	var c := area.end
	var d := Vector2(a.x, c.y)
	_add_line(tool, a, b, width, lift)
	_add_line(tool, b, c, width, lift)
	_add_line(tool, c, d, width, lift)
	_add_line(tool, d, a, width, lift)


func _add_line(tool: SurfaceTool, a: Vector2, b: Vector2, width: float, lift: float) -> void:
	var offset := (b - a).orthogonal().normalized() * width * 0.5
	for point: Vector2 in [a + offset, a - offset, b + offset, b + offset, a - offset, b - offset]:
		tool.add_vertex(_panel_center + _panel_right * point.x + _panel_up * point.y
			+ _panel_normal * (_surface_lift + lift))
