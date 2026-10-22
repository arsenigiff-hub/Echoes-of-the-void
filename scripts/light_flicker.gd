extends Light3D

# Мерцание лампы «умирающего корабля»: медленное неровное дыхание яркости +
# редкие провалы в ноль (выключение/перезажигание питания).
# Вешается на OmniLight3D / SpotLight3D / DirectionalLight3D.

## Базовая яркость. Если -1, берётся текущая light_energy на старте.
@export var base_energy: float = -1.0
## Насколько сильно яркость гуляет (0.25 = ±25%).
@export_range(0.0, 1.0, 0.01) var flicker_amount: float = 0.25
## Скорость гуляния.
@export var speed: float = 8.0
## Вероятность полного провала в секунду (0.05 = в среднем раз в 20 сек).
@export_range(0.0, 2.0, 0.01) var dropout_chance: float = 0.05
## Длительность провала, сек.
@export var dropout_min: float = 0.05
@export var dropout_max: float = 0.5

var _time := 0.0
var _rng := RandomNumberGenerator.new()
var _drop_left := 0.0


func _ready() -> void:
	_rng.randomize()
	if base_energy < 0.0:
		base_energy = light_energy
	set_process(true)


func _process(delta: float) -> void:
	_time += delta

	# три несинхронные синусоиды — «живой» неровный свет
	var n := sin(_time * speed + 1.3) * 0.5
	n += sin(_time * speed * 2.37 + 4.1) * 0.32
	n += sin(_time * speed * 5.11 + 0.7) * 0.18
	n = clampf(n * 0.5 + 0.5, 0.0, 1.0)

	var energy := base_energy * (1.0 - flicker_amount + flicker_amount * n)

	# полный провал питания
	if _drop_left <= 0.0 and dropout_chance > 0.0:
		if _rng.randf() < dropout_chance * delta:
			_drop_left = _rng.randf_range(dropout_min, dropout_max)
	if _drop_left > 0.0:
		_drop_left -= delta
		energy = 0.0

	light_energy = maxf(energy, 0.0)
