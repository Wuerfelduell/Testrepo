extends Node
## Performance probe (no display needed for the counts; frame times need a renderer):
## loads the Torviertel or the crypt like in play and prints draw calls, objects,
## primitives, lights and process times averaged over 60 frames.
## Usage: godot --path . res://tests/integration/profile_level.tscn -- --level=town|crypt
var level: DungeonLevel

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var which: String = "town"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--level="):
			which = argument.trim_prefix("--level=")
	var bus: Node = get_tree().root.get_node("CommandBus")
	bus.submit(ResetRunCommand.new())
	var scene: String = "res://scenes/levels/torviertel/torviertel.tscn"
	if which == "crypt":
		bus.submit(LevelSetupCommand.new({}))
		scene = "res://scenes/levels/crypt/crypt.tscn"
	else:
		bus.submit(LevelSetupCommand.new({}, TownLevel.TORVIERTEL_PATH))
	level = (load(scene) as PackedScene).instantiate() as DungeonLevel
	get_tree().root.add_child(level)
	while not level.ready_for_input:
		await get_tree().physics_frame
	if OS.get_cmdline_user_args().has("--no-lod"):
		get_viewport().mesh_lod_threshold = 0.0
	for frame: int in 30:
		await get_tree().process_frame
	var sums: Dictionary = {}
	var monitors: Dictionary = {
		"fps": Performance.TIME_FPS,
		"process_ms": Performance.TIME_PROCESS,
		"physics_ms": Performance.TIME_PHYSICS_PROCESS,
		"draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
		"objects": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME,
		"primitives": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
		"nodes": Performance.OBJECT_NODE_COUNT,
	}
	var frames: int = 60
	var start: int = Time.get_ticks_usec()
	for frame: int in frames:
		await get_tree().process_frame
		for key: String in monitors:
			sums[key] = float(sums.get(key, 0.0)) + Performance.get_monitor(monitors[key])
	var wall_ms: float = (Time.get_ticks_usec() - start) / 1000.0 / frames
	var lights: Array[Node] = level.find_children("*", "Light3D", true, false)
	var shadowed: int = 0
	for light: Node in lights:
		if (light as Light3D).shadow_enabled:
			shadowed += 1
	var meshes: int = level.find_children("*", "MeshInstance3D", true, false).size()
	var multimeshes: int = level.find_children("*", "MultiMeshInstance3D", true, false).size()
	var line: String = "PROFILE %s wall_ms=%.1f lights=%d shadowed=%d mesh_instances=%d multimeshes=%d" % [
		which, wall_ms, lights.size(), shadowed, meshes, multimeshes]
	for key: String in monitors:
		line += " %s=%.1f" % [key, float(sums[key]) / frames]
	print(line)
	if OS.get_cmdline_user_args().has("--breakdown"):
		var surfaces: Dictionary = {}
		for node: Node in level.find_children("*", "GeometryInstance3D", true, false):
			var mesh: Mesh = null
			var count: int = 1
			if node is MeshInstance3D:
				mesh = (node as MeshInstance3D).mesh
			elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
				mesh = (node as MultiMeshInstance3D).multimesh.mesh
			var key: String = node.get_class() + ":" + (mesh.resource_path.get_file() if mesh != null and not mesh.resource_path.is_empty() else String(node.get_parent().name))
			var entry: Array = surfaces.get(key, [0, 0])
			entry[0] += 1
			entry[1] += mesh.get_surface_count() if mesh != null else 0
			surfaces[key] = entry
		var keys: Array = surfaces.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return surfaces[a][1] > surfaces[b][1])
		for key: String in keys.slice(0, 25):
			print("  %s nodes=%d surfaces=%d" % [key, surfaces[key][0], surfaces[key][1]])
	get_tree().quit(0)
