extends Node
## A failed EVA becomes a nightmare: red peripheral stress, blackout, waking in bed.

signal recovered

enum Stage { IDLE, PANIC, BLACKOUT, WAKING, SITTING }
const LOST_DISTANCE := 8.0
const OUTWARD_SPEED := 0.5
const PANIC_SECONDS := 4.2
const SAMPLE_INTERVAL := 0.2

var host: Node3D
var player: Player
var active := false
var stage := Stage.IDLE
var cinematic_speed := 1.0
var recovery_count := 0
var blackout := 0.0
var view_position := Vector3.ZERO
var view_yaw := PI
var view_pitch := 0.9
var view_roll := 0.045
var view_fov := 75.0
var _sample_clock := 0.0
var _clock := 0.0
var _wake_clock := 0.0
var _start_physics_frame := -1
var _base_head := Vector3.ZERO
var _base_view := Vector3.ZERO
var _base_position := Vector3.ZERO
var _base_fov := 75.0
var _capsule_position := Vector3.ZERO
var _stand_position := Vector3.ZERO
var _ship_center := Vector3.ZERO
var _ship_span := 40.0
var _near_shape := SphereShape3D.new()
var _far_shape := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _overlay: CanvasLayer
var _red: ColorRect
var _black: ColorRect
var _red_material: ShaderMaterial
var _heart: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _hud: CanvasLayer
var _hud_was_visible := false


func configure(owner_eva: Node3D, operator: Player, grip_mask: int) -> void:
	host = owner_eva
	player = operator
	_query.collision_mask = grip_mask


func _ready() -> void:
	var hull := host.get("_hull_root") as MeshInstance3D
	_ship_center = hull.global_transform * hull.mesh.get_aabb().get_center()
	_ship_span = (hull.global_basis * hull.mesh.get_aabb().size).length()
	_capsule_position = (host.get_parent().get_node("TripoCapsule") as Node3D).global_position
	_stand_position = Vector3(-0.10, 0.035, _capsule_position.z + 0.18)
	_near_shape.radius = LOST_DISTANCE
	_query.margin = 0.0
	_build_overlay()
	_build_audio()


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "NightmareOverlay"
	_overlay.layer = 140
	add_child(_overlay)
	_red = ColorRect.new()
	_red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_red.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_red_material = ShaderMaterial.new()
	_red_material.shader = preload("res://shaders/eva_panic.gdshader")
	_red.material = _red_material
	_overlay.add_child(_red)
	_black = ColorRect.new()
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.color = Color(0, 0, 0, 0)
	_overlay.add_child(_black)
	_overlay.hide()


func _make_sound(breathing: bool) -> AudioStreamWAV:
	# Original synthesized suit breathing and a double heartbeat; no external samples.
	var rate := 22050
	var duration := 1.4 if breathing else 0.8
	var count := int(rate * duration)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41829
	var filtered := 0.0
	var bass := 0.0
	for i in count:
		var t := float(i) / rate
		var value := 0.0
		if breathing:
			filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.32)
			bass = lerpf(bass, filtered, 0.055)
			var envelope := 0.0
			if t < 0.44:
				envelope = pow(sin(PI * t / 0.44), 1.3)
			elif t > 0.53 and t < 1.23:
				envelope = pow(sin(PI * (t - 0.53) / 0.70), 1.1) * 0.75
			value = (filtered - bass) * envelope * 1.8
		else:
			for onset in [0.0, 0.17]:
				var local: float = t - onset
				if local >= 0.0:
					value += sin(TAU * (53.0 * local - 22.0 * local * local)) * exp(-27.0 * local) * 0.75
		pcm.encode_s16(i * 2, int(clampf(value, -0.95, 0.95) * 32767.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = rate
	sound.data = pcm
	sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sound.loop_end = count
	return sound


func _build_audio() -> void:
	_heart = AudioStreamPlayer.new()
	_heart.name = "Heartbeat"
	_heart.stream = _make_sound(false)
	add_child(_heart)
	_breath = AudioStreamPlayer.new()
	_breath.name = "SuitBreathing"
	_breath.stream = _make_sound(true)
	add_child(_breath)


func is_lost() -> bool:
	if active or not bool(host.call("_can_start_nightmare")):
		return false
	var velocity: Vector3 = host.get("drift")
	if velocity.length_squared() <= OUTWARD_SPEED * OUTWARD_SPEED:
		return false
	var center := player.global_position + Vector3.UP * 0.92
	_query.transform = Transform3D(Basis.IDENTITY, center)
	_query.shape = _near_shape
	var space := player.get_world_3d().direct_space_state
	if not space.get_rest_info(_query).is_empty():
		return false
	_far_shape.radius = maxf(16.0, center.distance_to(_ship_center) + _ship_span + 4.0)
	_query.shape = _far_shape
	var nearest := space.get_rest_info(_query)
	if nearest.is_empty():
		return false
	var outward := (center - Vector3(nearest["point"])).normalized()
	return velocity.dot(outward) > OUTWARD_SPEED


func monitor(delta: float) -> void:
	_sample_clock -= delta
	if _sample_clock > 0.0:
		return
	_sample_clock = SAMPLE_INTERVAL
	if is_lost():
		begin()


func begin() -> bool:
	if active or not bool(host.call("_can_start_nightmare")):
		return false
	active = true
	_start_physics_frame = Engine.get_physics_frames()
	stage = Stage.PANIC
	_clock = 0.0
	blackout = 0.0
	_base_head = player.head.rotation
	_base_view = player.camera.rotation
	_base_position = player.camera.position
	_base_fov = player.camera.fov
	view_fov = _base_fov
	host.call("_begin_nightmare")
	_hud = host.get_parent().get_node_or_null("Hud") as CanvasLayer
	if _hud != null:
		_hud_was_visible = _hud.visible
		_hud.hide()
	_overlay.show()
	_heart.pitch_scale = 1.0
	_breath.pitch_scale = 1.0
	_heart.play()
	_breath.play()
	var sequence := create_tween().set_speed_scale(cinematic_speed)
	sequence.tween_interval(PANIC_SECONDS)
	sequence.tween_callback(_close_eyes)
	sequence.tween_property(self, "blackout", 1.0, 0.38)
	sequence.tween_callback(_full_black)
	sequence.tween_interval(0.65)
	sequence.tween_callback(_wake)
	sequence.tween_property(self, "blackout", 0.05, 0.12)
	sequence.parallel().tween_property(self, "view_pitch", -0.32, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	sequence.tween_property(self, "blackout", 0.72, 0.08)
	sequence.tween_property(self, "blackout", 0.0, 0.22)
	sequence.tween_interval(0.55)
	sequence.tween_callback(_sit)
	sequence.tween_property(self, "view_position", Vector3(_capsule_position.x + 0.25, 1.13, _capsule_position.z + 0.35), 1.10).set_trans(Tween.TRANS_SINE)
	sequence.parallel().tween_property(self, "view_pitch", -0.16, 1.10)
	sequence.parallel().tween_property(self, "view_roll", -0.02, 1.10)
	sequence.tween_interval(0.30)
	sequence.tween_property(self, "view_position", _stand_position + Vector3.UP * 1.5, 1.20).set_trans(Tween.TRANS_SINE)
	sequence.parallel().tween_property(self, "view_yaw", PI * 1.5, 1.20)
	sequence.parallel().tween_property(self, "view_pitch", -0.08, 1.20)
	sequence.parallel().tween_property(self, "view_roll", 0.0, 1.20)
	sequence.parallel().tween_property(self, "view_fov", _base_fov, 1.20)
	sequence.tween_property(self, "view_yaw", PI, 0.45).set_trans(Tween.TRANS_SINE)
	sequence.tween_callback(_finish)
	return true


func _physics_process(delta: float) -> void:
	if active and stage == Stage.PANIC and Engine.get_physics_frames() != _start_physics_frame:
		host.call("_apply_drift", delta)


func _process(delta: float) -> void:
	if not active:
		return
	_clock += delta * cinematic_speed
	_black.color.a = blackout
	if stage == Stage.PANIC:
		var strength := clampf(_clock / PANIC_SECONDS, 0.0, 1.0)
		var beat := pow(maxf(0.0, sin(_clock * (10.0 + strength * 6.0))), 4.0)
		_red_material.set_shader_parameter("amount", lerpf(0.12, 1.0, strength))
		_red_material.set_shader_parameter("pulse", beat)
		player.head.rotation = _base_head + Vector3(0, sin(_clock * 2.6) * 0.075 * strength, 0)
		player.camera.rotation = _base_view + Vector3(sin(_clock * 8.1) * 0.040, 0, sin(_clock * 3.7) * 0.065) * strength
		player.camera.position = _base_position + Vector3(sin(_clock * 17.0), sin(_clock * 11.0), 0) * 0.012 * strength
		player.camera.fov = _base_fov + 13.0 * strength + beat * 1.8
		_heart.volume_db = lerpf(-26.0, -15.0, strength)
		_heart.pitch_scale = lerpf(1.0, 1.55, strength)
		_breath.volume_db = lerpf(-29.0, -17.0, strength)
		_breath.pitch_scale = lerpf(1.0, 1.45, strength)
	elif stage == Stage.WAKING or stage == Stage.SITTING:
		_wake_clock += delta * cinematic_speed
		_heart.volume_db = maxf(-45.0, -20.0 - _wake_clock * 7.0)
		_breath.volume_db = maxf(-35.0, -17.0 - _wake_clock * 3.0)
		var breath_offset := Vector3.UP * sin(_wake_clock * 6.5) * 0.007 * exp(-_wake_clock * 0.5)
		player.camera.global_transform = Transform3D(Basis.from_euler(Vector3(view_pitch, view_yaw, view_roll)), view_position + breath_offset)
		player.camera.fov = view_fov


func _close_eyes() -> void:
	stage = Stage.BLACKOUT


func _full_black() -> void:
	blackout = 1.0
	_black.color.a = 1.0
	_red_material.set_shader_parameter("amount", 0.0)
	_heart.stop()
	_breath.stop()
	host.call("_nightmare_reset_inside")
	player.global_position = _stand_position
	player.head.rotation = Vector3.ZERO
	player.camera.position = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.flashlight_flag = false
	player.flashlight.hide()


func _wake() -> void:
	stage = Stage.WAKING
	_wake_clock = 0.0
	view_position = Vector3(_capsule_position.x + 0.25, 0.92, _capsule_position.z - 0.35)
	view_yaw = PI
	view_pitch = 0.45
	view_roll = 0.045
	view_fov = _base_fov + 4.0
	_heart.pitch_scale = 0.9
	_breath.pitch_scale = 0.65
	_heart.play()
	_breath.play()
	player.camera.global_transform = Transform3D(Basis.from_euler(Vector3(view_pitch, view_yaw, view_roll)), view_position)


func _sit() -> void:
	stage = Stage.SITTING


func _finish() -> void:
	_heart.stop()
	_breath.stop()
	player.global_position = _stand_position
	player.head.rotation = Vector3(0, PI, 0)
	player.camera.position = Vector3.ZERO
	player.camera.rotation = Vector3(-0.08, 0, 0)
	player.camera.fov = _base_fov
	blackout = 0.0
	_black.color.a = 0.0
	_overlay.hide()
	if _hud != null:
		_hud.visible = _hud_was_visible
	active = false
	stage = Stage.IDLE
	recovery_count += 1
	host.call("_finish_nightmare")
	recovered.emit()
