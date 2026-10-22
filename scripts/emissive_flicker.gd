extends MeshInstance3D

# Мерцание светящейся панели (трубки/плафона). Материал дублируется,
# чтобы у каждой панели было своё независимое мерцание.

@export var base_energy: float = -1.0
@export_range(0.0, 1.0, 0.01) var flicker_amount: float = 0.18
@export var speed: float = 9.0
@export_range(0.0, 1.0, 0.01) var dropout_chance: float = 0.02
@export var dropout_min: float = 0.04
@export var dropout_max: float = 0.25

var _material: StandardMaterial3D
var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _drop_left := 0.0


func _ready() -> void:
	_rng.randomize()
	if material_override is StandardMaterial3D:
		_material = (material_override as StandardMaterial3D).duplicate()
		material_override = _material
		if base_energy < 0.0:
			base_energy = _material.emission_energy_multiplier
	set_process(_material != null)


func _process(delta: float) -> void:
	_time += delta

	var n := sin(_time * speed + 0.7) * 0.5
	n += sin(_time * speed * 2.7 + 1.1) * 0.32
	n += sin(_time * speed * 6.3 + 2.2) * 0.18
	n = clampf(n * 0.5 + 0.5, 0.0, 1.0)

	var energy := base_energy * (1.0 - flicker_amount + flicker_amount * n)

	if _drop_left <= 0.0 and dropout_chance > 0.0:
		if _rng.randf() < dropout_chance * delta:
			_drop_left = _rng.randf_range(dropout_min, dropout_max)
	if _drop_left > 0.0:
		_drop_left -= delta
		energy = 0.0

	_material.emission_energy_multiplier = maxf(energy, 0.0)
