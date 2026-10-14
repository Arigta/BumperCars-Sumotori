extends Node

signal lobby_updated
signal match_started
signal network_error(message: String)

const CAR_NAMES := ["SportsCar", "SportsCar2", "NormalCar1", "NormalCar2", "SUV", "Taxi", "Cop"]
var selected_car := 0
var player_name := "Pemain"
var multiplayer_mode := false
var room_mode := "Deathmatch"
var room_minutes := 5
var player_team := "Biru"
var player_ready := false
var room_host := false
var room_name := ""
var match_active := false
var match_time_remaining := 0.0
var lobby_players: Dictionary = {}
var next_bot_id := -1
var game_ready_peers: Dictionary = {}
var peer: ENetMultiplayerPeer
var discovery := PacketPeerUDP.new()
var discovery_server := UDPServer.new()
var discovery_timer := 0.0
var discovery_results: Dictionary = {}


func _process(delta: float) -> void:
	discovery_timer -= delta
	if discovery_timer <= 0.0:
		discovery_timer = 1.0
		_broadcast_room()
		for address in discovery_results.keys():
			if Time.get_ticks_msec() - int(discovery_results[address].get("_seen_at", 0)) > 3500:
				discovery_results.erase(address)
	_poll_discovery()


func selected_name() -> String:
	return CAR_NAMES[selected_car]


func selected_asset_path() -> String:
	return "res://assets/cars/%s.res" % selected_name()


func host_room(port: int = 27890) -> Error:
	close_room()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 7)
	if error != OK:
		network_error.emit("Gagal membuat room di port %d." % port)
		return error
	multiplayer.multiplayer_peer = peer
	room_host = true
	multiplayer_mode = true
	match_active = false
	match_time_remaining = room_minutes * 60.0
	lobby_players.clear()
	game_ready_peers.clear()
	next_bot_id = -1
	lobby_players[1] = _local_player_record()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_start_discovery(port)
	lobby_updated.emit()
	return OK


func join_room(address: String, port: int = 27890) -> Error:
	close_room()
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port)
	if error != OK:
		network_error.emit("Tidak dapat terhubung ke %s." % address)
		return error
	multiplayer.multiplayer_peer = peer
	room_host = false
	multiplayer_mode = true
	match_active = false
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	return OK


func close_room() -> void:
	var peer_connected_callback := Callable(self, "_on_peer_connected")
	var peer_disconnected_callback := Callable(self, "_on_peer_disconnected")
	var connected_callback := Callable(self, "_on_connected")
	var failed_callback := Callable(self, "_on_connection_failed")
	var disconnected_callback := Callable(self, "_on_server_disconnected")
	if multiplayer.peer_connected.is_connected(peer_connected_callback):
		multiplayer.peer_connected.disconnect(peer_connected_callback)
	if multiplayer.peer_disconnected.is_connected(peer_disconnected_callback):
		multiplayer.peer_disconnected.disconnect(peer_disconnected_callback)
	if multiplayer.connected_to_server.is_connected(connected_callback):
		multiplayer.connected_to_server.disconnect(connected_callback)
	if multiplayer.connection_failed.is_connected(failed_callback):
		multiplayer.connection_failed.disconnect(failed_callback)
	if multiplayer.server_disconnected.is_connected(disconnected_callback):
		multiplayer.server_disconnected.disconnect(disconnected_callback)
	if discovery.is_bound():
		discovery.close()
	if discovery_server.is_listening():
		discovery_server.stop()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	peer = null
	room_host = false
	multiplayer_mode = false
	match_active = false
	match_time_remaining = 0.0
	lobby_players.clear()
	game_ready_peers.clear()
	next_bot_id = -1


func _local_player_record() -> Dictionary:
	return {"name": player_name, "car": selected_car, "team": player_team, "ready": player_ready, "spectator": player_team == "Spectator"}


func _on_peer_connected(id: int) -> void:
	if not room_host:
		return
	# The full roster is sent after the new peer registers its car and name.
	pass


func _on_connected() -> void:
	_register_player.rpc_id(1, _local_player_record())


func _on_connection_failed() -> void:
	network_error.emit("Koneksi room gagal.")
	close_room()


func _on_server_disconnected() -> void:
	network_error.emit("Host terputus.")
	close_room()


func _on_peer_disconnected(id: int) -> void:
	lobby_players.erase(id)
	game_ready_peers.erase(id)
	_broadcast_roster()


func announce_game_ready() -> void:
	if multiplayer_mode and not room_host:
		_rpc_game_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_game_ready() -> void:
	if room_host:
		var id := multiplayer.get_remote_sender_id()
		if lobby_players.has(id):
			game_ready_peers[id] = true


@rpc("any_peer", "reliable")
func _register_player(record: Dictionary) -> void:
	if not room_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if lobby_players.size() >= 8:
		peer.disconnect_peer(id)
		return
	var clean := record.duplicate()
	clean["name"] = str(clean.get("name", "Pemain")).left(20)
	clean["car"] = clampi(int(clean.get("car", 0)), 0, CAR_NAMES.size() - 1)
	clean["team"] = str(clean.get("team", "Biru"))
	if room_mode == "Tim 4 vs 4" and clean["team"] in ["Biru", "Oranye"] and _team_count(clean["team"]) >= 4:
		clean["team"] = "Spectator"
	clean["spectator"] = clean["team"] == "Spectator"
	clean["ready"] = false
	clean["bot"] = false
	lobby_players[id] = clean
	_broadcast_roster()


@rpc("any_peer", "reliable")
func _update_local_record(record: Dictionary) -> void:
	if room_host:
		var id := multiplayer.get_remote_sender_id()
		if lobby_players.has(id):
			var current: Dictionary = lobby_players[id]
			var requested_team := str(record.get("team", current.get("team", "Biru")))
			if room_mode == "Tim 4 vs 4" and requested_team in ["Biru", "Oranye"] and _team_count(requested_team, id) >= 4:
				requested_team = str(current.get("team", "Spectator"))
			current.merge(record, true)
			current["team"] = requested_team
			current["spectator"] = requested_team == "Spectator"
			current["bot"] = false
			lobby_players[id] = current
			_broadcast_roster()
	else:
		_rpc_update_local_record.rpc_id(1, _local_player_record())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_update_local_record(record: Dictionary) -> void:
	_update_local_record(record)


@rpc("authority", "call_remote", "reliable")
func _rpc_send_roster(roster: Dictionary, settings: Dictionary) -> void:
	lobby_players = roster.duplicate(true)
	room_name = str(settings.get("name", "Room LAN"))
	room_mode = str(settings.get("mode", "Deathmatch"))
	room_minutes = int(settings.get("minutes", 5))
	match_active = bool(settings.get("playing", false))
	match_time_remaining = float(settings.get("time_left", room_minutes * 60.0))
	if lobby_players.has(multiplayer.get_unique_id()):
		var own_record: Dictionary = lobby_players[multiplayer.get_unique_id()]
		player_team = str(own_record.get("team", "Biru"))
	lobby_updated.emit()
	if match_active and lobby_players.has(multiplayer.get_unique_id()):
		match_started.emit()


func update_lobby_record() -> void:
	if not multiplayer_mode:
		return
	if room_host:
		lobby_players[1] = _local_player_record()
		_broadcast_roster()
	else:
		_rpc_update_local_record.rpc_id(1, _local_player_record())


func _broadcast_roster() -> void:
	lobby_players[1] = _local_player_record()
	_rpc_send_roster.rpc(lobby_players, _room_settings())
	lobby_updated.emit()


func _room_settings() -> Dictionary:
	return {"name": room_name, "mode": room_mode, "minutes": room_minutes, "playing": match_active, "time_left": match_time_remaining}


func _team_count(team: String, except_id: int = 0) -> int:
	var count := 0
	for id in lobby_players:
		if int(id) != except_id and str(lobby_players[id].get("team", "")) == team:
			count += 1
	return count


func add_bot() -> void:
	if not room_host or match_active or lobby_players.size() >= 8:
		return
	var id := next_bot_id
	next_bot_id -= 1
	var team := "Biru"
	if room_mode == "Tim 4 vs 4":
		team = "Biru" if _team_count("Biru") <= _team_count("Oranye") else "Oranye"
		if _team_count(team) >= 4:
			team = "Oranye" if team == "Biru" else "Biru"
	var number := -id
	lobby_players[id] = {"name": "Bot %d" % number, "car": randi() % CAR_NAMES.size(), "team": team, "ready": true, "spectator": false, "bot": true}
	_broadcast_roster()


func remove_bot(id: int) -> void:
	if room_host and not match_active and id < 0 and lobby_players.has(id):
		lobby_players.erase(id)
		_broadcast_roster()


func start_room_match() -> void:
	if not room_host or match_active:
		return
	var ready_count := 0
	for record in lobby_players.values():
		if bool(record.get("ready", false)):
			ready_count += 1
	if lobby_players.size() < 2 or ready_count < lobby_players.size():
		return
	match_active = true
	match_time_remaining = room_minutes * 60.0
	_rpc_begin_match.rpc()
	match_started.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_begin_match() -> void:
	match_active = true
	match_started.emit()


func kick_player(id: int) -> void:
	if room_host and id > 1 and lobby_players.has(id) and peer != null:
		peer.disconnect_peer(id)


func _start_discovery(port: int) -> void:
	if discovery.is_bound():
		discovery.close()
	if discovery_server.is_listening():
		discovery_server.stop()
	var err := discovery_server.listen(27891)
	if err == OK:
		discovery.bind(0)
		discovery.set_broadcast_enabled(true)
		discovery.set_dest_address("255.255.255.255", 27891)


func scan_rooms() -> void:
	if not discovery_server.is_listening():
		discovery_server.listen(27891)
	if not discovery.is_bound():
		discovery.bind(0)
	discovery.set_broadcast_enabled(true)
	discovery.set_dest_address("255.255.255.255", 27891)
	discovery_results.clear()


func _broadcast_room() -> void:
	if room_host and peer != null:
		var packet := JSON.stringify({"room": room_name, "mode": room_mode, "minutes": room_minutes, "players": lobby_players.size(), "port": 27890, "status": "Playing" if match_active else "Waiting"})
		discovery.put_packet(packet.to_utf8_buffer())


func _poll_discovery() -> void:
	discovery_server.poll()
	while discovery_server.is_connection_available():
		var connection := discovery_server.take_connection()
		while connection.get_available_packet_count() > 0:
			var packet: Variant = JSON.parse_string(connection.get_packet().get_string_from_utf8())
			if packet is Dictionary:
				packet["address"] = connection.get_packet_ip()
				packet["_seen_at"] = Time.get_ticks_msec()
				discovery_results[packet["address"]] = packet
