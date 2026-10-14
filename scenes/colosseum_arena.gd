@tool
extends Node3D

## A 71 m wide circular arena. All geometry is built from Godot primitives.
const FLOOR_RADIUS := 35.5
const WALL_RADIUS := 35.3
const PIT_INNER_RADIUS := 36.5
const PIT_OUTER_RADIUS := 74.0
const PIT_DEPTH := 32.0
const OUTER_RADIUS := 62.0
const SEGMENTS := 64
const ARCADE_BAYS := 32


func _ready() -> void:
	_build_arena()


func _build_arena() -> void:
	# Generated nodes are deliberately not saved in the scene. Reopening the scene
	# rebuilds them, so changing this script never leaves old geometry behind.
	for child in get_children():
		child.free()

	var asphalt := _material(Color("30353b"))
	var lane_white := _material(Color("e9e5d9"))
	var safety_yellow := _material(Color("f4bb3b"))
	var barrier_red := _material(Color("c8443d"))
	var barrier_white := _material(Color("ede9df"))
	var pad_blue := _material(Color("3389b6"))
	var pad_orange := _material(Color("df8540"))
	var sandstone := _material(Color("c8a77a"))
	var pale_stone := _material(Color("e2c9a0"))
	var shadow_stone := _material(Color("7c6551"))
	var trim := _material(Color("9b5542"))
	var pit_shadow := _material(Color("101319"))
	var pit_wall := _material(Color("242831"))
	var pit_edge := _material(Color("d84336"))

	_disc("Asphalt driving surface", FLOOR_RADIUS, 2.0, -1.0, asphalt, true)
	# Thin paint sits just above the asphalt; the driving surface remains flat.
	_ring("Outer track line", 32.0, 0.18, 0.025, 0.025, safety_yellow, SEGMENTS)
	_ring("Inner track line", 9.0, 0.16, 0.025, 0.025, lane_white, SEGMENTS)
	_disc("Center circle", 7.7, 0.025, 0.0125, asphalt, false)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		for dash in 4:
			var distance := 12.5 + float(dash) * 4.5
			var dash_pos := Vector3(sin(angle) * distance, 0.027, cos(angle) * distance)
			_box("Lane dash %d-%d" % [i, dash], dash_pos, Vector3(0.16, 0.025, 2.0), lane_white, angle)

	# Eight marked start spots let LAN rooms place a full 4v4 match safely.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var pad_pos := Vector3(sin(angle) * 23.0, 0.027, cos(angle) * 23.0)
		var pad_color: Material = pad_blue if i % 2 == 0 else _material(Color("43b879"))
		_box("Car start pad %d" % (i + 1), pad_pos, Vector3(3.7, 0.025, 5.8), pad_color, angle)
		var stripe_pos := pad_pos + Vector3(sin(angle) * 2.7, 0.018, cos(angle) * 2.7)
		_box("Start line %d" % (i + 1), stripe_pos, Vector3(3.5, 0.025, 0.25), lane_white, angle)
		var spawn := Marker3D.new()
		spawn.name = "CarSpawn_%d" % (i + 1)
		spawn.position = Vector3(pad_pos.x, 0.15, pad_pos.z)
		spawn.rotation.y = angle
		add_child(spawn)

	# Low painted warnings mark the drop. They have no collision, so cars can be
	# shoved past them and fall into the pit.
	_ring("Track edge warning line", 34.9, 0.28, 0.04, 0.035, safety_yellow, SEGMENTS)
	for i in SEGMENTS:
		var angle := TAU * float(i) / SEGMENTS
		var panel_pos := Vector3(sin(angle) * 35.0, 0.06, cos(angle) * 35.0)
		var panel_color: Material = barrier_red if int(i / 2) % 2 == 0 else barrier_white
		_box("Drop warning panel %02d" % i, panel_pos, Vector3(TAU * 35.0 / SEGMENTS + 0.05, 0.08, 0.18), panel_color, angle)

	# Broad concentric seating tiers rise away from the play area.
	_ring("Lower seats", 49.0, 4.8, 1.6, 0.8, shadow_stone, SEGMENTS)
	_ring("Lower seat tops", 49.0, 4.8, 0.28, 1.74, sandstone, SEGMENTS)
	_ring("Middle seats", 53.5, 4.8, 3.2, 1.6, shadow_stone, SEGMENTS)
	_ring("Middle seat tops", 53.5, 4.8, 0.28, 3.34, sandstone, SEGMENTS)
	_ring("Upper seats", 58.0, 5.0, 4.8, 2.4, shadow_stone, SEGMENTS)
	_ring("Upper seat tops", 58.0, 5.0, 0.28, 4.94, pale_stone, SEGMENTS)

	# Pillars and horizontal stone courses form two open arcade levels.
	_ring("Lower arcade base", OUTER_RADIUS, 2.4, 1.0, 0.5, sandstone, SEGMENTS)
	for i in ARCADE_BAYS:
		var angle := TAU * float(i) / ARCADE_BAYS
		var pillar_pos := Vector3(sin(angle) * OUTER_RADIUS, 3.65, cos(angle) * OUTER_RADIUS)
		_box("Lower pillar %02d" % i, pillar_pos, Vector3(1.65, 6.3, 2.2), pale_stone, angle)
		pillar_pos.y = 9.05
		_box("Upper pillar %02d" % i, pillar_pos, Vector3(1.45, 4.5, 2.0), pale_stone, angle)
		var bay_angle := angle + TAU / float(ARCADE_BAYS * 2)
		_arch("Lower arch %02d" % i, bay_angle, 4.9, pale_stone)
		_arch("Upper arch %02d" % i, bay_angle, 9.3, pale_stone)
	_ring("Lower arcade cornice", OUTER_RADIUS, 2.8, 0.85, 7.2, trim, SEGMENTS)
	_ring("Upper arcade cornice", OUTER_RADIUS, 3.0, 1.1, 11.85, sandstone, SEGMENTS)
	_ring("Roof rim", OUTER_RADIUS, 3.3, 0.35, 12.58, pale_stone, SEGMENTS)

	# Deep moat outside the stands. Its dark bottom reads as an actual drop from above.
	_disc("Pit floor far below", PIT_OUTER_RADIUS, 1.0, -PIT_DEPTH, pit_shadow, false)
	_ring("Pit inner cliff", PIT_INNER_RADIUS, 1.5, PIT_DEPTH, -PIT_DEPTH * 0.5, pit_wall, SEGMENTS)
	_ring("Pit outer cliff", PIT_OUTER_RADIUS, 1.5, PIT_DEPTH, -PIT_DEPTH * 0.5, pit_wall, SEGMENTS)
	_ring("Cliff warning lip", 35.9, 0.55, 0.22, 0.04, pit_edge, SEGMENTS)
	for i in SEGMENTS:
		var angle := TAU * float(i) / SEGMENTS
		var shaft_pos := Vector3(sin(angle) * 36.5, -15.0, cos(angle) * 36.5)
		_box("Cliff striation %02d" % i, shaft_pos, Vector3(0.16, 25.0, 0.25), pit_edge if i % 4 == 0 else pit_wall, angle)

	# Direction markers sit above the barrier, clear of the driving surface.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var marker_pos := Vector3(sin(angle) * 34.2, 2.65, cos(angle) * 34.2)
		_box("Boundary marker %d" % i, marker_pos, Vector3(1.6, 0.8, 0.45), trim, angle)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	var camera := Camera3D.new()
	camera.name = "Arena overview camera"
	camera.position = Vector3(0.0, 88.0, 128.0)
	camera.fov = 60.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 2.0, 0.0), Vector3.UP)

	var world_environment := WorldEnvironment.new()
	world_environment.name = "Arena atmosphere"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("718ca7")
	sky_material.sky_horizon_color = Color("d5baa0")
	sky_material.ground_bottom_color = Color("22252c")
	sky_material.ground_horizon_color = Color("807263")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9a995")
	environment.ambient_light_energy = 0.65
	world_environment.environment = environment
	add_child(world_environment)


func _material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.9
	return result


func _disc(label: String, radius: float, height: float, y: float, material: Material, solid: bool) -> void:
	var root: Node3D
	if solid:
		root = StaticBody3D.new()
	else:
		root = Node3D.new()
	root.name = label
	root.position.y = y
	add_child(root)

	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = SEGMENTS * 2
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	root.add_child(instance)

	if solid:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		var collider := CollisionShape3D.new()
		collider.shape = shape
		root.add_child(collider)


func _ring(label: String, radius: float, depth: float, height: float, y: float, material: Material, count: int, solid: bool = false) -> void:
	var width := TAU * radius / float(count) + 0.12
	for i in count:
		var angle := TAU * float(i) / float(count)
		var position_3d := Vector3(sin(angle) * radius, y, cos(angle) * radius)
		_box("%s %02d" % [label, i], position_3d, Vector3(width, height, depth), material, angle, solid)


func _arch(label: String, angle: float, base_y: float, material: Material) -> void:
	const ARCH_PIECES := 8
	const HALF_WIDTH := 3.85
	const RISE := 1.85
	for i in ARCH_PIECES:
		var t0 := PI * float(i) / ARCH_PIECES
		var t1 := PI * float(i + 1) / ARCH_PIECES
		var x0 := cos(t0) * HALF_WIDTH
		var x1 := cos(t1) * HALF_WIDTH
		var y0 := base_y + sin(t0) * RISE
		var y1 := base_y + sin(t1) * RISE
		var x := (x0 + x1) * 0.5
		var position_3d := Vector3(sin(angle) * OUTER_RADIUS + cos(angle) * x, (y0 + y1) * 0.5, cos(angle) * OUTER_RADIUS - sin(angle) * x)
		var roll := atan2(y1 - y0, x1 - x0)
		var length := Vector2(x1 - x0, y1 - y0).length() + 0.15
		_box("%s piece %d" % [label, i], position_3d, Vector3(length, 0.72, 2.15), material, angle, false, roll)


func _box(label: String, position_3d: Vector3, size: Vector3, material: Material, yaw: float, solid: bool = false, roll: float = 0.0) -> void:
	var root: Node3D
	if solid:
		root = StaticBody3D.new()
	else:
		root = Node3D.new()
	root.name = label
	root.position = position_3d
	root.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, roll)
	add_child(root)

	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	root.add_child(instance)

	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		root.add_child(collider)
