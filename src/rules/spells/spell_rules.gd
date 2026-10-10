class_name SpellRules
extends RefCounted
## Pure spellcasting math from SRD 5.2: attack bonus, save DC, slots, cantrip
## scaling, area templates, concentration and the level-1 class feature numbers.
## No Nodes, no singletons; randomness only through the supplied generator.

const CONE_TOLERANCE_M: float = 0.3
## Full-caster slot table (Wizard) for levels 1-10, index 0 = 1st-level slots.
const FULL_CASTER_SLOTS: Array = [
	[2], [3], [4, 2], [4, 3], [4, 3, 2], [4, 3, 3], [4, 3, 3, 1], [4, 3, 3, 2],
	[4, 3, 3, 3, 1], [4, 3, 3, 3, 2],
]

static func spell_attack_bonus(ability_score: int, level: int) -> int:
	return Abilities.modifier(ability_score) + Abilities.proficiency_bonus(level)

static func spell_attack_modifiers(ability: StringName, ability_score: int, level: int) -> Array[Dictionary]:
	return [{"amount": Abilities.modifier(ability_score), "source": String(ability)},
		{"amount": Abilities.proficiency_bonus(level), "source": "proficiency"}]

static func spell_save_dc(ability_score: int, level: int) -> int:
	return 8 + Abilities.modifier(ability_score) + Abilities.proficiency_bonus(level)

static func full_caster_slots(level: int) -> Array[int]:
	var result: Array[int] = []
	if level >= 1 and level <= FULL_CASTER_SLOTS.size():
		result.assign(FULL_CASTER_SLOTS[level - 1])
	return result

static func has_slot(slots: Array, slot_level: int) -> bool:
	return slot_level >= 1 and slot_level <= slots.size() and int(slots[slot_level - 1]) > 0

## Returns false and leaves the array untouched when no slot of that level remains.
static func spend_slot(slots: Array, slot_level: int) -> bool:
	if not has_slot(slots, slot_level):
		return false
	slots[slot_level - 1] = int(slots[slot_level - 1]) - 1
	return true

## Lowest available slot at or above the spell level, 0 if none.
static func lowest_slot(slots: Array, spell_level: int) -> int:
	for slot_level: int in range(maxi(1, spell_level), slots.size() + 1):
		if has_slot(slots, slot_level):
			return slot_level
	return 0

## Cantrip Upgrade: one die more at character levels 5, 11 and 17.
static func cantrip_multiplier(character_level: int) -> int:
	return 1 + int(character_level >= 5) + int(character_level >= 11) + int(character_level >= 17)

## The damage expression after cantrip scaling or upcasting.
static func damage_expression(spell: SpellDefinition, character_level: int, slot_level: int) -> String:
	if spell.damage_dice.is_empty():
		return ""
	var parsed: Dictionary = Dice.parse(spell.damage_dice)
	var count: int = int(parsed["count"])
	if spell.is_cantrip():
		count *= cantrip_multiplier(character_level)
	elif not spell.upcast_dice.is_empty() and slot_level > spell.level:
		count += int(Dice.parse(spell.upcast_dice)["count"]) * (slot_level - spell.level)
	return "%dd%d" % [count, int(parsed["sides"])]

static func dart_count(spell: SpellDefinition, slot_level: int) -> int:
	return spell.darts + spell.upcast_darts * maxi(0, slot_level - spell.level)

static func average_damage(expression: String, flat: int = 0) -> float:
	var parsed: Dictionary = Dice.parse(expression)
	if parsed.has("error"):
		return 0.0
	return int(parsed["count"]) * (int(parsed["sides"]) + 1) / 2.0 + flat

## SRD 5.2 cone: its width at any point equals the distance from the origin.
## Creatures count when their centre lies within the cone plus a body tolerance.
static func in_cone(origin: Vector3, direction: Vector3, length: float, point: Vector3) -> bool:
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.000001:
		return false
	flat = flat.normalized()
	var offset: Vector3 = point - origin
	var along: float = offset.dot(flat)
	if along <= 0.05 or along > length + CONE_TOLERANCE_M:
		return false
	var perpendicular: float = (offset - flat * along).length()
	return perpendicular <= minf(along, length) * 0.5 + CONE_TOLERANCE_M

static func in_sphere(center: Vector3, radius: float, point: Vector3) -> bool:
	return center.distance_to(point) <= radius + CONE_TOLERANCE_M

static func in_line(origin: Vector3, direction: Vector3, length: float, width: float, point: Vector3) -> bool:
	if direction.length_squared() < 0.000001:
		return false
	var axis: Vector3 = direction.normalized()
	var offset: Vector3 = point - origin
	var along: float = offset.dot(axis)
	if along < 0.0 or along > length:
		return false
	return (offset - axis * along).length() <= width * 0.5 + CONE_TOLERANCE_M

## SRD 5.2 concentration: DC 10 or half the damage taken, whichever is higher, max 30.
static func concentration_dc(damage: int) -> int:
	return mini(30, maxi(10, floori(damage / 2.0)))

## Arcane Recovery: slots with a combined level up to half the wizard level
## (rounded up), none of 6th level or higher. Returns the levels recovered.
static func arcane_recovery_budget(wizard_level: int) -> int:
	return ceili(wizard_level / 2.0)

static func arcane_recovery(slots: Array, maximum: Array, wizard_level: int,
		requested_levels: Array[int]) -> bool:
	var budget: int = arcane_recovery_budget(wizard_level)
	var total: int = 0
	var counts: Dictionary = {}
	for slot_level: int in requested_levels:
		if slot_level < 1 or slot_level >= 6 or slot_level > maximum.size():
			return false
		total += slot_level
		counts[slot_level] = int(counts.get(slot_level, 0)) + 1
	if total == 0 or total > budget:
		return false
	for slot_level: int in counts:
		if int(slots[slot_level - 1]) + int(counts[slot_level]) > int(maximum[slot_level - 1]):
			return false
	for slot_level: int in counts:
		slots[slot_level - 1] = int(slots[slot_level - 1]) + int(counts[slot_level])
	return true

## Fighter Second Wind uses by fighter level (SRD 5.2 Fighter table).
static func second_wind_uses(fighter_level: int) -> int:
	if fighter_level >= 10:
		return 4
	return 3 if fighter_level >= 4 else 2

static func second_wind_expression(fighter_level: int) -> String:
	return "1d10+%d" % fighter_level

## Saving-throw modifiers for hero sheets (proficiency list) and SRD stat blocks
## (listed totals). Keys may be String or StringName.
static func save_modifiers(actor: Dictionary, ability: StringName) -> Array[RuleModifier]:
	var scores: Dictionary = actor.get("ability_scores", {})
	var score: int = int(_lookup(scores, ability, 10))
	var result: Array[RuleModifier] = [RuleModifier.new(Abilities.modifier(score), ability)]
	var listed: Variant = _lookup(actor.get("saving_throws", {}), ability, null)
	if listed != null:
		var extra: int = int(listed) - Abilities.modifier(score)
		if extra != 0:
			result.append(RuleModifier.new(extra, &"proficiency"))
	elif ability in actor.get("save_proficiencies", []) or String(ability) in actor.get("save_proficiencies", []):
		result.append(RuleModifier.new(int(actor.get("proficiency_bonus", 2)), &"proficiency"))
	return result

static func save_bonus(actor: Dictionary, ability: StringName) -> int:
	var total: int = 0
	for modifier: RuleModifier in save_modifiers(actor, ability):
		total += modifier.amount
	return total

## Chance that a d20 + bonus meets the DC (no natural 1/20 rule for saves).
static func save_success_chance(bonus: int, dc: int, advantage: int = 0) -> float:
	var chance: float = clampf(float(21 + bonus - dc) / 20.0, 0.0, 1.0)
	if advantage > 0:
		return 1.0 - pow(1.0 - chance, 2.0)
	if advantage < 0:
		return chance * chance
	return chance

static func _lookup(dictionary: Dictionary, key: StringName, fallback: Variant) -> Variant:
	if dictionary.has(key):
		return dictionary[key]
	if dictionary.has(String(key)):
		return dictionary[String(key)]
	return fallback

## One saving throw for an encounter actor. Returns {"success", "roll", "automatic",
## "dc", "ability"}; the roll is serialized for the dice popup. Unconscious and
## stunned creatures fail STR/DEX saves automatically without consuming RNG.
static func roll_save(actor: Dictionary, ability: StringName, dc: int, rng: RandomNumberGenerator,
		extra: Array[RuleModifier] = [], advantages: Array[StringName] = []) -> Dictionary:
	var conditions: ConditionState = CombatRules.conditions_for(actor)
	var result: Dictionary = {"success": false, "automatic": false, "dc": dc,
		"ability": String(ability), "roll": {}}
	if conditions.automatically_fails_save(ability):
		result["automatic"] = true
		result["reason"] = "unconscious" if conditions.has(&"unconscious") else "stunned"
		return result
	var disadvantages: Array[StringName] = []
	if ability == &"dex" and conditions.has(&"restrained"):
		disadvantages.append(&"restrained")
	var modifiers: Array[RuleModifier] = save_modifiers(actor, ability)
	modifiers.append_array(extra)
	var roll: DiceResult = Dice.d20(rng, modifiers, advantages, disadvantages)
	result["success"] = roll.is_valid() and roll.total >= dc
	result["roll"] = CombatRules.serialize_roll(roll)
	return result
