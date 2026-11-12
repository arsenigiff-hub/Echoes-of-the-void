extends Node3D

func _ready() -> void:
	for mesh in $blockbench_export/hull.get_children():
		if mesh is MeshInstance3D and mesh.mesh:
			var shape = mesh.mesh.create_trimesh_shape()
			var col = CollisionShape3D.new()
			col.shape = shape
			col.transform = mesh.transform
			$blockbench_export/hull.add_child(col)
