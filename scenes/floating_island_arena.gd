@tool
extends Node3D

## Four connected islands with roughly the same total walkable area as the old arena.
const HUB_RADIUS := 18.0
const ISLAND_RADIUS := 17.2
const BRIDGE_WIDTH := 8.5
const OUTER_DISTANCE := 45.0

var hazard_material: StandardMaterial3D


func _ready() -> void:
	_build_arena()


func _build_arena() -> void:
	for child in get_children():
		child.free()

	var hub := Vector3.ZERO
	var desert := Vector3(-OUTER_DISTANCE * 0.866, 0.0, OUTER_DISTANCE * 0.5)
	var forest := Vector3(OUTER_DISTANCE * 0.866, 0.0, OUTER_DISTANCE * 0.5)
	var volcano := Vector3(0.0, 0.0, -OUTER_DISTANCE)

	var stone := _material(Color("676d70"))
	var sand := _material(Color("c89e60"))
	var grass := _material(Color("477c56"))
	var basalt := _material(Color("343840"))
	var lava := _material(Color("b93920"), Color("ff4c14"), 2.0)
	hazard_material = lava
	var bridge_stone := _material(Color("99938a"))
	var bridge_wood := _material(Color("795438"))
	var bridge_basalt := _material(Color("4b4c50"))

	_add_lava_ocean(lava)
	_add_island("Central hub", hub, HUB_RADIUS, 0.0, stone, Color("bbb4a7"))
	_add_island("Sandy island", desert, ISLAND_RADIUS, 2.0, sand, Color("e8c47d"))
	_add_island("Forest island", forest, ISLAND_RADIUS, 4.0, grass, Color("88bd68"))
	_add_island("Volcanic island", volcano, ISLAND_RADIUS, 1.0, basalt, Color("e25731"))

	_build_bridge("Stone bridge to sand", hub, 0.0, HUB_RADIUS, desert, 2.0, ISLAND_RADIUS, bridge_stone, false)
	_build_bridge("Wood bridge to forest", hub, 0.0, HUB_RADIUS, forest, 4.0, ISLAND_RADIUS, bridge_wood, true)
	_build_bridge("Basalt bridge to volcano", hub, 0.0, HUB_RADIUS, volcano, 1.0, ISLAND_RADIUS, bridge_basalt, false)
	_add_sand_dunes(desert, 2.0)
	_add_sand_surface(desert, 2.0)
	_add_forest_trees(forest, 4.0)
	_add_volcanic_hazards(volcano, 1.0)
	_add_spawn_markers(hub)
	_add_sky_and_camera()


func _add_island(label: String, center: Vector3, radius: float, height: float, surface: Material, edge_color: Color) -> void:
	var ground := StaticBody3D.new()
	ground.name = "%s ground" % label
	ground.position = Vector3(center.x, height - 1.0, center.z)
	add_child(ground)
	var ground_mesh := CylinderMesh.new()
	ground_mesh.top_radius = radius
	ground_mesh.bottom_radius = radius * 0.94
	ground_mesh.height = 2.0
	ground_mesh.radial_segments = 64
	var ground_visual := MeshInstance3D.new()
	ground_visual.mesh = ground_mesh
	ground_visual.material_override = surface
	ground.add_child(ground_visual)
	var floor_shape := CylinderShape3D.new()
	floor_shape.radius = radius
	floor_shape.height = 2.0
	var floor_collider := CollisionShape3D.new()
	floor_collider.shape = floor_shape
	ground.add_child(floor_collider)

	var underside := CylinderMesh.new()
	underside.top_radius = radius * 0.76
	underside.bottom_radius = 2.2
	underside.height = 13.0
	underside.radial_segments = 48
	var rock := MeshInstance3D.new()
	rock.name = "%s floating rock" % label
	rock.mesh = underside
	rock.material_override = _material(edge_color.darkened(0.38))
	rock.position = Vector3(center.x, height - 8.3, center.z)
	add_child(rock)

	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = radius - 0.48
	rim_mesh.outer_radius = radius - 0.22
	rim.mesh = rim_mesh
	rim.material_override = _material(edge_color)
	rim.position = Vector3(center.x, height + 0.06, center.z)
	add_child(rim)

	var sign := Label3D.new()
	sign.name = "%s name" % label
	sign.text = label.to_upper()
	sign.font_size = 48
	sign.outline_size = 8
	sign.modulate = Color("f2eee5")
	sign.position = Vector3(center.x, height + 0.25, center.z + radius * 0.58)
	add_child(sign)


func _build_bridge(label: String, start_center: Vector3, start_height: float, start_radius: float, end_center: Vector3, end_height: float, end_radius: float, deck_material: Material, wooden_planks: bool) -> void:
	var direction := Vector3(end_center.x - start_center.x, 0.0, end_center.z - start_center.z).normalized()
	var start := Vector3(start_center.x, start_height, start_center.z) + direction * (start_radius - 1.1)
	var finish := Vector3(end_center.x, end_height, end_center.z) - direction * (end_radius - 1.1)
	var span := start.distance_to(finish)
	var bridge := StaticBody3D.new()
	bridge.name = label
	bridge.position = (start + finish) * 0.5
	add_child(bridge)
	bridge.look_at(finish, Vector3.UP)
	var deck_size := Vector3(BRIDGE_WIDTH, 0.62, span + 0.5)
	var deck := BoxMesh.new()
	deck.size = deck_size
	var deck_visual := MeshInstance3D.new()
	deck_visual.mesh = deck
	deck_visual.material_override = deck_material
	bridge.add_child(deck_visual)
	var deck_shape := BoxShape3D.new()
	deck_shape.size = deck_size
	var deck_collider := CollisionShape3D.new()
	deck_collider.shape = deck_shape
	bridge.add_child(deck_collider)

	if wooden_planks:
		var plank_material := _material(Color("a77a4c"))
		for index in 9:
			var plank := MeshInstance3D.new()
			var plank_mesh := BoxMesh.new()
			plank_mesh.size = Vector3(BRIDGE_WIDTH - 0.25, 0.14, span / 9.0 - 0.07)
			plank.mesh = plank_mesh
			plank.material_override = plank_material
			plank.position = Vector3(0.0, 0.37, -span * 0.5 + span * (float(index) + 0.5) / 9.0)
			bridge.add_child(plank)


func _add_sand_dunes(center: Vector3, height: float) -> void:
	for offset in [Vector3(-8.0, 0.0, -5.0), Vector3(8.0, 0.0, 6.0), Vector3(-9.0, 0.0, 8.0)]:
		var dune := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 3.2
		mesh.height = 1.0
		dune.mesh = mesh
		dune.material_override = _material(Color("d5ad70"))
		dune.scale = Vector3(1.5, 0.16, 0.8)
		dune.position = Vector3(center.x + offset.x, height + 0.04, center.z + offset.z)
		add_child(dune)


func _add_sand_surface(center: Vector3, height: float) -> void:
	var area := Area3D.new()
	area.name = "Loose sand traction zone"
	area.add_to_group("slippery_surfaces")
	area.collision_layer = 2
	area.collision_mask = 1
	area.position = Vector3(center.x, height + 0.2, center.z)
	var shape := CylinderShape3D.new()
	shape.radius = ISLAND_RADIUS - 0.6
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	area.add_child(collider)
	add_child(area)


func _add_forest_trees(center: Vector3, height: float) -> void:
	for offset in [Vector3(-10.0, 0.0, -8.0), Vector3(10.0, 0.0, -7.0), Vector3(-10.0, 0.0, 8.0), Vector3(7.0, 0.0, -10.0)]:
		var tree := StaticBody3D.new()
		tree.name = "Forest tree trunk"
		tree.position = Vector3(center.x + offset.x, height, center.z + offset.z)
		add_child(tree)
		var trunk_mesh := CylinderMesh.new()
		trunk_mesh.top_radius = 0.45
		trunk_mesh.bottom_radius = 0.65
		trunk_mesh.height = 3.2
		var trunk := MeshInstance3D.new()
		trunk.mesh = trunk_mesh
		trunk.material_override = _material(Color("61452d"))
		trunk.position.y = 1.6
		tree.add_child(trunk)
		var trunk_shape := CylinderShape3D.new()
		trunk_shape.radius = 0.65
		trunk_shape.height = 3.2
		var trunk_collider := CollisionShape3D.new()
		trunk_collider.shape = trunk_shape
		trunk_collider.position.y = 1.6
		tree.add_child(trunk_collider)
		var crown := MeshInstance3D.new()
		var crown_mesh := SphereMesh.new()
		crown_mesh.radius = 2.2
		crown_mesh.height = 4.4
		crown.mesh = crown_mesh
		crown.material_override = _material(Color("427c4b"))
		crown.position.y = 4.1
		tree.add_child(crown)


func _add_volcanic_hazards(center: Vector3, height: float) -> void:
	for offset in [Vector3(-8.0, 0.0, -8.0), Vector3(8.0, 0.0, -7.0), Vector3(-9.0, 0.0, 5.0)]:
		var pool_center := Vector3(center.x + offset.x, height + 0.08, center.z + offset.z)
		var warning := MeshInstance3D.new()
		var warning_mesh := TorusMesh.new()
		warning_mesh.inner_radius = 2.8
		warning_mesh.outer_radius = 3.15
		warning.mesh = warning_mesh
		warning.material_override = _material(Color("f1a04f"), Color("ff6a1c"), 0.8)
		warning.position = pool_center
		add_child(warning)

		var area := Area3D.new()
		area.name = "Lava hazard"
		area.add_to_group("arena_hazards")
		area.position = pool_center
		area.collision_layer = 0
		area.collision_mask = 1
		var pool_shape := CylinderShape3D.new()
		pool_shape.radius = 2.55
		pool_shape.height = 1.0
		var pool_collider := CollisionShape3D.new()
		pool_collider.shape = pool_shape
		area.add_child(pool_collider)
		var pool_mesh := CylinderMesh.new()
		pool_mesh.top_radius = 2.55
		pool_mesh.bottom_radius = 2.55
		pool_mesh.height = 0.12
		var pool_visual := MeshInstance3D.new()
		pool_visual.mesh = pool_mesh
		pool_visual.material_override = hazard_material
		area.add_child(pool_visual)
		add_child(area)


func _add_spawn_markers(center: Vector3) -> void:
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var marker := Marker3D.new()
		marker.name = "CarSpawn_%d" % (index + 1)
		marker.position = Vector3(center.x + sin(angle) * 10.0, 0.15, center.z + cos(angle) * 10.0)
		marker.rotation.y = angle
		add_child(marker)


func _add_lava_ocean(material: Material) -> void:
	var ocean := MeshInstance3D.new()
	ocean.name = "Lava far below"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 100.0
	mesh.bottom_radius = 100.0
	mesh.height = 0.5
	mesh.radial_segments = 64
	ocean.mesh = mesh
	ocean.material_override = material
	ocean.position.y = -18.0
	add_child(ocean)


func _add_sky_and_camera() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Floating islands sun"
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	var camera := Camera3D.new()
	camera.name = "Arena overview camera"
	camera.position = Vector3(0.0, 105.0, 145.0)
	camera.fov = 60.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -5.0), Vector3.UP)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("41678e")
	sky_material.sky_horizon_color = Color("e2c49d")
	sky_material.ground_bottom_color = Color("202631")
	sky_material.ground_horizon_color = Color("95836f")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c8b8a4")
	environment.ambient_light_energy = 0.7
	world_environment.environment = environment
	add_child(world_environment)


func _material(color: Color, emission_color: Color = Color(0.0, 0.0, 0.0), emission_energy: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.92
	if emission_energy > 0.0:
		result.emission_enabled = true
		result.emission = emission_color
		result.emission_energy_multiplier = emission_energy
	return result
