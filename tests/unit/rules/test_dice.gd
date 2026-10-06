extends GutTest

func before_each() -> void:
	Rng.set_seed(81732)

func test_parser_accepts_requested_notation_and_preserves_signed_modifiers() -> void:
	for expression: String in ["1d20+5", "2d6+3", "8d6", "1D8-2+1"]:
		assert_false(Dice.parse(expression).has("error"), expression)
	var parsed: Dictionary = Dice.parse("2d6+3-2")
	assert_eq(parsed["count"], 2)
	assert_eq(parsed["sides"], 6)
	assert_eq(parsed["modifiers"][0].amount, 3)
	assert_eq(parsed["modifiers"][1].amount, -2)

func test_invalid_expressions_do_not_consume_rng() -> void:
	for expression: String in ["", "d6", "1d0", "0d6", "-2d6", "1d6+", "2d6x", "1d20+1.5",
		"1001d6", "1d1000001", "1d6+1000001", "99999999999999999999d6"]:
		var state: int = Rng.rng.state
		assert_false(Dice.roll(expression, Rng.rng).is_valid(), expression)
		assert_eq(Rng.rng.state, state)

func test_dice_and_named_modifiers_reconstruct_total_and_are_copied() -> void:
	var strength: RuleModifier = RuleModifier.new(3, &"str")
	var result: DiceResult = Dice.roll("2d6+1", Rng.rng, [strength, RuleModifier.new(2, &"proficiency")])
	assert_true(result.is_valid())
	assert_eq(result.groups[0].values.size(), 2)
	assert_eq(result.modifiers.size(), 3)
	assert_eq(result.modifiers[1].source, &"str")
	assert_eq(result.modifiers[2].source, &"proficiency")
	assert_eq(result.total, result.groups[0].values[0] + result.groups[0].values[1] + 6)
	strength.amount = 90
	assert_eq(result.modifiers[1].amount, 3)

func test_seed_replays_complete_roll_and_advantage_keeps_both_values() -> void:
	var first: DiceResult = Dice.d20(Rng.rng, [], [&"help"])
	Rng.set_seed(81732)
	var second: DiceResult = Dice.d20(Rng.rng, [], [&"help", &"another_source"])
	assert_eq(first.groups[0].values, second.groups[0].values)
	assert_eq(first.groups[0].values.size(), 2)
	assert_eq(first.natural, maxi(first.groups[0].values[0], first.groups[0].values[1]))
	assert_eq(first.groups[0].kept_indices.size(), 1)
	assert_eq(first.mode, &"advantage")

func test_disadvantage_keeps_lower_value() -> void:
	var result: DiceResult = Dice.d20(Rng.rng, [], [], [&"poisoned"])
	assert_eq(result.natural, mini(result.groups[0].values[0], result.groups[0].values[1]))
	assert_eq(result.mode, &"disadvantage")

func test_any_advantage_and_disadvantage_cancel_with_one_rng_draw() -> void:
	var result: DiceResult = Dice.d20(Rng.rng, [], [&"a", &"b"], [&"c"])
	var state_after_cancelled: int = Rng.rng.state
	Rng.set_seed(81732)
	var plain: DiceResult = Dice.d20(Rng.rng)
	assert_eq(result.groups[0].values.size(), 1)
	assert_eq(result.mode, &"normal")
	assert_eq(result.natural, plain.natural)
	assert_eq(Rng.rng.state, state_after_cancelled)
	assert_eq(result.advantage_sources.size(), 2)
	assert_eq(result.disadvantage_sources.size(), 1)

func test_natural_flags_follow_kept_die_not_total_or_discarded_die() -> void:
	var saw_one: bool = false
	var saw_twenty: bool = false
	for index: int in range(200):
		var result: DiceResult = Dice.d20(Rng.rng, [RuleModifier.new(19, &"test")], [&"help"])
		assert_eq(result.natural_1, result.natural == 1)
		assert_eq(result.natural_20, result.natural == 20)
		saw_one = saw_one or 1 in result.groups[0].values
		saw_twenty = saw_twenty or result.natural_20
	assert_true(saw_one)
	assert_true(saw_twenty)
	assert_false(Dice.roll("1d6", Rng.rng).natural_1)

func test_null_rng_and_invalid_modifier_are_rejected_before_draw() -> void:
	assert_false(Dice.d20(null).is_valid())
	assert_false(Dice.roll("1d6", null).is_valid())
	var state: int = Rng.rng.state
	assert_false(Dice.d20(Rng.rng, [null]).is_valid())
	assert_false(Dice.roll("1d6", Rng.rng, [RuleModifier.new(1, &"")]).is_valid())
	assert_eq(Rng.rng.state, state)
