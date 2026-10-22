extends Node

# «Экранный дрессер» мостика: навешивает emissive-квады с CRT-текстурами на
# светящиеся экраны модулей console_section и crt_terminal.
#
# Зачем в рантайме: внутренние материалы GLB-инстансов при сохранении
# ship_interior.tscn теряются, поэтому текстуру на экран не назначить в сцене.
#
# Квады кладутся чуть перед плоскостью экрана (выше выступающей рамки) и
# повторяют её наклон. Локальные координаты плоскостей сняты с геометрии
# GLB-модулей (меш console_section/console_section и crt_terminal/crt_terminal).

const QUAD_PREFIX := "ScreenQuad"
# Экран утоплен в корпус: рамка/козырёк выступает над плоскостью crt_green
# на ~25 мм у консоли и ~34 мм у терминала. Квад ставим чуть выше рамки,
# иначе он прячется внутри корпуса.
const CONSOLE_OFFSET := 0.03
const TERMINAL_OFFSET := 0.04

const CONSOLE_TEXTURES: Array[Texture2D] = [
	preload("res://assetss/tex_gemini/crt/crt_telemetry.png"),
	preload("res://assetss/tex_gemini/crt/crt_waveform.png"),
	preload("res://assetss/tex_gemini/crt/crt_systems.png"),
]
const TERMINAL_TEXTURE: Texture2D = preload("res://assetss/tex_gemini/crt/crt_radar.png")

# console_section: три экрана-секции в одной наклонной плоскости.
# Центры панелей (локально): X = -0.48 / 0 / +0.48, Y/Z — центр передней грани.
const CONSOLE_FACE_CENTERS: Array[Vector3] = [
	Vector3(-0.48, 0.896736, -0.058665),
	Vector3(0.0, 0.896736, -0.058665),
	Vector3(0.48, 0.896736, -0.058665),
]
# Нормаль передней грани (наружу, в кабину) и «верх» экрана.
const CONSOLE_FACE_NORMAL := Vector3(0.0, 0.888327, 0.459561)
const CONSOLE_FACE_UP := Vector3(0.0, 0.459561, -0.888327)
const CONSOLE_QUAD_SIZE := Vector2(0.45, 0.28)

# crt_terminal: один экран, почти вертикальный, слегка наклонён назад.
const TERMINAL_FACE_CENTER := Vector3(0.0, 0.848827, 0.232343)
const TERMINAL_FACE_NORMAL := Vector3(0.0, 0.099504, 0.995037)
const TERMINAL_FACE_UP := Vector3(0.0, 0.995037, -0.099504)
const TERMINAL_QUAD_SIZE := Vector2(0.40, 0.30)

# Ключи модулей, внутри которых ищем меши экранов.
const MODULE_KEYS: Array[String] = ["console_section", "crt_terminal", "wall_panel"]

# Один материал на текстуру — переиспользуем между квадами.
var _materials: Dictionary = {}


func _ready() -> void:
	# Даём сцене доинстанцироваться (GLB-инстансы появляются при загрузке).
	await get_tree().process_frame

	var interior := get_parent().get_node_or_null("ShipInterior")
	if interior == null:
		push_warning("ScreenDresser: узел ShipInterior не найден, экраны не одеты")
		return

	var meshes: Array[Node] = []
	_collect_screen_meshes(interior, meshes)
	for mesh_node in meshes:
		_dress_mesh(mesh_node as MeshInstance3D)


# Рекурсивно собирает MeshInstance3D, у которых имя или имя родителя содержит
# ключ модуля (console_section / crt_terminal / wall_panel).
func _collect_screen_meshes(node: Node, out: Array[Node]) -> void:
	# Квады-экраны сами по себе не модули: иначе повторный вызов одевал бы их.
	if node.name.begins_with(QUAD_PREFIX):
		return
	if node is MeshInstance3D:
		var kind := _module_kind(node)
		# wall_panel_b содержит лишь маленький индикатор 0.26x0.1 — это не экран,
		# поэтому стены не заклеиваем CRT-квадами.
		if kind != "" and kind != "wall_panel":
			out.append(node)
	for child in node.get_children():
		_collect_screen_meshes(child, out)


func _module_kind(node: Node) -> String:
	var current: Node = node
	var depth := 0
	while current != null and depth < 4:
		var node_name := current.name.to_lower()
		for key in MODULE_KEYS:
			if node_name.contains(key):
				return key
		current = current.get_parent()
		depth += 1
	return ""


func _dress_mesh(mesh_node: MeshInstance3D) -> void:
	var kind := _module_kind(mesh_node)
	if kind == "console_section":
		_dress_console(mesh_node)
	elif kind == "crt_terminal":
		_dress_terminal(mesh_node)


func _dress_console(mesh_node: MeshInstance3D) -> void:
	for i in CONSOLE_FACE_CENTERS.size():
		var texture: Texture2D = CONSOLE_TEXTURES[i % CONSOLE_TEXTURES.size()]
		_spawn_quad(mesh_node, i, CONSOLE_FACE_CENTERS[i],
			CONSOLE_FACE_NORMAL, CONSOLE_FACE_UP, CONSOLE_QUAD_SIZE, texture, CONSOLE_OFFSET)


func _dress_terminal(mesh_node: MeshInstance3D) -> void:
	_spawn_quad(mesh_node, 0, TERMINAL_FACE_CENTER,
		TERMINAL_FACE_NORMAL, TERMINAL_FACE_UP, TERMINAL_QUAD_SIZE, TERMINAL_TEXTURE, TERMINAL_OFFSET)


# Создаёт один квад-экран. Повторный вызов не плодит дубликаты: имя
# ScreenQuad_<i> проверяется у родителя.
func _spawn_quad(parent: MeshInstance3D, index: int, center: Vector3,
		normal: Vector3, up: Vector3, size: Vector2, texture: Texture2D,
		offset: float) -> void:
	var quad_name := "%s_%d" % [QUAD_PREFIX, index]
	if parent.get_node_or_null(quad_name) != null:
		return

	var quad := QuadMesh.new()
	quad.size = size

	var screen := MeshInstance3D.new()
	screen.name = quad_name
	screen.mesh = quad
	screen.material_override = _screen_material(texture)
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	screen.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	var n := normal.normalized()
	var u := up.normalized()
	var right := u.cross(n).normalized()
	u = n.cross(right).normalized()
	screen.transform = Transform3D(Basis(right, u, n), center + n * offset)

	parent.add_child(screen)


# Материал экрана: unshaded + albedo/emission-текстура, без тумана и теней.
func _screen_material(texture: Texture2D) -> StandardMaterial3D:
	if _materials.has(texture):
		return _materials[texture] as StandardMaterial3D

	var mat := StandardMaterial3D.new()
	mat.resource_name = "screen_%s" % texture.resource_path.get_file().get_basename()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.albedo_texture = texture
	mat.emission_enabled = true
	mat.emission_texture = texture
	mat.emission = Color(0.55, 1.0, 0.7)
	mat.emission_energy_multiplier = 1.2
	mat.disable_fog = true
	mat.disable_receive_shadows = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	_materials[texture] = mat
	return mat
