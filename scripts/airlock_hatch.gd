extends Interactable

# Триггер люка шлюза: игрок смотрит на него лучом и жмёт E.
# Физически ничего не блокирует (collision_layer = 2), только ловится лучом.

var controller: Node = null
var outside_hatch := false


func interact(player: CharacterBody3D) -> void:
	if controller != null:
		controller.request_airlock(player)
