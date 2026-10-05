extends SceneTree

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Provide one absolute output directory after --")
		quit(1)
		return
	var output: String = arguments[0]
	DirAccess.make_dir_recursive_absolute(output)
	for filename: String in DirAccess.get_files_at("res://"):
		if not filename.ends_with(".fbx"):
			continue
		var scene: PackedScene = load("res://" + filename)
		var instance: Node3D = scene.instantiate()
		var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
		for mesh: MeshInstance3D in meshes:
			for surface: int in mesh.mesh.get_surface_count():
				var old: Material = mesh.mesh.surface_get_material(surface)
				var neutral: StandardMaterial3D = StandardMaterial3D.new()
				neutral.resource_name = old.resource_name if old else ""
				mesh.mesh.surface_set_material(surface, neutral)
		var state: GLTFState = GLTFState.new()
		var doc: GLTFDocument = GLTFDocument.new()
		var err: Error = doc.append_from_scene(instance, state)
		if err != OK:
			push_error("Could not convert " + filename)
			quit(1)
			return
		err = doc.write_to_filesystem(state, output.path_join(filename.get_basename() + ".glb"))
		if err != OK:
			quit(1)
			return
		instance.free()
	quit()
