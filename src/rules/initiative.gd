class_name Initiative
extends RefCounted
## DEX-score then random tie-break is the explicit project adaptation in prompt 03.
## Never draw randomness inside a sorting comparator.

class Participant extends RefCounted:
	var id: StringName = &""
	var dexterity: int = 10
	var context: RollContext = RollContext.new()
	var extra_modifiers: Array[RuleModifier] = []

	func _init(actor_id: StringName = &"", dex_score: int = 10) -> void:
		id = actor_id
		dexterity = dex_score

class Entry extends RefCounted:
	var id: StringName = &""
	var dexterity: int = 10
	var roll: DiceResult = null

class Result extends RefCounted:
	var error: StringName = &""
	var ordered: Array[Entry] = []
	var tie_breaks: Array[Dictionary] = []

	func is_valid() -> bool:
		return error == &""

static func roll(participants: Array[Participant], rng: RandomNumberGenerator) -> Result:
	var result: Result = Result.new()
	var ids: Array[StringName] = []
	# Validate the complete request before consuming any RNG state.
	for participant: Participant in participants:
		if participant == null or participant.id == &"" or participant.id in ids or \
				participant.dexterity < 1 or participant.dexterity > 30 or \
				participant.context == null or not participant.context.is_valid() or \
				not Dice.valid_modifiers(participant.extra_modifiers):
			result.error = &"invalid_initiative_input"
			return result
		ids.append(participant.id)
	if rng == null:
		result.error = &"invalid_rng"
		return result
	for participant: Participant in participants:
		var entry: Entry = Entry.new()
		entry.id = participant.id
		entry.dexterity = participant.dexterity
		var modifiers: Array[RuleModifier] = [RuleModifier.new(Abilities.modifier(entry.dexterity), &"dex")]
		modifiers.append_array(participant.extra_modifiers)
		var ctx: RollContext = participant.context
		var disadvantages: Array[StringName] = ctx.disadvantages.duplicate()
		disadvantages.append_array(ctx.conditions.check_disadvantages(ctx.fear_source_visible))
		if ctx.conditions.has(&"incapacitated"):
			disadvantages.append(&"incapacitated")
		entry.roll = Dice.d20(rng, modifiers, ctx.advantages, disadvantages)
		result.ordered.append(entry)
	result.ordered.sort_custom(_before)
	var start: int = 0
	while start < result.ordered.size():
		var end: int = start + 1
		while end < result.ordered.size() and \
				result.ordered[start].roll.total == result.ordered[end].roll.total and \
				result.ordered[start].dexterity == result.ordered[end].dexterity:
			end += 1
		for index: int in range(end - 1, start, -1):
			var selected: int = rng.randi_range(start, index)
			result.tie_breaks.append({"from": index, "selected": selected,
				"actor_a": result.ordered[index].id, "actor_b": result.ordered[selected].id})
			var temp: Entry = result.ordered[index]
			result.ordered[index] = result.ordered[selected]
			result.ordered[selected] = temp
		start = end
	return result

static func _before(left: Entry, right: Entry) -> bool:
	if left.roll.total != right.roll.total:
		return left.roll.total > right.roll.total
	if left.dexterity != right.dexterity:
		return left.dexterity > right.dexterity
	return String(left.id) < String(right.id)
