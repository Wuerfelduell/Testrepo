extends GutTest
## Package 10: crypt data, dormant encounters, joiners, trap and the save field.

var level: Dictionary

func before_each() -> void:
	level = EncounterData.load_level()
	Rng.set_seed(77)

func _fresh() -> GameState:
	var state: GameState = GameState.new()
	var setup: LevelSetupCommand = LevelSetupCommand.new()
	assert_eq(setup.validate(state), OK)
	setup.apply(state)
	return state

func test_crypt_data_is_valid_and_spawnable() -> void:
	assert_eq(EncounterData.problems(level), PackedStringArray())
	assert_eq(level["encounters"].size(), 4, "Three fights and the boss")
	var difficulties: Array = []
	for encounter: Dictionary in level["encounters"]:
		difficulties.append(encounter["difficulty"])
		for member: Dictionary in encounter["members"]:
			var record: Dictionary = EncounterData.member_record(member, encounter["id"])
			assert_false(record.is_empty(), member["id"])
			assert_true(CombatRules.weapon_valid(record["weapon"]), member["id"])
			assert_true(ResourceLoader.exists(record["model"]), member["id"])
	assert_eq(difficulties, ["low", "moderate", "high", "boss"], "Rising difficulty")
	var boss: Dictionary = EncounterData.encounter(level, "shrine")
	assert_true(bool(boss.get("boss", false)))
	assert_eq(boss["members"][0]["monster"], "cult_priest")

func test_rising_difficulty_in_srd_experience() -> void:
	var totals: Array[int] = []
	for encounter: Dictionary in level["encounters"]:
		var total: int = 0
		for member: Dictionary in encounter["members"]:
			total += EncounterData.monster(member["monster"]).experience
		totals.append(total)
	for index: int in range(1, totals.size()):
		assert_gt(totals[index], totals[index - 1], "Encounter %d is harder than the one before" % index)

func test_problems_are_reported() -> void:
	var broken: Dictionary = level.duplicate(true)
	broken["encounters"][0]["members"][0]["monster"] = "dragon"
	broken["encounters"][1]["members"][0]["id"] = broken["encounters"][0]["members"][1]["id"]
	broken["encounters"][2]["joins"] = ["nowhere"]
	var found: PackedStringArray = EncounterData.problems(broken)
	assert_eq(found.size(), 3, ", ".join(found))

func test_setup_keeps_encounters_dormant() -> void:
	var state: GameState = _fresh()
	assert_eq(state.actors.keys(), ["hero"])
	assert_eq(state.actors["hero"]["position"], Vector3(0, 0, 17.5))
	assert_eq(state.world["dormant"].keys().size(), 4)
	assert_eq(state.world["dormant"]["hall"]["hall_cultist_a"]["pose"], "sleeping")
	assert_eq(LevelSetupCommand.new().validate(state), ERR_ALREADY_IN_USE, "Only on an empty run")

func test_trigger_only_brings_that_encounter_into_combat() -> void:
	var state: GameState = _fresh()
	var trigger: EncounterTriggerCommand = EncounterTriggerCommand.new("hall", {"hall_cultist_b": Vector3(0, 0, 1)})
	assert_eq(trigger.validate(state), OK)
	trigger.apply(state)
	assert_eq(state.actors.size(), 3)
	assert_false(state.world["dormant"].has("hall"))
	var start: StartCombatCommand = StartCombatCommand.new()
	assert_eq(start.validate(state), OK)
	start.apply(state)
	assert_eq(state.turn_order.size(), 3, "Other rooms do not roll initiative")
	assert_eq(EncounterTriggerCommand.new("hall").validate(state), ERR_DOES_NOT_EXIST, "Once only")

func test_patrol_position_must_lie_on_its_route() -> void:
	var state: GameState = _fresh()
	assert_eq(EncounterTriggerCommand.new("hall", {"hall_cultist_b": Vector3(0, 0, 6)}).validate(state), ERR_INVALID_DATA)
	assert_eq(EncounterTriggerCommand.new("hall", {"hall_cultist_a": Vector3(-9, 1, 6.5)}).validate(state), ERR_INVALID_DATA,
		"Only patrols move while unaware")
	var route: Array = state.world["dormant"]["hall"]["hall_cultist_b"]["patrol"]
	assert_eq(EncounterData.patrol_position(route, 0.0), Vector3(4.5, 0, 1))
	var halfway: Vector3 = EncounterData.patrol_position(route, 9.0 / EncounterData.PATROL_SPEED_M * 0.5)
	assert_almost_eq(halfway.x, 0.0, 0.01)
	assert_almost_eq(EncounterData.patrol_position(route, 9.0 / EncounterData.PATROL_SPEED_M * 2.0).x, 4.5, 0.01, "Walks back")

func test_joiners_enter_a_running_fight_at_the_end_of_the_order() -> void:
	var state: GameState = _fresh()
	EncounterTriggerCommand.new("ossuary").apply(state)
	StartCombatCommand.new().apply(state)
	state.pending = {}
	var before: Array[String] = state.turn_order.duplicate()
	var join: EncounterTriggerCommand = EncounterTriggerCommand.new("side_chamber")
	assert_eq(join.validate(state), OK)
	var result: Dictionary = join.apply(state)
	assert_eq(state.turn_order.slice(0, before.size()), before, "The running order is kept")
	assert_eq(state.turn_order.size(), before.size() + 3)
	var rolls: int = 0
	for event: Dictionary in result["events"]:
		rolls += 1 if event.get("kind") == "initiative" else 0
	assert_eq(rolls, 3, "Joiners roll visible initiative")
	assert_true(result["events"][0]["joined_combat"])

func test_perception_rules() -> void:
	var sleeper: Dictionary = {"pose": "sleeping"}
	var guard: Dictionary = {"pose": "guarding"}
	assert_true(EncounterData.notices(level, "hall", sleeper, Vector3(-9, 1, 6.5), Vector3(-6, 0, 6.5)))
	assert_false(EncounterData.notices(level, "hall", sleeper, Vector3(-9, 1, 6.5), Vector3(-3, 0, 6.5)))
	assert_true(EncounterData.notices(level, "side_chamber", guard, Vector3(7, 0, -9), Vector3(12, 0, -9)), "Same room")
	assert_false(EncounterData.notices(level, "side_chamber", guard, Vector3(7, 0, -9), Vector3(0, 0, -9)), "Corridor, 7 m away")
	assert_true(EncounterData.notices(level, "side_chamber", guard, Vector3(7, 0, -9), Vector3(3, 0, -9)), "Close in the passage")

func test_trap_springs_once_and_only_on_the_plate() -> void:
	var state: GameState = _fresh()
	assert_eq(LevelTrapCommand.new("corridor_darts").validate(state), ERR_INVALID_PARAMETER, "Hero is not on the plate")
	state.actors["hero"]["position"] = Vector3(-0.7, 0, -10)
	assert_eq(LevelTrapCommand.new("other").validate(state), ERR_UNAVAILABLE)
	var trap: LevelTrapCommand = LevelTrapCommand.new("corridor_darts")
	assert_eq(trap.validate(state), OK)
	var hp: int = int(state.actors["hero"]["hp"])
	var events: Array = trap.apply(state)["events"]
	assert_eq(events[1]["kind"], "save")
	assert_eq(events[1]["ability"], "dex")
	if bool(events[1]["success"]):
		assert_eq(int(state.actors["hero"]["hp"]), hp)
	else:
		assert_lt(int(state.actors["hero"]["hp"]), hp)
	assert_eq(trap.validate(state), ERR_UNAVAILABLE, "Sprung traps stay sprung")

func test_trap_can_kill_and_ends_the_run() -> void:
	var state: GameState = _fresh()
	state.actors["hero"]["position"] = Vector3(-0.7, 0, -10)
	state.actors["hero"]["hp"] = 1
	# Seeds until the save fails: deterministic with the fixed RNG sequence.
	for attempt: int in 50:
		Rng.set_seed(attempt)
		var copy: GameState = state.copy()
		var events: Array = LevelTrapCommand.new("corridor_darts").apply(copy)["events"]
		if not bool(events[1]["success"]):
			assert_eq(copy.mode, &"defeat")
			assert_eq(events[-1]["type"], "combat_end")
			return
	fail_test("No failed save in 50 seeds")

func test_world_survives_the_save_round_trip() -> void:
	var state: GameState = _fresh()
	EncounterTriggerCommand.new("hall").apply(state)
	var restored: GameState = GameState.from_dict(state.to_dict())
	assert_eq(restored.world["triggered"], ["hall"])
	assert_eq(restored.world["dormant"].keys().size(), 3)
	var old_save: Dictionary = state.to_dict()
	old_save.erase("world")
	assert_eq(GameState.from_dict(old_save).world, {}, "Saves from before the crypt still load")
	ResetRunCommand.new().apply(state)
	assert_eq(state.world, {})

func test_test_hero_wears_a_look_not_the_base_body() -> void:
	for class_id: StringName in [&"fighter", &"wizard"]:
		var model: String = HeroKit.create(class_id)["model"]
		assert_false(model.contains("superhero"), model)
		assert_eq(model, HeroLooks.for_class(String(class_id), "male")[0]["scene"])
