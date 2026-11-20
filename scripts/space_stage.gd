extends Node3D

const CANARY_BLACK_HOLE_SCENE: PackedScene = preload(
	"res://assetss/celestial/canary_games_dizzying_space_travel.glb")
const ACCRETION_DISK_SHADER: Shader = preload("res://shaders/accretion_disk.gdshader")
const CANARY_BLACK_HOLE_MODEL_SCALE := 0.025
const CANARY_BLACK_HOLE_SPEED := 0.1
const GAS_ORBIT_RADIUS := 332.0
const RING_INNER_RADIUS := 49.0
const RING_OUTER_RADIUS := 68.0
const BLACK_HOLE_FAR_DISTANCE := 1200.0
const BLACK_HOLE_NEAR_DISTANCE := 550.0
const BLACK_HOLE_SCALE := 1.8
const PLANET_RING_VIEW_INCLINATION := 0.72
const PLANET_VIEW_SCALE := 0.46
const PLANET_RECEDING_SCALE := 0.16
const SUN_INITIAL_SCALE := 0.08
const SUN_RECEDING_SCALE := 0.02
const SUN_INITIAL_DISTANCE := 2600.0
const SUN_INITIAL_SIDE := -330.0
const SUN_INITIAL_HEIGHT := 65.0
const SUN_RECEDING_FORWARD := 5000.0
const SUN_RECEDING_SIDE := 1200.0
const ACCRETION_DISK_INNER_RADIUS := 38.0
const ACCRETION_DISK_OUTER_RADIUS := 72.0
const ACCRETION_DISK_TILT_DEGREES := 48.0

# Космос по сюжету: три стадии пролёта.
#   0 — Солнечная система: газовый гигант с кольцами за бортом, звёзды.
#   1 — пустота: планета уходит в сторону/назад, звёзды, чёрная дыра вдали.
#   2 — чёрная дыра: планета скрыта, дыра занимает окно, аккреция близко.
# Сцена только управляет объектами, созданными в ship_interior.tscn
# (SpaceGasGiant / SpaceRing / SpaceBlackHole). Триггерить переходы может
# сюжетный скрипт вызовом set_stage(1) / set_stage(2).

signal stage_changed(index: int)

@export var initial_stage: int = 0
@export var transition_time: float = 7.0
## Угловая скорость планеты на безопасной орбите (радиан в секунду).
@export_range(0.0, 0.01, 0.00005) var orbit_speed: float = 0.00045
## Центр орбиты фиксирован у корабля; радиус берётся из исходного положения планеты.
@export var orbit_center := Vector3(0.0, 6.0, 12.0)

var _gas: Node3D
var _ring: Node3D
var _blackhole: Node3D
var _sun: Node3D
var _blackhole_animation: AnimationPlayer
var _tween: Tween
var _stage := 0
var _base := {}
var _orbit_radius := 0.0
var _orbit_angle := 0.0
var _window_forward := Vector3.FORWARD
var _window_right := Vector3.RIGHT
var _window_eye := Vector3.ZERO

# стадия: смещение и масштаб планет; дыра; видимость
const STAGES := [
	{
		"gas_offset": Vector3.ZERO,
		"gas_scale": PLANET_VIEW_SCALE,
		"ring_scale": 0.38,
		"ring_visible": true,
		"bh_offset": Vector3.ZERO,
		"bh_scale": 1.0,
		"bh_visible": false,
		"gas_visible": true,
		"sun_scale": SUN_INITIAL_SCALE,
	},
	{
		"gas_offset": Vector3(280.0, 8.0, 160.0),
		"gas_scale": PLANET_RECEDING_SCALE,
		"ring_scale": 0.15,
		"ring_visible": true,
		"bh_offset": Vector3.ZERO,
		"bh_scale": BLACK_HOLE_SCALE,
		"bh_visible": true,
		"gas_visible": true,
		"sun_scale": SUN_RECEDING_SCALE,
	},
	{
		"gas_offset": Vector3(480.0, 60.0, -60.0),
		"gas_scale": 0.35,
		"ring_scale": 0.35,
		"ring_visible": false,
		"bh_offset": Vector3.ZERO,
		"bh_scale": BLACK_HOLE_SCALE,
		"bh_visible": true,
		"gas_visible": false,
		"sun_scale": SUN_RECEDING_SCALE,
	},
]


func _ready() -> void:
	_find_space_objects()
	if _gas == null:
		push_warning("SpaceStage: не нашёл объекты космоса в сцене")
		return
	_configure_bridge_window_positions()
	_build_planet_ring()
	_install_canary_black_hole()
	_base = {
		"gas_pos": _gas.global_position,
		"gas_scale": _gas.scale.x,
		"ring_pos": _ring.global_position if _ring != null else Vector3.ZERO,
		"ring_scale": _ring.scale.x if _ring != null else 1.0,
		"bh_pos": _blackhole.global_position if _blackhole != null else Vector3.ZERO,
		"bh_scale": _blackhole.scale.x if _blackhole != null else 1.0,
		"sun_pos": _sun.global_position if _sun != null else Vector3.ZERO,
		"sun_scale": _sun.scale.x if _sun != null else 1.0,
	}
	var orbit_delta: Vector2 = Vector2(_gas.global_position.x - orbit_center.x,
		_gas.global_position.z - orbit_center.z)
	_orbit_radius = maxf(orbit_delta.length(), GAS_ORBIT_RADIUS)
	_orbit_angle = atan2(orbit_delta.y, orbit_delta.x)
	set_stage(initial_stage, true)


func _configure_bridge_window_positions() -> void:
	var scene_root := get_parent()
	var interior := scene_root.find_child("ShipInterior", true, false) as Node3D
	if interior == null:
		return
	# Use the actual bridge viewport transform so a future interior rotation does
	# not silently send planets behind the hull again.
	var eye := interior.to_global(Vector3(2.94, 0.0, -13.79)) + Vector3.UP * 1.65
	var target := interior.to_global(Vector3(3.14, 1.4, -17.09))
	_window_eye = eye
	_window_forward = (target - eye).normalized()
	_window_right = _window_forward.cross(Vector3.UP).normalized()
	if _window_right.length_squared() < 0.01:
		_window_right = Vector3.RIGHT
	var orbit_forward := Vector3(_window_forward.x, 0.0, _window_forward.z).normalized()
	var orbit_offset := orbit_forward * GAS_ORBIT_RADIUS
	_gas.global_position = Vector3(
		orbit_center.x + orbit_offset.x,
		eye.y + _window_forward.y * GAS_ORBIT_RADIUS,
		orbit_center.z + orbit_offset.z
	)
	if _ring != null:
		_ring.global_position = _gas.global_position
	if _blackhole != null:
		_blackhole.global_position = eye + _window_forward * BLACK_HOLE_FAR_DISTANCE


func _build_planet_ring() -> void:
	if _ring == null:
		return
	_ring.mesh = _make_annulus(RING_INNER_RADIUS, RING_OUTER_RADIUS, 64, 256)
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.vertex_color_use_as_albedo = true
	ring_material.albedo_color = Color.WHITE
	ring_material.roughness = 1.0
	ring_material.disable_fog = true
	_ring.material_override = ring_material
	var window_up := (Vector3.UP - _window_forward * Vector3.UP.dot(_window_forward)).normalized()
	var ring_normal := (_window_forward * PLANET_RING_VIEW_INCLINATION
		+ window_up * sqrt(1.0 - PLANET_RING_VIEW_INCLINATION * PLANET_RING_VIEW_INCLINATION)).normalized()
	_ring.look_at(_gas.global_position - ring_normal, Vector3.UP)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _make_annulus(inner_radius: float, outer_radius: float,
		radial_steps: int, angular_steps: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for radial_index in range(radial_steps + 1):
		var radial_t := float(radial_index) / float(radial_steps)
		var radius := lerpf(inner_radius, outer_radius, radial_t)
		for angular_index in range(angular_steps + 1):
			var angle := TAU * float(angular_index) / float(angular_steps)
			vertices.append(Vector3(cos(angle) * radius, sin(angle) * radius, 0.0))
			normals.append(Vector3.BACK)
			uvs.append(Vector2(radial_t, float(angular_index) / float(angular_steps)))
			var wide_band := sin(radial_t * TAU * 31.0 + sin(angle * 7.0) * 0.16)
			var fine_band := sin(radial_t * TAU * 97.0 + sin(angle * 17.0) * 0.12)
			var density := clampf(0.58 + wide_band * 0.19 + fine_band * 0.06, 0.12, 0.94)
			var cassini_gap := clampf(1.0 - absf(radial_t - 0.58) / 0.022, 0.0, 1.0)
			var inner_gap := clampf(1.0 - absf(radial_t - 0.19) / 0.016, 0.0, 1.0)
			var outer_gap := clampf(1.0 - absf(radial_t - 0.83) / 0.018, 0.0, 1.0)
			density *= 1.0 - maxf(cassini_gap * 0.86, maxf(inner_gap * 0.56, outer_gap * 0.62))
			density *= 0.94 + 0.06 * sin(angle * 37.0 + radial_t * 42.0)
			var edge_fade := clampf(radial_t / 0.035, 0.0, 1.0) \
				* clampf((1.0 - radial_t) / 0.035, 0.0, 1.0)
			var ring_color := Color(0.43, 0.40, 0.34).lerp(Color(0.91, 0.80, 0.63), density)
			var bright_bands := clampf((density - 0.74) / 0.20, 0.0, 1.0) * 0.32
			ring_color = ring_color.lerp(Color(1.0, 0.93, 0.77), bright_bands)
			ring_color = ring_color.lerp(Color(0.17, 0.18, 0.18), 1.0 - edge_fade)
			colors.append(Color(ring_color.r, ring_color.g, ring_color.b, 1.0))
	for radial_index in range(radial_steps):
		for angular_index in range(angular_steps):
			var inner := radial_index * (angular_steps + 1) + angular_index
			var outer := (radial_index + 1) * (angular_steps + 1) + angular_index
			indices.append(inner)
			indices.append(outer)
			indices.append(outer + 1)
			indices.append(inner)
			indices.append(outer + 1)
			indices.append(inner + 1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _install_canary_black_hole() -> void:
	if _blackhole == null:
		return
	# Keep the existing SpaceBlackHole node as the position/scale anchor used by
	# the story stages, but replace its flat texture quad with the selected GLB.
	if _blackhole is MeshInstance3D:
		(_blackhole as MeshInstance3D).mesh = null
	var model := CANARY_BLACK_HOLE_SCENE.instantiate() as Node3D
	model.name = "CanaryBlackHole"
	model.scale = Vector3.ONE * CANARY_BLACK_HOLE_MODEL_SCALE
	_blackhole.add_child(model)
	var ship := model.find_child("Nave_2", true, false) as Node3D
	if ship != null:
		ship.visible = false
	_blackhole_animation = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _blackhole_animation != null:
		_blackhole_animation.speed_scale = CANARY_BLACK_HOLE_SPEED
		_blackhole_animation.play("Take 001")
	_build_accretion_disk()


func _build_accretion_disk() -> void:
	var disk := MeshInstance3D.new()
	disk.name = "CanaryAccretionDisk"
	disk.mesh = _make_annulus(ACCRETION_DISK_INNER_RADIUS, ACCRETION_DISK_OUTER_RADIUS, 24, 192)
	var disk_material := ShaderMaterial.new()
	disk_material.shader = ACCRETION_DISK_SHADER
	disk.material_override = disk_material
	disk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blackhole.add_child(disk)
	disk.global_position = _blackhole.global_position
	disk.look_at(disk.global_position - _window_forward, Vector3.UP)
	disk.rotate_object_local(Vector3.RIGHT, deg_to_rad(ACCRETION_DISK_TILT_DEGREES))


func _process(delta: float) -> void:
	# Сохраняем постоянную дистанцию до корабля: долгий простой не может
	# превратить дрейф планеты в столкновение с корпусом.
	if _stage != 0 or _tween != null or _gas == null:
		return
	_orbit_angle = wrapf(_orbit_angle + orbit_speed * delta, -PI, PI)
	_gas.global_position = Vector3(
		orbit_center.x + cos(_orbit_angle) * _orbit_radius,
		float(_base["gas_pos"].y),
		orbit_center.z + sin(_orbit_angle) * _orbit_radius
	)
	if _ring != null:
		_ring.global_position = _gas.global_position


func _find_space_objects() -> void:
	# Resolve relative to this scene first; current_scene can still be the old
	# scene while a packed main scene is being instantiated by a loader/test.
	var root: Node = get_parent()
	if root == null:
		root = get_tree().current_scene
	if root == null:
		root = get_tree().root
	_gas = root.find_child("SpaceGasGiant", true, false) as Node3D
	_ring = root.find_child("SpaceRing", true, false) as Node3D
	_blackhole = root.find_child("SpaceBlackHole", true, false) as Node3D
	_sun = root.find_child("Sun", true, false) as Node3D


## Переключить стадию. instant=true — без плавного перехода.
func set_stage(index: int, instant: bool = false) -> void:
	index = clampi(index, 0, STAGES.size() - 1)
	_stage = index
	var data: Dictionary = STAGES[index]

	if _tween != null:
		_tween.kill()
		_tween = null

	var gas_pos: Vector3 = _base["gas_pos"] + data["gas_offset"]
	var gas_scale: float = _base["gas_scale"] * data["gas_scale"]
	var ring_scale: float = _base["ring_scale"] * data["ring_scale"]
	var bh_offset: Vector3 = data["bh_offset"]
	if index == 2:
		bh_offset = _window_forward * (BLACK_HOLE_NEAR_DISTANCE - BLACK_HOLE_FAR_DISTANCE)
	var bh_pos: Vector3 = _base["bh_pos"] + bh_offset
	var bh_scale: float = _base["bh_scale"] * data["bh_scale"]
	var sun_pos: Vector3 = _window_eye + _window_forward * SUN_INITIAL_DISTANCE \
		+ _window_right * SUN_INITIAL_SIDE + Vector3.UP * SUN_INITIAL_HEIGHT
	var sun_scale: float = _base["sun_scale"] * float(data.get("sun_scale", 1.0))
	if index > 0:
		# After FTL the Sun leaves the forward window over the same travel beat.
		sun_pos += _window_forward * SUN_RECEDING_FORWARD + _window_right * SUN_RECEDING_SIDE

	if instant or transition_time <= 0.01:
		_apply(gas_pos, gas_scale, ring_scale, bh_pos, bh_scale, sun_pos, sun_scale, data)
	else:
		_tween = create_tween().set_parallel(true)
		_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if _gas != null:
			_tween.tween_property(_gas, "global_position", gas_pos, transition_time)
			_tween.tween_property(_gas, "scale", Vector3.ONE * gas_scale, transition_time)
			_tween.tween_property(_gas, "visible", data["gas_visible"], 0.6)
		if _ring != null:
			_tween.tween_property(_ring, "global_position", gas_pos, transition_time)
			_tween.tween_property(_ring, "scale", Vector3.ONE * ring_scale, transition_time)
			_tween.tween_property(_ring, "visible", data["ring_visible"], 0.6)
		if _blackhole != null:
			_tween.tween_property(_blackhole, "global_position", bh_pos, transition_time)
			_tween.tween_property(_blackhole, "scale", Vector3.ONE * bh_scale, transition_time)
			_tween.tween_property(_blackhole, "visible", data["bh_visible"], 0.6)
		if _sun != null:
			_tween.tween_property(_sun, "global_position", sun_pos, transition_time)
			_tween.tween_property(_sun, "scale", Vector3.ONE * sun_scale, transition_time)
		_tween.finished.connect(func() -> void: _tween = null)

	stage_changed.emit(index)


func _apply(gas_pos: Vector3, gas_scale: float, ring_scale: float,
		bh_pos: Vector3, bh_scale: float, sun_pos: Vector3, sun_scale: float,
		data: Dictionary) -> void:
	if _gas != null:
		_gas.global_position = gas_pos
		_gas.scale = Vector3.ONE * gas_scale
		_gas.visible = data["gas_visible"]
	if _ring != null:
		_ring.global_position = gas_pos
		_ring.scale = Vector3.ONE * ring_scale
		_ring.visible = data["ring_visible"]
	if _blackhole != null:
		_blackhole.global_position = bh_pos
		_blackhole.scale = Vector3.ONE * bh_scale
		_blackhole.visible = data["bh_visible"]
	if _sun != null:
		_sun.global_position = sun_pos
		_sun.scale = Vector3.ONE * sun_scale
