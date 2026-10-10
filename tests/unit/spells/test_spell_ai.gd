extends GutTest
## Utility AI with spells: scores spell options, never burns its allies, keeps range.

func enemy(position: Vector3, hp: int = 7) -> Dictionary:
	return {"team": "hero", "position": position, "hp": hp, "max_hp": 30, "ac": 12, "dex": 10,
		"speed_m": 9.0, "move_left": 9.0, "action_available": true, "bonus_available": true,
		"reaction_available": true, "disengaged": false, "conditions": [], "effects": [],
		"ability_scores": {&"str": 10, &"dex": 10, &"con": 10, &"int": 10, &"wis": 10, &"cha": 10},
		"weapon": {"ranged": false, "reach": 1.5, "attack_bonus": 4, "damage_dice": "1d4",
			"damage_bonus": 0, "damage_type": "slashing"}}

func caster(position: Vector3) -> Dictionary:
	var record: Dictionary = HeroKit.create(&"wizard", position)
	record["team"] = "enemy"
	record["id"] = "caster"
	return record

func make_state(actors: Dictionary) -> GameState:
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = actors
	var order: Array[String] = ["caster"]
	for id: String in actors:
		if id != "caster":
			order.append(id)
	state.turn_order = order
	return state

func before_each() -> void:
	CombatSpace.active = null

func after_each() -> void:
	CombatSpace.active = null

func spell_options(options: Array[Dictionary], spell_id: String) -> Array[Dictionary]:
	return options.filter(func(option: Dictionary) -> bool:
		return option["kind"] == &"cast_spell" and option["spell_id"] == spell_id)

func test_caster_scores_spell_options_with_breakdowns() -> void:
	var state: GameState = make_state({"caster": caster(Vector3.ZERO), "h": enemy(Vector3(0, 0, -8), 25)})
	var options: Array[Dictionary] = UtilityAI.consider(state, "caster")
	assert_false(spell_options(options, "fire_bolt").is_empty())
	assert_false(spell_options(options, "magic_missile").is_empty())
	var bolt: Dictionary = spell_options(options, "fire_bolt")[0]
	assert_almost_eq(float(bolt["breakdown"]["hit_chance"]), 0.65, 0.001, "+4 vs AC 12")
	assert_true(UtilityAI.command_for(bolt, "caster") is CastSpellCommand)

func test_magic_missile_finishes_a_low_target_that_fire_bolt_might_miss() -> void:
	var state: GameState = make_state({"caster": caster(Vector3.ZERO), "h": enemy(Vector3(0, 0, -8), 5)})
	var command: Command = UtilityAI.choose(state, "caster")
	assert_true(command is CastSpellCommand)
	assert_eq((command as CastSpellCommand).spell_id, "magic_missile")

func test_burning_hands_is_never_aimed_through_an_ally() -> void:
	var friend: Dictionary = enemy(Vector3(0.3, 0, -2), 7)
	friend["team"] = "enemy"
	var state: GameState = make_state({"caster": caster(Vector3.ZERO), "h": enemy(Vector3(0, 0, -3), 9),
		"friend": friend})
	var options: Array[Dictionary] = UtilityAI.consider(state, "caster")
	var hands: Array[Dictionary] = spell_options(options, "burning_hands")
	for option: Dictionary in hands:
		if float(option["breakdown"].get("allies_hit", 0.0)) > 0.0:
			assert_lt(float(option["score"]), 0.0, "an area that catches an ally scores negative")
	var command: Command = UtilityAI.choose(state, "caster")
	if command is CastSpellCommand:
		var cast: CastSpellCommand = command as CastSpellCommand
		if cast.spell_id == "burning_hands":
			var preview: Dictionary = SpellResolver.preview(state, "caster", "burning_hands", 0, [], cast.point)
			for target: Dictionary in preview["targets"]:
				assert_false(bool(target["ally"]), "AI must not burn its ally")

func test_burning_hands_is_chosen_against_a_clustered_group_without_allies() -> void:
	var state: GameState = make_state({"caster": caster(Vector3.ZERO), "h": enemy(Vector3(0, 0, -2.5), 9),
		"i": enemy(Vector3(0.8, 0, -3.2), 9), "j": enemy(Vector3(-0.8, 0, -3.2), 9)})
	var command: Command = UtilityAI.choose(state, "caster")
	assert_true(command is CastSpellCommand)
	assert_eq((command as CastSpellCommand).spell_id, "burning_hands")

func test_no_slots_means_cantrips_only() -> void:
	var record: Dictionary = caster(Vector3.ZERO)
	record["spell_slots"] = [0]
	var state: GameState = make_state({"caster": record, "h": enemy(Vector3(0, 0, -8), 5)})
	var options: Array[Dictionary] = UtilityAI.consider(state, "caster")
	assert_true(spell_options(options, "magic_missile").is_empty())
	assert_false(spell_options(options, "fire_bolt").is_empty())

func test_spell_ai_is_read_only_and_rng_free() -> void:
	var state: GameState = make_state({"caster": caster(Vector3.ZERO), "h": enemy(Vector3(0, 0, -3), 9),
		"i": enemy(Vector3(0, 0, -9), 20)})
	var before: Dictionary = state.actors.duplicate(true)
	var rng_state: int = Rng.rng.state
	var first: Array[Dictionary] = UtilityAI.consider(state, "caster")
	var second: Array[Dictionary] = UtilityAI.consider(state, "caster")
	assert_eq(state.actors, before)
	assert_eq(Rng.rng.state, rng_state)
	assert_eq(str(first[0]), str(second[0]))

func test_caster_keeps_spell_range_instead_of_closing_to_melee() -> void:
	CombatSpace.active = CombatSpace.new()
	var record: Dictionary = caster(Vector3.ZERO)
	record["action_available"] = false
	var state: GameState = make_state({"caster": record, "h": enemy(Vector3(0, 0, -12), 25)})
	var options: Array[Dictionary] = UtilityAI.consider(state, "caster")
	var moves: Array[Dictionary] = options.filter(func(option: Dictionary) -> bool: return option["kind"] == &"move")
	assert_false(moves.is_empty())
	var target: Vector3 = state.actors["h"]["position"]
	assert_gt((moves[0]["destination"] as Vector3).distance_to(target), 3.0, "no melee rush")
