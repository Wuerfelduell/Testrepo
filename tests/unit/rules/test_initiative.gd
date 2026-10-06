extends GutTest

func before_each() -> void:
	Rng.set_seed(1006)

func test_order_rolls_and_modifiers_are_replayable() -> void:
	var participants: Array[Initiative.Participant] = [Initiative.Participant.new(&"hero", 16),
		Initiative.Participant.new(&"enemy", 8), Initiative.Participant.new(&"ally", 12)]
	var first: Initiative.Result = Initiative.roll(participants, Rng.rng)
	Rng.set_seed(1006)
	var replay: Initiative.Result = Initiative.roll(participants, Rng.rng)
	assert_true(first.is_valid())
	assert_eq(first.ordered.size(), 3)
	for index: int in range(3):
		assert_eq(first.ordered[index].id, replay.ordered[index].id)
		assert_eq(first.ordered[index].roll.natural, replay.ordered[index].roll.natural)
		assert_eq(first.ordered[index].roll.modifiers[0].source, &"dex")
		if index > 0:
			assert_gte(first.ordered[index - 1].roll.total, first.ordered[index].roll.total)

func test_tied_totals_use_dexterity_score_before_randomness() -> void:
	# Predict two draws from the same fixed seed, then force equal totals via explicit bonuses.
	var a: int = Rng.randi_range(1, 20)
	var b: int = Rng.randi_range(1, 20)
	Rng.set_seed(1006)
	var low: Initiative.Participant = Initiative.Participant.new(&"low", 14)
	var high: Initiative.Participant = Initiative.Participant.new(&"high", 15)
	low.extra_modifiers = [RuleModifier.new(b - a, &"test_tie")]
	var result: Initiative.Result = Initiative.roll([low, high], Rng.rng)
	assert_eq(result.ordered[0].roll.total, result.ordered[1].roll.total)
	assert_eq(result.ordered[0].id, &"high")
	assert_true(result.tie_breaks.is_empty())

func test_equal_dexterity_ties_are_seeded_and_audited_not_random_comparators() -> void:
	var participants: Array[Initiative.Participant] = []
	for index: int in range(6):
		var value: int = Rng.randi_range(1, 20)
		var participant: Initiative.Participant = Initiative.Participant.new(StringName("actor_%d" % index), 10)
		participant.extra_modifiers = [RuleModifier.new(20 - value, &"test_tie")]
		participants.append(participant)
	Rng.set_seed(1006)
	var result: Initiative.Result = Initiative.roll(participants, Rng.rng)
	Rng.set_seed(1006)
	var replay: Initiative.Result = Initiative.roll(participants, Rng.rng)
	assert_eq(result.tie_breaks.size(), 5)
	assert_eq(result.tie_breaks, replay.tie_breaks)
	var ids: Array[StringName] = []
	for index: int in range(6):
		assert_eq(result.ordered[index].roll.total, 20)
		assert_eq(result.ordered[index].id, replay.ordered[index].id)
		assert_false(result.ordered[index].id in ids)
		ids.append(result.ordered[index].id)

func test_initiative_is_a_dexterity_check_and_incapacitation_adds_disadvantage() -> void:
	for condition: StringName in [&"poisoned", &"stunned", &"unconscious"]:
		var participant: Initiative.Participant = Initiative.Participant.new(&"hero", 10)
		participant.context.conditions.add(condition)
		assert_eq(Initiative.roll([participant], Rng.rng).ordered[0].roll.mode, &"disadvantage")
		participant.context.advantages.append(&"alert_effect")
		assert_eq(Initiative.roll([participant], Rng.rng).ordered[0].roll.mode, &"normal")

func test_empty_and_invalid_participants_do_not_consume_rng() -> void:
	var state: int = Rng.rng.state
	assert_true(Initiative.roll([], Rng.rng).is_valid())
	assert_false(Initiative.roll([Initiative.Participant.new(&"same"), Initiative.Participant.new(&"same")], Rng.rng).is_valid())
	assert_false(Initiative.roll([Initiative.Participant.new(&"bad", 0)], Rng.rng).is_valid())
	assert_false(Initiative.roll([null], Rng.rng).is_valid())
	assert_eq(Rng.rng.state, state)
