extends Node3D

# Космос по сюжету: три стадии пролёта.
#   0 — Солнечная система: газовый гигант с кольцами за бортом, звёзды.
#   1 — пустота: планета уходит в сторону/назад, звёзды, чёрная дыра вдали.
#   2 — чёрная дыра: планета скрыта, дыра занимает окно, аккреция близко.
# Сцена только управляет объектами, созданными в ship_interior.tscn
# (SpaceGasGiant / SpaceRing / SpaceBlackHole). Триггерить переходы может
# сюжетный скрипт вызовом set_stage(1) / set_stage(2).

signal stage_changed(index: int)

@export var initial_stage: int = 0
@export var transition_time: float = 7.0
## Медленный дрейф планеты в первой стадии (м/с), чтобы космос не был статикой.
@export var drift_speed: float = 0.35

var _gas: Node3D
var _ring: Node3D
var _blackhole: Node3D
var _tween: Tween
var _stage := 0
var _base := {}

# стадия: смещение и масштаб планет; дыра; видимость
const STAGES := [
	{
		"gas_offset": Vector3.ZERO,
		"gas_scale": 1.0,
		"ring_scale": 1.0,
		"ring_visible": true,
		"bh_offset": Vector3.ZERO,
		"bh_scale": 1.0,
		"bh_visible": true,
		"gas_visible": true,
	},
	{
		"gas_offset": Vector3(40.0, 30.0, -260.0),
		"gas_scale": 0.72,
		"ring_scale": 0.72,
		"ring_visible": true,
		"bh_offset": Vector3(-260.0, -9.0, 156.0),
		"bh_scale": 1.5,
		"bh_visible": true,
		"gas_visible": true,
	},
	{
		"gas_offset": Vector3(-60.0, 60.0, -420.0),
		"gas_scale": 0.35,
		"ring_scale": 0.35,
		"ring_visible": false,
		"bh_offset": Vector3(-340.0, -38.0, 90.0),
		"bh_scale": 5.6,
		"bh_visible": true,
		"gas_visible": false,
	},
]


func _ready() -> void:
	_find_space_objects()
	if _gas == null:
		push_warning("SpaceStage: не нашёл объекты космоса в сцене")
		return
	_base = {
		"gas_pos": _gas.global_position,
		"gas_scale": _gas.scale.x,
		"ring_pos": _ring.global_position if _ring != null else Vector3.ZERO,
		"ring_scale": _ring.scale.x if _ring != null else 1.0,
		"bh_pos": _blackhole.global_position if _blackhole != null else Vector3.ZERO,
		"bh_scale": _blackhole.scale.x if _blackhole != null else 1.0,
	}
	set_stage(initial_stage, true)


func _process(delta: float) -> void:
	# в первой стадии планета медленно уплывает вбок — корабль дрейфует
	if _stage != 0 or _tween != null or _gas == null:
		return
	_gas.global_position.z += drift_speed * delta
	if _ring != null:
		_ring.global_position.z = _gas.global_position.z


func _find_space_objects() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	_gas = root.find_child("SpaceGasGiant", true, false) as Node3D
	_ring = root.find_child("SpaceRing", true, false) as Node3D
	_blackhole = root.find_child("SpaceBlackHole", true, false) as Node3D


## Переключить стадию. instant=true — без плавного перехода.
func set_stage(index: int, instant: bool = false) -> void:
	index = clampi(index, 0, STAGES.size() - 1)
	_stage = index
	var data: Dictionary = STAGES[index]

	if _tween != null:
		_tween.kill()
		_tween = null

	var gas_pos: Vector3 = _base["gas_pos"] + data["gas_offset"]
	var gas_scale: float = _base["gas_scale"] * data["gas_scale"]
	var ring_scale: float = _base["ring_scale"] * data["ring_scale"]
	var bh_pos: Vector3 = _base["bh_pos"] + data["bh_offset"]
	var bh_scale: float = _base["bh_scale"] * data["bh_scale"]

	if instant or transition_time <= 0.01:
		_apply(gas_pos, gas_scale, ring_scale, bh_pos, bh_scale, data)
	else:
		_tween = create_tween().set_parallel(true)
		_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if _gas != null:
			_tween.tween_property(_gas, "global_position", gas_pos, transition_time)
			_tween.tween_property(_gas, "scale", Vector3.ONE * gas_scale, transition_time)
			_tween.tween_property(_gas, "visible", data["gas_visible"], 0.6)
		if _ring != null:
			_tween.tween_property(_ring, "global_position", gas_pos, transition_time)
			_tween.tween_property(_ring, "scale", Vector3.ONE * ring_scale, transition_time)
			_tween.tween_property(_ring, "visible", data["ring_visible"], 0.6)
		if _blackhole != null:
			_tween.tween_property(_blackhole, "global_position", bh_pos, transition_time)
			_tween.tween_property(_blackhole, "scale", Vector3.ONE * bh_scale, transition_time)
			_tween.tween_property(_blackhole, "visible", data["bh_visible"], 0.6)
		_tween.finished.connect(func() -> void: _tween = null)

	stage_changed.emit(index)


func _apply(gas_pos: Vector3, gas_scale: float, ring_scale: float,
		bh_pos: Vector3, bh_scale: float, data: Dictionary) -> void:
	if _gas != null:
		_gas.global_position = gas_pos
		_gas.scale = Vector3.ONE * gas_scale
		_gas.visible = data["gas_visible"]
	if _ring != null:
		_ring.global_position = gas_pos
		_ring.scale = Vector3.ONE * ring_scale
		_ring.visible = data["ring_visible"]
	if _blackhole != null:
		_blackhole.global_position = bh_pos
		_blackhole.scale = Vector3.ONE * bh_scale
		_blackhole.visible = data["bh_visible"]
