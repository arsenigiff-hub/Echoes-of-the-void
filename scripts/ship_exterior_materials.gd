extends Node3D

# Материалы внешнего корабля: ship_hull.glb / airlock_hatch.glb (плоские цвета)
# -> наши текстуры из assetss/tex_gemini/ship.

const TEX := "res://assetss/tex_gemini/ship/"

var _cache: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	_apply(self)


func _apply(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			var m := _mat(String(src.resource_name))
			if m != null:
				mi.set_surface_override_material(i, m)
	for c in node.get_children():
		_apply(c)


func _mat(key: String) -> Material:
	if _cache.has(key):
		return _cache[key]
	var m: StandardMaterial3D = null
	match key:
		"paint_white":
			m = _tri("hull_white.png", Color(1, 1, 1), 0.28, 0.85, 0.2)
		"metal_panel":
			m = _tri("hull_dark.png", Color(1, 1, 1), 0.3, 0.8, 0.35)
		"metal_dark":
			m = _tri("hull_dark.png", Color(0.55, 0.55, 0.55), 0.35, 0.85, 0.35)
		"paint_worn":
			m = _tri("repair_plates.png", Color(1, 1, 1), 0.35, 0.8, 0.3)
		"rust":
			m = _tri("rust_heavy2.png", Color(1, 1, 1), 0.3, 0.9, 0.2)
		"hazard_y":
			m = _tri("hazard_stripes2.png", Color(1, 1, 1), 0.42, 0.85, 0.2)
		"hazard_k":
			m = _tri("hull_dark.png", Color(0.4, 0.4, 0.4), 0.3, 0.85, 0.3)
		"glass_grime":
			m = _glass()
		"lamp_cold":
			m = _emissive(Color(0.7, 0.85, 1.0), 1.4)
		"red_lamp":
			m = _emissive(Color(1.0, 0.12, 0.06), 1.4)
	_cache[key] = m
	return m


func _tri(name: String, tint: Color, scale: float, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := load(TEX + name) as Texture2D
	if tex != null:
		m.albedo_texture = tex
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.roughness = rough
	m.metallic = metal
	return m


func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.13, 0.15, 0.7)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.15
	m.metallic = 0.4
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.2
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m
