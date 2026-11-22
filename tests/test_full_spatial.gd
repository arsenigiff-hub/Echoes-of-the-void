extends SceneTree
## Full positional / collision / support audit of the current main scene.
## Saves full_meshes.json, full_shapes.json, full_audit.json and prints a summary.

const OUT := "res://.codex_qa/qa_spatial"
const PROP_NAMES := [
	"CabinBunk", "CabinLocker", "CabinTable", "CabinChair", "CabinPipes",
	"CabinMug", "CabinNotebook", "CabinPhoto", "CabinBoots", "CabinPapers",
	"ObservationConsole", "ObservationBench", "ObservationTable", "ObservationVent",
	"ObservationMug", "ObservationLog", "ObservationPapers",
	"TechShelf", "TechLocker", "TechTable", "TechBin", "TechPipes",
	"TechCable", "TechPapers", "HallVent", "HallPipes",
	"CrateA", "CrateB", "CrateC",
]

var main: Node3D
var interior: Node3D
var upper: Node3D
var rooms: Node3D
var player: CharacterBody3D
var space: PhysicsDirectSpaceState3D
var upper_body: StaticBody3D
var meshes: Array = []
var shapes: Array = []
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	await create_timer(5.0).timeout
	interior = main.get_node("ShipInterior") as Node3D
	upper = interior.get_node("UpperDeck") as Node3D
	rooms = interior.get_node("Rooms") as Node3D
	player = main.get_node("Player") as CharacterBody3D
	space = main.get_world_3d().direct_space_state
	upper_body = upper.get_node("UpperDeckCollision") as StaticBody3D

	_collect_meshes(interior, "ShipInterior")
	_collect_shapes(interior, "ShipInterior")
	_write_json("full_meshes.json", {"meshes": meshes})
	_write_json("full_shapes.json", {"shapes": shapes})
	print("FULL_MESHES=", meshes.size(), " FULL_SHAPES=", shapes.size())

	_audit_props()
	_audit_signs()
	_audit_counter()
	_audit_barriers()
	_room_floors()
	_capsule_grids()
	_pair_scan()
	for failure in failures:
		print("FULL_FAIL: ", failure)
	print("FULL_AUDIT_FAILURES=", failures.size())
	_write_json("full_audit.json", {
		"meshes": meshes.size(), "shapes": shapes.size(), "failures": failures,
	})
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _collect_meshes(node: Node, prefix: String) -> void:
	var path := prefix + "/" + String(node.name)
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and not _inside_subviewport(mi) and mi.is_visible_in_tree():
			var box: AABB = mi.global_transform * mi.get_aabb()
			var mats: Array = []
			for surface in mi.mesh.get_surface_count():
				var mat := mi.get_surface_override_material(surface)
				if mat == null:
					mat = mi.mesh.surface_get_material(surface)
				if mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					mats.append("%s(cull=%d,transp=%d)" % [sm.resource_name, sm.cull_mode, sm.transparency])
				else:
					mats.append(str(mat) if mat != null else "null")
			meshes.append({"path": path, "pos": box.get_center(), "aabb": [box.position, box.size],
				"materials": mats})
	for child in node.get_children():
		_collect_meshes(child, path)


func _collect_shapes(node: Node, prefix: String) -> void:
	var path := prefix + "/" + String(node.name)
	if node is CollisionShape3D:
		var cs := node as CollisionShape3D
		var kind := "?"
		var size := Vector3.ZERO
		if cs.shape is BoxShape3D:
			kind = "box"
			size = (cs.shape as BoxShape3D).size
		elif cs.shape is CapsuleShape3D:
			kind = "capsule"
			size = Vector3((cs.shape as CapsuleShape3D).radius, (cs.shape as CapsuleShape3D).height, 0)
		elif cs.shape is SphereShape3D:
			kind = "sphere"
			size = Vector3.ONE * (cs.shape as SphereShape3D).radius
		shapes.append({"path": path, "owner": String(cs.get_parent().get_path()),
			"kind": kind, "size": size, "pos": cs.global_position,
			"disabled": cs.disabled})
	for child in node.get_children():
		_collect_shapes(child, path)


func _audit_props() -> void:
	print("=== PROPS ===")
	var aabbs := {}
	for prop_name in PROP_NAMES:
		var node := _find_recursive(interior, prop_name)
		if node == null:
			print("PROP_MISSING ", prop_name)
			continue
		var box := _bounds_world(node)
		aabbs[prop_name] = box
		var gap := _floor_gap(box)
		var supported := _supported(node, box)
		print("PROP %s aabb=%s floor_gap=%.3f supported=%s" % [prop_name, box, gap, supported])
		if not supported:
			failures.append("FLOATING " + prop_name + " gap=" + str(gap))
	var keys := aabbs.keys()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var an: String = keys[i]
			var bn: String = keys[j]
			var a: AABB = aabbs[an]
			var b: AABB = aabbs[bn]
			if not a.intersects(b):
				continue
			var ov := a.intersection(b)
			var vol := ov.size.x * ov.size.y * ov.size.z
			if vol > 0.004:
				print("PROP_OVERLAP %s / %s vol=%.4f at=%s" % [an, bn, vol, ov.get_center()])
				failures.append("OVERLAP " + an + "/" + bn)


func _audit_signs() -> void:
	print("=== SIGNS ===")
	var idx := 0
	for mi in upper.find_children("*", "MeshInstance3D", true, false):
		var mesh := mi as MeshInstance3D
		if mesh.mesh is TextMesh:
			var tm := mesh.mesh as TextMesh
			var mat := mesh.material_override as StandardMaterial3D
			print("SIGN[%d] text=%s pos=%s rot=%s cull=%s aabb=%s" % [
				idx, tm.text, mesh.position, mesh.rotation_degrees,
				str(mat.cull_mode) if mat != null else "?", mesh.get_aabb()])
			idx += 1


func _audit_counter() -> void:
	print("=== COUNTER ===")
	for label in ["common ivory_aged", "common amber_indicator", "common structural_graphite"]:
		var node := rooms.find_child(label, true, false) as Node3D
		if node == null or not node.is_visible_in_tree():
			continue
		var box := _bounds_world(node)
		print("COUNTER %s aabb=%s floor_gap=%.3f supported=%s" % [
			label, box, _floor_gap(box), _supported(node, box)])


func _audit_barriers() -> void:
	print("=== BARRIERS ===")
	var idx := 0
	for child in upper_body.get_children():
		if child is CollisionShape3D:
			var cs := child as CollisionShape3D
			var size := (cs.shape as BoxShape3D).size if cs.shape is BoxShape3D else Vector3.ZERO
			print("BARRIER[%d] pos=%s size=%s" % [idx, cs.position, size])
			idx += 1


func _room_floors() -> void:
	print("=== ROOM FLOORS ===")
	for label in ["common", "airlock", "quarters", "passage"]:
		var node := rooms.find_child(label + " structural_graphite", true, false) as Node3D
		if node == null:
			continue
		var box := _bounds_in(node, rooms)
		var holes := 0
		var samples := 0
		var x := box.position.x + 0.35
		while x <= box.end.x - 0.35:
			var z := box.position.z + 0.35
			while z <= box.end.z - 0.35:
				samples += 1
				var hit := _ray_world(rooms.to_global(Vector3(x, 2.0, z)),
					rooms.to_global(Vector3(x, -1.0, z)))
				if hit.is_empty() or (hit["position"] as Vector3).y < rooms.to_global(Vector3(0, -0.2, 0)).y:
					holes += 1
				z += 0.5
			x += 0.5
		print("ROOM %s samples=%d holes=%d" % [label, samples, holes])
	# upper floors: sample each floor node AABB
	for label in ["CabinFloor", "ObservationFloor", "TechFloor", "BackWalkway", "EastWalkway"]:
		var node := upper.find_child(label, true, false) as Node3D
		if node == null:
			continue
		var box := _bounds_in(node, upper)
		var holes := 0
		var samples := 0
		var x := box.position.x + 0.2
		while x <= box.end.x - 0.2:
			var z := box.position.z + 0.2
			while z <= box.end.z - 0.2:
				samples += 1
				var hit := _ray_world(upper.to_global(Vector3(x, 4.0, z)),
					upper.to_global(Vector3(x, 1.0, z)))
				if hit.is_empty():
					holes += 1
				z += 0.5
			x += 0.5
		print("ROOM %s samples=%d holes=%d" % [label, samples, holes])


func _capsule_grids() -> void:
	print("=== CAPSULE GRIDS ===")
	_capsule_room("lower_common", rooms.find_child("common structural_graphite", true, false) as Node3D, rooms)
	_capsule_room("lower_airlock", rooms.find_child("airlock structural_graphite", true, false) as Node3D, rooms)
	_capsule_room("lower_quarters", rooms.find_child("quarters structural_graphite", true, false) as Node3D, rooms)
	_capsule_room("upper_cabin", upper.find_child("CabinFloor", true, false) as Node3D, upper)
	_capsule_room("upper_observation", upper.find_child("ObservationFloor", true, false) as Node3D, upper)
	_capsule_room("upper_tech", upper.find_child("TechFloor", true, false) as Node3D, upper)


func _capsule_room(label: String, node: Node3D, frame: Node3D) -> void:
	if node == null:
		return
	var box := _bounds_in(node, frame)
	var x := box.position.x + 0.35
	while x <= box.end.x - 0.35:
		var z := box.position.z + 0.35
		var row := ""
		while z <= box.end.z - 0.35:
			var hit := _ray_world(frame.to_global(Vector3(x, 4.0, z)),
				frame.to_global(Vector3(x, -1.0, z)))
			if hit.is_empty():
				row += " "
			else:
				var floor_y := frame.to_local(hit["position"] as Vector3).y
				var center := frame.to_global(Vector3(x, floor_y + 0.95, z))
				var q := PhysicsShapeQueryParameters3D.new()
				var shape := CapsuleShape3D.new()
				shape.radius = 0.38
				shape.height = 1.82
				q.shape = shape
				q.transform = Transform3D(Basis(), center)
				q.collision_mask = 1
				q.exclude = [player.get_rid()]
				row += "#" if not space.intersect_shape(q, 1).is_empty() else "."
			z += 0.5
		print("CAP %-18s %s" % [label, row])
		x += 0.5


func _pair_scan() -> void:
	print("=== UPPER/NEW PAIRS ===")
	var items: Array = []
	for m in meshes:
		var p: String = m["path"]
		if p.contains("UpperDeck") or p.contains("Details") or p.contains("common ivory") \
				or p.contains("common amber") or p.contains("Crate"):
			var aabb_arr: Array = m["aabb"]
			items.append({"path": p, "aabb": AABB(aabb_arr[0], aabb_arr[1])})
	var thin := 0
	var deep := 0
	for i in range(items.size()):
		for j in range(i + 1, items.size()):
			var a: AABB = items[i]["aabb"]
			var b: AABB = items[j]["aabb"]
			if not a.intersects(b):
				continue
			var ov := a.intersection(b)
			var o := ov.size
			var vol := o.x * o.y * o.z
			if vol < 0.004:
				continue
			var is_thin := (o.x < 0.03 and o.y > 0.15 and o.z > 0.15) \
				or (o.y < 0.03 and o.x > 0.15 and o.z > 0.15) \
				or (o.z < 0.03 and o.x > 0.15 and o.y > 0.15)
			if is_thin:
				thin += 1
				print("PAIR_THIN %s <> %s ov=%s" % [items[i]["path"], items[j]["path"], o])
			elif o.x > 0.05 and o.y > 0.05 and o.z > 0.05:
				deep += 1
				if deep <= 80:
					print("PAIR_DEEP %s <> %s ov=%s vol=%.4f" % [
						items[i]["path"], items[j]["path"], o, vol])
	print("PAIR_SUMMARY thin=", thin, " deep=", deep)


func _find_recursive(root_node: Node, wanted: String) -> Node:
	if String(root_node.name) == wanted:
		return root_node
	for child in root_node.get_children():
		var found := _find_recursive(child, wanted)
		if found != null:
			return found
	return null


func _bounds_world(root_node: Node) -> AABB:
	var result := AABB()
	var found := false
	var nodes: Array = []
	if root_node is MeshInstance3D:
		nodes.append(root_node)
	nodes += root_node.find_children("*", "MeshInstance3D", true, false)
	for node in nodes:
		var mi := node as MeshInstance3D
		if mi.mesh == null or _inside_subviewport(mi):
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		if not found:
			result = box
			found = true
		else:
			result = result.merge(box)
	return result


func _bounds_in(root_node: Node, relative_to: Node3D) -> AABB:
	var result := AABB()
	var found := false
	var nodes: Array = []
	if root_node is MeshInstance3D:
		nodes.append(root_node)
	nodes += root_node.find_children("*", "MeshInstance3D", true, false)
	for node in nodes:
		var mi := node as MeshInstance3D
		if mi.mesh == null or _inside_subviewport(mi):
			continue
		var box: AABB = (relative_to.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		if not found:
			result = box
			found = true
		else:
			result = result.merge(box)
	return result


func _floor_gap(box: AABB) -> float:
	var center := box.get_center()
	var hit := _ray_world(Vector3(center.x, box.position.y + 0.05, center.z),
		Vector3(center.x, box.position.y - 1.0, center.z))
	if hit.is_empty():
		return 999.0
	return box.position.y - (hit["position"] as Vector3).y


func _supported(node: Node3D, box: AABB) -> bool:
	var center := box.get_center()
	var bottom := box.position.y
	var top := box.end.y
	var ex: Array[RID] = []
	for body in node.find_children("*", "CollisionObject3D", true, false):
		ex.append((body as CollisionObject3D).get_rid())
	if node is CollisionObject3D:
		ex.append((node as CollisionObject3D).get_rid())
	var points := [
		Vector3(center.x, bottom, center.z),
		Vector3(box.position.x + 0.02, bottom, box.position.z + 0.02),
		Vector3(box.end.x - 0.02, bottom, box.position.z + 0.02),
		Vector3(box.position.x + 0.02, bottom, box.end.z - 0.02),
		Vector3(box.end.x - 0.02, bottom, box.end.z - 0.02),
	]
	for p in points:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.08, p - Vector3.UP * 0.40)
		q.collision_mask = 1
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf((hit["position"] as Vector3).y - bottom) <= 0.16:
			return true
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var q2 := PhysicsRayQueryParameters3D.create(center, center + dir * 0.55)
		q2.collision_mask = 1
		q2.exclude = ex
		if not space.intersect_ray(q2).is_empty():
			return true
	var q3 := PhysicsRayQueryParameters3D.create(Vector3(center.x, top - 0.02, center.z),
		Vector3(center.x, top + 0.60, center.z))
	q3.collision_mask = 1
	q3.exclude = ex
	var up := space.intersect_ray(q3)
	return not up.is_empty()


func _ray_world(a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	q.exclude = [player.get_rid()]
	return space.intersect_ray(q)


func _inside_subviewport(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is SubViewport:
			return true
		parent = parent.get_parent()
	return false


func _write_json(file_name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f := FileAccess.open(OUT + "/" + file_name, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()

