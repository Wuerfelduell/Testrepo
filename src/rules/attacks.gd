class_name Attacks
extends RefCounted

class Result extends RefCounted:
	var error: StringName = &""
	var armor_class: int = 0
	var roll: DiceResult = null
	var hit: bool = false
	var critical: bool = false
	var critical_source: StringName = &""

	func is_valid() -> bool:
		return error == &""

static func resolve(armor_class: int, modifiers: Array[RuleModifier],
		rng: RandomNumberGenerator, attacker: RollContext = null,
		target: ConditionState = null, distance_m: float = 1.5) -> Result:
	var result: Result = Result.new()
	result.armor_class = armor_class
	var ctx: RollContext = attacker if attacker != null else RollContext.new()
	var defender: ConditionState = target if target != null else ConditionState.new()
	if not ctx.is_valid() or not is_finite(distance_m) or distance_m < 0.0 or \
			rng == null or not Dice.valid_modifiers(modifiers):
		result.error = &"invalid_attack_input"
		return result
	if not ctx.conditions.can_act():
		result.error = &"incapacitated"
		return result
	var advantages: Array[StringName] = ctx.advantages.duplicate()
	advantages.append_array(defender.incoming_advantages(distance_m))
	var disadvantages: Array[StringName] = ctx.disadvantages.duplicate()
	disadvantages.append_array(ctx.conditions.attack_disadvantages(ctx.fear_source_visible))
	disadvantages.append_array(defender.incoming_disadvantages(distance_m))
	result.roll = Dice.d20(rng, modifiers, advantages, disadvantages)
	result.error = result.roll.error
	if not result.roll.is_valid():
		return result
	result.hit = not result.roll.natural_1 and (result.roll.natural_20 or result.roll.total >= armor_class)
	result.critical = result.hit and (result.roll.natural_20 or \
		(defender.has(&"unconscious") and distance_m <= 1.5))
	if result.critical:
		result.critical_source = &"natural_20" if result.roll.natural_20 else &"unconscious_near"
	return result
