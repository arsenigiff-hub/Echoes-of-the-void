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
	var repair_hands := player.camera.get_node_or_null("SolarRepairHands") as Node3D
	var solar := main.get_node("SolarArrayRepair") as StaticBody3D
	var interior := main.get_node("ShipInterior") as Node3D
	assert(not player.is_interacting, "Wake sequence must restore control before the EVA test")
	assert(repair_hands != null and not repair_hands.visible,
		"Repair hands must stay hidden outside manual repair actions")

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
	for code: Key in [KEY_W, KEY_D]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = true
		story.call("focus_story_target", "solar", event)
	story.call("toggle_repair", "solar", solar, player)
	assert(repair_hands != null and repair_hands.visible,
		"Suit-gloved hands must appear for manual solar repair")
	story.call("toggle_repair", "solar", solar, player) # open cover, leave repair incomplete
	assert(int(story.get("_solar_repair_step")) == 1, "The test must leave the repair partially complete")

	var checkpoint := interior.to_global(eva.get("return_pos"))
	eva.set("oxygen_remaining_seconds", 0.1)
	eva.call("_tick_oxygen", 0.2)
	await create_timer(5.4).timeout

	assert(not bool(eva.get("is_outside")), "Oxygen depletion must return the player inside")
	assert(not player.eva_mode, "Checkpoint return must restore normal movement")
	assert(int(story.get("stage")) == 0, "Oxygen failure must preserve the current story stage")
	assert(int(story.get("_solar_repair_step")) == 0, "Oxygen failure must reset the incomplete EVA repair")
	assert(repair_hands != null and not repair_hands.visible,
		"Repair hands must hide when EVA repair is interrupted")
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
