@tool
extends Node3D

const SEGMENTS := 64
const RINGS := 12
const ISLANDS := [
	{"name": "Hub", "center": Vector2(0, 0), "radius": 31.0, "height": 2.0, "theme": "hub", "color": Color("#d8bd83"), "seed": 2},
	{"name": "Snow", "center": Vector2(-72, -42), "radius": 27.0, "height": 5.0, "theme": "snow", "color": Color("#b9e9f6"), "seed": 7},
	{"name": "Forest", "center": Vector2(72, -42), "radius": 27.0, "height": 3.0, "theme": "forest", "color": Color("#74b94c"), "seed": 13},
	{"name": "Desert", "center": Vector2(0, -88), "radius": 27.0, "height": 1.5, "theme": "desert", "color": Color("#f2bd48"), "seed": 19},
	{"name": "Jungle", "center": Vector2(-61, 66), "radius": 27.0, "height": 3.5, "theme": "jungle", "color": Color("#4cae61"), "seed": 29},
	{"name": "Volcano", "center": Vector2(61, 66), "radius": 27.0, "height": 2.0, "theme": "volcano", "color": Color("#dc7836"), "seed": 37},
]

var _built := false


func _ready() -> void:
	_build_arena()


func _build_arena() -> void:
	if _built:
		return
	_built = true
	for child in get_children():
		child.free()
	_add_ocean()
	for island_data in ISLANDS:
		_add_island(island_data)
	_add_bridges()
	_add_spawns()
	_add_hazards()
	_add_camera()


func _add_ocean() -> void:
	var ocean := MeshInstance3D.new()
	ocean.name = "Lava Ocean"
	var plane := PlaneMesh.new()
	plane.size = Vector2(330.0, 350.0)
	ocean.mesh = plane
	ocean.position = Vector3(0, -15.0, -10.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#10245b")
	material.roughness = 0.9
	ocean.material_override = material
	add_child(ocean)


func _add_island(data: Dictionary) -> void:
	var center: Vector2 = data.center
	var radius: float = data.radius
	var base_y: float = data.height
	var seed_value: int = data.seed
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for ring in RINGS:
		var r0 := radius * float(ring) / float(RINGS)
		var r1 := radius * float(ring + 1) / float(RINGS)
		for segment in SEGMENTS:
			var a0 := TAU * float(segment) / float(SEGMENTS)
			var a1 := TAU * float(segment + 1) / float(SEGMENTS)
			var p00 := _terrain_point(center, radius, r0, a0, base_y, seed_value)
			var p01 := _terrain_point(center, radius, r0, a1, base_y, seed_value)
			var p10 := _terrain_point(center, radius, r1, a0, base_y, seed_value)
			var p11 := _terrain_point(center, radius, r1, a1, base_y, seed_value)
			if ring == 0:
				_add_terrain_triangle(surface_tool, faces, Vector3(center.x, base_y, center.y), p11, p10, data.color, data.theme)
			else:
				_add_terrain_triangle(surface_tool, faces, p00, p01, p10, data.color, data.theme)
				_add_terrain_triangle(surface_tool, faces, p01, p11, p10, data.color, data.theme)
	surface_tool.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "%s Terrain" % data.name
	mesh_instance.mesh = surface_tool.commit()
	var terrain_material := StandardMaterial3D.new()
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 0.95
	mesh_instance.material_override = terrain_material
	add_child(mesh_instance)
	var body := StaticBody3D.new()
	body.name = "%s Ground" % data.name
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	_add_cliff(data)
	_add_theme_props(data)
	if data.theme == "desert":
		_add_sand_zone(data)


func _terrain_point(center: Vector2, radius: float, r: float, angle: float, base_y: float, seed_value: int) -> Vector3:
	var edge_wave := 1.0 + 0.035 * sin(angle * 5.0 + float(seed_value)) + 0.022 * sin(angle * 9.0 - float(seed_value) * 0.3)
	var edge_radius := radius * edge_wave
	var normalized := r / radius
	var envelope := sin(PI * normalized)
	var broad_hill := sin(angle * 2.0 + float(seed_value)) * 1.6 + cos(angle * 3.0 - float(seed_value) * 0.2) * 0.8
	var y := base_y + envelope * (0.4 + normalized * broad_hill)
	if normalized > 0.16 and normalized < 0.90:
		var ridge := maxf(0.0, sin(angle * 3.0 + float(seed_value) * 0.7))
		y += pow(ridge, 4.0) * sin(normalized * PI) * 3.5
	return Vector3(center.x + cos(angle) * normalized * edge_radius, y, center.y + sin(angle) * normalized * edge_radius)


func _add_terrain_triangle(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, base_color: Color, theme: String) -> void:
	for point in [a, b, c]:
		var elevation_tint := clampf((point.y - 1.0) / 9.0, 0.0, 0.23)
		var color := base_color.lerp(Color("#f4e5c3"), elevation_tint)
		if theme == "volcano":
			color = color.lerp(Color("#612f32"), clampf((point.y - 2.0) / 9.0, 0.0, 0.32))
		st.set_color(color)
		st.add_vertex(point)
	faces.append_array(PackedVector3Array([a, b, c]))


func _terrain_height(data: Dictionary, world_x: float, world_z: float) -> float:
	var center: Vector2 = data.center
	var offset := Vector2(world_x - center.x, world_z - center.y)
	return _terrain_point(center, data.radius, offset.length(), offset.angle(), data.height, data.seed).y


func _add_cliff(data: Dictionary) -> void:
	var rock := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = float(data.radius) * 0.98
	mesh.bottom_radius = float(data.radius) * 0.72
	mesh.height = 9.0
	mesh.radial_segments = 9
	mesh.rings = 2
	rock.mesh = mesh
	rock.position = Vector3(data.center.x, float(data.height) - 4.5, data.center.y)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#70504a") if data.theme != "snow" else Color("#667a91")
	material.roughness = 1.0
	rock.material_override = material
	add_child(rock)


func _add_bridges() -> void:
	var hub: Dictionary = ISLANDS[0]
	for index in range(1, ISLANDS.size()):
		var island: Dictionary = ISLANDS[index]
		var direction: Vector2 = island.center - hub.center
		var unit := direction.normalized()
		var half_width := 5.4
		var start_2d: Vector2 = hub.center + unit * (float(hub.radius) - 4.0)
		var end_2d: Vector2 = island.center - unit * (float(island.radius) - 4.0)
		var start := Vector3(start_2d.x, _terrain_height(hub, start_2d.x, start_2d.y) + 0.2, start_2d.y)
		var finish := Vector3(end_2d.x, _terrain_height(island, end_2d.x, end_2d.y) + 0.2, end_2d.y)
		_add_bridge(island.name, start, finish, half_width, island.theme == "forest")


func _add_bridge(label: String, start: Vector3, finish: Vector3, width: float, wooden: bool) -> void:
	var delta := finish - start
	var length := delta.length()
	var center := (start + finish) * 0.5
	var basis := Basis().looking_at(delta.normalized(), Vector3.UP)
	var bridge := StaticBody3D.new()
	bridge.name = "%s Bridge" % label
	bridge.position = center
	bridge.basis = basis
	var deck := BoxMesh.new()
	deck.size = Vector3(width, 0.55, length + 1.5)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = deck
	mesh_instance.position.y = -0.22
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#8b5937") if wooden else Color("#827a7e")
	material.roughness = 0.92
	mesh_instance.material_override = material
	bridge.add_child(mesh_instance)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.55, length + 1.5)
	collider.shape = shape
	collider.position.y = -0.22
	bridge.add_child(collider)
	add_child(bridge)
	if wooden:
		for plank_index in range(1, 13):
			var plank := MeshInstance3D.new()
			var plank_mesh := BoxMesh.new()
			plank_mesh.size = Vector3(width + 0.12, 0.08, 0.16)
			plank.mesh = plank_mesh
			plank.position = Vector3(0, 0.09, -length * 0.5 + length * float(plank_index) / 13.0)
			var plank_material := StandardMaterial3D.new()
			plank_material.albedo_color = Color("#ad7546")
			plank.material_override = plank_material
			bridge.add_child(plank)


func _add_theme_props(data: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.seed) * 937
	var theme: String = data.theme
	var color: Color = data.color
	var center: Vector2 = data.center
	for index in 9:
		var angle := TAU * float(index) / 9.0 + rng.randf_range(-0.2, 0.2)
		var radius := rng.randf_range(9.0, float(data.radius) * 0.68)
		var x := center.x + cos(angle) * radius
		var z := center.y + sin(angle) * radius
		var h := _terrain_height(data, x, z)
		if theme == "snow":
			_add_prop_cone("Ice Peak %d" % index, Vector3(x, h, z), rng.randf_range(3.0, 6.5), Color("#e8f8ff"), 7)
		elif theme == "desert":
			_add_prop_cone("Sand Dune %d" % index, Vector3(x, h, z), rng.randf_range(2.0, 4.0), Color("#ffd66a"), 6)
		elif theme == "volcano":
			if index % 2 == 0:
				_add_prop_cone("Basalt Spire %d" % index, Vector3(x, h, z), rng.randf_range(3.0, 5.0), Color("#824943"), 6)
		elif theme == "forest" or theme == "jungle":
			var trunk := _add_prop_cylinder("Tree Trunk %d" % index, Vector3(x, h + 1.65, z), 0.65, 3.2, Color("#765039"))
			_add_prop_cone("Tree Canopy %d" % index, Vector3(x, h + 2.8, z), 3.0, color, 7)
			if theme == "jungle":
				trunk.scale.x = 1.35
	_add_center_marker(data)


func _add_center_marker(data: Dictionary) -> void:
	var center: Vector2 = data.center
	var pos := Vector3(center.x, float(data.height) + 0.4, center.y)
	if data.theme == "snow":
		_add_prop_cone("Snow Summit", pos, 6.2, Color("#effaff"), 7)
	elif data.theme == "volcano":
		_add_prop_cone("Volcano Crater Rim", pos, 7.0, Color("#713b37"), 8)
		_add_prop_cone("Lava Spire", pos + Vector3(0, 2.0, 0), 4.0, Color("#ff7135"), 7)
	elif data.theme == "desert":
		_add_prop_cone("Golden Dune", pos, 6.5, Color("#ffdb65"), 6)


func _add_prop_cone(label: String, position: Vector3, height: float, color: Color, sides: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = height * 0.48
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	node.mesh = mesh
	node.position = position + Vector3.UP * height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	node.material_override = material
	add_child(node)
	return node


func _add_prop_cylinder(label: String, position: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.8
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 7
	node.mesh = mesh
	node.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	add_child(node)
	return node


func _add_spawns() -> void:
	var hub: Dictionary = ISLANDS[0]
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var x := cos(angle) * 14.0
		var z := sin(angle) * 14.0
		var marker := Marker3D.new()
		marker.name = "CarSpawn_%d" % (index + 1)
		marker.position = Vector3(x, _terrain_height(hub, x, z) + 0.1, z)
		marker.rotation.y = -angle + PI * 0.5
		add_child(marker)


func _add_hazards() -> void:
	var volcano: Dictionary = ISLANDS[5]
	for index in range(3):
		var local_offset := [Vector2(-12, 7), Vector2(10, -10), Vector2(12, 10)][index]
		var x := float(volcano.center.x + local_offset.x)
		var z := float(volcano.center.y + local_offset.y)
		var y := _terrain_height(volcano, x, z) + 0.22
		_add_lava_pool("Lava Pool %d" % index, Vector3(x, y, z))


func _add_lava_pool(label: String, position: Vector3) -> void:
	var hazard := Area3D.new()
	hazard.name = label
	hazard.add_to_group("arena_hazards")
	hazard.collision_layer = 0
	hazard.collision_mask = 1
	var mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 4.1
	disc.bottom_radius = 4.1
	disc.height = 0.16
	disc.radial_segments = 10
	mesh.mesh = disc
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#ff5a23")
	material.emission_enabled = true
	material.emission = Color("#ff3c12")
	material.emission_energy_multiplier = 1.6
	mesh.material_override = material
	mesh.position.y = -0.05
	hazard.add_child(mesh)
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 4.0
	shape.height = 2.0
	collider.shape = shape
	hazard.add_child(collider)
	hazard.position = position
	add_child(hazard)


func _add_sand_zone(data: Dictionary) -> void:
	var area := Area3D.new()
	area.name = "Loose Sand"
	area.add_to_group("slippery_surfaces")
	area.collision_layer = 0
	area.collision_mask = 1
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 23.0
	shape.height = 14.0
	collider.shape = shape
	collider.position.y = 6.0
	area.add_child(collider)
	area.position = Vector3(data.center.x, 0.0, data.center.y)
	add_child(area)


func _add_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "Map Preview Camera"
	camera.position = Vector3(0, 175, 220)
	camera.look_at(Vector3(0, 0, -5), Vector3.UP)
	camera.current = true
	add_child(camera)
