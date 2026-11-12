extends SceneTree

# Сравнение поз игрока в контрольных точках для двух сцен (baseline/fixed).
# Запуск: godot --headless --path D:\4 --script res://.codex_qa/zfight/probe_pose.gd -- <scene_path>

const SHOTS := [
	{"name": "01_bridge_floor", "pos": Vector3(8.95, 0.0, 11.9), "look": Vector3(9.75, 2.20, 11.9)},
	{"name": "02_bridge_ceiling", "pos": Vector3(8.9, 0.0, 11.9), "look": Vector3(9.75, 4.68, 11.9)},
	{"name": "03_airlock_floor", "pos": Vector3(-3.45, 0.0, 11.9), "look": Vector3(-4.05, 2.30, 11.9)},
	{"name": "04_decal_pair", "pos": Vector3(-6.25, 0.0, 11.45), "look": Vector3(-7.0, 3.45, 10.5)},
	{"name": "05_quarters_seam", "pos": Vector3(4.55, 0.0, 9.95), "look": Vector3(5.0, 2.25, 9.0)},
]

var main: Node3D
var player: CharacterBody3D
var head: Node3D
var camera: Camera3D
var floor_y := 0.0


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var path := "res://scenes/main.tscn"
	if args.size() > 0:
		path = args[0]
	main = (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(main)
	await create_timer(1.6).timeout
	player = main.get_node("Player") as CharacterBody3D
	head = player.get_node("Head") as Node3D
	camera = player.get_node("Head/Camera3D") as Camera3D
	player.set_process_unhandled_input(false)
	floor_y = player.global_position.y
	print("SCENE=", path, " spawn=", player.global_position)
	for shot in SHOTS:
		_place(shot["pos"], shot["look"])
		await create_timer(0.35).timeout
		print(shot["name"], " pos=", player.global_position,
				" head_yaw=", snappedf(rad_to_deg(head.rotation.y), 0.01),
				" cam_pitch=", snappedf(rad_to_deg(camera.rotation.x), 0.01))
	print("=== done ===")
	quit()


func _place(pos: Vector3, look_at: Vector3) -> void:
	player.global_position = Vector3(pos.x, floor_y + pos.y, pos.z)
	player.velocity = Vector3.ZERO
	var eye := player.global_position + Vector3(0, 1.5, 0)
	var direction: Vector3 = (look_at - eye).normalized()
	head.rotation.y = atan2(-direction.x, -direction.z) - player.rotation.y
	camera.rotation.x = asin(clampf(direction.y, -1.0, 1.0))
