extends GutTest
## Character creation for M1: standard array by class priority, class default skills,
## looks from hero_looks.json or the fallback models, victory XP through the sheet.

func test_standard_array_assigned_by_class_priority() -> void:
	var fighter: Dictionary = HeroFactory.standard_scores("fighter")
	assert_eq(fighter, {&"str": 15, &"con": 14, &"dex": 13, &"wis": 12, &"int": 10, &"cha": 8})
	var wizard: Dictionary = HeroFactory.standard_scores("wizard")
	assert_eq(wizard[&"int"], 15)
	var values: Array = wizard.values()
	values.sort()
	assert_eq(values, [8, 10, 12, 13, 14, 15])

func test_fighter_and_wizard_records() -> void:
	var fighter: Dictionary = HeroFactory.build_record("fighter", HeroLooks.for_class("fighter", "male")[0], "  Aldric  ")
	assert_eq(fighter["name_key"], "Aldric")
	assert_eq(fighter["max_hp"], 12)
	assert_eq(fighter["ac"], 18, "Chain mail and shield")
	assert_eq(fighter["weapon"]["id"], "longsword")
	assert_eq(fighter["skill_proficiencies"], [&"athletics", &"perception", &"insight"])
	assert_true(HeroFactory.valid_record(fighter))
	var wizard: Dictionary = HeroFactory.build_record("wizard", HeroLooks.for_class("wizard", "female")[1], "Mira")
	assert_eq(wizard["max_hp"], 8)
	assert_eq(wizard["ac"], 11, "Unarmoured: 10 + Dex 13")
	assert_eq(wizard["weapon"]["damage_dice"], "1d6")
	assert_eq(wizard["class_id"], "wizard")
	assert_eq(wizard["body"], "female")
	assert_eq(wizard["xp"], 0)

func test_invalid_choices_build_nothing() -> void:
	var look: Dictionary = HeroLooks.for_class("fighter", "male")[0]
	assert_eq(HeroFactory.build_record("rogue", look, "X"), {}, "Not playable in M1")
	assert_eq(HeroFactory.build_record("fighter", look, "   "), {}, "A name is required")
	assert_eq(HeroFactory.build_record("fighter", {"scene": "res://missing.glb"}, "X"), {})
	assert_eq(HeroFactory.clean_name("x".repeat(60)).length(), HeroFactory.MAX_NAME_LENGTH)

func test_setup_command_uses_the_created_hero() -> void:
	var record: Dictionary = HeroFactory.build_record("wizard", HeroLooks.for_class("wizard", "male")[0], "Odo")
	var state: GameState = GameState.new()
	var command: SetupArenaCommand = SetupArenaCommand.new(record)
	assert_eq(command.validate(state), OK)
	command.apply(state)
	assert_eq(state.actors["hero"]["class_id"], "wizard")
	assert_eq(state.actors.size(), 4)
	var broken: Dictionary = record.duplicate(true)
	broken.erase("ability_scores")
	assert_eq(SetupArenaCommand.new(broken).validate(GameState.new()), ERR_INVALID_DATA)
	var default_state: GameState = GameState.new()
	SetupArenaCommand.new().apply(default_state)
	assert_eq(default_state.actors["hero"]["name_key"], "ACTOR_FIGHTER", "Test arena keeps its Fighter")

func test_fallback_looks_per_body() -> void:
	var male: Array[Dictionary] = HeroLooks.for_class("fighter", "male", "res://does_not_exist.json")
	var female: Array[Dictionary] = HeroLooks.for_class("wizard", "female", "res://does_not_exist.json")
	assert_eq(male.size(), 3)
	assert_eq(female.size(), 3)
	for look: Dictionary in male + female:
		assert_true(ResourceLoader.exists(look["scene"]), look["scene"])

func test_looks_file_is_read_leniently() -> void:
	var text: String = JSON.stringify({"looks": [
		{"class": "Wizard", "body": "F", "id": "robes", "scene": "res://assets/characters/female_ranger/model.glb"},
		{"class_id": "fighter", "sex": "male", "look_id": "plate", "scene_path": "res://assets/characters/male_peasant/model.glb"},
		{"class": "wizard", "body": "female", "scene": "res://assets/characters/missing/model.glb"},
		{"body": "male", "model": "res://assets/characters/male_ranger/model.glb"},
		"nonsense",
	]})
	var looks: Array[Dictionary] = HeroLooks.parse(text)
	assert_eq(looks.size(), 3, "Missing scenes and junk entries are skipped")
	assert_eq(looks[0], {"id": "robes", "class": "wizard", "body": "female",
		"scene": "res://assets/characters/female_ranger/model.glb"})
	assert_eq(looks[1]["class"], "fighter")
	assert_eq(looks[2]["class"], "", "No class means every class")
	assert_eq(looks[2]["id"], "male_ranger")
	assert_eq(HeroLooks.parse("not json"), [] as Array[Dictionary])

func test_victory_awards_srd_experience_once_through_the_sheet() -> void:
	var state: GameState = GameState.new()
	SetupArenaCommand.new(HeroFactory.build_record("fighter", HeroLooks.for_class("fighter", "male")[0], "A")).apply(state)
	var command: AwardVictoryXpCommand = AwardVictoryXpCommand.new()
	assert_eq(command.validate(state), ERR_UNAVAILABLE, "Enemies still alive")
	var expected: int = 0
	for id: String in state.actors:
		if state.actors[id]["team"] == "enemy":
			state.actors[id]["hp"] = 0
			expected += int(state.actors[id]["experience"])
	assert_eq(command.validate(state), OK)
	var result: Dictionary = command.apply(state)
	var event: Dictionary = result["events"][0]
	assert_eq(event["amount"], expected)
	assert_eq(event["reason_key"], AwardVictoryXpCommand.REASON_KEY)
	assert_eq(event["defeated"].size(), 3)
	assert_eq(state.actors["hero"]["xp"], expected)
	assert_eq(state.actors["hero"]["xp_history"].size(), 1)
	assert_eq(state.actors["hero"]["xp_history"][0]["reason"], AwardVictoryXpCommand.REASON_KEY)
	assert_eq(command.validate(state), ERR_ALREADY_EXISTS, "Each enemy pays out once")
	var rebuilt: CharacterSheet = AwardVictoryXpCommand.rebuild_sheet(state.actors["hero"])
	assert_eq(rebuilt.xp, expected, "History replays into a fresh sheet")

func test_level_up_reported_by_the_sheet() -> void:
	var state: GameState = GameState.new()
	SetupArenaCommand.new(HeroFactory.build_record("fighter", HeroLooks.for_class("fighter", "male")[0], "A")).apply(state)
	for id: String in state.actors:
		if state.actors[id]["team"] == "enemy":
			state.actors[id]["hp"] = 0
			state.actors[id]["experience"] = 100
	var event: Dictionary = AwardVictoryXpCommand.new().apply(state)["events"][0]
	assert_eq(event["gained_levels"], [2])
	assert_eq(state.actors["hero"]["level"], 2)
