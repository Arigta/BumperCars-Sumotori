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
const NETWORK_UPDATE_INTERVAL := 0.05

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
var remote_players: Dictionary = {}
var network_update_timer := 0.0
var match_time_left := 0.0
var match_over := false
var player_kills := 0
var player_deaths := 0
var player_assists := 0
var leaderboard_panel: PanelContainer
var leaderboard_label: Label
var match_clock_label: Label


func _ready() -> void:
	for index in 8:
		var marker := get_node_or_null("Arena/CarSpawn_%d" % (index + 1)) as Marker3D
		if marker:
			spawn_markers.append(marker)
	_build_hud()
	match_time_left = GameState.room_minutes * 60.0 if GameState.multiplayer_mode else 0.0
	if GameState.player_team != "Spectator" or not GameState.multiplayer_mode:
		_spawn_player(_available_spawn())
	if GameState.multiplayer_mode:
		for id in GameState.lobby_players:
			var record: Dictionary = GameState.lobby_players[id]
			if int(id) != multiplayer.get_unique_id() and not bool(record.get("spectator", false)):
				_spawn_remote_player(int(id), record)
	else:
		for index in BOT_COUNT:
			bots.append(_spawn_bot(_available_spawn(), index))
			bot_respawn_timers.append(0.0)
			bot_rage_progress.append(0.0)
			bot_scores.append(0)
	camera_target = player if is_instance_valid(player) else (remote_players.values()[0] if not remote_players.is_empty() else null)
	follow_camera = Camera3D.new()
	follow_camera.name = "Follow camera"
	follow_camera.fov = 72.0
	follow_camera.current = true
	add_child(follow_camera)
	if is_instance_valid(camera_target):
		follow_camera.global_position = camera_target.global_position + camera_target.global_basis * Vector3(0.0, 5.5, 10.0)
		follow_camera.look_at(camera_target.global_position + Vector3.UP * 1.2)
	else:
		follow_camera.global_position = Vector3(0.0, 20.0, 32.0)
		follow_camera.look_at(Vector3.ZERO)


func _process(delta: float) -> void:
	if toast_timer > 0.0:
		toast_timer -= delta
		toast_label.visible = toast_timer > 0.0
	if GameState.multiplayer_mode and multiplayer.is_server() and match_time_left > 0.0:
		match_time_left = maxf(0.0, match_time_left - delta)
	if GameState.multiplayer_mode and match_time_left <= 0.0 and not match_over:
		_set_match_over()
	if GameState.multiplayer_mode:
		network_update_timer -= delta
		if network_update_timer <= 0.0:
			network_update_timer = NETWORK_UPDATE_INTERVAL
			_send_network_state()
	if is_instance_valid(player) and (player.health <= 0.0 or (not player.is_defeated and player.global_position.y < ARENA_FALL_HEIGHT)):
		_player_fell()
	if GameState.multiplayer_mode and multiplayer.is_server():
		for remote in remote_players.values():
			if is_instance_valid(remote) and not remote.is_defeated and (remote.health <= 0.0 or remote.global_position.y < ARENA_FALL_HEIGHT):
				_award_fall(remote)
				remote.is_defeated = true
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
	_update_leaderboard()
	if is_instance_valid(match_clock_label):
		match_clock_label.visible = GameState.multiplayer_mode
		match_clock_label.text = "%02d:%02d" % [int(match_time_left) / 60, int(match_time_left) % 60]
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
		_return_to_menu()


func _spawn_player(marker: Marker3D) -> CharacterBody3D:
	var car = PLAYER_CAR.new()
	car.model_path = GameState.selected_asset_path()
	car.is_bot = false
	car.display_name = GameState.player_name
	car.team_name = GameState.player_team if GameState.multiplayer_mode else ""
	car.rage_progress = player_rage_progress
	car.score = player_score
	car.kills = player_kills
	car.deaths = player_deaths
	car.assists = player_assists
	_place_car(car, marker)
	add_child(car)
	car.name = "PlayerCar"
	player = car
	return car


func _spawn_remote_player(id: int, record: Dictionary) -> CharacterBody3D:
	var car = PLAYER_CAR.new()
	var car_index := clampi(int(record.get("car", 0)), 0, GameState.CAR_NAMES.size() - 1)
	car.model_path = "res://assets/cars/%s.res" % GameState.CAR_NAMES[car_index]
	car.is_bot = false
	car.network_remote = true
	car.display_name = str(record.get("name", "Pemain"))
	car.team_name = str(record.get("team", "Biru"))
	car.set_meta("network_id", id)
	_place_car(car, _available_spawn())
	add_child(car)
	car.name = "RemoteCar_%d" % id
	remote_players[id] = car
	return car


func _send_network_state() -> void:
	if not is_instance_valid(player):
		return
	var state := {"id": multiplayer.get_unique_id(), "position": player.global_position, "rotation": player.rotation.y, "speed": player.speed, "health": player.health, "score": player.score, "kills": player.kills, "deaths": player.deaths, "assists": player.assists, "time_left": match_time_left}
	if multiplayer.is_server():
		_relay_network_state(state)
	else:
		_rpc_network_state.rpc_id(1, state)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_network_state(state: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if int(state.get("id", -1)) != sender:
		return
	if remote_players.has(sender):
		var remote: CharacterBody3D = remote_players[sender]
		var reported_position: Vector3 = state.get("position", remote.global_position)
		if not remote.is_defeated and (float(state.get("health", remote.health)) <= 0.0 or reported_position.y < ARENA_FALL_HEIGHT):
			_award_fall(remote)
			remote.is_defeated = true
	_relay_network_state(state)


func _relay_network_state(state: Dictionary) -> void:
	_apply_network_state(state)
	var id := int(state.get("id", -1))
	if id != 1 and remote_players.has(id):
		var authoritative_car: CharacterBody3D = remote_players[id]
		state["score"] = authoritative_car.score
		state["kills"] = authoritative_car.kills
		state["deaths"] = authoritative_car.deaths
		state["assists"] = authoritative_car.assists
	for id in multiplayer.get_peers():
		_rpc_apply_network_state.rpc_id(int(id), state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_apply_network_state(state: Dictionary) -> void:
	_apply_network_state(state)


func _apply_network_state(state: Dictionary) -> void:
	var id := int(state.get("id", -1))
	if id == 1:
		match_time_left = float(state.get("time_left", match_time_left))
	if id == multiplayer.get_unique_id():
		player_score = int(state.get("score", player_score))
		player_kills = int(state.get("kills", player_kills))
		player_deaths = int(state.get("deaths", player_deaths))
		player_assists = int(state.get("assists", player_assists))
		if is_instance_valid(player):
			player.score = int(state.get("score", player.score))
			player.kills = int(state.get("kills", player.kills))
			player.deaths = int(state.get("deaths", player.deaths))
			player.assists = int(state.get("assists", player.assists))
		return
	if not remote_players.has(id):
		var record: Dictionary = GameState.lobby_players.get(id, {"name": "Pemain %d" % id, "car": 0})
		if bool(record.get("spectator", false)):
			return
		_spawn_remote_player(id, record)
	var car: CharacterBody3D = remote_players[id]
	car.global_position = state.get("position", car.global_position)
	car.rotation.y = float(state.get("rotation", car.rotation.y))
	car.speed = float(state.get("speed", 0.0))
	car.health = float(state.get("health", 100.0))
	car.score = int(state.get("score", 0))
	car.kills = int(state.get("kills", 0))
	car.deaths = int(state.get("deaths", 0))
	car.assists = int(state.get("assists", 0))
	car.is_defeated = car.health <= 0.0 or car.global_position.y < ARENA_FALL_HEIGHT


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
	for car in remote_players.values():
		if is_instance_valid(car) and not car.is_defeated:
			result.append(car)
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
	_award_fall(player)
	_send_network_state()
	player_score = player.score
	player_kills = player.kills
	player_deaths = player.deaths
	player_assists = player.assists
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
	var board := _make_hud_panel(canvas, Vector2(0, 0), Vector2(0, 0))
	board.position = Vector2(18, 18)
	var board_content := VBoxContainer.new()
	board_content.add_theme_constant_override("separation", 4)
	board.add_child(board_content)
	var title := Label.new()
	title.text = "PERINGKAT • KDA • SKOR"
	title.add_theme_color_override("font_color", Color("f4bb3b"))
	title.add_theme_font_size_override("font_size", 15)
	board_content.add_child(title)
	leaderboard_label = Label.new()
	leaderboard_label.add_theme_font_size_override("font_size", 13)
	board_content.add_child(leaderboard_label)
	var speed_panel := _make_hud_panel(canvas, Vector2(0, 1), Vector2(18, -18))
	speed_panel.anchor_top = 1.0
	speed_panel.anchor_bottom = 1.0
	speed_panel.offset_top = -114
	speed_panel.offset_bottom = -18
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	speed_panel.add_child(info)
	var model_label := Label.new()
	model_label.text = "%s  •  %s" % [GameState.player_name, GameState.selected_name()]
	model_label.add_theme_font_size_override("font_size", 14)
	model_label.add_theme_color_override("font_color", Color("f4bb3b"))
	info.add_child(model_label)
	speed_label = Label.new()
	speed_label.add_theme_font_size_override("font_size", 23)
	info.add_child(speed_label)
	nos_label = Label.new()
	nos_label.add_theme_font_size_override("font_size", 13)
	info.add_child(nos_label)
	ability_status_label = Label.new()
	ability_status_label.add_theme_font_size_override("font_size", 12)
	ability_status_label.add_theme_color_override("font_color", Color("dce2e7"))
	info.add_child(ability_status_label)
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 14)
	score_label.add_theme_color_override("font_color", Color("f4bb3b"))
	info.add_child(score_label)
	var vitals_panel := _make_hud_panel(canvas, Vector2(1, 0), Vector2(-18, 18))
	vitals_panel.anchor_left = 1.0
	vitals_panel.anchor_right = 1.0
	vitals_panel.offset_left = -302
	vitals_panel.offset_right = -18
	var vitals := VBoxContainer.new()
	vitals.add_theme_constant_override("separation", 4)
	vitals_panel.add_child(vitals)
	var health_title := Label.new()
	health_title.text = "DARAH"
	health_title.add_theme_font_size_override("font_size", 12)
	vitals.add_child(health_title)
	health_meter = _make_meter(vitals, Color("43d17a"))
	var nos_title := Label.new()
	nos_title.text = "ENERGI NOS"
	nos_title.add_theme_font_size_override("font_size", 12)
	vitals.add_child(nos_title)
	nos_meter = _make_meter(vitals, Color("39bbfa"))
	var rage_panel := _make_hud_panel(canvas, Vector2(0.5, 1), Vector2(0, 0))
	rage_panel.anchor_left = 0.5
	rage_panel.anchor_right = 0.5
	rage_panel.offset_left = -180
	rage_panel.offset_right = 180
	rage_panel.offset_top = -54
	rage_panel.offset_bottom = -10
	var rage_box := VBoxContainer.new()
	rage_box.add_theme_constant_override("separation", 2)
	rage_panel.add_child(rage_box)
	var rage_title := Label.new()
	rage_title.text = "RAGE"
	rage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rage_title.add_theme_font_size_override("font_size", 11)
	rage_box.add_child(rage_title)
	rage_meter = _make_meter(rage_box, Color("ff5148"))

	var menu_button := Button.new()
	menu_button.text = "MENU  (Esc)"
	menu_button.anchor_left = 1.0
	menu_button.anchor_right = 1.0
	menu_button.offset_left = -156.0
	menu_button.offset_right = -18.0
	menu_button.offset_top = 18.0
	menu_button.offset_bottom = 58.0
	menu_button.pressed.connect(_return_to_menu)
	canvas.add_child(menu_button)
	match_clock_label = Label.new()
	match_clock_label.anchor_left = 0.5
	match_clock_label.anchor_right = 0.5
	match_clock_label.offset_left = -80
	match_clock_label.offset_right = 80
	match_clock_label.offset_top = 16
	match_clock_label.offset_bottom = 48
	match_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_clock_label.add_theme_font_size_override("font_size", 24)
	match_clock_label.add_theme_color_override("font_color", Color("f4bb3b"))
	canvas.add_child(match_clock_label)
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
	_update_leaderboard()


func _make_hud_panel(canvas: Control, anchor: Vector2, offset: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = anchor.x
	panel.anchor_top = anchor.y
	panel.anchor_right = anchor.x
	panel.anchor_bottom = anchor.y
	panel.position = offset
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.13, 0.88)
	style.set_corner_radius_all(9)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	return panel


func _update_leaderboard() -> void:
	if not is_instance_valid(leaderboard_label):
		return
	var entries: Array[Dictionary] = []
	for car in _active_cars():
		entries.append({"name": car.display_name, "score": car.score, "k": car.kills, "d": car.deaths, "a": car.assists})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	var lines := PackedStringArray()
	for i in mini(5, entries.size()):
		var e: Dictionary = entries[i]
		lines.append("%d. %s  %d/%d/%d  •  %d" % [i + 1, e["name"], e["k"], e["d"], e["a"], e["score"]])
	leaderboard_label.text = "\n".join(lines) if not lines.is_empty() else "Menunggu pemain"


func _set_match_over() -> void:
	match_over = true
	for car in _active_cars():
		car.match_over = true
	_show_notification("WAKTU HABIS  •  MATCH SELESAI", Color("f4bb3b"))


func _return_to_menu() -> void:
	GameState.close_room()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


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
	victim.deaths += 1
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
	killer.kills += 1
	for attacker in eligible:
		var points := KILL_POINTS if attacker == killer else ASSIST_POINTS
		if attacker != killer:
			attacker.assists += 1
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
	menu.pressed.connect(_return_to_menu)
	layout.add_child(menu)
