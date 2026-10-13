extends Node
## Screenshots of the Torviertel for the owner (needs a display, runs under Xvfb):
## the hero walks to each view on the real navmesh, the camera follows like in play.
const VIEWS: Array = [
	["gate", Vector3(0, 0, 13.5), 14.0],
	["square", Vector3(-4.0, 0, -15.0), 16.0],
	["inn", Vector3(-5.0, 0, -20.0), 13.0],
	["alley", Vector3(-18.5, 0, -14.0), 13.0],
	["overview", Vector3(0, 0, -6.0), 34.0],
]
var level: DungeonLevel

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var output: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--town-capture-dir="):
			output = argument.trim_prefix("--town-capture-dir=")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("capture_town needs --town-capture-dir=<dir> and a display")
		get_tree().quit(1)
		return
	var bus: Node = get_tree().root.get_node("CommandBus")
	var game: Node = get_tree().root.get_node("Game")
	bus.submit(ResetRunCommand.new())
	bus.submit(LevelSetupCommand.new({}, TownLevel.TORVIERTEL_PATH))
	level = (load("res://scenes/levels/torviertel/torviertel.tscn") as PackedScene).instantiate() as DungeonLevel
	get_tree().root.add_child(level)
	while not level.ready_for_input:
		await get_tree().physics_frame
	for view: Array in VIEWS:
		if bus.submit(MoveCommand.new("hero", view[1])) == OK:
			var steps: int = 0
			while not game.state.pending.is_empty() and steps < 3000:
				level.simulation_step(0.1, true)
				steps += 1
		level.camera_rig._zoom_target = float(view[2])
		for frame: int in 45:
			await get_tree().process_frame
		level._clear_hover()
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		image.resize(1280, roundi(1280.0 * image.get_height() / image.get_width()), Image.INTERPOLATE_LANCZOS)
		image.save_png(output.path_join("town-%s.png" % view[0]))
	get_tree().quit(0)
