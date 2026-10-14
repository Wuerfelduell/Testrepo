extends Node
## Campaign package K3: taking an exit on the real level scene changes the scene, the new
## area is built from the saved state, and coming back restores the crypt.
const YARD: String = "res://tests/fixtures/travel_yard.json"
var checks: int = 0
var failed: bool = false

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func _run() -> void:
	var game: Node = get_tree().root.get_node("Game")
	var bus: Node = get_tree().root.get_node("CommandBus")
	get_tree().root.get_node("Rng").set_seed(11)
	var crypt: Dictionary = EncounterData.load_level()
	crypt["exits"] = [{"id": "crypt_to_yard", "position": [0.0, 0.0, 17.5], "to": YARD, "arrive": [1.0, 0.0, 0.0]}]
	EncounterData._cache[EncounterData.CRYPT_PATH] = crypt
	bus.submit(ResetRunCommand.new())
	check(bus.submit(LevelSetupCommand.new()) == OK, "Level setup accepted")
	var level: DungeonLevel = (load("res://scenes/levels/crypt/crypt.tscn") as PackedScene).instantiate() as DungeonLevel
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	level = await _wait_for_level(level, true)
	check(level.hook_views.has("crypt_to_yard"), "The exit is drawn and clickable")
	check(level.journal != null and not level.journal.is_open(), "The journal exists and starts closed")
	level.journal.toggle()
	check(level.journal.list_label.text.contains(tr(String(QuestLog.load_quest("crypt_cult")["title"]))), "The crypt quest is in the journal")
	level.journal.close()
	check(level.interact("crypt_to_yard"), "The exit answers")
	var yard: DungeonLevel = await _wait_for_level(level)
	check(yard != level and yard != null, "A new scene was loaded")
	check(String(game.state.world["level"]) == "travel_yard", "The run is in the yard")
	check(game.state.actors["hero"]["position"] == Vector3(1, 0, 0), "The hero stands at the arrival point")
	check(yard.dormant_views.is_empty(), "No crypt enemies in the yard")
	game.state.actors["hero"]["position"] = Vector3(0, 0, 0)
	check(yard.interact("yard_to_crypt"), "The yard's exit answers")
	var back: DungeonLevel = await _wait_for_level(yard)
	check(back != null and String(game.state.world["level"]) == "crypt", "Back in the crypt")
	# Vaelor is his conversation's figure (hook), not a dormant view.
	check(back.dormant_views.size() == 11, "The crypt's enemies are still waiting")
	EncounterData._cache.erase(EncounterData.CRYPT_PATH)
	print("TRAVEL_CHECKS: %d, failed: %s" % [checks, str(failed)])
	get_tree().quit(1 if failed else 0)

## Waits until the current scene is a ready level; with `old` given, a different one.
func _wait_for_level(old: DungeonLevel, first: bool = false) -> DungeonLevel:
	for frame: int in range(600):
		await get_tree().physics_frame
		var current: Node = get_tree().current_scene
		if current is DungeonLevel and (current as DungeonLevel).ready_for_input and (first or current != old):
			return current as DungeonLevel
	return null
