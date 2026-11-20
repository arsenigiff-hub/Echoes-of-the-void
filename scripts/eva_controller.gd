extends Node

# Контроллер выхода в открытый космос (EVA).
#
# Ответственность:
#   1) триггеры у внутренней двери шлюза и у внешнего люка;
#   2) анимация цикла шлюза (затемнение/глитч, шипение, открытие створок);
#   3) перевод игрока в режим невесомости и обратно;
#   4) подсказки и граница полёта (страховочный трос).
#
# Физика невесомости живёт в scripts/player.gd (eva_mode).

const FONT_PATH := "res://assetss/ui/fonts/CascadiaMono.ttf"
const PROMPT_FONT_PATH := "res://assetss/ui/fonts/RussoOne-Regular.ttf"
const CLUNK := "res://assetss/audio/intro/clunk.wav"
const HISS := "res://assetss/audio/intro/hull_groan.wav"
const ALARM := "res://assetss/audio/intro/alarm_warning.ogg"
const ALARM_REST_SECONDS := 7.0
const HATCH_INTERACTION_RADIUS := 2.0
const EXTERIOR_LIGHT_BLEND_SECONDS := 1.05
const EXTERIOR_AMBIENT := 1.3
const OUTER_HATCH_INTERACTION_POS := Vector3(-8.47, 3.30, 11.90)
const CYCLE_HISS := "res://assetss/audio/intro/whoosh_flyby.wav"
const CYCLE_GROAN := "res://assetss/audio/intro/hull_groan.wav"
const CYCLE_RUMBLE := "res://assetss/audio/intro/engine_rumble_loop.wav"
const STATE_SEALED := "sealed"
const STATE_VENTING := "venting"
const STATE_VACUUM := "vacuum"
const STATE_FILLING := "filling"
const CYCLE_RED := Color(0.95, 0.12, 0.06, 1.0)
const CYCLE_GREEN := Color(0.18, 0.95, 0.42, 1.0)

## Появление на внешней площадке: камера сразу видит корпус и космос сбоку.
@export var exit_pos := Vector3(-10.2, 2.18, 11.9)
## Радиус страховочного троса от точки выхода.
@export var tether_length := 34.0
## После этой дистанции трос мягко тянет назад.
@export var hard_tether := 52.0
## Interior coordinates are configurable so a new deck does not move the exterior.
@export var inside_trigger_pos := Vector3(0.0, 1.06, 4.6)
@export var inside_trigger_size := Vector3(1.2, 2.0, 1.8)
@export var return_pos := Vector3(0.0, 0.13, 4.5)
@export var return_yaw_degrees := 180.0
@export var oxygen_seconds_standard := 180.0
@export var oxygen_seconds_calm := 240.0
@export var oxygen_seconds_tense := 120.0
## Длительность сброса/наддува шлюза. У тестов можно уменьшить.
@export var cycle_seconds := 4.0

var player: Player = null
var camera: Camera3D = null
var interior_door: Node3D = null
var exterior_hatch: Node3D = null

var inside_trigger: Node3D = null
var outside_trigger: Node3D = null

var _ship_ext: Node3D = null
var _interior: Node3D = null
var _ship_light: OmniLight3D = null
var _hatch_light: OmniLight3D = null
var _env: WorldEnvironment = null
var _env_ambient := 0.36
var _ship_light_energy := 0.0
var _hatch_light_energy := 0.0
var _exterior_light_mix := 0.0
var _exterior_light_target := 0.0
var _exterior_light_tween: Tween
var _ext_hatch: Node3D = null
var _hatch_pivot: Node3D = null
var _hull_body: StaticBody3D = null
var _hatch_leaf_body: AnimatableBody3D = null
var _interaction_mask_before_eva := 1
var _interior_door_open := false
var _outer_hatch_open := false

var busy := false
var is_outside := false
var oxygen_remaining_seconds := 0.0

var _ui: CanvasLayer
var _fade: ColorRect
var _prompt: Label
var _status: Label
var _oxygen_label: Label
var _clunk: AudioStreamPlayer
var _hiss: AudioStreamPlayer
var _alarm: AudioStreamPlayer

var _interior_door_rest := Vector3.ZERO
var _interior_door_tween: Tween
var _hatch_rest_rot := Vector3.ZERO
var _oxygen_depletion_in_progress := false
var _oxygen_last_displayed_second := -1
var _alarm_repeat_enabled := false
var _alarm_rest_elapsed := 0.0

# --- Цикл давления в шлюзе -------------------------------------------------
var _airlock_state := STATE_SEALED
var _cycle_elapsed := 0.0
var _tunnel_light: Light3D = null
var _tunnel_light_energy := 0.0
var _tunnel_light_rest_energy := 0.0
var _inner_lamp_light: OmniLight3D = null
var _outer_lamp_light: OmniLight3D = null
var _inner_lamp_material: StandardMaterial3D = null
var _outer_lamp_material: StandardMaterial3D = null
var _steam_inner: CPUParticles3D = null
var _steam_outer: CPUParticles3D = null
var _cycle_hiss: AudioStreamPlayer = null
var _cycle_groan: AudioStreamPlayer = null
var _cycle_rumble: AudioStreamPlayer = null
var _cycle_audio_tween: Tween = null
var _cycle_pulse := 0.0
var _prompt_hold_until := 0


func _ready() -> void:
	call_deferred("_setup")


func _setup() -> void:
	player = get_parent().get_node_or_null("Player") as Player
	if player == null:
		push_warning("EVA: не найден Player")
		return
	camera = player.get_node_or_null("Head/Camera3D") as Camera3D
	interior_door = _find_named("airlock_door")
	if interior_door != null:
		_interior_door_rest = interior_door.position
	exterior_hatch = _find_named("AirlockExterior")
	if exterior_hatch != null:
		_hatch_pivot = exterior_hatch
		var moving_leaf := _find_named("HatchLeafPivot")
		if moving_leaf != null:
			_hatch_pivot = moving_leaf
		else:
			for c in exterior_hatch.get_children():
				if c is Node3D:
					_hatch_pivot = c as Node3D
					break
		_hatch_rest_rot = _hatch_pivot.rotation_degrees

	_make_trigger("EVA_InsideTrigger", inside_trigger_pos, inside_trigger_size, false)
	_make_trigger("EVA_OutsideTrigger", OUTER_HATCH_INTERACTION_POS,
			Vector3(0.5, 2.2, 1.9), true)

	_ship_ext = get_parent().get_node_or_null("ShipExterior") as Node3D
	_interior = get_parent().get_node_or_null("ShipInterior") as Node3D
	_ext_hatch = get_parent().get_node_or_null("AirlockExterior") as Node3D
	_ship_light = get_parent().get_node_or_null("EVAShipLight") as OmniLight3D
	_hatch_light = get_parent().get_node_or_null("EVAHatchLight") as OmniLight3D
	_env = get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	var story := get_parent().get_node_or_null("StoryProgression")
	if story != null and story.has_method("get_indoor_ambient"):
		_env_ambient = float(story.call("get_indoor_ambient"))
	elif _env != null and _env.environment != null:
		_env_ambient = _env.environment.ambient_light_energy
	if _ship_light != null:
		_ship_light_energy = _ship_light.light_energy
	if _hatch_light != null:
		_hatch_light_energy = _hatch_light.light_energy
	_apply_exterior_light_mix(0.0)
	_make_hull_collider()
	_make_eva_platform_collider()
	_make_hatch_leaf_collider()
	_add_hatch_inner_skin()
	_add_hull_status_lights()
	_dim_cold_hull_lamps()
	_dim_hatch_status_lenses()
	# No invisible crossing zones. Every door, pressure cycle and gravity
	# switch is started by an explicit E interaction.

	# Луч игрока должен видеть слой триггеров (2), тело — нет.
	var ray := player.get_node_or_null("Head/Camera3D/RayCast3D") as RayCast3D
	if ray != null:
		_interaction_mask_before_eva = ray.collision_mask
		ray.collision_mask |= 2
	_set_exterior_visible(false)

	_build_ui()
	_build_audio()
	_build_airlock_cycle()
	_reset_airlock_cycle()


func _process(delta: float) -> void:
	if player == null:
		return
	_update_status(_outside_status() if is_outside else "")
	_update_airlock_cycle(delta)
	if is_outside:
		_tether(delta)
		_tick_oxygen(delta)
	elif _ship_ext != null and _ship_ext.visible and not _outer_hatch_open \
			and not _interior_door_open and player.global_position.z < 9.8:
		# The exterior shell is only needed while the tunnel or platform is in
		# view. Hide it after the player is back in the pressurised room with
		# both doors shut.
		_set_exterior_shell_visible(false)
	_tick_emergency_alarm(delta)


func _outside_status() -> String:
	var d := player.global_position.distance_to(exit_pos)
	if d > tether_length:
		return "ТРОС: НАТЯНУТ"
	return ""

# ------------------------------------------------------------- триггеры ----

func _make_trigger(node_name: String, pos: Vector3, size: Vector3, outside: bool) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.set_script(load("res://scripts/airlock_hatch.gd"))
	body.set("controller", self)
	body.set("outside_hatch", outside)
	get_parent().add_child(body)
	if outside:
		outside_trigger = body
	else:
		inside_trigger = body


# ------------------------------------------------------------------ API ----

func request_airlock(actor: CharacterBody3D) -> void:
	try_interact_airlock(actor)


func try_interact_airlock(actor: CharacterBody3D) -> bool:
	var active_player := actor as Player
	if active_player == null or active_player != player or active_player.is_interacting:
		return false
	var inner_pos := inside_trigger.global_position if inside_trigger != null else inside_trigger_pos
	var outer_pos := outside_trigger.global_position if outside_trigger != null else OUTER_HATCH_INTERACTION_POS
	var inner_distance := _flat_distance(player.global_position, inner_pos)
	var outer_distance := _flat_distance(player.global_position, outer_pos)
	if not is_outside and inner_distance <= HATCH_INTERACTION_RADIUS and inner_distance <= outer_distance:
		return _interact_inner_door()
	if outer_distance <= HATCH_INTERACTION_RADIUS:
		return _interact_outer_hatch()
	return false


func _flat_distance(a: Vector3, b: Vector3) -> float:
	# Interaction is horizontal: the trigger sits at chest height, while the
	# player origin is at the feet, so a 3D distance would make the hatch
	# unreachable from the landing platform.
	return Vector2(a.x - b.x, a.z - b.z).length()


func _interact_inner_door() -> bool:
	if is_outside:
		return false
	if _airlock_state != STATE_SEALED:
		_airlock_denied("ЗАБЛОКИРОВАНО: ЦИКЛ ДАВЛЕНИЯ")
		return true
	if _outer_hatch_open:
		_airlock_denied("СНАЧАЛА ЗАКРОЙТЕ НАРУЖНЫЙ ЛЮК")
		return true
	var opening := not _interior_door_open
	_set_inner_door_open(opening)
	if opening:
		# The tunnel is part of the exterior shell; it must be visible before
		# the player can see through the open inner door.
		_set_exterior_shell_visible(true)
	return true


func _interact_outer_hatch() -> bool:
	if _airlock_state == STATE_VENTING or _airlock_state == STATE_FILLING:
		_airlock_denied("ИДЁТ ЦИКЛ ДАВЛЕНИЯ")
		return true

	if is_outside:
		if _airlock_state == STATE_SEALED:
			# Emergency re-entry: the tunnel is pressurised and the outer
			# hatch is shut. Vent it; the hatch stays closed until E.
			if _interior_door_open:
				_set_inner_door_open(false)
			_start_venting()
			_airlock_denied("СБРОС ДАВЛЕНИЯ…")
			return true
		if _outer_hatch_open:
			_enter_airlock_from_space()
		else:
			_set_outer_hatch_open(true)
		return true

	if _airlock_state == STATE_VACUUM:
		if _outer_hatch_open:
			_exit_to_space()
		else:
			_set_outer_hatch_open(true)
		return true

	# One E action at the hatch seals the inner door and starts the pressure
	# dump. Nothing happens on its own; the player explicitly chooses the cycle.
	if _interior_door_open:
		_set_inner_door_open(false)
	_start_venting()
	return true


# ------------------------------------------------------------- цикл шлюза ---

func _build_airlock_cycle() -> void:
	_tunnel_light = _find_named("AirlockTunnelLight") as Light3D
	if _tunnel_light != null:
		_tunnel_light_energy = _tunnel_light.light_energy
		_tunnel_light_rest_energy = _tunnel_light_energy

	var inner := _make_cycle_lamp("AirlockInnerPressureLamp",
			Vector3(-7.20, 4.00, 10.86), 4.34)
	_inner_lamp_material = inner.get("material") as StandardMaterial3D
	_inner_lamp_light = inner.get("light") as OmniLight3D

	var outer := _make_cycle_lamp("AirlockOuterPressureLamp",
			Vector3(-8.24, 3.96, 11.90), 4.30)
	_outer_lamp_material = outer.get("material") as StandardMaterial3D
	_outer_lamp_light = outer.get("light") as OmniLight3D

	_steam_inner = _make_steam(Vector3(-7.08, 2.46, 10.92))
	_steam_outer = _make_steam(Vector3(-8.26, 2.46, 11.88))

	_cycle_hiss = _audio(CYCLE_HISS, -60.0)
	_cycle_groan = _audio(CYCLE_GROAN, -60.0)
	_cycle_rumble = _audio(CYCLE_RUMBLE, -60.0)


func _make_cycle_lamp(name: String, pos: Vector3, ceiling_y: float) -> Dictionary:
	var fixture := Node3D.new()
	fixture.name = name + "Fixture"
	fixture.position = pos
	get_parent().add_child(fixture)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.055, 0.060, 0.062)
	steel.metallic = 0.45
	steel.roughness = 0.72

	var hang := maxf(ceiling_y - pos.y, 0.16)
	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.075
	base_mesh.bottom_radius = 0.075
	base_mesh.height = 0.02
	base.mesh = base_mesh
	base.material_override = steel
	base.position = Vector3(0.0, hang - 0.01, 0.0)
	fixture.add_child(base)

	var stem := MeshInstance3D.new()
	stem.name = "Stem"
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.012
	stem_mesh.bottom_radius = 0.012
	stem_mesh.height = maxf(hang - 0.12, 0.02)
	stem.mesh = stem_mesh
	stem.material_override = steel
	stem.position = Vector3(0.0, 0.09 + stem_mesh.height * 0.5, 0.0)
	fixture.add_child(stem)

	var cup := MeshInstance3D.new()
	cup.name = "Cup"
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = 0.042
	cup_mesh.bottom_radius = 0.058
	cup_mesh.height = 0.06
	cup.mesh = cup_mesh
	cup.material_override = steel
	cup.position = Vector3(0.0, 0.06, 0.0)
	fixture.add_child(cup)

	var mesh := MeshInstance3D.new()
	mesh.name = "Lens"
	var sphere := SphereMesh.new()
	sphere.radius = 0.045
	sphere.height = 0.09
	mesh.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.06, 0.08, 0.06)
	material.emission_enabled = true
	material.emission = CYCLE_GREEN
	material.emission_energy_multiplier = 1.1
	material.roughness = 0.3
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fixture.add_child(mesh)

	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0.0, -0.02, 0.0)
	light.light_color = CYCLE_GREEN
	light.light_energy = 0.16
	light.omni_range = 1.6
	light.shadow_enabled = false
	fixture.add_child(light)
	return {"mesh": mesh, "material": material, "light": light}


func _make_steam(pos: Vector3) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "AirlockSteam"
	particles.amount = 18
	particles.lifetime = 1.35
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.emitting = false
	particles.direction = Vector3(0.0, 0.8, 0.0)
	particles.spread = 38.0
	particles.gravity = Vector3(0.0, 0.25, 0.0)
	particles.initial_velocity_min = 0.3
	particles.initial_velocity_max = 0.95
	particles.scale_amount_min = 0.08
	particles.scale_amount_max = 0.22
	var quad := QuadMesh.new()
	quad.size = Vector2(0.36, 0.36)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assetss/fx/intro/smoke_puff.png")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.68, 0.73, 0.76, 0.34)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = material
	particles.mesh = quad
	particles.position = pos
	get_parent().add_child(particles)
	return particles


func _update_airlock_cycle(delta: float) -> void:
	if _airlock_state != STATE_VENTING and _airlock_state != STATE_FILLING:
		return
	_cycle_elapsed += delta
	var duration := maxf(cycle_seconds, 0.05)
	var progress := clampf(_cycle_elapsed / duration, 0.0, 1.0)
	_animate_cycle(progress)
	if _cycle_elapsed >= duration:
		if _airlock_state == STATE_VENTING:
			_finish_venting()
		else:
			_finish_filling()


func _animate_cycle(_progress: float) -> void:
	_cycle_pulse = 0.5 + 0.5 * sin(_cycle_elapsed * 9.0)
	var pulse_energy := 0.9 + 0.7 * _cycle_pulse
	if _inner_lamp_material != null:
		_inner_lamp_material.emission_energy_multiplier = pulse_energy
	if _outer_lamp_material != null:
		_outer_lamp_material.emission_energy_multiplier = pulse_energy
	if _inner_lamp_light != null:
		_inner_lamp_light.light_energy = 0.08 + 0.14 * _cycle_pulse
	if _outer_lamp_light != null:
		_outer_lamp_light.light_energy = 0.08 + 0.14 * _cycle_pulse
	if _tunnel_light != null:
		var base := maxf(_tunnel_light_rest_energy, 0.16)
		_tunnel_light.light_energy = base * (0.32 + 0.30 * _cycle_pulse)


func _start_venting() -> void:
	if _airlock_state != STATE_SEALED or _interior_door_open:
		return
	_remember_tunnel_light()
	_airlock_state = STATE_VENTING
	_cycle_elapsed = 0.0
	_update_cycle_lamps()
	_start_cycle_audio(-10.0)
	_trigger_steam(true, true)


func _finish_venting() -> void:
	_airlock_state = STATE_VACUUM
	_cycle_elapsed = 0.0
	# The hatch stays shut. The player opens it with E.
	_stop_cycle_audio()
	_update_cycle_lamps()
	_trigger_steam(false, true)


func _start_filling() -> void:
	if _airlock_state != STATE_VACUUM:
		return
	_remember_tunnel_light()
	_airlock_state = STATE_FILLING
	_cycle_elapsed = 0.0
	_update_cycle_lamps()
	_start_cycle_audio(-12.0)
	_trigger_steam(true, true)


func _finish_filling() -> void:
	_airlock_state = STATE_SEALED
	_cycle_elapsed = 0.0
	# The inner door stays shut. The player opens it with E.
	_stop_cycle_audio()
	_update_cycle_lamps()
	_trigger_steam(true, false)


func _update_cycle_lamps() -> void:
	var inner_color := CYCLE_GREEN if _airlock_state == STATE_SEALED else CYCLE_RED
	var outer_color := CYCLE_GREEN if _airlock_state == STATE_VACUUM else CYCLE_RED
	_set_cycle_lamp(_inner_lamp_material, _inner_lamp_light, inner_color)
	_set_cycle_lamp(_outer_lamp_material, _outer_lamp_light, outer_color)


func _set_cycle_lamp(material: StandardMaterial3D, light: OmniLight3D, color: Color) -> void:
	if material != null:
		material.emission = color
		material.emission_energy_multiplier = 1.1
	if light != null:
		light.light_color = color
		light.light_energy = 0.16


func _remember_tunnel_light() -> void:
	if _tunnel_light != null:
		_tunnel_light_rest_energy = _tunnel_light.light_energy


func _start_cycle_audio(base_db: float) -> void:
	_stop_cycle_audio(true)
	if _cycle_hiss != null:
		_cycle_hiss.volume_db = -60.0
		_cycle_hiss.play()
	if _cycle_groan != null:
		_cycle_groan.volume_db = -60.0
		_cycle_groan.play()
	if _cycle_rumble != null:
		_cycle_rumble.volume_db = -60.0
		_cycle_rumble.play()
	_cycle_audio_tween = create_tween()
	_cycle_audio_tween.set_trans(Tween.TRANS_SINE)
	if _cycle_hiss != null:
		_cycle_audio_tween.parallel().tween_property(_cycle_hiss, "volume_db", base_db, 0.35)
	if _cycle_groan != null:
		_cycle_audio_tween.parallel().tween_property(_cycle_groan, "volume_db", base_db - 2.0, 0.45)
	if _cycle_rumble != null:
		_cycle_audio_tween.parallel().tween_property(_cycle_rumble, "volume_db", -26.0, 0.5)


func _stop_cycle_audio(immediate := false) -> void:
	if _cycle_audio_tween != null and _cycle_audio_tween.is_valid():
		_cycle_audio_tween.kill()
	_cycle_audio_tween = null
	if immediate:
		if _cycle_hiss != null:
			_cycle_hiss.stop()
		if _cycle_groan != null:
			_cycle_groan.stop()
		if _cycle_rumble != null:
			_cycle_rumble.stop()
		return
	_cycle_audio_tween = create_tween()
	_cycle_audio_tween.set_trans(Tween.TRANS_SINE)
	if _cycle_hiss != null:
		_cycle_audio_tween.parallel().tween_property(_cycle_hiss, "volume_db", -60.0, 0.8)
	if _cycle_groan != null:
		_cycle_audio_tween.parallel().tween_property(_cycle_groan, "volume_db", -60.0, 0.8)
	if _cycle_rumble != null:
		_cycle_audio_tween.parallel().tween_property(_cycle_rumble, "volume_db", -60.0, 0.9)
	_cycle_audio_tween.chain().tween_callback(func() -> void:
		if _cycle_hiss != null:
			_cycle_hiss.stop()
		if _cycle_groan != null:
			_cycle_groan.stop()
		if _cycle_rumble != null:
			_cycle_rumble.stop()
	)


func _trigger_steam(inner: bool, outer: bool) -> void:
	if inner and _steam_inner != null:
		_steam_inner.restart()
	if outer and _steam_outer != null:
		_steam_outer.restart()


func _exit_to_space() -> void:
	if is_outside:
		return
	is_outside = true
	player.set_eva_mode(true)
	player.global_position = exit_pos
	player.velocity = Vector3.ZERO
	_start_eva_oxygen()
	_set_exterior_shell_visible(true)
	if _hull_body != null:
		_hull_body.collision_layer = 1


func _enter_airlock_from_space() -> void:
	if not is_outside:
		return
	is_outside = false
	player.set_eva_mode(false)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(-7.85, 2.25, 11.90)
	_refill_eva_oxygen()
	_set_outer_hatch_open(false)
	_start_filling()
	_set_exterior_shell_visible(true)
	if _hull_body != null:
		# The interior/tunnel floor remains solid; the exterior trimesh only
		# blocks the return path through the hull.
		_hull_body.collision_layer = 0


func _reset_airlock_cycle() -> void:
	_airlock_state = STATE_SEALED
	_cycle_elapsed = 0.0
	_stop_cycle_audio(true)
	if _tunnel_light != null:
		_tunnel_light.light_energy = _tunnel_light_rest_energy
	_update_cycle_lamps()


func _airlock_denied(text: String) -> void:
	if _prompt != null:
		_prompt.text = text
	_prompt_hold_until = Time.get_ticks_msec() + 1500


## The outage alarm is a temporary condition, not a continuous ambience loop.
func stop_emergency_alarm(fade_seconds: float = 1.2) -> void:
	_alarm_repeat_enabled = false
	_alarm_rest_elapsed = 0.0
	if _alarm == null:
		return
	var alarm := _alarm
	_alarm = null
	if fade_seconds <= 0.01:
		alarm.stop()
		alarm.queue_free()
		return
	var tween := create_tween()
	tween.tween_property(alarm, "volume_db", -60.0, fade_seconds)
	tween.tween_callback(func() -> void:
		if is_instance_valid(alarm):
			alarm.stop()
			alarm.queue_free()
	)

# -------------------------------------------------------------- анимации ---

func _spin_door_open() -> void:
	_set_inner_door_open(true)


func _spin_door_close() -> void:
	_set_inner_door_open(false)


func _set_inner_door_open(open: bool) -> void:
	if interior_door == null or _interior_door_open == open:
		return
	_interior_door_open = open
	_play(_clunk, 0.2)
	var collision := interior_door.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if open and collision != null:
		collision.set_deferred("disabled", true)
	if _interior_door_tween != null and _interior_door_tween.is_valid():
		_interior_door_tween.kill()
	_interior_door_tween = create_tween()
	_interior_door_tween.set_trans(Tween.TRANS_SINE)
	_interior_door_tween.set_ease(Tween.EASE_IN_OUT)
	var parked := _interior_door_rest + Vector3(-0.06, 0.0, -1.58)
	var target := parked if open else _interior_door_rest
	_interior_door_tween.tween_property(interior_door, "position", target, 1.1 if open else 1.0)
	if not open and collision != null:
		_interior_door_tween.tween_callback(func() -> void: collision.set_deferred("disabled", false))


func _set_outer_hatch_open(open: bool) -> void:
	if _outer_hatch_open == open:
		return
	if _hatch_pivot == null:
		push_warning("EVA: не найден внешний люк для анимации")
		return
	_outer_hatch_open = open
	_play(_clunk, 0.2)
	# With the leaf swung outboard, the long hinge barrel and knuckles sit
	# between the tunnel camera and the leaf and read as a dark object passing
	# through the door. The hinge is only needed visually while the hatch is shut.
	for hinge_name in ["HatchHingeBarrel", "HatchHingeKnuckle1",
			"HatchHingeKnuckle2", "HatchHingeKnuckle3",
			"HatchStatusLens_2_57", "HatchStatusLens_4_03"]:
		var hinge := get_parent().find_child(hinge_name, true, false) as Node3D
		if hinge != null:
			hinge.visible = not open
	if open:
		_set_exterior_shell_visible(true)
		# Keep the exterior trimesh non-blocking while the player is still
		# inside; the platform has its own collider. It is enabled explicitly
		# by the E exit action.
		if _hull_body != null:
			_hull_body.collision_layer = 1 if is_outside else 0
		_play(_hiss, 0.5)
	if _hatch_leaf_body != null:
		_hatch_leaf_body.collision_layer = 0
	var tween := _open_hatch(open)
	if tween != null:
		# The leaf is solid both closed and fully open. Collision is disabled
		# only while it is swinging, otherwise the player could walk through
		# the physical door panel itself.
		tween.finished.connect(func() -> void:
			if is_instance_valid(_hatch_leaf_body) and _hatch_pivot != null:
				# AnimatableBody3D does not always inherit a parent Tween
				# rotation in the physics server; sync the closed/open leaf
				# transform explicitly before making it solid again.
				_hatch_leaf_body.global_transform = _hatch_pivot.global_transform
				_hatch_leaf_body.collision_layer = 1
		)
	elif _hatch_leaf_body != null and _hatch_pivot != null:
		_hatch_leaf_body.global_transform = _hatch_pivot.global_transform
		_hatch_leaf_body.collision_layer = 1


func _oxygen_duration_for_profile() -> float:
	var profiles := get_node_or_null("/root/ProfileDB")
	var difficulty := String(profiles.get("difficulty")) if profiles != null else "standard"
	match difficulty:
		"calm": return oxygen_seconds_calm
		"tense": return oxygen_seconds_tense
	return oxygen_seconds_standard


func _start_eva_oxygen() -> void:
	oxygen_remaining_seconds = _oxygen_duration_for_profile()
	_oxygen_last_displayed_second = -1
	if _oxygen_label != null:
		_oxygen_label.show()
		_update_oxygen_display()


func _refill_eva_oxygen() -> void:
	oxygen_remaining_seconds = _oxygen_duration_for_profile()
	_oxygen_last_displayed_second = -1
	if _oxygen_label != null:
		_oxygen_label.hide()


func _tick_oxygen(delta: float) -> void:
	if _oxygen_depletion_in_progress:
		return
	oxygen_remaining_seconds = maxf(0.0, oxygen_remaining_seconds - delta)
	_update_oxygen_display()
	if oxygen_remaining_seconds <= 0.0:
		_return_to_eva_checkpoint.call_deferred()


func _update_oxygen_display() -> void:
	if _oxygen_label == null:
		return
	var whole_seconds := maxi(0, ceili(oxygen_remaining_seconds))
	if whole_seconds == _oxygen_last_displayed_second:
		return
	_oxygen_last_displayed_second = whole_seconds
	var minutes := whole_seconds / 60
	var seconds := whole_seconds % 60
	_oxygen_label.text = "O2  %02d:%02d" % [minutes, seconds]
	if whole_seconds <= 15:
		_oxygen_label.add_theme_color_override("font_color", Color(0.92, 0.34, 0.23, 0.92))
	elif whole_seconds <= 45:
		_oxygen_label.add_theme_color_override("font_color", Color(0.82, 0.62, 0.34, 0.88))
	else:
		_oxygen_label.add_theme_color_override("font_color", Color(0.62, 0.74, 0.70, 0.82))


func _return_to_eva_checkpoint() -> void:
	if _oxygen_depletion_in_progress or not is_outside or player == null:
		return
	_oxygen_depletion_in_progress = true
	busy = true
	if player.is_interacting:
		var story := get_parent().get_node_or_null("StoryProgression")
		if story != null and story.has_method("reset_incomplete_eva_repair"):
			story.call("reset_incomplete_eva_repair")
		else:
			player.is_interacting = false
			player.interacting_object = null
	player.velocity = Vector3.ZERO
	player.is_interacting = true
	player.interacting_object = null
	if _oxygen_label != null:
		_oxygen_label.text = "O2  ИСЧЕРПАН"
		_oxygen_label.add_theme_color_override("font_color", Color(0.92, 0.34, 0.23, 0.92))
		_oxygen_label.show()
	await _fade_to(1.0, 0.85)

	# Failure returns to the last in-ship checkpoint. Story stage is preserved;
	# an unfinished solar-panel action is reset so the EVA can be retried cleanly.
	is_outside = false
	player.set_eva_mode(false)
	if _outer_hatch_open:
		_set_outer_hatch_open(false)
	if _interior_door_open:
		_set_inner_door_open(false)
	_reset_airlock_cycle()
	if _interior != null:
		player.global_position = _interior.to_global(return_pos)
	player.velocity = Vector3.ZERO
	var look_target := _interior.to_global(Vector3(3.4, 1.5, 5.5)) if _interior != null else player.global_position + Vector3(0, 0, 1)
	var eye := player.global_position + Vector3(0.0, 1.5, 0.0)
	var look_dir := (look_target - eye).normalized()
	player.head.rotation.y = atan2(-look_dir.x, -look_dir.z) - player.rotation.y
	player.camera.rotation.x = asin(clampf(look_dir.y, -1.0, 1.0))
	if _hatch_leaf_body != null:
		_hatch_leaf_body.collision_layer = 1
	if _hull_body != null:
		_hull_body.collision_layer = 1
	await get_tree().create_timer(1.45).timeout
	_set_exterior_shell_visible(false)
	_refill_eva_oxygen()
	player.is_interacting = false
	player.interacting_object = null
	busy = false
	await _fade_to(0.0, 1.0)
	var story := get_parent().get_node_or_null("StoryProgression")
	if story != null and story.has_method("notify_eva_oxygen_depleted"):
		story.call("notify_eva_oxygen_depleted")
	_oxygen_depletion_in_progress = false


func _open_hatch(open: bool) -> Tween:
	if _hatch_pivot == null:
		return null
	var t := create_tween()
	t.set_trans(Tween.TRANS_CUBIC)
	# The GLB hinge sits on the positive-Z edge; positive yaw swings the leaf
	# outboard instead of across the pressure tunnel.
	var target_rot := _hatch_rest_rot + Vector3(0.0, 95.0, 0.0) if open else _hatch_rest_rot
	t.tween_property(_hatch_pivot, "rotation_degrees", target_rot, 1.4)
	return t

# ------------------------------------------------------------------ трос ---

func _tether(delta: float) -> void:
	var offset := player.global_position - exit_pos
	var dist := offset.length()
	if dist <= tether_length or dist < 0.01:
		return
	# мягко тянем к шлюзу, чем дальше — тем сильнее
	var pull := clampf((dist - tether_length) / (hard_tether - tether_length), 0.0, 1.0)
	player.velocity -= offset.normalized() * (1.5 + 6.0 * pull) * delta
	if dist > hard_tether:
		player.global_position = exit_pos + offset.normalized() * tether_length
		player.velocity *= 0.2

# ------------------------------------------------------------------- UI ----

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "EVA_UI"
	_ui.layer = 40
	get_parent().add_child(_ui)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 1)
	_fade.modulate.a = 0.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)

	var font: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null

	_prompt = Label.new()
	_prompt.text = ""
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.anchor_left = 0.0
	_prompt.anchor_right = 1.0
	_prompt.offset_top = -140.0
	_prompt.offset_bottom = -100.0
	_prompt.add_theme_color_override("font_color", Color(0.83, 0.95, 0.84))
	var prompt_font: Font = load(PROMPT_FONT_PATH) if ResourceLoader.exists(PROMPT_FONT_PATH) else font
	if prompt_font != null:
		_prompt.add_theme_font_override("font", prompt_font)
		_prompt.add_theme_font_size_override("font_size", 22)
	root.add_child(_prompt)

	_status = Label.new()
	_status.text = ""
	_status.anchor_left = 0.03
	_status.anchor_right = 0.6
	_status.offset_top = 26.0
	_status.offset_bottom = 58.0
	_status.add_theme_color_override("font_color", Color(0.72, 0.86, 0.72))
	if font != null:
		_status.add_theme_font_override("font", font)
		_status.add_theme_font_size_override("font_size", 18)
	root.add_child(_status)

	_oxygen_label = Label.new()
	_oxygen_label.text = "O2  03:00"
	_oxygen_label.anchor_left = 0.03
	_oxygen_label.anchor_top = 1.0
	_oxygen_label.anchor_bottom = 1.0
	_oxygen_label.offset_top = -76.0
	_oxygen_label.offset_bottom = -54.0
	_oxygen_label.add_theme_color_override("font_color", Color(0.62, 0.74, 0.70, 0.82))
	_oxygen_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_oxygen_label.add_theme_constant_override("shadow_offset_x", 1)
	_oxygen_label.add_theme_constant_override("shadow_offset_y", 1)
	if font != null:
		_oxygen_label.add_theme_font_override("font", font)
		_oxygen_label.add_theme_font_size_override("font_size", 16)
	_oxygen_label.hide()
	root.add_child(_oxygen_label)


func _update_status(top: String) -> void:
	if _status != null:
		_status.text = top
	if _prompt == null or player == null or busy:
		if _prompt != null:
			_prompt.text = ""
		return
	if Time.get_ticks_msec() < _prompt_hold_until:
		return
	var inner_pos := inside_trigger.global_position if inside_trigger != null else inside_trigger_pos
	var outer_pos := outside_trigger.global_position if outside_trigger != null else OUTER_HATCH_INTERACTION_POS
	var inner_distance := _flat_distance(player.global_position, inner_pos)
	var outer_distance := _flat_distance(player.global_position, outer_pos)
	if outer_distance <= HATCH_INTERACTION_RADIUS and (is_outside or outer_distance < inner_distance):
		if is_outside:
			if _airlock_state == STATE_VACUUM:
				_prompt.text = "[E] ОТКРЫТЬ НАРУЖНЫЙ ЛЮК" if not _outer_hatch_open else "[E] ВОЙТИ В ШЛЮЗ"
			elif _airlock_state == STATE_SEALED:
				_prompt.text = "[E] СБРОС ДАВЛЕНИЯ / ВОЙТИ"
			else:
				_prompt.text = "ИДЁТ ЦИКЛ ДАВЛЕНИЯ…"
		else:
			match _airlock_state:
				STATE_SEALED:
					_prompt.text = "[E] ЗАКРЫТЬ ДВЕРЬ / СБРОС" if _interior_door_open else "[E] СБРОС ДАВЛЕНИЯ"
				STATE_VENTING:
					_prompt.text = "ИДЁТ СБРОС ДАВЛЕНИЯ…"
				STATE_VACUUM:
					_prompt.text = "[E] ОТКРЫТЬ ЛЮК" if not _outer_hatch_open else "[E] ВЫЙТИ В КОСМОС"
				STATE_FILLING:
					_prompt.text = "ИДЁТ НАДДУВ…"
	elif not is_outside and inner_distance <= HATCH_INTERACTION_RADIUS:
		if _airlock_state == STATE_SEALED:
			_prompt.text = "[E] ЗАКРЫТЬ ВНУТРЕННИЙ ЛЮК" if _interior_door_open else "[E] ОТКРЫТЬ ВНУТРЕННИЙ ЛЮК"
		else:
			_prompt.text = "ЗАБЛОКИРОВАНО: ЦИКЛ ДАВЛЕНИЯ"
	else:
		_prompt.text = ""


func _fade_to(alpha: float, seconds: float) -> void:
	if _fade == null:
		return
	var t := create_tween()
	t.tween_property(_fade, "modulate:a", alpha, seconds)
	await t.finished

# ---------------------------------------------------------------- аудио ----

func _build_audio() -> void:
	_clunk = _audio(CLUNK, -8.0)
	_hiss = _audio(HISS, -6.0)
	_alarm = _audio(ALARM, -24.0)
	if _alarm != null:
		_alarm_repeat_enabled = true
		_alarm.play()


func _tick_emergency_alarm(delta: float) -> void:
	if not _alarm_repeat_enabled or _alarm == null or _alarm.playing:
		return
	_alarm_rest_elapsed += delta
	if _alarm_rest_elapsed >= ALARM_REST_SECONDS:
		_alarm_rest_elapsed = 0.0
		_alarm.play()


func _audio(path: String, db: float) -> AudioStreamPlayer:
	if not ResourceLoader.exists(path):
		return null
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db
	get_parent().add_child(p)
	return p


func _play(p: AudioStreamPlayer, from: float = 0.0) -> void:
	if p == null:
		return
	p.play(from)

# --------------------------------------------------------------- утилиты ---

func _find_named(part: String) -> Node3D:
	var found: Node3D = null
	var stack: Array[Node] = [get_parent()]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is Node3D and String(node.name).to_lower().contains(part.to_lower()):
			found = node as Node3D
			break
		for c in node.get_children():
			stack.push_back(c)
	return found


# ------------------------------------------------- внешний корпус корабля ---

func _make_hull_collider() -> void:
	if _ship_ext == null:
		push_warning("EVA: не найден внешний корпус для коллизии")
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_hull_meshes(_ship_ext, meshes)
	if meshes.is_empty():
		push_warning("EVA: во внешнем корпусе нет мешей для коллизии")
		return

	_hull_body = StaticBody3D.new()
	_hull_body.name = "EVA_HullCollider"
	_hull_body.collision_layer = 0
	_hull_body.collision_mask = 0
	get_parent().add_child(_hull_body)

	var collider_count := 0
	for mesh_instance in meshes:
		var shape := mesh_instance.mesh.create_trimesh_shape()
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		_hull_body.add_child(cs)
		cs.global_transform = mesh_instance.global_transform
		collider_count += 1
	if collider_count == 0:
		_hull_body.queue_free()
		_hull_body = null
		push_warning("EVA: не удалось создать треугольные коллизии внешнего корпуса")


func _make_eva_platform_collider() -> void:
	# The platform is part of the exterior hull mesh. Disabling the hull
	# trimesh on the way back must not take the floor out from under the
	# player at the exact moment gravity returns, so the landing deck gets
	# its own stable collider.
	var platform := StaticBody3D.new()
	platform.name = "EVA_PlatformCollider"
	platform.collision_layer = 1
	platform.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.40, 0.18, 2.50)
	collision.shape = box
	collision.position = Vector3(-9.85, 2.10, 11.85)
	platform.add_child(collision)
	get_parent().add_child(platform)


func _make_hatch_leaf_collider() -> void:
	if _hatch_pivot == null:
		return
	_hatch_leaf_body = AnimatableBody3D.new()
	_hatch_leaf_body.name = "HatchLeafCollider"
	_hatch_leaf_body.collision_layer = 1
	_hatch_leaf_body.collision_mask = 0
	_hatch_leaf_body.sync_to_physics = true
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.22, 2.40, 1.90)
	collision.shape = box
	# The imported leaf is centered 0.98 m from its vertical hinge in local Z.
	collision.position = Vector3(-0.02, 0.0, -0.98)
	_hatch_leaf_body.add_child(collision)
	_hatch_pivot.add_child(_hatch_leaf_body)


func _add_hatch_inner_skin() -> void:
	# The imported leaf is a shell with an opening for the outer inset and
	# manual wheel. From inside the tunnel the open leaf showed that hardware
	# through the opening as a floating dark wedge. A thin inner skin closes
	# the back of the leaf and travels with the hatch.
	var leaf := get_parent().find_child("HatchLeaf", true, false) as MeshInstance3D
	if leaf == null:
		return
	var skin := MeshInstance3D.new()
	skin.name = "HatchInnerSkin"
	var box := BoxMesh.new()
	box.size = Vector3(0.012, 2.40, 1.85)
	skin.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.31, 0.33, 0.32)
	material.roughness = 0.84
	material.metallic = 0.18
	skin.material_override = material
	skin.position = Vector3(0.067, 0.0, -0.98)
	skin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	leaf.add_child(skin)


func _add_hull_status_lights() -> void:
	# Two cold status lamps sit on the outer hull beside the hatch. In the dark
	# their emissive faces read as detached white rectangles, so each gets a
	# small local light that reveals the surrounding hull plate.
	if _ship_ext == null:
		return
	var index := 0
	for point in [Vector3(-8.56, 4.22, 13.18), Vector3(-8.44, 3.99, 14.45)]:
		var light := OmniLight3D.new()
		light.name = "HullStatusGlow%d" % index
		index += 1
		light.position = _ship_ext.to_local(point)
		light.light_color = Color(0.78, 0.88, 1.0)
		light.light_energy = 0.38
		light.omni_range = 1.6
		light.shadow_enabled = false
		_ship_ext.add_child(light)


func _dim_cold_hull_lamps() -> void:
	if _ship_ext == null:
		return
	for mesh_node in _ship_ext.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			if material == null or material.resource_name != "lamp_cold":
				continue
			var dim := material.duplicate() as StandardMaterial3D
			dim.emission_energy_multiplier = 2.0
			mesh.set_surface_override_material(surface, dim)


func _dim_hatch_status_lenses() -> void:
	# The red status lenses were authored at emission 4.0. In the dark opening
	# they clipped to white rectangles that read as floating lights, so keep
	# the red colour but bring the energy back to indicator level.
	for lens_name in ["HatchStatusLens_2_57", "HatchStatusLens_4_03"]:
		var lens := get_parent().find_child(lens_name, true, false) as MeshInstance3D
		if lens == null:
			continue
		var material := lens.get_active_material(0) as StandardMaterial3D
		if material == null:
			continue
		var dim := material.duplicate() as StandardMaterial3D
		dim.emission = Color(0.85, 0.08, 0.035, 1.0)
		dim.emission_energy_multiplier = 1.15
		lens.material_override = dim


func _collect_hull_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			result.append(mesh_instance)
	for child in node.get_children():
		_collect_hull_meshes(child, result)


func _set_exterior_visible(v: bool) -> void:
	_set_exterior_shell_visible(v)


func _set_exterior_shell_visible(v: bool) -> void:
	# The cut hull and door remain visible around the continuous walkable passage.
	if player != null:
		var ray := player.get_node_or_null("Head/Camera3D/RayCast3D") as RayCast3D
		if ray != null:
			ray.collision_mask = 2 if v else (_interaction_mask_before_eva | 2)
	if _ship_ext != null:
		_ship_ext.visible = v
	if _ext_hatch != null:
		# Keep the pressure hatch visible from the interior. The hull shell is
		# hidden during cabin view, so this leaf is the visible end of the tunnel.
		_ext_hatch.visible = true
	if _hull_body != null:
		_hull_body.collision_layer = 1 if v else 0
	_blend_exterior_lighting(1.0 if v and is_outside else 0.0)


func set_indoor_ambient(energy: float) -> void:
	_env_ambient = energy
	_apply_exterior_light_mix(_exterior_light_mix)


func _blend_exterior_lighting(target: float) -> void:
	if is_equal_approx(_exterior_light_target, target):
		return
	_exterior_light_target = target
	if _exterior_light_tween != null and _exterior_light_tween.is_valid():
		_exterior_light_tween.kill()
	_exterior_light_tween = create_tween()
	_exterior_light_tween.set_trans(Tween.TRANS_SINE)
	_exterior_light_tween.set_ease(Tween.EASE_IN_OUT)
	_exterior_light_tween.tween_method(_apply_exterior_light_mix,
		_exterior_light_mix, target, EXTERIOR_LIGHT_BLEND_SECONDS)


func _apply_exterior_light_mix(fraction: float) -> void:
	_exterior_light_mix = fraction
	if _env != null and _env.environment != null:
		_env.environment.ambient_light_energy = lerpf(_env_ambient, EXTERIOR_AMBIENT, fraction)
	if _ship_light != null:
		_ship_light.light_energy = _ship_light_energy * fraction
		_ship_light.visible = fraction > 0.0
	if _hatch_light != null:
		_hatch_light.light_energy = _hatch_light_energy * fraction
		_hatch_light.visible = fraction > 0.0
