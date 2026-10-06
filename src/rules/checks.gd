class_name Checks
extends RefCounted

static func ability_check(ability: StringName, score: int, dc: int,
		rng: RandomNumberGenerator, level: int = 1, proficient: bool = false,
		context: RollContext = null, expertise: bool = false) -> CheckResult:
	return _resolve(&"ability_check", ability, score, dc, rng, level, proficient, context, expertise)

static func skill_check(skill: StringName, scores: Dictionary, dc: int,
		rng: RandomNumberGenerator, level: int = 1, proficient: bool = false,
		context: RollContext = null, expertise: bool = false,
		ability_override: StringName = &"") -> CheckResult:
	if not Abilities.SKILLS.has(skill) or not Abilities.valid_scores(scores):
		var invalid: CheckResult = CheckResult.new()
		invalid.error = &"invalid_skill_input"
		return invalid
	var ability: StringName = Abilities.SKILLS[skill] if ability_override == &"" else ability_override
	if not ability in Abilities.IDS:
		var invalid: CheckResult = CheckResult.new()
		invalid.error = &"invalid_ability"
		return invalid
	var result: CheckResult = _resolve(&"skill_check", ability, scores[ability], dc, rng,
		level, proficient, context, expertise)
	result.skill = skill
	return result

static func saving_throw(ability: StringName, score: int, dc: int,
		rng: RandomNumberGenerator, level: int = 1, proficient: bool = false,
		context: RollContext = null) -> CheckResult:
	return _resolve(&"saving_throw", ability, score, dc, rng, level, proficient, context, false)

static func _resolve(kind: StringName, ability: StringName, score: int, dc: int,
		rng: RandomNumberGenerator, level: int, proficient: bool,
		context: RollContext, expertise: bool) -> CheckResult:
	var result: CheckResult = CheckResult.new()
	result.kind = kind
	result.ability = ability
	result.dc = dc
	if not ability in Abilities.IDS or score < 1 or score > 30 or level < 1 or level > 10 or \
			rng == null or (expertise and not proficient):
		result.error = &"invalid_check_input"
		return result
	var ctx: RollContext = context if context != null else RollContext.new()
	if not ctx.is_valid():
		result.error = &"invalid_context"
		return result
	var disadvantages: Array[StringName] = ctx.disadvantages.duplicate()
	if kind == &"saving_throw":
		if ctx.conditions.automatically_fails_save(ability):
			result.automatic_failure = true
			result.reason = &"unconscious" if ctx.conditions.has(&"unconscious") else &"stunned"
		elif ability == &"dex" and ctx.conditions.has(&"restrained"):
			disadvantages.append(&"restrained")
	else:
		if ctx.requires_sight and ctx.conditions.has(&"blinded"):
			result.automatic_failure = true
			result.reason = &"blinded"
		disadvantages.append_array(ctx.conditions.check_disadvantages(ctx.fear_source_visible))
	if result.automatic_failure:
		return result
	result.roll = Dice.d20(rng, Abilities.modifiers_for(score, ability, level, proficient, expertise),
		ctx.advantages, disadvantages)
	result.error = result.roll.error
	result.success = result.roll.is_valid() and result.roll.total >= dc
	return result
