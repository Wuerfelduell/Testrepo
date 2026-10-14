extends GutTest
## Campaign package K4: companions join through dialogue, the party holds four at most,
## follows the leader, fights as allies, shares XP and survives the ironman save.

const TEST_PATH: String = "user://test_party.save"

func before_each() -> void:
	Rng.set_seed(11)
	SaveGame.path = TEST_PATH
	SaveGame.delete()

func after_each() -> void:
	SaveGame.delete()
	SaveGame.path = SaveGame.DEFAULT_PATH

func _fresh() -> GameState:
	var state: GameState = GameState.new()
	var setup: LevelSetupCommand = LevelSetupCommand.new()
	assert_eq(setup.validate(state), OK)
	setup.apply(state)
	return state

func _run(state: GameState, command: Command) -> Dictionary:
	assert_eq(command.validate(state), OK, str(command.to_dict()))
	return command.apply(state)

func _events(result: Dictionary, type: String) -> Array:
	return result.get("events", []).filter(func(event: Dictionary) -> bool: return event.get("type") == type)

## Lyra joins through her conversation (hub -> "someone who knows magic" -> "come along" ->
## accept her condition); the others join directly.
func _recruit(state: GameState, companion_id: String) -> Dictionary:
	if companion_id != "companion_lyra":
		return {"events": PartyRules.recruit(state, companion_id)}
	_run(state, DialogueStartCommand.new(companion_id))
	_run(state, DialogueChooseCommand.new(6))
	_run(state, DialogueChooseCommand.new(0))
	var result: Dictionary = _run(state, DialogueChooseCommand.new(0))
	_run(state, DialogueEndCommand.new())
	return result

func test_companion_definitions_are_valid() -> void:
	assert_eq(PartyRules.problems(), PackedStringArray())
	assert_eq(PartyRules.definitions().size(), 3, "Kael, Lyra and Seren")
	for id: String in PartyRules.definitions():
		var record: Dictionary = PartyRules.create_record(id)
		assert_eq(record["id"], id)
		assert_eq(record["team"], "hero")
		assert_true(bool(record["class_features_active"]))
		assert_true(EquipmentRules.has_inventory(record), id + " carries the class kit")
		assert_true(DialogueData.exists(String(PartyRules.definition(id)["dialogue"])))

func test_old_saves_have_a_party_of_one() -> void:
	var state: GameState = _fresh()
	assert_eq(PartyRules.members(state), ["hero"] as Array[String])
	assert_true(PartyRules.has_room(state))
	assert_true(PartyRules.is_member(state, "hero"))
	assert_false(PartyRules.is_member(state, "companion_lyra"))

func test_recruit_through_dialogue() -> void:
	var state: GameState = _fresh()
	var result: Dictionary = _recruit(state, "companion_lyra")
	assert_eq(_events(result, "party_joined").size(), 1)
	assert_eq(PartyRules.members(state), ["hero", "companion_lyra"] as Array[String])
	var companion: Dictionary = state.actors["companion_lyra"]
	assert_eq(companion["team"], "hero")
	assert_gt((companion["position"] as Vector3).distance_to(state.actors["hero"]["position"]), 0.8, "Not inside the hero")
	assert_lt((companion["position"] as Vector3).distance_to(state.actors["hero"]["position"]), 4.0, "Next to the hero")
	assert_true(DialogueData.conditions_met([{"in_party": "companion_lyra"}], state), "The hook hides")
	assert_true(DialogueData.conditions_met([{"in_party": "companion_kael", "is": false}], state))
	# Talking again cannot recruit twice.
	assert_eq(PartyRules.recruit_reason(state, "companion_lyra"), "PARTY_REASON_MEMBER")

func test_party_holds_four_at_most() -> void:
	var state: GameState = _fresh()
	for id: String in ["companion_lyra", "companion_kael", "companion_seren"]:
		_recruit(state, id)
	assert_eq(PartyRules.members(state).size(), PartyRules.MAX_SIZE)
	assert_false(PartyRules.has_room(state))
	assert_true(DialogueData.conditions_met([{"party_room": false}], state))
	# A full party offers only the "too many" answer.
	var data: Dictionary = DialogueData.load_dialogue("companion_lyra")
	assert_eq(DialogueData.available_choices(data, "hire", state), [1, 2, 5, 6] as Array[int])
	# Even a forced recruit is refused.
	state.world["party"].erase("companion_seren")
	state.actors.erase("companion_seren")
	_recruit(state, "companion_seren")
	assert_eq(PartyRules.members(state).size(), 4)
	var events: Array[Dictionary] = PartyRules.recruit(state, "companion_seren")
	assert_eq(String(events[0]["type"]), "party_refused")
	assert_eq(String(events[0]["reason_key"]), "PARTY_REASON_MEMBER")

func test_dismissed_companion_serenomes_back_as_they_were() -> void:
	var state: GameState = _fresh()
	_recruit(state, "companion_kael")
	state.actors["companion_kael"]["xp"] = 40
	state.actors["companion_kael"]["hp"] = 3
	var left: Array[Dictionary] = PartyRules.dismiss(state, "companion_kael")
	assert_eq(String(left[0]["type"]), "party_left")
	assert_false(state.actors.has("companion_kael"))
	assert_eq(PartyRules.members(state), ["hero"] as Array[String])
	PartyRules.recruit(state, "companion_kael")
	assert_eq(int(state.actors["companion_kael"]["xp"]), 40)
	assert_eq(int(state.actors["companion_kael"]["hp"]), 3)
	assert_eq(String(PartyRules.dismiss(state, "hero")[0]["type"]), "party_refused")

func test_dialogue_validation_knows_party_effects() -> void:
	var tree: Dictionary = {"id": "x", "speaker": "X", "start": [{"node": "a"}], "nodes": {
		"a": {"text": "t", "effects": {"recruit": "nobody"}, "choices": [{"text": "c", "if": [{"party_room": "yes"}]}]}}}
	var found: PackedStringArray = DialogueData.problems(tree)
	assert_eq(found.size(), 2, str(found))
	tree["nodes"]["a"]["effects"] = {"recruit": "companion_lyra", "dismiss": "companion_kael"}
	tree["nodes"]["a"]["choices"][0]["if"] = [{"party_room": true}, {"in_party": "companion_seren"}]
	assert_eq(DialogueData.problems(tree), PackedStringArray())

func test_party_follows_the_leader_out_of_combat() -> void:
	var state: GameState = _fresh()
	_recruit(state, "companion_lyra")
	_recruit(state, "companion_kael")
	var target: Vector3 = (state.actors["hero"]["position"] as Vector3) + Vector3(0, 0, -6)
	var result: Dictionary = _run(state, MoveCommand.new("hero", target))
	assert_eq(_events(result, "start_move").size(), 3, "Leader and two followers")
	assert_eq((state.pending["followers"] as Array).size(), 2)
	while not state.pending.is_empty():
		AdvanceCombatCommand.new(0.1).apply(state)
	assert_true((state.actors["hero"]["position"] as Vector3).is_equal_approx(target))
	for id: String in ["companion_lyra", "companion_kael"]:
		var distance: float = (state.actors[id]["position"] as Vector3).distance_to(target)
		assert_between(distance, PartyRules.SPOT_CLEARANCE_M, 3.5, id + " stands behind the leader")
	var spread: float = (state.actors["companion_lyra"]["position"] as Vector3).distance_to(state.actors["companion_kael"]["position"])
	assert_gt(spread, PartyRules.SPOT_CLEARANCE_M, "Followers do not stack")
	# A companion can lead as well; then the hero follows.
	var second: Vector3 = (state.actors["companion_lyra"]["position"] as Vector3) + Vector3(2, 0, 0)
	_run(state, MoveCommand.new("companion_lyra", second))
	var followers: Array = (state.pending["followers"] as Array).map(func(entry: Dictionary) -> String: return entry["actor_id"])
	assert_true("hero" in followers)

func test_companions_fight_on_the_hero_side() -> void:
	var state: GameState = _fresh()
	_recruit(state, "companion_lyra")
	var dormant: Dictionary = state.world["dormant"]
	var encounter: Dictionary = dormant[dormant.keys()[0]]
	var enemy: Dictionary = encounter[encounter.keys()[0]]
	enemy["position"] = Vector3(0, 0, 12)
	state.actors["enemy_1"] = enemy
	_run(state, StartCombatCommand.new())
	assert_true("companion_lyra" in state.turn_order, "Companions roll initiative")
	# A fallen companion does not end the run ...
	state.actors["companion_lyra"]["hp"] = 0
	CombatRules.check_combat_end(state)
	assert_eq(state.mode, &"combat")
	# ... but the hero's death does (permadeath).
	state.actors["hero"]["hp"] = 0
	CombatRules.check_combat_end(state)
	assert_eq(state.mode, &"defeat")

func test_companions_share_victory_and_dialogue_xp() -> void:
	var state: GameState = _fresh()
	_recruit(state, "companion_lyra")
	_recruit(state, "companion_kael")
	state.actors["companion_kael"]["hp"] = 0
	state.actors["enemy_1"] = {"id": "enemy_1", "team": "enemy", "hp": 0, "max_hp": 9, "experience": 50,
		"position": Vector3(0, 0, 12), "dex": 10, "name_key": "X"}
	var result: Dictionary = _run(state, AwardVictoryXpCommand.new())
	var award: Dictionary = _events(result, "xp_awarded")[0]
	assert_eq(int(state.actors["companion_lyra"]["xp"]), int(state.actors["hero"]["xp"]))
	assert_eq(int(state.actors["companion_lyra"]["xp"]), 50)
	assert_eq((award["shared"] as Array).size(), 1, "The fallen companion gets nothing")
	assert_eq(int(state.actors["companion_kael"].get("xp", 0)), 0)
	var events: Array[Dictionary] = DialogueEffects.apply(state, {"xp": 25}, "test/node")
	assert_eq(int(state.actors["companion_lyra"]["xp"]), 75)
	assert_eq((events[0]["shared"] as Array).size(), 1)

func test_party_survives_the_ironman_save() -> void:
	var state: GameState = _fresh()
	_recruit(state, "companion_lyra")
	_recruit(state, "companion_seren")
	PartyRules.dismiss(state, "companion_lyra")
	assert_eq(SaveGame.save(state, 7), OK)
	var loaded: SaveGame.LoadResult = SaveGame.load_save()
	assert_true(loaded.is_valid(), String(loaded.error))
	assert_eq(PartyRules.members(loaded.state), ["hero", "companion_seren"] as Array[String])
	assert_eq(loaded.state.actors["companion_seren"], state.actors["companion_seren"])
	assert_true((loaded.state.world["companions"] as Dictionary).has("companion_lyra"))
	PartyRules.recruit(loaded.state, "companion_lyra")
	assert_eq(PartyRules.members(loaded.state), ["hero", "companion_seren", "companion_lyra"] as Array[String])

func test_companions_are_the_owners_three() -> void:
	assert_eq(PartyRules.id_for("seren"), "companion_seren")
	assert_eq(PartyRules.short_name("companion_kael"), "kael")
	var seren: Dictionary = PartyRules.create_record("companion_seren")
	assert_eq(String(seren["species"]), "dark_elf")
	# Seren is a Rogue; until that class is playable she uses the Fighter rules.
	assert_eq(String(seren["class_id"]), PartyRules.class_for(PartyRules.definition("companion_seren")))
	assert_true(HeroFactory.is_playable(String(seren["class_id"])))

func test_kael_haggles_once_and_the_price_sticks() -> void:
	var state: GameState = _fresh()
	Money.set_copper(state.actors["hero"], 1000)
	_run(state, DialogueStartCommand.new("companion_kael"))
	_run(state, DialogueChooseCommand.new(0))
	var data: Dictionary = DialogueData.load_dialogue("companion_kael")
	assert_eq(DialogueData.available_choices(data, "hire", state), [0, 4, 5, 6, 8] as Array[int], "50 silver, haggle, duel, threaten")
	var result: Dictionary = _run(state, DialogueChooseCommand.new(4))
	var success: bool = bool(_events(result, "roll")[0]["success"])
	var price: int = 300 if success else 600
	assert_eq(DialogueData.number(DialogueData.flags(state)["kael_price"]), price)
	var choices: Array[int] = DialogueData.available_choices(data, "hire", state)
	assert_false(4 in choices, "One roll only")
	assert_false(0 in choices, "The old price is gone")
	_run(state, DialogueChooseCommand.new(2 if success else 1))
	assert_eq(Money.copper(state.actors["hero"]), 1000 - price)
	assert_true(PartyRules.is_member(state, "companion_kael"))

func test_reactions_move_loyalty_once_and_low_loyalty_leaves() -> void:
	var state: GameState = _fresh()
	_recruit(state, "companion_kael")
	var react: Dictionary = {"kael": {"text": "Hm.", "loyalty": -2}, "lyra": {"text": "Not here."}}
	var events: Array[Dictionary] = DialogueEffects.apply(state, {"react": react}, "test/a")
	assert_eq(events.size(), 1, "Only party members react")
	assert_eq(String(events[0]["type"]), "companion_reaction")
	assert_eq(int(events[0]["loyalty"]), -2)
	assert_eq(PartyRules.loyalty(state, "companion_kael"), -2)
	DialogueEffects.apply(state, {"react": react}, "test/a")
	assert_eq(PartyRules.loyalty(state, "companion_kael"), -2, "Repeating an answer does not count twice")
	events = DialogueEffects.apply(state, {"react": react}, "test/b")
	assert_eq(PartyRules.loyalty(state, "companion_kael"), -4)
	var left: Array = events.filter(func(event: Dictionary) -> bool: return event["type"] == "party_left")
	assert_eq(left.size(), 1, "Below -3 Kael leaves")
	assert_eq(String(left[0]["reason"]), "loyalty")
	assert_false(PartyRules.is_member(state, "companion_kael"))
	assert_true(DialogueData.conditions_met([{"flag": "kael_left"}], state), "His hook stays hidden")
	# Lyra has no leaves_below: she stays whatever happens.
	_recruit(state, "companion_lyra")
	DialogueEffects.apply(state, {"react": {"lyra": {"text": "x", "loyalty": -9}}}, "test/c")
	assert_true(PartyRules.is_member(state, "companion_lyra"))

func test_banter_plays_once_when_both_are_in_the_party() -> void:
	assert_eq(PartyRules.banter_problems(), PackedStringArray())
	var state: GameState = _fresh()
	_recruit(state, "companion_kael")
	assert_eq(PartyRules.next_banter(state, "rest"), "", "Lyra is not here")
	_recruit(state, "companion_lyra")
	assert_eq(PartyRules.next_banter(state, "arrive"), "")
	assert_eq(PartyRules.next_banter(state, "rest"), "banter_kael_lyra")
	_run(state, DialogueStartCommand.new("banter_kael_lyra"))
	var data: Dictionary = DialogueData.load_dialogue("banter_kael_lyra")
	assert_eq(DialogueData.speaker_name(data, "first"), "Kael Dorn")
	assert_eq(PartyRules.next_banter(state, "rest"), "", "Not while a conversation runs")
	_run(state, DialogueChooseCommand.new(0))
	var result: Dictionary = _run(state, DialogueChooseCommand.new(0))
	assert_eq(_events(result, "companion_reaction").size(), 2, "Taking sides: both react")
	assert_eq(PartyRules.loyalty(state, "companion_kael"), 1)
	assert_eq(PartyRules.loyalty(state, "companion_lyra"), -1)
	_run(state, DialogueEndCommand.new())
	assert_eq(PartyRules.next_banter(state, "rest"), "", "Each banter plays once")

func test_dialogue_validation_knows_reactions_and_speakers() -> void:
	var tree: Dictionary = {"id": "x", "speaker": "X", "start": [{"node": "a"}], "nodes": {
		"a": {"text": "t", "speaker": "nobody", "effects": {"react": {"ghost": {"text": "t"}, "kael": {"loyalty": 1}}}}}}
	assert_eq(DialogueData.problems(tree).size(), 3, str(DialogueData.problems(tree)))
	tree["nodes"]["a"] = {"text": "t", "speaker": "seren", "effects": {"react": {"kael": {"text": "t", "loyalty": 1}}}}
	assert_eq(DialogueData.problems(tree), PackedStringArray())
	assert_eq(DialogueData.speaker_name(tree, "a"), "Seren Nachtfall")
