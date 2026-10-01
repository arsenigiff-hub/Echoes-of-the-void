extends Node3D
@onready var anim_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	anim_player.play("takeoff")

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "takeoff":
		get_tree().change_scene_to_file("res://scenes/main.tscn")
