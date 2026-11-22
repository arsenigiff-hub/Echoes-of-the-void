class_name SolarWingRepair
extends Node3D
## One large solar wing: 11x2 selectable cells, six broken cells with their own
## cracked plates and a replacement plate that flies into the selected cell.
## The owner (StoryProgression) creates the target and controls availability;
## this node owns the cell state, the cursor, the overlays and the animations.

const GRID := preload("res://scripts/solar_cell_grid.gd")
const FOCUS_SCRIPT := preload("res://scripts/solar_repair_focus.gd")
const SOLAR_DAMAGE_SPARKS := preload("res://scripts/solar_damage_sparks.gd")
const BRIGHT_CELL_MATERIAL := preload("res://assetss/ship_exterior/solar_cells_bright.tres")

const CURSOR_COLOR := Color(0.93, 0.98, 0.90, 0.92)
const CURSOR_WIDTH := 0.010
const CURSOR_LIFT := 0.012
const OVERLAY_LIFT := 0.006
const INSTALL_SECONDS := 0.38
const READY_SECONDS := 0.28

var wing_id := ""
var progression: Node
var target: StaticBody3D
var surface: MeshInstance3D
var focus: Node3D

var _repaired: Dictionary = {}
var _overlays: Dictionary = {}
var _selected := Vector2i(1, 0)
var _active := false
var _installing := false
var _cursor: MeshInstance3D
var _cursor_material: StandardMaterial3D
var _replacement: Node3D
var _replacement_key := ""
var _frame_material: StandardMaterial3D
var _tween: Tween
var _replacement_tween: Tween
var _install_overlay: MeshInstance3D
var _install_overlay_rest := Vector3.ZERO
var _install_overlay_rotation := Vector3.ZERO

static var _crack_textures: Array[ImageTexture] = []


func setup(id: String, owner_progression: Node, target_body: StaticBody3D, surface_mesh: MeshInstance3D) -> void:
	wing_id = id
	progression = owner_progression
	target = target_body
	surface = surface_mesh
	_frame_material = StandardMaterial3D.new()
	_frame_material.albedo_color = Color(0.62, 0.65, 0.69)
	_frame_material.metallic = 0.70
	_frame_material.roughness = 0.34
	focus = FOCUS_SCRIPT.new()
	focus.name = "SolarRepairFocus"
	target.add_child(focus)
	focus.top_level = true
	focus.global_transform = Transform3D(Basis.IDENTITY, target.global_position)
	focus.call("bind_surface", surface)
	_build_overlays()
	_build_cursor()
	_selected = Vector2i(GRID.COLUMNS, 0)
	_cursor.hide()


func can_repair_from(eye: Vector3) -> bool:
	return focus.call("can_repair_from", eye)


func is_complete() -> bool:
	for cell in GRID.broken_cells(wing_id):
		if not _repaired.has(GRID.cell_key(cell["column"], cell["row"])):
			return false
	return true


func repaired_keys() -> Array[String]:
	var keys: Array[String] = []
	for key in _repaired.keys():
		keys.append(String(key))
	return keys


func restore(keys: Array) -> void:
	for key in keys:
		var text := String(key)
		if not _overlays.has(text):
			continue
		var overlay := _overlays[text] as MeshInstance3D
		_overlays.erase(text)
		if is_instance_valid(overlay):
			overlay.queue_free()
		_repaired[text] = true
	if is_complete():
		_active = false


func force_complete() -> void:
	for key in _overlays.keys():
		var overlay := _overlays[key] as MeshInstance3D
		if is_instance_valid(overlay):
			overlay.queue_free()
		_repaired[key] = true
	_overlays.clear()
	_active = false


func begin(camera: Camera3D) -> bool:
	if is_complete():
		return false
	_active = true
	_installing = false
	focus.call("begin", camera)
	_selected = Vector2i(GRID.COLUMNS, 0)
	_cursor.show()
	_refresh_selection()
	return true


func move_selection(screen_delta: Vector2i) -> void:
	if not _active or _installing:
		return
	var column_step := int(focus.call("column_screen_step"))
	var row_step := int(focus.call("row_screen_step"))
	_selected.x = clampi(_selected.x + screen_delta.x * column_step, 1, GRID.COLUMNS)
	_selected.y = clampi(_selected.y + screen_delta.y * row_step, 0, GRID.ROWS - 1)
	_refresh_selection()


func confirm() -> void:
	if not _active or _installing:
		return
	var key := GRID.cell_key(_selected.x, _selected.y)
	if _overlays.has(key) and not _repaired.has(key):
		_install_selected(key)
		return
	_set_status("СЕКТОР ИСПРАВЕН", 1.3)


func cancel() -> void:
	_cancel_tweens()
	if _installing and is_instance_valid(_install_overlay):
		_install_overlay.position = _install_overlay_rest
		_install_overlay.rotation_degrees = _install_overlay_rotation
		var material := _install_overlay.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_installing = false
	_install_overlay = null
	_clear_replacement()
	_active = false
	if _cursor != null:
		_cursor.hide()
	focus.call("reset")
	_set_status("РЕМОНТ ПРЕРВАН", 2.0)


func reset_incomplete() -> void:
	if _active:
		cancel()


func _refresh_selection() -> void:
	if _cursor == null or _installing:
		return
	_cursor.mesh = _cursor_mesh(GRID.rect(_selected.x, _selected.y))
	_cursor.show()
	var key := GRID.cell_key(_selected.x, _selected.y)
	if _overlays.has(key) and not _repaired.has(key):
		_show_replacement()
		_set_status("E — ЗАМЕНИТЬ  ·  ESC — ОТОЙТИ", 0.0)
	else:
		_clear_replacement()
		_set_status("ESC — ОТОЙТИ", 0.0)


func _install_selected(key: String) -> void:
	var overlay := _overlays.get(key) as MeshInstance3D
	if overlay == null:
		return
	_installing = true
	_install_overlay = overlay
	_install_overlay_rest = overlay.position
	_install_overlay_rotation = overlay.rotation_degrees
	var rect := GRID.rect(_selected.x, _selected.y)
	var base := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	_cancel_tweens()
	_installing = true
	_install_overlay = overlay
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_replacement, "position", base, INSTALL_SECONDS)
	_tween.tween_property(_replacement, "rotation_degrees", Vector3.ZERO, INSTALL_SECONDS)
	_tween.tween_property(_replacement, "scale", Vector3.ONE, INSTALL_SECONDS)
	_tween.tween_property(overlay, "position", _install_overlay_rest + Vector3(0.0, 0.38, 0.0), INSTALL_SECONDS)
	_tween.tween_property(overlay, "rotation_degrees",
		_install_overlay_rotation + Vector3(0.0, 35.0, 0.0), INSTALL_SECONDS)
	var material := overlay.material_override as StandardMaterial3D
	if material != null:
		_tween.tween_property(material, "albedo_color", Color(1.0, 1.0, 1.0, 0.0), INSTALL_SECONDS)
	_tween.finished.connect(_on_install_finished.bind(key, overlay, rect))
	_set_status("УСТАНОВКА СЕКТОРА…", 0.0)


func _on_install_finished(key: String, overlay: MeshInstance3D, rect: Rect2) -> void:
	if not _installing:
		return
	_installing = false
	_install_overlay = null
	_repaired[key] = true
	_overlays.erase(key)
	if is_instance_valid(overlay):
		overlay.queue_free()
	_clear_replacement()
	_spawn_sparks(rect)
	_set_status("СЕКТОР ЗАМЕНЁН", 1.1)
	progression.call("save_solar_progress")
	if is_complete():
		_finish_wing()
		return
	await get_tree().create_timer(1.1).timeout
	if not _active or _installing:
		return
	_refresh_selection()


func _finish_wing() -> void:
	_active = false
	_installing = false
	_cursor.hide()
	_clear_replacement()
	focus.call("reset")
	progression.call("on_solar_wing_completed", wing_id)


func _build_overlays() -> void:
	_ensure_crack_textures()
	for cell in GRID.broken_cells(wing_id):
		var column := int(cell["column"])
		var row := int(cell["row"])
		var key := GRID.cell_key(column, row)
		var rect := GRID.rect(column, row)
		var overlay := MeshInstance3D.new()
		overlay.name = "BrokenSolarCell_%d_%d" % [row, column]
		var plane := PlaneMesh.new()
		plane.size = rect.size
		overlay.mesh = plane
		overlay.material_override = _cracked_material(column + row * 31)
		overlay.position = Vector3(rect.get_center().x, OVERLAY_LIFT, rect.get_center().y)
		overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surface.add_child(overlay)
		_overlays[key] = overlay


func _build_cursor() -> void:
	_cursor = MeshInstance3D.new()
	_cursor.name = "SolarCellCursor"
	_cursor_material = StandardMaterial3D.new()
	_cursor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cursor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cursor_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cursor_material.albedo_color = CURSOR_COLOR
	_cursor_material.no_depth_test = true
	_cursor.material_override = _cursor_material
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	surface.add_child(_cursor)


func _cursor_mesh(rect: Rect2) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector2(rect.position.x, rect.position.y)
	var b := Vector2(rect.end.x, rect.position.y)
	var c := Vector2(rect.end.x, rect.end.y)
	var d := Vector2(rect.position.x, rect.end.y)
	_add_cursor_line(tool, a, b)
	_add_cursor_line(tool, b, c)
	_add_cursor_line(tool, c, d)
	_add_cursor_line(tool, d, a)
	return tool.commit()


func _add_cursor_line(tool: SurfaceTool, a: Vector2, b: Vector2) -> void:
	var direction := (b - a).normalized()
	var offset := Vector2(-direction.y, direction.x) * CURSOR_WIDTH * 0.5
	var p0 := a + offset
	var p1 := a - offset
	var p2 := b + offset
	var p3 := b - offset
	for point in [p0, p1, p2, p1, p3, p2]:
		tool.add_vertex(Vector3(point.x, CURSOR_LIFT, point.y))


func _show_replacement() -> void:
	var key := GRID.cell_key(_selected.x, _selected.y)
	if _replacement != null and _replacement_key == key:
		return
	_clear_replacement()
	var rect := GRID.rect(_selected.x, _selected.y)
	_replacement = Node3D.new()
	_replacement.name = "SolarReplacementCell"
	surface.add_child(_replacement)
	var frame := MeshInstance3D.new()
	var frame_mesh := PlaneMesh.new()
	frame_mesh.size = rect.size + Vector2(0.016, 0.016)
	frame.mesh = frame_mesh
	frame.material_override = _frame_material
	_replacement.add_child(frame)
	var cell := MeshInstance3D.new()
	var cell_mesh := PlaneMesh.new()
	cell_mesh.size = rect.size
	cell.mesh = cell_mesh
	cell.material_override = BRIGHT_CELL_MATERIAL
	cell.position = Vector3(0.0, 0.003, 0.0)
	_replacement.add_child(cell)
	_replacement.position = Vector3(rect.get_center().x, 0.0, rect.get_center().y) + _ready_offset(rect)
	_replacement.rotation_degrees = Vector3(0.0, -38.0, -12.0)
	_replacement.scale = Vector3.ONE * 0.05
	_replacement_key = key
	_replacement_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_replacement_tween.tween_property(_replacement, "scale", Vector3.ONE, READY_SECONDS)
	_replacement_tween.tween_property(_replacement, "rotation_degrees", Vector3(0.0, -38.0, -12.0), READY_SECONDS)


func _ready_offset(rect: Rect2) -> Vector3:
	# Put the replacement plate towards the middle of the wing so it stays in
	# frame even when the selected cell is at the outer edge.
	var direction := -1.0 if rect.get_center().x > 0.0 else 1.0
	return Vector3(direction * rect.size.x * 0.95, 0.18, 0.0)


func _clear_replacement() -> void:
	if _replacement_tween != null and _replacement_tween.is_valid():
		_replacement_tween.kill()
	_replacement_tween = null
	if is_instance_valid(_replacement):
		_replacement.queue_free()
	_replacement = null
	_replacement_key = ""


func _cancel_tweens() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _replacement_tween != null and _replacement_tween.is_valid():
		_replacement_tween.kill()
	_replacement_tween = null


func _spawn_sparks(rect: Rect2) -> void:
	var sparks := SOLAR_DAMAGE_SPARKS.new()
	var world := surface.to_global(Vector3(rect.get_center().x, 0.02, rect.get_center().y))
	sparks.position = target.to_local(world)
	target.add_child(sparks)
	sparks.call("set_active", true)
	var cleanup := Timer.new()
	cleanup.one_shot = true
	cleanup.wait_time = 1.6
	cleanup.timeout.connect(sparks.queue_free)
	sparks.add_child(cleanup)
	cleanup.start()


func _set_status(text: String, seconds: float) -> void:
	if progression != null and progression.has_method("set_status"):
		progression.call("set_status", text, seconds)


func _cracked_material(seed_value: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = _crack_textures[seed_value % _crack_textures.size()]
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.62
	material.metallic = 0.18
	material.metallic_specular = 0.45
	return material


static func _ensure_crack_textures() -> void:
	if not _crack_textures.is_empty():
		return
	_crack_textures.append(_cracked_texture(101, 64, 192))
	_crack_textures.append(_cracked_texture(202, 64, 192))


static func _cracked_texture(seed_value: int, width: int, height: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var img := Image.create(width, height, false, Image.FORMAT_RGB8)
	for y in height:
		var sheen := 0.026 + 0.034 * (1.0 - absf(float(y) / float(height) - 0.42) * 2.0)
		for x in width:
			var grain := rng.randf_range(-0.008, 0.008)
			img.set_pixel(x, y, Color(
				maxf(0.0, sheen * 0.75 + grain),
				maxf(0.0, sheen * 0.95 + grain),
				maxf(0.0, sheen * 1.30 + grain)))
	for impact_index in 2:
		var impact := Vector2(
			rng.randf_range(width * 0.2, width * 0.8),
			rng.randf_range(height * (0.16 if impact_index == 0 else 0.55),
				height * (0.45 if impact_index == 0 else 0.88)))
		var rays := 6 if impact_index == 0 else 5
		for ray in rays:
			var angle := TAU * float(ray) / float(rays) + rng.randf_range(-0.35, 0.35)
			var point := impact
			var steps := rng.randi_range(14, 24)
			for step in steps:
				angle += rng.randf_range(-0.55, 0.55)
				var length := rng.randf_range(1.8, 4.0) * (1.25 - float(step) / float(steps))
				var next := point + Vector2(cos(angle), sin(angle)) * maxf(length, 1.0)
				_draw_crack_line(img, point, next, Color(0.52, 0.60, 0.68), 2)
				_draw_crack_line(img, point, next, Color(0.78, 0.84, 0.90), 2)
				point = next
			if ray % 2 == 0:
				var branch_start := impact.lerp(point, rng.randf_range(0.35, 0.6))
				var branch_angle := angle + rng.randf_range(0.7, 1.5) * (1.0 if ray % 4 == 0 else -1.0)
				var branch_point := branch_start
				for _step in rng.randi_range(6, 10):
					branch_angle += rng.randf_range(-0.5, 0.5)
					var branch_next := branch_point + Vector2(cos(branch_angle), sin(branch_angle)) * rng.randf_range(1.2, 2.8)
					_draw_crack_line(img, branch_point, branch_next, Color(0.58, 0.65, 0.72), 2)
					branch_point = branch_next
		for x in range(int(impact.x) - 3, int(impact.x) + 4):
			for y in range(int(impact.y) - 3, int(impact.y) + 4):
				if x < 0 or y < 0 or x >= width or y >= height:
					continue
				if Vector2(x, y).distance_to(impact) <= 2.6:
					img.set_pixel(x, y, Color(0.42, 0.50, 0.58))
	for _chip in rng.randi_range(8, 14):
		var center := Vector2(rng.randf_range(0.0, width), rng.randf_range(0.0, height))
		var radius := rng.randf_range(0.8, 2.6)
		for x in range(int(center.x - radius), int(center.x + radius) + 1):
			for y in range(int(center.y - radius), int(center.y + radius) + 1):
				if x < 0 or y < 0 or x >= width or y >= height:
					continue
				if Vector2(x, y).distance_to(center) <= radius:
					img.set_pixel(x, y, Color(0.006, 0.008, 0.010))
	return ImageTexture.create_from_image(img)


static func _draw_crack_line(img: Image, from: Vector2, to: Vector2, color: Color, thickness: int = 1) -> void:
	var steps := int(maxf(absf(to.x - from.x), absf(to.y - from.y))) + 1
	for i in steps + 1:
		var t := float(i) / float(maxi(steps, 1))
		var point := from.lerp(to, t)
		var x := int(point.x)
		var y := int(point.y)
		for ox in thickness:
			for oy in thickness:
				var px := x + ox
				var py := y + oy
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
					img.set_pixel(px, py, color)
