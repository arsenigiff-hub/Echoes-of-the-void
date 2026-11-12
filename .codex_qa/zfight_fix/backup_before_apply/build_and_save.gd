extends "res://.codex_qa/shipassemble/build_ship.gd"

# Сборка нового интерьера и сохранение его как сцены для main.tscn.
# Наследует сборщик (build_ship.gd), но не рендерит кадры и не сохраняет
# тестовое окружение: свет/модули/космос остаются, WorldEnvironment — нет.
# Запуск: godot --headless --path D:\4 --script res://.codex_qa/shipassemble/build_and_save.gd


func _initialize() -> void:
	_build_save()


func _build_save() -> void:
	rng.seed = 7
	ship = Node3D.new()
	ship.name = "ShipInterior"
	root.add_child(ship)

	_make_materials()
	_build_corridor()
	_build_airlock()
	_build_bridge()
	_build_quarters()
	_place_quarters_furniture()
	_polish_props()
	_build_props()
	_build_lights()
	_build_space()
	_rebuild_light_rig()
	_name_space_objects()
	_clean_radio_bench()
	_apply_gemini_textures()
	_place_decals()
	# _apply_screen_textures()  # временно: без UV даёт артефакты

	# Тестовое окружение убираем: в main.tscn свой WorldEnvironment.
	if world_env != null:
		ship.remove_child(world_env)
		world_env.free()
		world_env = null

	# Материалы и декали, повешенные на внутренние узлы GLB-инстансов, в
	# PackedScene не сохраняются (у этих узлов нет owner). Поэтому внутрь
	# сцены кладём узел-«одевальщик»: в игре он сам навесит текстуры и декали.
	var dresser := Node3D.new()
	dresser.name = "ShipDresser"
	dresser.set_script(load("res://scripts/ship_dresser.gd"))
	ship.add_child(dresser)

	_set_owners(ship)

	var packed := PackedScene.new()
	var err := packed.pack(ship)
	print("pack err=", err, " nodes=", _count_nodes(ship))
	if err == OK:
		var save_err := ResourceSaver.save(packed, "res://scenes/ship_interior.tscn")
		print("save err=", save_err)
	else:
		print("не сохраняю: pack не удался")
	print("=== done ===")
	quit()


func _set_owners(node: Node) -> void:
	for child in node.get_children():
		child.owner = ship
		# внутрь инстансов GLB не лезем — они сохранятся как ссылки на сцены
		if child.scene_file_path == "":
			_set_owners(child)


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


# -------------------------------------------------- экраны консолей и CRT --

func _apply_screen_textures() -> void:
	# какой модуль каким экраном светит
	var screens := {
		"console_section": "res://assetss/tex/crt_telemetry.png",
		"crt_terminal": "res://assetss/tex/crt_telemetry.png",
		"wall_panel_b": "res://assetss/tex/crt_radar.png",
	}
	for node in ship.get_children():
		var key := String(node.name)
		for prefix in screens:
			if key.begins_with(prefix):
				_apply_screen(node, screens[prefix], 2.5)
				break


func _apply_screen(node: Node, tex_path: String, uv_scale: float) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null or src.resource_name != "crt_green":
				continue
			mi.set_surface_override_material(i, _screen_material(tex_path, uv_scale))
	for child in node.get_children():
		_apply_screen(child, tex_path, uv_scale)


func _screen_material(tex_path: String, uv_scale: float) -> StandardMaterial3D:
	var tex := load(tex_path) as Texture2D
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	m.emission_enabled = true
	m.emission = Color(0.6, 1.0, 0.75)
	m.emission_texture = tex
	m.emission_energy_multiplier = 1.3
	m.roughness = 0.65
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


# ------------------------------------------------ свой световой риг ---------
# Вариант C «контрастный хоррор» (полировка 2026-10-22, аудит light-auditor):
# 19 ламп, 3 тени (#1, #9, #13); радиусы сжаты, энергия поднята, между пятнами
# глубокая темнота, красная аварийка и CRT-зелень усилены. Лампа #19 добавлена
# отдельно: без неё зона подхода к переборке B-3 уходила в почти полную черноту.
var RIG_C := [
	{"pos": Vector3(0.0, 4.2986, 11.90), "color": Color(0.70, 0.83, 1.00), "energy": 3.20, "range": 3.6, "shadow": true},
	{"pos": Vector3(4.5, 4.2986, 11.90), "color": Color(0.70, 0.83, 1.00), "energy": 3.20, "range": 3.6, "shadow": false},
	{"pos": Vector3(8.0, 4.2986, 11.90), "color": Color(0.70, 0.83, 1.00), "energy": 3.20, "range": 3.6, "shadow": false},
	{"pos": Vector3(-2.5, 4.2986, 11.90), "color": Color(1.00, 0.07, 0.03), "energy": 2.40, "range": 3.6, "shadow": false},
	{"pos": Vector3(6.5, 4.2986, 11.90), "color": Color(1.00, 0.07, 0.03), "energy": 2.40, "range": 3.6, "shadow": false},
	{"pos": Vector3(-3.6, 4.3486, 11.90), "color": Color(1.00, 0.12, 0.05), "energy": 1.00, "range": 2.0, "shadow": false},
	{"pos": Vector3(-2.3, 3.6486, 11.90), "color": Color(0.60, 0.76, 1.00), "energy": 0.60, "range": 2.8, "shadow": false},
	{"pos": Vector3(-5.9, 4.2986, 11.90), "color": Color(0.72, 0.84, 1.00), "energy": 2.40, "range": 4.2, "shadow": true},
	{"pos": Vector3(10.6, 4.3486, 11.90), "color": Color(0.70, 0.83, 1.00), "energy": 3.00, "range": 4.4, "shadow": true},
	{"pos": Vector3(13.2, 4.3486, 11.90), "color": Color(0.70, 0.83, 1.00), "energy": 2.50, "range": 4.0, "shadow": false},
	{"pos": Vector3(13.9, 3.2486, 11.90), "color": Color(0.30, 1.00, 0.45), "energy": 2.20, "range": 2.8, "shadow": false},
	{"pos": Vector3(4.7, 4.0486, 12.50), "color": Color(1.00, 0.83, 0.55), "energy": 1.80, "range": 2.2, "shadow": false},
	{"pos": Vector3(5.0, 4.2986, 8.85), "color": Color(0.72, 0.84, 1.00), "energy": 2.90, "range": 4.4, "shadow": true},
	{"pos": Vector3(5.9, 3.4986, 8.00), "color": Color(1.00, 0.80, 0.48), "energy": 1.90, "range": 2.2, "shadow": false},
	{"pos": Vector3(3.8, 4.1986, 7.80), "color": Color(1.00, 0.12, 0.05), "energy": 1.50, "range": 2.2, "shadow": false},
	{"pos": Vector3(-1.0, 3.0486, 11.10), "color": Color(0.62, 0.76, 1.00), "energy": 0.30, "range": 3.6, "shadow": false},
	{"pos": Vector3(5.5, 3.0486, 12.70), "color": Color(0.62, 0.76, 1.00), "energy": 0.30, "range": 3.6, "shadow": false},
	{"pos": Vector3(12.0, 3.0486, 11.10), "color": Color(0.62, 0.76, 1.00), "energy": 0.35, "range": 3.8, "shadow": false},
	# #19: филл у переборки B-3, чтобы дверь/рама читались в жёстком C
	{"pos": Vector3(-2.6, 3.40, 11.90), "color": Color(0.62, 0.76, 1.00), "energy": 0.90, "range": 3.2, "shadow": false},
	# шлюз: подсветка круглой двери, пульт, красная аварийка
	{"pos": Vector3(-7.0, 3.30, 11.90), "color": Color(0.78, 0.87, 1.00), "energy": 1.00, "range": 3.0, "shadow": false},
	{"pos": Vector3(-7.05, 3.95, 11.90), "color": Color(1.00, 0.14, 0.06), "energy": 1.10, "range": 2.6, "shadow": false},
	{"pos": Vector3(-5.0, 3.30, 10.95), "color": Color(0.55, 1.00, 0.60), "energy": 0.55, "range": 1.6, "shadow": false},
]


func _rebuild_light_rig() -> void:
	for child in ship.get_children():
		if child is Light3D:
			child.free()
	for l in RIG_C:
		_rig_omni(l["pos"], l["color"], float(l["energy"]), float(l["range"]), bool(l["shadow"]))


func _rig_omni(pos: Vector3, color: Color, energy: float, range_m: float, shadow: bool) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.shadow_enabled = shadow
	ship.add_child(l)


# ---------------------------------------------- имена объектов космоса ----

func _name_space_objects() -> void:
	for child in ship.get_children():
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var m := mi.material_override as StandardMaterial3D
		if m == null or m.albedo_texture == null:
			continue
		var path := m.albedo_texture.resource_path
		if path.ends_with("planet_gas.png"):
			mi.name = "SpaceGasGiant"
		elif path.ends_with("planet_ring.png"):
			mi.name = "SpaceRing"
		elif path.ends_with("planet_blackhole.png"):
			mi.name = "SpaceBlackHole"


# ---------------------------------------------- расчистка верстака с радио --

func _clean_radio_bench() -> void:
	# На верстаке теперь стоит новое радио: старый CRT-терминал убираем,
	# иначе модели пересекаются.
	for child in ship.get_children():
		var node := child as Node3D
		if node == null:
			continue
		if not String(node.name).begins_with("crt_terminal"):
			continue
		# локальная позиция вместо global_position: узел может быть ещё не в дереве,
		# а global_position в этом случае возвращает origin и сносит не тот объект
		if node.position.x < 8.0:
			node.free()


# ----------------------------------------- проба новых текстур (CC0/пиксель) --

func _apply_tex2() -> void:
	var map := {
		"m_wall": "res://assetss/tex2/metal_wall.png",
		"m_wall_b": "res://assetss/tex2/metal_wall_clean.png",
		"m_floor": "res://assetss/tex2/floor_grate.png",
		"m_floor_wet": "res://assetss/tex2/floor_plate.png",
		"m_hazard": "res://assetss/tex2/hazard_hand.png",
	}
	for key in map:
		var mat: StandardMaterial3D = get(key)
		if mat == null:
			continue
		var tex := load(map[key]) as Texture2D
		if tex != null:
			mat.albedo_texture = tex


# ------------------------------------- проба пользовательской текстуры стены --

func _apply_user_metal() -> void:
	var tex := load("res://assetss/tex_gemini/metal_wall.png") as Texture2D
	if tex == null:
		print("нет пользовательской текстуры")
		return
	for key in ["m_wall", "m_wall_b"]:
		var mat: StandardMaterial3D = get(key)
		if mat != null:
			mat.albedo_texture = tex
			mat.uv1_scale = Vector3(0.9, 0.9, 0.9)


# ------------------------------- новые текстуры из папки images (Gemini) -----

const GEM_TILES := "res://assetss/tex_gemini/tiles/"
const GEM_DECALS := "res://assetss/tex_gemini/decals/"

var _gem_map := {
	"metal_panel": "metal_wall",
	"metal_dark": "metal_wall_dark",
	"floor_grate": "floor_grate",
	"floor_wet": "floor_wet",
	"hazard_stripes": "hazard_stripes",
	"paint_worn": "metal_wall_clean",
	"rust": "metal_wall_rust",
	"hazard_y": "hazard_stripes_worn",
	"hazard_k": "metal_wall_dark",
}


func _apply_gemini_textures() -> void:
	_apply_to_meshes(ship)


func _apply_to_meshes(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_surface_override_material(i) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var old_path := mat.albedo_texture.resource_path
			for key in _gem_map:
				if old_path.contains(key):
					var new_tex := load(GEM_TILES + _gem_map[key] + ".png") as Texture2D
					if new_tex != null:
						mat.albedo_texture = new_tex
					break
	for child in node.get_children():
		_apply_to_meshes(child)


func _place_decals() -> void:
	var z_port := Z0 + 0.06
	var z_stbd := Z1 - 0.06
	# коридор
	_decal("stencil_deckb", Vector3(6.2, FLOOR + 1.85, z_stbd), Vector3(0, 180, 0), Vector2(1.3, 0.5))
	_decal("poster_keepcalm", Vector3(2.6, FLOOR + 1.5, z_port), Vector3.ZERO, Vector2(0.5, 0.7))
	_decal("poster_rec", Vector3(0.9, FLOOR + 1.5, z_stbd), Vector3(0, 180, 0), Vector2(0.45, 0.62))
	_decal("sign_warning", Vector3(8.2, FLOOR + 1.5, z_port), Vector3.ZERO, Vector2(0.5, 0.5))
	_decal("note_handwritten", Vector3(4.25, FLOOR + 0.955, 12.45), Vector3(-90, 0, 0), Vector2(0.32, 0.42))
	# шлюз
	_decal("poster_mng", Vector3(-5.4, FLOOR + 1.55, z_port), Vector3.ZERO, Vector2(0.5, 0.7))
	_decal("sign_decompression", Vector3(-6.6, FLOOR + 1.45, z_port), Vector3.ZERO, Vector2(0.9, 0.5))
	_decal("hazard_labels", Vector3(-7.1, FLOOR + 1.3, z_port), Vector3.ZERO, Vector2(0.5, 0.5))
	# дверь B-3: номер на полотне
	_decal("b3_number", Vector3(-3.80, FLOOR + 1.45, 11.9), Vector3(0, 90, 0), Vector2(0.6, 0.45))
	# мостик: иллюминатор-декор на борту
	_decal("porthole", Vector3(10.2, FLOOR + 1.5, z_stbd), Vector3(0, 180, 0), Vector2(0.6, 0.6))


func _decal(tex_name: String, pos: Vector3, rot_deg: Vector3, size: Vector2) -> void:
	var tex := load(GEM_DECALS + tex_name + ".png") as Texture2D
	if tex == null:
		print("нет декали: ", tex_name)
		return
	var mi := MeshInstance3D.new()
	mi.name = "Decal_" + tex_name
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.6, 0.6, 0.6)
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	ship.add_child(mi)


# ------------------------------------------- мебель каюты экипажа -----------

const QFURN := "res://assetss/rooms/quarters/"
const QROOM_ORIGIN := Vector3((ROOM_X0 + ROOM_X1) * 0.5, FLOOR, (ROOM_Z0 + Z0) * 0.5)

const QF_ITEMS := [
	{"glb": "bunk_bed.glb", "pos": Vector3(0.0, 0.0, -1.008), "rot": 0.0,
			"coll": Vector3(1.99, 0.98, 1.70)},
	{"glb": "locker.glb", "pos": Vector3(1.305, 0.0, -0.85), "rot": -90.0,
			"coll": Vector3(0.57, 1.88, 0.59)},
	{"glb": "shelf_rack.glb", "pos": Vector3(-1.422, 0.0, -0.45), "rot": 90.0,
			"coll": Vector3(1.62, 1.80, 0.36)},
	{"glb": "table_small.glb", "pos": Vector3(0.62, 0.0, 0.35), "rot": -6.0,
			"coll": Vector3(0.90, 0.75, 0.55)},
	{"glb": "chair_folded.glb", "pos": Vector3(1.477, 0.0, 0.95), "rot": -90.0},
	{"glb": "sleeping_bag.glb", "pos": Vector3(-0.625, 0.0, 1.05), "rot": 4.0},
	{"glb": "wall_pipes_small.glb", "pos": Vector3(-0.45, 2.18, -1.429), "rot": 0.0},
	{"glb": "vent_grille.glb", "pos": Vector3(0.95, 2.05, -1.456), "rot": 0.0},
	{"glb": "cable_bundle_floor.glb", "pos": Vector3(0.55, 0.0, 1.44), "rot": 0.0},
	{"glb": "papers_scattered.glb", "pos": Vector3(0.68, 0.0, 1.02), "rot": 20.0},
	{"glb": "personal_photo_a.glb", "pos": Vector3(0.31, 0.754, 0.28), "rot": 8.0},
	{"glb": "personal_photo_b.glb", "pos": Vector3(0.9, 0.754, 0.4), "rot": -38.0},
	{"glb": "personal_mug.glb", "pos": Vector3(0.78, 0.754, 0.16), "rot": 25.0},
	{"glb": "personal_notebook.glb", "pos": Vector3(0.5, 0.754, 0.31), "rot": -12.0},
	{"glb": "personal_pencil.glb", "pos": Vector3(0.38, 0.757, 0.47), "rot": 70.0},
	{"glb": "personal_boots.glb", "pos": Vector3(1.26, 0.0, -0.32), "rot": 24.0},
	{"glb": "personal_toothbrush.glb", "pos": Vector3(0.93, 0.754, 0.2), "rot": 100.0},
]


func _place_quarters_furniture() -> void:
	var count := 0
	for item in QF_ITEMS:
		var packed := load(QFURN + String(item["glb"])) as PackedScene
		if packed == null:
			print("нет мебели: ", item["glb"])
			continue
		var node := packed.instantiate() as Node3D
		var pos: Vector3 = QROOM_ORIGIN + (item["pos"] as Vector3)
		node.position = pos
		node.rotation_degrees = Vector3(0.0, float(item["rot"]), 0.0)
		ship.add_child(node)
		if item.has("coll"):
			var size: Vector3 = item["coll"]
			_collider(size, Vector3(pos.x, FLOOR + size.y * 0.5, pos.z),
					Vector3(0.0, float(item["rot"]), 0.0))
		count += 1
	print("quarters furniture: ", count)


# ------------------------------- полировка: мелкие пропсы в пустых зонах ----
# Расстановки вдоль стен/на полках, полоса движения (z≈11.0…12.8) свободна.
const POLISH_PROPS := [
	# бумаги на полке штурманского поста мостика
	{"glb": "res://assetss/shipkit/equip/equip_papers.glb", "pos": Vector3(13.0, FLOOR + 0.696, 11.9),
			"rot": 35.0, "scale": Vector3(0.30, 0.01, 0.40)},
	# кабель на полу мостика у левого борта
	{"glb": "res://assetss/shipkit/arch/cable_bundle.glb", "pos": Vector3(11.9, FLOOR + 0.041, 10.9),
			"rot": 80.0, "scale": Vector3(1.6, 0.10, 0.10)},
	# вторая кружка на верстаке
	{"glb": "res://assetss/shipkit/equip/equip_mug.glb", "pos": Vector3(3.95, FLOOR + 0.971, 12.75),
			"rot": -20.0, "scale": Vector3(0.1, 0.1, 0.1)},
	# кабель у переборки B-3
	{"glb": "res://assetss/shipkit/arch/cable_bundle.glb", "pos": Vector3(-3.2, FLOOR + 0.041, 12.95),
			"rot": 15.0, "scale": Vector3(2.0, 0.12, 0.12)},
	# ящик в углу шлюза
	{"glb": "res://assetss/shipkit/equip/crate_small.glb", "pos": Vector3(-7.15, FLOOR, 12.95),
			"rot": 35.0, "scale": Vector3.ONE},
]


func _polish_props() -> void:
	var count := 0
	for item in POLISH_PROPS:
		var packed := load(String(item["glb"])) as PackedScene
		if packed == null:
			print("нет пропса: ", item["glb"])
			continue
		var node := packed.instantiate() as Node3D
		node.name = "PolishProp_" + String(item["glb"]).get_file().get_basename()
		node.position = item["pos"]
		node.rotation_degrees = Vector3(0.0, float(item["rot"]), 0.0)
		node.scale = item["scale"]
		ship.add_child(node)
		count += 1
	print("polish props: ", count)
