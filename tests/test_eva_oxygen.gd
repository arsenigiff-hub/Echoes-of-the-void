extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(4.7).timeout

	var player := main.get_node("Player") as Player
	var eva := main.get_node("EVA")	
	var story := main.get_node("StoryProgression")
	var solar := main.find_child("SolarArrayRepair_fore", true, false) as StaticBody3D
	var interior := main.get_node("ShipInterior") as Node3D
	assert(not player.is_interacting, "Wake sequence must restore control before the EVA test")
	assert(solar != null, "The fore solar wing must be present")

	# Enter the outside state through the same explicit E action used in play.
	eva.set("_airlock_state", "vacuum")
	eva.set("_outer_hatch_open", true)
	eva.call("_exit_to_space")
	assert(bool(eva.get("is_outside")), "E exit must enter EVA mode")
	assert(float(eva.get("oxygen_remaining_seconds")) > 100.0, "EVA entry must start an oxygen timer")

	player.global_position = solar.global_position + Vector3(2.1, 0.4, 2.7)
	story.call("_update_targets")
	story.call("toggle_repair", "solar", solar, player)
	assert(player.is_interacting, "Solar repair must start while outside")
	assert(player.camera_position_managed, "Solar repair must take camera control")
	# Leave the solar sequence active; oxygen depletion must cancel it.

	var checkpoint := interior.to_global(eva.get("return_pos"))
	eva.set("oxygen_remaining_seconds", 0.1)
	eva.call("_tick_oxygen", 0.2)
	await create_timer(5.4).timeout

	assert(not bool(eva.get("is_outside")), "Oxygen depletion must return the player inside")
	assert(not player.eva_mode, "Checkpoint return must restore normal movement")
	assert(int(story.get("stage")) == 0, "Oxygen failure must preserve the current story stage")
	assert(not player.is_interacting, "Oxygen failure must release the solar interaction")
	assert(story.get("_operating_solar_wing") == null,
		"Oxygen failure must reset the incomplete EVA repair")
	assert(not player.camera_position_managed,
		"Oxygen failure must restore the player camera")
	assert(player.global_position.distance_to(checkpoint) < 1.0, "Player must return to the hatch checkpoint")
	assert(not bool(eva.get("_outer_hatch_open")), "Outer hatch must close after checkpoint return")
	assert(not bool(eva.get("_interior_door_open")), "Inner pressure door must close after checkpoint return")
	assert(float(eva.get("oxygen_remaining_seconds")) >= 119.0, "Checkpoint return must refill suit oxygen")

	for node in main.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()
	main.queue_free()
	current_scene = null
	await process_frame
	await process_frame
	print("EVA_OXYGEN_CHECKPOINT_OK: depleted -> hatch checkpoint -> retryable repair")
	quit(0)
