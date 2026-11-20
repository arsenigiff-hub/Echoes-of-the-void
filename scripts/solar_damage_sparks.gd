extends Node3D

const SPARK_TEXTURE := preload("res://assetss/fx/intro/spark.png")

var _particles: CPUParticles3D
var _interval: Timer
var _active := false


func _ready() -> void:
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.billboard_keep_scale = true
	glow.vertex_color_use_as_albedo = true
	glow.albedo_texture = SPARK_TEXTURE
	glow.disable_fog = true
	var sprite := QuadMesh.new()
	sprite.size = Vector2(0.27, 0.27)
	sprite.material = glow

	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.26, 0.70, 1.0])
	fade.colors = PackedColorArray([
		Color(1.0, 0.97, 0.80, 1.0), Color(1.0, 0.70, 0.28, 0.95),
		Color(1.0, 0.32, 0.08, 0.60), Color(0.42, 0.10, 0.02, 0.0),
	])
	_particles = CPUParticles3D.new()
	_particles.name = "Sparks"
	_particles.mesh = sprite
	_particles.amount = 26
	_particles.lifetime = 0.55
	_particles.one_shot = true
	_particles.explosiveness = 0.82
	_particles.randomness = 0.38
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = 0.12
	_particles.direction = Vector3(0.72, 0.52, 0.18).normalized()
	_particles.spread = 62.0
	_particles.gravity = Vector3.ZERO
	_particles.initial_velocity_min = 1.7
	_particles.initial_velocity_max = 4.6
	_particles.scale_amount_min = 0.42
	_particles.scale_amount_max = 1.20
	_particles.color_ramp = fade
	_particles.emitting = false
	_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_particles)

	_interval = Timer.new()
	_interval.name = "BurstInterval"
	_interval.one_shot = true
	_interval.timeout.connect(_burst)
	add_child(_interval)
	hide()


func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	visible = active
	if _active:
		_burst()
	else:
		_interval.stop()
		_particles.emitting = false


func _burst() -> void:
	if not _active:
		return
	_particles.restart()
	_particles.emitting = true
	_interval.start(randf_range(1.35, 2.35))
