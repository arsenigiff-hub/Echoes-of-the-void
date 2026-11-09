@tool
extends Node3D

# =============================================================================
# LAUNCH DOCK — стартовая площадка орбитального дока для катсцены старта.
#
# Вся геометрия строится процедурно в _ready() (сцена launch_dock.tscn почти
# пустая: один Node3D + этот скрипт). Это позволяет Лиду свободно анимировать
# узлы Clamp_* и не тащить в git тысячи строк .tscn.
#
# СОСТАВ:
#   * настил 44 x 40 м из kit-плиток floor_tile (2 x 2 м) — MultiMesh;
#   * hazard-трим по краю «посадочного пятака» и по внешнему периметру;
#   * трубы/кабели под настилом и по краям (kit pipe_run / cable_bundle);
#   * 4 ферменные вышки 22.5 м + верхние фермы-рамы + 2 подвесные кран-балки;
#   * 4 зажима Clamp_NW / Clamp_NE / Clamp_SW / Clamp_SE — Node3D, pivot у
#     внешнего основания (x = ±15, z = ±8, y = 4), лапа тянется к кораблю
#     до x = ±9 (ладонь обхватывает законцовку крыла);
#   * эмиссивные акценты: холодные рабочие полосы, янтарные лампы по краю,
#     красные маячки на вышках, зелёные CRT-вставки;
#   * дальний фон: силуэты станции/кольца/ферм на 100–250 м.
#
# СОГЛАШЕНИЯ:
#   1 юнит = 1 м. Origin — центр площадки, верх настила y = 0.
#   Свободная зона корабля: x[-14..14], z[-16..16], y[0..26] НЕ занимается
#   статикой. Единственное исключение — лапы зажимов (они специально
#   дотягиваются до x = ±9, чтобы держать крыло), ими Лид анимирует сброс.
#   НИКАКИХ Light3D внутри сцены: только эмиссивные материалы.
#   Marker3D LightAnchor_1..4 — позиция/ориентация (-Z смотрит в цель) для
#   реальных SpotLight3D, которые Лид добавляет в катсцене.
#
# АНИМАЦИЯ ЗАЖИМОВ (для Лида):
#   Каждый Clamp_* — Node3D, origin = шарнир у внешнего основания.
#   Локальная геометрия: лапа идёт вдоль local -X (к центру площадки),
#   вверх +Y, вбок ±Z. Поворот узла вокруг local Y отводит лапу вбок,
#   вокруг local Z — поднимает/опускает. У западных зажимов (Clamp_NW/SW)
#   узел повёрнут на 180° по Y — их локальные оси те же.
#   Координаты лапы в локе: кончик лапы x ≈ -6.3, ладонь y ≈ ±0.6.
# =============================================================================

const ARCH := "res://assetss/shipkit/arch/"
const EQUIP := "res://assetss/shipkit/equip/"
const TEX2 := "res://assetss/tex2/"
const TEX := "res://assetss/tex/"

# --- габариты площадки -------------------------------------------------------
const DECK_HALF_X := 22.0        # настил 44 м по X
const DECK_HALF_Z := 20.0        # настил 40 м по Z
const TILE := 2.0
const DECK_TOP_Y := 0.0          # верх настила
const TILE_TOP := 0.008          # у kit-плитки верх на +0.008 от origin

# --- вышки, зажимы, кран-балки ----------------------------------------------
const TOWER_X := 20.5
const TOWER_Z := 18.5
const TOWER_H := 22.5
const CLAMP_X := 15.0
const CLAMP_Y := 4.0
const CLAMP_Z := 8.0
const GANTRY_X := 10.0
const GANTRY_Y := 27.2
const GANTRY_TOP_Y := 28.45

# --- свободная зона под корабль ---------------------------------------------
const FREE_MIN := Vector3(-14.0, 0.0, -16.0)
const FREE_MAX := Vector3(14.0, 26.0, 16.0)

@export var build_in_editor := true     # @tool: строить ли геометрию в редакторе
@export var verbose_report := true      # печатать сводку в консоль

# --- материалы --------------------------------------------------------------
var _mats: Dictionary = {}

# --- накопители батчей ------------------------------------------------------
# Ключ — материал; значение — Array[Transform3D] (локальное пространство корня).
var _gb: Dictionary = {}     # глобальные коробки
var _gs: Dictionary = {}     # глобальные сферы-лампы
var _lb: Dictionary = {}     # коробки внутри узла зажима
var _ls: Dictionary = {}     # сферы внутри узла зажима

var _mesh_cache: Dictionary = {}
var _unit_box: BoxMesh
var _unit_sphere: SphereMesh

var _group_nodes: Dictionary = {}
var _clamp_info: Array = []
var _anchor_info: Array = []

# Карта слотов материалов kit-модулей -> материалы дока.
const KIT_MAP := {
	"metal_panel": "metal",
	"metal_dark": "metal_dark",
	"paint_worn": "paint",
	"rust": "rust",
	"hazard_y": "hazard",
	"hazard_k": "metal_dark",
	"crt_green": "lamp_green",
	"red_lamp": "lamp_red",
	"lamp_cold": "lamp_cold",
	"wet_grime": "wet",
}

const FLOOR_MAP := {
	"metal_panel": "floor_plate",
	"metal_dark": "floor_grate",
	"paint_worn": "floor_grate",
	"rust": "rust",
}

const WET_FLOOR_MAP := {
	"metal_panel": "floor_plate",
	"metal_dark": "floor_grate",
	"paint_worn": "floor_grate",
	"rust": "rust",
	"wet_grime": "wet",
}


# =============================================================================
#  ЗАПУСК
# =============================================================================

func _ready() -> void:
	if Engine.is_editor_hint() and not build_in_editor:
		return
	var t0 := Time.get_ticks_msec()
	_prepare_materials()
	_build_deck()
	_build_deck_understructure()
	_build_edge_trim_and_lamps()
	_build_clamp_pedestals()
	_build_clamps()
	_build_towers()
	_build_top_frames()
	_build_gantries_and_anchors()
	_build_ground_dressing()
	_build_background()
	_flush_global_batches()
	if verbose_report:
		_report(Time.get_ticks_msec() - t0)


func _group(node_name: String) -> Node3D:
	if _group_nodes.has(node_name):
		return _group_nodes[node_name] as Node3D
	var n := Node3D.new()
	n.name = node_name
	add_child(n)
	_group_nodes[node_name] = n
	return n


# =============================================================================
#  МАТЕРИАЛЫ
# =============================================================================

func _prepare_materials() -> void:
	# Промышленный металл — трипланарно (у kit-модулей нет UV).
	_mats["metal"] = _tri(TEX2 + "metal_wall.png", Color(0.78, 0.80, 0.77), 0.42, 0.88, 0.35)
	_mats["metal_dark"] = _tri(TEX2 + "metal_wall.png", Color(0.42, 0.44, 0.45), 0.50, 0.92, 0.30)
	_mats["paint"] = _tri(TEX2 + "metal_wall_clean.png", Color(0.58, 0.59, 0.56), 0.50, 0.82, 0.20)
	_mats["rust"] = _tri(TEX2 + "metal_wall.png", Color(0.44, 0.26, 0.17), 0.55, 0.95, 0.15)
	_mats["floor_plate"] = _tri(TEX2 + "floor_plate.png", Color(0.66, 0.68, 0.70), 0.55, 0.90, 0.42)
	_mats["floor_grate"] = _tri(TEX2 + "floor_grate.png", Color(0.62, 0.64, 0.66), 0.60, 0.92, 0.35)
	_mats["hazard"] = _tri(TEX + "hazard_stripes.png", Color(0.95, 0.90, 0.80), 1.10, 0.80, 0.15)
	_mats["hazard_uv"] = _uv(TEX2 + "hazard_hand.png", Color(0.95, 0.90, 0.78), 1.0, 0.80, 0.15)
	_mats["wet"] = _plain(Color(0.20, 0.24, 0.27), 0.14, 0.35)

	# Эмиссивные материалы (Light3D в сцене нет — только это).
	_mats["lamp_cold"] = _emit(Color(0.62, 0.76, 1.0), 3.4, Color(0.30, 0.42, 0.58))
	_mats["lamp_green"] = _emit(Color(0.42, 1.0, 0.58), 2.6, Color(0.07, 0.20, 0.10))
	_mats["lamp_red"] = _emit(Color(1.0, 0.12, 0.06), 4.6, Color(0.24, 0.03, 0.02))
	_mats["lamp_amber"] = _emit(Color(1.0, 0.64, 0.26), 2.4, Color(0.30, 0.16, 0.05))

	# Своя геометрия: светящиеся полосы/лампы — unshaded (в GL Compatibility
	# bloom нет, поэтому яркий albedo читается как «горит»).
	_mats["strip_cold"] = _unshaded(Color(0.78, 0.87, 0.98), true)
	_mats["strip_amber"] = _unshaded(Color(0.92, 0.62, 0.28), true)
	_mats["strip_red"] = _unshaded(Color(0.95, 0.22, 0.14), true)
	_mats["strip_green"] = _unshaded(Color(0.42, 0.90, 0.55), true)

	# Дальний фон: силуэты не должны съедаться туманом катсцены.
	_mats["bg_dark"] = _tri(TEX2 + "metal_wall.png", Color(0.46, 0.48, 0.50), 0.35, 0.92, 0.30, true)
	_mats["bg_metal"] = _tri(TEX2 + "metal_wall_clean.png", Color(0.36, 0.38, 0.40), 0.35, 0.90, 0.25, true)
	_mats["bg_lamp_cold"] = _unshaded(Color(0.70, 0.82, 0.96), false)
	_mats["bg_lamp_red"] = _unshaded(Color(0.95, 0.18, 0.10), false)


func _tri(path: String, color: Color, uv_scale: float, rough: float, metal: float,
		no_fog: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := load(path) as Texture2D
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.disable_fog = no_fog
	return m


func _uv(path: String, color: Color, uv_scale: float, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := load(path) as Texture2D
	if tex != null:
		m.albedo_texture = tex
		m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _plain(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _emit(color: Color, energy: float, albedo: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.55
	return m


func _unshaded(color: Color, keep_fog: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.roughness = 1.0
	m.disable_fog = not keep_fog
	return m


func _mat(key: String) -> Material:
	if not _mats.has(key):
		push_warning("LaunchDock: нет материала '%s'" % key)
		return _mats["metal"]
	return _mats[key]


# =============================================================================
#  БАТЧИ ПРИМИТИВОВ (MultiMesh: сотни коробок = единицы draw call'ов)
# =============================================================================

func _ensure_primitives() -> void:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
		_unit_box.size = Vector3.ONE
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 0.5
		_unit_sphere.height = 1.0
		_unit_sphere.radial_segments = 10
		_unit_sphere.rings = 5


func _push(dict: Dictionary, mat_key: String, xf: Transform3D) -> void:
	if not dict.has(mat_key):
		dict[mat_key] = []
	(dict[mat_key] as Array).append(xf)


# --- глобальные (статичные) примитивы ---------------------------------------

func _gxf(mat_key: String, xf: Transform3D) -> void:
	_push(_gb, mat_key, xf)


func _gbox(mat_key: String, center: Vector3, size: Vector3, rot_deg := Vector3.ZERO) -> void:
	var basis := Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(size)
	_push(_gb, mat_key, Transform3D(basis, center))


func _gbeam(mat_key: String, a: Vector3, b: Vector3, thick: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var dir := d / length
	var basis := Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(thick, length, thick))
	_push(_gb, mat_key, Transform3D(basis, (a + b) * 0.5))


func _gsphere(mat_key: String, center: Vector3, diameter: float) -> void:
	_push(_gs, mat_key, Transform3D(Basis.from_scale(Vector3.ONE * diameter), center))


# --- локальные примитивы (внутри вращаемого узла зажима) ---------------------

func _cbox(mat_key: String, center: Vector3, size: Vector3, rot_deg := Vector3.ZERO) -> void:
	var basis := Basis.from_euler(rot_deg * (PI / 180.0)) * Basis.from_scale(size)
	_push(_lb, mat_key, Transform3D(basis, center))


func _cbeam(mat_key: String, a: Vector3, b: Vector3, thick: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var dir := d / length
	var basis := Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(thick, length, thick))
	_push(_lb, mat_key, Transform3D(basis, (a + b) * 0.5))


func _csphere(mat_key: String, center: Vector3, diameter: float) -> void:
	_push(_ls, mat_key, Transform3D(Basis.from_scale(Vector3.ONE * diameter), center))


# --- создание MultiMeshInstance3D -------------------------------------------

func _make_multimesh(parent: Node3D, node_name: String, mesh: Mesh,
		xforms: Array, material_override: Material = null,
		cast_shadow := true) -> MultiMeshInstance3D:
	if xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	if material_override != null:
		mmi.material_override = material_override
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


func _flush_boxes(parent: Node3D, dict: Dictionary, prefix: String) -> void:
	_ensure_primitives()
	for mat_key in dict.keys():
		var list: Array = dict[mat_key]
		if list.is_empty():
			continue
		var key := String(mat_key)
		var no_shadow := key.begins_with("strip") or key.begins_with("lamp") \
				or key.begins_with("bg")
		_make_multimesh(parent, "%s_%s" % [prefix, mat_key], _unit_box, list,
				_mat(key), not no_shadow)
	dict.clear()


func _flush_spheres(parent: Node3D, dict: Dictionary, prefix: String) -> void:
	_ensure_primitives()
	for mat_key in dict.keys():
		var list: Array = dict[mat_key]
		if list.is_empty():
			continue
		var key := String(mat_key)
		var no_shadow := key.begins_with("strip") or key.begins_with("lamp")
		_make_multimesh(parent, "%s_%s" % [prefix, mat_key], _unit_sphere, list,
				_mat(key), not no_shadow)
	dict.clear()


func _flush_global_batches() -> void:
	var structure := _group("Structure")
	_flush_boxes(structure, _gb, "Boxes")
	_flush_spheres(structure, _gs, "Spheres")


# --- kit-модули как MultiMesh ------------------------------------------------

func _load_glb_mesh(path: String) -> Mesh:
	if _mesh_cache.has(path):
		return _mesh_cache[path] as Mesh
	var ps := load(path) as PackedScene
	if ps == null:
		push_error("LaunchDock: не загрузился " + path)
		return null
	var inst := ps.instantiate()
	var mesh := _find_mesh(inst)
	inst.free()
	if mesh == null:
		push_error("LaunchDock: нет меша в " + path)
		return null
	_mesh_cache[path] = mesh
	return mesh


func _find_mesh(node: Node) -> Mesh:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		return mi.mesh
	for c in node.get_children():
		var m := _find_mesh(c)
		if m != null:
			return m
	return null


func _kit_multi(parent: Node3D, node_name: String, path: String,
		xforms: Array, mat_map: Dictionary, cast_shadow := true) -> void:
	if xforms.is_empty():
		return
	var src := _load_glb_mesh(path)
	if src == null:
		return
	var mesh := src.duplicate() as ArrayMesh
	if mesh == null:
		mesh = src as ArrayMesh
	if mesh == null:
		push_error("LaunchDock: меш не ArrayMesh: " + path)
		return
	for i in mesh.get_surface_count():
		var sm := mesh.surface_get_material(i) as BaseMaterial3D
		var key := String(sm.resource_name) if sm != null else ""
		if mat_map.has(key):
			mesh.surface_set_material(i, _mat(String(mat_map[key])))
		elif sm != null:
			push_warning("LaunchDock: не замаплен слот '%s' в %s" % [key, path])
	_make_multimesh(parent, node_name, mesh, xforms, null, cast_shadow)


func _aim_xf(pos: Vector3, target: Vector3) -> Transform3D:
	# -Z смотрит в цель (так же, как у Light3D/Camera3D).
	return Transform3D(Basis(), pos).looking_at(target, Vector3.UP)


func _rx(deg: float) -> float:
	return deg * (PI / 180.0)


# =============================================================================
#  НАСТИЛ
# =============================================================================

func _build_deck() -> void:
	var deck := _group("Deck")
	var regular: Array = []
	var wet: Array = []
	for ix in range(-11, 11):
		for iz in range(-10, 10):
			var x := ix * TILE + 1.0
			var z := iz * TILE + 1.0
			var rot := 0.0
			if ((ix * 7 + iz * 3 + 5) % 4) == 0:
				rot = PI * 0.5
			var xf := Transform3D(Basis(Vector3.UP, rot), Vector3(x, DECK_TOP_Y - TILE_TOP, z))
			if posmod(ix * 73 + iz * 37 + 11, 41) < 2:
				wet.append(xf)
			else:
				regular.append(xf)
	_kit_multi(deck, "DeckTiles", ARCH + "floor_tile.glb", regular, FLOOR_MAP, false)
	_kit_multi(deck, "DeckTilesWet", ARCH + "floor_tile_wet.glb", wet, WET_FLOOR_MAP, false)


func _build_deck_understructure() -> void:
	# Корпус платформы: сверху плитки, под ними толстая плита + рёбра.
	_gbox("metal_dark", Vector3(0, -0.64, 0), Vector3(44.0, 1.0, 40.0))
	# кромочные балки
	_gbox("metal", Vector3(0, -0.55, -20.05), Vector3(44.3, 1.35, 0.7))
	_gbox("metal", Vector3(0, -0.55, 20.05), Vector3(44.3, 1.35, 0.7))
	_gbox("metal", Vector3(-22.05, -0.55, 0), Vector3(0.7, 1.35, 40.3))
	_gbox("metal", Vector3(22.05, -0.55, 0), Vector3(0.7, 1.35, 40.3))
	# ферменные рёбра под настилом
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		_gbox("metal_dark", Vector3(x, -0.85, 0), Vector3(0.42, 0.95, 40.0))
	for z in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		_gbox("metal_dark", Vector3(0, -1.0, z), Vector3(44.0, 0.8, 0.5))
	# опорные пилоны, уходящие вниз в темноту
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var px := 19.0 * sx
			var pz := 17.0 * sz
			_gbox("metal_dark", Vector3(px, -21.0, pz), Vector3(2.4, 40.0, 2.4))
			_gbox("metal", Vector3(px, -1.35, pz), Vector3(3.2, 0.6, 3.2))
			_gbeam("metal_dark", Vector3(px, -10.0, pz), Vector3(0, -10.0, pz * 0.35), 0.34)
			_gbeam("metal_dark", Vector3(px, -22.0, pz), Vector3(0, -22.0, pz * 0.35), 0.34)
	# горизонтальные распорки между пилонами
	_gbox("metal_dark", Vector3(0, -10.0, -17.0), Vector3(38.0, 0.4, 0.4))
	_gbox("metal_dark", Vector3(0, -10.0, 17.0), Vector3(38.0, 0.4, 0.4))
	_gbox("metal_dark", Vector3(0, -22.0, -17.0), Vector3(38.0, 0.4, 0.4))
	_gbox("metal_dark", Vector3(0, -22.0, 17.0), Vector3(38.0, 0.4, 0.4))
	# причальные тумбы-направляющие по коротким торцам
	for sx: float in [-1.0, 1.0]:
		_gbox("metal", Vector3(15.5 * sx, 0.15, 0), Vector3(0.5, 0.3, 6.0))
		_gbox("strip_amber", Vector3(15.5 * sx, 0.31, 0), Vector3(0.16, 0.03, 5.8))


# =============================================================================
#  HAZARD-ТРИМ, ЯНТАРНЫЕ ЛАМПЫ, ХОЛОДНЫЕ ПОЛОСЫ
# =============================================================================

func _build_edge_trim_and_lamps() -> void:
	var deck := _group("Deck")
	var trims: Array = []
	var trims_outer: Array = []
	# --- hazard-контур «посадочного пятака» (чуть шире свободной зоны) ---
	for z in range(-16, 18, 2):
		trims.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-14.8, 0.02, z)))
		trims.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(14.8, 0.02, z)))
	for x in range(-16, 18, 2):
		trims.append(Transform3D(Basis(), Vector3(x, 0.02, -16.8)))
		trims.append(Transform3D(Basis(), Vector3(x, 0.02, 16.8)))
	# --- внешний периметр платформы ---
	for z in range(-18, 20, 2):
		trims_outer.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-21.4, 0.02, z)))
		trims_outer.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(21.4, 0.02, z)))
	for x in range(-20, 22, 2):
		trims_outer.append(Transform3D(Basis(), Vector3(x, 0.02, -19.4)))
		trims_outer.append(Transform3D(Basis(), Vector3(x, 0.02, 19.4)))
	trims.append_array(trims_outer)
	_kit_multi(deck, "HazardTrim", ARCH + "trim_hazard.glb", trims, KIT_MAP, false)

	# --- янтарные лампы (тёплые точки по краю): корпус + светящийся купол ---
	var lamp_pts: Array = []
	for z in [-15.0, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0]:
		lamp_pts.append(Vector3(-15.35, 0, z))
		lamp_pts.append(Vector3(15.35, 0, z))
	for x in [-15.0, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0]:
		lamp_pts.append(Vector3(x, 0, -17.35))
		lamp_pts.append(Vector3(x, 0, 17.35))
	for z in [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0]:
		lamp_pts.append(Vector3(-21.0, 0, z))
		lamp_pts.append(Vector3(21.0, 0, z))
	for x in [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0]:
		lamp_pts.append(Vector3(x, 0, -19.0))
		lamp_pts.append(Vector3(x, 0, 19.0))
	for p in lamp_pts:
		var pv: Vector3 = p
		_gbox("metal_dark", pv + Vector3(0, 0.09, 0), Vector3(0.30, 0.18, 0.30))
		_gsphere("lamp_amber", pv + Vector3(0, 0.24, 0), 0.28)

	# --- холодные рабочие полосы на апроне ---
	for z in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		_gbox("strip_cold", Vector3(-18.6, 0.04, z), Vector3(0.34, 0.05, 2.6))
		_gbox("strip_cold", Vector3(18.6, 0.04, z), Vector3(0.34, 0.05, 2.6))
	for x in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		_gbox("strip_cold", Vector3(x, 0.04, -17.0), Vector3(2.6, 0.05, 0.34))
		_gbox("strip_cold", Vector3(x, 0.04, 17.0), Vector3(2.6, 0.05, 0.34))


# =============================================================================
#  СТАТИЧНЫЕ ОСНОВАНИЯ ЗАЖИМОВ (пилоны на апроне, вне свободной зоны)
# =============================================================================

func _build_clamp_pedestals() -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var px := 16.4 * sx
			var pz := CLAMP_Z * sz
			# фундамент
			_gbox("metal_dark", Vector3(px, 0.25, pz), Vector3(2.9, 0.5, 2.7))
			_gbox("metal", Vector3(px, 0.52, pz), Vector3(2.5, 0.14, 2.3))
			# hazard-пояс фундамента
			_gbox("hazard_uv", Vector3(px, 0.55, pz - 1.32), Vector3(2.72, 0.20, 0.10))
			_gbox("hazard_uv", Vector3(px, 0.55, pz + 1.32), Vector3(2.72, 0.20, 0.10))
			_gbox("hazard_uv", Vector3(px - 1.42, 0.55, pz), Vector3(0.10, 0.20, 2.52))
			_gbox("hazard_uv", Vector3(px + 1.42, 0.55, pz), Vector3(0.10, 0.20, 2.52))
			# колонна и привод
			_gbox("metal", Vector3(px, 2.1, pz), Vector3(0.9, 3.3, 0.9))
			_gbox("metal_dark", Vector3(px, 3.95, pz), Vector3(1.5, 0.7, 1.55))
			_gbox("metal_dark", Vector3(px, 5.0, pz), Vector3(1.15, 1.25, 1.2))
			_gbox("metal", Vector3(px - 0.35 * sx, 5.0, pz), Vector3(0.6, 0.85, 0.9))
			# кронштейн шарнира к пивоту зажима
			_gbox("metal", Vector3(15.62 * sx, CLAMP_Y, pz), Vector3(0.95, 0.95, 1.0))
			_gbeam("metal_dark", Vector3(px, 3.85, pz), Vector3(15.65 * sx, CLAMP_Y + 0.15, pz), 0.30)
			_gbeam("metal_dark", Vector3(px, 0.6, pz), Vector3(15.5 * sx, 3.55, pz), 0.22)
			_gbeam("metal_dark", Vector3(px, 2.0, pz - 1.0), Vector3(px, 3.9, pz), 0.18)
			_gbeam("metal_dark", Vector3(px, 2.0, pz + 1.0), Vector3(px, 3.9, pz), 0.18)
			# маячок и патрубок на приводе
			_gsphere("strip_red", Vector3(px, 5.85, pz), 0.30)
			_gbox("strip_cold", Vector3(15.62 * sx, CLAMP_Y - 0.52, pz), Vector3(0.7, 0.05, 0.7))


# =============================================================================
#  ЗАЖИМЫ (анимируемые узлы)
# =============================================================================

func _build_clamps() -> void:
	var defs := [
		{"name": "Clamp_NW", "sx": -1.0, "sz": -1.0},
		{"name": "Clamp_NE", "sx": 1.0, "sz": -1.0},
		{"name": "Clamp_SW", "sx": -1.0, "sz": 1.0},
		{"name": "Clamp_SE", "sx": 1.0, "sz": 1.0},
	]
	for d in defs:
		var node := Node3D.new()
		node.name = String(d["name"])
		var sx := float(d["sx"])
		var sz := float(d["sz"])
		node.position = Vector3(CLAMP_X * sx, CLAMP_Y, CLAMP_Z * sz)
		node.rotation = Vector3(0.0, 0.0 if sx > 0.0 else PI, 0.0)
		# Узлы зажимов — прямые дети корня LaunchDock (путь для Анимации Лида:
		# "Clamp_NW:rotation" и т.п.).
		add_child(node)
		_build_one_clamp(node)
		_flush_boxes(node, _lb, "ClampBoxes")
		_flush_spheres(node, _ls, "ClampLamps")
		# kit-детали на лапе (имена с префиксом Clamp_ — это анимируемый узел)
		_kit_multi(node, "Clamp_ArmPipe", ARCH + "pipe_run.glb",
				[Transform3D(Basis(), Vector3(-2.4, 0.5, -0.2))], KIT_MAP, false)
		_kit_multi(node, "Clamp_ArmCables", ARCH + "cable_bundle.glb",
				[Transform3D(Basis(), Vector3(-2.2, -0.34, 0.18))], KIT_MAP, false)
		_clamp_info.append({
			"name": String(d["name"]),
			"pos": node.position,
			"rot_y": node.rotation.y,
			"reach": CLAMP_X - 6.3,
		})


func _build_one_clamp(node: Node3D) -> void:
	# --- шарнир у основания ---
	_cbox("metal", Vector3(0.10, 0.0, 0.0), Vector3(0.85, 0.95, 1.05))
	_cbox("metal_dark", Vector3(0.10, 0.0, 0.0), Vector3(0.95, 0.35, 0.55))
	_cbox("metal_dark", Vector3(0.10, 0.0, -0.55), Vector3(0.45, 0.45, 0.22))
	_cbox("metal_dark", Vector3(0.10, 0.0, 0.55), Vector3(0.45, 0.45, 0.22))
	# --- лапа ---
	_cbox("metal", Vector3(-2.85, 0.0, 0.0), Vector3(5.6, 0.42, 0.55))
	_cbox("metal_dark", Vector3(-2.4, 0.34, 0.0), Vector3(4.4, 0.16, 0.72))
	_cbox("metal_dark", Vector3(-2.4, -0.30, 0.0), Vector3(4.0, 0.12, 0.42))
	# гидравлика сверху
	_cbox("metal_dark", Vector3(-2.2, 0.52, 0.0), Vector3(2.2, 0.18, 0.32))
	_cbox("metal", Vector3(-2.2, 0.66, 0.0), Vector3(0.9, 0.20, 0.26))
	# hazard-полосы на лапе
	_cbox("hazard_uv", Vector3(-3.3, 0.235, 0.0), Vector3(2.9, 0.05, 0.58))
	_cbox("hazard_uv", Vector3(-3.3, -0.235, 0.0), Vector3(2.9, 0.05, 0.58))
	# холодная рабочая полоса вдоль борта лапы (читается издалека)
	_cbox("strip_cold", Vector3(-2.9, 0.04, 0.29), Vector3(4.2, 0.06, 0.04))
	_cbox("strip_cold", Vector3(-2.9, 0.04, -0.29), Vector3(4.2, 0.06, 0.04))
	# --- запястье и клешня ---
	_cbox("metal_dark", Vector3(-5.55, 0.0, 0.0), Vector3(0.95, 0.75, 0.9))
	_cbox("metal", Vector3(-5.7, 0.62, 0.0), Vector3(1.3, 0.28, 0.78), Vector3(0, 0, -8))
	_cbox("metal", Vector3(-5.7, -0.62, 0.0), Vector3(1.3, 0.28, 0.78), Vector3(0, 0, 8))
	# контактные светящиеся подушки (янтарные — «захват активен»)
	_cbox("strip_amber", Vector3(-5.55, 0.45, 0.0), Vector3(0.55, 0.06, 0.6))
	_cbox("strip_amber", Vector3(-5.55, -0.45, 0.0), Vector3(0.55, 0.06, 0.6))
	# красный маячок на запястье
	_csphere("strip_red", Vector3(-5.55, 0.95, 0.0), 0.34)
	# кабельный хомут / крепёж
	_cbox("metal_dark", Vector3(-4.4, 0.0, 0.0), Vector3(0.22, 0.62, 0.66))
	_cbox("metal_dark", Vector3(-1.3, 0.0, 0.0), Vector3(0.22, 0.62, 0.66))


# =============================================================================
#  ВЫШКИ
# =============================================================================

func _build_towers() -> void:
	var towers := _group("Towers")
	var panels_a: Array = []
	var panels_b: Array = []
	var pipes: Array = []
	var cables: Array = []
	var red_fixtures: Array = []
	var doors: Array = []
	var levels := [0.6, 4.35, 8.1, 11.85, 15.6, 19.35, 22.2]

	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var cx := TOWER_X * sx
			var cz := TOWER_Z * sz
			# --- ноги ---
			for lx: float in [-1.0, 1.0]:
				for lz: float in [-1.0, 1.0]:
					_gbox("metal_dark", Vector3(cx + lx * 1.5, TOWER_H * 0.5, cz + lz * 1.5),
							Vector3(0.46, TOWER_H, 0.46))
			# --- пояса-рамы ---
			for y in levels:
				_gbox("metal", Vector3(cx, y, cz - 1.5), Vector3(3.46, 0.24, 0.24))
				_gbox("metal", Vector3(cx, y, cz + 1.5), Vector3(3.46, 0.24, 0.24))
				_gbox("metal", Vector3(cx - 1.5, y, cz), Vector3(0.24, 0.24, 3.46))
				_gbox("metal", Vector3(cx + 1.5, y, cz), Vector3(0.24, 0.24, 3.46))
			# --- диагонали фермы ---
			for i in range(levels.size() - 1):
				var y0: float = levels[i]
				var y1: float = levels[i + 1]
				var dir := 1.0 if i % 2 == 0 else -1.0
				_gbeam("metal_dark", Vector3(cx - 1.5 * dir, y0 + 0.15, cz - 1.5),
						Vector3(cx + 1.5 * dir, y1 - 0.15, cz - 1.5), 0.13)
				_gbeam("metal_dark", Vector3(cx - 1.5 * dir, y0 + 0.15, cz + 1.5),
						Vector3(cx + 1.5 * dir, y1 - 0.15, cz + 1.5), 0.13)
				_gbeam("metal_dark", Vector3(cx - 1.5, y0 + 0.15, cz - 1.5 * dir),
						Vector3(cx - 1.5, y1 - 0.15, cz + 1.5 * dir), 0.13)
				_gbeam("metal_dark", Vector3(cx + 1.5, y0 + 0.15, cz - 1.5 * dir),
						Vector3(cx + 1.5, y1 - 0.15, cz + 1.5 * dir), 0.13)
			# --- обшивка панелями: внутренняя X-грань (2 ряда выше двери),
			#     внутренняя Z-грань (3 ряда), внешняя Z-грань (3 ряда) ---
			var inner_x := cx - sx * 1.73
			var inner_z := cz - sz * 1.73
			var outer_z := cz + sz * 1.73
			for row in 2:
				panels_a.append(Transform3D(Basis(Vector3.UP, -sx * PI * 0.5),
						Vector3(inner_x, 3.9 + row * 2.6, cz)))
			for row in 3:
				panels_b.append(Transform3D(Basis(Vector3.UP, 0.0 if sz < 0.0 else PI),
						Vector3(cx, 1.3 + row * 2.6, inner_z)))
				panels_a.append(Transform3D(Basis(Vector3.UP, PI if sz < 0.0 else 0.0),
						Vector3(cx, 1.3 + row * 2.6, outer_z)))
			# панели кабины-агрегата наверху
			panels_b.append(Transform3D(Basis(Vector3.UP, -sx * PI * 0.5),
					Vector3(inner_x, 23.75, cz)))
			panels_a.append(Transform3D(Basis(Vector3.UP, 0.0 if sz < 0.0 else PI),
					Vector3(cx, 23.75, cz - sz * 1.63)))
			# --- кабина-агрегат наверху ---
			_gbox("metal", Vector3(cx, 23.75, cz), Vector3(3.2, 2.5, 3.2))
			_gbox("metal_dark", Vector3(cx, 25.08, cz), Vector3(3.34, 0.22, 3.34))
			# hazard-пояс по кромке крыши
			_gbox("hazard_uv", Vector3(cx, 25.22, cz - 1.62), Vector3(3.3, 0.16, 0.14))
			_gbox("hazard_uv", Vector3(cx, 25.22, cz + 1.62), Vector3(3.3, 0.16, 0.14))
			_gbox("hazard_uv", Vector3(cx - 1.62, 25.22, cz), Vector3(0.14, 0.16, 3.3))
			_gbox("hazard_uv", Vector3(cx + 1.62, 25.22, cz), Vector3(0.14, 0.16, 3.3))
			# светящиеся щели кабины
			_gbox("strip_cold", Vector3(cx - sx * 1.62, 24.15, cz), Vector3(0.06, 0.14, 2.4))
			_gbox("strip_cold", Vector3(cx - sx * 1.62, 24.62, cz), Vector3(0.06, 0.14, 2.4))
			_gbox("strip_cold", Vector3(cx, 24.35, cz - sz * 1.62), Vector3(1.7, 0.14, 0.06))
			_gbox("strip_cold", Vector3(cx, 24.35, cz + sz * 1.62), Vector3(1.7, 0.14, 0.06))
			# красные маячки на вышке
			_gsphere("strip_red", Vector3(cx, 25.62, cz), 0.52)
			_gbeam("metal_dark", Vector3(cx + 1.2, 25.1, cz + 1.2), Vector3(cx + 1.2, 26.7, cz + 1.2), 0.11)
			_gsphere("strip_red", Vector3(cx + 1.2, 26.78, cz + 1.2), 0.26)
			_gsphere("strip_cold", Vector3(cx - 1.25, 25.45, cz - 1.25), 0.22)
			# hazard-пояс у основания
			_gbox("hazard_uv", Vector3(cx, 1.0, cz - 1.55), Vector3(3.3, 0.20, 0.12))
			_gbox("hazard_uv", Vector3(cx, 1.0, cz + 1.55), Vector3(3.3, 0.20, 0.12))
			_gbox("hazard_uv", Vector3(cx - 1.55, 1.0, cz), Vector3(0.12, 0.20, 3.3))
			_gbox("hazard_uv", Vector3(cx + 1.55, 1.0, cz), Vector3(0.12, 0.20, 3.3))
			# --- прожектор-корпус на верхней внутренней стороне вышки ---
			var fix_pos := Vector3(cx - sx * 2.0, 19.4, cz - sz * 2.0)
			var fix_xf := _aim_xf(fix_pos, Vector3(0, 5.0, 0))
			_gxf("metal_dark", fix_xf * Transform3D(Basis.from_scale(Vector3(1.25, 0.9, 0.85)),
					Vector3(0, 0, 0.15)))
			_gxf("metal", fix_xf * Transform3D(Basis.from_scale(Vector3(0.5, 0.42, 0.5)),
					Vector3(0, 0.66, 0.2)))
			_gxf("strip_cold", fix_xf * Transform3D(Basis.from_scale(Vector3(0.92, 0.58, 0.08)),
					Vector3(0, 0, -0.36)))
			# --- вертикальные трубы и кабели на «голой» внешней X-грани ---
			for k in range(9):
				var vy := 2.4 + k * 2.0
				pipes.append(Transform3D(Basis(Vector3.BACK, PI * 0.5),
						Vector3(cx + sx * 1.79, vy, cz + 0.95)))
				pipes.append(Transform3D(Basis(Vector3.BACK, PI * 0.5),
						Vector3(cx + sx * 1.79, vy, cz - 0.95)))
			for k in range(9):
				cables.append(Transform3D(Basis(Vector3.BACK, PI * 0.5),
						Vector3(cx + sx * 1.62, 2.4 + k * 2.0, cz)))
			# --- сервисная дверь в основании (внутренняя X-грань, ниже панелей) ---
			doors.append(Transform3D(Basis(Vector3.UP, -sx * PI * 0.5),
					Vector3(inner_x, 0.0, cz)))
			_gbox("metal_dark", Vector3(inner_x + sx * 0.13, 1.12, cz), Vector3(0.22, 2.2, 1.44))
			_gbox("strip_red", Vector3(inner_x - sx * 0.16, 2.52, cz), Vector3(0.10, 0.12, 0.5))
			# --- красные лампы на вышке (kit lamp_red) ---
			red_fixtures.append(Transform3D(Basis(Vector3.BACK, -sx * PI * 0.5),
					Vector3(inner_x - sx * 0.09, 6.5, cz + 0.9)))
			red_fixtures.append(Transform3D(Basis(Vector3.BACK, -sx * PI * 0.5),
					Vector3(inner_x - sx * 0.09, 12.5, cz - 0.9)))
			red_fixtures.append(Transform3D(Basis(Vector3.BACK, -sx * PI * 0.5),
					Vector3(inner_x - sx * 0.09, 2.75, cz)))

	_kit_multi(towers, "WallPanelsA", ARCH + "wall_panel_a.glb", panels_a, KIT_MAP)
	_kit_multi(towers, "WallPanelsB", ARCH + "wall_panel_b.glb", panels_b, KIT_MAP)
	_kit_multi(towers, "TowerPipes", ARCH + "pipe_run.glb", pipes, KIT_MAP, false)
	_kit_multi(towers, "TowerCables", ARCH + "cable_bundle.glb", cables, KIT_MAP, false)
	_kit_multi(towers, "RedLamps", EQUIP + "lamp_red.glb", red_fixtures, KIT_MAP, false)
	_kit_multi(towers, "ServiceDoors", ARCH + "door_frame.glb", doors, KIT_MAP)


# =============================================================================
#  ВЕРХНИЕ РАМЫ, КАТУШКИ, КРАН-БАЛКИ
# =============================================================================

func _build_top_frames() -> void:
	var frame := _group("TopFrames")
	var cables: Array = []
	var fixtures: Array = []
	var yb := 22.7
	var yt := 23.95

	# --- фермы вдоль X (на северных и южных торцах вышек) ---
	for sz: float in [-1.0, 1.0]:
		var z := TOWER_Z * sz
		_gbox("metal", Vector3(0, yb, z), Vector3(41.4, 0.30, 0.30))
		_gbox("metal", Vector3(0, yt, z), Vector3(41.4, 0.30, 0.30))
		var n := 10
		for i in range(n):
			var x0 := -TOWER_X + i * (2.0 * TOWER_X / n)
			var x1 := x0 + 2.0 * TOWER_X / n
			_gbeam("metal_dark", Vector3(x0, yb, z), Vector3(x1, yt, z), 0.12)
			_gbeam("metal_dark", Vector3(x1, yb, z), Vector3(x0, yt, z), 0.10)
			_gbeam("metal_dark", Vector3(x0, yb, z), Vector3(x0, yt, z), 0.10)
		# катвок с ограждением (между вышками, не заходя в кабины)
		_gbox("metal_dark", Vector3(0, 24.22, z), Vector3(35.0, 0.10, 1.25))
		_gbox("hazard_uv", Vector3(0, 24.28, z - 0.56), Vector3(35.0, 0.03, 0.10))
		_gbox("hazard_uv", Vector3(0, 24.28, z + 0.56), Vector3(35.0, 0.03, 0.10))
		for lz: float in [-1.0, 1.0]:
			_gbox("metal", Vector3(0, 24.85, z + lz * 0.58), Vector3(35.0, 0.06, 0.06))
		for i in range(9):
			var px := -16.0 + i * 4.0
			for lz: float in [-1.0, 1.0]:
				_gbeam("metal_dark", Vector3(px, 24.27, z + lz * 0.58),
						Vector3(px, 24.88, z + lz * 0.58), 0.07)
		# кабели по катвоку
		for i in range(8):
			var cxp := -14.0 + i * 4.0
			cables.append(Transform3D(Basis(), Vector3(cxp, 24.30, z - 0.30)))
		# светильники под нижним поясом
		for i in range(9):
			var fxp := -16.0 + i * 4.0
			fixtures.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(fxp, 22.52, z)))

	# --- фермы вдоль Z (на западных и восточных торцах вышек) ---
	for sx: float in [-1.0, 1.0]:
		var x := TOWER_X * sx
		_gbox("metal", Vector3(x, yb, 0), Vector3(0.30, 0.30, 37.4))
		_gbox("metal", Vector3(x, yt, 0), Vector3(0.30, 0.30, 37.4))
		var n := 9
		for i in range(n):
			var z0 := -TOWER_Z + i * (2.0 * TOWER_Z / n)
			var z1 := z0 + 2.0 * TOWER_Z / n
			_gbeam("metal_dark", Vector3(x, yb, z0), Vector3(x, yt, z1), 0.12)
			_gbeam("metal_dark", Vector3(x, yb, z1), Vector3(x, yt, z0), 0.10)
			_gbeam("metal_dark", Vector3(x, yb, z0), Vector3(x, yt, z0), 0.10)

	# --- две подвесные кран-балки над кораблём (y > 26 — над свободной зоной) ---
	for sx: float in [-1.0, 1.0]:
		var gx := GANTRY_X * sx
		_gbox("metal", Vector3(gx, GANTRY_Y, 0), Vector3(0.30, 0.30, 37.6))
		_gbox("metal", Vector3(gx, GANTRY_TOP_Y, 0), Vector3(0.30, 0.30, 37.6))
		var n := 9
		for i in range(n):
			var z0 := -TOWER_Z + i * (2.0 * TOWER_Z / n)
			var z1 := z0 + 2.0 * TOWER_Z / n
			_gbeam("metal_dark", Vector3(gx, GANTRY_Y, z0), Vector3(gx, GANTRY_TOP_Y, z1), 0.12)
			_gbeam("metal_dark", Vector3(gx, GANTRY_Y, z1), Vector3(gx, GANTRY_TOP_Y, z0), 0.10)
		# подвесы к торцевым фермам
		for sz: float in [-1.0, 1.0]:
			_gbox("metal_dark", Vector3(gx, 25.55, TOWER_Z * sz), Vector3(0.36, 3.4, 0.36))
			_gbox("metal_dark", Vector3(gx, 23.98, TOWER_Z * sz), Vector3(0.8, 0.3, 0.8))
		# рабочая полоса под балкой (эмиссия)
		_gbox("strip_cold", Vector3(gx, GANTRY_Y - 0.17, 0), Vector3(0.16, 0.08, 37.0))
		# светильники-корпуса под кран-балкой
		for z in [-12.0, -6.0, 0.0, 6.0, 12.0]:
			fixtures.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(gx, GANTRY_Y - 0.28, z)))
		# концевые балки-упоры
		for sz: float in [-1.0, 1.0]:
			_gbox("metal", Vector3(gx, GANTRY_TOP_Y + 0.25, TOWER_Z * sz), Vector3(1.1, 0.5, 1.1))

	_kit_multi(frame, "CatwalkCables", ARCH + "cable_bundle.glb", cables, KIT_MAP, false)
	_kit_multi(frame, "CeilFixtures", ARCH + "ceil_light_fixture.glb", fixtures, KIT_MAP, false)


# =============================================================================
#  ПРОЖЕКТОРЫ И ЯКОРЯ СВЕТА (Marker3D для SpotLight3D Лида)
# =============================================================================

func _build_gantries_and_anchors() -> void:
	var idx := 1
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var pos := Vector3(GANTRY_X * sx, GANTRY_Y - 0.2, CLAMP_Z * sz)
			var aim := Vector3(-2.0 * sx, 6.0, 5.0 * sz)
			var xf := _aim_xf(pos, aim)
			# корпус прожектора (статичная геометрия, висит на кран-балке)
			_gxf("metal_dark", xf * Transform3D(Basis.from_scale(Vector3(1.3, 0.95, 0.85)),
					Vector3(0, 0, 0.15)))
			_gxf("metal", xf * Transform3D(Basis.from_scale(Vector3(0.5, 0.45, 0.5)),
					Vector3(0, 0.72, 0.2)))
			_gxf("strip_cold", xf * Transform3D(Basis.from_scale(Vector3(1.0, 0.62, 0.08)),
					Vector3(0, 0, -0.34)))
			_gxf("metal_dark", xf * Transform3D(Basis.from_scale(Vector3(0.9, 0.12, 0.9)),
					Vector3(0, 0.55, 0.1)))
			# якорь: позиция линзы, -Z смотрит в цель (как у SpotLight3D).
			# Прямой ребёнок корня LaunchDock — get_node("LightAnchor_1").
			var marker := Marker3D.new()
			marker.name = "LightAnchor_%d" % idx
			marker.transform = Transform3D(xf.basis, xf * Vector3(0, 0, -0.42))
			add_child(marker)
			_anchor_info.append({
				"name": marker.name,
				"pos": marker.position,
				"aim": aim,
			})
			idx += 1


# =============================================================================
#  ДЕКОР ПЛОЩАДКИ: КОНСОЛИ, ЯЩИКИ, ТРУБЫ, КАБЕЛИ
# =============================================================================

func _build_ground_dressing() -> void:
	var dress := _group("Dressing")
	# --- пульты у вышках (Console — kit) ---
	_kit_multi(dress, "Console_W", EQUIP + "console_section.glb",
			[Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-17.0, 0.0, -12.5))], KIT_MAP)
	_kit_multi(dress, "Console_E", EQUIP + "console_section.glb",
			[Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(17.0, 0.0, 12.5))], KIT_MAP)
	# пультовые экраны светятся зелёным
	_gbox("strip_green", Vector3(-16.55, 1.05, -12.5), Vector3(0.06, 0.42, 1.1))
	_gbox("strip_green", Vector3(16.55, 1.05, 12.5), Vector3(0.06, 0.42, 1.1))

	# --- ящики (kit crate / crate_small) ---
	var crates: Array = []
	var crates_small: Array = []
	var crate_spots := [
		Vector3(17.9, 0.0, -15.4), Vector3(18.6, 0.0, -14.5), Vector3(-18.2, 0.0, -15.2),
		Vector3(-17.3, 0.0, 15.8), Vector3(18.3, 0.0, 16.2), Vector3(19.6, 0.0, 15.1),
		Vector3(20.0, 0.0, -16.8), Vector3(-19.4, 0.0, 14.6), Vector3(-20.0, 0.0, -14.0),
	]
	var crate_rots := [22.0, -14.0, 47.0, 9.0, 78.0, -31.0, 4.0, 121.0, -63.0]
	for i in crate_spots.size():
		crates.append(Transform3D(Basis(Vector3.UP, _rx(crate_rots[i])), crate_spots[i]))
	var small_spots := [
		Vector3(17.2, 0.0, -13.9), Vector3(-17.6, 0.0, -14.1), Vector3(16.8, 0.0, 15.0),
		Vector3(-18.6, 0.0, 16.6), Vector3(18.8, 0.0, -16.0), Vector3(19.2, 0.0, 14.3),
	]
	var small_rots := [-12.0, 33.0, 61.0, -44.0, 8.0, 102.0]
	for i in small_spots.size():
		crates_small.append(Transform3D(Basis(Vector3.UP, _rx(small_rots[i])), small_spots[i]))
	_kit_multi(dress, "Crates", EQUIP + "crate.glb", crates, KIT_MAP)
	_kit_multi(dress, "CratesSmall", EQUIP + "crate_small.glb", crates_small, KIT_MAP)

	# --- трубы по внешнему периметру настила ---
	var pipes: Array = []
	for z in range(-18, 20, 2):
		pipes.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-21.5, 0.27, z)))
		pipes.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(21.5, 0.27, z)))
	for x in range(-20, 22, 2):
		pipes.append(Transform3D(Basis(), Vector3(x, 0.27, -19.5)))
		pipes.append(Transform3D(Basis(), Vector3(x, 0.27, 19.5)))
	# трубы под настилом (видны сбоку, реже — экономия полигонов)
	for x in range(-20, 22, 4):
		pipes.append(Transform3D(Basis(), Vector3(x, -0.35, -20.45)))
		pipes.append(Transform3D(Basis(), Vector3(x, -0.35, 20.45)))
	# вертикальные трубы на пилонах зажимов
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for k in range(3):
				pipes.append(Transform3D(Basis(Vector3.BACK, PI * 0.5),
						Vector3(16.4 * sx + 0.62 * sx, 1.6 + k * 2.0,
								CLAMP_Z * sz + 0.55)))
	_kit_multi(dress, "Pipes", ARCH + "pipe_run.glb", pipes, KIT_MAP, false)

	# --- кабельные пучки ---
	var cables: Array = []
	for z in range(-18, 20, 6):
		cables.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-22.15, -0.55, z)))
		cables.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(22.15, -0.55, z)))
	_kit_multi(dress, "Cables", ARCH + "cable_bundle.glb", cables, KIT_MAP, false)

	# --- кабельные лотки между пультами и вышками ---
	for sx: float in [-1.0, 1.0]:
		_gbox("metal_dark", Vector3(17.6 * sx, 0.30, -12.5), Vector3(1.1, 0.06, 0.7))
		_gbox("metal_dark", Vector3(17.6 * sx, 0.30, 12.5), Vector3(1.1, 0.06, 0.7))


# =============================================================================
#  ДАЛЬНИЙ ФОН: СИЛУЭТЫ СТАНЦИИ (100-250 м)
# =============================================================================

func _build_background() -> void:
	var bg := _group("Background")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1997

	# --- гигантское разорванное кольцо станции (R = 170 м, наклон 22°) ---
	var radius := 170.0
	var tilt := _rx(22.0)
	var u := Vector3(1, 0, 0)
	var v := Vector3(0, sin(tilt), -cos(tilt)).normalized()
	var normal := u.cross(v).normalized()
	var n_seg := 48
	var ring_center := Vector3(0, 18, 0)
	for i in range(n_seg):
		if i % 3 == 1 or i % 11 == 5:
			continue
		var th := TAU * i / n_seg
		var c := ring_center + (u * cos(th) + v * sin(th)) * radius
		var tang := (-u * sin(th) + v * cos(th)).normalized()
		var radial := tang.cross(normal).normalized()
		var basis := Basis(tang, normal, tang.cross(normal).normalized())
		# сегмент кольца: длинный по касательной
		_gxf("bg_dark", Transform3D(basis, c)
				* Transform3D(Basis.from_scale(Vector3(21.5, 2.4, 3.2)), Vector3.ZERO))
		# внешняя обшивка/надстройка на каждом третьем сегменте
		if i % 3 == 0:
			_gxf("bg_metal", Transform3D(basis, c + normal * 1.6)
					* Transform3D(Basis.from_scale(Vector3(12.0, 4.0, 2.2)), Vector3.ZERO))
		# редкие огни на внутренней кромке
		var light_pos: Vector3 = c - radial * 1.9
		_gxf("bg_lamp_cold", Transform3D(Basis.from_scale(Vector3(0.9, 0.5, 0.5)),
				light_pos + tang * 2.0))
		if i % 5 == 0:
			_gxf("bg_lamp_red", Transform3D(Basis.from_scale(Vector3(0.7, 0.7, 0.7)),
					light_pos - tang * 3.0))
	# спицы кольца к центру (начинаем с R=95 — чтобы не залезать в кадры
	# камер катсцены, которые стоят в 35-60 м от центра площадки)
	for a in [0.0, 60.0, 120.0, 180.0, 240.0, 300.0]:
		var th := _rx(a)
		var dir := (u * cos(th) + v * sin(th)).normalized()
		_gbeam("bg_dark", ring_center + dir * 95.0, ring_center + dir * 166.0, 1.4)
		_gbeam("bg_dark", ring_center + dir * 100.0 + normal * 6.0,
				ring_center + dir * 150.0 + normal * 6.0, 0.8)
		_gbeam("bg_dark", ring_center + dir * 95.0 + normal * 6.0,
				ring_center + dir * 97.0, 0.7)

	# --- станционное ядро в -Z (нос корабля смотрит туда) ---
	var core := Vector3(0, 56, -238)
	_gbox("bg_dark", core, Vector3(76, 32, 30))
	_gbox("bg_metal", core + Vector3(0, 20, 6), Vector3(56, 12, 18))
	_gbox("bg_metal", core + Vector3(-30, -14, 0), Vector3(20, 20, 22))
	_gbox("bg_metal", core + Vector3(34, -10, -2), Vector3(16, 16, 18))
	_gbox("bg_dark", core + Vector3(0, -22, -4), Vector3(30, 12, 14))
	for i in range(6):
		_gbox("bg_metal", core + Vector3(-24 + i * 9.5, 12, 17), Vector3(3.2, 6.0, 4.0))
	for i in range(8):
		_gbox("bg_lamp_cold", core + Vector3(-30 + i * 8.5, 4, 16.0),
				Vector3(1.1, 2.4, 0.4))
	# ферменные стрелы от ядра
	_gbeam("bg_dark", core + Vector3(0, 10, 14), Vector3(-150, 20, -60), 2.0)
	_gbeam("bg_dark", core + Vector3(0, 6, 14), Vector3(152, 0, -40), 2.0)
	_gbeam("bg_dark", core + Vector3(0, 18, 16), Vector3(10, 120, -120), 1.6)

	# --- стыковочные стрелы станции сбоку (перекликаются с зажимами дока) ---
	for side: float in [-1.0, 1.0]:
		var arm_base := Vector3(178.0 * side, 16.0, -64.0 * side)
		var arm_tip := Vector3(100.0 * side, 5.0, 27.0 * side)
		var dir := (arm_tip - arm_base).normalized()
		_gbeam("bg_dark", arm_base, arm_tip, 2.4)
		_gbeam("bg_dark", arm_base + Vector3(0, 9, 0), arm_tip + Vector3(0, 9, 0), 1.6)
		# поперечные рёбра
		for i in range(6):
			var p := arm_base.lerp(arm_tip, i / 6.0)
			_gbeam("bg_dark", p + Vector3(0, 4.5, 0), p + Vector3(0, 4.5, 0) + dir * 9.0, 0.7)
		# стыковочное «гнездо» на конце стрелы
		_gbox("bg_dark", arm_tip, Vector3(14, 14, 9))
		_gbox("bg_metal", arm_tip + Vector3(0, 0, 5), Vector3(9, 9, 4))
		for k in range(4):
			_gbox("bg_lamp_red", arm_tip + Vector3(-5 + k * 3.4, 5.2, 4.8),
					Vector3(1.1, 1.1, 0.5))
		_gbox("bg_lamp_cold", arm_tip + Vector3(0, 0, 7.2), Vector3(4.0, 4.0, 0.4))
		# опорная ферма стрелы к кольцу
		var ring_join: Vector3 = ring_center + u * (145.0 * side)
		_gbeam("bg_dark", arm_base, ring_join, 1.2)
		_gbox("bg_dark", ring_join, Vector3(8.0, 8.0, 8.0))

	# --- обломки/дрейфующий мусор вокруг дока (дальний фон, 150-230 м) ---
	for i in range(11):
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(150.0, 230.0)
		var pos := Vector3(cos(ang) * dist, rng.randf_range(-40.0, 80.0),
				sin(ang) * dist * 0.9)
		var rot := Vector3(rng.randf_range(0.0, 360.0), rng.randf_range(0.0, 360.0),
				rng.randf_range(0.0, 360.0))
		var size := Vector3(rng.randf_range(4.0, 14.0), rng.randf_range(2.5, 9.0),
				rng.randf_range(4.0, 12.0))
		var basis := Basis.from_euler(rot * (PI / 180.0)) * Basis.from_scale(size)
		_gxf("bg_dark", Transform3D(basis, pos))

	# --- редкие огни на горизонте ---
	for i in range(14):
		var ang := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(120.0, 230.0)
		var pos := Vector3(cos(ang) * dist, rng.randf_range(-20.0, 70.0), sin(ang) * dist)
		var sz := rng.randf_range(1.0, 2.6)
		_gxf("bg_lamp_cold", Transform3D(Basis.from_scale(Vector3(sz, sz, sz)), pos))


# =============================================================================
#  ОТЧЁТ / ВАЛИДАЦИЯ
# =============================================================================

func _report(build_ms: int) -> void:
	_ensure_primitives()
	var stats := _count_stats()
	print("[LaunchDock] сборка: %d мс" % build_ms)
	print("[LaunchDock] узлов=%d, меш-батчей=%d, инстансов в батчах=%d, ~трис=%d"
			% [stats.nodes, stats.meshes, stats.instances, stats.tris])
	print("[LaunchDock] настил %.0f x %.0f м; вышки h=%.1f м; кран-балки y=%.1f"
			% [DECK_HALF_X * 2.0, DECK_HALF_Z * 2.0, TOWER_H, GANTRY_Y])
	for info in _clamp_info:
		print("[LaunchDock] %s: pos=(%.1f, %.1f, %.1f) rot_y=%.2f, лапа до x=%.1f"
				% [String(info["name"]), info["pos"].x, info["pos"].y, info["pos"].z,
				info["rot_y"], info["reach"]])
	for info in _anchor_info:
		print("[LaunchDock] %s: pos=(%.1f, %.1f, %.1f) -> смотрит в (%.1f, %.1f, %.1f)"
				% [String(info["name"]), info["pos"].x, info["pos"].y, info["pos"].z,
				info["aim"].x, info["aim"].y, info["aim"].z])
	# проверка свободной зоны (AABB MultiMesh читаются только с реальным
	# рендерером; в --headless RenderingServer dummy и трансформы не видны)
	if DisplayServer.get_name() == "headless":
		print("[LaunchDock] проверка свободной зоны пропущена (headless-рендерер)")
	else:
		_check_free_zone(FREE_MIN, FREE_MAX)
	# проверка «нет Light3D»
	var lights := _count_lights()
	if lights == 0:
		print("[LaunchDock] Light3D в сцене: 0 (только эмиссии)")
	else:
		push_warning("LaunchDock: в сцене %d Light3D — так быть не должно!" % lights)


func _check_free_zone(free_min: Vector3, free_max: Vector3) -> void:
	var zone := AABB(free_min + Vector3(0, 0.05, 0),
			free_max - free_min - Vector3(0, 0.05, 0))
	var outside := {}       # имя батча -> [кол-во, пример AABB]
	var clamp_hits := {}    # имя батча -> [кол-во, объединённый AABB]
	for entry in _world_aabbs():
		var n: String = entry[0]
		var box: AABB = entry[1]
		if not zone.intersects(box):
			continue
		if _has_ancestor_named(n, "Clamp"):
			if not clamp_hits.has(n):
				clamp_hits[n] = [0, box]
			clamp_hits[n][0] += 1
			clamp_hits[n][1] = (clamp_hits[n][1] as AABB).merge(box)
		else:
			if not outside.has(n):
				outside[n] = [0, box]
			outside[n][0] += 1
			outside[n][1] = (outside[n][1] as AABB).merge(box)
	if outside.is_empty():
		print("[LaunchDock] свободная зона x[-14..14] z[-16..16] y[0..26]: чисто")
	else:
		for n in outside.keys():
			var data: Array = outside[n]
			push_warning("LaunchDock: статика в свободной зоне: %s x%d %s"
					% [n, data[0], data[1]])
	if not clamp_hits.is_empty():
		var total := 0
		var union := AABB()
		var first := true
		for n in clamp_hits.keys():
			var data: Array = clamp_hits[n]
			total += int(data[0])
			if first:
				union = data[1]
				first = false
			else:
				union = union.merge(data[1])
		print("[LaunchDock] лапы зажимов заходят в зону (это норма): %d деталей, x %.2f..%.2f, y %.2f..%.2f"
				% [total, union.position.x, union.end.x, union.position.y, union.end.y])


func _has_ancestor_named(node_name: String, needle: String) -> bool:
	return node_name.begins_with(needle) or node_name.contains(needle)


func _count_lights() -> int:
	var n := 0
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is Light3D:
			n += 1
		for c in cur.get_children():
			stack.append(c)
	return n


func _count_stats() -> Dictionary:
	var nodes := 0
	var meshes := 0
	var instances := 0
	var tris := 0
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		nodes += 1
		for c in cur.get_children():
			stack.append(c)
		var mmi := cur as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null and mmi.multimesh.mesh != null:
			meshes += 1
			var mm := mmi.multimesh
			instances += mm.instance_count
			var mesh := mm.mesh
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() / 3) * mm.instance_count
	return {"nodes": nodes, "meshes": meshes, "instances": instances, "tris": tris}


func _world_aabbs() -> Array:
	# Возвращает ['имя батча', AABB] ПО КАЖДОМУ инстансу: батч-общий AABB
	# бесполезен (фермы всех четырёх вышек дают один огромный бокс).
	var out: Array = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var mmi := cur as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null and mmi.multimesh.mesh != null:
			var mm := mmi.multimesh
			var mesh_aabb: AABB = mm.mesh.get_aabb()
			var node_xf := mmi.global_transform
			for i in mm.instance_count:
				var xf := node_xf * mm.get_instance_transform(i)
				out.append([String(mmi.name), xf * mesh_aabb])
		else:
			var mi := cur as MeshInstance3D
			if mi != null and mi.mesh != null:
				out.append([String(mi.name), mi.global_transform * mi.get_aabb()])
	return out
