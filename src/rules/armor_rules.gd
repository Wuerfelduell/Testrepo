class_name ArmorRules
extends RefCounted
## SRD 5.2 p. 92. No class feature AC formulas are silently enabled.

const ARMOR: Dictionary = {
	&"none": {"category": &"none", "base": 10, "dex_cap": 30, "strength": 0, "stealth": false},
	&"padded": {"category": &"light", "base": 11, "dex_cap": 30, "strength": 0, "stealth": true},
	&"leather": {"category": &"light", "base": 11, "dex_cap": 30, "strength": 0, "stealth": false},
	&"studded_leather": {"category": &"light", "base": 12, "dex_cap": 30, "strength": 0, "stealth": false},
	&"hide": {"category": &"medium", "base": 12, "dex_cap": 2, "strength": 0, "stealth": false},
	&"chain_shirt": {"category": &"medium", "base": 13, "dex_cap": 2, "strength": 0, "stealth": false},
	&"scale_mail": {"category": &"medium", "base": 14, "dex_cap": 2, "strength": 0, "stealth": true},
	&"breastplate": {"category": &"medium", "base": 14, "dex_cap": 2, "strength": 0, "stealth": false},
	&"half_plate": {"category": &"medium", "base": 15, "dex_cap": 2, "strength": 0, "stealth": true},
	&"ring_mail": {"category": &"heavy", "base": 14, "dex_cap": 0, "strength": 0, "stealth": true},
	&"chain_mail": {"category": &"heavy", "base": 16, "dex_cap": 0, "strength": 13, "stealth": true},
	&"splint": {"category": &"heavy", "base": 17, "dex_cap": 0, "strength": 15, "stealth": true},
	&"plate": {"category": &"heavy", "base": 18, "dex_cap": 0, "strength": 15, "stealth": true},
}

class Result extends RefCounted:
	var error: StringName = &""
	var armor_class: int = 0
	var breakdown: Array[RuleModifier] = []
	var speed_penalty_m: float = 0.0
	var stealth_disadvantage: bool = false
	var strength_dexterity_disadvantage: bool = false
	var can_cast_spells: bool = true
	var shield_effective: bool = false

	func is_valid() -> bool:
		return error == &""

static func calculate(armor: StringName, dexterity: int, strength: int,
		training: Array[StringName], shield: bool = false) -> Result:
	var result: Result = Result.new()
	if not ARMOR.has(armor) or dexterity < 1 or dexterity > 30 or strength < 1 or strength > 30:
		result.error = &"invalid_armor_input"
		return result
	var data: Dictionary = ARMOR[armor]
	result.breakdown.append(RuleModifier.new(data["base"], armor))
	if data["category"] != &"heavy":
		result.breakdown.append(RuleModifier.new(mini(Abilities.modifier(dexterity), data["dex_cap"]), &"dex"))
	result.shield_effective = shield and &"shield" in training
	if result.shield_effective:
		result.breakdown.append(RuleModifier.new(2, &"shield"))
	for modifier: RuleModifier in result.breakdown:
		result.armor_class += modifier.amount
	result.speed_penalty_m = 3.0 if strength < data["strength"] else 0.0
	result.stealth_disadvantage = data["stealth"]
	result.strength_dexterity_disadvantage = data["category"] != &"none" and not data["category"] in training
	result.can_cast_spells = not result.strength_dexterity_disadvantage
	return result
