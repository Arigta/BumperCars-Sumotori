extends Node3D

const PLAYER_CAR = preload("res://scripts/player_car.gd")
const BOT_COUNT := 3
const ARENA_FALL_HEIGHT := -8.0
const RESPAWN_COOLDOWN := 3.0
const BOT_RESPAWN_DELAY := 2.0
const PICKUP_TYPES := ["blue_shield", "unlimited_nos", "jump"]
const RAGE_SURVIVAL_RATE := 1.2
const KILL_POINTS := 30.0
const ASSIST_POINTS := 10.0

var player: CharacterBody3D
var fallen_player: CharacterBody3D
var follow_camera: Camera3D
var camera_target: Node3D
var speed_label: Label
var nos_label: Label
var ability_status_label: Label
var nos_meter: ProgressBar
var health_meter: ProgressBar
var rage_meter: ProgressBar
var score_label: Label
var toast_label: Label
var toast_timer := 0.0
var defeat_overlay: ColorRect
var respawn_button: Button
var respawn_countdown := 0.0
var respawn_ready := false
var bots: Array[CharacterBody3D] = []
var bot_respawn_timers: Array[float] = []
var bot_rage_progress: Array[float] = []
var bot_scores: Array[int] = []
var spawn_markers: Array[Marker3D] = []
var pickups: Array[Area3D] = []
var pickup_spawn_timer := 3.0
var player_rage_progress := 0.0
var player_score := 0


func _ready() -> void:
	for index in 4:
		var marker := get_node_or_null("Arena/CarSpawn_%d" % (index + 1)) as Marker3D
		if marker:
			spawn_markers.append(marker)
	_build_hud()
	_spawn_player(_available_spawn())
	for index in BOT_COUNT:
		bots.append(_spawn_bot(_available_spawn(), index))
		bot_respawn_timers.append(0.0)
		bot_rage_progress.append(0.0)
		bot_scores.append(0)
	camera_target = player
	follow_camera = Camera3D.new()
	follow_camera.name = "Follow camera"
	follow_camera.fov = 72.0
	follow_camera.current = true
	add_child(follow_camera)
	follow_camera.global_position = player.global_position + player.global_basis * Vector3(0.0, 5.5, 10.0)
	follow_camera.look_at(player.global_position + Vector3.UP * 1.2)


func _process(delta: float) -> void:
	if toast_timer > 0.0:
		toast_timer -= delta
		toast_label.visible = toast_timer > 0.0
	if is_instance_valid(player) and (player.health <= 0.0 or (not player.is_defeated and player.global_position.y < ARENA_FALL_HEIGHT)):
		_player_fell()
	for index in bots.size():
		var bot := bots[index]
		if is_instance_valid(bot) and (bot.health <= 0.0 or (not bot.is_defeated and bot.global_position.y < ARENA_FALL_HEIGHT)):
			bot_rage_progress[index] = maxf(0.0, bot.rage_progress - 10.0)
			bot_scores[index] = bot.score
			_award_fall(bot)
			bot.is_defeated = true
			bot.set_collision_layer_value(1, false)
			bot.set_collision_mask_value(1, false)
			bot_respawn_timers[index] = BOT_RESPAWN_DELAY
			bot.queue_free()
		elif not is_instance_valid(bot) and bot_respawn_timers[index] > 0.0:
			bot_respawn_timers[index] -= delta
			if bot_respawn_timers[index] <= 0.0:
				bots[index] = _spawn_bot(_available_spawn(), index)
	_assign_bot_targets()
	for car in _active_cars():
		if car.add_rage_progress(delta * RAGE_SURVIVAL_RATE) and car == player:
			_show_notification("RAGE AKTIF  •  10 DETIK", Color("ff5148"))
	_update_pickups(delta)
	_update_spectator_target()
	_update_camera(delta)
	_update_player_hud()
	if respawn_countdown > 0.0:
		respawn_countdown = maxf(0.0, respawn_countdown - delta)
		if respawn_countdown <= 0.0:
			respawn_ready = true
			respawn_button.disabled = false
			respawn_button.text = "KEMBALI KE ARENA"
		else:
			respawn_button.text = "KEMBALI KE ARENA  (%d)" % ceili(respawn_countdown)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if is_instance_valid(player):
			player.activate_jump()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and is_instance_valid(defeat_overlay) and not defeat_overlay.visible:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _spawn_player(marker: Marker3D) -> CharacterBody3D:
	var car = PLAYER_CAR.new()
	car.model_path = GameState.selected_asset_path()
	car.is_bot = false
	car.display_name = GameState.selected_name()
	car.rage_progress = player_rage_progress
	car.score = player_score
	_place_car(car, marker)
	add_child(car)
	car.name = "PlayerCar"
	player = car
	return car


func _spawn_bot(marker: Marker3D, slot: int) -> CharacterBody3D:
	var car = PLAYER_CAR.new()
	var model_names: Array = GameState.CAR_NAMES.duplicate()
	model_names.erase(GameState.selected_name())
	var model_name: String = model_names[randi() % model_names.size()]
	car.model_path = "res://assets/cars/%s.res" % model_name
	car.is_bot = true
	car.display_name = model_name
	car.rage_progress = bot_rage_progress[slot] if slot < bot_rage_progress.size() else 0.0
	car.score = bot_scores[slot] if slot < bot_scores.size() else 0
	_place_car(car, marker)
	add_child(car)
	car.name = "BotCar_%d" % (bots.size() + 1)
	return car


func _place_car(car: CharacterBody3D, marker: Marker3D) -> void:
	car.position = marker.global_position
	car.rotation.y = marker.rotation.y + randf_range(-0.32, 0.32)


func _available_spawn() -> Marker3D:
	if spawn_markers.is_empty():
		var fallback := Marker3D.new()
		fallback.position = Vector3(0.0, 0.15, 20.0)
		return fallback
	var best_marker := spawn_markers[randi() % spawn_markers.size()]
	var best_distance := -1.0
	for marker in spawn_markers:
		var nearest_distance := INF
		for car in _active_cars():
			nearest_distance = minf(nearest_distance, marker.global_position.distance_to(car.global_position))
		if nearest_distance > best_distance:
			best_distance = nearest_distance
			best_marker = marker
	return best_marker


func _active_cars() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	if is_instance_valid(player) and not player.is_defeated:
		result.append(player)
	for bot in bots:
		if is_instance_valid(bot) and not bot.is_defeated:
			result.append(bot)
	return result


func _assign_bot_targets() -> void:
	var active := _active_cars()
	for bot in bots:
		if not is_instance_valid(bot) or bot.is_defeated:
			continue
		var target: Node3D
		var nearest_distance := INF
		for car in active:
			if car == bot:
				continue
			var distance := bot.global_position.distance_squared_to(car.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				target = car
		bot.ai_target = target


func _player_fell() -> void:
	if not is_instance_valid(player):
		return
	player_rage_progress = maxf(0.0, player.rage_progress - 10.0)
	player_score = player.score
	_award_fall(player)
	player.is_defeated = true
	player.set_collision_layer_value(1, false)
	player.set_collision_mask_value(1, false)
	player.planar_velocity = Vector3.ZERO
	player.speed = 0.0
	fallen_player = player
	player = null
	respawn_countdown = RESPAWN_COOLDOWN
	respawn_ready = false
	respawn_button.disabled = true
	respawn_button.text = "KEMBALI KE ARENA  (3)"
	defeat_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_spectator_target()


func _update_spectator_target() -> void:
	if is_instance_valid(player):
		camera_target = player
		return
	var active := _active_cars()
	if active.is_empty():
		camera_target = null
		return
	var spectator_position := follow_camera.global_position if is_instance_valid(follow_camera) else Vector3.ZERO
	var closest: CharacterBody3D = active[0]
	for car in active:
		if car.global_position.distance_squared_to(spectator_position) < closest.global_position.distance_squared_to(spectator_position):
			closest = car
	camera_target = closest


func _update_camera(delta: float) -> void:
	if not is_instance_valid(follow_camera):
		return
	if not is_instance_valid(camera_target):
		return
	var desired := camera_target.global_position + camera_target.global_basis * Vector3(0.0, 5.5, 10.0)
	follow_camera.global_position = follow_camera.global_position.lerp(desired, 1.0 - exp(-5.5 * delta))
	follow_camera.look_at(camera_target.global_position + Vector3.UP * 1.2)


func _update_player_hud() -> void:
	if not is_instance_valid(player):
		speed_label.text = "SPECTATOR"
		nos_label.text = "Kamera mengikuti pertandingan"
		ability_status_label.text = ""
		nos_meter.value = 0.0
		health_meter.value = 0.0
		rage_meter.value = player_rage_progress
		score_label.text = "POIN  %d" % player_score
		return
	speed_label.text = "KECEPATAN  %02d km/j" % int(absf(player.speed) * 3.6)
	nos_label.text = "NOS TAK TERBATAS  %d dtk" % ceili(player.unlimited_nos_time) if player.unlimited_nos_time > 0.0 else ("NOS AKTIF" if player.is_boosting else ("DRIFT" if player.is_drifting else "WASD  •  Shift drift  •  Klik kanan NOS  •  Space lompat"))
	nos_label.add_theme_color_override("font_color", Color("39bbfa") if player.is_boosting else (Color("f4bb3b") if player.is_drifting else Color("dce2e7")))
	var active_abilities := PackedStringArray()
	if player.blue_shield_time > 0.0:
		active_abilities.append("PERISAI %.0f dtk" % player.blue_shield_time)
	if player.jump_charges > 0:
		active_abilities.append("LOMPAT %dx  (Space)" % player.jump_charges)
	if player.rage_time > 0.0:
		active_abilities.append("RAGE %.0f dtk" % player.rage_time)
	ability_status_label.text = "  •  ".join(active_abilities) if not active_abilities.is_empty() else ""
	nos_meter.value = 100.0 if player.unlimited_nos_time > 0.0 else player.nos_energy
	health_meter.value = player.health
	rage_meter.value = player.rage_progress
	score_label.text = "POIN  %d" % player.score
	var health_fill := health_meter.get_theme_stylebox("fill") as StyleBoxFlat
	if health_fill:
		health_fill.bg_color = Color("e84b3c").lerp(Color("43d17a"), player.health / 100.0)


func _return_to_arena() -> void:
	if not respawn_ready:
		return
	respawn_ready = false
	defeat_overlay.visible = false
	if is_instance_valid(fallen_player):
		fallen_player.queue_free()
	fallen_player = null
	_spawn_player(_available_spawn())
	camera_target = player
	_update_player_hud()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(canvas)
	_build_defeat_panel(canvas)

	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.custom_minimum_size = Vector2(330.0, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 0.88)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 7)
	panel.add_child(info)
	var model_label := Label.new()
	model_label.text = "MOBIL  %s  •  1 PEMAIN + 3 BOT" % GameState.selected_name()
	model_label.add_theme_font_size_override("font_size", 18)
	model_label.add_theme_color_override("font_color", Color("f4bb3b"))
	info.add_child(model_label)
	speed_label = Label.new()
	speed_label.add_theme_font_size_override("font_size", 24)
	info.add_child(speed_label)
	nos_label = Label.new()
	nos_label.add_theme_font_size_override("font_size", 15)
	info.add_child(nos_label)
	ability_status_label = Label.new()
	ability_status_label.add_theme_font_size_override("font_size", 13)
	ability_status_label.add_theme_color_override("font_color", Color("dce2e7"))
	info.add_child(ability_status_label)
	var health_title := Label.new()
	health_title.text = "DARAH"
	health_title.add_theme_font_size_override("font_size", 13)
	info.add_child(health_title)
	health_meter = _make_meter(info, Color("43d17a"))
	var nos_title := Label.new()
	nos_title.text = "ENERGI NOS"
	nos_title.add_theme_font_size_override("font_size", 13)
	info.add_child(nos_title)
	nos_meter = _make_meter(info, Color("39bbfa"))
	var rage_title := Label.new()
	rage_title.text = "RAGE"
	rage_title.add_theme_font_size_override("font_size", 13)
	info.add_child(rage_title)
	rage_meter = _make_meter(info, Color("ff5148"))
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 15)
	score_label.add_theme_color_override("font_color", Color("f4bb3b"))
	info.add_child(score_label)

	var menu_button := Button.new()
	menu_button.text = "MENU  (Esc)"
	menu_button.anchor_left = 1.0
	menu_button.anchor_right = 1.0
	menu_button.offset_left = -156.0
	menu_button.offset_right = -18.0
	menu_button.offset_top = 18.0
	menu_button.offset_bottom = 58.0
	menu_button.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	canvas.add_child(menu_button)
	toast_label = Label.new()
	toast_label.anchor_left = 0.2
	toast_label.anchor_right = 0.8
	toast_label.offset_top = 82.0
	toast_label.offset_bottom = 132.0
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", 30)
	toast_label.add_theme_color_override("font_color", Color("f4bb3b"))
	toast_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	toast_label.add_theme_constant_override("shadow_offset_x", 2)
	toast_label.add_theme_constant_override("shadow_offset_y", 2)
	toast_label.visible = false
	canvas.add_child(toast_label)


func _make_meter(parent: Control, fill_color: Color) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.min_value = 0.0
	meter.max_value = 100.0
	meter.show_percentage = false
	meter.custom_minimum_size = Vector2(285.0, 16.0)
	var background := StyleBoxFlat.new()
	background.bg_color = Color("11151b")
	background.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(4)
	meter.add_theme_stylebox_override("background", background)
	meter.add_theme_stylebox_override("fill", fill)
	parent.add_child(meter)
	return meter


func _show_notification(message: String, color: Color = Color("f4bb3b")) -> void:
	toast_label.text = message
	toast_label.add_theme_color_override("font_color", color)
	toast_label.visible = true
	toast_timer = 2.5


func _award_fall(victim: CharacterBody3D) -> void:
	var now := Time.get_ticks_msec()
	var latest_time := -1
	var killer: CharacterBody3D
	var eligible: Array[CharacterBody3D] = []
	for entry in victim.recent_attackers.values():
		var attacker = entry.get("car")
		var touched_at: int = entry.get("time", 0)
		if not is_instance_valid(attacker) or now - touched_at > 5000:
			continue
		eligible.append(attacker)
		if touched_at > latest_time:
			latest_time = touched_at
			killer = attacker
	if not is_instance_valid(killer):
		return
	for attacker in eligible:
		var points := KILL_POINTS if attacker == killer else ASSIST_POINTS
		attacker.score += int(points)
		var rage_activated: bool = attacker.add_rage_progress(points)
		if attacker == player:
			var message := "MENJATUHKAN %s  +%d" % [victim.display_name, int(points)] if points == KILL_POINTS else "ASSIST  +%d" % int(points)
			if rage_activated:
				message += "  •  RAGE AKTIF!"
			_show_notification(message, Color("ff5148") if rage_activated else Color("f4bb3b"))
		elif attacker.is_bot:
			var slot := bots.find(attacker)
			if slot >= 0:
				bot_scores[slot] = attacker.score
				bot_rage_progress[slot] = attacker.rage_progress


func _update_pickups(delta: float) -> void:
	pickup_spawn_timer -= delta
	for pickup in pickups:
		if is_instance_valid(pickup):
			var base_y: float = pickup.get_meta("base_y", 0.5)
			var phase: float = pickup.get_meta("phase", 0.0)
			pickup.position.y = base_y + sin(Time.get_ticks_msec() * 0.002 + phase) * 0.16
			pickup.rotation.y += delta * 0.9
	if pickup_spawn_timer <= 0.0 and pickups.size() < 3:
		_spawn_pickup()
		pickup_spawn_timer = randf_range(6.0, 9.0)


func _spawn_pickup() -> void:
	var angle := randf_range(0.0, TAU)
	var radius := sqrt(randf()) * 28.0
	var pickup := Area3D.new()
	pickup.name = "Arena pickup"
	pickup.position = Vector3(sin(angle) * radius, 0.5, cos(angle) * radius)
	pickup.collision_layer = 0
	pickup.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 1.3
	shape.shape = sphere_shape
	shape.position.y = 0.5
	pickup.add_child(shape)
	var ability: String = PICKUP_TYPES[randi() % PICKUP_TYPES.size()]
	var color := Color("2799ff")
	var label_text := "SHIELD"
	match ability:
		"unlimited_nos":
			color = Color("27cfff")
			label_text = "NOS"
		"jump":
			color = Color("ffd83d")
			label_text = "JUMP"
	var visual := MeshInstance3D.new()
	var pickup_mesh := SphereMesh.new()
	pickup_mesh.radius = 0.58
	pickup_mesh.height = 1.16
	visual.mesh = pickup_mesh
	visual.position.y = 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.2
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visual.material_override = material
	pickup.add_child(visual)
	var aura := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.68
	ring_mesh.outer_radius = 0.78
	aura.mesh = ring_mesh
	aura.position.y = 0.18
	aura.material_override = material
	pickup.add_child(aura)
	var label := Label3D.new()
	label.text = label_text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.008
	label.position.y = 1.35
	label.modulate = color
	pickup.add_child(label)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.4
	light.omni_range = 5.0
	light.position.y = 0.8
	pickup.add_child(light)
	pickup.set_meta("base_y", pickup.position.y)
	pickup.set_meta("phase", randf_range(0.0, TAU))
	pickup.body_entered.connect(_on_pickup_collected.bind(pickup, ability))
	add_child(pickup)
	pickups.append(pickup)


func _on_pickup_collected(body: Node3D, pickup: Area3D, ability: String) -> void:
	if not is_instance_valid(body) or not body.has_method("apply_pickup"):
		return
	body.apply_pickup(ability)
	if body == player:
		var messages := {
			"blue_shield": "PERISAI BIRU  •  5 DETIK",
			"unlimited_nos": "NOS TAK TERBATAS  •  10 DETIK",
			"jump": "LOMPAT  •  3 CHARGE  (SPACE)"
		}
		_show_notification(messages[ability], Color("39bbfa") if ability != "jump" else Color("ffd83d"))
	pickups.erase(pickup)
	pickup.queue_free()


func _build_defeat_panel(parent: Control) -> void:
	defeat_overlay = ColorRect.new()
	defeat_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	defeat_overlay.color = Color(0.02, 0.025, 0.035, 0.34)
	defeat_overlay.visible = false
	parent.add_child(defeat_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	defeat_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420.0, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("242a33")
	style.border_color = Color("d84336")
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 26
	style.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "KAMU JATUH  •  SPECTATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("f06a59"))
	layout.add_child(title)
	var description := Label.new()
	description.text = "Kamera mengikuti mobil yang masih bertanding."
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size", 17)
	layout.add_child(description)
	respawn_button = Button.new()
	respawn_button.text = "KEMBALI KE ARENA  (3)"
	respawn_button.custom_minimum_size.y = 48
	respawn_button.disabled = true
	respawn_button.pressed.connect(_return_to_arena)
	layout.add_child(respawn_button)
	var menu := Button.new()
	menu.text = "KEMBALI KE MENU"
	menu.custom_minimum_size.y = 44
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	layout.add_child(menu)
