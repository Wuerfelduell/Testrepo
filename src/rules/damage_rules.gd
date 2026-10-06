class_name DamageRules
extends RefCounted

const TYPES: Array[StringName] = [&"acid", &"bludgeoning", &"cold", &"fire", &"force",
	&"lightning", &"necrotic", &"piercing", &"poison", &"psychic", &"radiant", &"slashing", &"thunder"]

class Defenses extends RefCounted:
	var resistances: Array[StringName] = []
	var vulnerabilities: Array[StringName] = []
	var immunities: Array[StringName] = []

class Result extends RefCounted:
	var error: StringName = &""
	var damage_type: StringName = &""
	var roll: DiceResult = null
	var raw: int = 0
	var after_resistance: int = 0
	var total: int = 0
	var immune: bool = false
	var resisted: bool = false
	var vulnerable: bool = false

	func is_valid() -> bool:
		return error == &""

static func apply(raw_damage: int, damage_type: StringName, defenses: Defenses = null) -> Result:
	var result: Result = Result.new()
	result.damage_type = damage_type
	result.raw = maxi(0, raw_damage)
	if not damage_type in TYPES:
		result.error = &"invalid_damage_type"
		return result
	var target: Defenses = defenses if defenses != null else Defenses.new()
	result.immune = damage_type in target.immunities
	result.resisted = damage_type in target.resistances
	result.vulnerable = damage_type in target.vulnerabilities
	result.after_resistance = floori(result.raw / 2.0) if result.resisted else result.raw
	result.total = result.after_resistance * (2 if result.vulnerable else 1)
	if result.immune:
		result.total = 0
	return result

static func roll(expression: String, damage_type: StringName, rng: RandomNumberGenerator,
		modifiers: Array[RuleModifier] = [], critical: bool = false,
		defenses: Defenses = null) -> Result:
	if not damage_type in TYPES:
		var invalid: Result = Result.new()
		invalid.error = &"invalid_damage_type"
		return invalid
	var dice_result: DiceResult = Dice.roll(expression, rng, modifiers, critical)
	if not dice_result.is_valid():
		var invalid: Result = Result.new()
		invalid.error = dice_result.error
		return invalid
	var result: Result = apply(dice_result.total, damage_type, defenses)
	result.roll = dice_result
	return result
