extends GutTest

const SCORES: Dictionary = {&"str": 16, &"dex": 14, &"con": 12, &"int": 10, &"wis": 8, &"cha": 18}

func before_each() -> void:
	Rng.set_seed(4711)

func test_modifiers_round_down_and_proficiency_boundaries() -> void:
	assert_eq(Abilities.modifier(1), -5)
	assert_eq(Abilities.modifier(9), -1)
	assert_eq(Abilities.modifier(10), 0)
	assert_eq(Abilities.modifier(19), 4)
	assert_eq(Abilities.modifier(30), 10)
	var expected: Array[int] = [2, 2, 2, 2, 3, 3, 3, 3, 4, 4]
	for level: int in range(1, 11):
		assert_eq(Abilities.proficiency_bonus(level), expected[level - 1])
	assert_eq(Abilities.proficiency_bonus(0), 0)
	assert_eq(Abilities.proficiency_bonus(11), 0)

func test_all_eighteen_skill_abilities_from_srd_page_9() -> void:
	var groups: Dictionary = {&"str": ["athletics"], &"dex": ["acrobatics", "sleight_of_hand", "stealth"],
		&"int": ["arcana", "history", "investigation", "nature", "religion"],
		&"wis": ["animal_handling", "insight", "medicine", "perception", "survival"],
		&"cha": ["deception", "intimidation", "performance", "persuasion"]}
	assert_eq(Abilities.SKILLS.size(), 18)
	for ability: StringName in groups:
		for skill: String in groups[ability]:
			assert_eq(Abilities.SKILLS[StringName(skill)], ability)

func test_ability_check_matches_dc_exactly_and_breaks_down_bonus() -> void:
	var probe: CheckResult = Checks.ability_check(&"str", 16, 0, Rng.rng, 5, true)
	Rng.set_seed(4711)
	var exact: CheckResult = Checks.ability_check(&"str", 16, probe.roll.total, Rng.rng, 5, true)
	assert_true(exact.success)
	assert_eq(exact.roll.modifiers[0].amount, 3)
	assert_eq(exact.roll.modifiers[1].amount, 3)
	Rng.set_seed(4711)
	assert_false(Checks.ability_check(&"str", 16, probe.roll.total + 1, Rng.rng, 5, true).success)

func test_skill_proficiency_expertise_and_explicit_ability_override() -> void:
	var result: CheckResult = Checks.skill_check(&"intimidation", SCORES, 10, Rng.rng, 9, true, null, true, &"str")
	assert_true(result.is_valid())
	assert_eq(result.ability, &"str")
	assert_eq(result.roll.modifiers[0].amount, 3)
	assert_eq(result.roll.modifiers[1].amount, 8)
	assert_eq(result.roll.modifiers[1].source, &"expertise")
	assert_eq(result.skill, &"intimidation")
	assert_false(Checks.skill_check(&"stealth", SCORES, 10, Rng.rng, 1, false, null, true).is_valid())

func test_saves_and_checks_have_no_automatic_natural_success_or_failure() -> void:
	var saw_twenty: bool = false
	var saw_one: bool = false
	for index: int in range(200):
		var hard: CheckResult = Checks.saving_throw(&"con", 10, 100, Rng.rng)
		assert_false(hard.success)
		saw_twenty = saw_twenty or hard.roll.natural_20
		var easy: CheckResult = Checks.ability_check(&"wis", 10, 1, Rng.rng)
		assert_true(easy.success)
		saw_one = saw_one or easy.roll.natural_1
	assert_true(saw_twenty)
	assert_true(saw_one)

func test_saving_throw_uses_ability_and_proficiency_once() -> void:
	var result: CheckResult = Checks.saving_throw(&"wis", 8, 12, Rng.rng, 10, true)
	assert_eq(result.roll.modifiers.size(), 2)
	assert_eq(result.roll.total, result.roll.natural - 1 + 4)

func test_poison_affects_checks_but_not_saves_and_frightened_needs_line_of_sight() -> void:
	var context: RollContext = RollContext.new()
	context.conditions.add(&"poisoned")
	assert_eq(Checks.ability_check(&"str", 10, 10, Rng.rng, 1, false, context).roll.mode, &"disadvantage")
	assert_eq(Checks.saving_throw(&"str", 10, 10, Rng.rng, 1, false, context).roll.mode, &"normal")
	context.conditions.remove(&"poisoned")
	context.conditions.add(&"frightened")
	assert_eq(Checks.ability_check(&"str", 10, 10, Rng.rng, 1, false, context).roll.mode, &"normal")
	context.fear_source_visible = true
	assert_eq(Checks.ability_check(&"str", 10, 10, Rng.rng, 1, false, context).roll.mode, &"disadvantage")

func test_blinded_only_auto_fails_sight_check_without_consuming_rng() -> void:
	var context: RollContext = RollContext.new()
	context.conditions.add(&"blinded")
	context.requires_sight = true
	var state: int = Rng.rng.state
	var result: CheckResult = Checks.ability_check(&"wis", 20, 1, Rng.rng, 1, false, context)
	assert_true(result.automatic_failure)
	assert_false(result.success)
	assert_null(result.roll)
	assert_eq(Rng.rng.state, state)
	context.requires_sight = false
	assert_not_null(Checks.ability_check(&"wis", 20, 1, Rng.rng, 1, false, context).roll)

func test_stunned_and_unconscious_auto_fail_only_strength_dexterity_saves() -> void:
	for condition: StringName in [&"stunned", &"unconscious"]:
		var context: RollContext = RollContext.new()
		context.conditions.add(condition)
		for ability: StringName in Abilities.IDS:
			var result: CheckResult = Checks.saving_throw(ability, 20, 1, Rng.rng, 1, false, context)
			assert_eq(result.automatic_failure, ability in [&"str", &"dex"])
			assert_eq(result.success, not ability in [&"str", &"dex"])

func test_restrained_dexterity_save_disadvantage_cancels_advantage() -> void:
	var context: RollContext = RollContext.new()
	context.conditions.add(&"restrained")
	assert_eq(Checks.saving_throw(&"dex", 10, 10, Rng.rng, 1, false, context).roll.mode, &"disadvantage")
	context.advantages.append(&"magic")
	assert_eq(Checks.saving_throw(&"dex", 10, 10, Rng.rng, 1, false, context).roll.mode, &"normal")

func test_invalid_inputs_are_rejected_without_rng_changes() -> void:
	var state: int = Rng.rng.state
	assert_false(Checks.ability_check(&"luck", 10, 10, Rng.rng).is_valid())
	assert_false(Checks.ability_check(&"str", 0, 10, Rng.rng).is_valid())
	assert_false(Checks.skill_check(&"flying", SCORES, 10, Rng.rng).is_valid())
	assert_false(Checks.skill_check(&"stealth", {}, 10, Rng.rng).is_valid())
	assert_false(Checks.saving_throw(&"str", 10, 10, Rng.rng, 11).is_valid())
	assert_eq(Rng.rng.state, state)
