extends RefCounted

const FILES := ["01_ivory","02_dark_metal","03_brushed_steel","04_cable_rubber","05_pipe_red","06_copper","07_floor_grate","08_floor_tread","09_acoustic","10_vinyl","11_blanket","12_pillow","13_oxygen","14_locker","15_laminate","16_cardboard","17_paper","18_notebook","19_foil","20_hazard"]
const DETAILS := ["ivory","dark_metal","brushed_steel","cable_rubber","pipe_red","copper","floor_grate","floor_tread","acoustic","vinyl","blanket","pillow","oxygen","locker","laminate","cardboard","paper","notebook","foil","hazard"]
const BASE := {"ivory_aged":0,"structural_graphite":1,"brushed_edges":2,"black_rubber":3,"oxidised_red_cable":4,"deck_plate":7,"seat_olive_vinyl":9,"bedding":10,"label_ivory":16}

static func apply_to(root_node: Node) -> Dictionary:
	var cache := {}
	var used := {}
	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node := stack.pop_back() as Node
		for child in node.get_children(): stack.append(child)
		if not node is MeshInstance3D: continue
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null: continue
		for surface in mesh_node.mesh.get_surface_count():
			var original := mesh_node.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null: continue
			var name := original.resource_name
			if name.begins_with("wall_"):
				if not cache.has(name):
					var wall := original.duplicate() as StandardMaterial3D
					wall.albedo_texture = load("res://assetss/ship_wall_textures_v2/"+name+".png")
					wall.albedo_color = Color(0.9,0.9,0.9)
					wall.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
					wall.roughness = 0.91
					wall.metallic = 0.1
					cache[name] = wall
				mesh_node.set_surface_override_material(surface,cache[name])
				used[name] = true
				continue
			var index: int = BASE.get(name,-1)
			if name.begins_with("detail_"):
				index = DETAILS.find(name.trim_prefix("detail_"))
			if index < 0: continue
			if not cache.has(name):
				var material := original.duplicate() as StandardMaterial3D
				material.albedo_texture = load("res://assetss/ship_textures_pixel/"+FILES[index]+".png")
				material.albedo_color = Color(0.8,0.82,0.8)
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				material.roughness = 0.87
				material.metallic = 0.25 if index in [1,2,5,18] else 0.05
				cache[name] = material
			mesh_node.set_surface_override_material(surface,cache[name])
			used[FILES[index]] = true
	return used
