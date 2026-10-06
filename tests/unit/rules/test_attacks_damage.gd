extends GutTest

func before_each() -> void:
	Rng.set_seed(2503)

func test_attack_hits_at_ac_and_misses_below_except_natural_twenty() -> void:
	for index: int in range(200):
		var result: Attacks.Result = Attacks.resolve(14, [RuleModifier.new(3, &"str"), RuleModifier.new(2, &"proficiency")], Rng.rng)
		assert_eq(result.hit, result.roll.natural >= 9)
		assert_eq(result.critical, result.roll.natural_20)

func test_natural_one_always_misses_and_twenty_hits_any_ac() -> void:
	var saw_one: bool = false
	var saw_twenty: bool = false
	for index: int in range(300):
		var easy: Attacks.Result = Attacks.resolve(1, [RuleModifier.new(100, &"magic")], Rng.rng)
		if easy.roll.natural_1:
			saw_one = true
			assert_false(easy.hit)
		var hard: Attacks.Result = Attacks.resolve(1000, [], Rng.rng)
		if hard.roll.natural_20:
			saw_twenty = true
			assert_true(hard.hit)
			assert_true(hard.critical)
	assert_true(saw_one)
	assert_true(saw_twenty)

func test_critical_doubles_dice_not_modifiers_with_auditable_extra_group() -> void:
	var result: DamageRules.Result = DamageRules.roll("2d6+3", &"slashing", Rng.rng,
		[RuleModifier.new(2, &"magic_weapon")], true)
	assert_true(result.is_valid())
	assert_eq(result.roll.groups.size(), 2)
	assert_eq(result.roll.groups[0].values.size(), 2)
	assert_eq(result.roll.groups[1].values.size(), 2)
	assert_true(result.roll.groups[1].critical)
	assert_eq(result.roll.groups[1].source, &"critical")
	var dice_sum: int = 0
	for group: DiceResult.Group in result.roll.groups:
		for value: int in group.values:
			dice_sum += value
	assert_eq(result.total, dice_sum + 5)

func test_damage_types_resistance_rounding_vulnerability_and_immunity() -> void:
	assert_eq(DamageRules.TYPES.size(), 13)
	for damage_type: StringName in DamageRules.TYPES:
		var defenses: DamageRules.Defenses = DamageRules.Defenses.new()
		defenses.resistances = [damage_type, damage_type]
		assert_eq(DamageRules.apply(7, damage_type, defenses).total, 3)
		defenses.vulnerabilities = [damage_type, damage_type]
		# Resistance precedes vulnerability: 7 -> 3 -> 6, NOT 7.
		var result: DamageRules.Result = DamageRules.apply(7, damage_type, defenses)
		assert_eq(result.after_resistance, 3)
		assert_eq(result.total, 6)
		defenses.immunities = [damage_type]
		assert_eq(DamageRules.apply(7, damage_type, defenses).total, 0)
	assert_false(DamageRules.apply(7, &"unknown").is_valid())

func test_vulnerability_alone_and_defenses_do_not_affect_other_types() -> void:
	var defenses: DamageRules.Defenses = DamageRules.Defenses.new()
	defenses.vulnerabilities = [&"fire"]
	assert_eq(DamageRules.apply(7, &"fire", defenses).total, 14)
	assert_eq(DamageRules.apply(7, &"cold", defenses).total, 7)
	assert_eq(DamageRules.roll("1d6-20", &"fire", Rng.rng, [], false, defenses).total, 0)

func test_blinded_attackers_and_targets_cancel() -> void:
	var context: RollContext = RollContext.new()
	context.conditions.add(&"blinded")
	var target: ConditionState = ConditionState.new()
	target.add(&"blinded")
	assert_eq(Attacks.resolve(12, [], Rng.rng, context, target).roll.mode, &"normal")

func test_prone_target_advantage_is_distance_based_including_ranged_attacks() -> void:
	var target: ConditionState = ConditionState.new()
	target.add(&"prone")
	assert_eq(Attacks.resolve(12, [], Rng.rng, null, target, 1.5).roll.mode, &"advantage")
	assert_eq(Attacks.resolve(12, [], Rng.rng, null, target, 1.5001).roll.mode, &"disadvantage")
	var context: RollContext = RollContext.new()
	context.conditions.add(&"prone")
	assert_eq(Attacks.resolve(12, [], Rng.rng, context).roll.mode, &"disadvantage")

func test_unconscious_critical_only_on_hit_within_five_feet_and_prone_persists() -> void:
	var target: ConditionState = ConditionState.new()
	target.add(&"unconscious")
	var near: Attacks.Result = Attacks.resolve(-100, [], Rng.rng, null, target, 1.5)
	assert_true(near.hit)
	assert_true(near.critical)
	var far: Attacks.Result = Attacks.resolve(-100, [], Rng.rng, null, target, 3.0)
	assert_eq(far.roll.mode, &"normal") # unconscious advantage + prone far disadvantage
	assert_eq(far.critical, far.roll.natural_20)
	target.remove(&"unconscious")
	assert_true(target.has(&"prone"))
	assert_false(target.has(&"incapacitated"))

func test_stunned_cannot_attack_but_can_be_attacked_with_advantage() -> void:
	var context: RollContext = RollContext.new()
	context.conditions.add(&"stunned")
	var state: int = Rng.rng.state
	assert_eq(Attacks.resolve(10, [], Rng.rng, context).error, &"incapacitated")
	assert_eq(Rng.rng.state, state)
	assert_eq(Attacks.resolve(10, [], Rng.rng, null, context.conditions).roll.mode, &"advantage")

func test_invalid_damage_attack_inputs_leave_rng_unchanged() -> void:
	var state: int = Rng.rng.state
	assert_false(DamageRules.roll("1d6", &"invalid", Rng.rng).is_valid())
	assert_false(DamageRules.roll("bad", &"fire", Rng.rng).is_valid())
	assert_false(Attacks.resolve(10, [], Rng.rng, null, null, -1.0).is_valid())
	assert_false(Attacks.resolve(10, [], Rng.rng, null, null, NAN).is_valid())
	assert_eq(Rng.rng.state, state)
