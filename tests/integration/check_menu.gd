extends Node
## godot --headless --path . tests/integration/check_menu.tscn
## The whole M1 loop through the real scenes: menu -> creation -> arena -> save and quit ->
## CONTINUE -> death -> death screen -> menu. With -- --menu-capture-dir=<dir> (on a real
## display) it also writes menu.png, creation.png and death.png.

const SAVE_PATH: String = "user://check_menu_ironman.save"

var checks: int = 0
var failures: PackedStringArray = []
var capture_dir: String = ""

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--menu-capture-dir="):
			capture_dir = argument.trim_prefix("--menu-capture-dir=")
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	SaveGame.path = SAVE_PATH
	SaveGame.delete()
	Rng.set_seed(4242)
	# The check stays alive across scene changes: the menu becomes the current scene.
	var menu: MainMenu = (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await _frames(10)
	check(not menu.buttons["continue"].visible, "CONTINUE is hidden without an ironman save")
	check(menu.buttons["new_game"].visible and menu.buttons["options"].visible and menu.buttons["quit"].visible,
		"NEW GAME, OPTIONS and QUIT are offered")
	await _capture("menu.png", 20)
	menu.buttons["options"].pressed.emit()
	await _frames(2)
	check(menu.options != null and menu.options.dice_speed.item_count == 4, "Options open with four dice speeds")
	menu.options.close()
	await _frames(2)
	menu.buttons["new_game"].pressed.emit()
	await _frames(2)
	var creation: CharacterCreation = menu.creation
	check(creation != null and not menu.main_page.visible, "NEW GAME opens character creation")
	var disabled: int = 0
	for id: String in creation.class_buttons:
		disabled += 1 if creation.class_buttons[id].disabled else 0
	check(creation.class_buttons.size() == 12 and disabled == 10, "Twelve classes, ten greyed out for later")
	check(creation.begin_button.disabled, "Begin needs a name")
	creation.select_class("rogue")
	check(creation.class_id == "fighter", "A greyed-out class cannot be chosen")
	creation.select_class("wizard")
	creation.select_body("female")
	creation.cycle_look(1)
	creation.set_hero_name("Mira")
	await _frames(3)
	check(not creation.begin_button.disabled, "Begin is enabled once a name exists")
	check(creation.preview_actor != null and creation.preview_actor.player.is_playing(), "3D preview plays its idle animation")
	var rotation_before: float = creation.preview_pivot.rotation.y
	var drag: InputEventMouseButton = InputEventMouseButton.new()
	drag.button_index = MOUSE_BUTTON_LEFT
	drag.pressed = true
	creation._preview_input(drag)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(60, 0)
	creation._preview_input(motion)
	check(not is_equal_approx(creation.preview_pivot.rotation.y, rotation_before), "Preview rotates by dragging")
	creation.preview_pivot.rotation.y = rotation_before
	check(creation.stats.text.contains("8") and creation.stats.text.contains("11"), "Wizard stats show HP 8 and AC 11")
	await _capture("creation.png", 20)
	creation.request_begin()
	await _frames(1)
	check(creation.confirm != null, "Begin states permadeath first")
	var permadeath_shown: bool = false
	for label: Node in creation.confirm.find_children("*", "Label", true, false):
		permadeath_shown = permadeath_shown or (label as Label).text == tr("CREATION_PERMADEATH")
	check(permadeath_shown, "The permadeath line is shown")
	creation.confirm_begin()
	var arena: CombatArena = await _wait_for_arena()
	if arena == null:
		return _finish()
	var hero: Dictionary = Game.state.actors["hero"]
	check(hero["name_key"] == "Mira" and hero["class_id"] == "wizard" and hero["look_id"] == "female_ranger",
		"The arena runs with the created hero, not the test Fighter")
	check(SaveGame.run_active and not SaveGame.exists(), "A new run starts without writing a save")
	arena.hud.dice_popup.speed = 40.0
	check(CommandBus.submit(MoveCommand.new("hero", Vector3(0, 0, 2))) == OK, "The hero can move")
	await _play_until(arena, func() -> bool: return Game.state.mode == &"combat" and Game.state.round_number >= 2)
	check(Game.state.mode == &"combat", "Combat starts with the created hero")
	arena.open_pause_menu()
	await _frames(1)
	check(get_tree().paused and arena.pause_menu != null, "Esc menu pauses the arena")
	var saved_hp: int = int(Game.state.actors["hero"]["hp"])
	var saved_round: int = Game.state.round_number
	arena.pause_menu.save_and_quit_to_menu.emit()
	menu = await _wait_for_menu()
	if menu == null:
		return _finish()
	check(not get_tree().paused, "Leaving unpauses the tree")
	check(SaveGame.exists(), "Quitting to the menu writes the ironman save")
	check(Game.state.actors.is_empty(), "The menu holds no running game")
	check(menu.buttons["continue"].visible, "CONTINUE appears once a save exists")
	menu.buttons["continue"].pressed.emit()
	arena = await _wait_for_arena()
	if arena == null:
		return _finish()
	check(int(Game.state.actors["hero"]["hp"]) == saved_hp and Game.state.round_number == saved_round,
		"CONTINUE restores the running combat")
	check(Game.state.actors["hero"]["name_key"] == "Mira", "CONTINUE restores the created hero")
	arena.hud.dice_popup.speed = 40.0
	await _play_until(arena, func() -> bool: return arena.death_screen != null)
	check(Game.state.mode == &"defeat", "The passive Wizard dies")
	check(not SaveGame.exists(), "Death deletes the ironman save")
	check(arena.death_screen != null, "The death screen replaces the old leave-arena panel")
	if arena.death_screen == null:
		return _finish()
	arena.death_screen.finish_fade()
	var detail: String = arena.death_screen.detail.text
	check(detail.contains("Mira") and detail.contains(tr("CREATION_CLASS_WIZARD")), "Death screen names the hero and class")
	check(detail.contains(tr("DEATH_CAUSE").get_slice("%", 0).strip_edges()), "Death screen says who killed the hero: " + detail)
	await _capture("death.png", 30)
	arena.death_screen.menu_button.pressed.emit()
	menu = await _wait_for_menu()
	if menu != null:
		check(not menu.buttons["continue"].visible, "After death there is nothing to continue")
	var broken: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	broken.store_string("{ not a save")
	broken.close()
	if menu != null:
		menu.refresh()
		menu.buttons["continue"].pressed.emit()
		await _frames(2)
		check(menu.message != null and get_tree().current_scene == menu, "A corrupt save shows a message instead of crashing")
	SaveGame.delete()
	_finish()

func _play_until(arena: CombatArena, done: Callable) -> void:
	for step: int in 6000:
		if done.call():
			return
		var state: GameState = Game.state
		if state.mode == &"combat" and state.pending.is_empty() and state.current_actor_id() == "hero" \
				and not arena.hud.rolls_busy():
			CommandBus.submit(EndTurnCommand.new("hero"))
		elif state.pending.get("type") == "reaction" and state.pending.get("actor_id") == "hero":
			# The passive Wizard declines the Shield reaction offer (prompt 05).
			CommandBus.submit(CastReactionCommand.new("hero", false))
		elif state.mode != &"defeat":
			arena.simulation_step(0.1, true)
		if step % 4 == 0:
			await get_tree().process_frame
	check(false, "The arena loop did not reach its goal")

func _wait_for_arena() -> CombatArena:
	for frame: int in 600:
		await get_tree().physics_frame
		var scene: Node = get_tree().current_scene
		if scene is CombatArena and (scene as CombatArena).ready_for_input:
			return scene as CombatArena
	check(false, "The arena did not start")
	return null

func _wait_for_menu() -> MainMenu:
	for frame: int in 120:
		await get_tree().process_frame
		if get_tree().current_scene is MainMenu:
			await _frames(2)
			return get_tree().current_scene as MainMenu
	check(false, "The main menu did not return")
	return null

func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame

func _capture(file_name: String, settle_frames: int) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _frames(settle_frames)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	check(image.save_png(capture_dir.path_join(file_name)) == OK, "Capture " + file_name)

func _finish() -> void:
	SaveGame.path = SaveGame.DEFAULT_PATH
	if failures.is_empty():
		print("MENU_FLOW_OK: %d checks; menu, creation, arena, save, continue, death, menu" % checks)
		get_tree().quit(0)
	else:
		get_tree().quit(1)
