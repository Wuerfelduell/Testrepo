extends Node
## Screenshots: the loot window over a dead bandit (--loot-capture=PATH), and an overloaded
## inventory with the slowed badge (--overload-capture=PATH).
## Run through tests/integration/capture_ui.sh (needs a real display, e.g. Xvfb).

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var path: String = ""
	var overloaded: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--loot-capture="):
			path = argument.trim_prefix("--loot-capture=")
		elif argument.begins_with("--overload-capture="):
			path = argument.trim_prefix("--overload-capture=")
			overloaded = true
	var game: Node = get_tree().root.get_node("Game")
	var arena: CombatArena = (load("res://scenes/arena/arena.tscn") as PackedScene).instantiate() as CombatArena
	get_tree().root.add_child(arena)
	var frames: int = 0
	while not arena.ready_for_input and frames < 600:
		await get_tree().physics_frame
		frames += 1
	var state: GameState = game.state
	for id: String in state.actors:
		if state.actors[id]["team"] == "enemy":
			state.actors[id]["hp"] = 0
	state.actors["hero"]["position"] = (state.actors["bandit"]["position"] as Vector3) + Vector3(1.2, 0, 1.2)
	state.mode = &"exploration"
	if overloaded:
		EquipmentRules.add_item(state.actors["hero"], "chain_mail", 4)
		EquipmentRules.refresh_speed(state.actors["hero"])
	game._commit_state(state)
	Rng.set_seed(11)
	CommandBus.submit(LootRollCommand.new("bandit"))
	for frame: int in 40:
		await get_tree().process_frame
	if overloaded:
		arena.menus.toggle_inventory()
	else:
		arena.menus.open_loot("bandit")
		arena.menus.loot._on_hovered(arena.menus.loot.slots[2])
	for frame: int in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result: Error = get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit(0 if result == OK else 1)
