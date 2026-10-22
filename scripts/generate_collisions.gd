@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	_add_collisions(scene)
	return scene

func _add_collisions(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		node.create_trimesh_collision() # или node.create_convex_collision()
	for child in node.get_children():
		_add_collisions(child)
