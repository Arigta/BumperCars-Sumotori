extends Control

const GOLD := Color("f4bb3b")
const TEXT := Color("e5ebf0")
const MUTED := Color("9aa9b7")

var content: VBoxContainer
var feedback: Label
var name_input: LineEdit
var room_name_input: LineEdit
var address_input: LineEdit
var mode_option: OptionButton
var time_option: OptionButton
var team_option: OptionButton
var room_list: VBoxContainer
var roster_grid: GridContainer
var ready_button: Button
var start_button: Button
var add_bot_button: Button
var lobby_status: Label
var lobby_title: Label
var preview_pivot: Node3D
var screen := ""
var room_refresh_timer := 0.0


func _ready() -> void:
	_build_frame()
	GameState.lobby_updated.connect(_refresh_lobby)
	GameState.match_started.connect(_start_match)
	GameState.network_error.connect(_show_error)
	_show_screen("main")


func _process(delta: float) -> void:
	if is_instance_valid(preview_pivot):
		preview_pivot.rotate_y(delta * 0.38)
	if screen == "join":
		room_refresh_timer -= delta
		if room_refresh_timer <= 0.0:
			room_refresh_timer = 1.0
			_refresh_rooms()


func _build_frame() -> void:
	var background := ColorRect.new()
	background.color = Color("131b25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	center.add_child(margin)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(810, 560)
	margin.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var padding := MarginContainer.new()
	for side in ["left", "right"]:
		padding.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(padding)
	content = VBoxContainer.new()
	content.custom_minimum_size.x = 700
	content.add_theme_constant_override("separation", 14)
	padding.add_child(content)


func _show_screen(next_screen: String) -> void:
	screen = next_screen
	preview_pivot = null
	team_option = null
	add_bot_button = null
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	content.add_child(_label("BUMPER CARS  /  SUMOTORI", 32, GOLD))
	match screen:
		"main": _build_main()
		"single": _build_single()
		"multiplayer": _build_multiplayer()
		"create": _build_create()
		"join": _build_join()
		"lobby": _build_lobby()
	feedback = _label("", 14, Color("ff9b85"))
	content.add_child(feedback)


func _build_main() -> void:
	content.add_child(_label("Masukkan nama, lalu pilih mode permainan.", 17, MUTED))
	content.add_child(_label("NAMA PEMAIN", 15, GOLD))
	name_input = LineEdit.new()
	name_input.text = GameState.player_name
	name_input.max_length = 20
	name_input.placeholder_text = "Nama pemain"
	content.add_child(name_input)
	_add_nav_button("SINGLE PLAYER", "single")
	_add_nav_button("MULTIPLAYER LAN", "multiplayer")
	content.add_child(_label("WASD bergerak  •  Shift drift  •  Klik kanan NOS  •  Space lompat", 13, MUTED))


func _build_single() -> void:
	content.add_child(_label("SINGLE PLAYER  /  PILIH MOBIL", 22, TEXT))
	content.add_child(_label("Pilih mobil dan lihat modelnya sebelum masuk arena.", 15, MUTED))
	_build_car_picker()
	var play := _button("MAIN SEKARANG", 20)
	play.pressed.connect(func() -> void:
		GameState.close_room()
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	)
	content.add_child(play)
	_add_nav_button("KEMBALI", "main")


func _build_multiplayer() -> void:
	content.add_child(_label("MULTIPLAYER LAN", 24, TEXT))
	content.add_child(_label("Buat room baru atau gabung ke room pada jaringan yang sama.", 15, MUTED))
	_add_nav_button("BUAT ROOM", "create")
	_add_nav_button("JOIN ROOM", "join")
	_add_nav_button("KEMBALI", "main")


func _build_create() -> void:
	content.add_child(_label("BUAT ROOM", 24, TEXT))
	content.add_child(_label("NAMA ROOM", 14, GOLD))
	room_name_input = LineEdit.new()
	room_name_input.text = "%s's Room" % GameState.player_name
	content.add_child(room_name_input)
	content.add_child(_label("MODE", 14, GOLD))
	mode_option = OptionButton.new()
	mode_option.add_item("Deathmatch")
	mode_option.add_item("Tim 4 vs 4")
	content.add_child(mode_option)
	content.add_child(_label("DURASI", 14, GOLD))
	time_option = OptionButton.new()
	for minutes in [5, 10, 15]:
		time_option.add_item("%d menit" % minutes)
	content.add_child(time_option)
	var create := _button("BUAT ROOM", 19)
	create.pressed.connect(_host_room)
	content.add_child(create)
	_add_nav_button("KEMBALI", "multiplayer")


func _build_join() -> void:
	GameState.scan_rooms()
	content.add_child(_label("JOIN ROOM", 24, TEXT))
	content.add_child(_label("ROOM TERSEDIA DI LAN", 14, GOLD))
	room_list = VBoxContainer.new()
	room_list.add_theme_constant_override("separation", 8)
	content.add_child(room_list)
	_refresh_rooms()
	content.add_child(_label("Jika room tidak muncul, masukkan IP host:", 14, MUTED))
	address_input = LineEdit.new()
	address_input.placeholder_text = "Contoh: 192.168.1.10"
	content.add_child(address_input)
	var join := _button("GABUNG DENGAN IP", 17)
	join.pressed.connect(func() -> void: _join_address(address_input.text))
	content.add_child(join)
	_add_nav_button("KEMBALI", "multiplayer")


func _build_lobby() -> void:
	lobby_title = _label("LOBBY  /  %s" % GameState.room_name, 24, TEXT)
	content.add_child(lobby_title)
	lobby_status = _label("", 15, MUTED)
	content.add_child(lobby_status)
	content.add_child(_label("PILIH MOBIL", 14, GOLD))
	_build_car_picker()
	if GameState.room_mode == "Tim 4 vs 4":
		content.add_child(_label("TIM", 14, GOLD))
		team_option = OptionButton.new()
		for team in ["Biru", "Oranye", "Spectator"]:
			team_option.add_item(team)
		team_option.select(maxi(0, ["Biru", "Oranye", "Spectator"].find(GameState.player_team)))
		team_option.item_selected.connect(_team_changed)
		content.add_child(team_option)
	content.add_child(_label("PEMAIN DALAM ROOM", 14, GOLD))
	roster_grid = GridContainer.new()
	roster_grid.columns = 5
	roster_grid.add_theme_constant_override("h_separation", 22)
	roster_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(roster_grid)
	if GameState.room_host:
		add_bot_button = _button("TAMBAH BOT", 17)
		add_bot_button.pressed.connect(GameState.add_bot)
		content.add_child(add_bot_button)
	ready_button = _button("SIAP", 18)
	ready_button.pressed.connect(_toggle_ready)
	content.add_child(ready_button)
	start_button = _button("MULAI MATCH", 20)
	start_button.pressed.connect(GameState.start_room_match)
	content.add_child(start_button)
	var leave := _button("KELUAR ROOM", 16)
	leave.pressed.connect(func() -> void:
		GameState.close_room()
		_show_screen("multiplayer")
	)
	content.add_child(leave)
	_refresh_lobby()


func _build_car_picker() -> void:
	var picker := HBoxContainer.new()
	picker.add_theme_constant_override("separation", 16)
	content.add_child(picker)
	var preview := SubViewportContainer.new()
	preview.custom_minimum_size = Vector2(420, 255)
	preview.stretch = true
	picker.add_child(preview)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(420, 255)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var environment_resource := Environment.new()
	environment_resource.background_mode = Environment.BG_COLOR
	environment_resource.background_color = Color("223348")
	environment.environment = environment_resource
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	world.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(3.7, 2.8, 6.5)
	camera.current = true
	world.add_child(camera)
	camera.look_at(Vector3(0, 0.7, 0))
	preview_pivot = Node3D.new()
	world.add_child(preview_pivot)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 10)
	picker.add_child(controls)
	controls.add_child(_label("MODEL MOBIL", 14, GOLD))
	var car_option := OptionButton.new()
	for car_name in GameState.CAR_NAMES:
		car_option.add_item(car_name)
	car_option.select(GameState.selected_car)
	controls.add_child(car_option)
	car_option.item_selected.connect(func(index: int) -> void:
		GameState.selected_car = index
		_update_car_preview()
		if GameState.multiplayer_mode:
			GameState.update_lobby_record()
	)
	controls.add_child(_label("Model mobil berputar untuk pratinjau.", 13, MUTED))
	_update_car_preview()


func _update_car_preview() -> void:
	if not is_instance_valid(preview_pivot):
		return
	for child in preview_pivot.get_children():
		preview_pivot.remove_child(child)
		child.queue_free()
	var resource := ResourceLoader.load(GameState.selected_asset_path())
	var model: Node3D
	if resource is PackedScene:
		model = resource.instantiate() as Node3D
	elif resource is Mesh:
		var instance := MeshInstance3D.new()
		instance.mesh = resource
		model = instance
	if model != null:
		model.rotation.y = PI
		preview_pivot.add_child(model)


func _refresh_rooms() -> void:
	if not is_instance_valid(room_list):
		return
	for child in room_list.get_children():
		room_list.remove_child(child)
		child.queue_free()
	for address in GameState.discovery_results:
		var room: Dictionary = GameState.discovery_results[address]
		var row := _button("%s  |  %s  |  %s  |  %s/8  |  %s" % [room.get("room", "Room"), room.get("mode", "Deathmatch"), room.get("status", "Waiting"), room.get("players", 1), address], 14)
		row.disabled = int(room.get("players", 8)) >= 8
		var target := str(address)
		row.pressed.connect(func() -> void: _join_address(target))
		room_list.add_child(row)
	if room_list.get_child_count() == 0:
		room_list.add_child(_label("Belum ada room terdeteksi.", 14, MUTED))


func _refresh_lobby() -> void:
	if screen != "lobby" or not is_instance_valid(roster_grid):
		return
	if (GameState.room_mode == "Tim 4 vs 4") != is_instance_valid(team_option):
		_show_screen("lobby")
		return
	lobby_title.text = "LOBBY  /  %s" % GameState.room_name
	if is_instance_valid(team_option):
		team_option.select(maxi(0, ["Biru", "Oranye", "Spectator"].find(GameState.player_team)))
	lobby_status.text = "%s  |  %s  |  %d menit  |  %d/8 pemain" % ["Playing" if GameState.match_active else "Waiting", GameState.room_mode, GameState.room_minutes, GameState.lobby_players.size()]
	for child in roster_grid.get_children():
		roster_grid.remove_child(child)
		child.queue_free()
	for heading in ["PEMAIN", "MOBIL", "TIM", "STATUS", "AKSI"]:
		roster_grid.add_child(_label(heading, 13, GOLD))
	for id in GameState.lobby_players:
		var record: Dictionary = GameState.lobby_players[id]
		var car_index := clampi(int(record.get("car", 0)), 0, GameState.CAR_NAMES.size() - 1)
		var is_bot := bool(record.get("bot", false))
		var state := "PLAYING" if GameState.match_active else ("BOT SIAP" if is_bot else ("SIAP" if bool(record.get("ready", false)) else "MENUNGGU"))
		for value in [str(record.get("name", "Pemain")), GameState.CAR_NAMES[car_index], str(record.get("team", "Biru")), state]:
			roster_grid.add_child(_label(value, 14, TEXT))
		if GameState.room_host and int(id) != 1:
			var kick := _button("HAPUS" if is_bot else "KICK", 13)
			kick.custom_minimum_size.y = 30
			if is_bot:
				kick.pressed.connect(GameState.remove_bot.bind(int(id)))
			else:
				kick.pressed.connect(GameState.kick_player.bind(int(id)))
			roster_grid.add_child(kick)
		else:
			roster_grid.add_child(_label("—", 14, MUTED))
	ready_button.visible = not GameState.match_active
	if is_instance_valid(add_bot_button):
		add_bot_button.disabled = GameState.lobby_players.size() >= 8
	ready_button.text = "BATAL SIAP" if GameState.player_ready else "SIAP"
	start_button.visible = GameState.room_host and not GameState.match_active
	start_button.disabled = not _all_ready()


func _all_ready() -> bool:
	if GameState.lobby_players.size() < 2:
		return false
	for record in GameState.lobby_players.values():
		if not bool(record.get("ready", false)):
			return false
	return true


func _host_room() -> void:
	GameState.room_name = room_name_input.text.strip_edges()
	if GameState.room_name.is_empty():
		GameState.room_name = "%s's Room" % GameState.player_name
	GameState.room_mode = "Tim 4 vs 4" if mode_option.selected == 1 else "Deathmatch"
	GameState.room_minutes = [5, 10, 15][time_option.selected]
	GameState.player_team = "Biru"
	GameState.player_ready = false
	if GameState.host_room() == OK:
		_show_screen("lobby")


func _join_address(address: String) -> void:
	if address.strip_edges().is_empty():
		_show_error("Masukkan alamat IP host.")
		return
	GameState.player_ready = false
	GameState.player_team = "Biru"
	if GameState.join_room(address) == OK:
		_show_screen("lobby")


func _team_changed(index: int) -> void:
	GameState.player_team = ["Biru", "Oranye", "Spectator"][index]
	GameState.update_lobby_record()


func _toggle_ready() -> void:
	GameState.player_ready = not GameState.player_ready
	GameState.update_lobby_record()
	_refresh_lobby()


func _start_match() -> void:
	if screen == "lobby":
		get_tree().change_scene_to_file("res://scenes/game.tscn")


func _show_error(message: String) -> void:
	if is_instance_valid(feedback):
		feedback.text = message
	if screen == "lobby" and not GameState.room_host:
		call_deferred("_return_after_disconnect", message)


func _return_after_disconnect(message: String) -> void:
	if not GameState.multiplayer_mode and screen == "lobby":
		_show_screen("join")
		feedback.text = message


func _add_nav_button(title: String, target: String) -> void:
	var button := _button(title, 18)
	button.pressed.connect(func() -> void:
		if screen == "main":
			GameState.player_name = name_input.text.strip_edges().left(20)
			if GameState.player_name.is_empty():
				GameState.player_name = "Pemain"
		_show_screen(target)
	)
	content.add_child(button)


func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String, size: int) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 46
	button.add_theme_font_size_override("font_size", size)
	return button
