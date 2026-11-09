extends Node3D

## Пролог: старт корабля с орбитального пускового дока.
## Хронология: стоянка -> запуск систем -> сбой тяги -> перезапуск и
## снятие зажимов -> вертикальный подъём -> разгон и уход в пустоту.
##
## Вся постановка (камера, свет, эффекты, звук) живёт в этом скрипте, чтобы
## таймлайн можно было править в одном месте. Недостающие звуки и текстуры
## эффектов подгружаются, только если они есть в проекте.

const DOCK_SCENE := "res://scenes/launch_dock.tscn"

# ── камеры (три плана) ───────────────────────────────────────────────────
const SHOT1_POS := Vector3(-30.0, 22.0, -40.0)
const SHOT1_TARGET := Vector3(0.0, 11.0, 0.0)
const SHOT1_END_POS := Vector3(-22.0, 16.0, -33.0)
const SHOT1_END_TARGET := Vector3(0.0, 9.5, 0.0)
const SHOT1_FOV := 52.0
const SHOT1_END_FOV := 46.0

const SHOT2_POS := Vector3(24.0, 9.0, 33.0)
const SHOT2_TARGET := Vector3(0.0, 8.0, 4.0)
const SHOT2_END_POS := Vector3(27.5, 10.0, 29.0)
const SHOT2_END_TARGET := Vector3(0.0, 9.0, 3.0)
const SHOT2_FOV := 46.0
const SHOT2_END_FOV := 42.0

const SHOT3_POS := Vector3(-34.0, 6.0, 0.0)
const SHOT3_TARGET := Vector3(0.0, 11.0, 0.0)
const SHOT3_FOV := 58.0

const SHIP_PARK := Vector3(0.0, 3.12, 0.0)
const SHIP_LIFT := Vector3(0.0, 4.0, 0.0)
const SHIP_GONE := Vector3(-10.0, 110.0, -560.0)

# ── базовые параметры VHS (модулируются сбоями) ─────────────────────────
const VHS_STRENGTH := 0.95
const VHS_TEAR := 0.06
const VHS_JUMP := 0.03
const VHS_JITTER := 0.1
const VHS_CHROMA := 0.8

@export var skip_enabled := true
@export var use_placeholder_dock := true

@onready var _ship_root: Node3D = $ShipRoot
@onready var _ship_attitude: Node3D = $ShipRoot/ShipAttitude
@onready var _ship_shake: Node3D = $ShipRoot/ShipAttitude/ShipShake
@onready var _shuttle: Node3D = $ShipRoot/ShipAttitude/ShipShake/LambdaShuttle
@onready var _dock_holder: Node3D = $DockHolder
@onready var _cam_rig: Node3D = $CameraRig
@onready var _cam: Camera3D = $CameraRig/Camera3D
@onready var _cam_target: Node3D = $CamTarget
@onready var _caption: Label = $CanvasLayer/Caption
@onready var _warning: Label = $CanvasLayer/Warning
@onready var _timecode: Label = $CanvasLayer/Timecode
@onready var _flash_rect: ColorRect = $CanvasLayer/Flash
@onready var _vhs: ShaderMaterial = $CanvasLayer/VHS.material
@onready var _key_light: DirectionalLight3D = $KeyLight
@onready var _rim_light: DirectionalLight3D = $RimLight

var _dock: Node3D
var _clamp_base := {}
var _floods: Array[SpotLight3D] = []
var _pad_light: OmniLight3D
var _beacon_mats: Array[StandardMaterial3D] = []
var _beacon_lights: Array[OmniLight3D] = []
var _engine_lights: Array[OmniLight3D] = []
var _engine_flame_mats: Array[StandardMaterial3D] = []
var _engine_flames: Array[MeshInstance3D] = []
var _sparks: Array[CPUParticles3D] = []
var _spark_light: OmniLight3D
var _steam: Array[CPUParticles3D] = []
var _players := {}
var _looping := {}

var _finished := false
var _t := 0.0
var _time := 0.0
var _fade := 1.0
var _glitch_amt := 0.0
var _shake := 0.0
var _shake_extra := 0.0
var _engine_level := 0.0
var _engine_base := 0.0
var _sputter := false
var _engine_on := false
var _follow_ship := false
var _warning_tween: Tween
var _ship_tween: Tween
var _cam_tween: Tween
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_environment()
	_setup_ship()
	_build_dock()
	_build_dock_lights()
	_build_beacons()
	_build_engine_fx()
	_build_sparks()
	_build_steam()
	_build_audio()
	_caption.modulate.a = 0.0
	_warning.modulate.a = 0.0
	$CanvasLayer/SkipHint.visible = skip_enabled
	_cut_shot(SHOT1_POS, SHOT1_TARGET, SHOT1_FOV)
	_run()


func _unhandled_input(event: InputEvent) -> void:
	if skip_enabled and not _finished and event.is_action_pressed("ui_cancel"):
		_skip()


# ─────────────────────────────────────────────────────────────── процесс ──

func _process(delta: float) -> void:
	_t += delta
	_time += delta
	_update_camera(delta)
	_update_engine(delta)
	_update_glitch(delta)
	_update_timecode()


func _update_camera(delta: float) -> void:
	if _follow_ship:
		var want := _ship_root.global_position + Vector3(0, 5.0, 0)
		_cam_target.global_position = _cam_target.global_position.lerp(want,
				clampf(delta * 2.4, 0.0, 1.0))
	_cam_rig.look_at(_cam_target.global_position, Vector3.UP)
	_shake = lerpf(_shake, 0.0, 0.02)
	_shake_extra = lerpf(_shake_extra, 0.0, 0.03)
	var amp := 0.035 + _shake * 0.55 + _shake_extra * 0.25
	var nx := sin(_t * 47.0 + 0.7) * sin(_t * 13.3 + 1.9)
	var ny := sin(_t * 53.0 + 2.3) * sin(_t * 7.7 + 0.4)
	var nz := sin(_t * 41.0 + 4.1) * sin(_t * 11.1 + 2.8)
	_cam.position = Vector3(nx, ny, 0.0) * amp * 0.35
	_cam.rotation_degrees = Vector3(ny * amp * 1.4, nx * amp * 1.1, nz * amp * 1.8)
	var vib := _engine_level * 0.045 + _shake * 0.03
	_ship_shake.position = Vector3(nx, ny, nz) * vib
	_ship_shake.rotation_degrees = Vector3(ny, nx, nz) * vib * 0.5


func _update_engine(delta: float) -> void:
	var target := _engine_base
	if _sputter:
		target = 0.0 if _rng.randf() < 0.55 else _engine_base * _rng.randf_range(0.1, 0.9)
	_engine_level = move_toward(_engine_level, target, delta * 2.6)
	var hum := 0.86 + 0.14 * sin(_t * 23.0 + sin(_t * 5.3))
	if _sputter:
		hum *= _rng.randf_range(0.2, 1.0)
	var lvl := clampf(_engine_level * hum, 0.0, 1.6)
	for light in _engine_lights:
		light.light_energy = lvl * float(light.get_meta("base_energy", 7.0))
	for flame in _engine_flames:
		if flame == null:
			continue
		var vis := clampf(lvl * 1.3, 0.0, 1.0)
		flame.visible = vis > 0.02
		var s := 0.45 + vis * 0.95
		flame.scale = Vector3(s, s, s)
	for mat in _engine_flame_mats:
		mat.albedo_color.a = clampf(lvl, 0.0, 1.0) * 0.95


func _update_glitch(delta: float) -> void:
	_glitch_amt = maxf(0.0, _glitch_amt - delta * 2.2)
	_vhs.set_shader_parameter("strength", VHS_STRENGTH + _glitch_amt * 0.22)
	_vhs.set_shader_parameter("tear", VHS_TEAR + _glitch_amt * 0.55)
	_vhs.set_shader_parameter("jump", VHS_JUMP + _glitch_amt * 0.35)
	_vhs.set_shader_parameter("jitter", VHS_JITTER + _glitch_amt * 0.9)
	_vhs.set_shader_parameter("chroma_shift", VHS_CHROMA + _glitch_amt * 3.0)


func _update_timecode() -> void:
	if _timecode == null:
		return
	var total := int(_time)
	var frames := int((_time - float(total)) * 24.0)
	_timecode.text = "%02d:%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60, frames]


# ──────────────────────────────────────────────────────────── построение ──

func _build_environment() -> void:
	_key_light.transform = _look_basis(_key_light.position, Vector3(0, 8, 0))
	_rim_light.transform = _look_basis(_rim_light.position, Vector3(0, 8, 0))
	# мягкая подсветка со стороны камеры, чтобы силуэт корабля и док
	# читались в каждом плане, а не только там, куда бьют прожекторы
	var cam_fill := OmniLight3D.new()
	cam_fill.name = "CameraFill"
	cam_fill.light_color = Color(0.74, 0.82, 1.0)
	cam_fill.omni_range = 90.0
	cam_fill.omni_attenuation = 1.35
	cam_fill.light_energy = 3.0
	_cam_rig.add_child(cam_fill)


func _setup_ship() -> void:
	# Корабль из Blockbench-кита: притемняем светлый «бумажный» корпус,
	# чтобы он читался как грязный металл в духе арт-дирекшна.
	var hull := _shuttle.get_node_or_null("Hull") as MeshInstance3D
	if hull == null or hull.mesh == null:
		return
	var surfaces := hull.mesh.get_surface_count()
	for i in surfaces:
		var src := hull.get_surface_override_material(i) as StandardMaterial3D
		if src == null:
			src = hull.mesh.surface_get_material(i) as StandardMaterial3D
		if src == null:
			continue
		var dup := src.duplicate() as StandardMaterial3D
		if dup == null:
			continue
		dup.albedo_color = Color(0.46, 0.5, 0.55)
		dup.roughness = 0.82
		dup.metallic = 0.22
		hull.set_surface_override_material(i, dup)


func _look_basis(from: Vector3, to: Vector3) -> Transform3D:
	var t := Transform3D(Basis(), from)
	return t.looking_at(to, Vector3.UP)


func _build_dock() -> void:
	if ResourceLoader.exists(DOCK_SCENE):
		var packed := load(DOCK_SCENE) as PackedScene
		if packed != null:
			_dock = packed.instantiate() as Node3D
			if _dock != null:
				_dock_holder.add_child(_dock)
				print("[intro] dock loaded: ", DOCK_SCENE)
	if _dock != null:
		for child in _dock.find_children("Clamp_*", "Node3D", true, false):
			var clamp := child as Node3D
			if clamp != null:
				_clamp_base[clamp] = clamp.rotation_degrees
	if _dock == null and use_placeholder_dock:
		_dock = _make_placeholder_dock()
		_dock_holder.add_child(_dock)
		print("[intro] placeholder dock built")
	_clear_exit_corridor()


func _clear_exit_corridor() -> void:
	# Фоновые силуэты станции (дальние декорации) не должны стоять на пути
	# вылета: корабль уходит в −Z и может пройти сквозь них. Прячем только
	# те инстансы, чей AABB пересекает коридор вылета, остальные не трогаем.
	if _dock == null:
		return
	var corridor := AABB(Vector3(-90.0, -40.0, -1000.0), Vector3(180.0, 260.0, 1000.0))
	var hidden := 0
	for node in _dock.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		if not mmi.name.to_lower().contains("bg"):
			continue
		var mesh_aabb: AABB = mmi.multimesh.mesh.get_aabb()
		for i in mmi.multimesh.instance_count:
			var xf := mmi.multimesh.get_instance_transform(i)
			var aabb: AABB = (mmi.global_transform * xf) * mesh_aabb
			if corridor.intersects(aabb):
				mmi.multimesh.set_instance_transform(i,
						Transform3D(Basis().scaled(Vector3.ONE * 0.0001), xf.origin))
				hidden += 1
	print("[intro] фоновых объектов убрано из коридора вылета: ", hidden)


func _make_mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _make_emissive(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.035, 0.04)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _box(parent: Node, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	return mesh


func _make_placeholder_dock() -> Node3D:
	var root := Node3D.new()
	root.name = "PlaceholderDock"
	var mat_hull := _make_mat(Color(0.05, 0.056, 0.064), 0.55, 0.6)
	var mat_panel := _make_mat(Color(0.09, 0.1, 0.11), 0.5, 0.6)
	var panel_tex := load("res://assetss/tex2/metal_wall.png")
	if panel_tex is Texture2D:
		mat_panel.albedo_texture = panel_tex
		mat_panel.uv1_scale = Vector3(6.0, 6.0, 1.0)
	var mat_hazard := _make_emissive(Color(1.0, 0.6, 0.16), 2.0)
	var mat_cold := _make_emissive(Color(0.55, 0.78, 1.0), 3.2)
	var mat_beacon := _make_emissive(Color(1.0, 0.1, 0.03), 2.0)

	_box(root, Vector3(46, 0.6, 42), Vector3(0, -0.32, 0), mat_panel)
	_box(root, Vector3(12, 0.06, 16), Vector3(0, 0.02, 0), mat_hull)
	for i in 4:
		if i < 2:
			_box(root, Vector3(0.35, 0.08, 16.4), Vector3(6.2 if i == 0 else -6.2, 0.05, 0), mat_hazard)
		else:
			_box(root, Vector3(12.4, 0.08, 0.35), Vector3(0, 0.05, 8.2 if i == 2 else -8.2), mat_hazard)

	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(root, Vector3(1.8, 19, 1.8), Vector3(21 * sx, 9.5, 18 * sz), mat_hull)
			_box(root, Vector3(0.22, 17, 0.22), Vector3(21 * sx - 0.95 * sx, 9.0, 18 * sz - 0.95 * sz), mat_cold)
			_box(root, Vector3(1.4, 1.2, 1.4), Vector3(20.2 * sx, 17.6, 17.2 * sz), mat_hull)
			_box(root, Vector3(1.0, 0.7, 0.9), Vector3(19.5 * sx, 17.4, 16.6 * sz), mat_cold)
			var anchor := Marker3D.new()
			anchor.name = "LightAnchor_%d%d" % [int(sx > 0.0), int(sz > 0.0)]
			anchor.position = Vector3(19.6 * sx, 17.2, 16.8 * sz)
			root.add_child(anchor)
			_box(root, Vector3(0.9, 0.9, 0.9), Vector3(21 * sx, 19.4, 18 * sz), mat_beacon)

	for sz in [-1.0, 1.0]:
		_box(root, Vector3(43.8, 1.0, 1.0), Vector3(0, 18.8, 18 * sz), mat_hull)
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(1.0, 1.0, 36.8), Vector3(21 * sx, 18.8, 0), mat_hull)

	var clamp_defs := [
		["Clamp_NW", Vector3(-16.0, 4.5, -7.5), 1.0],
		["Clamp_NE", Vector3(-16.0, 4.5, 7.5), 1.0],
		["Clamp_SW", Vector3(16.0, 4.5, -7.5), -1.0],
		["Clamp_SE", Vector3(16.0, 4.5, 7.5), -1.0],
	]
	for def in clamp_defs:
		var pivot := Node3D.new()
		pivot.name = def[0]
		pivot.position = def[1]
		root.add_child(pivot)
		var dirx: float = def[2]
		_box(pivot, Vector3(6.4, 0.9, 1.4), Vector3(dirx * 3.2, 0, 0), mat_hull)
		_box(pivot, Vector3(1.6, 2.2, 2.4), Vector3(dirx * 6.6, 0.2, 0), mat_hazard)

	var mat_far := _make_mat(Color(0.028, 0.031, 0.036), 0.4, 0.85)
	_box(root, Vector3(150, 26, 30), Vector3(120, 6, -210), mat_far)
	_box(root, Vector3(120, 18, 34), Vector3(-150, 2, -260), mat_far)
	_box(root, Vector3(220, 8, 12), Vector3(60, -24, -300), mat_far)
	for fl in [Vector3(112, 18, -196), Vector3(-140, 10, -246), Vector3(46, -20, -296)]:
		_box(root, Vector3(0.8, 0.8, 0.8), fl, mat_cold)
	return root


func _build_dock_lights() -> void:
	var anchor_points: Array[Vector3] = []
	if _dock != null:
		for child in _dock.find_children("LightAnchor_*", "Marker3D", true, false):
			var mark := child as Marker3D
			if mark != null:
				anchor_points.append(mark.global_position)
	if anchor_points.is_empty():
		anchor_points = [
			Vector3(-19.6, 17.2, -16.8), Vector3(19.6, 17.2, -16.8),
			Vector3(-19.6, 17.2, 16.8), Vector3(19.6, 17.2, 16.8),
		]
	var idx := 0
	for p in anchor_points:
		var spot := SpotLight3D.new()
		spot.name = "Flood_%d" % idx
		spot.light_color = Color(0.72, 0.82, 1.0)
		spot.spot_range = 90.0
		spot.spot_angle = 26.0
		spot.spot_angle_attenuation = 0.9
		spot.shadow_enabled = false
		spot.light_energy = 0.0
		spot.transform = _look_basis(p, Vector3(0, 8, 0))
		add_child(spot)
		_floods.append(spot)
		idx += 1
	_pad_light = OmniLight3D.new()
	_pad_light.name = "PadBounce"
	_pad_light.light_color = Color(1.0, 0.7, 0.45)
	_pad_light.omni_range = 26.0
	_pad_light.light_energy = 0.0
	_pad_light.position = Vector3(0, 1.2, 0)
	add_child(_pad_light)


func _build_beacons() -> void:
	var pts := [
		Vector3(-20.5, 23.1, -18.5), Vector3(20.5, 23.1, -18.5),
		Vector3(-20.5, 23.1, 18.5), Vector3(20.5, 23.1, 18.5),
	]
	var sphere := SphereMesh.new()
	sphere.radius = 0.42
	sphere.height = 0.84
	sphere.radial_segments = 8
	sphere.rings = 4
	for p in pts:
		var mat := _make_emissive(Color(1.0, 0.07, 0.02), 1.0)
		_beacon_mats.append(mat)
		var mesh := MeshInstance3D.new()
		mesh.mesh = sphere
		mesh.material_override = mat
		mesh.position = p
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.14, 0.05)
		light.omni_range = 16.0
		light.light_energy = 0.0
		light.position = p + Vector3(0, -0.3, 0)
		add_child(light)
		_beacon_lights.append(light)


func _build_engine_fx() -> void:
	var glow_tex: Texture2D = _radial_gradient_texture("EngineGlowGrad", [
		[0.0, Color(1, 1, 1, 1)], [0.22, Color(1, 0.85, 0.6, 0.95)],
		[0.55, Color(1, 0.45, 0.16, 0.45)], [1.0, Color(0.6, 0.1, 0.0, 0.0)],
	])
	var glow_png: Texture2D = null
	if ResourceLoader.exists("res://assetss/fx/intro/engine_flame.png"):
		glow_png = load("res://assetss/fx/intro/engine_flame.png") as Texture2D
	if glow_png != null:
		glow_tex = glow_png

	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame_mat.billboard_keep_scale = true
	flame_mat.albedo_texture = glow_tex
	flame_mat.albedo_color = Color(1.0, 0.8, 0.55, 0.0)
	flame_mat.disable_fog = true
	flame_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_engine_flame_mats.append(flame_mat)

	var quad := QuadMesh.new()
	quad.size = Vector2(6.5, 6.5)
	for sz in [-1.0, 1.0]:
		var flame := MeshInstance3D.new()
		flame.mesh = quad
		flame.material_override = flame_mat
		flame.position = Vector3(-11.8, -0.35, 1.45 * sz)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ship_shake.add_child(flame)
		_engine_flames.append(flame)

	for sz in [-1.0, 1.0]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.22)
		light.omni_range = 55.0
		light.omni_attenuation = 1.2
		light.light_energy = 0.0
		light.position = Vector3(-13.2, -0.4, 1.45 * sz)
		light.set_meta("base_energy", 7.0)
		_ship_shake.add_child(light)
		_engine_lights.append(light)
	var bounce := OmniLight3D.new()
	bounce.light_color = Color(1.0, 0.6, 0.3)
	bounce.omni_range = 30.0
	bounce.light_energy = 0.0
	bounce.position = Vector3(-9.0, -1.5, 0.0)
	bounce.set_meta("base_energy", 2.2)
	_ship_shake.add_child(bounce)
	_engine_lights.append(bounce)


func _build_sparks() -> void:
	var spark_tex: Texture2D = _radial_gradient_texture("SparkGrad", [
		[0.0, Color(1, 1, 1, 1)], [0.35, Color(1, 0.85, 0.45, 0.9)],
		[0.75, Color(1, 0.35, 0.05, 0.25)], [1.0, Color(0.6, 0.1, 0, 0)],
	])
	var png: Texture2D = null
	if ResourceLoader.exists("res://assetss/fx/intro/spark.png"):
		png = load("res://assetss/fx/intro/spark.png") as Texture2D
	if png != null:
		spark_tex = png
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = spark_tex
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true

	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	quad.material = mat
	for p in [Vector3(-8.6, 2.4, 6.4), Vector3(-9.6, 0.2, -6.2), Vector3(-10.2, -1.0, 2.2)]:
		var parts := CPUParticles3D.new()
		parts.mesh = quad
		parts.position = p
		parts.amount = 40
		parts.lifetime = 0.9
		parts.one_shot = true
		parts.explosiveness = 0.95
		parts.randomness = 0.4
		parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		parts.emission_sphere_radius = 0.5
		parts.direction = Vector3(0.4, 0.7, 0.4).normalized()
		parts.spread = 75.0
		parts.gravity = Vector3(0, -12.0, 0)
		parts.initial_velocity_min = 3.0
		parts.initial_velocity_max = 9.0
		parts.damping_min = 0.5
		parts.damping_max = 1.5
		parts.scale_amount_min = 0.5
		parts.scale_amount_max = 1.2
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
		ramp.colors = PackedColorArray([
			Color(1, 1, 0.9, 1), Color(1, 0.8, 0.35, 1),
			Color(1, 0.35, 0.05, 0.7), Color(0.5, 0.05, 0, 0),
		])
		parts.color_ramp = ramp
		parts.emitting = false
		parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ship_shake.add_child(parts)
		_sparks.append(parts)
	_spark_light = OmniLight3D.new()
	_spark_light.light_color = Color(1.0, 0.6, 0.25)
	_spark_light.omni_range = 22.0
	_spark_light.light_energy = 0.0
	_spark_light.position = Vector3(-8.6, 1.5, 6.2)
	_ship_shake.add_child(_spark_light)


func _build_steam() -> void:
	var puff_tex: Texture2D = _radial_gradient_texture("PuffGrad", [
		[0.0, Color(1, 1, 1, 0.55)], [0.5, Color(0.8, 0.82, 0.85, 0.3)],
		[1.0, Color(0.6, 0.62, 0.65, 0.0)],
	])
	var png: Texture2D = null
	if ResourceLoader.exists("res://assetss/fx/intro/smoke_puff.png"):
		png = load("res://assetss/fx/intro/smoke_puff.png") as Texture2D
	if png != null:
		puff_tex = png
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_texture = puff_tex
	mat.albedo_color = Color(0.7, 0.73, 0.78, 0.5)
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true

	var quad := QuadMesh.new()
	quad.size = Vector2(3.5, 3.5)
	quad.material = mat
	for p in [Vector3(-7.5, 0.3, -8.5), Vector3(7.5, 0.3, -8.5),
			Vector3(-7.5, 0.3, 8.5), Vector3(7.5, 0.3, 8.5)]:
		var parts := CPUParticles3D.new()
		parts.mesh = quad
		parts.position = p
		parts.amount = 18
		parts.lifetime = 3.2
		parts.one_shot = true
		parts.explosiveness = 0.6
		parts.randomness = 0.5
		parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		parts.emission_box_extents = Vector3(2.5, 0.2, 2.5)
		parts.direction = Vector3(0, 1, 0)
		parts.spread = 35.0
		parts.gravity = Vector3(0, 1.6, 0)
		parts.initial_velocity_min = 1.5
		parts.initial_velocity_max = 4.0
		parts.damping_min = 0.4
		parts.damping_max = 0.9
		parts.scale_amount_min = 1.0
		parts.scale_amount_max = 2.2
		var curve := Curve.new()
		curve.add_point(Vector2(0, 0.35))
		curve.add_point(Vector2(0.5, 1.1))
		curve.add_point(Vector2(1, 1.9))
		parts.scale_amount_curve = curve
		var ramp := Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
		ramp.colors = PackedColorArray([
			Color(0.9, 0.92, 0.95, 0.0), Color(0.85, 0.87, 0.9, 0.5),
			Color(0.7, 0.72, 0.76, 0.22), Color(0.6, 0.62, 0.65, 0.0),
		])
		parts.color_ramp = ramp
		parts.emitting = false
		parts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(parts)
		_steam.append(parts)


func _build_audio() -> void:
	_players["ambient"] = $Audio/AmbientBed
	_players["takeoff"] = $Audio/EngineTakeoff
	_players["creak"] = $Audio/Creak
	for p in _players.values():
		(p as AudioStreamPlayer).volume_db = -60.0
	_add_sound("power_up", "res://assetss/audio/intro/power_up.wav", -8.0)
	_add_sound("alarm", "res://assetss/audio/intro/alarm_loop.wav", -12.0, true)
	_add_sound("sputter", "res://assetss/audio/intro/engine_sputter.wav", -8.0)
	_add_sound("ignition", "res://assetss/audio/intro/engine_ignition.wav", -4.0)
	_add_sound("rumble", "res://assetss/audio/intro/engine_rumble_loop.wav", -14.0, true)
	_add_sound("sparks", "res://assetss/audio/intro/sparks.wav", -9.0)
	_add_sound("clunk", "res://assetss/audio/intro/clunk.wav", -6.0)
	_add_sound("whoosh", "res://assetss/audio/intro/whoosh_flyby.wav", -8.0)
	_add_sound("groan", "res://assetss/audio/intro/hull_groan.wav", -12.0)


func _add_sound(key: String, path: String, volume_db: float, loop := false) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = "sfx_" + key
	player.stream = stream
	player.volume_db = -60.0
	$Audio.add_child(player)
	_players[key] = player
	if loop:
		_looping[key] = true
		player.finished.connect(player.play)


func _radial_gradient_texture(res_name: String, stops: Array) -> GradientTexture2D:
	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for s in stops:
		offsets.append(s[0])
		colors.append(s[1])
	grad.offsets = offsets
	grad.colors = colors
	var tex := GradientTexture2D.new()
	tex.resource_name = res_name
	tex.gradient = grad
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.0, 0.5)
	return tex


# ─────────────────────────────────────────────────────────────── таймлайн ──

func _run() -> void:
	# 0.0 — стоянка в доке, камера медленно подъезжает
	_fade_to(0.0, 2.6)
	_audio_fade("ambient", -22.0, 3.0)
	_dolly(SHOT1_END_POS, SHOT1_END_TARGET, 9.4, Tween.TRANS_SINE, Tween.EASE_IN_OUT,
			SHOT1_END_FOV)
	await _wait(2.2)
	if _finished:
		return
	_show_caption("ОРБИТАЛЬНЫЙ ДОК B-3 // 04:17", 4.6)
	await _wait(2.4)
	if _finished:
		return
	_play("creak", -18.0, 1.0)

	# 5.8 — запуск систем
	await _wait(1.6)
	if _finished:
		return
	_power_up()

	# 9.6 — сбой
	await _wait(3.8)
	if _finished:
		return
	_glitch(0.8)
	_cut_shot(SHOT2_POS, SHOT2_TARGET, SHOT2_FOV)
	_dolly(SHOT2_END_POS, SHOT2_END_TARGET, 7.4, Tween.TRANS_SINE, Tween.EASE_IN_OUT,
			SHOT2_END_FOV)
	await _wait(0.7)
	if _finished:
		return
	_malfunction()

	# 14.0 — перезапуск, вспышка
	await _wait(4.4)
	if _finished:
		return
	_recovery_ignition()

	# 16.9 — третий план, снятие зажимов, подъём
	await _wait(2.9)
	if _finished:
		return
	_glitch(0.9)
	_cut_shot(SHOT3_POS, SHOT3_TARGET, SHOT3_FOV)
	await _wait(0.9)
	if _finished:
		return
	_release_clamps()
	await _wait(1.3)
	if _finished:
		return
	_liftoff()

	# 23.5 — разгон и уход
	await _wait(3.4)
	if _finished:
		return
	_depart()
	await _wait(4.0)
	if _finished:
		return
	_ending()
	await _wait(2.7)
	_finish()


func _power_up() -> void:
	_play("power_up", -9.0, 0.25)
	_engine_on = true
	_engine_base = 0.16
	_flash(0.10, 0.5)
	_glitch(0.30)
	_add_shake(0.18, 0.6)
	var tw := create_tween().set_parallel(true)
	for i in _floods.size():
		tw.tween_property(_floods[i], "light_energy", 7.5, 1.6).set_delay(i * 0.28)
		tw.tween_property(_floods[i], "light_energy", 5.0, 1.2).set_delay(1.7 + i * 0.28)
	if _pad_light != null:
		tw.tween_property(_pad_light, "light_energy", 0.8, 2.2).set_delay(0.4)
	var light_tw := create_tween()
	for i in 6:
		light_tw.tween_callback(func() -> void: _glitch(0.18))
		light_tw.tween_interval(0.12)
	_play("creak", -20.0, 0.8)


func _malfunction() -> void:
	_sputter = true
	_play("alarm", -14.0, 0.2)
	_play("sputter", -8.0, 0.1)
	_play("groan", -13.0, 0.2)
	_show_warning("СБОЙ ТЯГИ // ПЕРЕЗАПУСК", true)
	_add_shake(0.75, 2.4)
	_glitch(0.85)
	var tw := create_tween()
	for i in 5:
		tw.tween_callback(_spark_burst)
		tw.tween_callback(_beacon_pulse)
		tw.tween_interval(0.65)
	var flick := create_tween().set_loops(5)
	for flood in _floods:
		flick.parallel().tween_property(flood, "light_energy", 1.2, 0.11)
		flick.parallel().tween_property(flood, "light_energy", 7.0, 0.2)
	flick.tween_interval(0.25)
	var glitch_tw := create_tween()
	for i in 7:
		glitch_tw.tween_callback(func() -> void: _glitch(0.6))
		glitch_tw.tween_interval(0.42)


func _recovery_ignition() -> void:
	_sputter = false
	_engine_base = 1.0
	_flash(0.38, 0.6)
	_add_shake(1.5, 1.6)
	_glitch(1.0)
	_play("ignition", -7.0, 0.08)
	_play("takeoff", -8.0, 0.6)
	_play("rumble", -16.0, 0.8)
	_audio_fade("rumble", -9.0, 3.2)
	_audio_fade("alarm", -60.0, 1.0)
	_show_warning("", false)
	_engine_flash_lights()
	var tw := create_tween().set_parallel(true)
	for flood in _floods:
		tw.tween_property(flood, "light_energy", 9.5, 0.4)
		tw.tween_property(flood, "light_energy", 6.5, 1.4).set_delay(0.5)
	await _wait(0.2)
	_show_caption("ПЕРЕЗАПУСК ТЯГИ // НОРМА", 2.2)


func _release_clamps() -> void:
	_play("clunk", -8.0, 0.03)
	_glitch(0.45)
	_add_shake(0.6, 1.0)
	var clamps: Array[Node3D] = []
	if _dock != null:
		for child in _dock.find_children("Clamp_*", "Node3D", true, false):
			var n := child as Node3D
			if n != null:
				clamps.append(n)
	for clamp in clamps:
		var side := signf(clamp.global_position.x)
		var zside := signf(clamp.global_position.z)
		var base: Vector3 = _clamp_base.get(clamp, clamp.rotation_degrees)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(clamp, "position", clamp.position + Vector3(side * 2.6, 0.6, 0), 1.3
				).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(clamp, "rotation_degrees",
				Vector3(base.x, base.y - side * zside * 34.0, base.z - 24.0), 1.3
				).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for p in _sparks:
		p.restart()
		p.emitting = true
	await _wait(0.3)
	for p in _sparks:
		p.emitting = false


func _liftoff() -> void:
	_engine_base = 1.2
	_show_warning("", false)
	_add_shake(1.2, 3.0)
	_play("groan", -13.0, 0.25)
	_audio_fade("takeoff", -4.0, 2.0)
	_audio_fade("rumble", -7.0, 3.0)
	if _ship_tween != null and _ship_tween.is_valid():
		_ship_tween.kill()
	_ship_tween = create_tween().set_parallel(true)
	_ship_tween.tween_property(_ship_root, "position", SHIP_LIFT, 2.8
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ship_tween.tween_property(_ship_attitude, "rotation_degrees", Vector3(0.0, 0.0, 9.0), 2.8
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = create_tween().set_parallel(true)
	_cam_tween.tween_property(_cam_target, "position", Vector3(0, 13, 0), 3.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(_cam_rig, "position", Vector3(-36.5, 6.5, 1.5), 3.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(_cam, "fov", 60.0, 3.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for s in _steam:
		s.restart()
		s.emitting = true
	var dim := create_tween().set_parallel(true)
	for b in _beacon_mats:
		dim.tween_property(b, "emission_energy_multiplier", 0.4, 2.0)
	for l in _beacon_lights:
		dim.tween_property(l, "light_energy", 0.0, 2.0)
	_spark_burst()


func _depart() -> void:
	_engine_base = 1.5
	_add_shake(1.8, 2.0)
	_play("whoosh", -10.0, 1.2)
	_audio_fade("takeoff", -4.0, 2.0)
	if _ship_tween != null and _ship_tween.is_valid():
		_ship_tween.kill()
	# 1) сначала выходим из дока на той же высоте — чтобы высокий киль не задел
	#    верхние фермы; 2) уже в пустоте разгоняемся и набираем высоту.
	_ship_tween = create_tween()
	_ship_tween.tween_property(_ship_root, "position", Vector3(0.0, 4.05, -34.0), 2.6
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_ship_tween.tween_property(_ship_root, "position", SHIP_GONE, 6.0
			).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var attitude_tw := create_tween()
	attitude_tw.tween_property(_ship_attitude, "rotation_degrees", Vector3(-4.0, 3.0, 14.0), 8.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_follow_ship = false
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	# финальный план: камера сзади за доком, корабль уходит в звёзды
	_glitch(0.75)
	_cut_shot(Vector3(0.0, 16.0, 46.0), Vector3(0.0, 10.0, 0.0), 50.0)
	_cam_tween = create_tween().set_parallel(true)
	_cam_tween.tween_property(_cam_rig, "position", Vector3(0.0, 20.0, 56.0), 5.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_cam_tween.tween_property(_cam_target, "position", Vector3(0.0, 26.0, -40.0), 5.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(_cam, "fov", 46.0, 5.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _ending() -> void:
	_audio_fade("takeoff", -60.0, 2.6)
	_audio_fade("rumble", -60.0, 2.6)
	_audio_fade("ambient", -60.0, 2.6)
	for key in _players.keys():
		var p := _players[key] as AudioStreamPlayer
		if p != null:
			create_tween().tween_property(p, "volume_db", -60.0, 2.6)
	_flash(0.12, 1.2)
	var tw := create_tween()
	tw.tween_method(_set_fade, _fade, 1.0, 2.6)
	$CanvasLayer/SkipHint.visible = false
	_caption.modulate.a = 0.0


func _finish() -> void:
	if _finished:
		return
	_finished = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _skip() -> void:
	if _finished:
		return
	_finished = true
	$CanvasLayer/SkipHint.visible = false
	for key in _players.keys():
		var p := _players[key] as AudioStreamPlayer
		if p != null:
			p.stop()
	var tw := create_tween()
	tw.tween_method(_set_fade, _fade, 1.0, 0.35)
	await tw.finished
	get_tree().change_scene_to_file("res://scenes/main.tscn")


# ──────────────────────────────────────────────────────── мелкие действия ──

func _play(key: String, volume_db: float, fade_in := 0.0) -> void:
	var p := _players.get(key) as AudioStreamPlayer
	if p == null:
		return
	if fade_in > 0.0:
		p.volume_db = -60.0
		p.play()
		create_tween().tween_property(p, "volume_db", volume_db, fade_in)
	else:
		p.volume_db = volume_db
		p.play()


func _audio_fade(key: String, volume_db: float, time: float) -> void:
	var p := _players.get(key) as AudioStreamPlayer
	if p == null:
		return
	if p.playing:
		create_tween().tween_property(p, "volume_db", volume_db, time)


func _spark_burst() -> void:
	for p in _sparks:
		p.restart()
		p.emitting = true
	if _spark_light != null:
		_spark_light.light_energy = 6.0
		create_tween().tween_property(_spark_light, "light_energy", 0.0, 0.35)
	_play("sparks", -8.0)
	_glitch(0.35)
	_add_shake(0.5, 0.4)
	await _wait(0.22)
	for p in _sparks:
		p.emitting = false


func _beacon_pulse() -> void:
	for mat in _beacon_mats:
		var tw := create_tween()
		tw.tween_property(mat, "emission_energy_multiplier", 7.0, 0.06)
		tw.tween_property(mat, "emission_energy_multiplier", 0.8, 0.5)
	for l in _beacon_lights:
		var tw := create_tween()
		tw.tween_property(l, "light_energy", 4.0, 0.06)
		tw.tween_property(l, "light_energy", 0.0, 0.5)


func _engine_flash_lights() -> void:
	for l in _engine_lights:
		l.light_energy = 18.0
	for mat in _engine_flame_mats:
		mat.albedo_color.a = 1.0


func _add_shake(amount: float, hold: float) -> void:
	_shake = maxf(_shake, amount)
	var tw := create_tween()
	tw.tween_property(self, "_shake_extra", amount * 0.55, 0.1)
	tw.tween_property(self, "_shake_extra", 0.0, hold).set_delay(0.1)


func _glitch(amount: float) -> void:
	_glitch_amt = maxf(_glitch_amt, amount)


func _flash(alpha: float, time: float) -> void:
	_flash_rect.color = Color(1.0, 1.0, 1.0, alpha)
	var tw := create_tween()
	tw.tween_property(_flash_rect, "color:a", 0.0, time)


# ────────────────────────────────────────────────────────────── камера ──

func _cut_shot(pos: Vector3, target: Vector3, fov: float) -> void:
	_cam_rig.position = pos
	_cam_target.position = target
	_cam.fov = fov


func _dolly(pos: Vector3, target: Vector3, time: float, trans: int, ease: int,
		fov: float) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_cam_rig, "position", pos, time).set_trans(trans).set_ease(ease)
	tw.tween_property(_cam_target, "position", target, time).set_trans(trans).set_ease(ease)
	tw.tween_property(_cam, "fov", fov, time).set_trans(trans).set_ease(ease)


# ──────────────────────────────────────────────────────────────── UI/HUD ──

func _show_caption(text: String, hold: float) -> void:
	if _caption == null:
		return
	_caption.text = text
	var tw := create_tween()
	tw.tween_property(_caption, "modulate:a", 1.0, 0.6)
	tw.tween_interval(hold)
	tw.tween_property(_caption, "modulate:a", 0.0, 0.9)


func _show_warning(text: String, on: bool) -> void:
	if _warning_tween != null and _warning_tween.is_valid():
		_warning_tween.kill()
	if text != "":
		_warning.text = text
	if on:
		_warning_tween = create_tween().set_loops()
		_warning_tween.tween_property(_warning, "modulate:a", 1.0, 0.12)
		_warning_tween.tween_property(_warning, "modulate:a", 0.18, 0.38)
	else:
		_warning_tween = create_tween()
		_warning_tween.tween_property(_warning, "modulate:a", 0.0, 0.35)


# ────────────────────────────────────────────────────────────── переходы ──

func _set_fade(value: float) -> void:
	_fade = value
	_vhs.set_shader_parameter("fade_amount", value)


func _fade_to(value: float, time: float) -> void:
	var tw := create_tween()
	tw.tween_method(_set_fade, _fade, value, time)


func _wait(seconds: float) -> void:
	var tw := create_tween()
	tw.tween_interval(seconds)
	await tw.finished
