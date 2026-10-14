class_name DivineSpellEffects
extends RefCounted
## Cleric, Paladin and Druid spells of the 2024 rules (SRD 5.2) that need more than
## data: smites, zones (Moonbeam, Insect Plague ...), weapon buffs, curses, Death Ward,
## Dispel Magic. Pure rules on plain actor records like ClassEffects, which calls in here.
##
## Simplifications (the spell text is longer than the game needs):
## - Smites are armed before the hit (like Divine Smite) and spent on the next melee weapon hit.
## - Command is always "Grovel": the target falls Prone and loses its next turn.
## - Bestow Curse always picks "1d8 Necrotic from the caster's weapon hits".
## - Elemental Weapon always deals Fire; Wrath of Nature is one damaging zone for enemies.
## - Zones hit a creature once per turn when it enters or ends its turn there (Spirit
##   Guardians rule); Sleet Storm and Wrath of Nature halve speed inside.

const SMITE_SPELLS: Array[StringName] = [&"searing_smite", &"thunderous_smite", &"wrathful_smite",
	&"shining_smite", &"blinding_smite"]
## Protection from Evil and Good keeps these creature types at Disadvantage.
const WARDED_TYPES: Array[String] = ["aberration", "celestial", "elemental", "fey", "fiend", "undead"]
const STONESKIN_TYPES: Array[String] = ["bludgeoning", "piercing", "slashing"]
const CRUSADERS_MANTLE_M: float = 9.0
const THORN_WHIP_PULL_M: float = 3.0
const THUNDEROUS_PUSH_M: float = 3.0
## Effects Greater Restoration lifts (curses and lingering magical illness).
const CURSES: Array[String] = ["bestow_curse", "contagion", "hex"]
## Kinds that grant a condition and are shaken off with a save at the end of each of the
## creature's turns: kind -> [condition, save ability].
const REPEAT_SAVES: Dictionary = {
	"blinded": ["blinded", "con"],
	"wrathful": ["frightened", "wis"],
	"contagion": ["poisoned", "con"],
}

static func _effects_of(actor: Dictionary, kind: String) -> Array:
	return ActiveEffects.effects(actor).filter(func(effect: Dictionary) -> bool:
		return String(effect.get("kind", "")) == kind)

static func granted_conditions(effect: Dictionary) -> Array[String]:
	var kind: String = String(effect.get("kind", ""))
	if REPEAT_SAVES.has(kind):
		return [String(REPEAT_SAVES[kind][0])]
	match kind:
		"command", "banishment":
			return ["incapacitated"]
	return []

static func is_weapon_attack(weapon: Dictionary) -> bool:
	return String(weapon.get("spell_id", "")).is_empty()

static func is_melee_weapon_attack(weapon: Dictionary) -> bool:
	return is_weapon_attack(weapon) and not bool(weapon.get("ranged", false))

# ---------------------------------------------------------------- attack and save modifiers

## Bane (-1d4) on attack rolls; Magic Weapon and Elemental Weapon (+1) on weapon attacks.
static func attack_modifiers(actor: Dictionary, weapon: Dictionary, rng: RandomNumberGenerator) -> Array[RuleModifier]:
	var result: Array[RuleModifier] = []
	if not _effects_of(actor, "bane").is_empty():
		result.append(RuleModifier.new(-Dice.roll("1d4", rng).total, &"bane"))
	if is_weapon_attack(weapon):
		for kind: String in ["magic_weapon", "elemental_weapon"]:
			if not _effects_of(actor, kind).is_empty():
				result.append(RuleModifier.new(1, StringName(kind)))
				break
	return result

static func attack_bonus_estimate(actor: Dictionary, weapon: Dictionary) -> int:
	var total: int = -2 if not _effects_of(actor, "bane").is_empty() else 0
	if is_weapon_attack(weapon) and (not _effects_of(actor, "magic_weapon").is_empty() or \
			not _effects_of(actor, "elemental_weapon").is_empty()):
		total += 1
	return total

static func save_modifiers(actor: Dictionary, rng: RandomNumberGenerator) -> Array[RuleModifier]:
	var result: Array[RuleModifier] = []
	if not _effects_of(actor, "bane").is_empty():
		result.append(RuleModifier.new(-Dice.roll("1d4", rng).total, &"bane"))
	return result

## Beacon of Hope: Advantage on Wisdom saving throws.
static func save_advantages(actor: Dictionary, ability: StringName) -> Array[StringName]:
	if ability == &"wis" and not _effects_of(actor, "beacon_of_hope").is_empty():
		return [&"beacon_of_hope"]
	return []

## Magic Weapon: +1 damage with weapon attacks.
static func damage_modifiers(actor: Dictionary, weapon: Dictionary) -> Array[RuleModifier]:
	if is_weapon_attack(weapon) and not _effects_of(actor, "magic_weapon").is_empty():
		return [RuleModifier.new(1, &"magic_weapon")]
	return []

## Advantage against a creature lit by Shining Smite.
static func attack_advantages(target: Dictionary) -> Array[StringName]:
	return [&"shining_smite"] if not _effects_of(target, "shining").is_empty() else []

## Protection from Evil and Good, Compelled Duel.
static func attack_disadvantages(state: GameState, attacker_id: String, target_id: String) -> Array[StringName]:
	var result: Array[StringName] = []
	var attacker: Dictionary = state.actors.get(attacker_id, {})
	var target: Dictionary = state.actors.get(target_id, {})
	if not _effects_of(target, "protection_from_evil_and_good").is_empty() and \
			String(attacker.get("creature_type", "humanoid")) in WARDED_TYPES:
		result.append(&"protection_from_evil_and_good")
	for effect: Dictionary in _effects_of(attacker, "compelled_duel"):
		if String(effect.get("source_id", "")) != target_id:
			result.append(&"compelled_duel")
			break
	return result

## Stoneskin: Resistance to Bludgeoning, Piercing and Slashing damage.
static func resistances(actor: Dictionary) -> Array[String]:
	if not _effects_of(actor, "stoneskin").is_empty():
		return STONESKIN_TYPES.duplicate()
	return []

## Heroism: immune to Frightened.
static func fear_immune(actor: Dictionary) -> bool:
	return not _effects_of(actor, "heroism").is_empty()

## Banished creatures are gone until the spell ends: no attack or spell reaches them.
static func untargetable(actor: Dictionary) -> bool:
	return not _effects_of(actor, "banishment").is_empty()

## Death Ward: the first drop to 0 hit points leaves the creature at 1 instead.
static func death_ward(target: Dictionary) -> bool:
	if _effects_of(target, "death_ward").is_empty() or int(target.get("hp", 0)) > 0:
		return false
	target["hp"] = 1
	ActiveEffects.remove_where(target, func(effect: Dictionary) -> bool: return String(effect.get("kind", "")) == "death_ward")
	return true

## Toll the Dead: d12 instead of d8 against a creature that is missing hit points.
static func damage_expression(spell: SpellDefinition, target: Dictionary, expression: String) -> String:
	if spell.effect == &"toll_the_dead" and not target.is_empty() and int(target.get("hp", 0)) < int(target.get("max_hp", 0)):
		return expression.replace("d8", "d12")
	return expression

## Beacon of Hope: healing restores the highest possible number.
static func maximize_healing(target: Dictionary, roll: DiceResult) -> void:
	if _effects_of(target, "beacon_of_hope").is_empty():
		return
	var missing: int = 0
	for group: DiceResult.Group in roll.groups:
		for value: int in group.values:
			missing += group.sides - value
	if missing > 0:
		roll.add_modifiers([RuleModifier.new(missing, &"beacon_of_hope")])

# ---------------------------------------------------------------- applying effects

## Extra fields of a new effect record (called from ClassEffects.apply_effect).
static func prepare_effect(state: GameState, caster: Dictionary, target_id: String, spell: SpellDefinition,
		slot_level: int, effect: Dictionary) -> void:
	match String(effect["kind"]):
		"command":
			effect["until"] = "end_of_turn"
			var target: Dictionary = state.actors[target_id]
			if not "prone" in target.get("conditions", []):
				if not target.has("conditions"):
					target["conditions"] = []
				target["conditions"].append("prone")
		"death_ward":
			effect["until"] = "long_rest"
		"magic_weapon", "heroism", "protection_from_evil_and_good", "stoneskin", "elemental_weapon":
			effect["amount"] = ClassEffects.spell_modifier(caster) if String(effect["kind"]) == "heroism" else 1
		"smite":
			effect["kind"] = "smite"
			effect["until"] = "start_of_turn"
			effect["dice"] = SpellRules.damage_expression(spell, int(caster.get("level", 1)), slot_level)
			effect["damage_type"] = String(spell.damage_type)
		"blinded", "wrathful", "contagion", "bestow_curse", "banishment":
			pass

## Self-contained resolutions: Dispel Magic and Greater Restoration on one creature,
## zones that only exist (Silence). Returns null when the spell is not handled here.
static func resolve_effect(state: GameState, caster_id: String, spell: SpellDefinition,
		pending: Dictionary, rng: RandomNumberGenerator) -> Variant:
	match String(spell.effect):
		"zone":
			return [] as Array[Dictionary]
		"dispel_magic":
			return dispel_magic(state, caster_id, String(pending["target_ids"][0]), int(pending["slot_level"]), rng)
		"greater_restoration":
			return greater_restoration(state, caster_id, String(pending["target_ids"][0]))
	return null

## Dispel Magic: every spell of the slot's level or lower on the creature ends; a higher
## one ends on a spellcasting ability check against DC 10 + its level.
static func dispel_magic(state: GameState, caster_id: String, target_id: String, slot_level: int,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var caster: Dictionary = state.actors[caster_id]
	var target: Dictionary = state.actors.get(target_id, {})
	if target.is_empty():
		return events
	var ended: Array[String] = []
	for effect: Dictionary in ActiveEffects.effects(target).duplicate():
		var spell: SpellDefinition = SpellBook.get_spell(String(effect.get("spell_id", "")))
		if spell == null or spell.level <= 0 or String(effect.get("spell_id", "")) in ended:
			continue
		if spell.level > slot_level:
			var check: DiceResult = Dice.d20(rng, [RuleModifier.new(ClassEffects.spell_modifier(caster), &"spellcasting")])
			events.append({"type": "roll", "kind": "check", "actor_id": caster_id, "target_id": target_id,
				"spell_id": "dispel_magic", "roll": CombatRules.serialize_roll(check), "dc": 10 + spell.level,
				"success": check.total >= 10 + spell.level})
			if check.total < 10 + spell.level:
				continue
		ended.append(String(effect.get("spell_id", "")))
	for spell_id: String in ended:
		_end_spell_on(state, target_id, spell_id, events)
	events.append({"type": "effect", "actor_id": target_id, "source_id": caster_id, "kind": "dispel_magic",
		"spell_id": "dispel_magic"})
	return events

static func _end_spell_on(state: GameState, target_id: String, spell_id: String, events: Array[Dictionary]) -> void:
	var target: Dictionary = state.actors[target_id]
	var removed: Array = ActiveEffects.effects(target).filter(func(effect: Dictionary) -> bool:
		return String(effect.get("spell_id", "")) == spell_id)
	ActiveEffects.remove_where(target, func(effect: Dictionary) -> bool:
		return String(effect.get("spell_id", "")) == spell_id)
	for effect: Dictionary in removed:
		if String(effect.get("kind", "")) == "aid":
			ClassEffects._remove_aid(target)
		for condition: String in ActiveEffects.granted_conditions(effect):
			events.append({"type": "condition_end", "actor_id": target_id, "condition": condition})
	events.append({"type": "effects_expired", "actor_id": target_id})

## Greater Restoration: lifts curses (Bestow Curse, Hex) and Contagion.
static func greater_restoration(state: GameState, caster_id: String, target_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: Dictionary = state.actors.get(target_id, {})
	if target.is_empty():
		return events
	var spells: Array[String] = []
	for effect: Dictionary in ActiveEffects.effects(target):
		if String(effect.get("kind", "")) in CURSES and not String(effect.get("spell_id", "")) in spells:
			spells.append(String(effect.get("spell_id", "")))
	for spell_id: String in spells:
		_end_spell_on(state, target_id, spell_id, events)
	events.append({"type": "effect", "actor_id": target_id, "source_id": caster_id, "kind": "greater_restoration",
		"spell_id": "greater_restoration"})
	return events

# ---------------------------------------------------------------- saves and riders

## A creature that failed the save of a spell with a lasting effect (Bane, Command,
## Blindness, Bestow Curse, Banishment, Contagion, Compelled Duel; Sleet Storm knocks Prone).
const SAVE_EFFECTS: Array[StringName] = [&"bane", &"command", &"blinded", &"bestow_curse", &"banishment",
	&"contagion", &"compelled_duel"]

static func failed_save(state: GameState, caster_id: String, target_id: String, spell: SpellDefinition,
		slot_level: int) -> Array[Dictionary]:
	var target: Dictionary = state.actors.get(target_id, {})
	if target.is_empty() or not CombatRules.alive(target):
		return []
	if spell.effect in SAVE_EFFECTS:
		return ClassEffects.apply_effect(state, caster_id, target_id, spell, slot_level)
	if spell.id == &"sleet_storm":
		return knock_prone(target, target_id, caster_id)
	return []

static func knock_prone(target: Dictionary, target_id: String, source_id: String) -> Array[Dictionary]:
	if "prone" in target.get("conditions", []):
		return []
	if not target.has("conditions"):
		target["conditions"] = []
	target["conditions"].append("prone")
	return [{"type": "condition", "actor_id": target_id, "condition": "prone", "source_id": source_id}]

## End of a creature's turn: Searing Smite burns; Blindness, Wrathful Smite's fear and
## Contagion are shaken off with a successful save against the caster's DC.
static func on_turn_end(state: GameState, actor_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var actor: Dictionary = state.actors.get(actor_id, {})
	if actor.is_empty() or not CombatRules.alive(actor):
		return events
	events.append_array(_searing(state, actor_id, rng))
	if not CombatRules.alive(actor):
		return events
	for effect: Dictionary in ActiveEffects.effects(actor).duplicate():
		var kind: String = String(effect.get("kind", ""))
		if not REPEAT_SAVES.has(kind):
			continue
		var save: Dictionary = SpellRules.roll_save(actor, StringName(String(REPEAT_SAVES[kind][1])),
			int(effect.get("save_dc", 10)), rng, ClassEffects.save_modifiers(state, actor_id, rng))
		events.append(ActiveEffects.save_event(String(effect.get("source_id", "")), actor_id, String(effect.get("spell_id", kind)), save))
		if bool(save["success"]):
			var source_id: String = String(effect.get("source_id", ""))
			ActiveEffects.remove_where(actor, func(other: Dictionary) -> bool:
				return String(other.get("kind", "")) == kind and String(other.get("source_id", "")) == source_id)
			events.append({"type": "condition_end", "actor_id": actor_id, "condition": String(REPEAT_SAVES[kind][0])})
	return events

## Start of a creature's turn: Heroism's temporary hit points.
static func on_turn_start(state: GameState, actor_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var actor: Dictionary = state.actors.get(actor_id, {})
	if actor.is_empty() or not CombatRules.alive(actor):
		return events
	for effect: Dictionary in _effects_of(actor, "heroism"):
		var amount: int = maxi(0, int(effect.get("amount", 0)))
		if amount > int(actor.get("temp_hp", 0)):
			actor["temp_hp"] = amount
			events.append({"type": "temp_hp", "actor_id": actor_id, "amount": amount, "spell_id": "heroism"})
	return events

## Searing Smite's flames: 1d6 Fire, then a Constitution save puts them out. The rules
## burn at the start of the creature's turn; here at its end, where the dice are.
static func _searing(state: GameState, actor_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var actor: Dictionary = state.actors[actor_id]
	for effect: Dictionary in _effects_of(actor, "searing"):
		var roll: DiceResult = Dice.roll("1d6", rng)
		var source_id: String = String(effect.get("source_id", ""))
		events.append({"type": "roll", "kind": "damage", "actor_id": source_id, "target_id": actor_id,
			"spell_id": "searing_smite", "roll": CombatRules.serialize_roll(roll), "damage_type": "fire", "amount": roll.total})
		events.append_array(SpellResolver._apply_damage(state, source_id, actor_id, roll.total, &"fire", rng))
		if not CombatRules.alive(actor):
			break
		var save: Dictionary = SpellRules.roll_save(actor, &"con", int(effect.get("save_dc", 10)), rng,
			ClassEffects.save_modifiers(state, actor_id, rng))
		events.append(ActiveEffects.save_event(source_id, actor_id, "searing_smite", save))
		if bool(save["success"]):
			ActiveEffects.remove_where(actor, func(other: Dictionary) -> bool: return String(other.get("kind", "")) == "searing")
			events.append({"type": "effects_expired", "actor_id": actor_id})
		break
	return events

# ---------------------------------------------------------------- hits

## Weapon-hit riders: an armed smite, Elemental Weapon, Crusader's Mantle, Bestow Curse.
## Returns [{"dice", "type", "source"}] for ClassEffects.hit_riders, and applies the
## smite's lasting effect to the target (after its save) into `events`.
static func weapon_riders(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		rng: RandomNumberGenerator, events: Array[Dictionary]) -> Array[Dictionary]:
	var riders: Array[Dictionary] = []
	var attacker: Dictionary = state.actors[attacker_id]
	var target: Dictionary = state.actors[target_id]
	if is_melee_weapon_attack(weapon):
		for smite: Dictionary in _effects_of(attacker, "smite"):
			riders.append({"dice": String(smite["dice"]), "type": String(smite["damage_type"]),
				"source": String(smite.get("spell_id", "smite"))})
			ActiveEffects.remove_where(attacker, func(effect: Dictionary) -> bool: return String(effect.get("kind", "")) == "smite")
			events.append_array(_smite_rider(state, attacker_id, target_id, smite, rng))
			break
	if not _effects_of(attacker, "elemental_weapon").is_empty():
		riders.append({"dice": "1d4", "type": "fire", "source": "elemental_weapon"})
	if crusaders_mantle(state, attacker_id):
		riders.append({"dice": "1d4", "type": "radiant", "source": "crusaders_mantle"})
	for curse: Dictionary in _effects_of(target, "bestow_curse"):
		if String(curse.get("source_id", "")) == attacker_id:
			riders.append({"dice": "1d8", "type": "necrotic", "source": "bestow_curse"})
			break
	return riders

static func _smite_rider(state: GameState, attacker_id: String, target_id: String, smite: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var attacker: Dictionary = state.actors[attacker_id]
	var target: Dictionary = state.actors[target_id]
	var spell_id: String = String(smite.get("spell_id", ""))
	var dc: int = int(attacker.get("spell_save_dc", 10))
	var base: Dictionary = {"source_id": attacker_id, "spell_id": spell_id, "turn_of": attacker_id,
		"until": "rounds", "rounds_left": 10, "save_dc": dc}
	var save_ability: StringName = {"thunderous_smite": &"str", "wrathful_smite": &"wis", "blinding_smite": &"con"}.get(spell_id, &"")
	var failed: bool = true
	if save_ability != &"":
		var save: Dictionary = SpellRules.roll_save(target, save_ability, dc, rng, ClassEffects.save_modifiers(state, target_id, rng))
		events.append(ActiveEffects.save_event(attacker_id, target_id, spell_id, save))
		failed = not bool(save["success"])
	if not failed:
		return events
	var effect: Dictionary = base.duplicate()
	match spell_id:
		"searing_smite":
			effect["kind"] = "searing"
		"thunderous_smite":
			events.append_array(push(state, attacker_id, target_id, THUNDEROUS_PUSH_M))
			events.append_array(knock_prone(target, target_id, attacker_id))
			return events
		"wrathful_smite":
			if ClassEffects.fear_immune(state, target_id):
				return events
			effect["kind"] = "wrathful"
		"shining_smite":
			effect["kind"] = "shining"
			effect["until"] = "concentration"
		"blinding_smite":
			effect["kind"] = "blinded"
		_:
			return events
	ActiveEffects.add(target, effect)
	events.append({"type": "effect", "actor_id": target_id, "source_id": attacker_id, "kind": effect["kind"], "spell_id": spell_id})
	for condition: String in ActiveEffects.granted_conditions(effect):
		events.append({"type": "condition", "actor_id": target_id, "condition": condition, "source_id": attacker_id})
	return events

## An ally (or the attacker) concentrating on Crusader's Mantle within 9 m.
static func crusaders_mantle(state: GameState, attacker_id: String) -> bool:
	var attacker: Dictionary = state.actors[attacker_id]
	if not attacker.get("position") is Vector3:
		return false
	for id: String in state.actors:
		var ally: Dictionary = state.actors[id]
		if ally.get("team") != attacker.get("team") or not CombatRules.alive(ally) or not ally.get("position") is Vector3:
			continue
		if String(ally.get("concentration", {}).get("spell_id", "")) == "crusaders_mantle" and \
				(ally["position"] as Vector3).distance_to(attacker["position"]) <= CRUSADERS_MANTLE_M + CombatRules.EPSILON:
			return true
	return false

## Spell attack hits: Thorn Whip pulls the target up to 3 m closer.
static func spell_hit(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> Array[Dictionary]:
	if String(weapon.get("spell_id", "")) == "thorn_whip" and CombatRules.alive(state.actors[target_id]):
		return push(state, attacker_id, target_id, -THORN_WHIP_PULL_M)
	return []

## Moves the target straight away from (distance > 0) or towards (< 0) the source,
## never closer than 1.5 m, onto the nearest walkable point.
static func push(state: GameState, source_id: String, target_id: String, distance: float) -> Array[Dictionary]:
	var source: Dictionary = state.actors[source_id]
	var target: Dictionary = state.actors[target_id]
	if not source.get("position") is Vector3 or not target.get("position") is Vector3:
		return []
	var from: Vector3 = target["position"]
	var away: Vector3 = Vector3(from.x - source["position"].x, 0.0, from.z - source["position"].z)
	var gap: float = away.length()
	if gap <= CombatRules.EPSILON:
		return []
	var step: float = distance if distance > 0.0 else -minf(-distance, maxf(0.0, gap - 1.5))
	if absf(step) <= CombatRules.EPSILON:
		return []
	var destination: Vector3 = CombatSpace.current().closest_point(from + away.normalized() * step)
	if not destination.is_finite() or not CombatSpace.current().visible(from, destination):
		return []
	target["position"] = destination
	return [{"type": "forced_move", "actor_id": target_id, "source_id": source_id,
		"from": from, "to": destination}]

# ---------------------------------------------------------------- zones and follow-ups

## Silence: no spells from inside it.
static func silenced(state: GameState, actor_id: String) -> bool:
	var actor: Dictionary = state.actors.get(actor_id, {})
	if not actor.get("position") is Vector3:
		return false
	for id: String in state.actors:
		var concentration: Dictionary = state.actors[id].get("concentration", {})
		if String(concentration.get("spell_id", "")) != "silence" or not concentration.get("point") is Vector3:
			continue
		var spell: SpellDefinition = SpellBook.get_spell("silence")
		if SpellRules.in_sphere(concentration["point"], spell.area_size_m, actor["position"]):
			return true
	return false

## Sleet Storm and Wrath of Nature (for the caster's enemies) are difficult terrain.
static func slowing_zone(state: GameState, actor_id: String) -> bool:
	var actor: Dictionary = state.actors.get(actor_id, {})
	if not actor.get("position") is Vector3:
		return false
	for id: String in state.actors:
		var caster: Dictionary = state.actors[id]
		var concentration: Dictionary = caster.get("concentration", {})
		var spell_id: String = String(concentration.get("spell_id", ""))
		if not spell_id in ["sleet_storm", "wrath_of_nature"] or not concentration.get("point") is Vector3:
			continue
		if spell_id == "wrath_of_nature" and caster.get("team") == actor.get("team"):
			continue
		if SpellRules.in_sphere(concentration["point"], SpellBook.get_spell(spell_id).area_size_m, actor["position"]):
			return true
	return false

## A follow-up spell (Spiritual Weapon's strike) is castable while the parent lasts.
static func follow_up_available(caster: Dictionary, spell: SpellDefinition) -> bool:
	return String(caster.get("concentration", {}).get("spell_id", "")) == String(spell.parent_spell)

## Casting a spell with a follow-up puts the follow-up on the caster's list.
static func add_follow_up(caster: Dictionary, spell: SpellDefinition) -> void:
	if spell.follow_up == &"" or SpellBook.get_spell(String(spell.follow_up)) == null:
		return
	if not caster.has("spells"):
		caster["spells"] = []
	if not String(spell.follow_up) in caster["spells"]:
		caster["spells"].append(String(spell.follow_up))
