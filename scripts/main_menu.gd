extends Control

var root_box: VBoxContainer
var name_input: LineEdit
var room_name_input: LineEdit
var address_input: LineEdit
var mode_option: OptionButton
var time_option: OptionButton
var team_option: OptionButton
var status_label: Label
var roster_box: VBoxContainer
var room_list: VBoxContainer
var menu_car_option: OptionButton
var ready_button: Button
var start_button: Button
var chosen_room := ""


func _ready() -> void:
	_build_ui()
	GameState.lobby_updated.connect(_refresh_roster)
	GameState.match_started.connect(_start_match)
	GameState.network_error.connect(_show_error)


func _process(_delta: float) -> void:
	if room_list and room_list.visible:
		_refresh_rooms()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("171b22")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(650, 580)
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650, 560)
	panel.add_child(scroll)
	root_box = VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 14)
	root_box.custom_minimum_size.x = 600
	scroll.add_child(root_box)
	var title := _label("BUMPER CARS\nSUMOTORI", 38, Color("f4bb3b"))
	root_box.add_child(title)
	root_box.add_child(_label("Deathmatch • Arena Colosseum", 17, Color("d2d7dc")))
	name_input = LineEdit.new()
	name_input.placeholder_text = "Nama pemain"
	name_input.text = GameState.player_name
	root_box.add_child(name_input)
	menu_car_option = OptionButton.new()
	for car_name in GameState.CAR_NAMES:
		menu_car_option.add_item(car_name)
	menu_car_option.selected = GameState.selected_car
	menu_car_option.item_selected.connect(func(index: int) -> void: GameState.selected_car = index)
	root_box.add_child(menu_car_option)
	var single := _button("MAIN SINGLE PLAYER", 21)
	single.pressed.connect(_start_single)
	root_box.add_child(single)
	var lan := _button("MULTIPLAYER LAN", 21)
	lan.pressed.connect(_show_lan)
	root_box.add_child(lan)
	root_box.add_child(_label("WASD bergerak • Shift drift • Klik kanan NOS • Space lompat", 14, Color("9aa5af")))
	_build_lan_controls()
	_build_waiting_room()


func _build_lan_controls() -> void:
	var section := VBoxContainer.new()
	section.name = "LanPanel"
	section.add_theme_constant_override("separation", 10)
	root_box.add_child(section)
	section.add_child(_label("ROOM MULTIPLAYER", 23, Color("f4bb3b")))
	room_name_input = LineEdit.new()
	room_name_input.placeholder_text = "Nama room"
	room_name_input.text = "%s's Room" % GameState.player_name
	section.add_child(room_name_input)
	mode_option = OptionButton.new()
	mode_option.add_item("Deathmatch")
	mode_option.add_item("Tim 4 vs 4")
	section.add_child(mode_option)
	time_option = OptionButton.new()
	for minutes in [5, 10, 15]:
		time_option.add_item("%d menit" % minutes)
	section.add_child(time_option)
	var host := _button("BUAT ROOM", 18)
	host.pressed.connect(_host_room)
	section.add_child(host)
	address_input = LineEdit.new()
	address_input.placeholder_text = "IP host (contoh 192.168.1.10)"
	section.add_child(address_input)
	var join := _button("GABUNG DENGAN IP", 18)
	join.pressed.connect(_join_address)
	section.add_child(join)
	section.add_child(_label("ROOM TERSEDIA DI JARINGAN", 16, Color("d2d7dc")))
	room_list = VBoxContainer.new()
	section.add_child(room_list)
	section.visible = false


func _build_waiting_room() -> void:
	var waiting := VBoxContainer.new()
	waiting.name = "WaitingPanel"
	waiting.add_theme_constant_override("separation", 10)
	root_box.add_child(waiting)
	waiting.add_child(_label("LOBBY ROOM", 23, Color("f4bb3b")))
	var car_title := _label("PILIH MOBIL", 16, Color("d2d7dc"))
	waiting.add_child(car_title)
	var car_select := OptionButton.new()
	for car_name in GameState.CAR_NAMES:
		car_select.add_item(car_name)
	car_select.selected = GameState.selected_car
	car_select.item_selected.connect(func(index: int) -> void: GameState.selected_car = index; GameState.update_lobby_record())
	waiting.add_child(car_select)
	team_option = OptionButton.new()
	for team in ["Biru", "Oranye", "Spectator"]:
		team_option.add_item(team)
	team_option.item_selected.connect(_team_changed)
	waiting.add_child(team_option)
	roster_box = VBoxContainer.new()
	waiting.add_child(roster_box)
	status_label = _label("Menunggu pemain...", 15, Color("d2d7dc"))
	waiting.add_child(status_label)
	ready_button = _button("SIAP", 18)
	ready_button.pressed.connect(_toggle_ready)
	waiting.add_child(ready_button)
	start_button = _button("MULAI MATCH", 20)
	start_button.pressed.connect(GameState.start_room_match)
	waiting.add_child(start_button)
	var leave := _button("KELUAR ROOM", 16)
	leave.pressed.connect(_leave_room)
	waiting.add_child(leave)
	waiting.visible = false


func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String, size: int) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", size)
	return button


func _set_player_identity() -> void:
	GameState.player_name = name_input.text.strip_edges().left(20)
	if GameState.player_name.is_empty():
		GameState.player_name = "Pemain"
	name_input.text = GameState.player_name


func _start_single() -> void:
	_set_player_identity()
	GameState.close_room()
	GameState.multiplayer_mode = false
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _show_lan() -> void:
	_set_player_identity()
	GameState.scan_rooms()
	root_box.get_node("LanPanel").visible = true


func _host_room() -> void:
	_set_player_identity()
	GameState.room_name = room_name_input.text.strip_edges()
	if GameState.room_name.is_empty():
		GameState.room_name = "%s's Room" % GameState.player_name
	GameState.room_mode = "Tim 4 vs 4" if mode_option.selected == 1 else "Deathmatch"
	GameState.room_minutes = [5, 10, 15][time_option.selected]
	GameState.player_ready = false
	if GameState.host_room() == OK:
		_show_waiting()
		GameState.update_lobby_record()


func _join_address() -> void:
	_set_player_identity()
	GameState.player_ready = false
	if GameState.join_room(address_input.text) == OK:
		_show_waiting()


func _refresh_rooms() -> void:
	if Time.get_ticks_msec() % 900 > 40:
		return
	for child in room_list.get_children():
		child.queue_free()
	for address in GameState.discovery_results:
		var room: Dictionary = GameState.discovery_results[address]
		var button := _button("%s  •  %s  •  %s/%s" % [room.get("room", "Room"), room.get("mode", "Deathmatch"), room.get("players", 1), 8], 15)
		button.pressed.connect(func() -> void:
			address_input.text = str(address)
			_join_address()
		)
		room_list.add_child(button)
	if room_list.get_child_count() == 0:
		room_list.add_child(_label("Belum ada room terdeteksi. Masukkan IP host jika perlu.", 13, Color("9aa5af")))


func _show_waiting() -> void:
	root_box.get_node("LanPanel").visible = false
	root_box.get_node("WaitingPanel").visible = true
	_refresh_roster()


func _refresh_roster() -> void:
	if not roster_box:
		return
	for child in roster_box.get_children():
		child.queue_free()
	for id in GameState.lobby_players:
		var record: Dictionary = GameState.lobby_players[id]
		roster_box.add_child(_label("%s  •  %s  •  %s  •  %s" % [record.get("name", "Pemain"), GameState.CAR_NAMES[clampi(int(record.get("car", 0)), 0, GameState.CAR_NAMES.size() - 1)], record.get("team", "Biru"), "SIAP" if record.get("ready", false) else "Menunggu"], 15, Color("d2d7dc")))
	status_label.text = "%d/8 pemain • %s • %d menit" % [GameState.lobby_players.size(), GameState.room_mode, GameState.room_minutes]
	start_button.visible = GameState.room_host
	start_button.disabled = GameState.lobby_players.size() < 2 or not _all_ready()


func _all_ready() -> bool:
	if GameState.lobby_players.size() < 2:
		return false
	for record in GameState.lobby_players.values():
		if not bool(record.get("ready", false)):
			return false
	return true


func _team_changed(index: int) -> void:
	GameState.player_team = ["Biru", "Oranye", "Spectator"][index]
	GameState.update_lobby_record()


func _toggle_ready() -> void:
	GameState.player_ready = not GameState.player_ready
	ready_button.text = "BATAL SIAP" if GameState.player_ready else "SIAP"
	GameState.update_lobby_record()


func _leave_room() -> void:
	GameState.close_room()
	root_box.get_node("WaitingPanel").visible = false
	root_box.get_node("LanPanel").visible = true


func _show_error(message: String) -> void:
	if status_label:
		status_label.text = message


func _start_match() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
