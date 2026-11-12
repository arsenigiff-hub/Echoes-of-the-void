extends SceneTree

# Аудит геометрии ECHOES OF THE VOID: инстанцирует scenes/main.tscn headless,
# даёт отработать ShipDresser/ScreenDresser, снимает ВСЕ MeshInstance3D
# (global AABB, трансформ, материалы, видимость) и пишет сырые данные в JSON.
# Детекторы пар считаются отдельно (python), чтобы не гонять движок повторно.
#
# Запуск: D:\Godot_v4.7.2-stable_win64.exe --headless --path D:\4 \
#           --script res://.codex_qa/model_audit/audit.gd
#
# НИЧЕГО в проекте не меняет: только читает main.tscn и пишет файлы в
# res://.codex_qa/model_audit/.

const OUT_DIR := "res://.codex_qa/model_audit/"
const FRAMES_TO_SETTLE := 6

var main_root: Node3D
var records: Array = []
var lights: Array = []
var nodes_total := 0
var colliders := 0
var particles: Array = []
var mesh_nodes: Array = []
var mesh_aabbs: Array[AABB] = []
var mesh_paths: Array[String] = []
var probes: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var t_load := Time.get_ticks_usec()
	var packed: PackedScene = load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		push_error("audit: не удалось загрузить main.tscn")
		quit(1)
		return
	main_root = packed.instantiate() as Node3D
	root.add_child(main_root)
	for i in FRAMES_TO_SETTLE:
		await process_frame
	var t_ready := Time.get_ticks_usec()

	_scan(main_root)
	_probe_thin_quads()
	print("[audit] nodes=", nodes_total, " meshes=", records.size(),
			" lights=", lights.size(), " colliders=", colliders,
			" particles=", particles.size(), " probes=", probes.size())
	print("[audit] load+settle ms=", (t_ready - t_load) / 1000.0)

	var meta := {
		"godot_version": Engine.get_version_info()["string"],
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
		"headless": DisplayServer.get_name(),
		"viewport": [root.size.x, root.size.y],
		"nodes_total": nodes_total,
		"mesh_instances": records.size(),
		"lights": lights.size(),
		"colliders": colliders,
		"particles": particles,
		"settle_frames": FRAMES_TO_SETTLE,
		"load_settle_ms": (t_ready - t_load) / 1000.0,
		"main_scene_nodes": _count_nodes(main_root),
	}
	_write_json("meshes.json", records)
	_write_json("probes.json", probes)
	_write_json("lights.json", lights)
	_write_json("meta.json", meta)
	_write_json("nodes.json", _node_dump(main_root))
	print("[audit] written to ", OUT_DIR)
	quit()


func _count_nodes(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count_nodes(c)
	return n


# ------------------------------------------------------------------ скан ----

func _scan(node: Node) -> void:
	nodes_total += 1
	if node is Light3D:
		_record_light(node as Light3D)
	if node is CollisionShape3D:
		colliders += 1
	if node is CPUParticles3D:
		var cp := node as CPUParticles3D
		particles.append({
			"path": _rel_path(cp),
			"amount": cp.amount,
			"mesh": _mesh_brief(cp.mesh),
			"material": _mat_brief(cp.material_override),
		})
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		_record_mesh(node as MeshInstance3D)
	for c in node.get_children():
		_scan(c)


func _rel_path(node: Node) -> String:
	var p := String(node.get_path())
	if p.begins_with("/root/main/"):
		return p.substr(11)
	return p


func _record_light(l: Light3D) -> void:
	var d := {
		"path": _rel_path(l),
		"class": l.get_class(),
		"visible": l.is_visible_in_tree(),
		"pos": _v3(l.global_position),
		"energy": l.light_energy,
		"color": [l.light_color.r, l.light_color.g, l.light_color.b],
		"shadow": l.shadow_enabled,
	}
	if l is OmniLight3D:
		var o := l as OmniLight3D
		d["range"] = o.omni_range
		d["attenuation"] = o.omni_attenuation
	elif l is SpotLight3D:
		var s := l as SpotLight3D
		d["range"] = s.spot_range
		d["angle"] = s.spot_angle
	elif l is DirectionalLight3D:
		d["range"] = -1.0
	lights.append(d)


func _record_mesh(mi: MeshInstance3D) -> void:
	var world_aabb := _world_aabb(mi)
	var surf := []
	var tex_count := 0
	var transparency := 0
	var shader := false
	var all_faces: PackedVector3Array = mi.mesh.get_faces()
	var tri := all_faces.size() / 3
	for i in mi.mesh.get_surface_count():
		var ov: Material = mi.get_surface_override_material(i)
		var src: Material = mi.mesh.surface_get_material(i)
		var use: Material = ov if ov != null else src
		var sd := _mat_brief(use)
		sd["override"] = ov != null
		if use != null:
			if use is BaseMaterial3D:
				transparency = maxi(transparency, (use as BaseMaterial3D).transparency)
			elif use is ShaderMaterial:
				shader = true
			if sd.has("tex") and sd["tex"] != "":
				tex_count += 1
		surf.append(sd)
	var override_brief := _mat_brief(mi.material_override)
	var basis := mi.global_transform.basis
	var scale := basis.get_scale()
	# "осевое" выравнивание: насколько базис близок к осевому (для доверия AABB)
	var ax := transform_aabb_quality(basis)
	records.append({
		"id": records.size(),
		"path": _rel_path(mi),
		"name": String(mi.name),
		"parent": String(mi.get_parent().name) if mi.get_parent() != null else "",
		"class": mi.get_class(),
		# источник: ближайший предок-инстанс GLB (кроме корня сцены корабля)
		"glb": _instance_source(mi),
		"pos": _v3(mi.global_position),
		"basis": [basis.x.x, basis.x.y, basis.x.z,
				basis.y.x, basis.y.y, basis.y.z,
				basis.z.x, basis.z.y, basis.z.z],
		"scale": _v3(scale),
		"rot_deg": _v3(mi.global_rotation_degrees),
		"axis_aligned": ax,
		"aabb": {"min": _v3(world_aabb.position),
				"max": _v3(world_aabb.position + world_aabb.size),
				"size": _v3(world_aabb.size)},
		"local_aabb": {"pos": _v3(mi.mesh.get_aabb().position),
				"size": _v3(mi.mesh.get_aabb().size)},
		"surfaces": surf,
		"material_override": override_brief,
		"surface_count": mi.mesh.get_surface_count(),
		"triangles": tri,
		"textured_surfaces": tex_count,
		"transparency": transparency,
		"shader_material": shader,
		"visible": mi.is_visible_in_tree(),
		"node_visible": mi.visible,
		"cast_shadow": mi.cast_shadow,
		"extra_cull": mi.extra_cull_margin,
		"mesh_id": mi.mesh.get_instance_id(),
		"mesh_res_path": mi.mesh.resource_path,
		"mesh_name": String(mi.mesh.resource_name),
		# осевые плоскости поверхностей в мировых координатах (для детекта
		# настоящих копланарных наложений, а не только AABB)
		"planes": _world_planes(all_faces, mi.global_transform),
	})
	mesh_nodes.append(mi)
	mesh_aabbs.append(world_aabb)
	mesh_paths.append(_rel_path(mi))


# ------------------------------------------------------- плоскости мира -----
# Триангулируем меш в мир и собираем почти-осевые грани: для каждого
# (ось, знак нормали) копим площадь и 2D-рамку на плоскости. Это даёт точные
# плоскости поверхностей (например верх плитки пола), по которым потом
# ищутся совпадающие плоскости у разных объектов (z-fighting).

func _world_planes(faces: PackedVector3Array, xf: Transform3D) -> Array:
	var buckets := {}
	var n := faces.size()
	var i := 0
	while i + 2 < n:
		var a := xf * faces[i]
		var b := xf * faces[i + 1]
		var c := xf * faces[i + 2]
		i += 3
		var nrm := (b - a).cross(c - a)
		var ln := nrm.length()
		if ln < 1e-8:
			continue
		nrm /= ln
		var area := ln * 0.5
		var ax := 0
		var best := absf(nrm.x)
		if absf(nrm.y) > best:
			ax = 1
			best = absf(nrm.y)
		if absf(nrm.z) > best:
			ax = 2
			best = absf(nrm.z)
		if best < 0.97:
			continue
		var sign := 1 if nrm[ax] > 0.0 else -1
		var coord := (a[ax] + b[ax] + c[ax]) / 3.0
		var u_ax := (ax + 1) % 3
		var v_ax := (ax + 2) % 3
		var ua := a[u_ax]
		var ub := b[u_ax]
		var uc := c[u_ax]
		var va := a[v_ax]
		var vb := b[v_ax]
		var vc := c[v_ax]
		var u_min := minf(ua, minf(ub, uc))
		var u_max := maxf(ua, maxf(ub, uc))
		var v_min := minf(va, minf(vb, vc))
		var v_max := maxf(va, maxf(vb, vc))
		var q := roundi(coord * 2000.0)
		var key := "%d_%d_%d" % [ax, sign, q]
		var bkt: Dictionary = buckets.get(key, {})
		if bkt.is_empty():
			bkt = {"ax": ax, "sign": sign, "wsum": 0.0, "area": 0.0,
					"u0": u_min, "u1": u_max, "v0": v_min, "v1": v_max}
			buckets[key] = bkt
		bkt["wsum"] = float(bkt["wsum"]) + coord * area
		bkt["area"] = float(bkt["area"]) + area
		bkt["u0"] = minf(float(bkt["u0"]), u_min)
		bkt["u1"] = maxf(float(bkt["u1"]), u_max)
		bkt["v0"] = minf(float(bkt["v0"]), v_min)
		bkt["v1"] = maxf(float(bkt["v1"]), v_max)
	var out := []
	for key in buckets:
		var bkt: Dictionary = buckets[key]
		var area := float(bkt["area"])
		if area < 0.0002:
			continue
		out.append({
			"ax": int(bkt["ax"]),
			"sign": int(bkt["sign"]),
			"coord": float(bkt["wsum"]) / area,
			"area": area,
			"u0": float(bkt["u0"]),
			"u1": float(bkt["u1"]),
			"v0": float(bkt["v0"]),
			"v1": float(bkt["v1"]),
		})
	out.sort_custom(func(p, q): return float(p["area"]) > float(q["area"]))
	if out.size() > 64:
		out.resize(64)
	return out


func transform_aabb_quality(b: Basis) -> float:
	# 1.0 = строго осевой базис; меньше = повёрнут (AABB раздувается)
	var cols: Array[Vector3] = [b.x, b.y, b.z]
	var score := 0.0
	for v in cols:
		var a: Vector3 = v.abs()
		var mx := maxf(a.x, maxf(a.y, a.z))
		if mx > 0.0001:
			score += mx / (a.x + a.y + a.z)
	return clampf(score / 3.0, 0.0, 1.0)


# --------------------------------------------------- лучи в тонкие квады ----
# Для декалей/экранов/бумажек меряем фактический зазор до ближайшей реальной
# поверхности вдоль нормали: луч назад (куда «приклеен» объект) и вперёд
# (не перекрыт ли он чем-то). Это отсекает выдумки и ловит висящие/утопленные
# таблички точными числами.

func _probe_thin_quads() -> void:
	for idx in records.size():
		var rec: Dictionary = records[idx]
		var aabb := mesh_aabbs[idx]
		var asz := aabb.size
		var mn := minf(asz.x, minf(asz.y, asz.z))
		var mx := maxf(asz.x, maxf(asz.y, asz.z))
		var is_thin := mn < 0.02
		if not is_thin or mx < 0.05:
			continue
		var normal := Vector3(0, 0, 1)
		var node3d := mesh_nodes[idx] as Node3D
		var b: Basis = node3d.global_transform.basis
		normal = b.z.normalized()
		var center := aabb.position + aabb.size * 0.5
		var front := _ray_scene(center, normal, idx, 0.75)
		var back := _ray_scene(center, -normal, idx, 0.75)
		probes.append({
			"id": idx,
			"path": rec["path"],
			"name": rec["name"],
			"glb": rec["glb"],
			"center": _v3(center),
			"normal": _v3(normal),
			"size": _v3(aabb.size),
			"hit_front": front,
			"hit_back": back,
		})


func _ray_scene(origin: Vector3, dir: Vector3, skip_idx: int, max_dist: float) -> Dictionary:
	var best := {"dist": -1.0}
	var end := origin + dir * max_dist
	var seg := AABB(origin, Vector3.ZERO)
	seg = seg.expand(end)
	for idx in records.size():
		if idx == skip_idx:
			continue
		var ab := mesh_aabbs[idx]
		if not ab.intersects(seg.grow(0.01)):
			continue
		var mi: MeshInstance3D = mesh_nodes[idx]
		var faces: PackedVector3Array = mi.mesh.get_faces()
		var xf: Transform3D = mi.global_transform
		var i := 0
		while i + 2 < faces.size():
			var a := xf * faces[i]
			var bb := xf * faces[i + 1]
			var cc := xf * faces[i + 2]
			i += 3
			var t := _ray_tri(origin, dir, a, bb, cc)
			if t >= 0.0 and t <= max_dist and (float(best["dist"]) < 0.0 or t < float(best["dist"])):
				var nrm := (bb - a).cross(cc - a)
				var ln := nrm.length()
				var dot := 0.0
				if ln > 1e-9:
					nrm /= ln
					dot = nrm.dot(dir)
				best = {"dist": t, "path": mesh_paths[idx], "glb": records[idx]["glb"],
						"tri_dot": dot, "point": _v3(origin + dir * t)}
	return best


func _ray_tri(orig: Vector3, dir: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var pvec := dir.cross(e2)
	var det := e1.dot(pvec)
	if absf(det) < 1e-10:
		return -1.0
	var inv := 1.0 / det
	var tvec := orig - a
	var u := tvec.dot(pvec) * inv
	if u < -0.00001 or u > 1.00001:
		return -1.0
	var qvec := tvec.cross(e1)
	var v := dir.dot(qvec) * inv
	if v < -0.00001 or u + v > 1.00001:
		return -1.0
	var t := e2.dot(qvec) * inv
	if t > 0.00001:
		return t
	return -1.0


func _instance_source(mi: MeshInstance3D) -> String:
	var cur: Node = mi
	while cur != null:
		var sfp := cur.scene_file_path
		if sfp != "":
			if sfp.contains("ship_interior.tscn") or sfp.contains("main.tscn"):
				return ""
			# ищем самый глубокий (ближайший) инстанс GLB
			return sfp
		cur = cur.get_parent()
	return ""


func _mesh_brief(mesh: Mesh) -> Dictionary:
	if mesh == null:
		return {}
	return {
		"class": mesh.get_class(),
		"resource_path": mesh.resource_path,
		"name": String(mesh.resource_name),
		"surfaces": mesh.get_surface_count(),
	}


func _mat_brief(mat: Material) -> Dictionary:
	if mat == null:
		return {"cls": "", "name": "", "tex": "", "transparency": 0, "tex_key": ""}
	var d := {
		"cls": mat.get_class(),
		"name": String(mat.resource_name),
		"tex": "",
		"transparency": 0,
		"tex_key": "",
	}
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		d["transparency"] = bm.transparency
		d["cull"] = bm.cull_mode
		d["shading"] = bm.shading_mode
		d["unshaded"] = bm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
		d["emission"] = bm.emission_enabled
		d["vertex_color"] = bm.vertex_color_use_as_albedo
		var tex := bm.albedo_texture
		if tex != null:
			d["tex"] = tex.resource_path
			var tex_key := tex.resource_path.get_file().get_basename()
			d["tex_key"] = tex_key
	elif mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		d["transparency"] = 1
		d["shader"] = true
		if sm.shader != null:
			d["shader_code_len"] = sm.shader.code.length()
			var params := {}
			for p in sm.get_property_list():
				var pn := String(p["name"])
				if pn.begins_with("shader_parameter/") and pn != "shader_parameter/grime_tex":
					params[pn] = str(sm.get_shader_parameter(pn.trim_prefix("shader_parameter/")))
			d["shader_params"] = params
	return d


# ---------------------------------------------------------------- AABB ------

func _world_aabb(mi: MeshInstance3D) -> AABB:
	var la: AABB = mi.mesh.get_aabb()
	var xf: Transform3D = mi.global_transform
	var out := AABB()
	var first := true
	for i in 8:
		var corner := la.position + Vector3(
				la.size.x if (i & 1) != 0 else 0.0,
				la.size.y if (i & 2) != 0 else 0.0,
				la.size.z if (i & 4) != 0 else 0.0)
		var w := xf * corner
		if first:
			out = AABB(w, Vector3.ZERO)
			first = false
		else:
			out = out.expand(w)
	return out


func _v3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _node_dump(node: Node) -> Array:
	var out := []
	_dump_rec(node, out)
	return out


func _dump_rec(node: Node, out: Array) -> void:
	out.append({
		"path": _rel_path(node),
		"type": node.get_class(),
		"visible": node.is_visible_in_tree() if node is Node3D else true,
		"source": node.scene_file_path,
		"children": node.get_child_count(),
	})
	for c in node.get_children():
		_dump_rec(c, out)


func _write_json(file_name: String, data: Variant) -> void:
	var f := FileAccess.open(OUT_DIR + file_name, FileAccess.WRITE)
	if f == null:
		push_error("audit: не могу открыть " + OUT_DIR + file_name)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
