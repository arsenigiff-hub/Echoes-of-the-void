extends SceneTree

# Сохраняем небо (панорама звёзд) как отдельный ресурс для основной сцены.
# Запуск: godot --headless --path D:\4 --script res://.codex_qa/shipassemble/save_sky.gd


func _initialize() -> void:
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assetss/space/starfield_pano.png") as Texture2D
	pano.energy_multiplier = 1.1
	var sky := Sky.new()
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var err := ResourceSaver.save(sky, "res://scenes/sky_space.tres")
	print("sky save err=", err)
	print("=== done ===")
	quit()
