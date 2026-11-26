extends SceneTree
## Smoke test for the slimmed-down game: main menu loads, the intro cutscene
## loads, finishing the intro opens the new shuttle, and the shuttle spawns the player.

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await create_timer(1.0).timeout
	menu.queue_free()
	await process_frame

	var intro := (load("res://scenes/intro_cutscene.tscn") as PackedScene).instantiate()
	root.add_child(intro)
	current_scene = intro
	await create_timer(3.0).timeout
	intro.call("_finish")
	await process_frame
	await process_frame
	var scene := current_scene
	if scene == null or scene.name != "ShuttleBlockout":
		failures.append("intro did not open the shuttle (current scene: %s)" % [scene.name if scene else "null"])
	elif scene.get_node_or_null("Player") == null:
		failures.append("shuttle has no player")
	else:
		await _verify_hints(scene)
	for failure in failures:
		print("FAIL: ", failure)
	print("GAME_FLOW ", "FAIL" if not failures.is_empty() else "OK")
	quit(1 if not failures.is_empty() else 0)


func _verify_hints(scene: Node) -> void:
	var flashlight := scene.get_node_or_null("Hud/FlashlightHint") as Label
	var objective := scene.get_node_or_null("Hud/PowerObjective") as Label
	if flashlight == null or not flashlight.visible or flashlight.text != "Нажмите F чтобы включить фонарик":
		failures.append("the flashlight hint is missing after the intro")
		return
	if objective == null or not objective.visible or objective.text != "Найдите включатель":
		failures.append("the startup objective is missing after the intro")
		return
	await create_timer(4.65).timeout
	if not flashlight.visible or flashlight.modulate.a < 0.99:
		failures.append("the flashlight hint began fading before five seconds")
	await create_timer(0.65).timeout
	if not flashlight.visible or flashlight.modulate.a >= 0.99 or flashlight.modulate.a <= 0.0:
		failures.append("the flashlight hint did not fade smoothly after five seconds")
	await create_timer(0.55).timeout
	if flashlight.visible or not objective.visible:
		failures.append("only the flashlight hint should have faded out")
