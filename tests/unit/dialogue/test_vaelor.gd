extends GutTest
## Owner's Vaelor dialogue (14-10-2026): the crypt boss talks first, can be talked down,
## gives up, flees or fights; a hesitating Vaelor gives the hero a first strike.

func before_each() -> void:
	Rng.set_seed(7)

func _crypt() -> GameState:
	var state: GameState = GameState.new()
	var setup: LevelSetupCommand = LevelSetupCommand.new()
	assert_eq(setup.validate(state), OK)
	setup.apply(state)
	return state

func _vaelor() -> Dictionary:
	return DialogueData.load_dialogue("crypt_vaelor")

func _enter(state: GameState, node_id: String) -> Array[Dictionary]:
	return DialogueEffects.apply(state, _vaelor()["nodes"][node_id].get("effects", {}), "crypt_vaelor/" + node_id)

func _flag(state: GameState, name: String) -> Variant:
	return state.world["flags"].get(name)

func _hook(id: String) -> Dictionary:
	for hook: Dictionary in EncounterData.load_level().get("hooks", []):
		if hook["id"] == id:
			return hook
	return {}

func _quest(id: String, state: GameState) -> String:
	return String(QuestLog.status(QuestLog.load_quest(id), state).get("state", ""))

func test_vaelor_is_the_shrine_boss_and_speaks_first() -> void:
	var state: GameState = _crypt()
	var priest: Dictionary = state.world["dormant"]["shrine"]["cult_priest"]
	assert_eq(priest["hook"], "crypt_vaelor", "The hook figure is the boss")
	assert_eq(priest["name_key"], "NPC_VAELOR")
	var level: Dictionary = EncounterData.load_level()
	assert_false(EncounterData.notices(level, "shrine", priest, priest["position"], priest["position"]),
		"Only the conversation starts the boss fight")
	var hook: Dictionary = _hook("crypt_vaelor")
	assert_true(DialogueData.conditions_met(hook["approach_if"], state))
	assert_eq(DialogueData.start_node(_vaelor(), state), "opening")
	_enter(state, "opening")
	assert_false(DialogueData.conditions_met(hook["approach_if"], state), "Opens by itself only once")
	assert_eq(DialogueData.start_node(_vaelor(), state), "again")

func test_hesitation_gives_a_first_strike() -> void:
	var state: GameState = _crypt()
	_enter(state, "hesitates")
	_enter(state, "fight")
	var trigger: EncounterTriggerCommand = EncounterTriggerCommand.new("shrine")
	assert_eq(trigger.validate(state), OK)
	trigger.apply(state)
	assert_false(DialogueData.is_set(_flag(state, "shrine_first_strike")), "Used up")
	assert_true(ActiveEffects.has_kind(state.actors["hero"], "first_strike"))
	state.actors["hero"]["position"] = state.actors["cult_priest"]["position"] + Vector3(0.0, 0.0, 1.2)
	var preview: Dictionary = CombatRules.attack_preview(state, "hero", "cult_priest", Vector3.INF, state.actors["hero"]["weapon"])
	assert_true(&"first_strike" in preview["advantages"])
	ActiveEffects.consume_attack_riders(state.actors["hero"])
	assert_false(ActiveEffects.has_kind(state.actors["hero"], "first_strike"), "Only the first attack")

func test_unused_first_strike_ends_with_the_fight() -> void:
	var state: GameState = _crypt()
	_enter(state, "ambush")
	EncounterTriggerCommand.new("shrine").apply(state)
	StartCombatCommand.new().apply(state)
	for id: String in state.actors:
		if state.actors[id].get("team") == "enemy":
			state.actors[id]["hp"] = 0
	CombatRules.check_combat_end(state)
	assert_eq(state.mode, &"exploration")
	assert_false(ActiveEffects.has_kind(state.actors["hero"], "first_strike"))

func test_defeating_vaelor_in_battle_sets_his_outcome() -> void:
	var state: GameState = _crypt()
	_enter(state, "fight")
	EncounterTriggerCommand.new("shrine").apply(state)
	for id: String in state.actors:
		if state.actors[id].get("team") == "enemy":
			state.actors[id]["hp"] = 0
	var award: AwardVictoryXpCommand = AwardVictoryXpCommand.new()
	assert_eq(award.validate(state), OK)
	award.apply(state)
	assert_eq(_flag(state, "vaelor_outcome"), "killed")
	assert_true(_flag(state, "defeated_cult_priest"))
	assert_true(_flag(state, "vaelor_manuscript_found"), "Lyra's camp event can follow")
	assert_eq(_quest("crypt_cult", state), "done")

func test_surrender_disbands_the_cultists_and_leads_to_trial() -> void:
	var state: GameState = _crypt()
	var events: Array[Dictionary] = _enter(state, "kneels")
	assert_false((state.world["dormant"] as Dictionary).has("shrine"), "The cultists lay down their arms")
	assert_eq(_flag(state, "shrine_fight"), "disbanded")
	assert_eq(events.filter(func(event: Dictionary) -> bool: return event["type"] == "encounter_disbanded").size(), 1)
	assert_eq(DialogueData.start_node(_vaelor(), state), "resolution_more")
	_enter(state, "trial")
	assert_eq(_flag(state, "vaelor_outcome"), "captured")
	assert_eq(DialogueData.start_node(_vaelor(), state), "bound")
	assert_false(DialogueData.conditions_met(_hook("crypt_vaelor")["hide_if"], state), "He waits bound")
	assert_eq(_quest("crypt_cult", state), "done")
	assert_eq(_quest("the_fallen_priest", state), "active")

func test_fleeing_vaelor_leaves_the_crypt() -> void:
	var state: GameState = _crypt()
	_enter(state, "gallows")
	_enter(state, "escaped")
	assert_eq(_flag(state, "vaelor_outcome"), "escaped")
	assert_true(DialogueData.conditions_met(_hook("crypt_vaelor")["hide_if"], state))

func test_self_sacrifice_breaks_the_stone() -> void:
	var state: GameState = _crypt()
	_enter(state, "self_sacrifice")
	assert_eq(_flag(state, "vaelor_outcome"), "ritual_sacrifice")
	assert_eq(_flag(state, "vaelor_ritual_stone"), "destroyed")
	assert_true(EquipmentRules.count(state.actors["hero"], "vaelor_key") > 0, "Thomas's cell can be opened")
	assert_true(DialogueData.conditions_met(_hook("crypt_vaelor")["hide_if"], state))

func test_the_last_sacrifice_needs_thomas() -> void:
	var state: GameState = _crypt()
	_enter(state, "pact")
	assert_eq(DialogueData.start_node(_vaelor(), state), "pact_wait")
	assert_eq(_quest("last_sacrifice", state), "active")
	assert_false(0 in DialogueData.available_choices(_vaelor(), "pact_wait", state), "Nobody to hand over")
	state.world["flags"]["thomas_status"] = "guide"
	state.world["flags"]["crypt_prisoner_key_hint"] = true
	assert_true(0 in DialogueData.available_choices(_vaelor(), "pact_wait", state))
	_enter(state, "ritual_completed")
	assert_eq(_flag(state, "thomas_status"), "dead")
	assert_eq(_quest("last_sacrifice", state), "done")
	assert_eq(_quest("crypt_prisoner", state), "failed")

func test_two_provocations_end_the_talk() -> void:
	var state: GameState = _crypt()
	_enter(state, "phil_careful")
	var calm: Array = DialogueData.available_choices(_vaelor(), "phil_careful", state)
	assert_eq(_vaelor()["nodes"]["phil_careful"]["choices"][calm[0]]["next"], "philosophy_more")
	_enter(state, "fait_will")
	var furious: Array = DialogueData.available_choices(_vaelor(), "fait_will", state)
	assert_eq(_vaelor()["nodes"]["fait_will"]["choices"][furious[0]]["next"], "lashes_out")

func test_vaelor_knows_nothing_of_the_city_below() -> void:
	# Owner's rule 5: only the supreme ruler knows about the living city under Rabenfels.
	var text: String = JSON.stringify(_vaelor()).to_lower()
	for word: String in ["underground city", "city below us", "civilisation", "civilization", "unterstadt"]:
		assert_false(word in text, word)
