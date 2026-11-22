class_name OxygenGenerator
extends Node3D
## Production oxygen generator: Poly Pizza "Generator" by KolosStudios (CC-BY 3.0),
## repainted to the ship palette, with the service panel and animated repair parts.
## The repair sequence in StoryProgression drives the public methods below.

const GLB := preload("res://assetss/ship_exterior/generator_poly_pizza.glb")

var needle_pivot: Node3D
var valve_pivot: Node3D
var filter_pivot: Node3D
var filter_mesh: MeshInstance3D
var lamp_material: StandardMaterial3D
var fan: Node3D

var _needle_material: StandardMaterial3D
var _filter_rest_z := 0.55
var _fan_speed := 90.0
var _lamp_phase := 0.0
var _lamp_base_energy := 0.85
var _model: Node3D


func _ready() -> void:
	_build_model()
	_build_repair_parts()
	_build_fan()


func _process(delta: float) -> void:
	if fan != null:
		fan.rotation_degrees.y = fmod(fan.rotation_degrees.y + _fan_speed * delta, 360.0)
	if lamp_material != null:
		_lamp_phase += delta
		lamp_material.emission_energy_multiplier = maxf(0.15,
			_lamp_base_energy + sin(_lamp_phase * 3.2) * 0.30)


func set_valve_closed(closed: bool) -> void:
	if valve_pivot == null:
		return
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(valve_pivot, "rotation_degrees:z", 270.0 if closed else 0.0, 0.65)


func set_gauge_index(index: int) -> void:
	if needle_pivot == null:
		return
	var angle := float(2 - index) * 20.0
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(needle_pivot, "rotation_degrees:z", angle, 0.35)


func set_gauge_color(color: Color) -> void:
	if _needle_material != null:
		_needle_material.albedo_color = color


func remove_filter() -> void:
	if filter_pivot == null:
		return
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(filter_pivot, "position:z", _filter_rest_z + 0.24, 0.45)


func insert_filter() -> void:
	if filter_mesh != null:
		var material := filter_mesh.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = Color(0.34, 0.39, 0.39)
	if filter_pivot == null:
		return
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(filter_pivot, "position:z", _filter_rest_z, 0.5)


func reset_repair() -> void:
	if valve_pivot != null:
		valve_pivot.rotation_degrees.z = 0.0
	if needle_pivot != null:
		needle_pivot.rotation_degrees.z = 40.0
	if _needle_material != null:
		_needle_material.albedo_color = Color(0.48, 0.12, 0.09)
	if filter_pivot != null:
		filter_pivot.position.z = _filter_rest_z
	if filter_mesh != null:
		var material := filter_mesh.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = Color(0.29, 0.26, 0.20)
	set_lamp_color(Color(0.12, 0.55, 0.25), 0.85)


func set_lamp_color(color: Color, energy: float = 0.85) -> void:
	if lamp_material == null:
		return
	lamp_material.emission = color
	_lamp_base_energy = energy


func set_fan_speed(speed: float) -> void:
	_fan_speed = speed


func _build_model() -> void:
	_model = GLB.instantiate() as Node3D
	if _model == null:
		push_error("Could not instantiate the oxygen generator model")
		return
	add_child(_model)
	var mesh := _model.find_child("Cylinder_001", true, false) as MeshInstance3D
	if mesh == null:
		push_error("Oxygen generator mesh missing")
		return
	_repaint(mesh)
	var aabb: AABB = _model.global_transform.affine_inverse() * mesh.global_transform * mesh.mesh.get_aabb()
	_model.position -= Vector3(
		aabb.position.x + aabb.size.x * 0.5,
		aabb.position.y,
		aabb.position.z + aabb.size.z * 0.5)


func _repaint(mesh: MeshInstance3D) -> void:
	var palette := [
		Color(0.62, 0.48, 0.10),    # small olive bracket -> hazard accent
		Color(0.20, 0.22, 0.24),    # light grey -> dark steel frame
		Color(0.35, 0.37, 0.39),    # mid grey -> steel
		Color(0.045, 0.05, 0.055),  # dark -> near black
		Color(0.12, 0.135, 0.15),   # olive body -> graphite
		Color(0.55, 0.10, 0.06),    # red -> warning red
	]
	for i in mesh.mesh.get_surface_count():
		var material := StandardMaterial3D.new()
		material.albedo_color = palette[i % palette.size()]
		material.metallic = 0.55 if i < 4 else 0.25
		material.roughness = 0.55 if i < 4 else 0.75
		mesh.set_surface_override_material(i, material)


func _build_repair_parts() -> void:
	var rim := MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(1.36, 0.56, 0.02)
	rim.mesh = rim_mesh
	rim.material_override = _mat(Color(0.30, 0.32, 0.34), 0.6, 0.5)
	rim.position = Vector3(0, 0.42, 0.505)
	add_child(rim)

	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(1.3, 0.5, 0.035)
	panel.mesh = panel_mesh
	panel.material_override = _mat(Color(0.13, 0.15, 0.16), 0.55, 0.6)
	panel.position = Vector3(0, 0.42, 0.52)
	add_child(panel)

	var bolt_mat := _mat(Color(0.22, 0.24, 0.25), 0.7, 0.45)
	for bx in [-0.60, 0.60]:
		for by in [0.21, 0.63]:
			_cyl(0.012, 0.015, Vector3(bx, by, 0.545), bolt_mat, Vector3(90, 0, 0))
	var hinge_mat := _mat(Color(0.26, 0.28, 0.30), 0.65, 0.5)
	for hy in [0.30, 0.54]:
		var hinge := MeshInstance3D.new()
		var hinge_mesh := BoxMesh.new()
		hinge_mesh.size = Vector3(0.035, 0.10, 0.055)
		hinge.mesh = hinge_mesh
		hinge.material_override = hinge_mat
		hinge.position = Vector3(-0.665, hy, 0.53)
		add_child(hinge)

	var stripe_mat := _mat(Color(0.72, 0.55, 0.10), 0.2, 0.6)
	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(1.3, 0.035, 0.012)
	stripe.mesh = stripe_mesh
	stripe.material_override = stripe_mat
	stripe.position = Vector3(0, 0.185, 0.55)
	add_child(stripe)
	for index in 5:
		var block := MeshInstance3D.new()
		var block_mesh := BoxMesh.new()
		block_mesh.size = Vector3(0.14, 0.035, 0.014)
		block.mesh = block_mesh
		block.material_override = _mat(Color(0.02, 0.02, 0.02), 0.1, 0.8)
		block.position = Vector3(-0.52 + index * 0.26, 0.185, 0.552)
		add_child(block)

	_build_gauge(Vector3(-0.42, 0.57, 0.55))
	_build_valve(Vector3(0.45, 0.57, 0.55))
	_build_filter(Vector3(-0.42, 0.31, 0.55))

	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.10, 0.22, 0.14)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(0.12, 0.55, 0.25)
	lamp_mat.emission_energy_multiplier = 0.85
	lamp_material = lamp_mat
	var lamp := MeshInstance3D.new()
	var lamp_mesh := CylinderMesh.new()
	lamp_mesh.top_radius = 0.035
	lamp_mesh.bottom_radius = 0.035
	lamp_mesh.height = 0.012
	lamp.mesh = lamp_mesh
	lamp.material_override = lamp_mat
	lamp.rotation_degrees.x = 90
	lamp.position = Vector3(0.45, 0.32, 0.55)
	add_child(lamp)
	_cyl(0.048, 0.02, Vector3(0.45, 0.32, 0.54), _mat(Color(0.08, 0.09, 0.10), 0.6, 0.5), Vector3(90, 0, 0))


func _build_gauge(base: Vector3) -> void:
	_cyl(0.132, 0.06, base + Vector3(0, 0, 0.02), _mat(Color(0.16, 0.19, 0.19), 0.7, 0.58), Vector3(90, 0, 0))
	_cyl(0.105, 0.012, base + Vector3(0, 0, 0.055), _mat(Color(0.43, 0.42, 0.35), 0.1, 0.72), Vector3(90, 0, 0))
	var tick_mat := _mat(Color(0.08, 0.10, 0.09), 0.05, 0.86)
	for index in 9:
		var angle := deg_to_rad(-120.0 + float(index) * 30.0)
		var tick := MeshInstance3D.new()
		var tick_mesh := BoxMesh.new()
		tick_mesh.size = Vector3(0.005, 0.014 if index % 2 == 0 else 0.009, 0.004)
		tick.mesh = tick_mesh
		tick.material_override = tick_mat
		tick.position = base + Vector3(cos(angle) * 0.078, sin(angle) * 0.078, 0.062)
		tick.rotation_degrees.z = rad_to_deg(angle)
		add_child(tick)
	needle_pivot = Node3D.new()
	needle_pivot.position = base + Vector3(0, 0, 0.068)
	needle_pivot.rotation_degrees.z = 40.0
	add_child(needle_pivot)
	var needle := MeshInstance3D.new()
	var needle_mesh := BoxMesh.new()
	needle_mesh.size = Vector3(0.006, 0.075, 0.006)
	needle.mesh = needle_mesh
	_needle_material = _mat(Color(0.48, 0.12, 0.09), 0.1, 0.86)
	needle.material_override = _needle_material
	needle.position = Vector3(0, 0.031, 0)
	needle_pivot.add_child(needle)
	_cyl(0.011, 0.018, base + Vector3(0, 0, 0.073), _mat(Color(0.25, 0.28, 0.27), 0.68, 0.64), Vector3(90, 0, 0))


func _build_valve(base: Vector3) -> void:
	var wheel_mat := _mat(Color(0.34, 0.37, 0.34), 0.55, 0.74)
	valve_pivot = Node3D.new()
	valve_pivot.position = base
	add_child(valve_pivot)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.060
	torus.outer_radius = 0.100
	torus.rings = 16
	torus.ring_segments = 12
	rim.mesh = torus
	rim.material_override = wheel_mat
	rim.rotation_degrees.x = 90
	rim.position = Vector3(0, 0, 0.02)
	valve_pivot.add_child(rim)
	for spoke in 4:
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(0.012, 0.16, 0.012)
		var spoke_node := MeshInstance3D.new()
		spoke_node.mesh = spoke_mesh
		spoke_node.material_override = wheel_mat
		spoke_node.position = Vector3(0, 0, 0.025)
		spoke_node.rotation_degrees.z = 45.0 * float(spoke)
		valve_pivot.add_child(spoke_node)
	# Asymmetric handle so the three-quarter turn is visible.
	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.032, 0.036, 0.032)
	handle.mesh = handle_mesh
	handle.material_override = _mat(Color(0.78, 0.60, 0.12), 0.2, 0.6)
	handle.position = Vector3(0, 0.125, 0.045)
	valve_pivot.add_child(handle)
	_cyl_child(valve_pivot, 0.030, 0.05, Vector3(0, 0, 0.03),
		_mat(Color(0.20, 0.22, 0.21), 0.6, 0.6), Vector3(90, 0, 0))
	_cyl(0.022, 0.10, base + Vector3(0, 0, -0.03), _mat(Color(0.20, 0.22, 0.21), 0.6, 0.6), Vector3(90, 0, 0))


func _build_filter(base: Vector3) -> void:
	var recess := MeshInstance3D.new()
	var recess_mesh := BoxMesh.new()
	recess_mesh.size = Vector3(0.24, 0.34, 0.03)
	recess.mesh = recess_mesh
	recess.material_override = _mat(Color(0.035, 0.04, 0.045), 0.4, 0.8)
	recess.position = Vector3(base.x, base.y, 0.512)
	add_child(recess)
	filter_pivot = Node3D.new()
	filter_pivot.position = base
	add_child(filter_pivot)
	_filter_rest_z = base.z
	filter_mesh = _cyl_child(filter_pivot, 0.075, 0.26, Vector3.ZERO,
		_mat(Color(0.29, 0.26, 0.20), 0.2, 0.88), Vector3.ZERO)
	_cyl_child(filter_pivot, 0.09, 0.03, Vector3(0, 0.14, 0),
		_mat(Color(0.34, 0.37, 0.34), 0.55, 0.7), Vector3.ZERO)
	_cyl_child(filter_pivot, 0.09, 0.015, Vector3(0, -0.13, 0),
		_mat(Color(0.20, 0.22, 0.21), 0.6, 0.6), Vector3.ZERO)


func _build_fan() -> void:
	fan = Node3D.new()
	fan.position = Vector3(1.06, 0.55, 0.0)
	fan.rotation_degrees.z = -90.0
	add_child(fan)
	_cyl_child(fan, 0.20, 0.02, Vector3(0, -0.012, 0),
		_mat(Color(0.04, 0.045, 0.05), 0.5, 0.6), Vector3.ZERO)
	_cyl_child(fan, 0.045, 0.035, Vector3(0, 0.006, 0),
		_mat(Color(0.25, 0.27, 0.28), 0.7, 0.4), Vector3.ZERO)
	for index in 6:
		var pivot := Node3D.new()
		pivot.rotation_degrees.y = 60.0 * float(index)
		fan.add_child(pivot)
		var blade := MeshInstance3D.new()
		var blade_mesh := BoxMesh.new()
		blade_mesh.size = Vector3(0.035, 0.02, 0.15)
		blade.mesh = blade_mesh
		blade.material_override = _mat(Color(0.16, 0.18, 0.19), 0.5, 0.55)
		blade.position = Vector3(0, 0.015, 0.095)
		pivot.add_child(blade)


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _cyl(radius: float, height: float, pos: Vector3, material: StandardMaterial3D, rotation: Vector3) -> MeshInstance3D:
	return _cyl_child(self, radius, height, pos, material, rotation)


func _cyl_child(parent: Node3D, radius: float, height: float, pos: Vector3,
		material: StandardMaterial3D, rotation: Vector3) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 24
	var node := MeshInstance3D.new()
	node.mesh = cylinder
	node.material_override = material
	node.position = pos
	node.rotation_degrees = rotation
	parent.add_child(node)
	return node
