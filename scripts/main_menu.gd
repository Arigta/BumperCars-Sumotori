extends Control

var main_panel: PanelContainer
var selection_panel: PanelContainer
var selected_label: Label
var car_buttons: Array[Button] = []
var preview_car: Node3D
var preview_mesh: MeshInstance3D


func _ready() -> void:
	_build_ui()
	_show_main()


func _process(delta: float) -> void:
	if preview_car and selection_panel.visible:
		preview_car.rotation.y += delta * 0.55


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("171b22")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	main_panel = _panel()
	center.add_child(main_panel)
	var main_content := _content(main_panel)
	var title := _label("BUMPER CARS\nSUMOTORI", 42, Color("f4bb3b"))
	main_content.add_child(title)
	main_content.add_child(_label("Arena mobil dalam koloseum", 18, Color("d2d7dc")))
	var start_button := _button("MULAI", 24)
	start_button.pressed.connect(_show_selection)
	main_content.add_child(start_button)
	main_content.add_child(_label("WASD bergerak  •  Shift drift  •  Klik kanan NOS", 15, Color("9aa5af")))

	selection_panel = _panel()
	selection_panel.custom_minimum_size = Vector2(920, 0)
	center.add_child(selection_panel)
	var select_content := _content(selection_panel)
	select_content.add_child(_label("PILIH MOBIL", 32, Color("f4bb3b")))
	select_content.add_child(_label("Pilih satu model untuk masuk arena", 17, Color("d2d7dc")))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	select_content.add_child(columns)
	var chooser := VBoxContainer.new()
	chooser.add_theme_constant_override("separation", 14)
	columns.add_child(chooser)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	chooser.add_child(grid)
	for i in GameState.CAR_NAMES.size():
		var button := _button(_display_name(GameState.CAR_NAMES[i]), 18)
		button.custom_minimum_size = Vector2(190, 48)
		button.pressed.connect(_select_car.bind(i))
		grid.add_child(button)
		car_buttons.append(button)
	selected_label = _label("", 18, Color("f4bb3b"))
	chooser.add_child(selected_label)
	var play_button := _button("MASUK ARENA", 22)
	play_button.pressed.connect(_enter_arena)
	chooser.add_child(play_button)
	var back_button := _button("Kembali", 16)
	back_button.pressed.connect(_show_main)
	chooser.add_child(back_button)
	_build_car_preview(columns)
	_select_car(GameState.selected_car)


func _build_car_preview(parent: HBoxContainer) -> void:
	var preview_column := VBoxContainer.new()
	preview_column.custom_minimum_size = Vector2(405, 0)
	preview_column.add_theme_constant_override("separation", 12)
	parent.add_child(preview_column)
	preview_column.add_child(_label("PRATINJAU MOBIL  •  ROTASI OTOMATIS", 16, Color("d2d7dc")))

	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(405, 300)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.stretch = true
	preview_column.add_child(container)

	var viewport := SubViewport.new()
	viewport.size = Vector2i(810, 600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("171b22")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c5cbd2")
	environment.ambient_light_energy = 0.8
	world.environment = environment
	viewport.add_child(world)

	var stage := Node3D.new()
	viewport.add_child(stage)
	preview_car = Node3D.new()
	preview_car.position.y = 0.55
	stage.add_child(preview_car)
	preview_mesh = MeshInstance3D.new()
	preview_mesh.position.y = -0.55
	preview_car.add_child(preview_mesh)

	var camera := Camera3D.new()
	camera.position = Vector3(4.3, 2.6, 6.2)
	camera.fov = 38.0
	camera.current = true
	stage.add_child(camera)
	camera.look_at(Vector3(0.0, 0.52, 0.0), Vector3.UP)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-36.0, -32.0, 0.0)
	key_light.light_energy = 1.5
	stage.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-18.0, 145.0, 0.0)
	fill_light.light_energy = 0.7
	stage.add_child(fill_light)

	var style := StyleBoxFlat.new()
	style.bg_color = Color("171b22")
	style.border_color = Color("55616e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	container.add_theme_stylebox_override("panel", style)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(470, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("252c35")
	style.border_color = Color("55616e")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 26
	style.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _content(panel: PanelContainer) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	return box


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String, font_size: int) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _display_name(model: String) -> String:
	match model:
		"SportsCar": return "Mobil Sport"
		"SportsCar2": return "Mobil Sport 2"
		"NormalCar1": return "Sedan 1"
		"NormalCar2": return "Sedan 2"
		"SUV": return "SUV"
		"Taxi": return "Taksi"
		"Cop": return "Polisi"
	return model


func _select_car(index: int) -> void:
	GameState.selected_car = index
	selected_label.text = "Dipilih: %s" % _display_name(GameState.selected_name())
	if preview_mesh:
		preview_mesh.mesh = load(GameState.selected_asset_path()) as Mesh
	for i in car_buttons.size():
		car_buttons[i].modulate = Color("f4bb3b") if i == index else Color.WHITE


func _show_main() -> void:
	main_panel.visible = true
	selection_panel.visible = false


func _show_selection() -> void:
	main_panel.visible = false
	selection_panel.visible = true


func _enter_arena() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
