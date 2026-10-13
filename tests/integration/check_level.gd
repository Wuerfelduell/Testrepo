extends Node
## Package 10: the crypt from spawn to the boss on the real level scene (navmesh, cover
## rays, perception, AI), deterministic seed. Three fights end with the hero standing,
## the trap springs, hooks open their placeholder and the Cult Priest's fight starts.
var checks: int = 0
var failed: bool = false
var level: DungeonLevel
var events: Array[Dictionary] = []

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
	get_tree().root.get_node("Rng").set_seed(6142)
	var data: Dictionary = EncounterData.load_level()
	check(EncounterData.problems(data).is_empty(), "Crypt data is valid: " + ", ".join(EncounterData.problems(data)))
	# Test hero: the level-1 test Fighter with extra hit points so one seed can walk the
	# whole level. The fights and the AI are unchanged.
	var hero: Dictionary = HeroKit.create(&"fighter")
	hero["hp"] = 160
	hero["max_hp"] = 160
	bus.submit(ResetRunCommand.new())
	check(bus.submit(LevelSetupCommand.new(hero)) == OK, "Level setup accepted")
	check(game.state.actors.size() == 1, "Only the hero is an actor before any encounter notices him")
	check(game.state.world["dormant"].size() == 4, "Three fights and the boss wait as dormant encounters")
	level = (load("res://scenes/levels/crypt/crypt.tscn") as PackedScene).instantiate() as DungeonLevel
	get_tree().root.add_child(level)
	var frames: int = 0
	while not level.ready_for_input and frames < 240:
		await get_tree().physics_frame
		frames += 1
	check(level.ready_for_input, "Crypt initializes fully")
	check(level.dungeon.navigation.navigation_mesh.get_polygon_count() > 0, "Baked crypt navmesh loads")
	check(level.dormant_views.size() == 12, "Every dormant enemy is drawn in its pose")
	check(level.fader != null and level.fader.occluders.size() > 40, "Walls are registered for the cutaway")
	_check_geometry()
	level.set_physics_process(false)
	level.auto_play = true
	bus.command_applied.connect(func(_command: Command, result: Dictionary) -> void:
		for event: Dictionary in result.get("events", []):
			events.append(event))
	# Hooks open their placeholder line.
	check(level.interact("crypt_inscription"), "Inscription hook exists")
	check(level.interaction.text_label.text == tr("DIALOGUE_PLACEHOLDER") % "crypt_inscription", "Hook shows the placeholder line")
	level.interaction.close()
	await _walk(Vector3(0, 0, 6.0), "hall")
	await _walk(Vector3(-0.7, 0, -10.0), "")
	check(bool(game.state.world.get("trap_sprung", false)), "Stepping on the plate springs the dart trap")
	check(_count("trap_sprung") == 1, "The trap springs once")
	await _walk(Vector3(8.0, 0, -9.0), "side_chamber")
	await _walk(Vector3(15.4, 0, -9.0), "")
	check(level._within_reach(game.state, "crypt_prisoner"), "The prisoner's cell can be reached at the gate")
	await _walk(Vector3(0.0, 0, -14.0), "")
	await _walk(Vector3(0.0, 0, -21.0), "ossuary")
	await _walk(Vector3(-2.6, 0, -36.0), "")
	check(level.interact("rest_alcove"), "The rest point answers")
	check(level.rest_panel.is_open(), "The rest point opens the long-rest dialog (package 08)")
	level.rest_panel.confirm()
	await get_tree().process_frame
	check(int(game.state.actors["hero"]["hp"]) == int(game.state.actors["hero"]["max_hp"]), "The long rest restores the hero")
	check(level.dormant_encounters() == ["shrine"], "Only the boss waits before the shrine")
	var hero_hp: int = int(game.state.actors["hero"]["hp"])
	check(hero_hp > 0 and game.state.mode == &"exploration", "The hero reaches the boss alive and rested")
	await _walk(Vector3(0.0, 0, -44.0), "shrine", false)
	var state: GameState = game.state
	check(state.mode == &"combat" and "cult_priest" in state.turn_order, "The Cult Priest's fight starts")
	check(state.actors.has("cult_priest") and int(state.actors["cult_priest"]["max_hp"]) == 38, "Boss uses the SRD Priest's hit points")
	check(_count("xp_awarded") == _count("combat_end") and _count("combat_end") >= 2, "Each cleared fight pays XP once")
	# A nearby group may hear a fight and join it, so two of the three fights can merge.
	var cleared: bool = true
	for event: Dictionary in events:
		if event.get("type") == "encounter_triggered" and event.get("encounter_id") != "shrine":
			for actor_id: Variant in event.get("actor_ids", []):
				cleared = cleared and not CombatRules.alive(state.actors.get(String(actor_id), {"hp": 1}))
	check(cleared and _count("encounter_triggered") == 4, "All three fights are cleared before the boss")
	print("LEVEL_CHECKS: %d, failed: %s, hero hp at boss %d" % [checks, failed, hero_hp])
	level.queue_free()
	await get_tree().process_frame
	bus.submit(ResetRunCommand.new())
	get_tree().quit(1 if failed else 0)

func _check_geometry() -> void:
	var space: ArenaSpace = level.space
	var balcony: PackedVector3Array = space.query_path(Vector3(0, 0, -20), Vector3(9, 2, -27))
	check(balcony.size() >= 3 and balcony[-1].y > 1.8, "Stairs lead onto the ossuary balcony")
	var altar: PackedVector3Array = space.query_path(Vector3(0, 0, -44), Vector3(0, 1, -54))
	check(altar.size() >= 2 and altar[-1].y > 0.8, "Stairs lead up to the altar dais")
	check(space.query_path(Vector3(0, 0, 17.5), Vector3(0, 0, -44)).size() >= 6, "One connected navmesh runs from the vestibule to the shrine")
	check(space.query_path(Vector3(15.4, 0, -9), Vector3(18, 0, -9)).is_empty(), "The locked gate blocks the prisoner's cell")
	check(not space.visible(Vector3(0, 0, 4), Vector3(10, 0, -9)), "Walls hide the side chamber from the hall")
	check(space.cover(Vector3(-2.25, 0, 8), Vector3(-2.25, 0, 1)) > 0, "Low walls in the hall give cover")

func _walk(target: Vector3, expected_encounter: String, finish: bool = true) -> void:
	var game: Node = get_tree().root.get_node("Game")
	var bus: Node = get_tree().root.get_node("CommandBus")
	var before: int = _count("encounter_triggered")
	check(bus.submit(MoveCommand.new("hero", target)) == OK, "Move to %s accepted" % target)
	var steps: int = 0
	var fought: bool = false
	while steps < 6000:
		_approach_if_idle()
		level.simulation_step(0.1, true)
		var state: GameState = game.state
		fought = fought or state.mode == &"combat"
		if state.mode == &"defeat":
			break
		if not finish and fought and state.pending.is_empty():
			break
		if state.mode == &"exploration" and state.pending.is_empty():
			break
		steps += 1
		if steps % 10 == 0:
			await get_tree().process_frame
	print("WALK %s: %d steps, mode %s, hero hp %d" % [target, steps, game.state.mode, int(game.state.actors["hero"]["hp"])])
	# The XP award is deferred to the frame after the fight.
	await get_tree().process_frame
	await get_tree().process_frame
	check(steps < 6000, "Walk to %s finishes without stalling" % target)
	check(game.state.mode != &"defeat", "The hero survives the walk to %s" % target)
	if expected_encounter.is_empty():
		check(_count("encounter_triggered") == before, "No encounter on the way to %s" % target)
	else:
		check(expected_encounter in game.state.world.get("triggered", []), "%s notices the hero" % expected_encounter)

## Like a player: the auto-played Fighter otherwise dances around an archer it cannot
## reach (the balcony bandit). With no enemy in melee reach, walk toward the nearest one.
func _approach_if_idle() -> void:
	var state: GameState = get_tree().root.get_node("Game").state
	if state.mode != &"combat" or not state.pending.is_empty() or state.current_actor_id() != "hero":
		return
	var hero: Dictionary = state.actors["hero"]
	for id: String in state.actors:
		var other: Dictionary = state.actors[id]
		if other.get("team") == "enemy" and CombatRules.alive(other) and \
				(other["position"] as Vector3).distance_to(hero["position"]) <= 2.0:
			return
	var best: PackedVector3Array = PackedVector3Array()
	for id: String in state.actors:
		var enemy: Dictionary = state.actors[id]
		if enemy.get("team") != "enemy" or not CombatRules.alive(enemy):
			continue
		var goal: Vector3 = enemy["position"] + ((hero["position"] as Vector3) - enemy["position"]).normalized() * 1.2
		var path: PackedVector3Array = level.space.query_path(hero["position"], goal)
		if path.size() >= 2 and (best.is_empty() or CombatRules.path_length(path) < CombatRules.path_length(best)):
			best = path
	if best.size() >= 2 and float(hero["move_left"]) > 0.5:
		var stop: Vector3 = CombatRules.position_on_path(best, minf(float(hero["move_left"]) - 0.05, CombatRules.path_length(best)))
		get_tree().root.get_node("CommandBus").submit(MoveCommand.new("hero", stop))

func _count(kind: String) -> int:
	var total: int = 0
	for event: Dictionary in events:
		total += 1 if event.get("type") == kind else 0
	return total
