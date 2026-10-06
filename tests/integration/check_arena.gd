extends Node
## Real navigation/physics plus commands/AI: a complete encounter, not a mocked scene.
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
	var rng_node: Node = get_tree().root.get_node("Rng")
	rng_node.set_seed(6142)
	var arena: CombatArena = (load("res://scenes/arena/arena.tscn") as PackedScene).instantiate() as CombatArena
	get_tree().root.add_child(arena)
	for index: int in 5:
		await get_tree().physics_frame
	check(arena.ready_for_input, "Arena must initialize fully")
	check(arena.dungeon.navigation.navigation_mesh.get_polygon_count() > 0, "Baked navmesh must load")
	var initial: GameState = game.state
	check(initial.actors.size() == 4, "Fighter and three SRD enemy types must exist")
	check(int(initial.actors["hero"]["max_hp"]) == 12 and int(initial.actors["hero"]["ac"]) == 18, "Level-one Fighter derived stats")
	var staircase: PackedVector3Array = arena.space.query_path(Vector3(6, 0, 3), Vector3(8, 2, -5))
	check(staircase.size() >= 3, "Navigation reaches raised platform through stairs")
	if not staircase.is_empty():
		check(staircase[-1].y > 1.8, "Raised platform has real navigation height")
	var detour: PackedVector3Array = arena.space.query_path(Vector3(-5, 0, 2), Vector3(-5, 0, -2))
	check(CombatRules.path_length(detour) > 4.3, "Path routes around the internal wall")
	check(arena.space.cover(Vector3(-5, 0, 2), Vector3(-5, 0, -2)) == 99, "Wall grants total cover")
	check(not arena.space.visible(Vector3(-5, 0, 2), Vector3(-5, 0, -2)), "Wall blocks detection")
	for actor: CombatActor in arena.actors.values():
		check(actor != null, "Actor presentation is instantiated")
	arena.set_physics_process(false)
	arena.auto_play = true
	var events: Array[Dictionary] = []
	var listener: Callable = func(_command: Command, result: Dictionary) -> void:
		for event: Dictionary in result.get("events", []):
			events.append(event)
	bus.command_applied.connect(listener)
	# Walk into sight through the actual navmesh: detection must interrupt exploration.
	check(bus.submit(MoveCommand.new("hero", Vector3(0, 0, 2))) == OK, "Exploration move accepted")
	var combat_seen: bool = false
	var steps: int = 0
	while steps < 4000:
		arena.simulation_step(0.1, true)
		var state: GameState = game.state
		combat_seen = combat_seen or state.mode == &"combat"
		if combat_seen and state.mode != &"combat" and state.pending.is_empty():
			break
		steps += 1
		if steps % 10 == 0:
			await get_tree().process_frame
	check(combat_seen, "Enemy sight starts combat during exploration movement")
	check(steps < 4000, "AI completes a whole encounter without stalling")
	var attacks_by_actor: Dictionary = {}
	var rolls: int = 0
	var damage: int = 0
	var ends: int = 0
	for event: Dictionary in events:
		if event.get("type") == "start_attack":
			var source: String = str(event["actor_id"])
			attacks_by_actor[source] = int(attacks_by_actor.get(source, 0)) + 1
		rolls += 1 if event.get("type") == "roll" else 0
		damage += 1 if event.get("type") == "damage" else 0
		ends += 1 if event.get("type") == "combat_end" else 0
	check(rolls >= 6 and damage > 0, "Initiative, attacks and damage use visible roll events")
	check(ends == 1, "Exactly one encounter end event")
	var final_state: GameState = game.state
	check(final_state.mode == &"defeat" or final_state.mode == &"exploration", "Encounter terminal mode")
	bus.command_applied.disconnect(listener)
	print("ARENA_ATTACKS: ", attacks_by_actor)
	print("ARENA_RESULT: ", final_state.mode, " rounds=", final_state.round_number, " steps=", steps, " rolls=", rolls, " damage=", damage)
	print("ARENA_CHECKS_PASSED: ", checks if not failed else 0)
	arena.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failed else 0)
