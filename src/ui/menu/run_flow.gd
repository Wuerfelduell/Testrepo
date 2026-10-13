class_name RunFlow
extends RefCounted
## Scene transitions of a run: menu -> level (the arena only with --debug-arena), between areas, back to menu. Game state changes still go
## through CommandBus; this only orders the commands and the ironman save.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const ARENA_SCENE: String = "res://scenes/arena/arena.tscn"
const CRYPT_SCENE: String = "res://scenes/levels/crypt/crypt.tscn"
## Command-line switch that keeps the old single-room arena reachable for debugging.
const DEBUG_ARENA_ARG: String = "--debug-arena"

## New game: the old ironman save is discarded, the created hero enters the crypt.
static func start_new(tree: SceneTree, hero_record: Dictionary) -> Error:
	CommandBus.submit(ResetRunCommand.new())
	var debug_arena: bool = DEBUG_ARENA_ARG in OS.get_cmdline_user_args() or DEBUG_ARENA_ARG in OS.get_cmdline_args()
	var setup: Command = SetupArenaCommand.new(hero_record) if debug_arena else LevelSetupCommand.new(hero_record)
	var result: Error = CommandBus.submit(setup)
	if result != OK:
		return result
	SaveGame.delete()
	SaveGame.run_active = true
	return tree.change_scene_to_file(ARENA_SCENE if debug_arena else CRYPT_SCENE)

## The scene a (restored) run belongs to: its level's scene, or the arena for arena runs.
static func scene_for(state: GameState) -> String:
	var path: String = String(state.world.get("data_path", ""))
	if path.is_empty():
		return CRYPT_SCENE if String(state.world.get("level", "")) == "crypt" else ARENA_SCENE
	var scene: String = String(EncounterData.load_level(path).get("scene", ""))
	return scene if ResourceLoader.exists(scene) else ARENA_SCENE

## After a TravelCommand: load the new area's scene. Ironman saves on leaving only, so
## travelling writes nothing; the state already holds both areas.
static func enter_area(tree: SceneTree) -> Error:
	return tree.change_scene_to_file(scene_for(Game.state))

## CONTINUE: returns the load result so the menu can show a message instead of crashing.
static func continue_saved(tree: SceneTree) -> SaveGame.LoadResult:
	var loaded: SaveGame.LoadResult = SaveGame.load_save()
	if not loaded.is_valid():
		return loaded
	CommandBus.submit(ResetRunCommand.new())
	if CommandBus.submit(RestoreSaveCommand.new(loaded.state)) != OK:
		loaded.error = &"corrupt"
		return loaded
	Rng.rng.state = loaded.rng_state
	SaveGame.run_active = true
	tree.change_scene_to_file(scene_for(Game.state))
	return loaded

## Ironman: the only moment a living run is written is leaving it (menu or closing).
static func save_run() -> Error:
	if not SaveGame.run_active:
		return ERR_UNAVAILABLE
	return SaveGame.save(Game.state, Rng.rng.state)

static func save_and_leave_to_menu(tree: SceneTree) -> Error:
	var result: Error = save_run()
	SaveGame.run_active = false
	CommandBus.submit(ResetRunCommand.new())
	tree.paused = false
	tree.change_scene_to_file(MENU_SCENE)
	return result

## After death: the save is already gone, the run is cleared.
static func back_to_menu(tree: SceneTree) -> void:
	SaveGame.run_active = false
	CommandBus.submit(ResetRunCommand.new())
	tree.paused = false
	tree.change_scene_to_file(MENU_SCENE)

static func on_defeat() -> void:
	SaveGame.delete()
	SaveGame.run_active = false
