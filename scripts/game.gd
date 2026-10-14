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
var bot_network_ids: Array[int] = []
var bot_contact_times: Dictionary = {}
var bot_respawn_timers: Array[float] = []
var bot_rage_progress: Array[float] = []
var bot_scores: Array[int] = []
var bot_kills: Array[int] = []
var bot_deaths: Array[int] = []
var bot_assists: Array[int] = []
var bot_names: Array[String] = []
var spawn_markers: Array[Marker3D] = []
var pickups: Array[Area3D] = []
var pickup_by_id: Dictionary = {}
var pickup_sent_peers: Dictionary = {}
var next_pickup_id := 1
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
var leaderboard_cells: Array[Label] = []
var match_clock_label: Label
var results_overlay: ColorRect
var results_label: Label


func _ready() -> void:
	for index in 8:
		var marker := get_node_or_null("Arena/CarSpawn_%d" % (index + 1)) as Marker3D
		if marker:
			spawn_markers.append(marker)
	_build_hud()
	match_time_left = GameState.match_time_remaining if GameState.multiplayer_mode else 0.0
	if GameState.player_team != "Spectator" or not GameState.multiplayer_mode:
		_spawn_player(_available_spawn())
	if GameState.multiplayer_mode:
		GameState.lobby_updated.connect(_sync_remote_roster)
		for id in GameState.lobby_players:
			var record: Dictionary = GameState.lobby_players[id]
			if bool(record.get("bot", false)) and multiplayer.is_server():
				var slot := bots.size()
				bot_network_ids.append(int(id))
				bots.append(_spawn_bot(_available_spawn(), slot, record))
				bot_respawn_timers.append(0.0)
				bot_rage_progress.append(0.0)
				bot_scores.append(0)
				bot_kills.append(0)
				bot_deaths.append(0)
				bot_assists.append(0)
				bot_names.append(str(record.get("name", "Bot")))
			elif int(id) != multiplayer.get_unique_id() and not bool(record.get("spectator", false)):
				_spawn_remote_player(int(id), record)
	else:
		for index in BOT_COUNT:
			bot_network_ids.append(0)
			bots.append(_spawn_bot(_available_spawn(), index))
			bot_respawn_timers.append(0.0)
			bot_rage_progress.append(0.0)
			bot_scores.append(0)
			bot_kills.append(0)
			bot_deaths.append(0)
			bot_assists.append(0)
			bot_names.append(bots[index].display_name)
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
	GameState.announce_game_ready()


func _process(delta: float) -> void:
	if toast_timer > 0.0:
		toast_timer -= delta
		toast_label.visible = toast_timer > 0.0
	_interpolate_network_cars(delta)
	if GameState.multiplayer_mode and multiplayer.is_server() and match_time_left > 0.0:
		match_time_left = maxf(0.0, match_time_left - delta)
		GameState.match_time_remaining = match_time_left
	if GameState.multiplayer_mode and match_time_left <= 0.0 and not match_over:
		_set_match_over()
	if GameState.multiplayer_mode:
		network_update_timer -= delta
		if network_update_timer <= 0.0:
			network_update_timer = NETWORK_UPDATE_INTERVAL
			_send_network_state()
			if multiplayer.is_server():
				_send_bot_states()
				_sync_pickups_to_peers()
	if is_instance_valid(player) and (player.health <= 0.0 or (not player.is_defeated and player.global_position.y < ARENA_FALL_HEIGHT)):
		_player_fell()
	if GameState.multiplayer_mode and multiplayer.is_server():
		for remote in remote_players.values():
			if is_instance_valid(remote) and not remote.is_defeated and (remote.health <= 0.0 or remote.global_position.y < ARENA_FALL_HEIGHT):
				remote.rage_progress = maxf(0.0, remote.rage_progress - 10.0)
				_award_fall(remote)
				remote.is_defeated = true
	for index in bots.size():
		var bot := bots[index]
		if is_instance_valid(bot) and (bot.health <= 0.0 or (not bot.is_defeated and bot.global_position.y < ARENA_FALL_HEIGHT)):
			bot_rage_progress[index] = maxf(0.0, bot.rage_progress - 10.0)
			_award_fall(bot)
			bot_scores[index] = bot.score
			bot_kills[index] = bot.kills
			bot_deaths[index] = bot.deaths
			bot_assists[index] = bot.assists
			bot.is_defeated = true
			if GameState.multiplayer_mode and multiplayer.is_server():
				_send_bot_state(index)
			bot.set_collision_layer_value(1, false)
			bot.set_collision_mask_value(1, false)
			bot_respawn_timers[index] = BOT_RESPAWN_DELAY
			bot.queue_free()
		elif not match_over and not is_instance_valid(bot) and bot_respawn_timers[index] > 0.0:
			bot_respawn_timers[index] -= delta
			if bot_respawn_timers[index] <= 0.0:
				var record: Dictionary = GameState.lobby_players.get(bot_network_ids[index], {}) if GameState.multiplayer_mode else {}
				bots[index] = _spawn_bot(_available_spawn(), index, record)
				bot_names[index] = bots[index].display_name
	_assign_bot_targets()
	for car in _active_cars():
		if car.add_rage_progress(delta * RAGE_SURVIVAL_RATE) and car == player:
			_show_notification("RAGE AKTIF  •  10 DETIK", Color("ff5148"))
	if not match_over:
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
	if GameState.multiplayer_mode:
		car.remote_bot_hit.connect(_on_remote_bot_hit)
		car.remote_player_hit.connect(_on_bot_remote_player_hit)
		car.remote_player_contact.connect(_on_remote_player_contact)
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
	car.is_bot = bool(record.get("bot", false))
	car.display_name = str(record.get("name", "Pemain"))
	car.team_name = str(record.get("team", "Biru"))
	car.set_meta("network_id", id)
	_place_car(car, _available_spawn())
	add_child(car)
	car.name = "RemoteCar_%d" % id
	remote_players[id] = car
	return car


func _sync_remote_roster() -> void:
	for id in remote_players.keys():
		var record: Dictionary = GameState.lobby_players.get(id, {})
		if record.is_empty() or bool(record.get("spectator", false)):
			var old_car: CharacterBody3D = remote_players[id]
			remote_players.erase(id)
			old_car.queue_free()
	for id in GameState.lobby_players:
		if int(id) == multiplayer.get_unique_id():
			continue
		var record: Dictionary = GameState.lobby_players[id]
		if bool(record.get("spectator", false)):
			continue
		if GameState.room_host and bool(record.get("bot", false)):
			continue
		if not remote_players.has(id):
			_spawn_remote_player(int(id), record)
		else:
			var car: CharacterBody3D = remote_players[id]
			car.display_name = str(record.get("name", "Pemain"))
			car.team_name = str(record.get("team", "Biru"))


func _send_network_state() -> void:
	if not is_instance_valid(player):
		return
	var state := _car_network_state(player, multiplayer.get_unique_id())
	if multiplayer.is_server():
		_relay_network_state(state)
	else:
		_rpc_network_state.rpc_id(1, state)


func _send_bot_states() -> void:
	for index in bots.size():
		_send_bot_state(index)


func _send_bot_state(index: int) -> void:
	if index >= bot_network_ids.size() or bot_network_ids[index] >= 0:
		return
	var bot := bots[index]
	if not is_instance_valid(bot):
		return
	var state := _car_network_state(bot, bot_network_ids[index])
	for peer_id in GameState.game_ready_peers:
		_rpc_apply_network_state.rpc_id(int(peer_id), state)


func _car_network_state(car: CharacterBody3D, network_id: int) -> Dictionary:
	return {
		"id": network_id,
		"position": car.global_position,
		"rotation": car.rotation.y,
		"speed": car.speed,
		"health": car.health,
		"score": car.score,
		"kills": car.kills,
		"deaths": car.deaths,
		"assists": car.assists,
		"nos_energy": car.nos_energy,
		"blue_shield_time": car.blue_shield_time,
		"unlimited_nos_time": car.unlimited_nos_time,
		"jump_charges": car.jump_charges,
		"rage_progress": car.rage_progress,
		"rage_time": car.rage_time,
		"is_boosting": car.is_boosting,
		"is_defeated": car.is_defeated,
		"time_left": match_time_left
	}


func _on_remote_bot_hit(bot_id: int, impact: Vector3, damage_multiplier: float) -> void:
	if bot_id < 0 and not multiplayer.is_server():
		var key := "local:%d" % bot_id
		var now := Time.get_ticks_msec()
		if now - int(bot_contact_times.get(key, -1000)) < 250:
			return
		bot_contact_times[key] = now
		_rpc_hit_bot.rpc_id(1, bot_id, impact, damage_multiplier)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hit_bot(bot_id: int, impact: Vector3, damage_multiplier: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var slot := bot_network_ids.find(bot_id)
	if not remote_players.has(sender) or slot < 0 or not is_instance_valid(bots[slot]):
		return
	var bot := bots[slot]
	var attacker: CharacterBody3D = remote_players[sender]
	_server_apply_contact(attacker, bot_id, impact, damage_multiplier)


func _on_remote_player_contact(victim_id: int, impact: Vector3, damage_multiplier: float) -> void:
	if GameState.multiplayer_mode and not multiplayer.is_server():
		var key := "%d:%d" % [multiplayer.get_unique_id(), victim_id]
		var now := Time.get_ticks_msec()
		if now - int(bot_contact_times.get(key, -1000)) < 250:
			return
		bot_contact_times[key] = now
		_rpc_report_player_contact.rpc_id(1, victim_id, impact, damage_multiplier)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_player_contact(victim_id: int, impact: Vector3, damage_multiplier: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not remote_players.has(sender):
		return
	_server_apply_contact(remote_players[sender], victim_id, impact, damage_multiplier)


func _on_bot_remote_player_hit(peer_id: int, bot_id: int, impact: Vector3, damage_multiplier: float) -> void:
	if peer_id <= 1 or not multiplayer.is_server() or not remote_players.has(peer_id):
		return
	var key := "%d:%d" % [peer_id, bot_id]
	var now := Time.get_ticks_msec()
	if now - int(bot_contact_times.get(key, -1000)) < 180:
		return
	bot_contact_times[key] = now
	var attacker := _network_car(bot_id)
	if is_instance_valid(attacker):
		_server_apply_contact(attacker, peer_id, impact, damage_multiplier)



func _network_car(network_id: int) -> CharacterBody3D:
	if network_id == 1:
		return player
	if network_id < 0:
		var slot := bot_network_ids.find(network_id)
		return bots[slot] if slot >= 0 and slot < bots.size() else null
	return remote_players.get(network_id) as CharacterBody3D


func _server_apply_contact(attacker: CharacterBody3D, victim_id: int, impact: Vector3, damage_multiplier: float) -> void:
	if not multiplayer.is_server() or not is_instance_valid(attacker):
		return
	var victim := _network_car(victim_id)
	if not is_instance_valid(victim) or victim.is_defeated or attacker.is_defeated:
		return
	if attacker.global_position.distance_to(victim.global_position) > 8.0:
		return
	victim.record_touch(attacker)
	if impact.length() > 0.5:
		victim.receive_bump(impact.limit_length(45.0), clampf(damage_multiplier, 0.0, 2.0))
	if victim_id > 1 and GameState.game_ready_peers.has(victim_id):
		_rpc_apply_contact.rpc_id(victim_id, int(attacker.get_meta("network_id", 1)), impact.limit_length(45.0), clampf(damage_multiplier, 0.0, 2.0))
	if victim_id < 0:
		var slot := bot_network_ids.find(victim_id)
		if slot >= 0:
			_send_bot_state(slot)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_contact(attacker_id: int, impact: Vector3, damage_multiplier: float) -> void:
	if not is_instance_valid(player):
		return
	var attacker := _network_car(attacker_id)
	if is_instance_valid(attacker):
		player.record_touch(attacker)
	player.receive_bump(impact, damage_multiplier)


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
		var reported_health := float(state.get("health", remote.health))
		if remote.is_defeated and not match_over and reported_health > 0.0 and reported_position.y >= ARENA_FALL_HEIGHT:
			remote.is_defeated = false
			remote.health = reported_health
			remote.nos_energy = float(state.get("nos_energy", remote.nos_energy))
			remote.blue_shield_time = 0.0
			remote.unlimited_nos_time = 0.0
			remote.jump_charges = 0
			remote.rage_progress = float(state.get("rage_progress", maxf(0.0, remote.rage_progress - 10.0)))
			remote.rage_time = 0.0
			remote.recent_attackers.clear()
		if not remote.is_defeated and (float(state.get("health", remote.health)) <= 0.0 or reported_position.y < ARENA_FALL_HEIGHT):
			remote.rage_progress = maxf(0.0, remote.rage_progress - 10.0)
			_award_fall(remote)
			remote.is_defeated = true
		# The host owns scoring and pickup effects; clients only report movement and NOS use.
		state["score"] = remote.score
		state["kills"] = remote.kills
		state["deaths"] = remote.deaths
		state["assists"] = remote.assists
		state["blue_shield_time"] = remote.blue_shield_time
		state["unlimited_nos_time"] = remote.unlimited_nos_time
		state["jump_charges"] = mini(remote.jump_charges, int(state.get("jump_charges", remote.jump_charges)))
		state["rage_progress"] = remote.rage_progress
		state["rage_time"] = remote.rage_time
		state["is_defeated"] = remote.is_defeated
	_relay_network_state(state)


func _relay_network_state(state: Dictionary) -> void:
	_apply_network_state(state)
	var id := int(state.get("id", -1))
	if id != 1 and remote_players.has(id):
		var authoritative_car: CharacterBody3D = remote_players[id]
		for key in ["score", "kills", "deaths", "assists", "nos_energy", "blue_shield_time", "unlimited_nos_time", "jump_charges", "rage_progress", "rage_time", "is_boosting", "is_defeated"]:
			state[key] = authoritative_car.get(key)
	for peer_id in GameState.game_ready_peers:
		_rpc_apply_network_state.rpc_id(int(peer_id), state)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_apply_network_state(state: Dictionary) -> void:
	_apply_network_state(state)


func _apply_network_state(state: Dictionary) -> void:
	var id := int(state.get("id", -1))
	if id == 1 or id < 0:
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
			_apply_car_ability_state(player, state)
		return
	if not remote_players.has(id):
		var record: Dictionary = GameState.lobby_players.get(id, {"name": "Pemain %d" % id, "car": 0})
		if bool(record.get("spectator", false)):
			return
		_spawn_remote_player(id, record)
	var car: CharacterBody3D = remote_players[id]
	car.set_meta("network_target_position", state.get("position", car.global_position))
	car.set_meta("network_target_rotation", float(state.get("rotation", car.rotation.y)))
	car.speed = float(state.get("speed", 0.0))
	car.planar_velocity = -car.global_basis.z * car.speed
	car.health = float(state.get("health", 100.0))
	car.score = int(state.get("score", 0))
	car.kills = int(state.get("kills", 0))
	car.deaths = int(state.get("deaths", 0))
	car.assists = int(state.get("assists", 0))
	_apply_car_ability_state(car, state)
	car.is_defeated = bool(state.get("is_defeated", false)) or car.health <= 0.0 or car.global_position.y < ARENA_FALL_HEIGHT
	car.visible = not car.is_defeated
	car._update_health_bar()
	car._update_ability_visuals()


func _interpolate_network_cars(delta: float) -> void:
	var weight := 1.0 - exp(-18.0 * delta)
	for car in remote_players.values():
		if not is_instance_valid(car):
			continue
		var target_position: Vector3 = car.get_meta("network_target_position", car.global_position)
		var distance := car.global_position.distance_to(target_position)
		if distance > 12.0:
			car.global_position = target_position
		else:
			car.global_position = car.global_position.lerp(target_position, weight)
		var target_rotation := float(car.get_meta("network_target_rotation", car.rotation.y))
		car.rotation.y = lerp_angle(car.rotation.y, target_rotation, weight)
		car.planar_velocity = -car.global_basis.z * car.speed


func _apply_car_ability_state(car: CharacterBody3D, state: Dictionary) -> void:
	car.nos_energy = float(state.get("nos_energy", car.nos_energy))
	car.blue_shield_time = float(state.get("blue_shield_time", car.blue_shield_time))
	car.unlimited_nos_time = float(state.get("unlimited_nos_time", car.unlimited_nos_time))
	car.jump_charges = int(state.get("jump_charges", car.jump_charges))
	car.rage_progress = float(state.get("rage_progress", car.rage_progress))
	car.rage_time = float(state.get("rage_time", car.rage_time))
	car.is_boosting = bool(state.get("is_boosting", car.is_boosting))


func _spawn_bot(marker: Marker3D, slot: int, record: Dictionary = {}) -> CharacterBody3D:
	var car = PLAYER_CAR.new()
	var model_name := ""
	if record.is_empty():
		var model_names: Array = GameState.CAR_NAMES.duplicate()
		model_names.erase(GameState.selected_name())
		model_name = str(model_names[randi() % model_names.size()])
	else:
		var car_index := clampi(int(record.get("car", 0)), 0, GameState.CAR_NAMES.size() - 1)
		model_name = GameState.CAR_NAMES[car_index]
	car.model_path = "res://assets/cars/%s.res" % model_name
	car.is_bot = true
	car.display_name = str(record.get("name", model_name))
	car.team_name = str(record.get("team", "")) if GameState.multiplayer_mode else ""
	if slot < bot_network_ids.size() and bot_network_ids[slot] < 0:
		car.set_meta("network_id", bot_network_ids[slot])
		car.remote_player_hit.connect(_on_bot_remote_player_hit)
	car.rage_progress = bot_rage_progress[slot] if slot < bot_rage_progress.size() else 0.0
	car.score = bot_scores[slot] if slot < bot_scores.size() else 0
	car.kills = bot_kills[slot] if slot < bot_kills.size() else 0
	car.deaths = bot_deaths[slot] if slot < bot_deaths.size() else 0
	car.assists = bot_assists[slot] if slot < bot_assists.size() else 0
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
	leaderboard_panel = _make_hud_panel(canvas, Vector2(0, 0), Vector2.ZERO)
	leaderboard_panel.offset_left = 18
	leaderboard_panel.offset_right = 258
	leaderboard_panel.offset_top = 18
	leaderboard_panel.offset_bottom = 222
	var board_content := VBoxContainer.new()
	board_content.add_theme_constant_override("separation", 6)
	leaderboard_panel.add_child(board_content)
	var title := Label.new()
	title.text = "LEADERBOARD"
	title.add_theme_color_override("font_color", Color("f4bb3b"))
	title.add_theme_font_size_override("font_size", 13)
	board_content.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 3)
	board_content.add_child(grid)
	for heading in ["#", "PEMAIN", "K", "D", "A"]:
		var header := Label.new()
		header.text = heading
		header.add_theme_font_size_override("font_size", 10)
		header.add_theme_color_override("font_color", Color("9aa5af"))
		if heading == "PEMAIN":
			header.custom_minimum_size.x = 110
		else:
			header.custom_minimum_size.x = 20
			header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(header)
	for row in 8:
		for column in 5:
			var cell := Label.new()
			cell.add_theme_font_size_override("font_size", 11)
			cell.add_theme_color_override("font_color", Color("f4bb3b") if column == 2 else Color("e5ebf0"))
			if column == 1:
				cell.custom_minimum_size.x = 110
				cell.clip_text = true
			else:
				cell.custom_minimum_size.x = 20
				cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(cell)
			leaderboard_cells.append(cell)
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
	menu_button.anchor_top = 1.0
	menu_button.anchor_bottom = 1.0
	menu_button.offset_left = -156.0
	menu_button.offset_right = -18.0
	menu_button.offset_top = -58.0
	menu_button.offset_bottom = -18.0
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
	_build_match_results(canvas)
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
	if leaderboard_cells.is_empty():
		return
	var entries: Array[Dictionary] = []
	if GameState.multiplayer_mode:
		for id in GameState.lobby_players:
			var record: Dictionary = GameState.lobby_players[id]
			if bool(record.get("spectator", false)):
				continue
			var name := str(record.get("name", "Pemain"))
			if int(id) == multiplayer.get_unique_id():
				var local_car := player if is_instance_valid(player) else fallen_player
				entries.append(_leaderboard_entry(name, local_car, player_kills, player_deaths, player_assists))
			elif GameState.room_host and bool(record.get("bot", false)):
				var slot := bot_network_ids.find(int(id))
				if slot < 0:
					continue
				entries.append(_leaderboard_entry(name, bots[slot], bot_kills[slot], bot_deaths[slot], bot_assists[slot]))
			else:
				var remote: Variant = remote_players.get(id)
				entries.append(_leaderboard_entry(name, remote))
	else:
		var local_car := player if is_instance_valid(player) else fallen_player
		entries.append(_leaderboard_entry(GameState.player_name, local_car, player_kills, player_deaths, player_assists))
		for index in bots.size():
			entries.append(_leaderboard_entry(bot_names[index], bots[index], bot_kills[index], bot_deaths[index], bot_assists[index]))
	entries.sort_custom(_leaderboard_before)
	for row in 8:
		var has_entry := row < entries.size()
		var values := ["", "", "", "", ""]
		if has_entry:
			var entry: Dictionary = entries[row]
			values = [str(row + 1), str(entry["name"]), str(entry["k"]), str(entry["d"]), str(entry["a"])]
		for column in 5:
			var cell := leaderboard_cells[row * 5 + column]
			cell.visible = has_entry
			cell.text = values[column]


func _leaderboard_entry(name: String, car: Variant, kills: int = 0, deaths: int = 0, assists: int = 0) -> Dictionary:
	if is_instance_valid(car):
		return {"name": name, "k": car.kills, "d": car.deaths, "a": car.assists}
	return {"name": name, "k": kills, "d": deaths, "a": assists}


func _leaderboard_before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["k"]) != int(b["k"]):
		return int(a["k"]) > int(b["k"])
	if int(a["d"]) != int(b["d"]):
		return int(a["d"]) < int(b["d"])
	if int(a["a"]) != int(b["a"]):
		return int(a["a"]) > int(b["a"])
	return str(a["name"]) < str(b["name"])


func _set_match_over() -> void:
	if match_over:
		return
	match_over = true
	_freeze_match_cars()
	if not GameState.multiplayer_mode:
		_show_match_results(_collect_match_results())
	elif multiplayer.is_server():
		var results := _collect_match_results()
		_show_match_results(results)
		for peer_id in GameState.game_ready_peers:
			_rpc_match_results.rpc_id(int(peer_id), results)


func _freeze_match_cars() -> void:
	if is_instance_valid(player):
		player.match_over = true
	if is_instance_valid(fallen_player):
		fallen_player.match_over = true
	for bot in bots:
		if is_instance_valid(bot):
			bot.match_over = true
	for remote in remote_players.values():
		if is_instance_valid(remote):
			remote.match_over = true


func _collect_match_results() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if GameState.multiplayer_mode:
		for id in GameState.lobby_players:
			var record: Dictionary = GameState.lobby_players[id]
			if bool(record.get("spectator", false)):
				continue
			var car: CharacterBody3D
			if int(id) == 1:
				car = player if is_instance_valid(player) else fallen_player
			elif int(id) < 0 and GameState.room_host:
				var slot := bot_network_ids.find(int(id))
				if slot >= 0 and slot < bots.size():
					car = bots[slot]
					if not is_instance_valid(car):
						entries.append(_stored_bot_result(slot, str(record.get("name", "Bot")), id))
						continue
			else:
				car = remote_players.get(id) as CharacterBody3D
			entries.append(_result_entry(str(record.get("name", "Pemain")), car, id))
	else:
		var local_car := player if is_instance_valid(player) else fallen_player
		entries.append(_result_entry(GameState.player_name, local_car, 1))
		for index in bots.size():
			if is_instance_valid(bots[index]):
				entries.append(_result_entry(bot_names[index], bots[index], index))
			else:
				entries.append(_stored_bot_result(index, bot_names[index], index))
	entries.sort_custom(_leaderboard_before)
	return entries


func _result_entry(name: String, car: CharacterBody3D, id: Variant) -> Dictionary:
	if is_instance_valid(car):
		return {"id": id, "name": name, "k": car.kills, "d": car.deaths, "a": car.assists, "score": car.score}
	return {"id": id, "name": name, "k": 0, "d": 0, "a": 0, "score": 0}


func _stored_bot_result(index: int, name: String, id: Variant) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"k": bot_kills[index] if index < bot_kills.size() else 0,
		"d": bot_deaths[index] if index < bot_deaths.size() else 0,
		"a": bot_assists[index] if index < bot_assists.size() else 0,
		"score": bot_scores[index] if index < bot_scores.size() else 0
	}


func _show_match_results(entries: Array) -> void:
	if not is_instance_valid(results_overlay):
		return
	var lines := PackedStringArray(["#   PEMAIN                         K    D    A    POIN"])
	for index in mini(entries.size(), 8):
		var entry: Dictionary = entries[index]
		lines.append("%d. %s   K:%d D:%d A:%d   Poin:%d" % [index + 1, str(entry.get("name", "Pemain")), int(entry.get("k", 0)), int(entry.get("d", 0)), int(entry.get("a", 0)), int(entry.get("score", 0))])
	if entries.is_empty():
		lines.append("Belum ada statistik pertandingan.")
	results_label.text = "\n".join(lines)
	results_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


@rpc("authority", "call_remote", "reliable")
func _rpc_match_results(entries: Array) -> void:
	match_over = true
	_freeze_match_cars()
	_show_match_results(entries)


func _build_match_results(parent: Control) -> void:
	results_overlay = ColorRect.new()
	results_overlay.name = "Match results"
	results_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results_overlay.color = Color(0.015, 0.02, 0.03, 0.82)
	results_overlay.visible = false
	results_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(results_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	results_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202833")
	style.border_color = Color("f4bb3b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "MATCH SELESAI  •  HASIL PERTANDINGAN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f4bb3b"))
	layout.add_child(title)
	results_label = Label.new()
	results_label.add_theme_font_size_override("font_size", 15)
	results_label.add_theme_color_override("font_color", Color("e5ebf0"))
	layout.add_child(results_label)
	var menu_button := Button.new()
	menu_button.text = "KEMBALI KE MENU"
	menu_button.custom_minimum_size.y = 44
	menu_button.pressed.connect(_return_to_menu)
	layout.add_child(menu_button)

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
				bot_kills[slot] = attacker.kills
				bot_assists[slot] = attacker.assists
				bot_rage_progress[slot] = attacker.rage_progress


func _update_pickups(delta: float) -> void:
	for pickup in pickups:
		if is_instance_valid(pickup):
			var base_y: float = pickup.get_meta("base_y", 0.5)
			var phase: float = pickup.get_meta("phase", 0.0)
			pickup.position.y = base_y + sin(Time.get_ticks_msec() * 0.002 + phase) * 0.16
			pickup.rotation.y += delta * 0.9
	if GameState.multiplayer_mode and not multiplayer.is_server():
		return
	pickup_spawn_timer -= delta
	if pickup_spawn_timer <= 0.0 and pickups.size() < 3:
		_spawn_pickup()
		pickup_spawn_timer = randf_range(6.0, 9.0)


func _spawn_pickup() -> void:
	if GameState.multiplayer_mode and not multiplayer.is_server():
		return
	var angle := randf_range(0.0, TAU)
	var radius := sqrt(randf()) * 28.0
	var spawn_position := Vector3(sin(angle) * radius, 0.5, cos(angle) * radius)
	var pickup_id := next_pickup_id
	next_pickup_id += 1
	var ability: String = PICKUP_TYPES[randi() % PICKUP_TYPES.size()]
	var phase := randf_range(0.0, TAU)
	_create_pickup(pickup_id, ability, spawn_position, phase)
	_sync_pickups_to_peers()


func _sync_pickups_to_peers() -> void:
	if not GameState.multiplayer_mode or not multiplayer.is_server():
		return
	for peer_id in GameState.game_ready_peers:
		var sent_ids: Dictionary = pickup_sent_peers.get(peer_id, {})
		for pickup_id in pickup_by_id:
			if sent_ids.has(pickup_id):
				continue
			var pickup: Area3D = pickup_by_id[pickup_id]
			if not is_instance_valid(pickup):
				continue
			_rpc_spawn_pickup.rpc_id(int(peer_id), int(pickup_id), str(pickup.get_meta("ability")), Vector3(pickup.get_meta("spawn_position")), float(pickup.get_meta("phase")))
			sent_ids[pickup_id] = true
		pickup_sent_peers[peer_id] = sent_ids


@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_pickup(pickup_id: int, ability: String, spawn_position: Vector3, phase: float) -> void:
	_create_pickup(pickup_id, ability, spawn_position, phase)


func _create_pickup(pickup_id: int, ability: String, spawn_position: Vector3, phase: float) -> void:
	if pickup_by_id.has(pickup_id) and is_instance_valid(pickup_by_id[pickup_id]):
		return
	var pickup := Area3D.new()
	pickup.name = "Arena pickup %d" % pickup_id
	pickup.position = spawn_position
	pickup.collision_layer = 0
	pickup.collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 1.3
	shape.shape = sphere_shape
	shape.position.y = 0.5
	pickup.add_child(shape)
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
	pickup.set_meta("pickup_id", pickup_id)
	pickup.set_meta("ability", ability)
	pickup.set_meta("base_y", spawn_position.y)
	pickup.set_meta("spawn_position", spawn_position)
	pickup.set_meta("phase", phase)
	pickup.set_meta("claimed", false)
	pickup.body_entered.connect(_on_pickup_collected.bind(pickup_id))
	add_child(pickup)
	pickups.append(pickup)
	pickup_by_id[pickup_id] = pickup


func _on_pickup_collected(body: Node3D, pickup_id: int) -> void:
	if not is_instance_valid(body) or not pickup_by_id.has(pickup_id):
		return
	if GameState.multiplayer_mode and not multiplayer.is_server():
		if body == player:
			_rpc_request_pickup.rpc_id(1, pickup_id)
		return
	var pickup: Area3D = pickup_by_id[pickup_id]
	if not is_instance_valid(pickup) or bool(pickup.get_meta("claimed", false)):
		return
	pickup.set_meta("claimed", true)
	var ability := str(pickup.get_meta("ability", ""))
	if body.has_method("apply_pickup"):
		body.apply_pickup(ability)
		if GameState.multiplayer_mode and body.network_remote:
			var peer_id := int(body.get_meta("network_id", 0))
			if peer_id > 1:
				_rpc_apply_pickup.rpc_id(peer_id, ability)
	if body == player:
		var messages := {
			"blue_shield": "PERISAI BIRU  •  5 DETIK",
			"unlimited_nos": "NOS TAK TERBATAS  •  10 DETIK",
			"jump": "LOMPAT  •  3 CHARGE  (SPACE)"
		}
		_show_notification(messages[ability], Color("39bbfa") if ability != "jump" else Color("ffd83d"))
	_remove_pickup(pickup_id)
	if GameState.multiplayer_mode:
		for peer_id in GameState.game_ready_peers:
			_rpc_remove_pickup.rpc_id(int(peer_id), pickup_id)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_pickup(pickup_id: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not remote_players.has(peer_id) or not pickup_by_id.has(pickup_id):
		return
	var collector: CharacterBody3D = remote_players[peer_id]
	var pickup: Area3D = pickup_by_id[pickup_id]
	if not is_instance_valid(pickup) or bool(pickup.get_meta("claimed", false)) or collector.global_position.distance_to(pickup.global_position) > 3.5:
		return
	_on_pickup_collected(collector, pickup_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_apply_pickup(ability: String) -> void:
	if is_instance_valid(player):
		player.apply_pickup(ability)
	var messages := {
		"blue_shield": "PERISAI BIRU  •  5 DETIK",
		"unlimited_nos": "NOS TAK TERBATAS  •  10 DETIK",
		"jump": "LOMPAT  •  3 CHARGE  (SPACE)"
	}
	if messages.has(ability):
		_show_notification(messages[ability], Color("ffd83d") if ability == "jump" else Color("39bbfa"))


func _remove_pickup(pickup_id: int) -> void:
	if not pickup_by_id.has(pickup_id):
		return
	var pickup: Area3D = pickup_by_id[pickup_id]
	pickup_by_id.erase(pickup_id)
	pickups.erase(pickup)
	for peer_id in pickup_sent_peers:
		var sent_ids: Dictionary = pickup_sent_peers[peer_id]
		sent_ids.erase(pickup_id)
	if is_instance_valid(pickup):
		pickup.queue_free()


@rpc("authority", "call_remote", "reliable")
func _rpc_remove_pickup(pickup_id: int) -> void:
	_remove_pickup(pickup_id)

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
