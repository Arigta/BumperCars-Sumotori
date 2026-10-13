extends CharacterBody3D

const ACCELERATION := 19.0
const BRAKING := 27.0
const DRAG := 10.0
const MAX_SPEED := 22.0
const REVERSE_SPEED := 9.0
const NOS_SPEED := 34.0
const STEER_RATE := 1.45
const MAX_MARKS := 420

var model_path := ""
var speed := 0.0
var is_drifting := false
var is_boosting := false
var is_defeated := false
var planar_velocity := Vector3.ZERO
var smoke_particles: Array[GPUParticles3D] = []
var nos_particles: Array[GPUParticles3D] = []
var marks: Array[Node3D] = []
var mark_timer := 0.0
var previous_tire_positions: Array[Vector3] = []
var mark_material: StandardMaterial3D


func _ready() -> void:
	name = "PlayerCar"
	floor_snap_length = 0.35
	_build_collision()
	_load_model()
	_build_effects()
	mark_material = StandardMaterial3D.new()
	mark_material.albedo_color = Color(0.025, 0.027, 0.03, 0.85)
	mark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _physics_process(delta: float) -> void:
	if is_defeated:
		velocity.y -= 24.0 * delta
		move_and_slide()
		return
	var throttle := 0.0
	if Input.is_key_pressed(KEY_W): throttle += 1.0
	if Input.is_key_pressed(KEY_S): throttle -= 1.0
	var steer := 0.0
	if Input.is_key_pressed(KEY_A): steer += 1.0
	if Input.is_key_pressed(KEY_D): steer -= 1.0

	is_drifting = Input.is_key_pressed(KEY_SHIFT) and absf(speed) > 3.0
	is_boosting = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and throttle > 0.0
	var top_speed := NOS_SPEED if is_boosting else MAX_SPEED
	if throttle > 0.0:
		speed = move_toward(speed, top_speed, (ACCELERATION + (17.0 if is_boosting else 0.0)) * delta)
	elif throttle < 0.0:
		speed = move_toward(speed, -REVERSE_SPEED, BRAKING * delta)
	else:
		speed = move_toward(speed, 0.0, DRAG * delta)

	if absf(speed) > 0.5:
		var steering_strength: float = clampf(absf(speed) / 11.0, 0.2, 1.0)
		rotation.y += steer * STEER_RATE * steering_strength * signf(speed) * delta

	var forward := -global_basis.z
	var desired_velocity := forward * speed
	var grip := 2.0 if is_drifting else 11.0
	planar_velocity = planar_velocity.lerp(desired_velocity, 1.0 - exp(-grip * delta))
	velocity.x = planar_velocity.x
	velocity.z = planar_velocity.z
	velocity.y -= 24.0 * delta
	move_and_slide()
	if is_on_wall():
		speed *= 0.75
		planar_velocity = Vector3(velocity.x, 0.0, velocity.z)

	for particle in smoke_particles:
		particle.emitting = is_drifting and absf(speed) > 5.0
	for particle in nos_particles:
		particle.emitting = is_boosting
	_update_tire_marks(delta)


func _build_collision() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.85, 1.15, 3.65)
	var collider := CollisionShape3D.new()
	collider.name = "Car collider"
	collider.shape = shape
	collider.position.y = 0.62
	add_child(collider)


func _load_model() -> void:
	var resource := ResourceLoader.load(model_path)
	var visual: Node3D
	if resource is PackedScene:
		visual = resource.instantiate() as Node3D
	elif resource is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = resource
		visual = mesh_instance
	else:
		push_error("Model mobil gagal dimuat: %s" % model_path)
		visual = _placeholder_model()
	visual.name = "Selected car model"
	# The source cars face +Z; Godot's forward direction is -Z.
	visual.rotation.y = PI
	add_child(visual)


func _placeholder_model() -> Node3D:
	var root := Node3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.8, 1.1, 3.6)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position.y = 0.65
	root.add_child(instance)
	return root


func _build_effects() -> void:
	for side in [-1.0, 1.0]:
		var smoke := _particles(Color(0.52, 0.54, 0.56, 0.6), 0.34, 0.75, Vector3(0.0, 1.0, 0.0), 24)
		smoke.name = "Drift smoke"
		smoke.position = Vector3(side * 0.72, 0.24, 1.25)
		add_child(smoke)
		smoke_particles.append(smoke)
		var flame := _particles(Color(0.12, 0.72, 1.0, 0.9), 0.17, 0.28, Vector3(0.0, 0.0, 1.0), 35)
		flame.name = "NOS flame"
		flame.position = Vector3(side * 0.48, 0.44, 1.92)
		add_child(flame)
		nos_particles.append(flame)


func _particles(color: Color, particle_size: float, lifetime: float, direction: Vector3, amount: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.explosiveness = 0.0
	particles.emitting = false
	var process := ParticleProcessMaterial.new()
	process.direction = direction
	process.spread = 22.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 3.5
	process.gravity = Vector3(0.0, 1.3, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.3
	particles.process_material = process
	var sphere := SphereMesh.new()
	sphere.radius = particle_size
	sphere.height = particle_size * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = false
	if direction.z > 0.5:
		material.emission_enabled = true
		material.emission = Color(0.1, 0.55, 1.0)
		material.emission_energy_multiplier = 3.0
	sphere.material = material
	particles.draw_pass_1 = sphere
	return particles


func _update_tire_marks(delta: float) -> void:
	if not is_drifting or not is_on_floor() or absf(speed) < 5.0:
		previous_tire_positions.clear()
		mark_timer = 0.0
		return
	mark_timer += delta
	if mark_timer < 0.055:
		return
	mark_timer = 0.0
	var tire_positions: Array[Vector3] = [global_transform * Vector3(-0.72, 0.0, 1.25), global_transform * Vector3(0.72, 0.0, 1.25)]
	if previous_tire_positions.size() == 2:
		for i in 2:
			_make_mark(previous_tire_positions[i], tire_positions[i])
	previous_tire_positions = tire_positions


func _make_mark(from: Vector3, to: Vector3) -> void:
	var difference := to - from
	difference.y = 0.0
	if difference.length() < 0.04 or difference.length() > 3.0:
		return
	var mark := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.24, 0.012, difference.length() + 0.05)
	mark.mesh = mesh
	mark.material_override = mark_material
	mark.position = (from + to) * 0.5
	mark.position.y = 0.014
	mark.rotation.y = atan2(difference.x, difference.z)
	get_parent().add_child(mark)
	marks.append(mark)
	if marks.size() > MAX_MARKS:
		marks.pop_front().queue_free()
