class_name Dice
extends RefCounted
## No global RNG. Pass Rng.rng from the application boundary.
## Grammar: NdS followed by zero or more signed integer modifiers.
## Limits are input/resource guards, not additional game rules.

const MAX_DICE: int = 1000
const MAX_SIDES: int = 1000000
const MAX_MODIFIER: int = 1000000

static func parse(expression: String) -> Dictionary:
	if expression.length() > 256:
		return {"error": &"invalid_expression"}
	var pattern: RegEx = RegEx.new()
	pattern.compile("^([0-9]+)[dD]([0-9]+)((?:[+-][0-9]+)*)$")
	var match_result: RegExMatch = pattern.search(expression.strip_edges())
	if match_result == null:
		return {"error": &"invalid_expression"}
	var count_text: String = match_result.get_string(1)
	var sides_text: String = match_result.get_string(2)
	if count_text.length() > 4 or sides_text.length() > 7:
		return {"error": &"dice_limit"}
	var count: int = count_text.to_int()
	var sides: int = sides_text.to_int()
	if count < 1 or count > MAX_DICE or sides < 2 or sides > MAX_SIDES:
		return {"error": &"dice_limit"}
	var modifiers: Array[RuleModifier] = []
	pattern.compile("[+-][0-9]+")
	for token: RegExMatch in pattern.search_all(match_result.get_string(3)):
		var number: String = token.get_string()
		if number.length() > 8 or absi(number.to_int()) > MAX_MODIFIER:
			return {"error": &"modifier_limit"}
		modifiers.append(RuleModifier.new(number.to_int(), &"expression"))
	return {"count": count, "sides": sides, "modifiers": modifiers}

static func roll(expression: String, rng: RandomNumberGenerator,
		modifiers: Array[RuleModifier] = [], critical: bool = false, minimum_die: int = 0) -> DiceResult:
	var result: DiceResult = DiceResult.new()
	result.expression = expression
	var parsed: Dictionary = parse(expression)
	result.error = parsed.get("error", &"")
	if not result.is_valid():
		return result
	if rng == null or not valid_modifiers(modifiers):
		result.error = &"invalid_roll_input"
		return result
	var count: int = parsed["count"]
	var sides: int = parsed["sides"]
	for repetition: int in range(2 if critical else 1):
		var group: DiceResult.Group = DiceResult.Group.new()
		group.sides = sides
		group.critical = repetition == 1
		group.source = &"critical" if group.critical else &"expression"
		for index: int in range(count):
			var value: int = rng.randi_range(1, sides)
			group.rolled.append(value)
			if value < minimum_die:
				# Treat a low die as the minimum (e.g. Great Weapon Fighting: 1 or 2 counts as 3).
				group.raised_indices.append(index)
				value = mini(minimum_die, sides)
			group.values.append(value)
			group.kept_indices.append(index)
			result.total += value
		result.groups.append(group)
	result.add_modifiers(parsed["modifiers"])
	result.add_modifiers(modifiers)
	if count == 1 and sides == 20 and not critical:
		result.record_natural(result.groups[0].values[0])
	return result

static func d20(rng: RandomNumberGenerator, modifiers: Array[RuleModifier] = [],
		advantages: Array[StringName] = [], disadvantages: Array[StringName] = [], minimum: int = 0) -> DiceResult:
	var result: DiceResult = DiceResult.new()
	result.expression = "1d20"
	if rng == null or not valid_modifiers(modifiers):
		result.error = &"invalid_roll_input"
		return result
	result.advantage_sources = advantages.duplicate()
	result.disadvantage_sources = disadvantages.duplicate()
	if not advantages.is_empty() and disadvantages.is_empty():
		result.mode = &"advantage"
	elif advantages.is_empty() and not disadvantages.is_empty():
		result.mode = &"disadvantage"
	var group: DiceResult.Group = DiceResult.Group.new()
	group.sides = 20
	group.values.append(rng.randi_range(1, 20))
	var kept: int = 0
	if result.mode != &"normal":
		group.values.append(rng.randi_range(1, 20))
		if (result.mode == &"advantage" and group.values[1] > group.values[0]) or \
				(result.mode == &"disadvantage" and group.values[1] < group.values[0]):
			kept = 1
	group.kept_indices.append(kept)
	result.groups.append(group)
	result.total = group.values[kept]
	result.record_natural(result.total)
	if group.values[kept] < minimum:
		# Reliable Talent: the kept die counts as the minimum (shown as "7→10").
		group.rolled = group.values.duplicate()
		group.raised_indices.append(kept)
		group.values[kept] = mini(minimum, 20)
		result.total = group.values[kept]
	result.add_modifiers(modifiers)
	return result

static func valid_modifiers(modifiers: Array[RuleModifier]) -> bool:
	if modifiers.size() > MAX_DICE:
		return false
	for modifier: RuleModifier in modifiers:
		if modifier == null or modifier.source == &"" or \
				modifier.amount < -MAX_MODIFIER or modifier.amount > MAX_MODIFIER:
			return false
	return true
