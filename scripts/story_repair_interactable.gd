class_name StoryRepairInteractable
extends Interactable

var progression: Node
var repair_id := ""


func interact(player: CharacterBody3D) -> void:
	if progression != null:
		progression.call("toggle_repair", repair_id, self, player)


func focus_input(event: InputEvent) -> void:
	if progression != null:
		progression.call("focus_story_target", repair_id, event)
