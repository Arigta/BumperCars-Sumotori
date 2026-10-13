extends Node3D

const PLAYER_CAR = preload("res://scripts/player_car.gd")
const ARENA_FALL_HEIGHT := -8.0

var player: CharacterBody3D
var follow_camera: Camera3D
var speed_label: Label
var nos_label: Label
var defeat_panel: PanelContainer
var defeat_overlay: ColorRect
var defeat_pending := false


func _ready() -> void:
	var car = PLAYER_CAR.new()
	car.model_path = GameState.selected_asset_path()
	var spawn := get_node_or_null("Arena/CarSpawn_1") as Marker3D
	if spawn:
		car.position = spawn.global_position
		car.rotation.y = spawn.rotation.y
	else:
		car.position = Vector3(0.0, 0.15, 20.0)
	add_child(car)
	player = car

	follow_camera = Camera3D.new()
	follow_camera.name = "Follow camera"
	follow_camera.fov = 72.0
	follow_camera.current = true
	add_child(follow_camera)
	follow_camera.position = player.global_position + player.global_basis * Vector3(0.0, 5.5, 10.0)
	follow_camera.look_at(player.global_position + Vector3.UP * 1.2)
	_build_hud()
	player.tree_exited.connect(_on_player_exited)


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if not player.is_defeated and player.global_position.y < ARENA_FALL_HEIGHT:
		defeat_pending = true
		player.is_defeated = true
		player.planar_velocity = Vector3.ZERO
		player.speed = 0.0
		get_tree().create_timer(1.0).timeout.connect(_show_defeat)
	var desired := player.global_position + player.global_basis * Vector3(0.0, 5.5, 10.0)
	follow_camera.global_position = follow_camera.global_position.lerp(desired, 1.0 - exp(-5.5 * delta))
	follow_camera.look_at(player.global_position + Vector3.UP * 1.2)
	speed_label.text = "KECEPATAN  %02d km/j" % int(absf(player.speed) * 3.6)
	nos_label.text = "NOS AKTIF" if player.is_boosting else ("DRIFT" if player.is_drifting else "WASD jalan  •  Shift drift  •  Klik kanan NOS")
	nos_label.add_theme_color_override("font_color", Color("39bbfa") if player.is_boosting else (Color("f4bb3b") if player.is_drifting else Color("dce2e7")))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not defeat_pending:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_player_exited() -> void:
	if not defeat_pending:
		return
	defeat_pending = false
	_show_defeat()


func _show_defeat() -> void:
	if not defeat_pending:
		return
	defeat_pending = false
	if not is_instance_valid(player):
		return
	defeat_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
	model_label.text = "MOBIL  %s" % GameState.selected_name()
	model_label.add_theme_font_size_override("font_size", 18)
	model_label.add_theme_color_override("font_color", Color("f4bb3b"))
	info.add_child(model_label)
	speed_label = Label.new()
	speed_label.add_theme_font_size_override("font_size", 24)
	info.add_child(speed_label)
	nos_label = Label.new()
	nos_label.add_theme_font_size_override("font_size", 15)
	info.add_child(nos_label)

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


func _build_defeat_panel(parent: Control) -> void:
	defeat_overlay = ColorRect.new()
	defeat_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	defeat_overlay.color = Color(0.02, 0.025, 0.035, 0.78)
	defeat_overlay.visible = false
	parent.add_child(defeat_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	defeat_overlay.add_child(center)
	defeat_panel = PanelContainer.new()
	defeat_panel.custom_minimum_size = Vector2(420.0, 0.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("242a33")
	style.border_color = Color("d84336")
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 26
	style.content_margin_bottom = 26
	defeat_panel.add_theme_stylebox_override("panel", style)
	center.add_child(defeat_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	defeat_panel.add_child(layout)
	var title := Label.new()
	title.text = "KAMU KALAH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("f06a59"))
	layout.add_child(title)
	var description := Label.new()
	description.text = "Mobilmu jatuh ke jurang."
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.add_theme_font_size_override("font_size", 18)
	layout.add_child(description)
	var retry := Button.new()
	retry.text = "ULANGI ARENA"
	retry.custom_minimum_size.y = 48
	retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	layout.add_child(retry)
	var menu := Button.new()
	menu.text = "KEMBALI KE MENU"
	menu.custom_minimum_size.y = 44
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	layout.add_child(menu)
