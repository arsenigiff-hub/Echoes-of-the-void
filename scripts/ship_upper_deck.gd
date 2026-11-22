extends Node3D
## Production upper deck for ECHOES OF THE VOID.
## Sits in the local space of ship_interior_b.tscn on top of the existing lower
## deck. Reuses the old ship's wall/pixel palette and its furniture models.
## The GLB on disk is untouched: only the common-room ceiling over the atrium
## and stair opening is removed at runtime.

const BUNK := preload("res://assetss/rooms/quarters/bunk_bed.glb")
const LOCKER := preload("res://assetss/rooms/quarters/locker.glb")
const SHELF := preload("res://assetss/rooms/quarters/shelf_rack.glb")
const TABLE := preload("res://assetss/rooms/quarters/table_small.glb")
const CHAIR := preload("res://assetss/rooms/quarters/chair_folded.glb")
const NAV_CONSOLE := preload("res://assetss/rooms/navigation_console/navigation_console_v2.glb")
const BENCH := preload("res://assetss/rooms/airlock/airlock_bench.glb")
const TRASH := preload("res://assetss/ship_clutter_external/trash_bin_lowpoly.glb")
const PIPES := preload("res://assetss/rooms/quarters/wall_pipes_small.glb")
const VENT := preload("res://assetss/rooms/quarters/vent_grille.glb")
const PAPERS := preload("res://assetss/rooms/quarters/papers_scattered.glb")
const MUG := preload("res://assetss/rooms/quarters/personal_mug.glb")
const NOTEBOOK := preload("res://assetss/rooms/quarters/personal_notebook.glb")
const PHOTO := preload("res://assetss/rooms/quarters/personal_photo_a.glb")
const BOOTS := preload("res://assetss/rooms/quarters/personal_boots.glb")
const CABLE := preload("res://assetss/rooms/quarters/cable_bundle_floor.glb")

const OLD_CEIL := 2.60
const FLOOR := 2.82
const CEIL := 5.42
const ROOF := 5.62
const SLAB := 2.62
const WALL_T := 0.12
const X0 := -4.10
const X1 := 0.0
const TECH_X1 := 4.50
const TECH_Z0 := -2.70
const CABIN_Z1 := 4.0
const HALL_Z0 := -4.0
const OBS_Z0 := -8.0
const ATRIUM_X0 := -3.10
const ATRIUM_X1 := -1.00
const ATRIUM_Z0 := -3.00
const ATRIUM_Z1 := 0.0
const STEP_COUNT := 13
const STAIR_RUN := 3.00
const STAIR_RISE := FLOOR

var roof_nodes: Array = []
var _materials := {}
var _collision_shapes: Array[CollisionShape3D] = []
var _window_viewport: SubViewport
var _window_camera: Camera3D
var _window_planet: MeshInstance3D
var _window_ring: MeshInstance3D
var _window_blackhole: MeshInstance3D
var _window_tween: Tween
var _window_time := 0.0


func _ready() -> void:
	_relocate_common_counter()
	_cut_stair_notch()
	_cut_stair_door()
	_cut_old_ceiling()
	_build_floors()
	_build_walls()
	_build_stairs()
	_build_cut_trim()
	_build_atrium_wall()
	_build_railings()
	_build_atrium_fascia()
	_build_ceilings()
	_build_lights()
	_build_props()
	_build_signs()
	_hide_stale_details()
	_build_collision()
	# The parent ShipInterior applies ship_pixel_materials to the whole interior,
	# including this deck, once. Do not apply them twice here.


func get_collision_shapes() -> Array:
	return _collision_shapes


func set_roof_visible(value: bool) -> void:
	for node in roof_nodes:
		if is_instance_valid(node):
			(node as Node3D).visible = value


func _material(label: String, color: Color, metallic := 0.2, roughness := 0.82,
		uv := Vector3.ONE) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [label, str(uv), color.to_html()]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.resource_name = label
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.uv1_scale = uv
	_materials[key] = material
	return material


func _box(size: Vector3, pos: Vector3, material: Material, node_name := "",
		is_roof := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	node.mesh = mesh
	node.position = pos
	if not node_name.is_empty():
		node.name = node_name
	add_child(node)
	if is_roof:
		roof_nodes.append(node)
	return node


func _sloped(size: Vector3, pos: Vector3, material: Material, pitch: float,
		node_name := "") -> MeshInstance3D:
	var node := _box(size, pos, material, node_name)
	node.rotation.x = pitch
	return node


func _relocate_common_counter() -> void:
	# The old galley counter runs exactly under the new stair flight. Move the
	# visible unit east and give it a new plinth; the old base is hidden by the
	# stair. The indicator follows the unit, not the old wall panel.
	var rooms := get_node_or_null("../Rooms")
	if rooms == null:
		return
	for label in ["common ivory_aged", "common amber_indicator"]:
		var node := rooms.find_child(label, true, false) as Node3D
		if node != null:
			node.position.x += 2.5
			if label == "common amber_indicator":
				node.position.y -= 0.31
				node.position.z = 1.40
	var base := _material("wall_common", Color(0.30, 0.34, 0.31), 0.3, 0.75)
	_box(Vector3(0.94, 0.28, 3.28), Vector3(-1.02, 0.14, -1.965), base,
		"RelocatedCounterBase")


func _cut_stair_notch() -> void:
	# A low structural bench/ledge of the old common runs along the outer wall
	# exactly where the flight lands. Remove only that ledge inside the stair
	# footprint, keeping the old floor, the outer hull wall and the rest of the room.
	var rooms := get_node_or_null("../Rooms")
	if rooms == null:
		return
	var node := rooms.find_child("common structural_graphite", true, false) as MeshInstance3D
	if node == null:
		return
	var removed := _cut_mesh_volume(node, position, -4.05, -3.10, -3.10, 0.10, 0.20, 2.05)
	print("[UpperDeck] stair bench cut removed=", removed)
	# The old bench trim (brushed_edges) still crosses the aligned ramp even
	# after the structural bench is cut. Remove only the part inside the stair
	# envelope, keeping the outer hull wall at x=-4.1 intact.
	var trim := rooms.find_child("common brushed_edges", true, false) as MeshInstance3D
	if trim != null:
		var trim_removed := _cut_mesh_box(trim,
			Vector3(-3.90, 0.0, -3.10), Vector3(-3.10, 2.80, 0.20))
		print("[UpperDeck] stair trim cut removed=", trim_removed)


func _cut_stair_door() -> void:
	# The old bulkhead closes the stair foot from the lower common. Cut a real
	# doorway (not a hole) through every bulkhead material layer; the user asked
	# to leave the opening without a door/frame.
	var rooms := get_node_or_null("../Rooms")
	if rooms == null:
		return
	for label in ["bulkhead structural_graphite", "bulkhead brushed_edges",
			"bulkhead wall_common"]:
		var node := rooms.find_child(label, true, false) as MeshInstance3D
		if node == null:
			continue
		var removed := _cut_mesh_box(node,
			Vector3(-2.95, 0.0, -0.90), Vector3(-2.35, 2.42, 0.60))
		removed += _cut_mesh_box(node,
			Vector3(-3.80, 0.0, -0.80), Vector3(-3.20, 2.40, 0.60))
		if removed > 0:
			print("[UpperDeck] stair doorway cut ", label, " removed=", removed)


func _cut_mesh_volume(mesh_node: MeshInstance3D, offset: Vector3, lx0: float, lx1: float,
		lz0: float, lz1: float, y0: float, y1: float) -> int:
	var source := mesh_node.mesh
	if source == null:
		return 0
	var result := ArrayMesh.new()
	var changed := false
	var removed := 0
	var hx0 := lx0 + offset.x
	var hx1 := lx1 + offset.x
	var hz0 := lz0 + offset.z
	var hz1 := lz1 + offset.z
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			continue
		var kept: Array[int] = []
		for index in range(0, indices.size(), 3):
			var ia := indices[index]
			var ib := indices[index + 1]
			var ic := indices[index + 2]
			var a := mesh_node.transform * vertices[ia]
			var b := mesh_node.transform * vertices[ib]
			var c := mesh_node.transform * vertices[ic]
			var centroid := (a + b + c) / 3.0
			if centroid.x > hx0 and centroid.x < hx1 \
					and centroid.z > hz0 and centroid.z < hz1 \
					and centroid.y > y0 and centroid.y < y1:
				changed = true
				removed += 1
				continue
			kept.append(ia)
			kept.append(ib)
			kept.append(ic)
		if kept.is_empty():
			continue
		var new_arrays := arrays.duplicate(true)
		new_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(kept)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
		result.surface_set_material(result.get_surface_count() - 1,
			source.surface_get_material(surface))
	if changed:
		mesh_node.mesh = result
	return removed


func _cut_mesh_box(mesh_node: MeshInstance3D, box_min: Vector3,
		box_max: Vector3) -> int:
	# Exact triangle-vs-box subtraction in UpperDeck local space. Using the
	# global transform chain matters for Details: its GLB root has its own
	# transform, unlike the Rooms meshes.
	var source := mesh_node.mesh
	if source == null:
		return 0
	var result := ArrayMesh.new()
	var upper_from_mesh := global_transform.affine_inverse() * mesh_node.global_transform
	var mesh_from_upper := upper_from_mesh.affine_inverse()
	var upper_normal_basis := upper_from_mesh.basis.inverse().transposed()
	var mesh_normal_basis := mesh_from_upper.basis.inverse().transposed()
	var lo := box_min
	var hi := box_max
	var planes := [
		[Vector3(1, 0, 0), lo.x], [Vector3(-1, 0, 0), -hi.x],
		[Vector3(0, 1, 0), lo.y], [Vector3(0, -1, 0), -hi.y],
		[Vector3(0, 0, 1), lo.z], [Vector3(0, 0, -1), -hi.z],
	]
	var removed := 0
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			continue
		var has_normals := normals.size() == vertices.size()
		var has_uvs := uvs.size() == vertices.size()
		var out_v: Array = []
		var out_n: Array = []
		var out_uv: Array = []
		var out_i: Array = []
		for index in range(0, indices.size(), 3):
			var ia := indices[index]
			var ib := indices[index + 1]
			var ic := indices[index + 2]
			var pa: Vector3 = vertices[ia]
			var pb: Vector3 = vertices[ib]
			var pc: Vector3 = vertices[ic]
			var wa := upper_from_mesh * pa
			var wb := upper_from_mesh * pb
			var wc := upper_from_mesh * pc
			var tmin := Vector3(minf(wa.x, minf(wb.x, wc.x)), minf(wa.y, minf(wb.y, wc.y)),
				minf(wa.z, minf(wb.z, wc.z)))
			var tmax := Vector3(maxf(wa.x, maxf(wb.x, wc.x)), maxf(wa.y, maxf(wb.y, wc.y)),
				maxf(wa.z, maxf(wb.z, wc.z)))
			if not _aabb_overlaps(tmin, tmax, lo, hi):
				_emit_original(out_v, out_n, out_uv, out_i, pa, pb, pc,
					normals, uvs, ia, ib, ic, has_normals, has_uvs)
				continue
			var poly: Array = []
			for v in [[pa, ia], [pb, ib], [pc, ic]]:
				var vp: Vector3 = v[0]
				var vi: int = v[1]
				poly.append({
					"p": upper_from_mesh * vp,
					"n": normals[vi] if has_normals else Vector3.UP,
					"uv": uvs[vi] if has_uvs else Vector2.ZERO,
				})
			var pieces: Array = []
			var inside := poly
			for plane in planes:
				var normal: Vector3 = plane[0]
				var d: float = plane[1]
				var outside := _clip_polygon(inside, normal, d, false)
				inside = _clip_polygon(inside, normal, d, true)
				if outside.size() >= 3:
					pieces.append(outside)
				if inside.size() < 3:
					break
			if inside.size() >= 3:
				# The whole triangle is inside the doorway volume.
				removed += 1
				continue
			if pieces.is_empty():
				_emit_original(out_v, out_n, out_uv, out_i, pa, pb, pc,
					normals, uvs, ia, ib, ic, has_normals, has_uvs)
				continue
			for piece in pieces:
				var base := out_v.size()
				for vertex in piece:
					out_v.append(mesh_from_upper * (vertex["p"] as Vector3))
					var normal: Vector3 = vertex["n"]
					out_n.append((mesh_normal_basis * normal).normalized())
					out_uv.append(vertex["uv"] as Vector2)
				for k in range(1, piece.size() - 1):
					out_i.append(base)
					out_i.append(base + k)
					out_i.append(base + k + 1)
			removed += 1
		if out_i.is_empty():
			continue
		var new_arrays: Array = []
		new_arrays.resize(Mesh.ARRAY_MAX)
		new_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(out_v)
		new_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(out_n)
		new_arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(out_uv)
		new_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(out_i)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
		result.surface_set_material(result.get_surface_count() - 1,
			source.surface_get_material(surface))
	if removed > 0:
		mesh_node.mesh = result
	return removed


func _emit_original(out_v: Array, out_n: Array, out_uv: Array, out_i: Array,
		pa: Vector3, pb: Vector3, pc: Vector3, normals: PackedVector3Array,
		uvs: PackedVector2Array, ia: int, ib: int, ic: int,
		has_normals: bool, has_uvs: bool) -> void:
	var positions := [pa, pb, pc]
	var ids := [ia, ib, ic]
	for k in 3:
		out_v.append(positions[k])
		out_n.append(normals[ids[k]] if has_normals else Vector3.UP)
		out_uv.append(uvs[ids[k]] if has_uvs else Vector2.ZERO)
		out_i.append(out_v.size() - 1)


func _aabb_overlaps(a_min: Vector3, a_max: Vector3, b_min: Vector3, b_max: Vector3) -> bool:
	return a_min.x <= b_max.x and a_max.x >= b_min.x \
		and a_min.y <= b_max.y and a_max.y >= b_min.y \
		and a_min.z <= b_max.z and a_max.z >= b_min.z


func _clip_polygon(poly: Array, normal: Vector3, d: float, keep_positive: bool) -> Array:
	if poly.is_empty():
		return []
	var out: Array = []
	var count := poly.size()
	for i in count:
		var a: Dictionary = poly[i]
		var b: Dictionary = poly[(i + 1) % count]
		var da := normal.dot(a["p"] as Vector3) - d
		var db := normal.dot(b["p"] as Vector3) - d
		var ain := da >= 0.0
		var bin := db >= 0.0
		if not keep_positive:
			ain = da <= 0.0
			bin = db <= 0.0
		if ain:
			out.append(a)
		if ain != bin:
			var t := da / (da - db)
			out.append(_lerp_poly_vertex(a, b, t))
	return out


func _lerp_poly_vertex(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var pa: Vector3 = a["p"]
	var pb: Vector3 = b["p"]
	var na: Vector3 = a["n"]
	var nb: Vector3 = b["n"]
	var ua: Vector2 = a["uv"]
	var ub: Vector2 = b["uv"]
	return {
		"p": pa.lerp(pb, t),
		"n": na.lerp(nb, t).normalized(),
		"uv": ua.lerp(ub, t),
	}


func _cut_old_ceiling() -> void:
	var rooms := get_node_or_null("../Rooms")
	if rooms == null:
		push_warning("[UpperDeck] Rooms not found, atrium ceiling stays closed")
		return
	# The UpperDeck node is offset relative to Rooms; the opening must be cut in
	# Rooms space, not in the deck's own local space. Only the shell/ceiling and
	# wall band are cut; furniture, lamps and floor plates stay.
	var offset := position
	var targets := [
		"common structural_graphite", "common brushed_edges", "common wall_common",
		"bulkhead structural_graphite", "bulkhead brushed_edges", "bulkhead wall_common"
	]
	for label in targets:
		var node := rooms.find_child(label, true, false) as MeshInstance3D
		if node != null:
			_cut_mesh_top(node, offset)


func _cut_mesh_top(mesh_node: MeshInstance3D, offset: Vector3) -> void:
	var source := mesh_node.mesh
	var result := ArrayMesh.new()
	var changed := false
	var removed := 0
	var hx0 := X0 - 0.05 + offset.x
	var hx1 := ATRIUM_X1 + 0.05 + offset.x
	var hz0 := ATRIUM_Z0 - 0.05 + offset.z
	var hz1 := ATRIUM_Z1 + 0.05 + offset.z
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			continue
		var kept: Array[int] = []
		for index in range(0, indices.size(), 3):
			var ia := indices[index]
			var ib := indices[index + 1]
			var ic := indices[index + 2]
			var a := mesh_node.transform * vertices[ia]
			var b := mesh_node.transform * vertices[ib]
			var c := mesh_node.transform * vertices[ic]
			# Remove the ceiling, beams and the low soffit/wall band above the
			# lower room; keep walls below head height and all floors.
			if a.y > 2.05 and b.y > 2.05 and c.y > 2.05:
				var centroid := (a + b + c) / 3.0
				if centroid.x > hx0 and centroid.x < hx1 \
						and centroid.z > hz0 and centroid.z < hz1:
					changed = true
					removed += 1
					continue
			kept.append(ia)
			kept.append(ib)
			kept.append(ic)
		var new_arrays := arrays.duplicate(true)
		new_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(kept)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
		result.surface_set_material(result.get_surface_count() - 1,
			source.surface_get_material(surface))
	if changed:
		mesh_node.mesh = result
		print("[UpperDeck] ceiling cut ", mesh_node.name, " removed=", removed)


func _build_floors() -> void:
	var plate := _material("deck_plate", Color(0.38, 0.39, 0.37), 0.35, 0.72,
		Vector3(3, 3, 1))
	var slab_y := (SLAB + FLOOR) * 0.5
	_box(Vector3(X1 - X0, FLOOR - SLAB, CABIN_Z1),
		Vector3((X0 + X1) * 0.5, slab_y, CABIN_Z1 * 0.5), plate, "CabinFloor")
	_box(Vector3(X1 - X0, FLOOR - SLAB, HALL_Z0 - OBS_Z0),
		Vector3((X0 + X1) * 0.5, slab_y, (OBS_Z0 + HALL_Z0) * 0.5),
		plate, "ObservationFloor")
	_box(Vector3(TECH_X1 - X1, FLOOR - SLAB, -TECH_Z0),
		Vector3((X1 + TECH_X1) * 0.5, slab_y, TECH_Z0 * 0.5), plate, "TechFloor")
	# Landing around the open atrium.
	_box(Vector3(X1 - X0, FLOOR - SLAB, ATRIUM_Z0 - HALL_Z0),
		Vector3((X0 + X1) * 0.5, slab_y, (HALL_Z0 + ATRIUM_Z0) * 0.5),
		plate, "BackWalkway")
	_box(Vector3(X1 - ATRIUM_X1, FLOOR - SLAB, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3((ATRIUM_X1 + X1) * 0.5, slab_y, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5),
		plate, "EastWalkway")


func _build_walls() -> void:
	var cabin := _material("wall_quarters", Color(0.74, 0.68, 0.58), 0.1, 0.92,
		Vector3(3, 1.2, 1))
	var hall := _material("wall_common", Color(0.62, 0.68, 0.62), 0.1, 0.92,
		Vector3(3, 1.2, 1))
	var tech := _material("wall_technical", Color(0.58, 0.62, 0.58), 0.12, 0.9,
		Vector3(3, 1.2, 1))
	var trim := _material("brushed_edges", Color(0.62, 0.64, 0.62), 0.55, 0.55)
	var height := CEIL - FLOOR
	var mid := (FLOOR + CEIL) * 0.5
	# Cabin shell.
	_box(Vector3(X1 - X0, height, WALL_T), Vector3((X0 + X1) * 0.5, mid, CABIN_Z1 + WALL_T * 0.5),
		cabin, "CabinBack")
	_box(Vector3(WALL_T, height, CABIN_Z1), Vector3(X0 - WALL_T * 0.5, mid, CABIN_Z1 * 0.5),
		cabin, "CabinOuter")
	_box(Vector3(WALL_T, height, CABIN_Z1), Vector3(X1 + WALL_T * 0.5, mid, CABIN_Z1 * 0.5),
		cabin, "CabinInner")
	# Cabin / hall wall, door at x -0.8..0 on the east walkway.
	_box(Vector3(ATRIUM_X1 - X0, height, WALL_T),
		Vector3((X0 + ATRIUM_X1) * 0.5, mid, -WALL_T * 0.5), cabin, "CabinHallWall")
	_box(Vector3(X1 - ATRIUM_X1, CEIL - 4.92, WALL_T),
		Vector3((ATRIUM_X1 + X1) * 0.5, (4.92 + CEIL) * 0.5, -WALL_T * 0.5),
		cabin, "CabinDoorHeader")
	# Observation shell and window opening.
	_box(Vector3(X1 - X0, height, WALL_T), Vector3((X0 + X1) * 0.5, mid, OBS_Z0 - WALL_T * 0.5),
		cabin, "ObservationBack")
	_box(Vector3(WALL_T, height, HALL_Z0 - OBS_Z0),
		Vector3(X1 + WALL_T * 0.5, mid, (OBS_Z0 + HALL_Z0) * 0.5), cabin, "ObservationInner")
	_box(Vector3(WALL_T, height, 0.8), Vector3(X0 - WALL_T * 0.5, mid, -7.6),
		cabin, "ObservationOuterFore")
	_box(Vector3(WALL_T, height, 0.8), Vector3(X0 - WALL_T * 0.5, mid, -4.4),
		cabin, "ObservationOuterAft")
	_box(Vector3(WALL_T, 0.70, 2.40), Vector3(X0 - WALL_T * 0.5, FLOOR + 0.35, -6.0),
		cabin, "ObservationSill")
	_box(Vector3(WALL_T, CEIL - 5.12, 2.40),
		Vector3(X0 - WALL_T * 0.5, (5.12 + CEIL) * 0.5, -6.0), cabin, "ObservationHeader")
	# Observation / hall wall, door at x -0.8..0.
	_box(Vector3(ATRIUM_X1 - X0, height, WALL_T),
		Vector3((X0 + ATRIUM_X1) * 0.5, mid, HALL_Z0 - WALL_T * 0.5),
		cabin, "ObservationHallWall")
	_box(Vector3(X1 - ATRIUM_X1, CEIL - 4.92, WALL_T),
		Vector3((ATRIUM_X1 + X1) * 0.5, (4.92 + CEIL) * 0.5, HALL_Z0 - WALL_T * 0.5),
		cabin, "ObservationDoorHeader")
	# Hall outer wall along the stair flight.
	_box(Vector3(WALL_T, height, ATRIUM_Z1 - HALL_Z0),
		Vector3(X0 - WALL_T * 0.5, mid, (HALL_Z0 + ATRIUM_Z1) * 0.5),
		hall, "HallOuterWall")
	# Hall / tech wall, door at z -2.2..-1.2, plus outer piece aft of the store.
	_box(Vector3(WALL_T, height, 1.2), Vector3(X1 + WALL_T * 0.5, mid, -0.6),
		hall, "HallTechWallFore")
	_box(Vector3(WALL_T, height, 0.5), Vector3(X1 + WALL_T * 0.5, mid, -2.45),
		hall, "HallTechWallAft")
	_box(Vector3(WALL_T, CEIL - 4.92, 1.0), Vector3(X1 + WALL_T * 0.5, (4.92 + CEIL) * 0.5, -1.7),
		hall, "TechDoorHeader")
	_box(Vector3(WALL_T, height, -TECH_Z0), Vector3(X1 + WALL_T * 0.5, mid, -3.35),
		hall, "HallOuterAft")
	# Tech storage shell.
	_box(Vector3(WALL_T, height, -TECH_Z0), Vector3(TECH_X1 + WALL_T * 0.5, mid, TECH_Z0 * 0.5),
		tech, "TechOuter")
	_box(Vector3(TECH_X1 - X1, height, WALL_T),
		Vector3((X1 + TECH_X1) * 0.5, mid, TECH_Z0 - WALL_T * 0.5), tech, "TechBack")
	_box(Vector3(TECH_X1 - X1, height, WALL_T),
		Vector3((X1 + TECH_X1) * 0.5, mid, WALL_T * 0.5), tech, "TechFront")
	# Heavy frames around each opening.
	_frame_x(-0.8, 0.0, -WALL_T * 0.5, trim)
	_frame_x(-0.8, 0.0, HALL_Z0 - WALL_T * 0.5, trim)
	_frame_z(-2.2, -1.2, X1 + WALL_T * 0.5, trim)
	# Base trim on the visible outer walls.
	var base := _material("brushed_edges", Color(0.62, 0.64, 0.62), 0.55, 0.55)
	_box(Vector3(0.04, 0.06, CABIN_Z1), Vector3(X0 + 0.02, FLOOR + 0.03, CABIN_Z1 * 0.5), base)
	_box(Vector3(0.04, 0.06, HALL_Z0 - OBS_Z0),
		Vector3(X0 + 0.02, FLOOR + 0.03, (OBS_Z0 + HALL_Z0) * 0.5), base)
	_box(Vector3(0.04, 0.06, -TECH_Z0), Vector3(TECH_X1 - 0.02, FLOOR + 0.03, TECH_Z0 * 0.5), base)
	# Hazard thresholds.
	var hazard := _material("detail_hazard", Color(0.82, 0.62, 0.10), 0.2, 0.6)
	_box(Vector3(0.84, 0.02, 0.14), Vector3(-0.4, FLOOR + 0.011, -0.07), hazard)
	_box(Vector3(0.84, 0.02, 0.14), Vector3(-0.4, FLOOR + 0.011, HALL_Z0 + 0.07), hazard)
	_box(Vector3(0.14, 0.02, 1.04), Vector3(X1 - 0.07, FLOOR + 0.011, -1.7), hazard)


func _frame_x(x0: float, x1: float, z: float, material: Material) -> void:
	_box(Vector3(0.06, 2.1, 0.17), Vector3(x0 - 0.03, FLOOR + 1.05, z), material)
	_box(Vector3(0.06, 2.1, 0.17), Vector3(x1 + 0.03, FLOOR + 1.05, z), material)
	_box(Vector3(x1 - x0 + 0.12, 0.08, 0.17),
		Vector3((x0 + x1) * 0.5, FLOOR + 2.14, z), material)


func _frame_z(z0: float, z1: float, x: float, material: Material) -> void:
	_box(Vector3(0.17, 2.1, 0.06), Vector3(x, FLOOR + 1.05, z0 - 0.03), material)
	_box(Vector3(0.17, 2.1, 0.06), Vector3(x, FLOOR + 1.05, z1 + 0.03), material)
	_box(Vector3(0.17, 0.08, z1 - z0 + 0.12),
		Vector3(x, FLOOR + 2.14, (z0 + z1) * 0.5), material)


func _build_atrium_wall() -> void:
	# The stair's atrium-side wall is back. The door itself stays removed: the
	# opening is open, but the shaft no longer looks into the atrium.
	var wall := _material("wall_common", Color(0.28, 0.32, 0.30), 0.3, 0.78)
	var edge := _material("brushed_edges", Color(0.48, 0.51, 0.49), 0.55, 0.55)
	_box(Vector3(0.12, CEIL - 0.02, 2.10),
		Vector3(ATRIUM_X0, (CEIL + 0.02) * 0.5, -1.95), wall, "AtriumWallNorth")
	_box(Vector3(0.12, CEIL - 2.42, 1.50),
		Vector3(ATRIUM_X0, (CEIL + 2.42) * 0.5, -0.15), wall, "AtriumWallHeader")


func _build_cut_trim() -> void:
	# The door frame is intentionally gone. Only the old wall-band backing
	# remains, so the cut does not open into space above the flight.
	var backing := _material("wall_common", Color(0.30, 0.34, 0.31), 0.3, 0.78)
	# Close the old wall band above the stair, where the old ceiling cut left a
	# strip of open hull behind the flight.
	_box(Vector3(0.10, FLOOR - 2.05, 3.10),
		Vector3(X0 - 0.01, (2.05 + FLOOR) * 0.5, -1.45), backing, "CutStairBackBand")


func _build_stairs() -> void:
	var tread := _material("deck_plate", Color(0.40, 0.41, 0.39), 0.35, 0.72)
	var riser := _material("structural_graphite", Color(0.34, 0.36, 0.34), 0.4, 0.66)
	var hazard := _material("detail_hazard", Color(0.82, 0.62, 0.10), 0.2, 0.6)
	var run := STAIR_RUN / float(STEP_COUNT)
	var rise := STAIR_RISE / float(STEP_COUNT)
	for i in STEP_COUNT:
		var z0 := -float(i) * run
		var z1 := z0 - run
		var top := float(i + 1) * rise
		_box(Vector3(1.0, 0.05, run + 0.005),
			Vector3(-3.6, top - 0.025, (z0 + z1) * 0.5), tread, "StairTread_%02d" % i)
		_box(Vector3(1.0, rise, 0.04),
			Vector3(-3.6, float(i) * rise + rise * 0.5, z0 - 0.02), riser, "StairRiser_%02d" % i)
		_box(Vector3(1.0, 0.018, 0.04),
			Vector3(-3.6, top + 0.009, z0 - 0.02), hazard, "StairNose_%02d" % i)
	var length := sqrt(STAIR_RUN * STAIR_RUN + STAIR_RISE * STAIR_RISE)
	var pitch := atan2(STAIR_RISE, STAIR_RUN)
	for x in [-4.04, -3.20]:
		_sloped(Vector3(0.06, 0.18, length), Vector3(x, STAIR_RISE * 0.5, -STAIR_RUN * 0.5),
			riser, pitch, "StairStringer")
	_box(Vector3(1.0, 0.02, 0.18), Vector3(-3.6, 0.032, 0.12), hazard, "StairThreshold")


func _build_railings() -> void:
	var rail := _material("brushed_edges", Color(0.66, 0.68, 0.66), 0.6, 0.48)
	var post := Vector3(0.04, 0.95, 0.04)
	# East walkway edge.
	for z in [-0.4, -1.2, -2.0, -2.8]:
		_box(post, Vector3(ATRIUM_X1, FLOOR + 0.475, z), rail)
	_box(Vector3(0.05, 0.05, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X1, FLOOR + 0.95, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), rail)
	# Back walkway edge.
	for x in [-2.80, -2.00, -1.20]:
		_box(post, Vector3(x, FLOOR + 0.475, ATRIUM_Z0), rail)
	_box(Vector3(ATRIUM_X1 - ATRIUM_X0, 0.05, 0.05),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, FLOOR + 0.95, ATRIUM_Z0), rail)
	_box(post, Vector3(ATRIUM_X1, FLOOR + 0.475, ATRIUM_Z0), rail)


func _build_atrium_fascia() -> void:
	var fascia := _material("structural_graphite", Color(0.30, 0.32, 0.31), 0.4, 0.68)
	var trim := _material("brushed_edges", Color(0.60, 0.62, 0.60), 0.55, 0.52)
	var h := 0.30
	var y := OLD_CEIL + h * 0.5
	_box(Vector3(0.08, h, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X0, y, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), fascia, "AtriumFasciaWest")
	_box(Vector3(0.08, h, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X1, y, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), fascia, "AtriumFasciaEast")
	_box(Vector3(ATRIUM_X1 - ATRIUM_X0, h, 0.08),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, y, ATRIUM_Z0), fascia, "AtriumFasciaBack")
	_box(Vector3(ATRIUM_X1 - ATRIUM_X0, h, 0.08),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, y, ATRIUM_Z1), fascia, "AtriumFasciaFront")
	# Top trim outlining the void. The corner trim sits a little higher than the
	# long trims so their coplanar faces cannot z-fight at the corners.
	_box(Vector3(0.10, 0.04, ATRIUM_Z1 - ATRIUM_Z0 - 0.04),
		Vector3(ATRIUM_X0, OLD_CEIL + h + 0.035, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), trim)
	_box(Vector3(0.10, 0.04, ATRIUM_Z1 - ATRIUM_Z0 - 0.04),
		Vector3(ATRIUM_X1, OLD_CEIL + h + 0.035, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), trim)
	_box(Vector3(ATRIUM_X1 - ATRIUM_X0, 0.04, 0.10),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, OLD_CEIL + h + 0.015, ATRIUM_Z0 - 0.06), trim)
	# Close the raw old-ceiling cut edges on the remaining three sides. The
	# fourth side is the new stair wall.
	_box(Vector3(0.08, 0.10, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X1, OLD_CEIL - 0.04, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5), trim,
		"AtriumCutEdgeEast")
	_box(Vector3(ATRIUM_X1 - ATRIUM_X0, 0.10, 0.08),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, OLD_CEIL - 0.04, ATRIUM_Z0), trim,
		"AtriumCutEdgeBack")
	_box(Vector3(ATRIUM_X1 - ATRIUM_X0, 0.10, 0.08),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, OLD_CEIL - 0.04, ATRIUM_Z1), trim,
		"AtriumCutEdgeFront")


func _build_ceilings() -> void:
	var roof_mat := _material("structural_graphite", Color(0.28, 0.30, 0.29), 0.4, 0.68)
	var beam := _material("brushed_edges", Color(0.54, 0.56, 0.54), 0.55, 0.52)
	var lamp := StandardMaterial3D.new()
	lamp.resource_name = "lamp_diffuser"
	lamp.albedo_color = Color(0.16, 0.21, 0.25)
	lamp.emission_enabled = true
	lamp.emission = Color(0.55, 0.68, 0.82)
	lamp.emission_energy_multiplier = 0.65
	# Roof slabs.
	_box(Vector3(X1 - X0, ROOF - CEIL, CABIN_Z1 - OBS_Z0),
		Vector3((X0 + X1) * 0.5, (CEIL + ROOF) * 0.5, (OBS_Z0 + CABIN_Z1) * 0.5),
		roof_mat, "UpperRoof", true)
	_box(Vector3(TECH_X1 - X1, ROOF - CEIL, -TECH_Z0),
		Vector3((X1 + TECH_X1) * 0.5, (CEIL + ROOF) * 0.5, TECH_Z0 * 0.5),
		roof_mat, "TechRoof", true)
	# Beams and recessed light panels.
	for z in [1.0, 2.0, 3.0]:
		_box(Vector3(X1 - X0, 0.08, 0.08), Vector3((X0 + X1) * 0.5, CEIL - 0.04, z),
			beam, "", true)
	for z in [-5.0, -6.0, -7.0]:
		_box(Vector3(X1 - X0, 0.08, 0.08), Vector3((X0 + X1) * 0.5, CEIL - 0.04, z),
			beam, "", true)
	for z in [-0.8, -1.8, -2.8]:
		_box(Vector3(ATRIUM_X1 - ATRIUM_X0, 0.08, 0.08),
			Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, CEIL - 0.04, z), beam, "", true)
	for x in [1.2, 2.4, 3.6]:
		_box(Vector3(0.08, 0.08, -TECH_Z0), Vector3(x, CEIL - 0.04, TECH_Z0 * 0.5),
			beam, "", true)
	# Lamps.
	_ceiling_panel(lamp, Vector3(-2.05, CEIL - 0.03, 2.0), Vector3(0.55, 0.02, 1.0))
	_ceiling_panel(lamp, Vector3(-2.05, CEIL - 0.03, -6.0), Vector3(0.55, 0.02, 1.0))
	_ceiling_panel(lamp, Vector3(-1.95, CEIL - 0.03, -1.55), Vector3(0.70, 0.02, 0.70))
	_ceiling_panel(lamp, Vector3(1.05, CEIL - 0.03, -1.35), Vector3(0.55, 0.02, 1.0))
	_ceiling_panel(lamp, Vector3(3.45, CEIL - 0.03, -1.35), Vector3(0.55, 0.02, 1.0))


func _ceiling_panel(material: Material, pos: Vector3, size: Vector3) -> void:
	_box(size, pos, material, "", true)


func _build_lights() -> void:
	# Dim cold deck lighting: the deck is abandoned, the only strong source is
	# the observation window. Warm light is reserved for the old lower deck.
	_spot("CabinLight", Vector3(-2.05, CEIL - 0.10, 2.0), Color(0.58, 0.70, 0.82), 1.15, 4.6)
	_spot("ObservationLight", Vector3(-2.05, CEIL - 0.10, -6.0), Color(0.52, 0.68, 0.85), 1.20, 5.0)
	_spot("HallLight", Vector3(-1.95, CEIL - 0.10, -1.55), Color(0.55, 0.68, 0.80), 1.25, 5.6, false)
	_spot("TechLight", Vector3(1.05, CEIL - 0.10, -1.35), Color(0.42, 0.58, 0.55), 0.80, 4.2, false)
	_spot("TechLightB", Vector3(3.45, CEIL - 0.10, -1.35), Color(0.42, 0.58, 0.55), 0.70, 3.8, false)
	_omni("StairFill", Vector3(-3.55, 3.90, -1.60), Color(0.55, 0.66, 0.78), 0.65, 3.4)
	_omni("StairFoot", Vector3(-3.55, 1.25, -0.15), Color(0.55, 0.66, 0.78), 0.42, 2.4)
	_omni("WindowGlow", Vector3(-3.95, 4.20, -6.0), Color(0.30, 0.50, 0.78), 0.55, 3.0)
	_omni("AtriumFill", Vector3(-2.0, 4.60, -1.50), Color(0.55, 0.68, 0.82), 1.00, 6.0)
	_omni("AtriumLower", Vector3(-2.0, 3.40, -1.50), Color(0.55, 0.68, 0.82), 0.80, 5.0)
	_spot("AtriumShaft", Vector3(-2.0, 3.45, -1.50), Color(0.55, 0.68, 0.82), 1.00, 4.0, false)


func _spot(name: String, pos: Vector3, color: Color, energy: float, range_m: float,
		shadows := true) -> void:
	var light := SpotLight3D.new()
	light.name = name
	light.position = pos
	light.rotation_degrees.x = -90
	light.light_color = color
	light.light_energy = energy
	light.spot_range = range_m
	light.spot_angle = 72.0
	light.shadow_enabled = shadows
	light.shadow_bias = 0.15
	light.shadow_normal_bias = 1.2
	add_child(light)


func _omni(name: String, pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var light := OmniLight3D.new()
	light.name = name
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	add_child(light)


func _build_props() -> void:
	_build_window()
	var wood := _material("detail_laminate", Color(0.46, 0.38, 0.28), 0.05, 0.9)
	# Cabin.
	_prop(BUNK, "CabinBunk", Vector3(-3.55, FLOOR, 2.20), 90.0)
	_prop(LOCKER, "CabinLocker", Vector3(-3.55, FLOOR, 3.65), 180.0)
	_prop(TABLE, "CabinTable", Vector3(-0.65, FLOOR, 3.20), 0.0)
	var cabin_chair := _prop(CHAIR, "CabinChair", Vector3(-0.34, FLOOR + 0.03, 2.52), -90.0)
	cabin_chair.rotation.z = -0.12
	_prop(PIPES, "CabinPipes", Vector3(-3.99, 4.75, 2.00), -90.0)
	# Crew traces: the deck was left in a hurry, not staged.
	_prop(MUG, "CabinMug", Vector3(-0.44, FLOOR + 0.754, 3.04), 24.0)
	_prop(NOTEBOOK, "CabinNotebook", Vector3(-0.86, FLOOR + 0.754, 3.10), -12.0)
	_prop(PHOTO, "CabinPhoto", Vector3(-0.62, FLOOR + 0.754, 3.43), 8.0)
	_prop(BOOTS, "CabinBoots", Vector3(-2.85, FLOOR + 0.026, 1.10), 24.0)
	_prop(PAPERS, "CabinPapers", Vector3(-1.60, FLOOR + 0.026, 3.55), 20.0)
	# Observation.
	_prop(NAV_CONSOLE, "ObservationConsole", Vector3(-2.05, FLOOR, -7.35), 0.0)
	_prop(BENCH, "ObservationBench", Vector3(-3.55, FLOOR, -5.20), 90.0)
	_prop(TABLE, "ObservationTable", Vector3(-0.45, FLOOR, -7.30), 0.0)
	_prop(VENT, "ObservationVent", Vector3(-0.06, 4.30, -5.20), 90.0)
	_prop(MUG, "ObservationMug", Vector3(-0.62, FLOOR + 0.754, -7.18), -18.0)
	_prop(NOTEBOOK, "ObservationLog", Vector3(-0.28, FLOOR + 0.754, -7.42), 12.0)
	_prop(PAPERS, "ObservationPapers", Vector3(-1.55, FLOOR + 0.026, -5.65), -14.0)
	# Tech storage.
	_prop(SHELF, "TechShelf", Vector3(4.20, FLOOR, -1.30), 90.0)
	_prop(LOCKER, "TechLocker", Vector3(3.70, FLOOR, -0.42), 180.0)
	_prop(TABLE, "TechTable", Vector3(2.00, FLOOR, -2.28), 0.0)
	_prop(TRASH, "TechBin", Vector3(2.85, FLOOR, -2.35), 0.0)
	_prop(PIPES, "TechPipes", Vector3(2.50, 4.05, -2.55), 0.0)
	_prop(CABLE, "TechCable", Vector3(1.35, FLOOR + 0.026, -0.92), 12.0)
	_prop(PAPERS, "TechPapers", Vector3(2.05, FLOOR + 0.77, -2.10), 28.0)
	# Crates on the floor, clear of the tech-storage door, bin and cable.
	var crate := _material("detail_cardboard", Color(0.55, 0.45, 0.32), 0.0, 0.9)
	_box(Vector3(0.62, 0.50, 0.62), Vector3(3.60, FLOOR + 0.25, -2.28), crate, "CrateA")
	_box(Vector3(0.62, 0.50, 0.62), Vector3(3.60, FLOOR + 0.75, -2.28), crate, "CrateB")
	_box(Vector3(0.52, 0.42, 0.52), Vector3(2.50, FLOOR + 0.21, -0.55), crate, "CrateC")
	# Hall dressing.
	_prop(VENT, "HallVent", Vector3(-0.06, 4.30, -3.35), -90.0)
	_prop(PIPES, "HallPipes", Vector3(-0.09, 4.75, -0.60), -90.0)
	# A small worktop at the cabin door is omitted: the visible decals/labels come next.


func _prop(scene: PackedScene, name: String, pos: Vector3, yaw: float) -> Node3D:
	var node := scene.instantiate() as Node3D
	node.name = name
	node.position = pos
	node.rotation_degrees.y = yaw
	add_child(node)
	return node


func _build_signs() -> void:
	_sign("ДОП. КАЮТА", Vector3(-0.40, 5.12, -0.01), 180.0)
	_sign("ОБЗОР", Vector3(-0.40, 5.12, HALL_Z0 + 0.01), 0.0)
	_sign("ТЕХСКЛАД", Vector3(X1 - 0.01, 5.12, -1.70), -90.0)



func _hide_stale_details() -> void:
	# The old Details GLB is merged by material and still contains ceiling,
	# bench and stair-level geometry above the lower room. Keeping only the
	# sub-2.15 m part preserves the lower-ship clutter while removing every old
	# detail that intersects the new deck, stair flight and relocated counter.
	var details := get_node_or_null("../Details")
	if details == null:
		return
	for mesh_node in details.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		_strip_mesh_above(mesh, 2.15)
		if mesh.name in ["export_detail_acoustic", "export_detail_hazard"]:
			mesh.visible = false
			print("[UpperDeck] hidden stale detail ", mesh.name)
		else:
			_split_details_mesh(mesh, 2.0)


func _strip_mesh_above(mesh_node: MeshInstance3D, cut_y: float) -> void:
	var source := mesh_node.mesh
	if source == null:
		return
	var upper_from_mesh := global_transform.affine_inverse() * mesh_node.global_transform
	var result := ArrayMesh.new()
	var changed := false
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices = PackedInt32Array()
			for i in range(0, vertices.size(), 3):
				indices.append(i)
		var kept: Array[int] = []
		for index in range(0, indices.size(), 3):
			var ia := indices[index]
			var ib := indices[index + 1]
			var ic := indices[index + 2]
			var ya := (upper_from_mesh * vertices[ia]).y
			var yb := (upper_from_mesh * vertices[ib]).y
			var yc := (upper_from_mesh * vertices[ic]).y
			var centroid := upper_from_mesh * ((vertices[ia] + vertices[ib] + vertices[ic]) / 3.0)
			var drop := maxf(ya, maxf(yb, yc)) > cut_y
			if not drop:
				for box in [
					[Vector3(-4.20, 0.0, -3.20), Vector3(-3.00, 2.90, 0.30)],
					[Vector3(-3.20, 0.0, -1.20), Vector3(-2.20, 2.60, 0.80)],
					[Vector3(-1.70, 0.0, -3.80), Vector3(-0.40, 0.50, -0.20)],
				]:
					if centroid.x > box[0].x and centroid.x < box[1].x \
							and centroid.y > box[0].y and centroid.y < box[1].y \
							and centroid.z > box[0].z and centroid.z < box[1].z:
						drop = true
						break
			if drop:
				changed = true
				continue
			kept.append(ia)
			kept.append(ib)
			kept.append(ic)
		if kept.is_empty():
			continue
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var has_normals := normals.size() == vertices.size()
		var has_uvs := uvs.size() == vertices.size()
		var out_v: Array = []
		var out_n: Array = []
		var out_uv: Array = []
		var out_i: Array = []
		for vi in kept:
			out_v.append(vertices[vi])
			out_n.append(normals[vi] if has_normals else Vector3.UP)
			out_uv.append(uvs[vi] if has_uvs else Vector2.ZERO)
			out_i.append(out_v.size() - 1)
		var new_arrays: Array = []
		new_arrays.resize(Mesh.ARRAY_MAX)
		new_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(out_v)
		new_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(out_n)
		new_arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(out_uv)
		new_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(out_i)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
		result.surface_set_material(result.get_surface_count() - 1,
			source.surface_get_material(surface))
	if changed:
		mesh_node.mesh = result


func _split_details_mesh(mesh_node: MeshInstance3D, cell_size: float) -> void:
	# Split the merged Details material groups into coarse spatial cells so an
	# old pipe in the aft room no longer shares an AABB with the new stair at the
	# bow. Visual triangles are preserved; only the node partition changes.
	var source := mesh_node.mesh
	if source == null:
		return
	var upper_from_mesh := global_transform.affine_inverse() * mesh_node.global_transform
	var parent := mesh_node.get_parent()
	var made := false
	var base_name := String(mesh_node.name)
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices = PackedInt32Array()
			for i in range(0, vertices.size(), 3):
				indices.append(i)
		var has_normals := normals.size() == vertices.size()
		var has_uvs := uvs.size() == vertices.size()
		var groups: Dictionary = {}
		for index in range(0, indices.size(), 3):
			var ia := indices[index]
			var ib := indices[index + 1]
			var ic := indices[index + 2]
			var center := upper_from_mesh * ((vertices[ia] + vertices[ib] + vertices[ic]) / 3.0)
			var key := Vector2i(int(floor(center.x / cell_size)), int(floor(center.z / cell_size)))
			if not groups.has(key):
				groups[key] = []
			groups[key].append(ia)
			groups[key].append(ib)
			groups[key].append(ic)
		for key in groups:
			var tri_indices: Array = groups[key]
			var out_v: Array = []
			var out_n: Array = []
			var out_uv: Array = []
			var out_i: Array = []
			for vi in tri_indices:
				out_v.append(vertices[vi])
				out_n.append(normals[vi] if has_normals else Vector3.UP)
				out_uv.append(uvs[vi] if has_uvs else Vector2.ZERO)
				out_i.append(out_v.size() - 1)
			var cell_arrays: Array = []
			cell_arrays.resize(Mesh.ARRAY_MAX)
			cell_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(out_v)
			cell_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(out_n)
			cell_arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(out_uv)
			cell_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(out_i)
			var cell_mesh := ArrayMesh.new()
			cell_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cell_arrays)
			cell_mesh.surface_set_material(0, source.surface_get_material(surface))
			var cell := MeshInstance3D.new()
			cell.name = "%s_cell_%d_%d_s%d" % [base_name, key.x, key.y, surface]
			cell.transform = mesh_node.transform
			cell.mesh = cell_mesh
			cell.material_override = mesh_node.material_override
			cell.cast_shadow = mesh_node.cast_shadow
			parent.add_child(cell)
			made = true
	if made:
		mesh_node.visible = false


func _sign(text: String, pos: Vector3, yaw: float) -> void:
	var text_mesh := TextMesh.new()
	text_mesh.text = text
	text_mesh.font = load("res://assetss/ui/fonts/RussoOne-Regular.ttf")
	text_mesh.font_size = 28
	text_mesh.pixel_size = 0.003
	text_mesh.depth = 0.008
	text_mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var sign := MeshInstance3D.new()
	sign.mesh = text_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.57, 0.65, 0.61)
	material.roughness = 0.9
	sign.material_override = material
	sign.position = pos
	sign.rotation_degrees.y = yaw
	sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sign)
	# Closed backing plate: from the rear the sign reads as a dark metal plate,
	# not as mirrored text floating in the doorway.
	var back := MeshInstance3D.new()
	var back_mesh := BoxMesh.new()
	var text_bounds := text_mesh.get_aabb()
	back_mesh.size = Vector3(text_bounds.size.x + 0.08, text_bounds.size.y + 0.04, 0.02)
	back.mesh = back_mesh
	var back_material := StandardMaterial3D.new()
	back_material.albedo_color = Color(0.055, 0.065, 0.065)
	back_material.roughness = 0.86
	back.material_override = back_material
	back.position = text_bounds.get_center() + Vector3(0.0, 0.0, -0.02)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign.add_child(back)
	# Second face: from the other room the plate reads correctly instead of
	# showing mirrored text through the mesh.
	var back_sign := MeshInstance3D.new()
	back_sign.mesh = text_mesh
	back_sign.material_override = material
	back_sign.position = text_bounds.get_center() + Vector3(0.0, 0.0, -0.032)
	back_sign.rotation_degrees.y = 180.0
	back_sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign.add_child(back_sign)


func _build_window() -> void:
	# The observation window is a live SubViewport: a nearby gas giant with its
	# ring, parallax against the real panorama sky, and the black hole that the
	# ship is travelling toward. It follows SpaceStage so the room always shows
	# the current chapter of the voyage, not a static star sticker.
	var viewport := SubViewport.new()
	viewport.name = "ObservationViewport"
	viewport.size = Vector2i(600, 400)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport)
	_window_viewport = viewport
	_build_window_space(viewport)

	var glass := StandardMaterial3D.new()
	glass.resource_name = "observation_glass"
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_texture = viewport.get_texture()
	glass.albedo_color = Color(0.82, 0.90, 1.0)
	glass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	glass.disable_receive_shadows = true
	var glass_node := MeshInstance3D.new()
	glass_node.name = "ObservationGlass"
	var glass_mesh := QuadMesh.new()
	glass_mesh.size = Vector2(2.40, 1.60)
	glass_node.mesh = glass_mesh
	glass_node.material_override = glass
	glass_node.position = Vector3(X0 + 0.015, FLOOR + 1.50, -6.0)
	glass_node.rotation_degrees.y = 90.0
	glass_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass_node)

	# Dust, salt and old condensation on the inside of the glass.
	var grime := StandardMaterial3D.new()
	grime.resource_name = "observation_grime"
	grime.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grime.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grime.albedo_texture = load("res://assetss/space/glass_grime.png")
	grime.albedo_color = Color(0.42, 0.52, 0.62, 0.22)
	grime.uv1_scale = Vector3(0.85, 0.85, 1.0)
	grime.disable_receive_shadows = true
	var grime_node := MeshInstance3D.new()
	grime_node.name = "ObservationGrime"
	var grime_mesh := QuadMesh.new()
	grime_mesh.size = Vector2(2.38, 1.58)
	grime_node.mesh = grime_mesh
	grime_node.material_override = grime
	grime_node.position = Vector3(X0 + 0.035, FLOOR + 1.50, -6.0)
	grime_node.rotation_degrees.y = 90.0
	grime_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(grime_node)

	# Frame and mullions.
	var frame := _material("brushed_edges", Color(0.52, 0.55, 0.53), 0.6, 0.48)
	_box(Vector3(0.10, 1.72, 0.10), Vector3(X0 + 0.04, FLOOR + 1.50, -7.20), frame)
	_box(Vector3(0.10, 1.72, 0.10), Vector3(X0 + 0.04, FLOOR + 1.50, -4.80), frame)
	_box(Vector3(0.10, 0.10, 2.50), Vector3(X0 + 0.04, FLOOR + 2.30, -6.0), frame)
	_box(Vector3(0.10, 0.10, 2.50), Vector3(X0 + 0.04, FLOOR + 0.70, -6.0), frame)
	_box(Vector3(0.06, 1.64, 0.06), Vector3(X0 + 0.06, FLOOR + 1.50, -6.0), frame)


func _build_window_space(viewport: SubViewport) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = load("res://scenes/sky_space.tres")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	var world_env := WorldEnvironment.new()
	world_env.name = "WindowEnvironment"
	world_env.environment = env
	viewport.add_child(world_env)

	_window_camera = Camera3D.new()
	_window_camera.name = "WindowCamera"
	_window_camera.position = Vector3(0.0, 1.55, 0.0)
	_window_camera.fov = 62.0
	_window_camera.current = true
	viewport.add_child(_window_camera)

	var planet_material := StandardMaterial3D.new()
	planet_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	planet_material.albedo_texture = load("res://assetss/space/planet_gas.png")
	planet_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	planet_material.disable_fog = true
	planet_material.disable_receive_shadows = true
	planet_material.emission_enabled = true
	planet_material.emission = Color(0.55, 0.60, 0.70)
	planet_material.emission_texture = planet_material.albedo_texture
	planet_material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	planet_material.emission_energy_multiplier = 0.45
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_window_planet = MeshInstance3D.new()
	_window_planet.name = "WindowGasGiant"
	_window_planet.mesh = sphere
	_window_planet.material_override = planet_material
	_window_planet.position = Vector3(-3.0, 3.2, -52.0)
	_window_planet.scale = Vector3.ONE * 19.0
	_window_planet.rotation.y = 3.05
	_window_planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(_window_planet)

	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.vertex_color_use_as_albedo = true
	ring_material.albedo_color = Color(0.64, 0.62, 0.58, 0.82)
	ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_material.disable_fog = true
	ring_material.disable_receive_shadows = true
	_window_ring = MeshInstance3D.new()
	_window_ring.name = "WindowPlanetRing"
	_window_ring.mesh = _make_window_ring_mesh(23.0, 35.0)
	_window_ring.material_override = ring_material
	_window_ring.position = Vector3(-3.0, 3.2, -53.0)
	_window_ring.rotation_degrees = Vector3(0.0, 0.0, 14.0)
	_window_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(_window_ring)

	var hole_material := StandardMaterial3D.new()
	hole_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hole_material.albedo_texture = load("res://assetss/space/planet_blackhole.png")
	hole_material.albedo_color = Color(0.75, 0.72, 0.82, 0.95)
	hole_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hole_material.disable_fog = true
	hole_material.disable_receive_shadows = true
	var hole_mesh := QuadMesh.new()
	hole_mesh.size = Vector2(34.0, 34.0)
	_window_blackhole = MeshInstance3D.new()
	_window_blackhole.name = "WindowBlackHole"
	_window_blackhole.mesh = hole_mesh
	_window_blackhole.material_override = hole_material
	_window_blackhole.position = Vector3(-16.0, 8.0, -148.0)
	_window_blackhole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(_window_blackhole)

	var stage_node := get_tree().root.find_child("SpaceStage", true, false)
	if stage_node != null and stage_node.has_signal("stage_changed"):
		stage_node.stage_changed.connect(_apply_window_stage)
		_apply_window_stage(int(stage_node.get("initial_stage")), true)
	else:
		_apply_window_stage(0, true)


func _make_window_ring_mesh(inner_radius: float, outer_radius: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var radial_steps := 6
	var angular_steps := 128
	for radial_index in range(radial_steps + 1):
		var radial_t := float(radial_index) / float(radial_steps)
		var radius := lerpf(inner_radius, outer_radius, radial_t)
		for angular_index in range(angular_steps + 1):
			var angle := TAU * float(angular_index) / float(angular_steps)
			vertices.append(Vector3(cos(angle) * radius, sin(angle) * radius * 0.30, 0.0))
			normals.append(Vector3.BACK)
			uvs.append(Vector2(radial_t, float(angular_index) / float(angular_steps)))
			var density := clampf(0.60 + sin(radial_t * TAU * 9.0 + sin(angle * 9.0) * 0.35) * 0.22
				+ sin(angle * 37.0 + radial_t * 14.0) * 0.05, 0.18, 0.94)
			var color := Color(0.30, 0.30, 0.29).lerp(Color(0.93, 0.87, 0.74), density)
			var edge_fade := clampf(radial_t / 0.10, 0.0, 1.0) \
				* clampf((1.0 - radial_t) / 0.10, 0.0, 1.0)
			colors.append(Color(color.r, color.g, color.b, edge_fade * 0.85))
	for radial_index in range(radial_steps):
		for angular_index in range(angular_steps):
			var inner := radial_index * (angular_steps + 1) + angular_index
			var outer := (radial_index + 1) * (angular_steps + 1) + angular_index
			indices.append(inner)
			indices.append(outer)
			indices.append(outer + 1)
			indices.append(inner)
			indices.append(outer + 1)
			indices.append(inner + 1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _apply_window_stage(index: int, instant := false) -> void:
	if _window_planet == null:
		return
	var planet_visible := index < 2
	var planet_scale := 19.0 if index == 0 else 11.0
	var ring_visible := index < 2
	var ring_scale := 1.0 if index == 0 else 0.72
	var hole_visible := index > 0
	var hole_scale := 2.2 if index == 1 else 4.2
	if _window_tween != null:
		_window_tween.kill()
	if instant:
		_window_planet.visible = planet_visible
		_window_planet.scale = Vector3.ONE * planet_scale
		_window_ring.visible = ring_visible
		_window_ring.scale = Vector3.ONE * ring_scale
		_window_blackhole.visible = hole_visible
		_window_blackhole.scale = Vector3.ONE * hole_scale
		return
	_window_tween = create_tween().set_parallel(true)
	_window_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_window_tween.tween_property(_window_planet, "scale",
		Vector3.ONE * planet_scale, 4.0)
	_window_tween.tween_property(_window_planet, "visible", planet_visible, 0.8)
	_window_tween.tween_property(_window_ring, "scale",
		Vector3.ONE * ring_scale, 4.0)
	_window_tween.tween_property(_window_ring, "visible", ring_visible, 0.8)
	_window_tween.tween_property(_window_blackhole, "scale",
		Vector3.ONE * hole_scale, 4.0)
	_window_tween.tween_property(_window_blackhole, "visible", hole_visible, 0.8)
	_window_tween.finished.connect(func() -> void: _window_tween = null)


func _process(delta: float) -> void:
	if _window_planet == null:
		return
	_window_time += delta
	# Slow planetary rotation and a barely perceptible camera drift keep the
	# window alive without turning the observation room into an attraction.
	_window_planet.rotation.y = wrapf(_window_planet.rotation.y + delta * 0.018, -PI, PI)
	if _window_camera != null:
		_window_camera.position.x = sin(_window_time * 0.055) * 0.55
		_window_camera.position.y = 1.55 + sin(_window_time * 0.11) * 0.10


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "UpperDeckCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	# The interior is scaled (0.953, 1, 1); Jolt rejects non-uniform body scales
	# and silently uses an average, which makes ramps and treads disagree with
	# the visuals. Keep the body un-scaled and pre-scale the shapes instead.
	body.top_level = true
	add_child(body)
	var world := global_transform
	body.global_transform = Transform3D(world.basis.orthonormalized(), world.origin)
	for label in ["CabinFloor", "ObservationFloor", "TechFloor", "BackWalkway",
			"EastWalkway", "CabinBack", "CabinOuter", "CabinInner", "CabinHallWall",
			"CabinDoorHeader", "ObservationBack", "ObservationInner",
			"ObservationOuterFore", "ObservationOuterAft", "ObservationSill",
			"ObservationHeader", "ObservationHallWall", "ObservationDoorHeader",
			"HallOuterWall", "HallTechWallFore", "HallTechWallAft", "TechDoorHeader",
			"HallOuterAft", "TechOuter", "TechBack", "TechFront",
			"RelocatedCounterBase", "CrateA", "CrateB", "CrateC"]:
		_collide_named(body, label)
	# Invisible barriers along the open east and back atrium edges. The west
	# edge is now a real stair wall, so it needs no invisible barrier.
	_add_box(body, Vector3(0.08, 1.0, ATRIUM_Z1 - ATRIUM_Z0),
		Vector3(ATRIUM_X1, FLOOR + 0.5, (ATRIUM_Z0 + ATRIUM_Z1) * 0.5))
	_add_box(body, Vector3(ATRIUM_X1 - ATRIUM_X0, 1.0, 0.08),
		Vector3((ATRIUM_X0 + ATRIUM_X1) * 0.5, FLOOR + 0.5, ATRIUM_Z0))
	# Atrium-side stair wall (the door opening stays clear).
	_add_box(body, Vector3(0.12, CEIL - 0.02, 2.10),
		Vector3(ATRIUM_X0, (CEIL + 0.02) * 0.5, -1.95))
	_add_box(body, Vector3(0.12, CEIL - 2.42, 1.50),
		Vector3(ATRIUM_X0, (CEIL + 2.42) * 0.5, -0.15))
	# Smooth ramp collider over the visual treads, aligned to the tread noses:
	# y=0.217 at z=0, y=2.82 at z=-3. The old collider sat ~0.24 m high, which
	# made the first step unclimbable and the player float above the treads.
	var pitch := atan2(STAIR_RISE - 0.217, STAIR_RUN)
	var run := sqrt(STAIR_RUN * STAIR_RUN + (STAIR_RISE - 0.217) * (STAIR_RISE - 0.217))
	var ramp := _add_box(body, Vector3(1.0, 0.20, run),
		Vector3(-3.60, (0.217 + STAIR_RISE) * 0.5 - 0.10 * cos(pitch) - 0.030, -STAIR_RUN * 0.5))
	ramp.rotation.x = pitch
	# The glass is solid; otherwise the player can step through the window.
	_add_box(body, Vector3(0.06, 1.60, 2.40), Vector3(X0 - 0.02, FLOOR + 1.50, -6.0))
	for prop_name in ["CabinBunk", "CabinLocker", "CabinTable", "CabinChair",
			"ObservationConsole", "ObservationBench", "ObservationTable",
			"TechShelf", "TechLocker", "TechTable", "TechBin"]:
		var prop := find_child(prop_name, true, false) as Node3D
		if prop != null:
			_add_prop_collision(body, prop)


func _collide_named(body: StaticBody3D, label: String) -> void:
	var node := find_child(label, true, false) as MeshInstance3D
	if node == null or not (node.mesh is BoxMesh):
		return
	var mesh := node.mesh as BoxMesh
	_add_box(body, mesh.size, node.position, node.rotation)


func _add_box(body: StaticBody3D, size: Vector3, pos: Vector3,
		rot := Vector3.ZERO) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var scale := global_transform.basis.get_scale()
	box.size = size * scale
	shape.shape = box
	shape.position = pos * scale
	shape.rotation = rot
	body.add_child(shape)
	_collision_shapes.append(shape)
	return shape


func _add_prop_collision(body: StaticBody3D, prop: Node3D) -> void:
	var inv := global_transform.affine_inverse()
	var bounds := AABB()
	var has_bounds := false
	for node in prop.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var local := inv * mesh_node.global_transform
		var box: AABB = local * mesh_node.mesh.get_aabb()
		if not has_bounds:
			bounds = box
			has_bounds = true
		else:
			bounds = bounds.merge(box)
	if not has_bounds:
		return
	_add_box(body, bounds.size, bounds.position + bounds.size * 0.5)
