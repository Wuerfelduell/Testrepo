extends GutTest
## Campaign package 1: dialogue trees, conditions, checks once, XP once, codec and hooks.

func before_each() -> void:
	Rng.set_seed(5)

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

func test_every_dialogue_file_is_valid() -> void:
	var ids: PackedStringArray = DialogueData.all_ids()
	assert_true(ids.size() >= 3)
	for id: String in ids:
		var data: Dictionary = DialogueData.load_dialogue(id)
		assert_eq(String(data.get("id", "")), id, "File name matches id")
		assert_eq(DialogueData.problems(data), PackedStringArray(), id)

func test_crypt_hooks_point_to_existing_dialogues() -> void:
	for hook: Dictionary in EncounterData.load_level().get("hooks", []):
		assert_true(DialogueData.exists(String(hook.get("dialogue", ""))), String(hook["id"]))

func test_problems_are_reported() -> void:
	var broken: Dictionary = DialogueData.load_dialogue("crypt_prisoner").duplicate(true)
	broken["nodes"]["first"]["choices"][0]["next"] = "nowhere"
	broken["nodes"]["first"]["choices"][3]["check"]["skill"] = "juggling"
	broken["nodes"]["who"]["effects"] = {"gold": 5}
	broken["start"][0]["if"] = [{"mood": "sad"}]
	assert_eq(DialogueData.problems(broken).size(), 4, ", ".join(DialogueData.problems(broken)))

func test_start_follow_and_end() -> void:
	var state: GameState = _fresh()
	var start: Dictionary = _run(state, DialogueStartCommand.new("crypt_prisoner"))
	assert_eq(state.world["conversation"], {"id": "crypt_prisoner", "node": "first"})
	assert_eq(_events(start, "dialogue_node").size(), 1)
	assert_true(bool(state.world["flags"]["crypt_prisoner_key_hint"]), "Node effects apply on entering")
	assert_eq(DialogueStartCommand.new("crypt_inscription").validate(state), ERR_UNAVAILABLE, "One conversation at a time")
	_run(state, DialogueChooseCommand.new(2))
	assert_eq(state.world["conversation"]["node"], "what")
	_run(state, DialogueChooseCommand.new(2))
	assert_eq(state.world["conversation"]["node"], "thanks")
	assert_true(bool(state.world["flags"]["crypt_prisoner_promised"]))
	var ended: Dictionary = _run(state, DialogueEndCommand.new())
	assert_false(state.world.has("conversation"))
	assert_eq(_events(ended, "dialogue_end").size(), 1)
	_run(state, DialogueStartCommand.new("crypt_prisoner"))
	assert_eq(state.world["conversation"]["node"], "cell", "Start depends on flags")
	assert_false(2 in DialogueData.available_choices(DialogueData.load_dialogue("crypt_prisoner"), "cell", state),
		"The deal is made once")

func test_end_node_has_no_answers() -> void:
	var state: GameState = _fresh()
	_run(state, DialogueStartCommand.new("crypt_prisoner"))
	_run(state, DialogueChooseCommand.new(2))
	_run(state, DialogueChooseCommand.new(3))
	assert_eq(state.world["conversation"]["node"], "wait")
	assert_eq(DialogueChooseCommand.new(0).validate(state), ERR_INVALID_PARAMETER, "End node has no answers")

func test_choice_without_next_ends() -> void:
	var state: GameState = _fresh()
	_run(state, DialogueStartCommand.new("crypt_prisoner"))
	var result: Dictionary = _run(state, DialogueChooseCommand.new(7))
	assert_false(state.world.has("conversation"))
	assert_eq(_events(result, "dialogue_end").size(), 1)

func test_check_is_rolled_once_and_shown() -> void:
	var state: GameState = _fresh()
	_run(state, DialogueStartCommand.new("crypt_prisoner"))
	var result: Dictionary = _run(state, DialogueChooseCommand.new(3))
	var rolls: Array = _events(result, "roll")
	assert_eq(rolls.size(), 1)
	var roll: Dictionary = rolls[0]
	assert_eq(roll["kind"], "check")
	assert_eq(roll["skill"], "insight")
	assert_eq(int(roll["dc"]), 13)
	assert_eq(bool(roll["success"]), int(roll["roll"]["total"]) >= 13)
	assert_eq(state.world["conversation"]["node"], "despair" if bool(roll["success"]) else "unsure")
	_run(state, DialogueEndCommand.new())
	_run(state, DialogueStartCommand.new("crypt_prisoner"))
	assert_eq(state.world["conversation"]["node"], "cell")
	var answers: Array[int] = DialogueData.available_choices(DialogueData.load_dialogue("crypt_prisoner"), "cell", state)
	assert_eq(answers, [0, 1, 2, 4, 6, 7] as Array[int], "The rolled check is gone, also in the other node with its id")
	assert_eq(DialogueChooseCommand.new(3).validate(state), ERR_INVALID_PARAMETER)

func test_check_uses_proficiency() -> void:
	var hero: Dictionary = _fresh().actors["hero"]
	hero["skill_proficiencies"] = ["insight"]
	hero["ability_scores"] = {"str": 10, "dex": 10, "con": 10, "int": 10, "wis": 14, "cha": 10}
	var roll: Dictionary = DialogueChooseCommand.roll_check(hero, "insight", 10)
	var modifiers: int = 0
	for modifier: Dictionary in roll["roll"]["modifiers"]:
		modifiers += int(modifier["amount"])
	assert_eq(modifiers, 2 + int(hero.get("proficiency_bonus", 2)), "WIS +2 and proficiency")

func test_xp_is_paid_once_and_conditions_filter() -> void:
	var state: GameState = _fresh()
	var hero: Dictionary = state.actors["hero"]
	var prisoner: Dictionary = DialogueData.load_dialogue("crypt_prisoner")
	assert_false(5 in DialogueData.available_choices(prisoner, "first", state), "The key needs the dead priest")
	state.world["flags"]["defeated_cult_priest"] = true
	assert_true(5 in DialogueData.available_choices(prisoner, "first", state))
	_run(state, DialogueStartCommand.new("crypt_wounded_cultist"))
	var before: int = int(hero.get("xp", 0))
	var killed: Dictionary = _run(state, DialogueChooseCommand.new(5))
	assert_eq(int(hero["xp"]), before + 25)
	assert_eq(_events(killed, "xp_awarded")[0]["reason_key"], DialogueEffects.XP_REASON_KEY)
	assert_eq(state.world["flags"]["crypt_wounded_cultist"], "killed")
	assert_eq(int(state.world["flags"]["player_cruelty"]), 1)
	_run(state, DialogueEndCommand.new())
	assert_eq(DialogueEffects.apply(state, {"xp": 25}, "crypt_wounded_cultist/killed_silent"), [] as Array[Dictionary])
	assert_eq(int(hero["xp"]), before + 25)
	_run(state, DialogueStartCommand.new("crypt_wounded_cultist"))
	assert_eq(state.world["conversation"]["node"], "spared_again")

func test_hook_hide_conditions() -> void:
	var state: GameState = _fresh()
	var hook: Dictionary = EncounterData.load_level()["hooks"][1]
	assert_false(DialogueData.conditions_met(hook["hide_if"], state))
	state.world["flags"] = {"crypt_wounded_cultist": "spared"}
	assert_false(DialogueData.conditions_met(hook["hide_if"], state))
	state.world["flags"] = {"crypt_wounded_cultist": "killed"}
	assert_true(DialogueData.conditions_met(hook["hide_if"], state))
	state.world["flags"] = {"crypt_wounded_cultist": "freed"}
	assert_true(DialogueData.conditions_met(hook["hide_if"], state))

func test_no_talking_in_combat() -> void:
	var state: GameState = _fresh()
	state.mode = &"combat"
	assert_eq(DialogueStartCommand.new("crypt_prisoner").validate(state), ERR_UNAVAILABLE)
	assert_eq(DialogueStartCommand.new("missing").validate(GameState.new()), ERR_UNAVAILABLE)

func test_codec_and_save_round_trip() -> void:
	for command: Command in [DialogueStartCommand.new("crypt_prisoner"), DialogueChooseCommand.new(2), DialogueEndCommand.new()]:
		var decoded: Command = CommandCodec.decode(JSON.parse_string(JSON.stringify(command.to_dict())))
		assert_not_null(decoded)
		assert_eq(decoded.to_dict(), command.to_dict())
	var state: GameState = _fresh()
	_run(state, DialogueStartCommand.new("crypt_prisoner"))
	_run(state, DialogueChooseCommand.new(3))
	var restored: GameState = GameState.from_dict(state.to_dict())
	assert_eq(restored.world["dialogue_checks"], state.world["dialogue_checks"])
	assert_eq(restored.world["conversation"], state.world["conversation"])
