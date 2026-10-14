extends GutTest
## Fights started by a conversation, lethal and nonlethal (owner's dialogues, 14-10-2026).

const TOWN: String = "res://data/encounters/torviertel.json"

func before_each() -> void:
	Rng.set_seed(11)

func _town() -> GameState:
	var state: GameState = GameState.new()
	var setup: LevelSetupCommand = LevelSetupCommand.new({}, TOWN)
	assert_eq(setup.validate(state), OK)
	setup.apply(state)
	return state

func _start(state: GameState, nonlethal: bool) -> void:
	var events: Array[Dictionary] = DialogueEffects.apply(state,
		{"fight": {"encounter": "gate_guards", "nonlethal": nonlethal}}, "torviertel_gate_guard/knees")
	assert_eq(events[-1]["type"], "dialogue_fight")
	assert_eq(state.world["flags"]["gate_guards_fight"], "running")
	var trigger: EncounterTriggerCommand = EncounterTriggerCommand.new("gate_guards")
	assert_eq(trigger.validate(state), OK)
	trigger.apply(state)
	assert_false(state.world.has("dialogue_fight"))
	assert_eq(NonlethalFights.active(state), nonlethal)
	var start: StartCombatCommand = StartCombatCommand.new()
	assert_eq(start.validate(state), OK)
	start.apply(state)
	assert_eq(state.mode, &"combat")

func _knock_out(state: GameState, ids: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for id: String in ids:
		state.actors[id]["hp"] = 0
		events.append(NonlethalFights.fall_event(state, id, "gate_guard_a"))
	events.append_array(CombatRules.check_combat_end(state))
	return events

func test_dialogue_encounters_never_notice_the_hero() -> void:
	var level: Dictionary = EncounterData.load_level(TOWN)
	assert_eq(EncounterData.problems(level), PackedStringArray())
	var record: Dictionary = _town().world["dormant"]["gate_guards"]["gate_guard_a"]
	assert_false(EncounterData.notices(level, "gate_guards", record, record["position"], record["position"]))
	assert_eq(_town().world["dormant"]["gate_guards"]["garrik"]["name_key"], "NPC_GARRIK", "Named, Guard stat block")
	assert_eq(_town().world["dormant"]["gate_guards"]["garrik"]["hook"], "torviertel_gate_guard")

func test_fight_needs_a_waiting_encounter() -> void:
	var state: GameState = _town()
	assert_eq(DialogueEffects.apply(state, {"fight": {"encounter": "nowhere"}}, "x"), [] as Array[Dictionary])
	assert_false(state.world.has("dialogue_fight"))

func test_party_wins_a_nonlethal_fight() -> void:
	var state: GameState = _town()
	_start(state, true)
	var events: Array[Dictionary] = _knock_out(state, ["garrik", "gate_guard_a"])
	assert_eq(events[0]["type"], "knocked_out", "Nobody dies")
	assert_eq(state.mode, &"combat", "One guard still stands")
	events = _knock_out(state, ["gate_guard_b"])
	var ended: Array = events.filter(func(event: Dictionary) -> bool: return event["type"] == "nonlethal_end")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0]["winner"], "party")
	assert_eq(state.mode, &"exploration")
	assert_eq(state.world["flags"]["gate_guards_fight"], "won")
	assert_false(state.actors.has("garrik"), "The guards leave the fight")
	assert_eq((state.world["dormant"]["gate_guards"] as Dictionary).size(), 3, "...and wait at the gate again")
	assert_false(NonlethalFights.active(state))
	assert_eq(AwardVictoryXpCommand.new().validate(state), ERR_ALREADY_EXISTS, "No XP for a brawl")

func test_beaten_hero_stands_up() -> void:
	var state: GameState = _town()
	_start(state, true)
	_knock_out(state, ["hero"])
	assert_eq(state.mode, &"exploration", "Not a defeat: the run goes on")
	assert_eq(int(state.actors["hero"]["hp"]), 1)
	assert_false(state.actors["hero"].has("knocked_out"))
	assert_eq(state.world["flags"]["gate_guards_fight"], "lost")
	var garrik: Dictionary = DialogueData.load_dialogue("torviertel_gate_guard")
	assert_eq(DialogueData.start_node(garrik, state), "after_lost")

func test_lethal_fight_still_kills() -> void:
	var state: GameState = _town()
	_start(state, false)
	state.actors["hero"]["hp"] = 0
	assert_eq(NonlethalFights.fall_event(state, "hero", "garrik")["type"], "death")
	CombatRules.check_combat_end(state)
	assert_eq(state.mode, &"defeat")

func test_hook_hides_while_its_figure_fights() -> void:
	var state: GameState = _town()
	var hook: Dictionary = {}
	for entry: Dictionary in EncounterData.load_level(TOWN)["hooks"]:
		if entry["id"] == "torviertel_gate_guard":
			hook = entry
	assert_false(DialogueData.conditions_met(hook["hide_if"], state))
	_start(state, true)
	assert_true(DialogueData.conditions_met(hook["hide_if"], state))
	_knock_out(state, ["hero"])
	assert_false(DialogueData.conditions_met(hook["hide_if"], state), "Back after the fight")
