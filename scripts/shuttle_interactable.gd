extends Interactable
## Thin interactable for the shuttle: attached to an existing StaticBody3D prop,
## it reports "E was pressed on me" to the shuttle, which decides what happens.

var action_id := ""
var prompt := ""
var hub: Node


func interact(player: CharacterBody3D) -> void:
	if hub != null:
		hub.call("on_interact", action_id, player)


func focus_input(event: InputEvent) -> void:
	if hub != null and action_id == "reactor":
		hub.call("reactor_focus_input", event)
