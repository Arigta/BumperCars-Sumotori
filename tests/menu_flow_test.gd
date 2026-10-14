extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	assert(menu.screen == "main")
	assert(menu.name_input != null)
	var panel: PanelContainer = menu.get_child(1).get_child(0).get_child(0)
	assert(panel.size.y >= 560.0)
	assert(menu.content.size.y > 100.0)
	menu.name_input.text = "Test Driver"
	menu._show_screen("single")
	await get_tree().process_frame
	assert(menu.preview_pivot.get_child_count() == 1)
	menu._show_screen("main")
	menu.name_input.text = "Test Driver"
	var nav: Button = menu.content.get_child(5)
	nav.pressed.emit()
	assert(menu.screen == "multiplayer")
	assert(GameState.player_name == "Test Driver")
	menu._show_screen("create")
	await get_tree().process_frame
	menu._host_room()
	await get_tree().process_frame
	assert(menu.screen == "lobby")
	assert(menu.roster_grid.get_child_count() == 10)
	assert(menu.start_button.disabled)
	assert(not GameState.match_active)
	menu._toggle_ready()
	assert(GameState.player_ready)
	assert(menu.ready_button.text == "BATAL SIAP")
	GameState.add_bot()
	assert(GameState.lobby_players.has(-1))
	assert(bool(GameState.lobby_players[-1].get("bot", false)))
	assert(GameState.lobby_players[-1]["ready"])
	assert(not menu.start_button.disabled)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	assert(game.bots.size() == 1)
	assert(game.bot_network_ids[0] == -1)
	assert(game.bots[0].display_name == "Bot 1")
	assert(game.leaderboard_panel.size.x <= 242.0)
	assert(game.leaderboard_panel.size.y <= 206.0)
	game.player.kills = 2
	game.bots[0].kills = 3
	game._update_leaderboard()
	assert(game.leaderboard_cells[1].text == "Bot 1")
	assert(game.leaderboard_cells[6].text == GameState.player_name)
	game._player_fell()
	game._update_leaderboard()
	assert(game.leaderboard_cells[6].text == GameState.player_name)
	game.bot_kills[0] = game.bots[0].kills
	game.bots[0].free()
	game._update_leaderboard()
	assert(game.leaderboard_cells[1].text == "Bot 1")
	game.queue_free()
	GameState.remove_bot(-1)
	assert(not GameState.lobby_players.has(-1))
	assert(menu.start_button.disabled)
	GameState.room_mode = "Tim 4 vs 4"
	for _index in 7:
		GameState.add_bot()
	assert(GameState.lobby_players.size() == 8)
	assert(GameState._team_count("Biru") == 4)
	assert(GameState._team_count("Oranye") == 4)
	assert(menu.add_bot_button.disabled)
	GameState.add_bot()
	assert(GameState.lobby_players.size() == 8)
	GameState.match_started.disconnect(menu._start_match)
	GameState.start_room_match()
	assert(GameState.match_active)
	GameState.close_room()
	menu.queue_free()
	print("Menu, bot lobby controls, and host bot spawn passed")
	get_tree().quit()
