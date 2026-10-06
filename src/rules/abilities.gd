class_name Abilities
extends RefCounted

const IDS: Array[StringName] = [&"str", &"dex", &"con", &"int", &"wis", &"cha"]
const SKILLS: Dictionary[StringName, StringName] = {
	&"acrobatics": &"dex", &"animal_handling": &"wis", &"arcana": &"int",
	&"athletics": &"str", &"deception": &"cha", &"history": &"int",
	&"insight": &"wis", &"intimidation": &"cha", &"investigation": &"int",
	&"medicine": &"wis", &"nature": &"int", &"perception": &"wis",
	&"performance": &"cha", &"persuasion": &"cha", &"religion": &"int",
	&"sleight_of_hand": &"dex", &"stealth": &"dex", &"survival": &"wis",
}

static func modifier(score: int) -> int:
	return floori((score - 10) / 2.0)

static func proficiency_bonus(level: int) -> int:
	if level < 1 or level > 10:
		return 0
	return 2 + floori((level - 1) / 4.0)

static func valid_scores(scores: Dictionary) -> bool:
	for ability: StringName in IDS:
		if not scores.has(ability) or not scores[ability] is int:
			return false
		if scores[ability] < 1 or scores[ability] > 30:
			return false
	return scores.size() == IDS.size()

static func modifiers_for(score: int, ability: StringName, level: int,
		proficient: bool, expertise: bool = false) -> Array[RuleModifier]:
	var result: Array[RuleModifier] = [RuleModifier.new(modifier(score), ability)]
	if proficient:
		result.append(RuleModifier.new(proficiency_bonus(level) * (2 if expertise else 1),
			&"expertise" if expertise else &"proficiency"))
	return result
