extends Node3D

@onready var anim_player: AnimationPlayer = $AnimationPlayer

func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_play_button_pressed() -> void:
	$CanvasLayer/MenuButtons.hide()
	anim_player.play("new_animation")

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "new_animation":
		get_tree().change_scene_to_file("res://scenes/intro_cutscene.tscn")
