extends SceneTree

# Контрольные кадры мест, найденных аудитом model-auditor:
# стыки зон (двойная геометрия), наложенные декали, швы каюты.
# Запуск: godot --path D:\4 --resolution 1680x1050 --script res://.codex_qa/model_audit/confirm_shots.gd

const OUT := "res://.codex_qa/model_audit/shots"

const SHOTS := [
	{"name": "01_joint_bridge_floor", "pos": Vector3(8.95, 0.0, 11.9), "look": Vector3(9.75, 2.20, 11.9)},
	{"name": "02_joint_bridge_ceiling", "pos": Vector3(8.9, 0.0, 11.9), "look": Vector3(9.75, 4.68, 11.9)},
	{"name": "03_joint_airlock_floor", "pos": Vector3(-3.45, 0.0, 11.9), "look": Vector3(-4.05, 2.30, 11.9)},
	{"name": "04_decal_pair_airlock", "pos": Vector3(-6.25, 0.0, 11.45), "look": Vector3(-7.0, 3.45, 10.5)},
	{"name": "05_quarters_floor_seam", "pos": Vector3(4.55, 0.0, 9.95), "look": Vector3(5.0, 2.25, 9.0)},
]

var main: Node3D
var player: CharacterBody3D
var head: Node3D
var camera: Camera3D
var floor_y := 0.0


func _initialize() -> void:
	_run()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(1.6).timeout

	player = main.get_node("Player") as CharacterBody3D
	head = player.get_node("Head") as Node3D
	camera = player.get_node("Head/Camera3D") as Camera3D
	floor_y = player.global_position.y
	player.set_process_unhandled_input(false)

	# QA-подсветка для наглядности (не сохраняется в проект): лампа у камеры.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.96, 0.9)
	lamp.light_energy = 4.0
	lamp.omni_range = 7.0
	lamp.position = Vector3(0.0, 1.9, 0.0)
	camera.add_child(lamp)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	for shot in SHOTS:
		_place(shot["pos"] as Vector3, shot["look"] as Vector3)
		await create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "%s/%s.png" % [OUT, shot["name"]]
		img.save_png(ProjectSettings.globalize_path(path))
		print("saved ", path)

	print("=== done ===")
	quit()


func _place(pos: Vector3, look_at: Vector3) -> void:
	player.global_position = Vector3(pos.x, floor_y + pos.y, pos.z)
	player.velocity = Vector3.ZERO
	var eye := player.global_position + Vector3(0, 1.5, 0)
	var direction: Vector3 = (look_at - eye).normalized()
	head.rotation.y = atan2(-direction.x, -direction.z) - player.rotation.y
	camera.rotation.x = asin(clampf(direction.y, -1.0, 1.0))
