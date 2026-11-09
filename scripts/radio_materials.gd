extends Node

# Материалы нового военного приёмника (radio_field.glb).
# Навешиваются на Model внутри scenes/radio_device.tscn.
#
# Материалы GLB:
#   metal_panel  -> зелёный корпус (radio_body)
#   metal_dark   -> тёмная лицевая панель (radio_panel)
#   paint_worn   -> голый металл: ручка, антенна, углы (radio_metal)
#   rust         -> тяжёлая ржавчина (rust_heavy)
#   hazard_y/k   -> хазард-полосы
#   crt_green    -> индикаторы
#   Screen       -> CRT-текстура по UV (radio_screen)

const TEX := "res://assetss/tex_gemini/radio/"
const TILES := "res://assetss/tex_gemini/tiles/"

var _cache: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	_apply(self)


func _apply(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		_apply_mesh(mi)
	for c in node.get_children():
		_apply(c)


func _apply_mesh(mi: MeshInstance3D) -> void:
	if String(mi.name).begins_with("Screen"):
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, _screen_material())
		return
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		var key := String(src.resource_name)
		var mat := _material_for(key)
		if mat != null:
			mi.set_surface_override_material(i, mat)


func _material_for(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	var m: StandardMaterial3D = null
	match key:
		"metal_panel":
			m = _tri("radio_body.png", Color(1, 1, 1), 1.55, 0.75, 0.35)
		"metal_dark":
			m = _tri("radio_panel.png", Color(1, 1, 1), 1.45, 0.8, 0.3)
		"paint_worn":
			m = _tri("radio_metal.png", Color(1, 1, 1), 1.9, 0.6, 0.6)
		"rust":
			m = _tri("rust_heavy.png", Color(1, 1, 1), 1.5, 0.9, 0.2)
		"hazard_y":
			m = _tri(TILES + "hazard_stripes_worn.png", Color(1, 1, 1), 1.6, 0.85, 0.2)
		"hazard_k":
			m = _tri(TILES + "metal_wall_dark.png", Color(0.35, 0.35, 0.35), 1.2, 0.85, 0.3)
		"crt_green":
			m = _emissive(Color(0.35, 1.0, 0.5), 0.6)
		"red_lamp":
			m = _emissive(Color(1.0, 0.08, 0.03), 0.8)
		"lamp_cold":
			m = _emissive(Color(0.75, 0.85, 1.0), 0.7)
		"glass_grime":
			m = _glass()
	_cache[key] = m
	return m


func _tri(name: String, tint: Color, scale: float, rough: float, metal: float) -> StandardMaterial3D:
	var path := name if name.contains("/") else TEX + name
	var tex := load(path) as Texture2D
	var m := StandardMaterial3D.new()
	m.resource_name = "radio_" + name.get_file().get_basename()
	if tex != null:
		m.albedo_texture = tex
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = rough
	m.metallic = metal
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.25
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.22, 0.2, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.2
	return m


func _screen_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := load(TEX + "radio_screen.png") as Texture2D
	if tex != null:
		m.albedo_texture = tex
		m.emission_texture = tex
	m.albedo_color = Color(0.9, 0.95, 0.9)
	m.emission_enabled = true
	m.emission = Color(0.6, 1.0, 0.65)
	m.emission_energy_multiplier = 0.85
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_receive_shadows = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m
