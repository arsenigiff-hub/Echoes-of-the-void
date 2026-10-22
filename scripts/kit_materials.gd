extends Node3D

# Накладывает грязные текстуры на GLB-модули по именам материалов.
# Тот же маппинг, что в сборщике корабля: metal_panel -> текстура и т.д.
# Отдельный случай — узел Screen у радио: там UV 0..1, поэтому накладываем
# текстуру радиодисплея без трипланарного проецирования.

const TEX := "res://assetss/tex/"
const GEM := "res://assetss/tex_gemini/"
const SPACE := "res://assetss/space/"

var _cache := {}


func _ready() -> void:
	_apply(self)


func _apply(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			var mat: Material = null
			if String(mi.name).begins_with("Screen"):
				mat = _radio_screen_material()
			else:
				mat = _kit_material(src.resource_name)
			if mat != null:
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply(child)


func _tex(name: String) -> Texture2D:
	var path := GEM + "tiles/" + name
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	path = TEX + name
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _triplanar(name: String, color: Color, scale: float, rough: float, metal: float) -> StandardMaterial3D:
	var key := name + str(color) + str(scale)
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	var tex := _tex(name)
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(scale, scale, scale)
	m.albedo_color = color.darkened(0.5)
	m.roughness = rough
	m.metallic = metal
	_cache[key] = m
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.08, 0.05)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.6
	return m


func _screen_material() -> StandardMaterial3D:
	if _cache.has("screen"):
		return _cache["screen"]
	var m := StandardMaterial3D.new()
	var path := GEM + "crt/crt_telemetry.png"
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		m.albedo_texture = tex
		m.emission_texture = tex
	m.albedo_color = Color(1, 1, 1)
	m.emission_enabled = true
	m.emission = Color(0.6, 1.0, 0.75)
	m.emission_energy_multiplier = 0.55
	m.roughness = 0.5
	_cache["screen"] = m
	return m


# Экран радио: unshaded CRT в зелёной гамме. Раньше был shaded-материал с белым
# albedo, и тёплая лампа верстака выбивала экран в белое пятно (final_05_radio).
func _radio_screen_material() -> StandardMaterial3D:
	if _cache.has("radio_screen"):
		return _cache["radio_screen"]
	var m := StandardMaterial3D.new()
	var path := GEM + "crt/crt_telemetry.png"
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		m.albedo_texture = tex
		m.emission_texture = tex
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.50, 0.85, 0.58)
	m.emission_enabled = true
	m.emission = Color(0.25, 0.90, 0.45)
	m.emission_energy_multiplier = 0.45
	m.disable_fog = true
	_cache["radio_screen"] = m
	return m


func _kit_material(key: String) -> Material:
	if key == "":
		return null
	if _cache.has("kit_" + key):
		return _cache["kit_" + key]
	var m: Material = null
	match key:
		"metal_panel":
			m = _triplanar("metal_wall.png", Color(1, 1, 1), 0.45, 0.85, 0.35)
		"metal_dark":
			m = _triplanar("metal_wall_dark.png", Color(1, 1, 1), 0.45, 0.88, 0.3)
		"paint_worn":
			m = _triplanar("metal_wall_clean.png", Color(0.85, 0.84, 0.78), 0.45, 0.8, 0.25)
		"rust":
			m = _triplanar("metal_wall_rust.png", Color(0.62, 0.38, 0.24), 0.45, 0.9, 0.15)
		"hazard_y":
			m = _triplanar("hazard_stripes.png", Color(1, 1, 1), 1.2, 0.85, 0.2)
		"hazard_k":
			m = _triplanar("metal_dark.png", Color(0.05, 0.05, 0.05), 2.0, 0.9, 0.1)
		"crt_green":
			m = _emissive(Color(0.3, 1.0, 0.5), 0.9)
		"red_lamp":
			m = _emissive(Color(1.0, 0.1, 0.05), 1.4)
		"paint_red":
			m = _triplanar("metal_wall_rust.png", Color(0.5, 0.16, 0.08), 0.45, 0.85, 0.2)
		"glass_grime":
			m = _screen_material()
		_:
			m = null
	_cache["kit_" + key] = m
	return m
