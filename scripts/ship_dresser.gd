extends Node3D

# «Одевание» интерьера корабля в рантайме.
#
# Зачем: сцена res://scenes/ship_interior.tscn собрана из GLB-модулей, и
# материалы/декали вешались на ВНУТРЕННИЕ узлы инстансов (MeshInstance3D
# внутри wall_panel_*.glb и т.п.). Такие узлы не имеют owner = корень сцены,
# поэтому в PackedScene не попадают: при сохранении остаются только ссылки
# на GLB, а surface_override_material теряется. В итоге в игре стены были
# с гладкими базовыми материалами Blender.
#
# Решение: этот узел живёт внутри ship_interior.tscn и при загрузке сцены
# заново навешивает материалы по имени материала из GLB (metal_panel, rust,
# paint_worn, ...), а также раскладывает декали (таблички, плакаты, DECK B).
#
# Скрипт идемпотентен: повторный запуск ничего не ломает, декали-дубли из
# старой сборки удаляются.

const TILE_DIR := "res://assetss/tex_gemini/tiles/"
const DECAL_DIR := "res://assetss/tex_gemini/decals/"

# Имя материала в GLB -> файл текстуры в tiles.
const TILE_FOR_KEY := {
	"metal_panel": "metal_wall",
	"metal_dark": "metal_wall_dark",
	"paint_worn": "metal_wall_clean",
	"rust": "metal_wall_rust",
	"hazard_y": "hazard_stripes_worn",
	"hazard_k": "metal_wall_dark",
	"floor_grate": "floor_grate",
	"floor_wet": "floor_wet",
	# мокрый пол шлюза (в ките остался от старой сборки)
	"wet_grime": "floor_wet",
}

# Полу и решётке нужен более крупный трипланар, чтобы плитка не «рябила».
const FLOOR_KEYS := ["floor_grate", "floor_wet", "wet_grime"]

# Эмиссивные поверхности: ключ -> [emission, energy, albedo]
const EMISSIVE_FOR_KEY := {
	"crt_green": [Color(0.35, 1.0, 0.55), 1.0, Color(0.008, 0.02, 0.012)],
	"red_lamp": [Color(1.0, 0.055, 0.02), 1.0, Color(0.05, 0.004, 0.002)],
	"lamp_cold": [Color(0.62, 0.82, 1.0), 1.0, Color(0.55, 0.66, 0.78)],
}

const GLASS_KEY := "glass_grime"
const SPECIAL_KEYS := ["fabric_dirty", "fabric_light", "fabric_pillow", "paper_old"]

# Декали: [текстура, позиция, поворот (град), размер].
# Y — уже с учётом пола (FLOOR = 2.1486).
#
# Позиции сверены с кадрами capture_final.gd. В кадре final_01 (взгляд вперёд
# по коридору) читаются DECK B, плакат и табличка на левом борту и записка на
# верстаке, в final_02 (взгляд назад) — плакат на правом борту и номер B-3 на
# двери. Исходные координаты давали на кадре 25-86 px для DECK B и знака
# (нечитаемо), поэтому часть декалей сдвинута вдоль коридора в зону, которую
# реально видно; Z — 0.07 м от плоскости панелей, чтобы не проваливаться за
# рёбра панелей.
const DECALS := [
	{"tex": "stencil_deckb", "pos": Vector3(2.0, 4.12, 10.536),
			"rot": Vector3(0, 0, 0), "size": Vector2(1.3, 0.5)},
	{"tex": "poster_keepcalm", "pos": Vector3(1.0, 3.36, 13.264),
			"rot": Vector3(0, 0, 0), "size": Vector2(0.5, 0.7)},
	{"tex": "poster_rec", "pos": Vector3(1.55, 3.6486, 13.264),
			"rot": Vector3(0, 180, 0), "size": Vector2(0.45, 0.62)},
	{"tex": "sign_warning", "pos": Vector3(7.4, 3.55, 10.536),
			"rot": Vector3(0, 0, 0), "size": Vector2(0.5, 0.5)},
	# записка лежит на столешнице верстака (её верх — 3.1086)
	{"tex": "note_handwritten", "pos": Vector3(4.25, 3.11, 12.45),
			"rot": Vector3(-90, 0, 0), "size": Vector2(0.32, 0.42)},
	{"tex": "poster_mng", "pos": Vector3(-5.4, 3.6986, 10.536),
			"rot": Vector3(0, 0, 0), "size": Vector2(0.5, 0.7)},
	{"tex": "sign_decompression", "pos": Vector3(-6.6, 3.5986, 10.536),
			"rot": Vector3(0, 0, 0), "size": Vector2(0.9, 0.5)},
	{"tex": "hazard_labels", "pos": Vector3(-7.1, 3.4486, 10.536),
			"rot": Vector3(0, 0, 0), "size": Vector2(0.5, 0.5)},
	{"tex": "porthole", "pos": Vector3(10.2, 3.6486, 13.264),
			"rot": Vector3(0, 180, 0), "size": Vector2(0.6, 0.6)},
	# номер на двери B-3 (геометрия модели затекстурена, надпись — декаль)
	{"tex": "b3_number", "pos": Vector3(-3.724, 3.62, 11.9),
			"rot": Vector3(0, 90, 0), "size": Vector2(0.62, 0.46)},
	# каюта экипажа
	{"tex": "poster_keepcalm", "pos": Vector3(6.564, 3.85, 8.4),
			"rot": Vector3(0, -90, 0), "size": Vector2(0.45, 0.62)},
	{"tex": "note_handwritten", "pos": Vector3(3.236, 3.65, 8.1),
			"rot": Vector3(0, 90, 0), "size": Vector2(0.3, 0.4)},
	{"tex": "sign_warning", "pos": Vector3(4.2, 3.9, 7.236),
			"rot": Vector3(0, 0, 0), "size": Vector2(0.4, 0.4)},
]

var _cache: Dictionary = {}
var _surfaces := 0
var _decals := 0


func _ready() -> void:
	# Ждём кадр: так все инстансы GLB в родительской сцене уже точно созданы.
	await get_tree().process_frame
	var host := get_parent() as Node3D
	if host == null:
		push_warning("ShipDresser: нет родительского узла, одевать нечего")
		return
	_dress_meshes(host)
	_place_decals(host)
	print("[ShipDresser] surfaces=", _surfaces, " decals=", _decals)


# --------------------------------------------------------------- материалы --

func _dress_meshes(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		_dress_mesh(mi)
	for child in node.get_children():
		_dress_meshes(child)


func _dress_mesh(mi: MeshInstance3D) -> void:
	# У планет, панорамного стекла и прочих авторских объектов уже стоит
	# material_override (в т.ч. ShaderMaterial) — их не трогаем.
	if mi.material_override is ShaderMaterial:
		return
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		var key := String(src.resource_name)
		if key == "":
			continue
		var keep_default := key in ["hazard_y", "hazard_k", "crt_green", "red_lamp", "glass_grime"]
		var mat: Material = null
		if _has_ancestor(mi, "door_b3") and not keep_default:
			mat = _door_material()
		else:
			mat = _material_for(key)
		if mat == null:
			continue
		if _is_ceiling(mi):
			mat = _ceiling_material()
		mi.set_surface_override_material(i, mat)
		_surfaces += 1


func _material_for(key: String) -> Material:
	if _cache.has(key):
		return _cache[key] as Material
	var mat: Material = null
	if EMISSIVE_FOR_KEY.has(key):
		mat = _emissive_material(key)
	elif SPECIAL_KEYS.has(key):
		mat = _special_material(key)
	elif key == GLASS_KEY:
		mat = _glass_material()
	elif TILE_FOR_KEY.has(key):
		mat = _tiled_material(key)
	_cache[key] = mat
	return mat


func _tiled_material(key: String) -> StandardMaterial3D:
	var tex := load(TILE_DIR + String(TILE_FOR_KEY[key]) + ".png") as Texture2D
	if tex == null:
		push_warning("ShipDresser: нет текстуры " + key)
		return null
	var m := StandardMaterial3D.new()
	m.resource_name = "dress_" + key
	m.albedo_texture = tex
	m.albedo_color = Color(0.62, 0.62, 0.66)
	m.uv1_triplanar = true
	# крупнее масштаб — убирает повторяющийся «X»-узор
	var s := 0.6 if FLOOR_KEYS.has(key) else 0.45
	m.uv1_scale = Vector3(s, s, s)
	m.roughness = 0.85
	m.metallic = 0.35
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _special_material(key: String) -> StandardMaterial3D:
	if _cache.has("sp_" + key):
		return _cache["sp_" + key]
	var m := StandardMaterial3D.new()
	m.resource_name = "dress_sp_" + key
	var tex_name := "fabric_blanket.png"
	if key == "fabric_light":
		tex_name = "fabric_sheet.png"
	elif key == "fabric_pillow":
		tex_name = "fabric_pillow.png"
	var tex := load(TILE_DIR + tex_name) as Texture2D
	if tex != null:
		m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.85, 0.85, 0.85)
	m.roughness = 1.0
	m.metallic = 0.0
	match key:
		"fabric_dirty":
			m.albedo_color = Color(0.95, 0.95, 0.95)
		"fabric_light":
			m.albedo_color = Color(0.56, 0.55, 0.52)
		"fabric_pillow":
			m.albedo_color = Color(0.74, 0.73, 0.7)
		"paper_old":
			m.albedo_color = Color(0.85, 0.82, 0.72)
	_cache["sp_" + key] = m
	return m


func _has_ancestor(node: Node, part: String) -> bool:
	var cur := node
	while cur != null:
		if String(cur.name).to_lower().contains(part):
			return true
		cur = cur.get_parent()
	return false


func _door_material() -> StandardMaterial3D:
	if _cache.has("__door_b3"):
		return _cache["__door_b3"]
	var m := StandardMaterial3D.new()
	m.resource_name = "dress_door_b3"
	var tex := load(TILE_DIR + "door_metal.png") as Texture2D
	if tex != null:
		m.albedo_texture = tex
	m.albedo_color = Color(0.95, 0.95, 0.95)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.55, 0.55, 0.55)
	m.roughness = 0.78
	m.metallic = 0.45
	_cache["__door_b3"] = m
	return m


func _is_ceiling(node: Node) -> bool:
	var cur := node
	while cur != null:
		if String(cur.name).begins_with("ceil_panel"):
			return true
		cur = cur.get_parent()
	return false


func _ceiling_material() -> StandardMaterial3D:
	if _cache.has("__ceiling"):
		return _cache["__ceiling"]
	var m := StandardMaterial3D.new()
	m.resource_name = "dress_ceiling"
	var tex := load(TILE_DIR + "metal_wall_dark.png") as Texture2D
	if tex != null:
		m.albedo_texture = tex
	m.albedo_color = Color(0.34, 0.34, 0.38)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.45, 0.45, 0.45)
	m.roughness = 0.9
	m.metallic = 0.3
	_cache["__ceiling"] = m
	return m


func _emissive_material(key: String) -> StandardMaterial3D:
	var data: Array = EMISSIVE_FOR_KEY[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "dress_" + key
	m.albedo_color = data[2]
	m.emission_enabled = true
	m.emission = data[0]
	m.emission_energy_multiplier = data[1]
	m.roughness = 0.6
	return m


func _glass_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "dress_glass_grime"
	m.albedo_color = Color(0.2, 0.3, 0.32, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.2
	m.metallic = 0.15
	return m


# ------------------------------------------------------------------ декали --

func _place_decals(host: Node3D) -> void:
	# В сохранённой сцене могут лежать декали старой сборки — убираем их,
	# чтобы не было дублей и z-fighting.
	for child in host.get_children():
		if String(child.name).begins_with("Decal_"):
			host.remove_child(child)
			child.queue_free()
	for data in DECALS:
		_add_decal(host, data)


func _add_decal(host: Node3D, data: Dictionary) -> void:
	var tex_name := String(data["tex"])
	var tex := load(DECAL_DIR + tex_name + ".png") as Texture2D
	if tex == null:
		push_warning("ShipDresser: нет декали " + tex_name)
		return
	var mi := MeshInstance3D.new()
	mi.name = "Decal_" + tex_name
	var quad := QuadMesh.new()
	quad.size = data["size"]
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.resource_name = "decal_" + tex_name
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.68, 0.68, 0.68)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = mat
	mi.position = data["pos"]
	mi.rotation_degrees = data["rot"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	_decals += 1
