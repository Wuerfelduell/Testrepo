extends GutTest
## Owner's dialogues (14-10-2026): copper money, counters, items and harmless damage.

func before_each() -> void:
	Rng.set_seed(7)

func _fresh() -> GameState:
	var state: GameState = GameState.new()
	var setup: LevelSetupCommand = LevelSetupCommand.new()
	assert_eq(setup.validate(state), OK)
	setup.apply(state)
	return state

func test_money_is_copper_and_old_gold_still_counts() -> void:
	var actor: Dictionary = {"gold": 4}
	assert_eq(Money.copper(actor), 400, "Old saves kept whole gold pieces")
	assert_true(Money.change(actor, -5))
	assert_eq(actor, {"money": 395})
	assert_false(Money.change(actor, -396), "Cannot pay more than the purse holds")
	assert_eq(Money.copper(actor), 395)
	assert_eq(Money.format(435), "4 gp 3 sp 5 cp")
	assert_eq(Money.format(20), "2 sp")
	assert_eq(Money.format(0), "0 cp")

func test_starting_kit_money_is_copper() -> void:
	assert_false(_fresh().actors["hero"].has("gold"), "New heroes keep copper only")

func test_money_effect_and_unaffordable_answers_are_hidden() -> void:
	var state: GameState = _fresh()
	var hero: Dictionary = state.actors["hero"]
	Money.set_copper(hero, 7)
	var pay: Dictionary = {"money": -5}
	assert_true(DialogueData.affordable(pay, state))
	var events: Array[Dictionary] = DialogueEffects.apply(state, pay, "test/pay")
	assert_eq(Money.copper(hero), 2)
	assert_eq(events[0]["type"], "money_changed")
	assert_false(DialogueData.affordable(pay, state), "2 cp cannot pay 5 cp")
	assert_true(DialogueData.conditions_met([{"money": 2}], state))
	assert_false(DialogueData.conditions_met([{"money": 3}], state))
	DialogueEffects.apply(state, {"money": 3500}, "test/reward")
	assert_eq(Money.copper(hero), 3502)

func test_counters_add_and_compare() -> void:
	var state: GameState = _fresh()
	DialogueEffects.apply(state, {"add": {"garrik_relationship": -1}}, "a")
	DialogueEffects.apply(state, {"add": {"garrik_relationship": -2}}, "b")
	assert_eq(state.world["flags"]["garrik_relationship"], -3)
	assert_true(DialogueData.conditions_met([{"flag": "garrik_relationship", "max": -3}], state))
	assert_false(DialogueData.conditions_met([{"flag": "garrik_relationship", "min": -2}], state))
	assert_true(DialogueData.conditions_met([{"flag": "edrin_trust", "min": 0, "max": 0}], state), "Unset counts as 0")

func test_items_are_given_and_taken() -> void:
	var state: GameState = _fresh()
	var hero: Dictionary = state.actors["hero"]
	assert_false(DialogueData.conditions_met([{"item": "wanted_poster"}], state))
	assert_false(DialogueData.affordable({"item": {"wanted_poster": -1}}, state))
	DialogueEffects.apply(state, {"item": {"wanted_poster": 1}}, "a")
	assert_eq(EquipmentRules.count(hero, "wanted_poster"), 1)
	assert_true(DialogueData.conditions_met([{"item": "wanted_poster"}], state))
	assert_true(DialogueData.conditions_met([{"item": "black_relic", "is": false}], state))
	DialogueEffects.apply(state, {"item": {"wanted_poster": -1}}, "b")
	assert_eq(EquipmentRules.count(hero, "wanted_poster"), 0)

func test_damage_never_kills() -> void:
	var state: GameState = _fresh()
	var hero: Dictionary = state.actors["hero"]
	hero["hp"] = 2
	for index: int in range(5):
		DialogueEffects.apply(state, {"damage": {"dice": "1d4", "type": "bludgeoning"}}, "garrik/punch%d" % index)
	assert_eq(int(hero["hp"]), 1, "A blow in a conversation leaves at least 1 HP")
	assert_true(DialogueEffects.can_talk(state))

func test_new_effects_are_validated() -> void:
	var where: String = "test"
	assert_eq(DialogueData._effect_problems({"money": -5, "add": {"x": 1}, "item": {"wanted_poster": 1},
		"damage": {"dice": "1d4", "type": "necrotic"}, "fight": {"encounter": "gate_guards", "nonlethal": true}}, where),
		PackedStringArray())
	assert_eq(DialogueData._effect_problems({"money": "five", "add": {"x": "one"}, "item": {"rubber_duck": 1},
		"damage": {"dice": "lots", "type": "bludgeoning"}, "fight": {}}, where).size(), 5)
	assert_eq(DialogueData.condition_problems([{"min": 1}, {"flag": "x", "max": "high"}, {"item": "rubber_duck"}], where).size(), 3)
