extends SceneTree

# Диагностика наложений/z-fighting в корабле: пары MeshInstance3D с пересекающимися
# world-AABB, раздельно «тонкие» (копланарные поверхности, риск мерцания) и «глубокие»
# (объекты реально входят друг в друга). Ничего не меняет в сцене.
# Запуск: godot --headless --path D:\4 --script res://.codex_qa/zfight/scan_overlaps.gd

const OUT := "res://.codex_qa/zfight"
const THIN := 0.03      # м: зазор/перекрытие по одной оси тоньше — риск z-fight
const DEEP := 0.05      # м: перекрытие по всем осям больше — реальное наложение
const MIN_AREA := 0.15  # м: две другие оси перекрытия не меньше — иначе это «уголок»

var items: Array = []
var main: Node3D


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	await process_frame
	await process_frame

	_collect(main, "")
	print("=== MESHES: ", items.size(), " ===")

	var thin_pairs: Array = []
	var deep_pairs: Array = []
	_grid_pairs(thin_pairs, deep_pairs)

	# дубли: одинаковый mesh-ассет и почти одинаковый transform
	var dupes: Array = []
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Dictionary = items[i]
			var b: Dictionary = items[j]
			if a["mesh"] == b["mesh"] and a["mesh"] != null:
				if a["pos"].distance_to(b["pos"]) < 0.01:
					dupes.append([a["path"], b["path"]])

	thin_pairs.sort_custom(func(a, b): return a["vol"] > b["vol"])
	deep_pairs.sort_custom(func(a, b): return a["vol"] > b["vol"])

	print("=== THIN (coplanar/z-fight candidates): ", thin_pairs.size(), " ===")
	for p in thin_pairs.slice(0, 25):
		print(p["a"], " <> ", p["b"], " overlap=", _v(p["ov"]), " axes=", p["axes"])
	print("=== DEEP (interpenetration): ", deep_pairs.size(), " ===")
	for p in deep_pairs.slice(0, 25):
		print(p["a"], " <> ", p["b"], " overlap=", _v(p["ov"]), " vol=", snappedf(p["vol"], 0.001))
	print("=== DUPES: ", dupes.size(), " ===")
	for d in dupes.slice(0, 15):
		print(d[0], " == ", d[1])

	var data := {
		"meshes": items.size(),
		"thin": thin_pairs,
		"deep": deep_pairs,
		"dupes": dupes,
	}
	var f := FileAccess.open(OUT + "/scan.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()
		print("saved ", OUT, "/scan.json")
	quit()


func _collect(node: Node, prefix: String) -> void:
	var path := prefix + "/" + String(node.name) if prefix != "" else String(node.name)
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			var aabb: AABB = mi.global_transform * mi.get_aabb()
			var mesh_id: Resource = mi.mesh
			items.append({
				"path": path,
				"aabb": aabb,
				"pos": aabb.get_center(),
				"mesh": mesh_id,
			})
	for c in node.get_children():
		_collect(c, path)


func _grid_pairs(thin_out: Array, deep_out: Array) -> void:
	var cell := 1.5
	var grid := {}
	for i in items.size():
		var aabb: AABB = items[i]["aabb"]
		var key := _cell_key(aabb.get_center(), cell)
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var k := Vector3i(key.x + dx, key.y + dy, key.z + dz)
					if not grid.has(k):
						continue
					for j in grid[k]:
						_compare(i, j, thin_out, deep_out)
		var k0 := _cell_key(aabb.get_center(), cell)
		if not grid.has(k0):
			grid[k0] = []
		grid[k0].append(i)


func _cell_key(p: Vector3, cell: float) -> Vector3i:
	return Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))


func _compare(i: int, j: int, thin_out: Array, deep_out: Array) -> void:
	var aabb_a: AABB = items[i]["aabb"]
	var aabb_b: AABB = items[j]["aabb"]
	if not aabb_a.intersects(aabb_b):
		return
	var inter: AABB = aabb_a.intersection(aabb_b)
	var o: Vector3 = inter.size
	var axes: Array = []
	if o.x < THIN and o.y > MIN_AREA and o.z > MIN_AREA:
		axes.append("x")
	if o.y < THIN and o.x > MIN_AREA and o.z > MIN_AREA:
		axes.append("y")
	if o.z < THIN and o.x > MIN_AREA and o.y > MIN_AREA:
		axes.append("z")
	var entry := {
		"a": items[i]["path"],
		"b": items[j]["path"],
		"ov": [snappedf(o.x, 0.001), snappedf(o.y, 0.001), snappedf(o.z, 0.001)],
		"axes": axes,
		"vol": o.x * o.y * o.z,
	}
	if axes.size() > 0:
		thin_out.append(entry)
	elif o.x > DEEP and o.y > DEEP and o.z > DEEP:
		deep_out.append(entry)


func _v(arr: Array) -> String:
	return "[%s, %s, %s]" % [arr[0], arr[1], arr[2]]
