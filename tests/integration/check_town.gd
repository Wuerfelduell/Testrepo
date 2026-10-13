extends Node
## Das Torviertel (act 1 start): the district loads with its baked navmesh, the streets are
## connected from the gate to the crypt entrance, every NPC anchor can be reached and opens
## its placeholder, and the crypt entrance leads into the crypt and back.
var checks: int = 0
var failed: bool = false
var level: DungeonLevel

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
	var data: Dictionary = EncounterData.load_level(TownLevel.TORVIERTEL_PATH)
	check(EncounterData.problems(data).is_empty(), "Torviertel data is valid: " + ", ".join(EncounterData.problems(data)))
	bus.submit(ResetRunCommand.new())
	check(bus.submit(LevelSetupCommand.new({}, TownLevel.TORVIERTEL_PATH)) == OK, "Torviertel setup accepted")
	check(game.state.world.get("dormant", {}).is_empty(), "Nobody fights in the Torviertel yet")
	level = (load(String(data["scene"])) as PackedScene).instantiate() as DungeonLevel
	get_tree().root.add_child(level)
	var frames: int = 0
	while not level.ready_for_input and frames < 240:
		await get_tree().physics_frame
		frames += 1
	check(level.ready_for_input, "Torviertel initializes fully")
	check(level.dungeon is TownBuilder, "The district is built by the town builder")
	check(level.dungeon.navigation.navigation_mesh.get_polygon_count() > 0, "Baked Torviertel navmesh loads")
	check(level.fader.occluders.size() >= TownBuilder.HOUSES.size(), "Houses are registered for the cutaway")
	var space: ArenaSpace = level.space
	var spawn: Vector3 = EncounterData.vector(data["hero_spawn"])
	check(space.query_path(spawn, Vector3(0, 0, -20)).size() >= 2, "The Torgasse leads from the gate to the Torplatz")
	check(space.query_path(spawn, Vector3(0, 0, 24)).is_empty() or space.query_path(spawn, Vector3(0, 0, 24))[-1].z < 18.5, "The shut gate keeps the hero inside the city")
	check(not space.visible(Vector3(0, 0, 8), Vector3(-10, 0, 8)), "Houses block sight from the street")
	check(level.hook_views.size() == data["hooks"].size() + data["exits"].size(), "Every NPC anchor and exit is placed")
	for hook: Dictionary in data["hooks"] + data["exits"]:
		var id: String = String(hook["id"])
		var target: Vector3 = EncounterData.vector(hook.get("interact_at", hook["position"]))
		var path: PackedVector3Array = space.query_path(spawn, target)
		check(path.size() >= 2 and Vector2(path[-1].x - target.x, path[-1].z - target.z).length() <= TownLevel.INTERACT_RANGE_M,
			"%s can be reached from the gate" % id)
		if hook.has("to"):
			continue
		check(level.interact(id), "%s is a known hook" % id)
		if hook.has("dialogue"):
			# Companions (package K4) already have a conversation: it opens and is left again.
			check(level.dialogue.is_open(), "%s opens its conversation" % id)
			bus.submit(DialogueEndCommand.new())
			continue
		check(level.interaction.text_label.text == tr("DIALOGUE_PLACEHOLDER") % id, "%s shows the placeholder line" % id)
		level.interaction.close()
	# Walk to the crypt entrance on the real navmesh.
	var entrance: Vector3 = Vector3(-20.6, 0, -14.0)
	check(bus.submit(MoveCommand.new("hero", entrance)) == OK, "Move to the crypt entrance accepted")
	var steps: int = 0
	while not game.state.pending.is_empty() and steps < 3000:
		level.simulation_step(0.1, true)
		steps += 1
		if steps % 10 == 0:
			await get_tree().process_frame
	check(level._within_reach(game.state, "torviertel_crypt_entrance"), "The hero reaches the crypt entrance")
	print("TOWN_WALK: %d steps to the crypt entrance" % steps)
	# Down into the crypt and back up into the alley (campaign K3 exits).
	get_tree().current_scene = level
	check(level.interact("torviertel_crypt_entrance"), "The crypt entrance answers")
	var crypt: DungeonLevel = await _wait_for_level(level)
	check(crypt != null and String(game.state.world["level"]) == "crypt", "The hero arrives in the crypt")
	check(crypt != null and crypt.hook_views.has("crypt_to_torviertel"), "The crypt has its way back up")
	# The hero arrives 1.8 m from the way back, within reach.
	check(crypt != null and crypt.interact("crypt_to_torviertel"), "The crypt exit answers")
	var back: DungeonLevel = await _wait_for_level(crypt)
	check(back is TownLevel and String(game.state.world["level"]) == "torviertel", "Back in the Torviertel")
	check(back != null and back.room_at(game.state.actors["hero"]["position"]) == "kellergasse", "The hero comes out in the Kellergasse")
	check(RunFlow.scene_for(game.state) == String(data["scene"]), "A run in the Torviertel continues in the Torviertel")
	if back != null:
		back.queue_free()
	await get_tree().process_frame
	bus.submit(ResetRunCommand.new())
	print("TOWN_CHECKS: %d, failed: %s" % [checks, failed])
	get_tree().quit(1 if failed else 0)

## Waits until the current scene is a different, ready level.
func _wait_for_level(old: DungeonLevel) -> DungeonLevel:
	for frame: int in range(600):
		await get_tree().physics_frame
		var current: Node = get_tree().current_scene
		if current is DungeonLevel and (current as DungeonLevel).ready_for_input and current != old:
			return current as DungeonLevel
	return null
