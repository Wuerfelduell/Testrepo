extends GutTest

class FakeSpace extends CombatSpace:
	var cover_points: Dictionary = {}
	var blocked_points: Array[Vector3] = []
	var detour_points: Array[Vector3] = []

	func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		if to in blocked_points:
			return PackedVector3Array()
		if to in detour_points:
			return PackedVector3Array([from, from + Vector3(0, 0, 10), to])
		return PackedVector3Array([from, to])

	func cover(_from: Vector3, to: Vector3) -> int:
		return int(cover_points.get(to, 0))

var space: FakeSpace

func before_each() -> void:
	space = FakeSpace.new()
	CombatSpace.active = space

func after_each() -> void:
	CombatSpace.active = null

func _actor(id: String, team: String, position: Vector3,
		personality: String = "brute", ranged: bool = false) -> Dictionary:
	return {"id": id, "team": team, "position": position, "hp": 20, "max_hp": 20,
		"ac": 12, "dex": 12, "speed_m": 9.0, "move_left": 9.0, "action_available": true,
		"bonus_available": true, "reaction_available": true, "disengaged": false,
		"personality": personality, "weapon": {"ranged": ranged, "reach": 1.5,
			"range": 24.0, "long_range": 96.0, "attack_bonus": 4, "damage_dice": "1d6",
			"damage_bonus": 2, "damage_type": "piercing", "name_key": "WEAPON_TEST"}}

func _state(enemy_position: Vector3 = Vector3.ZERO, hero_position: Vector3 = Vector3(1, 0, 0),
		personality: String = "brute", ranged: bool = false) -> GameState:
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = {"enemy": _actor("enemy", "enemy", enemy_position, personality, ranged),
		"hero": _actor("hero", "hero", hero_position)}
	state.turn_order = ["enemy", "hero"]
	return state

func test_finishes_one_hp_target_and_considers_every_live_target() -> void:
	var state: GameState = _state()
	state.actors["hero"]["hp"] = 1
	state.actors["other"] = _actor("other", "hero", Vector3(0, 0, 1))
	state.actors["dead"] = _actor("dead", "hero", Vector3(0, 0, -1))
	state.actors["dead"]["hp"] = 0
	var options: Array[Dictionary] = UtilityAI.consider(state, "enemy")
	assert_eq(options[0]["kind"], &"attack")
	assert_eq(options[0]["target_id"], "hero")
	var attack_targets: Array[String] = []
	for option: Dictionary in options:
		if option["kind"] == &"attack":
			attack_targets.append(option["target_id"])
	assert_has(attack_targets, "hero")
	assert_has(attack_targets, "other")
	assert_does_not_have(attack_targets, "dead")
	assert_almost_eq(options[0]["breakdown"]["kill_chance"], 0.65, 0.00001)

func test_archer_disengages_then_steps_back_from_melee_without_free_action() -> void:
	var state: GameState = _state(Vector3(1, 0, 0), Vector3.ZERO, "archer", true)
	var command: Command = UtilityAI.choose(state, "enemy")
	assert_true(command is DisengageCommand)
	assert_eq(command.validate(state), OK)
	command.apply(state)
	assert_false(state.actors["enemy"]["action_available"])
	command = UtilityAI.choose(state, "enemy")
	assert_true(command is MoveCommand)
	if command is MoveCommand:
		assert_gt(command.destination.distance_to(Vector3.ZERO), 1.5)
		assert_eq(command.validate(state), OK)
		var path: PackedVector3Array = CombatRules.movement_path(state, "enemy", command.destination)
		assert_true(CombatRules.opportunity_crossings(state, "enemy", path).is_empty())

func test_archer_prefers_cover_to_equally_distant_exposed_position() -> void:
	var state: GameState = _state(Vector3(0, 0, 5), Vector3.ZERO, "archer", true)
	state.actors["enemy"]["action_available"] = false
	var covered: Vector3 = Vector3(-4, 0, 8)
	var exposed: Vector3 = Vector3(4, 0, 8)
	space.cover_points[covered] = 5
	var options: Array[Dictionary] = UtilityAI.consider(state, "enemy", [exposed, covered])
	assert_eq(options[0]["kind"], &"move")
	assert_eq(options[0]["destination"], covered)
	assert_eq(options[0]["reason_key"], &"AI_COVER")

func test_archer_uses_reachable_high_ground_before_shooting() -> void:
	var state: GameState = _state(Vector3(0, 0, 8), Vector3.ZERO, "archer", true)
	var high: Vector3 = Vector3(1, 2, 9)
	var options: Array[Dictionary] = UtilityAI.consider(state, "enemy", [high])
	assert_eq(options[0]["kind"], &"move")
	assert_eq(options[0]["destination"], high)
	assert_eq(options[0]["reason_key"], &"AI_HIGH_GROUND")

func test_avoids_opportunity_path_even_if_endpoint_has_cover() -> void:
	var state: GameState = _state(Vector3(-4, 0, 0), Vector3.ZERO, "archer", true)
	state.actors["enemy"]["action_available"] = false
	var unsafe: Vector3 = Vector3(5, 0, 0)
	var safe: Vector3 = Vector3(-4, 0, 5)
	space.cover_points[unsafe] = 2
	space.cover_points[safe] = 2
	var options: Array[Dictionary] = UtilityAI.consider(state, "enemy", [unsafe, safe])
	assert_ne(options[0]["destination"], unsafe)
	var danger_seen: bool = false
	for option: Dictionary in options:
		if option["kind"] == &"move" and option["destination"] == unsafe:
			danger_seen = true
			assert_gt(option["breakdown"]["opportunity_cost"], 0.0)
	assert_true(danger_seen, "The dangerous alternative remains visible in F3 scoring.")

func test_coward_retreats_below_thirty_percent_hp() -> void:
	var state: GameState = _state(Vector3(5, 0, 0), Vector3.ZERO, "coward", true)
	state.actors["enemy"]["hp"] = 5
	var options: Array[Dictionary] = UtilityAI.consider(state, "enemy")
	assert_true(options[0]["kind"] in [&"move", &"dash"])
	if options[0]["kind"] == &"move":
		assert_eq(options[0]["reason_key"], &"AI_RETREAT")
	var destination: Vector3 = options[0]["destination"]
	assert_gt(destination.distance_to(Vector3.ZERO), 5.0)

func test_wounded_coward_disengages_instead_of_dashing_through_lethal_attack() -> void:
	var state: GameState = _state(Vector3(1, 0, 0), Vector3.ZERO, "coward", false)
	state.actors["enemy"]["hp"] = 1
	var options: Array[Dictionary] = UtilityAI.consider(state, "enemy")
	assert_eq(options[0]["kind"], &"disengage")

func test_path_cost_obeys_navigation_detour_movement_and_prone_cost() -> void:
	var state: GameState = _state(Vector3.ZERO, Vector3(20, 0, 0))
	state.actors["enemy"]["move_left"] = 6.0
	state.actors["enemy"]["conditions"] = ["prone"]
	var near_but_blocked: Vector3 = Vector3(2, 0, 0)
	space.detour_points.append(near_but_blocked)
	var options: Array[Dictionary] = UtilityAI.consider(state, "enemy", [near_but_blocked])
	for option: Dictionary in options:
		if option["kind"] == &"move":
			assert_ne(option["destination"], near_but_blocked)
			var command: Command = UtilityAI.command_for(option, "enemy")
			assert_eq(command.validate(state), OK)
			assert_lte(float(option["breakdown"]["path_cost"]), 6.00001)

func test_unreachable_high_ground_never_enters_candidate_list() -> void:
	var state: GameState = _state(Vector3(0, 0, 8), Vector3.ZERO, "archer", true)
	var unreachable: Vector3 = Vector3(0, 3, 8)
	space.blocked_points.append(unreachable)
	var options: Array[Dictionary] = UtilityAI.consider(state, "enemy", [unreachable])
	for option: Dictionary in options:
		assert_ne(option["destination"], unreachable)

func test_brute_dashes_to_close_a_distant_target() -> void:
	var state: GameState = _state(Vector3.ZERO, Vector3(30, 0, 0))
	assert_true(UtilityAI.choose(state, "enemy") is DashCommand)

func test_healthy_melee_attacker_closes_from_cover_against_one_reachable_enemy() -> void:
	var state: GameState = _state(Vector3.ZERO, Vector3(4, 0, 0))
	state.actors["hero"]["ac"] = 18
	state.actors["hero"]["hp"] = 12
	state.actors["enemy"]["weapon"]["attack_bonus"] = 3
	state.actors["enemy"]["weapon"]["damage_bonus"] = 1
	space.cover_points[Vector3.ZERO] = 5
	var command: Command = UtilityAI.choose(state, "enemy")
	assert_true(command is MoveCommand, "One opponent must not become three danger units at melee reach.")
	if command is MoveCommand:
		assert_true(CombatRules.attack_preview(state, "enemy", "hero", command.destination)["legal"])

func test_decisions_are_repeatable_read_only_and_rng_free() -> void:
	var state: GameState = _state(Vector3(2, 0, 0), Vector3.ZERO, "archer", true)
	var before: Dictionary = state.actors.duplicate(true)
	Rng.set_seed(9001)
	var rng_state: int = Rng.rng.state
	var first: Array[Dictionary] = UtilityAI.consider(state, "enemy")
	var second: Array[Dictionary] = UtilityAI.consider(state, "enemy")
	assert_eq(first, second)
	assert_eq(state.actors, before)
	assert_eq(Rng.rng.state, rng_state)

func test_director_preserves_debug_options_and_waits_for_presentation() -> void:
	var state: GameState = _state()
	var director: AIDirector = AIDirector.new()
	assert_not_null(director.decide(state))
	assert_eq(director.last_actor_id, "enemy")
	assert_false(director.last_candidates.is_empty())
	var previous: Array[Dictionary] = director.last_candidates.duplicate(true)
	state.pending = {"type": "attack"}
	assert_null(director.decide(state))
	assert_eq(director.last_candidates, previous)
	state.pending = {}
	state.turn_index = 1
	assert_null(director.decide(state))
