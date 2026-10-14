extends Node

var saw_join := false
var saw_ready := false
var saw_kick := false
var saw_disconnect := false
var test_role := ""
var active_client_game: Node3D
var bot_initial_position := Vector3.ZERO


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var role := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ""
	test_role = role
	print("LAN test role: ", role)
	if role == "host":
		GameState.lobby_updated.connect(_on_lobby_updated)
		GameState.room_name = "LAN Test"
		GameState.player_name = "Host"
		assert(GameState.host_room() == OK)
		GameState.add_bot()
		GameState.match_active = true
		GameState.match_time_remaining = 120.0
		var host_game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
		add_child(host_game)
		await get_tree().create_timer(5.0).timeout
		assert(saw_join)
		assert(host_game.bots.size() == 1)
		host_game.queue_free()
		GameState.close_room()
		print("LAN host accepted late join")
		get_tree().quit()
	elif role == "client":
		await get_tree().create_timer(0.3).timeout
		GameState.player_name = "Late Player"
		GameState.match_started.connect(_on_match_started)
		assert(GameState.join_room("127.0.0.1") == OK)
		await get_tree().create_timer(3.0).timeout
		assert(GameState.match_active)
		assert(GameState.lobby_players.has(multiplayer.get_unique_id()))
		assert(GameState.lobby_players.has(-1))
		assert(GameState.match_time_remaining > 0.0 and GameState.match_time_remaining <= 120.0)
		assert(is_instance_valid(active_client_game))
		assert(active_client_game.remote_players.has(-1))
		assert(active_client_game.remote_players[-1].is_bot)
		assert(active_client_game.remote_players[-1].global_position.distance_to(bot_initial_position) > 0.1)
		active_client_game.queue_free()
		GameState.close_room()
		print("LAN client joined a playing room")
		get_tree().quit()
	elif role == "host_waiting":
		GameState.lobby_updated.connect(_on_lobby_updated)
		GameState.room_name = "Waiting Test"
		assert(GameState.host_room() == OK)
		await get_tree().create_timer(4.0).timeout
		assert(saw_join and saw_ready and saw_kick)
		GameState.close_room()
		print("LAN host received ready state and kicked client")
		get_tree().quit()
	elif role == "client_waiting":
		GameState.lobby_updated.connect(_on_lobby_updated)
		GameState.network_error.connect(func(_message: String) -> void: saw_disconnect = true)
		await get_tree().create_timer(0.3).timeout
		assert(GameState.join_room("127.0.0.1") == OK)
		await get_tree().create_timer(3.0).timeout
		assert(saw_join and saw_disconnect)
		print("LAN waiting client received disconnect after kick")
		get_tree().quit()
	else:
		push_error("Pass host or client as a user argument")
		get_tree().quit(1)


func _on_match_started() -> void:
	assert(GameState.match_active)
	if test_role == "client" and not is_instance_valid(active_client_game):
		call_deferred("_spawn_client_game")


func _spawn_client_game() -> void:
	if is_instance_valid(active_client_game):
		return
	active_client_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(active_client_game)
	await get_tree().process_frame
	bot_initial_position = active_client_game.remote_players[-1].global_position


func _on_lobby_updated() -> void:
	if (test_role in ["host", "client"] and GameState.lobby_players.size() == 3) or (test_role in ["host_waiting", "client_waiting"] and GameState.lobby_players.size() == 2):
		saw_join = true
	if test_role == "host_waiting":
		for id in GameState.lobby_players:
			if int(id) != 1 and bool(GameState.lobby_players[id].get("ready", false)) and not saw_ready:
				saw_ready = true
				call_deferred("_kick_waiting_player", int(id))
		if saw_join and GameState.lobby_players.size() == 1:
			saw_kick = true
	elif test_role == "client_waiting" and GameState.lobby_players.has(multiplayer.get_unique_id()) and not GameState.player_ready:
		GameState.player_ready = true
		GameState.update_lobby_record()


func _kick_waiting_player(id: int) -> void:
	GameState.kick_player(id)
