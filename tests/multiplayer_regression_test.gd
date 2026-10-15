extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := root.get_node("GameState")
	state.player_name = "Host"
	assert(state.host_room() == OK)
	state.lobby_players[2] = {"name": "Client", "car": 0, "team": "Oranye", "ready": true, "spectator": false, "bot": false}
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	var remote: CharacterBody3D = game.remote_players[2]
	remote.kills = 3
	remote.score = 90
	remote.deaths = 1
	var stale_state := {"id": 2, "position": remote.global_position, "rotation": 0.0, "speed": 0.0, "health": 100.0, "score": 0, "kills": 0, "deaths": 0, "assists": 0}
	game._relay_network_state(stale_state)
	assert(remote.kills == 3 and remote.score == 90 and remote.deaths == 1)
	assert(stale_state["kills"] == 3 and stale_state["score"] == 90)
	remote.global_position = game.player.global_position + Vector3(3.0, 0.0, 0.0)
	var health_before: float = game.player.health
	game._server_apply_contact(remote, 1, Vector3(20.0, 0.0, 0.0), 1.0)
	assert(game.player.health < health_before)
	assert(game.player.recent_attackers.has(remote.get_instance_id()))
	game._apply_network_state({"id": 2, "position": remote.global_position, "health": 0.0, "is_defeated": true})
	assert(remote.get_collision_layer_value(1) == false and remote.get_collision_mask_value(1) == false)
	game._apply_network_state({"id": 2, "position": remote.global_position, "health": 100.0, "is_defeated": false})
	assert(remote.get_collision_layer_value(1) and remote.get_collision_mask_value(1))
	game.queue_free()
	state.close_room()
	print("Multiplayer score authority and player damage passed")
	quit()
