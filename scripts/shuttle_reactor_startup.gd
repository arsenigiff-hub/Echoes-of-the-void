extends Panel
## The player trims a drifting needle to follow a moving operating band.

signal stabilized
signal dial_changed(needle: float, band: float)

const FONT := preload("res://assetss/ui/fonts/CascadiaMono.ttf")
const BACKDROP_SHADER := preload("res://shaders/reactor_hud_dissolve.gdshader")
const PANEL_SIZE := Vector2(656.0, 159.0)
const PANEL_SCALE := 1.5
const INSET := 50.0
const CONTENT_WIDTH := PANEL_SIZE.x - INSET * 2.0
const ZONE_HALF_WIDTH := 0.08
const MIN_ZONE_CENTER := 0.16
const MAX_ZONE_CENTER := 0.84
const MIN_ZONE_TRAVEL := 0.23
const REST_ZONE_CENTER := 0.54
const HOLD_SECONDS := 4.0
const START_LEVEL := 0.17
const INK := Color(0.84, 0.84, 0.79)
const SCALE_INK := Color(0.59, 0.58, 0.55)
const MOSS := Color(0.43, 0.49, 0.28)
const BAR_RECESS := Color(0.041, 0.037, 0.032)

var level := START_LEVEL
var zone_center := REST_ZONE_CENTER
var held_seconds := 0.0
var _elapsed := 0.0
var _zone_from := REST_ZONE_CENTER
var _zone_to := REST_ZONE_CENTER
var _zone_elapsed := 0.0
var _zone_duration := 0.0
var _zone_rng := RandomNumberGenerator.new()
var _meter: Control
var _timer: Label
var _pixel_font: FontFile


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_bottom = -50.0
	offset_top = offset_bottom - PANEL_SIZE.y
	pivot_offset = Vector2(PANEL_SIZE.x * 0.5, PANEL_SIZE.y)
	scale = Vector2.ONE * PANEL_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = BACKDROP_SHADER
	material.set_shader_parameter("panel_size", PANEL_SIZE)
	backdrop.material = material
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_pixel_font = FONT.duplicate() as FontFile
	_pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	_pixel_font.oversampling = 0.5
	_meter = Control.new()
	_meter.position = Vector2(INSET, 26.0)
	_meter.size = Vector2(CONTENT_WIDTH, 76.0)
	_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_meter)
	_meter.draw.connect(_draw_meter)
	_timer = _caption("", HORIZONTAL_ALIGNMENT_LEFT)
	_caption("A / D — регулировка", HORIZONTAL_ALIGNMENT_RIGHT)
	_zone_rng.randomize()
	cancel()


func begin() -> void:
	level = START_LEVEL
	held_seconds = 0.0
	_elapsed = 0.0
	zone_center = _zone_rng.randf_range(0.44, 0.62)
	_pick_zone_target()
	_update_meter()
	show()
	set_process(true)


func cancel() -> void:
	hide()
	set_process(false)


func _process(delta: float) -> void:
	var raise := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	var lower := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	advance(delta, float(raise) - float(lower))


func advance(delta: float, adjustment: float) -> void:
	if not visible:
		return
	_elapsed += delta
	_move_zone(delta)
	var drift := -0.11 + sin(_elapsed * 2.5) * 0.045
	level = clampf(level + (clampf(adjustment, -1.0, 1.0) * 0.86 + drift) * delta, 0.0, 1.0)
	if absf(level - zone_center) <= ZONE_HALF_WIDTH:
		held_seconds += delta
	else:
		held_seconds = 0.0
	_update_meter()
	if held_seconds >= HOLD_SECONDS:
		cancel()
		stabilized.emit()


func _pick_zone_target() -> void:
	var left := zone_center - MIN_ZONE_TRAVEL
	var right := zone_center + MIN_ZONE_TRAVEL
	_zone_from = zone_center
	if left >= MIN_ZONE_CENTER and (right > MAX_ZONE_CENTER or _zone_rng.randf() < 0.5):
		_zone_to = _zone_rng.randf_range(MIN_ZONE_CENTER, left)
	else:
		_zone_to = _zone_rng.randf_range(right, MAX_ZONE_CENTER)
	_zone_elapsed = 0.0
	_zone_duration = absf(_zone_to - _zone_from) / _zone_rng.randf_range(0.30, 0.37)


func _move_zone(delta: float) -> void:
	if _zone_elapsed >= _zone_duration:
		_pick_zone_target()
	_zone_elapsed += delta
	var t := clampf(_zone_elapsed / _zone_duration, 0.0, 1.0)
	# Smooth reversals are readable at speed; the band never jumps between targets.
	zone_center = lerpf(_zone_from, _zone_to, t * t * (3.0 - 2.0 * t))


func _update_meter() -> void:
	_timer.text = "%.1f / %.1f с" % [held_seconds, HOLD_SECONDS]
	_meter.queue_redraw()
	dial_changed.emit(level, zone_center)


func _draw_meter() -> void:
	var width := _meter.size.x
	var track_x := 7.0
	var track_width := width - track_x * 2.0
	_meter.draw_rect(Rect2(track_x, 29.0, track_width, 3.0), SCALE_INK)
	for i in range(10):
		var x := roundf(track_x + track_width * i / 9.0)
		_meter.draw_rect(Rect2(x - 1.5, 22.0, 3.0, 17.0), SCALE_INK)
	var zone_left := roundf(track_x + track_width * (zone_center - ZONE_HALF_WIDTH))
	var zone_right := roundf(track_x + track_width * (zone_center + ZONE_HALF_WIDTH))
	_meter.draw_rect(Rect2(zone_left, 22.0, zone_right - zone_left, 17.0), MOSS)
	_meter.draw_rect(Rect2(zone_left - 1.0, 22.0, 2.0, 17.0), SCALE_INK)
	_meter.draw_rect(Rect2(zone_right - 1.0, 22.0, 2.0, 17.0), SCALE_INK)

	var needle := roundf(track_x + track_width * level)
	for step in range(4):
		var tip_width := 18.0 - step * 4.0
		_meter.draw_rect(Rect2(needle - tip_width * 0.5, step * 3.0, tip_width, 3.0), INK)
	_meter.draw_rect(Rect2(needle - 1.5, 17.0, 3.0, 13.0), INK)

	var bar := Rect2(0.0, 53.0, width, 19.0)
	_meter.draw_rect(bar, SCALE_INK)
	_meter.draw_rect(bar.grow(-2.5), BAR_RECESS)
	if held_seconds > 0.0:
		var fill := bar.grow(-5.0)
		fill.size.x *= minf(held_seconds / HOLD_SECONDS, 1.0)
		_meter.draw_rect(fill, MOSS)


func _caption(value: String, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.position = Vector2(INSET, 105.0)
	label.size = Vector2(CONTENT_WIDTH, 30.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.horizontal_alignment = alignment
	label.text = value
	label.add_theme_font_override("font", _pixel_font)
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_color", INK)
	add_child(label)
	return label
