class_name RunFlow
extends RefCounted
## Scene transitions of a run: menu -> arena, arena -> menu. Game state changes still go
## through CommandBus; this only orders the commands and the ironman save.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const ARENA_SCENE: String = "res://scenes/arena/arena.tscn"

## New game: the old ironman save is discarded, the created hero enters the arena.
static func start_new(tree: SceneTree, hero_record: Dictionary) -> Error:
	CommandBus.submit(ResetRunCommand.new())
	var result: Error = CommandBus.submit(SetupArenaCommand.new(hero_record))
	if result != OK:
		return result
	SaveGame.delete()
	SaveGame.run_active = true
	return tree.change_scene_to_file(ARENA_SCENE)

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
	tree.change_scene_to_file(ARENA_SCENE)
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
