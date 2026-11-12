extends SceneTree

# Сборка нового интерьера корабля из модульного кита.
# Проверочный прогон: строит сцену в рантайме и рендерит кадры.
# Позже этим же скриптом сохраним готовую сцену для main.tscn.
# Запуск: godot --path D:\4 --resolution 1680x1050 --script res://.codex_qa/shipassemble/build_ship.gd

const OUT := "res://.codex_qa/shipassemble"
const ARCH := "res://assetss/shipkit/arch/"
const EQUIP := "res://assetss/shipkit/equip/"

const FLOOR := 2.1486
const CEIL := FLOOR + 2.6
const Z0 := 10.5
const Z1 := 13.3
const X_CORR_AFT := -4.0
const X_CORR_FWD := 9.4
const X_BRIDGE_FWD := 14.8
const Z_B0 := Z0
const Z_B1 := Z1
const X_AIR_AFT := -7.8
# каюта экипажа (боковое ответвление слева от коридора)
const ROOM_X0 := 3.2
const ROOM_X1 := 6.6
const ROOM_Z0 := 7.2
const ROOM_DOOR_X := 5.0

var ship: Node3D
var cam: Camera3D
var rng := RandomNumberGenerator.new()

var m_wall: StandardMaterial3D
var m_wall_b: StandardMaterial3D
var m_floor: StandardMaterial3D
var m_floor_wet: StandardMaterial3D
var m_ceil: StandardMaterial3D
var m_hazard: StandardMaterial3D
var m_metal: StandardMaterial3D
var m_dark: StandardMaterial3D
var m_crt: StandardMaterial3D
var m_red: StandardMaterial3D
var m_leak: StandardMaterial3D
var m_work: StandardMaterial3D
var m_glass: ShaderMaterial
var m_white: StandardMaterial3D

var missing: Array[String] = []
var world_env: WorldEnvironment


func _initialize() -> void:
	_run()


func _run() -> void:
	rng.seed = 7
	ship = Node3D.new()
	ship.name = "ShipInterior"
	root.add_child(ship)

	_make_materials()
	_build_shell()
	_build_corridor()
	_build_airlock()
	_build_bridge()
	_build_quarters()
	_build_props()
	_build_lights()
	_build_space()

	cam = Camera3D.new()
	ship.add_child(cam)
	cam.current = true
	cam.fov = 75.0
	await process_frame

	await _shot(Vector3(1.15, 3.5, 11.82), Vector3(9.6, 3.34, 11.88), "01_corridor", 74.0)
	await _shot(Vector3(-4.75, 3.5, 12.0), Vector3(-7.7, 3.3, 11.9), "02_airlock_door", 70.0)
	await _shot(Vector3(-5.75, 3.55, 12.55), Vector3(-3.9, 3.2, 11.85), "03_b3_from_airlock", 74.0)
	await _shot(Vector3(8.75, 3.6, 11.5), Vector3(14.9, 3.82, 11.6), "04_bridge", 72.0)
	await _shot(Vector3(2.35, 3.5, 11.05), Vector3(4.75, 3.25, 12.75), "05_workbench", 60.0)
	await _shot(Vector3(12.6, 3.95, 11.35), Vector3(30.0, 3.78, 11.75), "bridge_space", 68.0)

	print("missing modules: ", missing)
	print("=== done ===")
	quit()


# ---------------------------------------------------------------- материалы --

func _mat(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _textured(path: String, color: Color, scale: float, roughness: float,
		metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var tex := load(path) as Texture2D
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(scale, scale, scale)
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


func _make_materials() -> void:
	m_wall = _textured("res://assetss/tex/metal_panel.png", Color(1, 1, 1), 0.55, 0.82, 0.35)
	m_wall_b = _textured("res://assetss/tex/metal_dark.png", Color(1, 1, 1), 0.5, 0.88, 0.3)
	m_floor = _textured("res://assetss/tex/floor_grate.png", Color(1, 1, 1), 0.7, 0.7, 0.4)
	m_floor_wet = _textured("res://assetss/tex/floor_wet.png", Color(1, 1, 1), 0.6, 0.35, 0.55)
	m_hazard = _textured("res://assetss/tex/hazard_stripes.png", Color(1, 1, 1), 1.4, 0.85, 0.2)
	m_ceil = _mat(Color(0.05, 0.06, 0.06), 0.9)
	m_metal = _mat(Color(0.17, 0.19, 0.20), 0.72, 0.45)
	m_dark = _mat(Color(0.055, 0.06, 0.065), 0.9)
	m_white = _mat(Color(0.55, 0.55, 0.5), 0.85)
	m_crt = _emissive(Color(0.005, 0.03, 0.01), Color(0.05, 1.0, 0.14), 0.55)
	m_red = _emissive(Color(0.06, 0.005, 0.002), Color(1.0, 0.03, 0.008), 0.9)
	m_leak = _emissive(Color(0.05, 0.004, 0.002), Color(1.0, 0.04, 0.01), 0.45)
	m_work = _emissive(Color(0.20, 0.17, 0.12), Color(1.0, 0.80, 0.52), 0.55)
	m_glass = _build_glass_grime()


func _emissive(base: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	m.roughness = 0.7
	return m


# ------------------------------------------------- материалы кита (по именам) --

var _mat_cache: Dictionary = {}


func _kit_material(key: String) -> Material:
	if key == "" or _mat_cache.has(key):
		return _mat_cache.get(key, null) as Material
	var m: Material = null
	match key:
		"metal_panel":
			m = _textured("res://assetss/tex/metal_panel.png", Color(1, 1, 1), 0.55, 0.82, 0.35)
		"metal_dark":
			m = _textured("res://assetss/tex/metal_dark.png", Color(1, 1, 1), 0.5, 0.88, 0.3)
		"paint_worn":
			m = _textured("res://assetss/tex/metal_panel.png", Color(0.85, 0.84, 0.78), 0.65, 0.8, 0.25)
		"rust":
			m = _textured("res://assetss/tex/metal_panel.png", Color(0.62, 0.38, 0.24), 0.5, 0.9, 0.15)
		"hazard_y":
			m = _textured("res://assetss/tex/hazard_stripes.png", Color(1, 1, 1), 1.2, 0.85, 0.2)
		"hazard_k":
			m = _mat(Color(0.04, 0.04, 0.035), 0.9)
		"crt_green":
			m = _emissive(Color(0.005, 0.03, 0.01), Color(0.05, 1.0, 0.14), 0.55)
		"red_lamp":
			m = _emissive(Color(0.06, 0.005, 0.002), Color(1.0, 0.03, 0.008), 0.95)
		"lamp_cold":
			m = _emissive(Color(0.62, 0.72, 0.82), Color(0.48, 0.66, 0.95), 0.9)
		"wet_grime":
			m = _textured("res://assetss/tex/floor_wet.png", Color(0.55, 0.62, 0.68), 0.6, 0.22, 0.65)
		"glass_grime":
			m = m_glass
		"paint_red":
			m = _mat(Color(0.32, 0.05, 0.03), 0.85)
		_:
			m = null
	_mat_cache[key] = m
	return m


func _apply_kit_materials(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			var override := _kit_material(src.resource_name)
			if override != null:
				mi.set_surface_override_material(i, override)
	for child in node.get_children():
		_apply_kit_materials(child)


# ---------------------------------------------------------------- примитивы --

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _spawn(glb: String, pos: Vector3, rot_deg: Vector3, parent: Node3D,
		fallback_size: Vector3 = Vector3.ONE) -> Node3D:
	var scene: PackedScene = null
	if glb.begins_with("res://"):
		if ResourceLoader.exists(glb):
			scene = load(glb) as PackedScene
	else:
		var arch_path := ARCH + glb
		var equip_path := EQUIP + glb
		if ResourceLoader.exists(arch_path):
			scene = load(arch_path) as PackedScene
		elif ResourceLoader.exists(equip_path):
			scene = load(equip_path) as PackedScene
	if scene == null:
		missing.append(glb)
		var placeholder := _box(parent, fallback_size, pos, m_dark, rot_deg)
		placeholder.name = "MISSING_" + glb
		return placeholder
	var node := scene.instantiate() as Node3D
	node.position = pos
	node.rotation_degrees = rot_deg
	node.name = glb.get_basename().replace(".", "_")
	parent.add_child(node)
	_apply_kit_materials(node)
	return node


func _collider(size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	ship.add_child(body)


# ---------------------------------------------------------------- обшивка ---
# Внешняя «коробка» за модульными панелями: без неё в щели между панелями,
# плитками пола и потолком видно звёздное небо. Служит и тёмным фоном.

func _build_shell() -> void:
	var x0 := X_AIR_AFT - 0.2
	var x1 := X_BRIDGE_FWD + 0.2
	var mid_x := (x0 + x1) * 0.5
	var span := x1 - x0
	var mid_y := (FLOOR + CEIL) * 0.5
	# пол и потолок
	_box(ship, Vector3(span, 0.4, Z1 - Z0 + 0.6), Vector3(mid_x, FLOOR - 0.36, 11.9), m_wall_b)
	_box(ship, Vector3(span, 0.4, Z1 - Z0 + 0.6), Vector3(mid_x, CEIL + 0.34, 11.9), m_wall_b)
	# боковые стены (за панелями); левый борт с разрывом под каюту
	var shell_left := ROOM_DOOR_X - 1.0 - x0
	var shell_right := x1 - (ROOM_DOOR_X + 1.0)
	_box(ship, Vector3(shell_left, CEIL - FLOOR + 0.7, 0.3),
			Vector3((x0 + ROOM_DOOR_X - 1.0) * 0.5, mid_y, Z0 - 0.40), m_wall_b)
	_box(ship, Vector3(shell_right, CEIL - FLOOR + 0.7, 0.3),
			Vector3((ROOM_DOOR_X + 1.0 + x1) * 0.5, mid_y, Z0 - 0.40), m_wall_b)
	_box(ship, Vector3(span, CEIL - FLOOR + 0.7, 0.3), Vector3(mid_x, mid_y, Z1 + 0.40), m_wall_b)
	# кормовая стена за люком
	_box(ship, Vector3(0.24, CEIL - FLOOR + 0.7, Z1 - Z0 + 0.6),
			Vector3(X_AIR_AFT - 0.17, mid_y, 11.9), m_wall_b)
	# лобовая стена за панорамным окном не нужна: её роль играет переборка с окнами


# ---------------------------------------------------------------- коридор ----

func _build_corridor() -> void:
	var length := X_CORR_FWD - X_CORR_AFT
	var mid_x := (X_CORR_AFT + X_CORR_FWD) * 0.5

	# пол и потолок
	_collider(Vector3(length, 0.2, Z1 - Z0), Vector3(mid_x, FLOOR - 0.1, 11.9))
	_collider(Vector3(length, 0.2, Z1 - Z0), Vector3(mid_x, CEIL + 0.1, 11.9))
	var x := X_CORR_AFT + 1.0
	while x < X_CORR_FWD:
		var ft := _spawn("floor_tile.glb", Vector3(x, FLOOR - 0.008, 11.9), Vector3.ZERO, ship)
		ft.scale.z = 1.4
		var cp := _spawn("ceil_panel.glb", Vector3(x, CEIL + 0.012, 11.9), Vector3.ZERO, ship)
		cp.scale.z = 1.4
		x += 2.0

	# стены: панели 2 м, чередуем варианты
	_collider(Vector3(ROOM_DOOR_X - 1.0 - X_CORR_AFT, CEIL - FLOOR, 0.16),
			Vector3((X_CORR_AFT + ROOM_DOOR_X - 1.0) * 0.5, (FLOOR + CEIL) * 0.5, Z0 - 0.08))
	_collider(Vector3(X_CORR_FWD - (ROOM_DOOR_X + 1.0), CEIL - FLOOR, 0.16),
			Vector3((ROOM_DOOR_X + 1.0 + X_CORR_FWD) * 0.5, (FLOOR + CEIL) * 0.5, Z0 - 0.08))
	_collider(Vector3(length, CEIL - FLOOR, 0.16), Vector3(mid_x, (FLOOR + CEIL) * 0.5, Z1 + 0.08))
	x = X_CORR_AFT
	var i := 0
	while x < X_CORR_FWD:
		var panel := "wall_panel_a.glb" if i % 2 == 0 else "wall_panel_b.glb"
		# проём в каюту на x≈5: эту панель не ставим
		if absf((x + 1.0) - ROOM_DOOR_X) > 0.1:
			_spawn(panel, Vector3(x + 1.0, FLOOR, Z0), Vector3(0, 0, 0), ship)
		_spawn(panel, Vector3(x + 1.0, FLOOR, Z1), Vector3(0, 180, 0), ship)
		# хазард-полоса у пола
		_spawn("trim_hazard.glb", Vector3(x + 1.0, FLOOR + 0.12, Z0 + 0.02), Vector3.ZERO, ship,
				Vector3(2.0, 0.2, 0.05))
		_spawn("trim_hazard.glb", Vector3(x + 1.0, FLOOR + 0.12, Z1 - 0.02), Vector3(0, 180, 0), ship,
				Vector3(2.0, 0.2, 0.05))
		x += 2.0
		i += 1

	# труба и кабели под потолком
	_spawn("pipe_run.glb", Vector3(mid_x, CEIL - 0.28, Z0 + 0.3), Vector3(0, 90, 0), ship,
			Vector3(2.0, 0.1, 0.1))
	_spawn("cable_bundle.glb", Vector3(mid_x, CEIL - 0.22, Z1 - 0.3), Vector3(0, 90, 0), ship,
			Vector3(2.0, 0.12, 0.12))

	# потолочные плафоны
	x = X_CORR_AFT + 2.0
	while x < X_CORR_FWD:
		_spawn("ceil_light_fixture.glb", Vector3(x, CEIL, 11.9), Vector3.ZERO, ship,
				Vector3(1.2, 0.08, 0.2))
		x += 3.5

	# радио-тумба (шкафчик) у правой стены
	var cab_pos := Vector3(4.73, FLOOR, 13.02)
	_spawn("radio_cabinet.glb", cab_pos, Vector3(0, 180, 0), ship)
	_collider(Vector3(1.0, 0.85, 0.55), cab_pos + Vector3(0.0, 0.425, 0.0))
	_spawn("equip_mug.glb", Vector3(4.33, FLOOR + 0.852, 12.95), Vector3(0, -40, 0), ship,
			Vector3(0.1, 0.1, 0.1))
	# лампа под тумбой
	_box(ship, Vector3(0.9, 0.014, 0.03), Vector3(4.73, FLOOR + 0.72, 12.70), m_work)
	_omni(Vector3(4.73, FLOOR + 0.55, 12.45), Color(1.0, 0.78, 0.50), 0.62, 1.8, false)

	# переборка с дверью B-3
	_build_bulkhead_b3()


func _build_bulkhead_b3() -> void:
	var x := X_CORR_AFT
	# стена с проёмом 1.6 x 2.2
	_box(ship, Vector3(0.18, CEIL - FLOOR, 0.95), Vector3(x - 0.09, (FLOOR + CEIL) * 0.5, Z0 + 0.475), m_wall)
	_box(ship, Vector3(0.18, CEIL - FLOOR, 0.95), Vector3(x - 0.09, (FLOOR + CEIL) * 0.5, Z1 - 0.475), m_wall)
	_box(ship, Vector3(0.18, CEIL - FLOOR - 2.25, Z1 - Z0 - 1.9), Vector3(x - 0.09, CEIL - (CEIL - FLOOR - 2.25) * 0.5, 11.9), m_wall)
	_collider(Vector3(0.18, CEIL - FLOOR, 0.95), Vector3(x - 0.09, (FLOOR + CEIL) * 0.5, Z0 + 0.475))
	_collider(Vector3(0.18, CEIL - FLOOR, 0.95), Vector3(x - 0.09, (FLOOR + CEIL) * 0.5, Z1 - 0.475))
	_collider(Vector3(0.18, CEIL - FLOOR - 2.25, Z1 - Z0 - 1.9), Vector3(x - 0.09, CEIL - (CEIL - FLOOR - 2.25) * 0.5, 11.9))
	# рама и полотно двери
	_spawn("door_frame.glb", Vector3(x - 0.02, FLOOR, 11.9), Vector3(0, 90, 0), ship,
			Vector3(0.25, 2.4, 1.6))
	_spawn("door_b3.glb", Vector3(x + 0.05, FLOOR, 11.9), Vector3(0, 90, 0), ship,
			Vector3(0.1, 2.2, 1.4))
	# красная лампа над дверью
	_spawn("lamp_red.glb", Vector3(x + 0.2, CEIL, 11.9), Vector3.ZERO, ship,
			Vector3(0.16, 0.14, 0.14))
	# щель красного света из-под двери со стороны шлюза
	_box(ship, Vector3(0.012, 0.016, 1.28), Vector3(x - 0.215, FLOOR + 0.014, 11.9), m_leak)
	_omni(Vector3(x - 0.45, FLOOR + 0.22, 11.9), Color(1.0, 0.10, 0.045), 0.5, 1.35, false)


# ---------------------------------------------------------------- шлюз ------

func _build_airlock() -> void:
	var length := X_CORR_AFT - X_AIR_AFT
	var mid_x := (X_AIR_AFT + X_CORR_AFT) * 0.5
	_collider(Vector3(length, 0.2, Z1 - Z0), Vector3(mid_x, FLOOR - 0.1, 11.9))
	_collider(Vector3(length, 0.2, Z1 - Z0), Vector3(mid_x, CEIL + 0.1, 11.9))
	_collider(Vector3(length, CEIL - FLOOR, 0.16), Vector3(mid_x, (FLOOR + CEIL) * 0.5, Z0 - 0.08))
	_collider(Vector3(length, CEIL - FLOOR, 0.16), Vector3(mid_x, (FLOOR + CEIL) * 0.5, Z1 + 0.08))
	_collider(Vector3(0.2, CEIL - FLOOR, Z1 - Z0), Vector3(X_AIR_AFT - 0.1, (FLOOR + CEIL) * 0.5, 11.9))

	# новая комната шлюза: детальные модули (assetss/rooms/airlock_room)
	var room_x := (X_AIR_AFT + X_CORR_AFT) * 0.5
	_spawn("res://assetss/rooms/airlock_room/airlock_floor.glb",
			Vector3(room_x, FLOOR, 11.9), Vector3.ZERO, ship)
	_spawn("res://assetss/rooms/airlock_room/airlock_ceiling.glb",
			Vector3(room_x, CEIL, 11.9), Vector3.ZERO, ship)
	_spawn("res://assetss/rooms/airlock_room/airlock_wall_port.glb",
			Vector3(room_x, FLOOR, Z0), Vector3.ZERO, ship)
	_spawn("res://assetss/rooms/airlock_room/airlock_wall_stbd.glb",
			Vector3(room_x, FLOOR, Z1), Vector3(0, 180, 0), ship)
	_spawn("res://assetss/rooms/airlock_room/airlock_aft_frame.glb",
			Vector3(X_AIR_AFT, FLOOR + 1.1514, 11.9), Vector3(0, 90, 0), ship)
	_spawn("res://assetss/rooms/airlock_room/airlock_b3_frame.glb",
			Vector3(X_CORR_AFT, FLOOR + 1.2, 11.9), Vector3(0, -90, 0), ship)
	_spawn("res://assetss/rooms/airlock_room/airlock_details.glb",
			Vector3(room_x, FLOOR, 11.9), Vector3.ZERO, ship)
	# видимая створка круглого люка (в раму нового модуля)
	_spawn("airlock_door.glb", Vector3(X_AIR_AFT + 0.08, FLOOR + 1.1514, 11.9),
			Vector3(0, 90, 0), ship, Vector3(0.1, 1.9, 1.9))

	# начинка шлюза (assetss/rooms/airlock)
	_spawn("res://assetss/rooms/airlock/airlock_lockers.glb",
			Vector3(-6.3, FLOOR, 13.05), Vector3(0, 180, 0), ship)
	_spawn("res://assetss/rooms/airlock/airlock_console.glb",
			Vector3(-5.0, FLOOR, 10.72), Vector3.ZERO, ship)
	_spawn("res://assetss/rooms/airlock/airlock_bench.glb",
			Vector3(-6.35, FLOOR, 10.72), Vector3.ZERO, ship)
	_spawn("res://assetss/rooms/airlock/airlock_oxygen.glb",
			Vector3(-4.5, FLOOR, 13.02), Vector3(0, 180, 0), ship)
	_spawn("res://assetss/rooms/airlock/airlock_ceiling.glb",
			Vector3(room_x, CEIL - 0.25, 11.9), Vector3.ZERO, ship)
	_spawn("res://assetss/rooms/airlock/airlock_wall_details.glb",
			Vector3(-4.9, FLOOR + 1.1, 10.72), Vector3.ZERO, ship)
	_spawn("res://assetss/rooms/airlock/airlock_debris.glb",
			Vector3(-5.2, FLOOR + 0.002, 12.3), Vector3(0, 20, 0), ship)

	# коллизии мебели
	_collider(Vector3(1.61, 1.9, 0.47), Vector3(-6.3, FLOOR + 0.95, 13.05))
	_collider(Vector3(0.62, 0.88, 0.38), Vector3(-5.0, FLOOR + 0.44, 10.72))
	_collider(Vector3(1.24, 0.53, 0.51), Vector3(-6.35, FLOOR + 0.27, 10.72))
	_collider(Vector3(0.57, 1.15, 0.51), Vector3(-4.5, FLOOR + 0.58, 13.02))


# ---------------------------------------------------------------- мостик ----

func _build_bridge() -> void:
	var length := X_BRIDGE_FWD - X_CORR_FWD
	var mid_x := (X_CORR_FWD + X_BRIDGE_FWD) * 0.5
	_collider(Vector3(length, 0.2, Z_B1 - Z_B0), Vector3(mid_x, FLOOR - 0.1, 11.9))
	_collider(Vector3(length, 0.2, Z_B1 - Z_B0), Vector3(mid_x, CEIL + 0.1, 11.9))
	_collider(Vector3(length, CEIL - FLOOR, 0.16), Vector3(mid_x, (FLOOR + CEIL) * 0.5, Z_B0 - 0.08))
	_collider(Vector3(length, CEIL - FLOOR, 0.16), Vector3(mid_x, (FLOOR + CEIL) * 0.5, Z_B1 + 0.08))

	var x := X_CORR_FWD
	while x < X_BRIDGE_FWD - 0.5:
		var ft := _spawn("floor_tile.glb", Vector3(x + 1.0, FLOOR - 0.008, 11.9), Vector3.ZERO, ship)
		ft.scale.z = 1.4
		_spawn("wall_panel_a.glb", Vector3(x + 1.0, FLOOR, Z_B0), Vector3.ZERO, ship)
		_spawn("wall_panel_a.glb", Vector3(x + 1.0, FLOOR, Z_B1), Vector3(0, 180, 0), ship)
		x += 2.0

	# потолок мостика
	var cx := X_CORR_FWD
	while cx < X_BRIDGE_FWD - 0.2:
		var cp := _spawn("ceil_panel.glb", Vector3(cx + 1.0, CEIL + 0.012, 11.9), Vector3.ZERO, ship,
				Vector3(2.0, 0.12, 2.0))
		cp.scale.z = 1.4
		cx += 2.0

	# лобовая стена с панорамными окнами
	var win_bottom := 2.95
	var win_top := 4.50
	var front_x := X_BRIDGE_FWD - 0.1
	_box(ship, Vector3(0.18, win_bottom - FLOOR, Z_B1 - Z_B0), Vector3(front_x, (FLOOR + win_bottom) * 0.5, 11.9), m_wall_b)
	_box(ship, Vector3(0.18, CEIL - win_top, Z_B1 - Z_B0), Vector3(front_x, (win_top + CEIL) * 0.5, 11.9), m_wall_b)
	_collider(Vector3(0.18, win_bottom - FLOOR, Z_B1 - Z_B0), Vector3(front_x, (FLOOR + win_bottom) * 0.5, 11.9))
	_collider(Vector3(0.18, CEIL - win_top, Z_B1 - Z_B0), Vector3(front_x, (win_top + CEIL) * 0.5, 11.9))

	var z := Z_B0
	var pane_w := 0.62
	while z < Z_B1 - 0.3:
		var pane_z := z + pane_w
		if pane_z > Z_B1 - 0.3:
			pane_z = Z_B1 - 0.3
		# простенок
		_box(ship, Vector3(0.2, win_top - win_bottom, 0.16), Vector3(front_x, (win_bottom + win_top) * 0.5, z + 0.02), m_metal)
		# стекло
		var pane := _box(ship, Vector3(0.03, win_top - win_bottom, pane_z - z - 0.16), Vector3(front_x - 0.12,
				(win_bottom + win_top) * 0.5, (z + 0.08 + pane_z) * 0.5), m_glass)
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		z = pane_z + 0.14
	_box(ship, Vector3(0.2, win_top - win_bottom, 0.16), Vector3(front_x, (win_bottom + win_top) * 0.5, Z_B1 - 0.28), m_metal)

	# консоли: штурманский пост под окнами (экраны к камере) и пост у правого борта
	_spawn("console_section.glb", Vector3(13.55, FLOOR, 11.9), Vector3(0, -90, 0), ship)
	_collider(Vector3(1.0, 1.0, 1.7), Vector3(13.55, FLOOR + 0.5, 11.9))
	_spawn("console_section.glb", Vector3(11.35, FLOOR, 12.88), Vector3(0, 180, 0), ship)
	_collider(Vector3(1.7, 1.0, 1.0), Vector3(11.35, FLOOR + 0.5, 12.88))
	# клавиатура и кружка на полке штурманского поста
	_spawn("equip_keyboard.glb", Vector3(13.17, FLOOR + 0.678, 12.18), Vector3(0, -90, 0), ship,
			Vector3(0.45, 0.04, 0.16))
	_spawn("equip_mug.glb", Vector3(13.17, FLOOR + 0.674, 11.52), Vector3(0, 30, 0), ship,
			Vector3(0.1, 0.1, 0.1))
	# терминал у левого борта
	_spawn("crt_terminal.glb", Vector3(12.55, FLOOR, 10.72), Vector3(0, -71, 0), ship)
	# плакат
	_spawn("poster.glb", Vector3(10.6, FLOOR + 1.55, Z_B0 + 0.06), Vector3.ZERO, ship,
			Vector3(0.5, 0.7, 0.03))

	# красные лампы мостика
	for pos in [Vector3(X_CORR_FWD + 0.3, CEIL, Z_B0 + 0.2), Vector3(X_CORR_FWD + 0.3, CEIL, Z_B1 - 0.2),
			Vector3(X_BRIDGE_FWD - 0.5, CEIL, Z_B0 + 0.2), Vector3(X_BRIDGE_FWD - 0.5, CEIL, Z_B1 - 0.2)]:
		_spawn("lamp_red.glb", pos, Vector3.ZERO, ship, Vector3(0.16, 0.14, 0.14))


# ---------------------------------------------------------------- декор -----

func _build_props() -> void:
	# коридор: ящики, предупреждающая табличка, кабели
	_spawn("crate.glb", Vector3(-1.8, FLOOR, Z0 + 0.5), Vector3(0, 15, 0), ship)
	_spawn("crate_small.glb", Vector3(-2.3, FLOOR, Z0 + 0.35), Vector3(0, 55, 0), ship)
	_spawn("crate.glb", Vector3(7.8, FLOOR, Z1 - 0.6), Vector3(0, -12, 0), ship)
	_spawn("sign_warning.glb", Vector3(1.2, FLOOR + 1.5, Z0 + 0.12), Vector3(0, 0, 0), ship,
			Vector3(0.4, 0.4, 0.05))
	_spawn("poster.glb", Vector3(-2.9, FLOOR + 1.6, Z1 - 0.12), Vector3(0, 180, 0), ship,
			Vector3(0.5, 0.7, 0.03))
	_spawn("cable_bundle.glb", Vector3(-0.5, FLOOR + 0.05, Z1 - 0.35), Vector3(0, 20, 0), ship,
			Vector3(2.0, 0.12, 0.12))
	# бумаги на полу
	for i in 10:
		var px := rng.randf_range(X_CORR_AFT + 1.0, X_CORR_FWD - 1.0)
		var pz := rng.randf_range(Z0 + 0.5, Z1 - 0.5)
		_spawn("equip_papers.glb", Vector3(px, FLOOR + 0.01, pz), Vector3(0, rng.randf_range(0, 360), 0), ship,
				Vector3(0.3, 0.01, 0.4))
	# лампы аварийные в коридоре
	for lx in [-2.5, 6.5]:
		_spawn("lamp_red.glb", Vector3(lx, CEIL, 11.9), Vector3.ZERO, ship,
				Vector3(0.16, 0.14, 0.14))


func _build_lights() -> void:
	# Окружение: почти полная темнота, холодный зенит, туман глубины.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.003, 0.004, 0.006)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.19, 0.26, 0.36)
	e.ambient_light_energy = 0.23
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.30
	e.fog_enabled = true
	e.fog_light_color = Color(0.036, 0.052, 0.068)
	e.fog_density = 0.040
	e.fog_sky_affect = 0.0
	e.fog_aerial_perspective = 0.0
	env.environment = e
	world_env = env
	ship.add_child(env)

	# --- коридор: холодные конусы от плафонов, между ними темнота ---
	for lx in [-2.0, 1.5, 5.0, 8.5]:
		var s := _spot_down(Vector3(lx, CEIL - 0.04, 11.9), Color(0.62, 0.78, 1.0),
				4.2, 6.2, 52.0, true)
		s.spot_angle_attenuation = 1.15
	# красные аварийные лампы в коридоре — локальные пятна
	for lx in [-2.5, 6.5]:
		_omni(Vector3(lx, CEIL - 0.32, 11.9), Color(1.0, 0.10, 0.045), 0.80, 2.1, false)
	# лампа над B-3
	_omni(Vector3(-3.55, CEIL - 0.30, 11.9), Color(1.0, 0.07, 0.03), 2.0, 3.2, true)

	# --- шлюз: холодный свет, зелёный отсвет терминала ---
	_spot_down(Vector3(-6.1, CEIL - 0.04, 11.85), Color(0.55, 0.72, 0.96),
			3.6, 5.4, 46.0, true)
	_omni(Vector3(-4.62, FLOOR + 0.92, 11.18), Color(0.14, 1.0, 0.30), 0.28, 1.15, false)
	_omni(Vector3(-7.35, FLOOR + 1.35, 11.9), Color(0.45, 0.62, 0.90), 0.45, 1.9, false)
	_omni(Vector3(-7.15, FLOOR + 1.55, 12.75), Color(0.40, 0.55, 0.85), 0.60, 2.2, false)
	# подсветка закрытой двери B-3 со стороны шлюза
	_omni(Vector3(-4.78, FLOOR + 1.45, 12.45), Color(0.45, 0.62, 0.95), 0.95, 2.4, false)
	# конус на круглый люк
	var hatch := SpotLight3D.new()
	hatch.position = Vector3(-5.35, CEIL - 0.06, 11.9)
	hatch.rotation_degrees = Vector3(-31.0, 90.0, 0.0)
	hatch.light_color = Color(0.55, 0.72, 0.96)
	hatch.light_energy = 3.4
	hatch.spot_range = 5.2
	hatch.spot_angle = 33.0
	hatch.spot_angle_attenuation = 1.0
	hatch.shadow_enabled = true
	ship.add_child(hatch)

	# --- мостик: холодный верх, зелёные экраны, красные углы ---
	var bs1 := _spot_down(Vector3(10.85, CEIL - 0.04, 11.9), Color(0.60, 0.76, 1.0),
			4.2, 6.0, 42.0, true)
	bs1.spot_angle_attenuation = 1.15
	_spot_down(Vector3(14.05, CEIL - 0.04, 11.9), Color(0.58, 0.74, 1.0),
			1.8, 5.4, 42.0, false)
	for p in [Vector3(X_CORR_FWD + 0.3, CEIL - 0.30, Z_B0 + 0.25),
			Vector3(X_CORR_FWD + 0.3, CEIL - 0.30, Z_B1 - 0.25),
			Vector3(X_BRIDGE_FWD - 0.55, CEIL - 0.30, Z_B0 + 0.25),
			Vector3(X_BRIDGE_FWD - 0.55, CEIL - 0.30, Z_B1 - 0.25)]:
		_omni(p, Color(1.0, 0.07, 0.03), 0.55, 1.9, false)
	_omni(Vector3(13.25, FLOOR + 1.15, 11.9), Color(0.12, 1.0, 0.28), 0.36, 1.6, false)
	_omni(Vector3(12.25, FLOOR + 1.10, 10.98), Color(0.12, 1.0, 0.28), 0.34, 1.45, false)

	# холодный ключ из космоса через панорамные окна (тени дают полосы от рам)
	var key := SpotLight3D.new()
	key.position = Vector3(X_BRIDGE_FWD + 1.4, 4.35, 11.9)
	key.rotation_degrees = Vector3(-14.0, 90.0, 0.0)
	key.light_color = Color(0.42, 0.60, 1.0)
	key.light_energy = 2.7
	key.spot_range = 16.0
	key.spot_angle = 52.0
	key.spot_angle_attenuation = 0.8
	key.shadow_enabled = true
	ship.add_child(key)

	# верстак: местный подвесной свет и подсветка с коридора
	_spot_down(Vector3(4.45, CEIL - 0.04, 12.35), Color(0.78, 0.86, 1.0),
			5.0, 4.6, 46.0, true)
	_omni(Vector3(3.55, FLOOR + 1.45, 11.35), Color(0.70, 0.80, 1.0), 0.90, 2.4, false)
	# зелёный отсвет экрана на столешницу и стену
	_omni(Vector3(4.40, FLOOR + 1.35, 12.22), Color(0.10, 1.0, 0.20), 0.16, 1.1, false)


func _spot_down(pos: Vector3, color: Color, energy: float, range_m: float,
		angle_deg: float, shadow: bool) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = pos
	l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	l.light_color = color
	l.light_energy = energy
	l.spot_range = range_m
	l.spot_angle = angle_deg
	l.spot_attenuation = 1.0
	l.shadow_enabled = shadow
	if shadow:
		l.shadow_bias = 0.035
		l.shadow_normal_bias = 1.4
	ship.add_child(l)
	return l


func _omni(pos: Vector3, color: Color, energy: float, range_m: float,
		shadow: bool) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = range_m
	l.omni_attenuation = 1.15
	l.shadow_enabled = shadow
	ship.add_child(l)
	return l


func _shot(from: Vector3, to: Vector3, shot_name: String, shot_fov: float = 75.0) -> void:
	cam.fov = shot_fov
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/tune_%s.png" % [OUT, shot_name])
	img.save_png("%s/ship_%s.png" % [OUT, shot_name])
	print("saved ", shot_name)


# ---------------------------------------------------------------- стекло ----
# Грязное стекло: базовая мутная плёнка + пыль/царапины из текстуры +
# процедурные потёки сверху и грязь по краям у рам. Unshaded, чтобы на
# GL Compatibility стекло читалось как плёнка, а не как чёрный пластик.

const GLASS_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform sampler2D grime_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 dirt_color : source_color = vec3(0.20, 0.185, 0.16);
uniform float grime_scale = 1.3;
uniform float film = 0.035;
uniform float grime_gain = 0.40;
uniform float streak_gain = 0.07;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	vec4 g = texture(grime_tex, uv * grime_scale);
	float n = vnoise(uv * 9.0) * 0.55 + vnoise(uv * 27.0) * 0.30 + vnoise(uv * 61.0) * 0.15;
	float drip = smoothstep(0.55, 0.95, vnoise(vec2(uv.x * 30.0, uv.y * 1.4)));
	drip *= smoothstep(0.95, 0.10, uv.y);
	float edge = smoothstep(0.75, 1.0, max(abs(uv.x - 0.5), abs(uv.y - 0.5)) * 2.0);
	float patch = smoothstep(0.03, 0.30, g.a);
	float dirt = clamp(patch * 0.90 + n * 0.15 + drip * 0.28 + edge * 0.18, 0.0, 1.0);
	ALBEDO = dirt_color * (0.55 + 0.6 * dirt) + vec3(0.10) * pow(g.r, 2.0);
	ALPHA = clamp(film + dirt * grime_gain + drip * streak_gain, 0.0, 0.42);
}
"""


func _build_glass_grime() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = GLASS_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var tex := load("res://assetss/space/glass_grime.png") as Texture2D
	if tex != null:
		mat.set_shader_parameter("grime_tex", tex)
	return mat


# ---------------------------------------------------------------- космос ----

func _build_space() -> void:
	# панорама звёзд: только фон, интерьер не подсвечиваем
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	var pano_tex := load("res://assetss/space/starfield_pano.png") as Texture2D
	if pano_tex != null:
		pano.panorama = pano_tex
	pano.energy_multiplier = 0.75
	sky.sky_material = pano
	if world_env != null:
		var e := world_env.environment
		e.background_mode = Environment.BG_SKY
		e.sky = sky
		e.background_energy_multiplier = 1.0
		e.ambient_light_sky_contribution = 0.0

	# газовый гигант с кольцами: смещён вправо, в окне виден частично
	var gas_pos := Vector3(345.0, 6.0, 92.0)
	_space_sphere("res://assetss/space/planet_gas.png", gas_pos, 42.0)
	_space_ring(gas_pos, 210.0)
	# чёрная дыра: далеко слева, у края окна, притушена
	_space_billboard("res://assetss/space/planet_blackhole.png", Vector3(560.0, 13.5, -96.0),
			82.0, Color(0.40, 0.39, 0.46, 0.90))


func _space_sphere(tex_path: String, pos: Vector3, radius: float,
		tint: Color = Color(1, 1, 1, 1)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	mi.mesh = sphere
	var m := StandardMaterial3D.new()
	var tex := load(tex_path) as Texture2D
	if tex != null:
		m.albedo_texture = tex
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	m.disable_receive_shadows = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	mi.position = pos
	mi.scale = Vector3.ONE * radius
	ship.add_child(mi)
	return mi


func _space_ring(pos: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	var tex := load("res://assetss/space/planet_ring.png") as Texture2D
	if tex != null:
		m.albedo_texture = tex
	m.albedo_color = Color(0.62, 0.60, 0.65, 0.88)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = Vector3(74.0, 9.0, 5.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ship.add_child(mi)


func _space_billboard(tex_path: String, pos: Vector3, size: float,
		tint: Color = Color(1, 1, 1, 1)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	mi.mesh = quad
	var m := StandardMaterial3D.new()
	var tex := load(tex_path) as Texture2D
	if tex != null:
		m.albedo_texture = tex
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.disable_fog = true
	m.disable_receive_shadows = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ship.add_child(mi)
	return mi


# ---------------------------------------------------------------- каюта -----

func _build_quarters() -> void:
	var mid_z := (ROOM_Z0 + Z0) * 0.5
	var depth := Z0 - ROOM_Z0
	var mid_x := (ROOM_X0 + ROOM_X1) * 0.5

	# пол и потолок
	for tx in [4.0, 5.9]:
		var ft := _spawn("floor_tile.glb", Vector3(tx, FLOOR - 0.008, mid_z), Vector3.ZERO, ship)
		ft.scale.z = depth / 2.0
		var cp := _spawn("ceil_panel.glb", Vector3(tx, CEIL + 0.012, mid_z), Vector3.ZERO, ship)
		cp.scale.z = depth / 2.0

	# задняя и боковые стены
	for wx in [4.0, 5.8]:
		_spawn("wall_panel_a.glb", Vector3(wx, FLOOR, ROOM_Z0), Vector3.ZERO, ship)
	for wz in [8.2, 9.9]:
		_spawn("wall_panel_a.glb", Vector3(ROOM_X0, FLOOR, wz), Vector3(0, 90, 0), ship)
		_spawn("wall_panel_b.glb", Vector3(ROOM_X1, FLOOR, wz), Vector3(0, -90, 0), ship)

	# дверной проём
	_spawn("door_frame.glb", Vector3(ROOM_DOOR_X, FLOOR, Z0), Vector3.ZERO, ship)
	_box(ship, Vector3(0.12, CEIL - FLOOR, 0.2), Vector3(4.06, (FLOOR + CEIL) * 0.5, Z0), m_metal)
	_box(ship, Vector3(0.12, CEIL - FLOOR, 0.2), Vector3(5.94, (FLOOR + CEIL) * 0.5, Z0), m_metal)
	_box(ship, Vector3(2.0, 0.22, 0.2), Vector3(ROOM_DOOR_X, CEIL - 0.11, Z0), m_metal)

	# коллизии
	_collider(Vector3(ROOM_X1 - ROOM_X0 + 0.4, 0.2, depth + 0.4), Vector3(mid_x, FLOOR - 0.1, mid_z))
	_collider(Vector3(ROOM_X1 - ROOM_X0 + 0.4, 0.2, depth + 0.4), Vector3(mid_x, CEIL + 0.1, mid_z))
	_collider(Vector3(ROOM_X1 - ROOM_X0 + 0.4, CEIL - FLOOR, 0.16),
			Vector3(mid_x, (FLOOR + CEIL) * 0.5, ROOM_Z0 - 0.08))
	_collider(Vector3(0.16, CEIL - FLOOR, depth + 0.4),
			Vector3(ROOM_X0 - 0.08, (FLOOR + CEIL) * 0.5, mid_z))
	_collider(Vector3(0.16, CEIL - FLOOR, depth + 0.4),
			Vector3(ROOM_X1 + 0.08, (FLOOR + CEIL) * 0.5, mid_z))
	_collider(Vector3(2.0, CEIL - (FLOOR + 2.4), 0.16),
			Vector3(ROOM_DOOR_X, (FLOOR + 2.4 + CEIL) * 0.5, Z0))

	# внешняя оболочка
	_box(ship, Vector3(ROOM_X1 - ROOM_X0 + 0.9, 0.3, depth + 0.9),
			Vector3(mid_x, FLOOR - 0.28, mid_z), m_wall_b)
	_box(ship, Vector3(ROOM_X1 - ROOM_X0 + 0.9, 0.3, depth + 0.9),
			Vector3(mid_x, CEIL + 0.27, mid_z), m_wall_b)
	_box(ship, Vector3(ROOM_X1 - ROOM_X0 + 0.9, CEIL - FLOOR + 0.6, 0.3),
			Vector3(mid_x, (FLOOR + CEIL) * 0.5, ROOM_Z0 - 0.25), m_wall_b)
	_box(ship, Vector3(0.3, CEIL - FLOOR + 0.6, depth + 0.9),
			Vector3(ROOM_X0 - 0.25, (FLOOR + CEIL) * 0.5, mid_z), m_wall_b)
	_box(ship, Vector3(0.3, CEIL - FLOOR + 0.6, depth + 0.9),
			Vector3(ROOM_X1 + 0.25, (FLOOR + CEIL) * 0.5, mid_z), m_wall_b)

	# свет
	_spawn("ceil_light_fixture.glb", Vector3(ROOM_DOOR_X, CEIL, mid_z), Vector3.ZERO, ship,
			Vector3(1.2, 0.08, 0.2))
	_omni(Vector3(ROOM_DOOR_X, CEIL - 0.4, mid_z), Color(0.72, 0.84, 1.0), 2.0, 4.6, true)
	_omni(Vector3(ROOM_X0 + 0.5, CEIL - 0.5, 8.0), Color(1.0, 0.16, 0.07), 0.8, 2.6, false)
	print("quarters built")
