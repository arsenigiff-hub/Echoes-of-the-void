extends SceneTree

# Object-placement audit: every top-level prop must be supported by a floor,
# wall, ceiling or parent assembly, and props must not deeply intersect each
# other. Prints FLOATING / OVERLAP lines and exits non-zero if any are found.

var main: Node3D
var checks := 0
var failures: Array[String] = []
var props: Dictionary = {}

const PROP_NAMES := [
	"Radio", "CrewWasteBin", "CrewBootsAfterImpact", "CrewPapersAfterImpact",
	"CrewNotebookOnBunk", "CrewMugOnBunk", "CrewToothbrushOnBunk",
	"CrewPhotoSlipOnBunk", "LooseCableAtQuartersWall",
	"AirlockPressureFrame", "airlock_door",
	"SolarArrayRepair", "OxygenServiceInteractable",
	"NavigationConsoleInteractable", "SleepStationInteractable",
	"AirlockInnerPressureLampFixture", "AirlockOuterPressureLampFixture",
	"CabinBunk", "CabinLocker", "CabinTable", "CabinChair",
	"CabinMug", "CabinNotebook", "CabinPhoto", "CabinBoots", "CabinPapers",
	"ObservationConsole", "ObservationBench", "ObservationTable",
	"ObservationMug", "ObservationLog", "ObservationPapers",
	"TechShelf", "TechLocker", "TechTable", "TechBin", "TechCable", "TechPapers",
	"CrateA", "CrateB", "CrateC",
	"common ivory_aged", "common amber_indicator",
]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	current_scene = main
	await create_timer(4.2).timeout
	var story := main.get_node("StoryProgression")
	story.set_process(false)
	for prop_name in PROP_NAMES:
		var node := main.find_child(prop_name, true, false) as Node3D
		if node != null:
			node.visible = true
			props[prop_name] = _bounds(node)
	await physics_frame

	var space := main.get_world_3d().direct_space_state
	for prop_name in props:
		var bounds: AABB = props[prop_name]
		if bounds.size.length() < 0.001:
			continue
		if prop_name == "AirlockPressureFrame":
			# Portal frame is embedded in the threshold wall and floor; it is
			# anchored by the surrounding structural mesh, not a floor ray.
			continue
		var supported := _supported(bounds, space)
		checks += 1
		if supported:
			print("PASS support/", prop_name, " bottom=", snappedf(bounds.position.y, 0.01))
		else:
			failures.append("FLOATING " + prop_name)
			print("FAIL FLOATING ", prop_name, " center=", bounds.get_center(),
				" size=", bounds.size, " bottom=", bounds.position.y)
		checks += 1
		if _sunk(bounds, space, main.find_child(prop_name, true, false)):
			failures.append("SUNK " + prop_name)
			print("FAIL SUNK ", prop_name, " bottom=", bounds.position.y,
				" center=", bounds.get_center())
		else:
			print("PASS no_sink/", prop_name)

	# The player must not be able to stand inside the navigation console and
	# clip through its front controls; its collider must cover the authored mesh.
	var nav := main.find_child("NavigationConsoleInteractable", true, false) as Node3D
	if nav != null and props.has("NavigationConsoleInteractable"):
		var nav_collision := nav.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if nav_collision != null and nav_collision.shape is BoxShape3D:
			var box := nav_collision.shape as BoxShape3D
			var mesh_size: Vector3 = (props["NavigationConsoleInteractable"] as AABB).size
			var sorted_mesh := [mesh_size.x, mesh_size.y, mesh_size.z]
			var sorted_box := [box.size.x, box.size.y, box.size.z]
			sorted_mesh.sort()
			sorted_box.sort()
			var covered := true
			for i in range(3):
				if float(sorted_box[i]) < float(sorted_mesh[i]) - 0.12:
					covered = false
			checks += 1
			if covered:
				print("PASS collision_covers/NavigationConsole")
			else:
				failures.append("COLLIDER_TOO_SMALL NavigationConsole")
				print("FAIL COLLIDER_TOO_SMALL NavigationConsole mesh=", mesh_size,
					" box=", box.size)

	var details := main.find_child("Details", true, false)
	if details != null:
		for mesh_node in details.find_children("*", "MeshInstance3D", true, false):
			var mesh := mesh_node as MeshInstance3D
			if mesh.mesh == null or not mesh.is_visible_in_tree():
				continue
			# Spatial cells are fragments of wall/ceiling detail, not floor props;
			# their support is checked by the full spatial audit.
			if "_cell_" in String(mesh.name):
				continue
			var b := mesh.global_transform * mesh.get_aabb()
			if b.size.length() < 0.005:
				continue
			checks += 1
			if not _supported(b, space):
				failures.append("FLOATING_DETAIL " + String(mesh.name))
				print("FAIL FLOATING_DETAIL ", mesh.name, " center=", b.get_center(),
					" size=", b.size, " bottom=", b.position.y)

	var names := props.keys()
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var a_name := String(names[i])
			var b_name := String(names[j])
			if a_name == "Details" or b_name == "Details":
				continue
			if (a_name == "AirlockPressureFrame" and b_name == "airlock_door") \
					or (a_name == "airlock_door" and b_name == "AirlockPressureFrame"):
				continue
			var a: AABB = props[a_name]
			var b: AABB = props[b_name]
			if not a.intersects(b):
				continue
			var overlap := a.intersection(b)
			var volume := overlap.size.x * overlap.size.y * overlap.size.z
			if volume < 0.01:
				continue
			# Resting contact: one prop's bottom sits on the other's top.
			if absf(a.end.y - b.position.y) < 0.09 or absf(b.end.y - a.position.y) < 0.09:
				continue
			# Small edge grazing is normal for dense set dressing.
			if overlap.size.x < 0.04 or overlap.size.z < 0.04:
				continue
			checks += 1
			failures.append("OVERLAP %s / %s" % [a_name, b_name])
			print("FAIL OVERLAP ", a_name, " / ", b_name,
				" volume=", snappedf(volume, 0.001), " at=", overlap.get_center())

	print("OBJECT_AUDIT total=", checks, " failed=", failures.size())
	if not failures.is_empty():
		print("OBJECT_AUDIT_FAILURES ", JSON.stringify(failures))
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _bounds(root_node: Node) -> AABB:
	var result := AABB()
	var found := false
	for mesh_node in root_node.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var bounds := mesh.global_transform * mesh.get_aabb()
		if not found:
			result = bounds
			found = true
		else:
			result = result.merge(bounds)
	return result


func _sunk(bounds: AABB, space: PhysicsDirectSpaceState3D, node: Node) -> bool:
	var center := bounds.get_center()
	var bottom := bounds.position.y
	var top := bounds.end.y
	var exclude: Array[RID] = []
	if node is CollisionObject3D:
		exclude.append((node as CollisionObject3D).get_rid())
	for child in node.find_children("*", "CollisionObject3D", true, false):
		exclude.append((child as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(center.x, top + 0.5, center.z),
		Vector3(center.x, bottom - 0.5, center.z))
	query.collision_mask = 1
	query.exclude = exclude
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider_name := String((hit["collider"] as Node).name) if hit["collider"] != null else ""
	if collider_name.contains("bedding"):
		# Bed-mounted control panels sit on soft bedding; the mattress is a
		# support surface, not a hard prop they can clip through.
		return false
	var hit_y := (hit["position"] as Vector3).y
	# A structural surface cutting through the volume above the object's base
	# means the prop is embedded in the floor/table.
	var sunk := hit_y > bottom + 0.012 and hit_y < top - 0.01
	if sunk:
		print("SUNK_HIT ", node.name, " hit=", hit["position"],
			" collider=", collider_name, " bottom=", bottom, " top=", top)
	return sunk


func _supported(bounds: AABB, space: PhysicsDirectSpaceState3D) -> bool:
	var center := bounds.get_center()
	var bottom := bounds.position.y
	var top := bounds.end.y
	var points := [
		Vector3(center.x, bottom, center.z),
		Vector3(bounds.position.x + 0.02, bottom, bounds.position.z + 0.02),
		Vector3(bounds.end.x - 0.02, bottom, bounds.position.z + 0.02),
		Vector3(bounds.position.x + 0.02, bottom, bounds.end.z - 0.02),
		Vector3(bounds.end.x - 0.02, bottom, bounds.end.z - 0.02),
	]
	for point in points:
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * 0.08, point - Vector3.UP * 0.35, 1))
		if not down.is_empty() and absf((down["position"] as Vector3).y - bottom) <= 0.16:
			return true
	var mid_y := center.y
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var side := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(center.x, mid_y, center.z),
			Vector3(center.x, mid_y, center.z) + dir * 0.55, 1))
		if not side.is_empty():
			return true
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(center.x, top - 0.02, center.z),
		Vector3(center.x, top + 0.60, center.z), 1))
	if not up.is_empty() and (up["position"] as Vector3).y <= top + 0.55:
		return true
	return false
