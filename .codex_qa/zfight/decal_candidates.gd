extends SceneTree

# Поиск свободного места для декали sign_decompression: рендерит кандидатов в одном кадре.
# Запуск: godot --path D:\4 --resolution 1680x1050 --script res://.codex_qa/zfight/decal_candidates.gd

const OUT := "res://.codex_qa/zfight/decal_candidates"

# name, pos, rot_deg
const CANDIDATES := [
	["00_ref_current", Vector3(-6.6, 3.5986, 10.498), Vector3(0, 0, 0)],
	["01_right_030", Vector3(-6.3, 3.5986, 10.498), Vector3(0, 0, 0)],
	["02_right_045", Vector3(-6.15, 3.5986, 10.498), Vector3(0, 0, 0)],
	["03_low", Vector3(-6.35, 2.95, 10.498), Vector3(0, 0, 0)],
	["04_high", Vector3(-6.35, 4.35, 10.498), Vector3(0, 0, 0)],
	["05_stbd", Vector3(-6.4, 3.5, 13.264), Vector3(0, 180, 0)],
]

var main: Node3D
var player: CharacterBody3D
var head: Node3D
var camera: Camera3D
var floor_y := 0.0


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(main)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await create_timer(1.8).timeout

	player = main.get_node("Player") as CharacterBody3D
	head = player.get_node("Head") as Node3D
	camera = player.get_node("Head/Camera3D") as Camera3D
	floor_y = player.global_position.y
	player.set_process_unhandled_input(false)

	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.96, 0.9)
	lamp.light_energy = 4.0
	lamp.omni_range = 7.0
	lamp.position = Vector3(0.0, 1.9, 0.0)
	camera.add_child(lamp)

	var decal := _find_decal(main, "sign_decompression")
	if decal == null:
		print("НЕ НАЙДЕНА декаль sign_decompression")
		quit()
		return
	print("decal node=", decal.name, " pos=", decal.global_position)

	for cand in CANDIDATES:
		decal.global_position = cand[1]
		decal.rotation_degrees = cand[2]
		await create_timer(0.2).timeout
		await _shoot(String(cand[0]))

	print("=== done ===")
	quit()


func _find_decal(node: Node, tex: String) -> Node3D:
	if node is Node3D and node is MeshInstance3D and String(node.name) == "Decal_" + tex:
		return node as Node3D
	for c in node.get_children():
		var found := _find_decal(c, tex)
		if found != null:
			return found
	return null


func _place(pos: Vector3, look_at: Vector3) -> void:
	player.global_position = Vector3(pos.x, floor_y + pos.y, pos.z)
	player.velocity = Vector3.ZERO
	var eye := player.global_position + Vector3(0, 1.5, 0)
	var direction: Vector3 = (look_at - eye).normalized()
	head.rotation.y = atan2(-direction.x, -direction.z) - player.rotation.y
	camera.rotation.x = asin(clampf(direction.y, -1.0, 1.0))


func _shoot(shot_name: String) -> void:
	# чуть отойти, чтобы табличка и окружение попали в кадр целиком
	_place(Vector3(-6.0, 0.0, 11.55), Vector3(-6.6, 3.5, 10.5))
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, shot_name])
	print("saved ", shot_name)
