extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for model_name in ["SportsCar", "SportsCar2", "NormalCar1", "NormalCar2", "SUV", "Taxi", "Cop"]:
		var path := "res://assets/cars/%s.res" % model_name
		var resource := ResourceLoader.load(path)
		if resource == null:
			push_error("Missing car model: %s" % path)
			quit(1)
			return
		print("Loaded ", model_name, " as ", resource.get_class())
	var scene := load("res://scenes/game.tscn") as PackedScene
	if scene == null:
		push_error("Game scene could not load")
		quit(1)
		return
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	if game.get_node_or_null("PlayerCar/Selected car model") == null:
		push_error("Player car did not instantiate")
		quit(1)
		return
	var car := game.get_node("PlayerCar")
	var forward := InputEventKey.new()
	forward.keycode = KEY_W
	forward.pressed = true
	Input.parse_input_event(forward)
	for frame in 25:
		await physics_frame
	if car.speed <= 0.0:
		push_error("W input did not accelerate the car")
		quit(1)
		return
	var drift := InputEventKey.new()
	drift.keycode = KEY_SHIFT
	drift.pressed = true
	Input.parse_input_event(drift)
	var boost := InputEventMouseButton.new()
	boost.button_index = MOUSE_BUTTON_RIGHT
	boost.pressed = true
	Input.parse_input_event(boost)
	await physics_frame
	await physics_frame
	print("Input state: speed=", car.speed, " shift=", Input.is_key_pressed(KEY_SHIFT), " mouse=", Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT), " drifting=", car.is_drifting, " boosting=", car.is_boosting)
	if not car.is_drifting or not car.is_boosting:
		push_error("Shift drift or right-click NOS did not activate")
		quit(1)
		return
	for frame in 15:
		await physics_frame
	if car.marks.is_empty() or not car.smoke_particles[0].emitting or not car.nos_particles[0].emitting:
		push_error("Drift marks, smoke, or NOS particles did not activate")
		quit(1)
		return
	print("Game scene, selected car, WASD acceleration, drift, and NOS passed")
	quit()
