extends GutTest
## Campaign package K3: travel between areas with per-area state, quests from flags.

const YARD: String = "res://tests/fixtures/travel_yard.json"

func before_each() -> void:
	Rng.set_seed(9)

func _yard_state() -> GameState:
	var state: GameState = GameState.new()
	var setup: LevelSetupCommand = LevelSetupCommand.new({}, YARD)
	assert_eq(setup.validate(state), OK)
	setup.apply(state)
	return state

## A crypt exit back to the yard, as the district thread will add one.
func _crypt_with_exit() -> void:
	var crypt: Dictionary = EncounterData.load_level()
	crypt["exits"] = [{"id": "crypt_to_yard", "position": [0.0, 0.0, 17.5], "to": YARD, "arrive": [1.0, 0.0, 0.0]}]
	EncounterData._cache[EncounterData.CRYPT_PATH] = crypt

func after_each() -> void:
	EncounterData._cache.erase(EncounterData.CRYPT_PATH)

func test_fixture_and_quests_are_valid() -> void:
	assert_eq(EncounterData.problems(EncounterData.load_level(YARD)), PackedStringArray())
	assert_true(QuestLog.all_ids().size() >= 2)
	for id: String in QuestLog.all_ids():
		var quest: Dictionary = QuestLog.load_quest(id)
		assert_eq(String(quest.get("id", "")), id)
		assert_eq(QuestLog.problems(quest), PackedStringArray(), id)

func test_exit_problems_are_reported() -> void:
	var level: Dictionary = EncounterData.load_level(YARD)
	level["exits"][0]["to"] = "res://nowhere.json"
	level["exits"][1].erase("arrive")
	assert_eq(EncounterData.problems(level).size(), 2)

func test_travel_needs_reach_and_conditions() -> void:
	var state: GameState = _yard_state()
	assert_eq(TravelCommand.new("yard_locked").validate(state), ERR_UNAVAILABLE)
	assert_eq(TravelCommand.new("nowhere").validate(state), ERR_DOES_NOT_EXIST)
	state.actors["hero"]["position"] = Vector3(10, 0, 0)
	assert_eq(TravelCommand.new("yard_to_crypt").validate(state), ERR_PARAMETER_RANGE_ERROR)
	state.actors["hero"]["position"] = Vector3(1, 0, 1)
	state.mode = &"combat"
	assert_eq(TravelCommand.new("yard_to_crypt").validate(state), ERR_UNAVAILABLE)

func test_areas_keep_their_state() -> void:
	_crypt_with_exit()
	var state: GameState = _yard_state()
	state.world["flags"]["talked"] = true
	state.loot_piles = {"pile_yard": {"position": Vector3(2, 0, 2), "items": ["dagger"], "gold": 0}}
	var travel: TravelCommand = TravelCommand.new("yard_to_crypt")
	assert_eq(travel.validate(state), OK)
	var result: Dictionary = travel.apply(state)
	assert_eq(result["events"][0], {"type": "travel", "from": "travel_yard", "to": "crypt", "exit_id": "yard_to_crypt"})
	assert_eq(state.world["level"], "crypt")
	assert_eq(state.world["dormant"].size(), 4, "The crypt starts fresh")
	assert_eq(state.actors["hero"]["position"], Vector3(0, 0, 17.5))
	assert_true(state.loot_piles.is_empty(), "Ground loot stays in its area")
	assert_true(bool(state.world["flags"]["visited_crypt"]))
	assert_true(bool(state.world["flags"]["talked"]), "Flags are global")
	# Change the crypt, leave and come back: the change is still there.
	EncounterTriggerCommand.new("hall", {"hall_cultist_b": Vector3(0, 0, 1)}).apply(state)
	state.world["trap_sprung"] = true
	assert_eq(state.actors.size(), 3)
	assert_eq(TravelCommand.new("crypt_to_yard").validate(state), OK)
	TravelCommand.new("crypt_to_yard").apply(state)
	assert_eq(state.world["level"], "travel_yard")
	assert_eq(state.actors.keys(), ["hero"], "Enemies stay behind")
	assert_eq(state.loot_piles.keys(), ["pile_yard"], "The yard's loot is back")
	assert_eq(state.actors["hero"]["position"], Vector3(1, 0, 0))
	TravelCommand.new("yard_to_crypt").apply(state)
	assert_eq(state.actors.size(), 3, "The awake cultists are still there")
	assert_true(bool(state.world["trap_sprung"]))
	assert_false(state.world["dormant"].has("hall"))
	assert_eq(state.world["areas"].keys(), ["travel_yard"])
	# Survives the ironman save.
	var restored: GameState = GameState.from_dict(state.to_dict())
	assert_eq(restored.world["areas"]["travel_yard"]["loot_piles"].keys(), ["pile_yard"])
	assert_eq(RunFlow.scene_for(restored), "res://scenes/levels/crypt/crypt.tscn")

func test_party_members_travel_along() -> void:
	var state: GameState = _yard_state()
	state.actors["companion"] = {"id": "companion", "team": "hero", "position": Vector3.ZERO, "hp": 5}
	state.actors["stranger"] = {"id": "stranger", "team": "enemy", "position": Vector3.ZERO, "hp": 5}
	TravelCommand.new("yard_to_crypt").apply(state)
	assert_true(state.actors.has("companion"))
	assert_false(state.actors.has("stranger"))
	assert_ne(state.actors["companion"]["position"], state.actors["hero"]["position"])

func test_quests_follow_flags() -> void:
	var state: GameState = _yard_state()
	var cult: Dictionary = QuestLog.load_quest("crypt_cult")
	assert_eq(QuestLog.status(cult, state)["state"], "hidden")
	var before: Dictionary = QuestLog.snapshot(state)
	state.world["flags"]["visited_crypt"] = true
	assert_eq(QuestLog.status(cult, state), {"state": "active", "text": String(cult["stages"][1]["text"])})
	assert_eq(QuestLog.changed(before, QuestLog.snapshot(state)), PackedStringArray(["crypt_cult"]))
	state.world["flags"]["crypt_knows_priest"] = true
	assert_eq(QuestLog.status(cult, state)["text"], String(cult["stages"][2]["text"]))
	state.world["flags"]["defeated_cult_priest"] = true
	assert_eq(QuestLog.status(cult, state)["state"], "done")
	var prisoner: Dictionary = QuestLog.load_quest("crypt_prisoner")
	state.world["flags"]["crypt_prisoner_key_hint"] = true
	state.world["flags"]["crypt_prisoner_freed"] = true
	state.world["flags"]["crypt_prisoner_refused"] = true
	assert_eq(QuestLog.status(prisoner, state)["state"], "failed", "Failing wins")
	assert_true(JournalPanel.text(state).contains(TranslationServer.translate(String(cult["title"]))))

func test_victory_sets_defeated_flags() -> void:
	var state: GameState = GameState.new()
	LevelSetupCommand.new().apply(state)
	EncounterTriggerCommand.new("hall", {"hall_cultist_b": Vector3(0, 0, 1)}).apply(state)
	for id: String in ["hall_cultist_a", "hall_cultist_b"]:
		state.actors[id]["hp"] = 0
	var award: AwardVictoryXpCommand = AwardVictoryXpCommand.new()
	assert_eq(award.validate(state), OK)
	award.apply(state)
	assert_true(bool(state.world["flags"]["defeated_hall_cultist_a"]))
	assert_true(bool(state.world["flags"]["defeated_hall_cultist_b"]))
	assert_true(bool(state.world["flags"]["visited_crypt"]))

func test_codec() -> void:
	var decoded: Command = CommandCodec.decode(JSON.parse_string(JSON.stringify(TravelCommand.new("yard_to_crypt").to_dict())))
	assert_not_null(decoded)
	assert_eq(decoded.to_dict(), TravelCommand.new("yard_to_crypt").to_dict())

func test_notice_board_starts_the_cult_quest() -> void:
	var state: GameState = GameState.new()
	LevelSetupCommand.new({}, "res://data/encounters/torviertel.json").apply(state)
	var cult: Dictionary = QuestLog.load_quest("crypt_cult")
	assert_eq(QuestLog.status(cult, state)["state"], "hidden")
	var start: DialogueStartCommand = DialogueStartCommand.new("torviertel_notice_board")
	assert_eq(start.validate(state), OK)
	start.apply(state)
	DialogueChooseCommand.new(0).apply(state)
	assert_eq(QuestLog.status(cult, state), {"state": "active", "text": String(cult["stages"][0]["text"])},
		"Any of its start conditions starts the quest")
	var board: Dictionary = {}
	for hook: Dictionary in EncounterData.load_level("res://data/encounters/torviertel.json")["hooks"]:
		if hook["id"] == "torviertel_notice_board":
			board = hook
	assert_eq(board.get("dialogue"), "torviertel_notice_board")

func test_any_condition() -> void:
	var state: GameState = GameState.new()
	state.world["flags"] = {"b": true}
	assert_true(DialogueData.conditions_met([{"any": [{"flag": "a"}, {"flag": "b"}]}], state))
	assert_false(DialogueData.conditions_met([{"any": [{"flag": "a"}, {"flag": "c"}]}], state))
	assert_eq(DialogueData.condition_problems([{"any": []}], "x").size(), 1)
