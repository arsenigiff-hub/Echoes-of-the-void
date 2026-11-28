extends Node3D
## Physical airlock sequence and mouse-only hand-over-hand locomotion.

signal exterior_audio(active: bool)

enum Phase { INTERIOR, DEPARTING, OUTSIDE, RETURNING, NIGHTMARE }

const DOCK := preload("res://assetss/blender/eva_shuttle_dock/eva_shuttle_dock.glb")
const PLATFORM := preload("res://assetss/blender/eva_platform/eva_platform.glb")
const HAND := preload("res://assetss/ui/eva/grip_hand.png")
const CLUNK := preload("res://assetss/audio/intro/clunk.wav")
const VENT := preload("res://assetss/audio/intro/whoosh_flyby.wav")
const GROAN := preload("res://assetss/audio/intro/hull_groan.wav")
const FABRIC := preload("res://assetss/audio/shuttle/step_04.wav")
const NIGHTMARE := preload("res://scripts/eva_nightmare.gd")
const GRIP_LAYER := 1 << 6
const OUTSIDE_RENDER := 1 << 14
const GRIP_RANGE := 2.75
const PULL_REACH := 1.14
const MAX_DRIFT := 4.9
const TETHER_SLACK := 1.0

var powered := false
var phase := Phase.INTERIOR
var gripping := false
var cycle_speed := 1.0
var player: Player
var port_z: float
var inner_z: float
var _hull_root: Node3D
var _outer: Node3D
var _wheel: Node3D
var _inner: Array[AnimatableBody3D] = []
var _hull_body: StaticBody3D
var _outer_body: AnimatableBody3D
var _platform_body: StaticBody3D
var _pressure_light: OmniLight3D
var _space_environment: Environment
var _initial_camera_environment: Environment
var _source: AudioStreamPlayer
var _mechanical: AudioStreamPlayer
var _hint: Label
var _dot: ColorRect
var _hand: TextureRect
var _visor: TextureRect
var _hand_tween: Tween
var _pointer_down := false
var _press_pending := false
var _release_pending := false
var _pending_drag := Vector2.ZERO
var _pull := Vector3.ZERO
var _hand_normal := Vector3.ZERO
var _grip_origin := Vector3.ZERO
var _grip_point := Vector3.ZERO
var drift := Vector3.ZERO
var _gate_template: MeshInstance3D
var tether_attached := false
var tether_length := 0.0
var _tether_mesh: MeshInstance3D
var _tether_anchor_node: Node3D
var _tether_anchor_local := Vector3.ZERO
var _tether_pending := false
var nightmare: NIGHTMARE


func configure(operator: Player, dock_z: float, inner_gate_z: float, room_environment: Environment) -> void:
	player = operator
	port_z = dock_z
	inner_z = inner_gate_z
	_space_environment = room_environment.duplicate() as Environment
	# Stars are a visible background, not an invisible source lighting the hull.
	_space_environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_space_environment.ambient_light_energy = 0.0
	_space_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_space_environment.fog_enabled = false



func _ready() -> void:
	_build_exterior()
	_build_inner_gate()
	_build_hud()
	_source = AudioStreamPlayer.new()
	add_child(_source)
	_mechanical = AudioStreamPlayer.new()
	add_child(_mechanical)
	nightmare = NIGHTMARE.new()
	nightmare.name = "NightmareRecovery"
	nightmare.configure(self, player, GRIP_LAYER)
	add_child(nightmare)



func _build_exterior() -> void:
	# The fitted Tripo hull and all visible fixtures are authored in Blender.
	var mount := DOCK.instantiate() as Node3D
	mount.name = "ExteriorMount"
	mount.position.z = port_z
	add_child(mount)
	_outer = mount.find_child("OuterLeafPivot", true, false) as Node3D
	_wheel = mount.find_child("OuterHandwheel", true, false) as Node3D
	_hull_root = mount.find_child("AriadnaTripoHull", true, false) as Node3D
	_gate_template = mount.find_child("InnerGateArt", true, false) as MeshInstance3D
	_gate_template.hide()
	# Reuse the authored Blender rope, hidden until the player clips it on with Q.
	_tether_mesh = mount.find_child("TetherArt", true, false) as MeshInstance3D
	_tether_mesh.reparent(self, false)
	_tether_mesh.name = "OptionalTether"
	_tether_mesh.layers = OUTSIDE_RENDER
	_tether_mesh.hide()
	var collar := mount.find_child("PressureTunnel", true, false) as MeshInstance3D
	for child in mount.find_children("*", "MeshInstance3D", true, false):
		var visual := child as MeshInstance3D
		for surface in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_hull_body = StaticBody3D.new()
	_hull_body.name = "HullGripCollision"
	_hull_body.collision_layer = 0
	_hull_body.collision_mask = 0
	add_child(_hull_body)
	for visual: MeshInstance3D in [_hull_root, collar]:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(visual.global_transform * visual.mesh.get_faces())
		shape.backface_collision = true
		var collider := CollisionShape3D.new()
		collider.shape = shape
		_hull_body.add_child(collider)
		visual.layers = OUTSIDE_RENDER
	_hull_root.hide()
	_build_platform()
	_build_hatch_collision()

	# Cabin lights cannot shine through the pressure hull onto its outside skin.
	# The real airlock lamp is added separately and can light the open threshold.
	for light: Light3D in get_parent().find_children("*", "Light3D", true, false):
		if not player.is_ancestor_of(light):
			light.light_cull_mask &= ~OUTSIDE_RENDER



func _build_platform() -> void:
	var mount := PLATFORM.instantiate() as Node3D
	mount.name = "LandingPlatform"
	mount.position.z = port_z
	add_child(mount)
	_platform_body = StaticBody3D.new()
	_platform_body.name = "PlatformCollision"
	_platform_body.collision_layer = 1 | GRIP_LAYER
	_platform_body.collision_mask = 0
	add_child(_platform_body)
	for visual: MeshInstance3D in mount.find_children("*", "MeshInstance3D", true, false):
		visual.layers = OUTSIDE_RENDER
		for surface in visual.mesh.get_surface_count():
			var material := visual.get_active_material(surface) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if visual.name == "PlatformStructure":
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(visual.global_transform * visual.mesh.get_faces())
		shape.backface_collision = true
		var collider := CollisionShape3D.new()
		collider.shape = shape
		_platform_body.add_child(collider)


func _build_hatch_collision() -> void:
	# This body follows the authored hinge, including its open resting pose.
	_outer_body = AnimatableBody3D.new()
	_outer_body.name = "HatchLeafCollision"
	_outer_body.sync_to_physics = false
	_outer_body.collision_layer = 1 | GRIP_LAYER
	_outer_body.collision_mask = 0
	_outer_body.set_script(preload("res://scripts/shuttle_interactable.gd"))
	_outer_body.set("action_id", "hatch")
	_outer_body.set("prompt", "[ЛКМ] Люк")
	_outer_body.set("hub", get_parent())
	_outer.add_child(_outer_body)
	for part in ["OuterLeafArt", "WheelArt"]:
		var visual := _outer.find_child(part, true, false) as MeshInstance3D
		var collider := CollisionShape3D.new()
		collider.shape = visual.mesh.create_convex_shape(true, true)
		_outer_body.add_child(collider)
		collider.global_transform = visual.global_transform

func _key_on_safe_layer(light: Light3D) -> void:
	light.add_to_group("eva_independent_light")


func _build_inner_gate() -> void:
	for side in [-1.0, 1.0]:
		var leaf := AnimatableBody3D.new()
		leaf.name = "PortInnerGate" if side < 0.0 else "StarboardInnerGate"
		leaf.sync_to_physics = false
		leaf.position = Vector3(side * 0.75, 0.99, inner_z)
		add_child(leaf)
		var visual := _gate_template.duplicate() as MeshInstance3D
		leaf.add_child(visual)
		visual.show()
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.483, 1.91, 0.11)
		collider.shape = box
		leaf.add_child(collider)
		_inner.append(leaf)
	_pressure_light = OmniLight3D.new()
	_pressure_light.name = "AirlockCycleLight"
	_pressure_light.light_color = Color(1.0, 0.34, 0.13)
	_pressure_light.light_energy = 0.0
	_pressure_light.shadow_enabled = true
	_pressure_light.omni_range = 3.2
	_pressure_light.position = Vector3(-2.93, 1.97, port_z + 0.31)
	_key_on_safe_layer(_pressure_light)
	add_child(_pressure_light)


func _build_hud() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 112
	add_child(ui)
	# Peripheral desaturation without obscuring the horizon or the grip point.
	var shade := GradientTexture2D.new()
	var stops := Gradient.new()
	stops.offsets = PackedFloat32Array([0.0, 0.52, 0.77, 1.0])
	stops.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0),
		Color(0.015, 0.033, 0.052, 0.18), Color(0.004, 0.009, 0.015, 0.81)])
	shade.gradient = stops
	shade.fill = GradientTexture2D.FILL_RADIAL
	shade.fill_from = Vector2(0.5, 0.48)
	shade.fill_to = Vector2(1.0, 1.0)
	_visor = TextureRect.new()
	_visor.texture = shade
	_visor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_visor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_visor.modulate.a = 0.0
	ui.add_child(_visor)
	_hint = Label.new()
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -520
	_hint.offset_right = 520
	_hint.offset_top = -94
	_hint.offset_bottom = -29
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(0.83, 0.91, 0.87))
	_hint.add_theme_constant_override("outline_size", 6)
	ui.add_child(_hint)
	_hint.hide()
	_dot = ColorRect.new()
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.set_anchors_preset(Control.PRESET_CENTER)
	_dot.offset_left = -2
	_dot.offset_top = -2
	_dot.offset_bottom = 2
	_dot.offset_right = 2
	ui.add_child(_dot)
	_dot.hide()
	_hand = TextureRect.new()
	_hand.texture = HAND
	_hand.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hand.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand.set_anchors_preset(Control.PRESET_CENTER)
	_hand.offset_left = -36
	_hand.offset_right = 36
	_hand.offset_top = -36
	_hand.offset_bottom = 36
	_hand.pivot_offset = Vector2(36, 36)
	ui.add_child(_hand)
	_hand.hide()


func _play(audio: AudioStreamPlayer, clip: AudioStream, decibels: float, pitch := 1.0) -> void:
	audio.stream = clip
	audio.volume_db = decibels
	audio.pitch_scale = pitch
	audio.play()


func _exit_pos() -> Vector3:
	return Vector3(-4.65, 0.035, port_z - 0.40)


func _tracks() -> Tween:
	return create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_speed_scale(cycle_speed)


func request_exit() -> bool:
	if phase != Phase.INTERIOR or not powered or player.is_interacting \
			or player.global_position.x > -0.95 or absf(player.global_position.z - port_z) > 1.25:
		return false
	phase = Phase.DEPARTING
	_initial_camera_environment = player.camera.environment
	player.interacting_object = null
	_lock_controls()
	_hint.text = "ШЛЮЗ · ГЕРМЕТИЗАЦИЯ"
	_hint.show()
	_depart()
	return true


func _lock_controls() -> void:
	player.is_interacting = true
	player.camera_position_managed = true
	player.velocity = Vector3.ZERO
	drift = Vector3.ZERO


func _depart() -> void:
	var align := _tracks().set_parallel()
	align.tween_property(player, "global_position", Vector3(-2.08, 0.035, port_z), 0.82)
	align.tween_property(player.head, "rotation:y", _near_yaw(PI * 0.5), 0.82)
	align.tween_property(player.camera, "position", Vector3.ZERO, 0.52)
	align.tween_property(player.camera, "rotation", Vector3(-0.10, 0, 0.015), 0.72)
	align.tween_property(_visor, "modulate:a", 0.85, 0.72)
	_play(_mechanical, GROAN, -22.0, 0.93)
	await align.finished
	await _slide_inner(false)
	_hint.text = "ШЛЮЗ · СБРОС ДАВЛЕНИЯ"
	_play(_mechanical, CLUNK, -13.5, 0.84)
	_play(_source, VENT, -19.0, 0.71)
	exterior_audio.emit(true)
	var vent := _tracks()
	vent.tween_property(_pressure_light, "light_energy", 0.8, 0.36)
	vent.tween_property(_pressure_light, "light_energy", 0.19, 0.31)
	vent.tween_property(_pressure_light, "light_energy", 0.64, 0.26)
	vent.tween_property(_pressure_light, "light_energy", 0.04, 0.68)
	await vent.finished
	_hull_root.show()
	player.camera.environment = _space_environment
	_hint.text = "ШЛЮЗ · ВНЕШНИЙ ЛЮК"
	await _swing_outer(true)
	_set_outer_collision(false)
	var move := _tracks()
	move.tween_property(player, "global_position", Vector3(-4.15, 0.08, port_z), 1.29)
	move.parallel().tween_property(player.camera, "rotation:x", 0.0, 1.17)
	move.tween_property(player, "global_position", _exit_pos(), 1.04)
	move.parallel().tween_property(player.head, "rotation:y", _near_yaw(PI * 0.5), 1.10)
	move.parallel().tween_property(player.camera, "rotation", Vector3(-0.30, 0, 0), 1.0)
	await move.finished
	_hull_body.collision_layer = 1 | GRIP_LAYER
	player.eva_mode = true
	player.eva_mouse_only = true
	player.is_interacting = false
	phase = Phase.OUTSIDE
	_dot.show()


func _arrive() -> void:
	phase = Phase.RETURNING
	_detach_tether()
	_stop_grip()
	_lock_controls()
	_dot.hide()
	_hull_body.collision_layer = 0
	_hint.text = "ШЛЮЗ · ВОЗВРАЩЕНИЕ"
	var approach := _tracks().set_parallel()
	approach.tween_property(player, "global_position", Vector3(-4.32, 0.10, port_z), 0.83)
	approach.tween_property(player.head, "rotation:y", _near_yaw(-PI * 0.5), 0.65)
	approach.tween_property(player.camera, "rotation", Vector3(-0.06, 0.0, 0.0), 0.70)
	await approach.finished
	var enter := _tracks()
	enter.tween_property(player, "global_position", Vector3(-1.73, 0.04, port_z), 1.65)
	await enter.finished
	await _swing_outer(false)
	_set_outer_collision(true)
	_hull_root.hide()
	player.camera.environment = _initial_camera_environment
	_hint.text = "ШЛЮЗ · ВЫРАВНИВАНИЕ ДАВЛЕНИЯ"
	_play(_source, VENT, -25.0, 1.06)
	exterior_audio.emit(false)
	_pressure_light.light_color = Color(0.53, 0.87, 0.73)
	var pressure := _tracks()
	pressure.tween_property(_pressure_light, "light_energy", 0.86, 0.65)
	pressure.tween_property(_pressure_light, "light_energy", 0.0, 0.50)
	pressure.parallel().tween_property(_visor, "modulate:a", 0.0, 0.55)
	await pressure.finished
	await _slide_inner(true)
	player.velocity = Vector3.ZERO
	player.eva_mode = false
	player.eva_mouse_only = false
	player.is_interacting = false
	player.camera_position_managed = false
	_pressure_light.light_color = Color(1.0, 0.34, 0.13)
	_hint.hide()
	phase = Phase.INTERIOR


func _near_yaw(yaw: float) -> float:
	return player.head.rotation.y + wrapf(yaw - player.head.rotation.y, -PI, PI)


func _set_outer_collision(closed: bool) -> void:
	var body := get_parent().get_node("EvaHatch") as StaticBody3D
	body.collision_layer = 1 if closed else 0


func _slide_inner(open: bool) -> void:
	var doors := _tracks().set_parallel()
	doors.tween_property(_inner[0], "position:x", -0.75 if open else -0.236, 0.76)
	doors.tween_property(_inner[1], "position:x", 0.75 if open else 0.236, 0.76)
	await doors.finished


func _swing_outer(open: bool) -> void:
	var hatch := _tracks()
	var wheel_home := _wheel.rotation.x
	if open:
		_play(_mechanical, CLUNK, -17.0)
		hatch.tween_property(_wheel, "rotation:x", wheel_home - TAU * 0.42, 0.40)
	hatch.tween_callback(_play.bind(_mechanical, GROAN, -21.0, 0.89))
	hatch.tween_property(_outer, "rotation_degrees:y", 101.0 if open else 0.0, 1.21)
	if not open:
		hatch.tween_property(_wheel, "rotation:x", wheel_home + TAU * 0.42, 0.32)
	await hatch.finished
	_play(_mechanical, CLUNK, -18.0, 0.96)


func _input(event: InputEvent) -> void:
	if phase == Phase.NIGHTMARE:
		get_viewport().set_input_as_handled()
		return
	if phase == Phase.OUTSIDE and event is InputEventKey \
			and (event.physical_keycode == KEY_Q or event.keycode == KEY_Q):
		if event.pressed and not event.echo \
				and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"):
			_tether_pending = true
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if phase == Phase.INTERIOR:
			if event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not player.is_interacting:
				player.interaction_ray.force_raycast_update()
				var target := player.interaction_ray.get_collider() as Node
				if target != null and (target.name == "EvaHatch" or target == _outer_body):
					get_parent().call("on_interact", "hatch", player)
					get_viewport().set_input_as_handled()
			return
		if phase == Phase.OUTSIDE:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
				_stop_grip()
				return
			_pointer_down = event.pressed
			if event.pressed:
				_press_pending = true
			else:
				# Consume the last mouse delta before releasing, even between ticks.
				_release_pending = true
		get_viewport().set_input_as_handled()
	elif phase == Phase.OUTSIDE and (gripping or _press_pending) and event is InputEventMouseMotion:
		# OS input provides screen_relative; injected/replayed input may only provide relative.
		var drag: Vector2 = event.screen_relative if not event.screen_relative.is_zero_approx() else event.relative
		if not gripping:
			_pending_drag += drag
			get_viewport().set_input_as_handled()
			return
		var eye := player.camera.global_basis
		# The hand stays fixed on the hull; the body moves opposite the drag.
		_pull += (-eye.x * drag.x + eye.y * drag.y).slide(_hand_normal) * 0.0063
		_pull = _pull.limit_length(0.85)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and phase == Phase.OUTSIDE:
		_stop_grip()
		_tether_pending = false


func _physics_process(delta: float) -> void:
	if phase != Phase.OUTSIDE:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
		_stop_grip()
		_tether_pending = false
	if tether_attached and (not is_instance_valid(_tether_anchor_node) or not _tether_anchor_node.is_inside_tree()):
		_detach_tether()
	if _tether_pending:
		_tether_pending = false
		if tether_attached:
			_detach_tether()
			_play(_mechanical, CLUNK, -23.0, 1.1)
		else:
			_attach_tether()
	var target: Dictionary = {} if gripping else _aim_surface()
	var return_target := not gripping and _aim_at_door()
	if _press_pending:
		_press_pending = false
		if _pointer_down or _release_pending:
			if return_target:
				_arrive()
				return
			if not target.is_empty():
				_grab(target["position"], target["normal"])
			else:
				_pending_drag = Vector2.ZERO
	if gripping:
		_apply_pull(delta)
	else:
		_apply_drift(delta)
	if _release_pending:
		_stop_grip()
	_update_tether()
	_dot.visible = not gripping
	_dot.color = Color(0.85, 0.89, 0.70, 0.92) if not target.is_empty() or return_target \
		else Color(0.67, 0.73, 0.74, 0.36)
	if gripping:
		_hint.text = "Тяните мышь · Отпустите ЛКМ для перехвата"
	elif return_target:
		_hint.text = "ЛКМ — вернуться в шлюз"
	else:
		_hint.text = "Зажмите ЛКМ на корпусе" if not target.is_empty() else "Наведитесь на корпус"
	if tether_attached:
		_hint.text += "\nQ — отцепить трос"
	elif not target.is_empty() or gripping:
		_hint.text += "\nQ — закрепить трос"
	nightmare.monitor(delta)


func _can_start_nightmare() -> bool:
	return phase == Phase.OUTSIDE and not gripping and not tether_attached and not player.is_interacting


func _begin_nightmare() -> void:
	phase = Phase.NIGHTMARE
	_stop_grip()
	_detach_tether()
	player.is_interacting = true
	player.interacting_object = null
	player.camera_position_managed = true
	_hint.hide()
	_dot.hide()


func _nightmare_reset_inside() -> void:
	_hull_body.collision_layer = 0
	_hull_root.hide()
	_outer.rotation_degrees.y = 0.0
	_wheel.rotation.x += TAU * 0.42
	_set_outer_collision(true)
	_inner[0].position.x = -0.75
	_inner[1].position.x = 0.75
	_pressure_light.light_energy = 0.0
	_pressure_light.light_color = Color(1.0, 0.34, 0.13)
	player.camera.environment = _initial_camera_environment
	player.eva_mode = false
	player.eva_mouse_only = false
	player.velocity = Vector3.ZERO
	drift = Vector3.ZERO
	_visor.modulate.a = 0.0
	exterior_audio.emit(false)


func _finish_nightmare() -> void:
	player.velocity = Vector3.ZERO
	player.is_interacting = false
	player.camera_position_managed = false
	phase = Phase.INTERIOR


func _aim_surface() -> Dictionary:
	var from := player.camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(from, from - player.camera.global_basis.z * GRIP_RANGE, GRIP_LAYER)
	return player.get_world_3d().direct_space_state.intersect_ray(ray)


func _aim_at_door() -> bool:
	var eye := player.camera.global_position
	if eye.x > -4.0 or eye.distance_to(Vector3(-3.78, 1.14, port_z)) > 3.2:
		return false
	var point: Variant = Plane(Vector3.RIGHT, -3.78).intersects_ray(eye, -player.camera.global_basis.z)
	if point == null:
		return false
	var p: Vector3 = point
	return absf(p.z - port_z) < 0.58 and p.y > 0.16 and p.y < 2.08


func _grab(point: Vector3, normal: Vector3) -> void:
	gripping = true
	_hand_normal = normal.normalized()
	_grip_point = point
	_grip_origin = player.global_position
	var eye := player.camera.global_basis
	_pull = (-eye.x * _pending_drag.x + eye.y * _pending_drag.y).slide(_hand_normal) * 0.0063
	_pending_drag = Vector2.ZERO
	drift = Vector3.ZERO
	_play(_mechanical, FABRIC, -19.0, 0.87)
	_hand.scale = Vector2.ONE * 0.78
	_hand.modulate.a = 0.45
	_hand.show()
	_hand_tween = _tracks().set_parallel()
	_hand_tween.tween_property(_hand, "scale", Vector2.ONE, 0.14)
	_hand_tween.tween_property(_hand, "modulate:a", 1.0, 0.14)


func _stop_grip() -> void:
	gripping = false
	_pointer_down = false
	_press_pending = false
	_release_pending = false
	_pending_drag = Vector2.ZERO
	_pull = Vector3.ZERO
	if _hand_tween != null:
		_hand_tween.kill()
	_hand.hide()


func _apply_pull(delta: float) -> void:
	if _pull.length_squared() < 0.000001:
		_pull = Vector3.ZERO
		drift = drift.move_toward(Vector3.ZERO, delta * 10.0)
		_enforce_tether()
		return
	var step := _pull.limit_length(MAX_DRIFT * delta)
	# Mouse motion belongs to this tick; do not replay a flick as queued travel.
	_pull = Vector3.ZERO
	var desired := _grip_origin + (player.global_position + step - _grip_origin).limit_length(PULL_REACH)
	var eye_offset := player.camera.global_position - player.global_position
	var eye_target := desired + eye_offset - _grip_point
	if eye_target.length() > GRIP_RANGE:
		desired = _grip_point + eye_target.limit_length(GRIP_RANGE) - eye_offset
	desired = _limit_tether_position(desired)
	var start := player.global_position
	_move_around_hull(desired - start)
	var actual := (player.global_position - start) / maxf(delta, 0.00001)
	drift = actual.limit_length(MAX_DRIFT)
	_enforce_tether()


func _apply_drift(delta: float) -> void:
	# Only the optional Q tether can limit drift; there is no radius from the hatch.
	drift = drift.limit_length(MAX_DRIFT)
	var desired := _limit_tether_position(player.global_position + drift * delta)
	_move_around_hull(desired - player.global_position)
	_enforce_tether()


func _harness_offset() -> Vector3:
	return player.global_basis * Vector3(0, 0.92, 0)


func _tether_point() -> Vector3:
	return _tether_anchor_node.to_global(_tether_anchor_local)


func _attach_tether() -> bool:
	if phase != Phase.OUTSIDE or tether_attached:
		return false
	var hit := _aim_surface()
	if hit.is_empty():
		return false
	_tether_anchor_node = hit["collider"] as Node3D
	_tether_anchor_local = _tether_anchor_node.to_local(hit["position"])
	tether_length = (player.global_position + _harness_offset()).distance_to(_tether_point()) + TETHER_SLACK
	tether_attached = true
	_tether_mesh.show()
	_update_tether()
	_play(_mechanical, CLUNK, -21.0, 0.91)
	return true


func _detach_tether() -> void:
	tether_attached = false
	tether_length = 0.0
	_tether_pending = false
	_tether_anchor_node = null
	_tether_mesh.hide()


func _limit_tether_position(desired: Vector3) -> Vector3:
	if not tether_attached:
		return desired
	var pin := _tether_point()
	var offset := _harness_offset()
	return pin + (desired + offset - pin).limit_length(tether_length) - offset


func _enforce_tether() -> void:
	if not tether_attached:
		return
	# Resolve via the capsule's collisions, never teleport through a bulkhead.
	for attempt in 3:
		var correction := _limit_tether_position(player.global_position) - player.global_position
		if correction.length_squared() < 0.0000001:
			break
		_move_around_hull(correction)
	var span := player.global_position + _harness_offset() - _tether_point()
	if span.length() >= tether_length - 0.002:
		var outward := span.normalized()
		# Preserve tangential/inward momentum; remove only speed stretching the line.
		drift -= outward * maxf(0.0, drift.dot(outward))


func _update_tether() -> void:
	if not tether_attached:
		return
	var a := _tether_point()
	var b := player.global_position + _harness_offset()
	var span := b - a
	if span.length_squared() < 0.000001:
		_tether_mesh.hide()
		return
	_tether_mesh.show()
	var bounds := _tether_mesh.mesh.get_aabb()
	_tether_mesh.basis = Basis(Quaternion(Vector3.UP, span.normalized())).scaled(
		Vector3(1.0, span.length() / bounds.size.y, 1.0))
	_tether_mesh.position = (a + b) * 0.5 - _tether_mesh.basis * bounds.get_center()


func _move_around_hull(motion: Vector3) -> void:
	if motion.length_squared() <= 0.0000001:
		return
	var hit := player.move_and_collide(motion)
	if hit == null:
		return
	drift = drift.slide(hit.get_normal())
	player.move_and_collide(hit.get_remainder().slide(hit.get_normal()))
