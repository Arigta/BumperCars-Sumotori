extends CharacterBody3D

const ACCELERATION := 19.0
const BRAKING := 27.0
const DRAG := 10.0
const MAX_SPEED := 22.0
const REVERSE_SPEED := 9.0
const NOS_SPEED := 34.0
const NOS_MAX_ENERGY := 100.0
const NOS_DRAIN_RATE := 34.0
const NOS_REGEN_RATE := 20.0
const MAX_HEALTH := 100.0
const JUMP_FORCE := 11.0
const STEER_RATE := 1.45
const MAX_MARKS := 420

var model_path := ""
var display_name := ""
var is_bot := false
var ai_target: Node3D
var speed := 0.0
var nos_energy := NOS_MAX_ENERGY
var health := MAX_HEALTH
var hit_cooldown := 0.0
var blue_shield_time := 0.0
var unlimited_nos_time := 0.0
var jump_charges := 0
var rage_progress := 0.0
var rage_time := 0.0
var score := 0
var recent_attackers: Dictionary = {}
var bot_jump_cooldown := 3.0
var is_drifting := false
var is_boosting := false
var is_defeated := false
var planar_velocity := Vector3.ZERO
var bump_velocity := Vector3.ZERO
var smoke_particles: Array[GPUParticles3D] = []
var nos_particles: Array[GPUParticles3D] = []
var marks: Array[Node3D] = []
var mark_timer := 0.0
var previous_tire_positions: Array[Vector3] = []
var mark_material: StandardMaterial3D
var health_bar: Node3D
var health_bar_fill: MeshInstance3D
var health_bar_fill_mesh: BoxMesh
var health_bar_material: StandardMaterial3D
var blue_shield_visual: MeshInstance3D
var nos_aura_visual: MeshInstance3D
var jump_aura_visual: MeshInstance3D
var rage_aura_visual: MeshInstance3D
var rage_fire_particles: GPUParticles3D


func _ready() -> void:
	name = "PlayerCar"
	floor_snap_length = 0.35
	_build_collision()
	_load_model()
	_build_effects()
	_build_health_bar()
	_build_ability_visuals()
	mark_material = StandardMaterial3D.new()
	mark_material.albedo_color = Color(0.025, 0.027, 0.03, 0.85)
	mark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _physics_process(delta: float) -> void:
	hit_cooldown = maxf(0.0, hit_cooldown - delta)
	blue_shield_time = maxf(0.0, blue_shield_time - delta)
	unlimited_nos_time = maxf(0.0, unlimited_nos_time - delta)
	rage_time = maxf(0.0, rage_time - delta)
	_update_ability_visuals()
	if is_defeated:
		velocity.y -= 24.0 * delta
		move_and_slide()
		return
	var throttle := 0.0
	var steer := 0.0
	if is_bot:
		var controls := _bot_controls()
		throttle = controls.x
		steer = controls.y
		bot_jump_cooldown -= delta
		if bot_jump_cooldown <= 0.0:
			bot_jump_cooldown = randf_range(2.5, 5.0)
			if is_instance_valid(ai_target) and global_position.distance_to(ai_target.global_position) < 8.0 and randf() < 0.65:
				activate_jump()
	else:
		if Input.is_key_pressed(KEY_W): throttle += 1.0
		if Input.is_key_pressed(KEY_S): throttle -= 1.0
		if Input.is_key_pressed(KEY_A): steer += 1.0
		if Input.is_key_pressed(KEY_D): steer -= 1.0

	is_drifting = not is_bot and Input.is_key_pressed(KEY_SHIFT) and absf(speed) > 3.0
	var wants_nos := false
	if is_bot:
		wants_nos = is_instance_valid(ai_target) and global_position.distance_to(ai_target.global_position) > 12.0 and absf(steer) < 0.35
	else:
		wants_nos = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	is_boosting = (nos_energy > 0.0 or unlimited_nos_time > 0.0) and wants_nos and throttle > 0.0
	if is_boosting and unlimited_nos_time <= 0.0:
		nos_energy = maxf(0.0, nos_energy - NOS_DRAIN_RATE * delta)
	elif not is_boosting:
		nos_energy = minf(NOS_MAX_ENERGY, nos_energy + NOS_REGEN_RATE * delta)
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
	bump_velocity = bump_velocity.move_toward(Vector3.ZERO, 8.0 * delta)
	velocity.x = planar_velocity.x + bump_velocity.x
	velocity.z = planar_velocity.z + bump_velocity.z
	velocity.y -= 24.0 * delta
	move_and_slide()
	_resolve_car_bumps()
	if is_on_wall():
		speed *= 0.75
		planar_velocity = Vector3(velocity.x, 0.0, velocity.z)

	for particle in smoke_particles:
		particle.emitting = is_drifting and absf(speed) > 5.0
	for particle in nos_particles:
		particle.emitting = is_boosting
	_update_tire_marks(delta)


func _bot_controls() -> Vector2:
	if not is_instance_valid(ai_target):
		return Vector2(0.65, 0.35 if int(Time.get_ticks_msec() / 1600) % 2 == 0 else -0.35)
	var local_target := global_basis.inverse() * (ai_target.global_position - global_position)
	var angle := atan2(local_target.x, -local_target.z)
	var steer := clampf(-angle * 1.8, -1.0, 1.0)
	var throttle := 1.0 if absf(angle) < 2.45 else 0.35
	if local_target.length() < 5.0 and absf(angle) > 0.7:
		throttle = 0.45
	return Vector2(throttle, steer)


func _resolve_car_bumps() -> void:
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		var other := collision.get_collider()
		if not other is CharacterBody3D or other == self or not other.has_method("receive_bump"):
			continue
		other.record_touch(self)
		var impact := (planar_velocity + bump_velocity) * 0.8
		var damage_multiplier := 1.0
		if rage_time > 0.0:
			impact *= 2.0
			damage_multiplier = 2.0
		if blue_shield_time > 0.0:
			impact *= 0.6
			damage_multiplier *= 0.6
		other.receive_bump(impact, damage_multiplier)
		if other.blue_shield_time <= 0.0:
			if rage_time <= 0.0:
				planar_velocity *= 0.82
				speed *= 0.82


func receive_bump(impact: Vector3, damage_multiplier: float = 1.0) -> void:
	if is_defeated:
		return
	if blue_shield_time > 0.0:
		return
	var impact_strength := impact.length()
	if hit_cooldown <= 0.0 and impact_strength > 2.5:
		var base_impact_strength := impact_strength / maxf(damage_multiplier, 0.01)
		health = maxf(0.0, health - clampf(base_impact_strength * 0.55, 5.0, 18.0) * damage_multiplier)
		hit_cooldown = 0.42
		_update_health_bar()
		if health <= 0.0:
			is_defeated = true
			return
	var damage_ratio := 1.0 - health / MAX_HEALTH
	var vulnerability := 1.0 + damage_ratio * 1.4
	if rage_time > 0.0:
		# Rage cars keep collision damage but ignore the knockback itself.
		return
	bump_velocity += impact * vulnerability
	var limit := NOS_SPEED * 1.2
	if bump_velocity.length() > limit:
		bump_velocity = bump_velocity.normalized() * limit
	speed = maxf(speed, bump_velocity.length() * 0.65)


func receive_projectile_hit(damage: float, impulse: Vector3) -> bool:
	if is_defeated or blue_shield_time > 0.0:
		return false
	health = maxf(0.0, health - maxf(0.0, damage))
	_update_health_bar()
	if health <= 0.0:
		is_defeated = true
	else:
		var damage_ratio := 1.0 - health / MAX_HEALTH
		if rage_time <= 0.0:
			bump_velocity += impulse * (1.0 + damage_ratio * 1.4)
	if bump_velocity.length() > NOS_SPEED * 1.2:
		bump_velocity = bump_velocity.normalized() * NOS_SPEED * 1.2
	return true


func record_touch(attacker: CharacterBody3D) -> void:
	if attacker == self:
		return
	recent_attackers[attacker.get_instance_id()] = {
		"car": attacker,
		"time": Time.get_ticks_msec()
	}


func add_rage_progress(amount: float) -> bool:
	if rage_time > 0.0 or amount <= 0.0:
		return false
	rage_progress = minf(100.0, rage_progress + amount)
	if rage_progress < 100.0:
		return false
	rage_progress = 0.0
	rage_time = 10.0
	bump_velocity = Vector3.ZERO
	_update_ability_visuals()
	return true


func apply_pickup(ability: String) -> void:
	match ability:
		"blue_shield":
			blue_shield_time = 5.0
		"unlimited_nos":
			unlimited_nos_time = 10.0
		"jump":
			jump_charges = 3
	_update_ability_visuals()


func activate_jump() -> bool:
	if jump_charges <= 0 or is_defeated or not is_on_floor():
		return false
	jump_charges -= 1
	velocity.y = JUMP_FORCE
	_update_ability_visuals()
	return true


func _build_ability_visuals() -> void:
	var shield_mesh := SphereMesh.new()
	shield_mesh.radius = 1.75
	shield_mesh.height = 3.5
	shield_mesh.radial_segments = 24
	shield_mesh.rings = 12
	blue_shield_visual = MeshInstance3D.new()
	blue_shield_visual.name = "Blue shield"
	blue_shield_visual.mesh = shield_mesh
	var shield_material := StandardMaterial3D.new()
	shield_material.albedo_color = Color(0.15, 0.58, 1.0, 0.22)
	shield_material.emission_enabled = true
	shield_material.emission = Color("2799ff")
	shield_material.emission_energy_multiplier = 1.2
	shield_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	blue_shield_visual.material_override = shield_material
	blue_shield_visual.position.y = 0.75
	blue_shield_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blue_shield_visual)
	nos_aura_visual = _make_aura("NOS neon", Color("27cfff"), Vector3(0.0, 0.16, 0.0), 1.15)
	jump_aura_visual = _make_aura("Jump aura", Color("ffd83d"), Vector3(0.0, 0.55, 0.0), 1.3)
	rage_aura_visual = _make_aura("Rage aura", Color("ff3434"), Vector3(0.0, 0.28, 0.0), 1.55)
	_build_rage_fire()
	_update_ability_visuals()


func _build_rage_fire() -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Rage fire"
	particles.amount = 56
	particles.lifetime = 0.58
	particles.explosiveness = 0.0
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 1.15
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 30.0
	process.initial_velocity_min = 1.1
	process.initial_velocity_max = 3.8
	process.gravity = Vector3(0.0, -1.5, 0.0)
	process.scale_min = 0.65
	process.scale_max = 1.35
	var colors := Gradient.new()
	colors.set_color(0, Color("fff29a"))
	colors.add_point(0.35, Color("ff8a24"))
	colors.add_point(0.78, Color("f52f16"))
	colors.set_color(1, Color(0.38, 0.025, 0.005, 0.0))
	var color_ramp := GradientTexture1D.new()
	color_ramp.gradient = colors
	process.color_ramp = color_ramp
	particles.process_material = process
	var flame_mesh := QuadMesh.new()
	flame_mesh.size = Vector2(0.48, 0.85)
	var flame_material := StandardMaterial3D.new()
	flame_material.albedo_color = Color("ff6a1a")
	flame_material.emission_enabled = true
	flame_material.emission = Color("ff4a12")
	flame_material.emission_energy_multiplier = 2.4
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame_mesh.material = flame_material
	particles.draw_pass_1 = flame_mesh
	particles.position.y = 0.35
	add_child(particles)
	rage_fire_particles = particles


func _make_aura(label: String, color: Color, aura_position: Vector3, radius: float) -> MeshInstance3D:
	var aura := MeshInstance3D.new()
	aura.name = label
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.08
	mesh.outer_radius = radius
	aura.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura.material_override = material
	aura.position = aura_position
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(aura)
	return aura


func _update_ability_visuals() -> void:
	if not is_instance_valid(blue_shield_visual):
		return
	blue_shield_visual.visible = blue_shield_time > 0.0
	nos_aura_visual.visible = unlimited_nos_time > 0.0
	jump_aura_visual.visible = jump_charges > 0
	rage_aura_visual.visible = rage_time > 0.0
	rage_fire_particles.emitting = rage_time > 0.0
	if rage_time > 0.0:
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.018) * 0.08
		rage_aura_visual.scale = Vector3(pulse, 1.0, pulse)
	if jump_charges > 0:
		jump_aura_visual.scale = Vector3.ONE * (1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.06)


func _build_health_bar() -> void:
	health_bar = Node3D.new()
	health_bar.name = "Health bar"
	health_bar.position = Vector3(0.0, 2.25, 0.0)
	add_child(health_bar)
	var background := MeshInstance3D.new()
	var background_mesh := BoxMesh.new()
	background_mesh.size = Vector3(2.35, 0.09, 0.16)
	background.mesh = background_mesh
	var background_material := StandardMaterial3D.new()
	background_material.albedo_color = Color("171b22")
	background_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	background.material_override = background_material
	background.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	health_bar.add_child(background)
	health_bar_fill_mesh = BoxMesh.new()
	health_bar_fill_mesh.size = Vector3(2.25, 0.11, 0.12)
	health_bar_fill = MeshInstance3D.new()
	health_bar_fill.name = "Health fill"
	health_bar_fill.mesh = health_bar_fill_mesh
	health_bar_material = StandardMaterial3D.new()
	health_bar_material.albedo_color = Color("43d17a")
	health_bar_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	health_bar_fill.material_override = health_bar_material
	health_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	health_bar.add_child(health_bar_fill)
	_update_health_bar()


func _update_health_bar() -> void:
	if not is_instance_valid(health_bar_fill):
		return
	var health_ratio := clampf(health / MAX_HEALTH, 0.0, 1.0)
	var full_width := 2.25
	var visible_width := maxf(0.03, full_width * health_ratio)
	health_bar_fill_mesh.size.x = visible_width
	health_bar_fill.position.x = -(full_width - visible_width) * 0.5
	health_bar_material.albedo_color = Color("e84b3c").lerp(Color("43d17a"), health_ratio)


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
