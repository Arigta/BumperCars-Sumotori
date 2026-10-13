extends SceneTree

const NAMES := ["SportsCar", "SportsCar2", "NormalCar1", "NormalCar2", "SUV", "Taxi", "Cop"]
const SOURCE := "res://Realistic Car Pack - Nov 2018/OBJ/"
const DESTINATION := "res://assets/cars/"


func _initialize() -> void:
	call_deferred("_convert_all")


func _convert_all() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	if directory_error != OK:
		push_error("Cannot create car asset directory")
		quit(1)
		return
	for model_name in NAMES:
		var mesh := _convert_obj(model_name)
		if mesh == null:
			quit(1)
			return
		var path: String = DESTINATION + model_name + ".res"
		var save_error := ResourceSaver.save(mesh, path)
		if save_error != OK:
			push_error("Cannot save: %s" % path)
			quit(1)
			return
		print("Converted ", model_name, ": ", mesh.get_surface_count(), " material surfaces")
	quit()


func _convert_obj(model_name: String) -> ArrayMesh:
	var path := SOURCE + model_name + ".obj"
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		push_error("Cannot read %s" % path)
		return null
	var positions: Array[Vector3] = []
	var source_normals: Array[Vector3] = []
	var groups: Dictionary = {}
	var active_material := "Default"
	for line in source.split("\n", false):
		if line.begins_with("v "):
			var parts := line.split(" ", false)
			positions.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
		elif line.begins_with("vn "):
			var parts := line.split(" ", false)
			source_normals.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
		elif line.begins_with("usemtl "):
			active_material = line.substr(7).strip_edges()
		elif line.begins_with("f "):
			if not groups.has(active_material):
				groups[active_material] = {"vertices": [], "normals": []}
			var group: Dictionary = groups[active_material]
			var corners := line.substr(2).split(" ", false)
			for triangle in range(1, corners.size() - 1):
				for corner in [corners[0], corners[triangle], corners[triangle + 1]]:
					var indices: PackedStringArray = corner.split("/")
					var vertex_index: int = indices[0].to_int() - 1
					var normal_index: int = indices[2].to_int() - 1 if indices.size() > 2 else -1
					if vertex_index < 0 or vertex_index >= positions.size():
						push_error("Invalid OBJ vertex index in %s" % path)
						return null
					group["vertices"].append(positions[vertex_index])
					group["normals"].append(source_normals[normal_index] if normal_index >= 0 and normal_index < source_normals.size() else Vector3.UP)

	var colors := _read_materials(model_name)
	var mesh := ArrayMesh.new()
	for material_name in groups:
		var group: Dictionary = groups[material_name]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(group["vertices"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(group["normals"])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.resource_name = material_name
		material.albedo_color = colors.get(material_name, Color.WHITE)
		material.roughness = 0.55
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


func _read_materials(model_name: String) -> Dictionary:
	var source := FileAccess.get_file_as_string(SOURCE + model_name + ".mtl")
	var colors: Dictionary = {}
	var active_material := ""
	for line in source.split("\n", false):
		if line.begins_with("newmtl "):
			active_material = line.substr(7).strip_edges()
		elif line.begins_with("Kd ") and not active_material.is_empty():
			var parts := line.split(" ", false)
			colors[active_material] = Color(parts[1].to_float(), parts[2].to_float(), parts[3].to_float())
	return colors
