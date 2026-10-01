extends MeshInstance3D

func _process(delta: float) -> void:
	#rotation.x += 0.2 * delta
	rotation.y += -0.2 * delta
