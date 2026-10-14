class_name SpellResolver
extends RefCounted
## Encounter layer for spells, like CombatRules for weapons: legality, previews,
## area targets, timeline pendings and impact resolution. RNG is used only at impact.

const RELEASE_TIME: float = 0.35
const BOLT_SPEED_M_S: float = 16.0
const DART_SPEED_M_S: float = 12.0
const AFTER_IMPACT: float = 0.45
const CAST_CLIP: String = "Spell_Simple_Shoot"

## Full legality and preview. Returns {"legal", "reason_key", "targets": [...],
## "slot_level", "spell_id"}. Each target: {"id", "ally", "chance" or "save_chance",
## "expected_damage", "darts"}.
static func preview(state: GameState, caster_id: String, spell_id: String, slot_level: int = 0,
		target_ids: Array = [], point: Vector3 = Vector3.INF, ignore_economy: bool = false) -> Dictionary:
	var result: Dictionary = {"legal": false, "reason_key": "SPELL_REASON_UNKNOWN", "targets": [],
		"slot_level": slot_level, "spell_id": spell_id, "dc": 0, "save_ability": ""}
	var spell: SpellDefinition = SpellBook.get_spell(spell_id)
	if spell == null or not state.actors.has(caster_id):
		return result
	var caster: Dictionary = state.actors[caster_id]
	var reason: String = availability_reason(state, caster_id, spell, slot_level, ignore_economy)
	if not reason.is_empty():
		result["reason_key"] = reason
		return result
	result["slot_level"] = effective_slot(caster, spell, slot_level)
	result["dc"] = int(caster.get("spell_save_dc", 10))
	result["save_ability"] = String(spell.save_ability)
	var origin: Vector3 = caster["position"]
	var geometry: CombatSpace = CombatSpace.current()
	match spell.targeting:
		"creature":
			if target_ids.size() != 1:
				result["reason_key"] = "SPELL_REASON_PICK_TARGET"
				return result
			if spell.resolution == "heal" or (spell.resolution == "none" and spell.allies):
				if not _valid_heal_target(state, caster_id, String(target_ids[0]), spell.range_m):
					result["reason_key"] = "SPELL_REASON_TARGET"
					return result
				var patient: Dictionary = state.actors[String(target_ids[0])]
				var expected: float = expected_heal(caster, spell, int(result["slot_level"]))
				result["targets"] = [{"id": String(target_ids[0]), "ally": true, "chance": 1.0, "expected_damage": 0.0,
					"expected_heal": minf(expected, float(int(patient["max_hp"]) - int(patient["hp"])))}]
				result["legal"] = true
				result["reason_key"] = ""
				return result
			if spell.resolution == "save":
				var victim_id: String = String(target_ids[0])
				if not _valid_creature_target(state, caster_id, victim_id, spell.range_m) or \
						not _type_allowed(spell, state.actors[victim_id]):
					result["reason_key"] = "SPELL_REASON_TARGET"
					return result
				result["targets"] = [_save_entry(state, caster, victim_id, spell, int(result["slot_level"]),
					state.actors[victim_id]["position"])]
				result["legal"] = true
				result["reason_key"] = ""
				return result
			if spell.resolution == "none":
				# A mark on an enemy without attack or save (Hunter's Mark): see _apply_mark.
				if not _valid_creature_target(state, caster_id, String(target_ids[0]), spell.range_m):
					result["reason_key"] = "SPELL_REASON_TARGET"
					return result
				result["targets"] = [{"id": String(target_ids[0]), "ally": false, "chance": 1.0, "expected_damage": 0.0}]
				result["legal"] = true
				result["reason_key"] = ""
				return result
			var weapon: Dictionary = attack_weapon(caster, spell)
			var attack: Dictionary = CombatRules.attack_preview(state, caster_id, String(target_ids[0]), Vector3.INF, weapon)
			if not bool(attack["legal"]):
				result["reason_key"] = "SPELL_REASON_TARGET"
				return result
			var entry: Dictionary = attack.duplicate(true)
			entry["id"] = String(target_ids[0])
			entry["ally"] = false
			result["targets"] = [entry]
		"darts":
			var count: int = SpellRules.dart_count(spell, int(result["slot_level"]))
			if target_ids.size() != count:
				result["reason_key"] = "SPELL_REASON_PICK_DARTS"
				return result
			var per_target: Dictionary = {}
			for value: Variant in target_ids:
				var target_id: String = String(value)
				if not _valid_creature_target(state, caster_id, target_id, spell.range_m):
					result["reason_key"] = "SPELL_REASON_TARGET"
					return result
				per_target[target_id] = int(per_target.get(target_id, 0)) + 1
			var entries: Array = []
			var dice: String = spell.damage_dice
			for target_id: String in per_target:
				var darts: int = int(per_target[target_id])
				entries.append({"id": target_id, "ally": false, "chance": 1.0, "darts": darts,
					"expected_damage": SpellRules.average_damage(dice, spell.dart_bonus) * darts})
			result["targets"] = entries
		"self", "point":
			if spell.area == "none":
				result["targets"] = []
			else:
				var aim: Vector3 = point
				if not aim.is_finite():
					result["reason_key"] = "SPELL_REASON_PICK_POINT"
					return result
				if spell.targeting == "point":
					if origin.distance_to(aim) > spell.range_m + CombatRules.EPSILON:
						result["reason_key"] = "SPELL_REASON_RANGE"
						return result
					if not geometry.visible(origin, aim):
						result["reason_key"] = "SPELL_REASON_SIGHT"
						return result
				elif Vector2(aim.x - origin.x, aim.z - origin.z).length() < 0.1:
					result["reason_key"] = "SPELL_REASON_PICK_POINT"
					return result
				var entries: Array = []
				for target_id: String in area_targets(state, caster_id, spell, aim):
					entries.append(_save_entry(state, caster, target_id, spell, int(result["slot_level"]), aim))
				result["targets"] = entries
	result["legal"] = true
	result["reason_key"] = ""
	return result

## Why a spell cannot be cast right now (empty when it can), independent of targets.
static func availability_reason(state: GameState, caster_id: String, spell: SpellDefinition,
		slot_level: int = 0, ignore_economy: bool = false) -> String:
	var caster: Dictionary = state.actors.get(caster_id, {})
	if caster.is_empty() or not CombatRules.alive(caster):
		return "SPELL_REASON_UNKNOWN"
	if not String(spell.id) in caster.get("spells", []):
		return "SPELL_REASON_NOT_PREPARED"
	if not CombatRules.conditions_for(caster).can_act():
		return "SPELL_REASON_INCAPACITATED"
	if caster.has("wild_shape") and not spell.is_feature():
		return "SPELL_REASON_WILD_SHAPE"
	if not bool(caster.get("can_cast_spells", true)) and not spell.is_feature():
		# Untrained armour (EquipmentRules) forbids spellcasting.
		return "SPELL_REASON_ARMOR"
	if not ignore_economy:
		match spell.casting_time:
			"action":
				if not bool(caster.get("action_available", false)):
					return "COMBAT_NO_ACTION"
			"bonus_action":
				if not bool(caster.get("bonus_available", false)):
					return "COMBAT_NO_BONUS"
			"reaction":
				if not bool(caster.get("reaction_available", false)):
					return "COMBAT_NO_REACTION"
	if spell.is_feature():
		# Class features on the spell pipeline pay with their own uses.
		return "" if ClassEffects.resource_available(state, caster, spell) else "FEATURE_NO_USES"
	if free_cast(caster, spell):
		return ""
	if caster.get("spell_uses", {}).has(String(spell.id)):
		# Monster spellcasting: a number of uses per day instead of spell slots.
		if int(caster["spell_uses"][String(spell.id)]) <= 0:
			return "SPELL_REASON_NO_USES"
	elif not spell.is_cantrip() and not (slot_level == 0 and ClassKits.free_cast_available(caster, String(spell.id))):
		var slots: Array = caster.get("spell_slots", [])
		if slot_level == 0:
			if SpellRules.lowest_slot(slots, spell.level) == 0:
				return "SPELL_REASON_NO_SLOT"
		elif slot_level < spell.level or not SpellRules.has_slot(slots, slot_level):
			return "SPELL_REASON_NO_SLOT"
	return ""

## Divine Intervention: the next Cleric spell of level 1-5 needs no slot.
static func free_cast(caster: Dictionary, spell: SpellDefinition) -> bool:
	var intervention: Dictionary = caster.get("features", {}).get("divine_intervention", {})
	return bool(intervention.get("armed", false)) and spell.level >= 1 and spell.level <= 5 and \
		String(spell.id) in ClassSpellcasting.spell_list("cleric")

static func effective_slot(caster: Dictionary, spell: SpellDefinition, slot_level: int) -> int:
	if spell.is_cantrip() or spell.is_feature():
		return 0
	if free_cast(caster, spell):
		return maxi(spell.level, slot_level)
	if caster.get("spell_uses", {}).has(String(spell.id)):
		return spell.level
	if slot_level == 0 and ClassKits.free_cast_available(caster, String(spell.id)):
		return spell.level
	return slot_level if slot_level > 0 else SpellRules.lowest_slot(caster.get("spell_slots", []), spell.level)

## Spell attacks reuse the weapon attack pipeline (cover, sight, conditions, criticals,
## Shield) through a synthetic ranged "weapon" built from the caster's spellcasting.
static func attack_weapon(caster: Dictionary, spell: SpellDefinition) -> Dictionary:
	var on_hit: Array = []
	if spell.effect == &"speed_penalty":
		on_hit.append({"kind": "speed_penalty", "amount": spell.effect_amount, "until": "start_of_turn"})
	elif spell.effect == &"guiding_bolt":
		on_hit.append({"kind": "guiding_bolt", "until": "rounds", "rounds_left": 1})
	var damage_modifiers: Array = []
	var potent: int = ClassEffects.cantrip_damage_bonus(caster, spell)
	if potent != 0:
		damage_modifiers.append({"amount": potent, "source": "potent_spellcasting"})
	return {"id": String(spell.id), "name_key": String(spell.name_key), "spell_id": String(spell.id),
		"ranged": true, "reach": 1.5, "range": spell.range_m, "long_range": spell.range_m,
		"attack_modifiers": caster.get("spell_attack_modifiers", []).duplicate(true),
		"damage_dice": SpellRules.damage_expression(spell, int(caster.get("level", 1)), 0),
		"damage_modifiers": damage_modifiers, "damage_type": String(spell.damage_type), "on_hit": on_hit,
		"attack_clip": CAST_CLIP}

## Average healing of a heal spell (Lay on Hands: the whole remaining pool).
static func expected_heal(caster: Dictionary, spell: SpellDefinition, slot_level: int) -> float:
	if spell.effect == &"lay_on_hands":
		return float(caster.get("features", {}).get("lay_on_hands", {}).get("uses", 0))
	if spell.resolution != "heal":
		return 0.0
	return SpellRules.average_damage(heal_expression(spell, slot_level, int(caster.get("level", 1))),
		ClassEffects.spell_modifier(caster))

static func _type_allowed(spell: SpellDefinition, target: Dictionary) -> bool:
	return spell.creature_types.is_empty() or \
		StringName(String(target.get("creature_type", "humanoid"))) in spell.creature_types

## Living creatures inside the area. Burning Hands hits everyone, allies included;
## Sleep affects only creatures of the caster's choice (its enemies).
static func area_targets(state: GameState, caster_id: String, spell: SpellDefinition, point: Vector3) -> Array[String]:
	var result: Array[String] = []
	var caster: Dictionary = state.actors[caster_id]
	var origin: Vector3 = caster["position"]
	var center: Vector3 = origin if spell.targeting == "self" else point
	var geometry: CombatSpace = CombatSpace.current()
	var ids: Array = state.actors.keys()
	ids.sort()
	var candidates: Array[String] = []
	for id: String in ids:
		if id == caster_id and not spell.allies:
			continue
		var other: Dictionary = state.actors[id]
		if not CombatRules.alive(other) or not other.get("position") is Vector3:
			continue
		if spell.chosen_creatures and other.get("team") == caster.get("team"):
			continue
		if spell.allies and other.get("team") != caster.get("team"):
			continue
		if not _type_allowed(spell, other):
			continue
		candidates.append(id)
	for id: String in candidates:
		var other: Dictionary = state.actors[id]
		var position: Vector3 = other["position"]
		var inside: bool = false
		match spell.area:
			"cone": inside = SpellRules.in_cone(origin, point - origin, spell.area_size_m, position)
			"sphere": inside = SpellRules.in_sphere(center, spell.area_size_m, position)
			"line": inside = SpellRules.in_line(origin, point - origin, spell.area_size_m, spell.line_width_m, position)
		# Total cover from the area's point of origin blocks the effect.
		if inside and (id == caster_id or geometry.visible(center, position)):
			result.append(id)
	return _limit_targets(state, caster_id, spell, result)

## Bless, Aid, Mass Healing Word, Abjure Foes: at most N creatures, the nearest first
## (the caster counts as nearest of all).
static func _limit_targets(state: GameState, caster_id: String, spell: SpellDefinition, ids: Array[String]) -> Array[String]:
	var limit: int = target_limit(state.actors[caster_id], spell, 0)
	if limit <= 0 or ids.size() <= limit:
		return ids
	var origin: Vector3 = state.actors[caster_id]["position"]
	var sorted: Array[String] = ids.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool:
		var da: float = origin.distance_to(state.actors[a]["position"])
		var db: float = origin.distance_to(state.actors[b]["position"])
		return da < db if not is_equal_approx(da, db) else a < b)
	return sorted.slice(0, limit)

static func target_limit(caster: Dictionary, spell: SpellDefinition, slot_level: int) -> int:
	if spell.effect == &"frightened" and spell.is_feature():
		# Abjure Foes: Charisma modifier creatures, at least one.
		return maxi(1, Abilities.modifier(ProgressionRules.score(caster, "cha")))
	if spell.max_targets <= 0:
		return 0
	var used: int = effective_slot(caster, spell, slot_level)
	return spell.max_targets + spell.upcast_targets * maxi(0, used - spell.level)

## Healing reaches a living creature of the caster's side (the caster too) in range and sight.
static func _valid_heal_target(state: GameState, caster_id: String, target_id: String, range_m: float) -> bool:
	if not state.actors.has(target_id):
		return false
	var caster: Dictionary = state.actors[caster_id]
	var target: Dictionary = state.actors[target_id]
	if not CombatRules.alive(target) or target.get("team") != caster.get("team"):
		return false
	if target_id == caster_id:
		return true
	var origin: Vector3 = caster["position"]
	var destination: Vector3 = target["position"]
	return origin.distance_to(destination) <= range_m + CombatRules.EPSILON and \
		CombatSpace.current().visible(origin, destination)

## Healing dice including upcasting (Healing Word: 2d4, +2d4 per slot level above 1).
static func heal_expression(spell: SpellDefinition, slot_level: int, caster_level: int = 1) -> String:
	var parsed: Dictionary = Dice.parse(spell.heal_dice)
	var count: int = int(parsed["count"])
	if not spell.upcast_dice.is_empty() and slot_level > spell.level:
		count += int(Dice.parse(spell.upcast_dice)["count"]) * (slot_level - spell.level)
	for scale_level: int in spell.scale_levels:
		if caster_level >= scale_level:
			count += 1
	return "%dd%d" % [count, int(parsed["sides"])]

static func _valid_creature_target(state: GameState, caster_id: String, target_id: String, range_m: float) -> bool:
	if target_id == caster_id or not state.actors.has(target_id):
		return false
	var caster: Dictionary = state.actors[caster_id]
	var target: Dictionary = state.actors[target_id]
	if not CombatRules.alive(target) or target.get("team") == caster.get("team"):
		return false
	var origin: Vector3 = caster["position"]
	var destination: Vector3 = target["position"]
	return origin.distance_to(destination) <= range_m + CombatRules.EPSILON and \
		CombatSpace.current().visible(origin, destination)

static func _save_entry(state: GameState, caster: Dictionary, target_id: String,
		spell: SpellDefinition, slot_level: int, point: Vector3) -> Dictionary:
	var target: Dictionary = state.actors[target_id]
	var dc: int = int(caster.get("spell_save_dc", 10))
	var bonus: int = SpellRules.save_bonus(target, spell.save_ability) + save_cover_bonus(caster, spell, point, target)
	var success: float = SpellRules.save_success_chance(bonus, dc)
	if CombatRules.conditions_for(target).automatically_fails_save(spell.save_ability):
		success = 0.0
	var expected: float = 0.0
	if not spell.damage_dice.is_empty():
		var average: float = SpellRules.average_damage(SpellRules.damage_expression(spell, int(caster.get("level", 1)), slot_level),
			flat_damage_bonus(caster, spell))
		if not spell.extra_damage_dice.is_empty():
			average += SpellRules.average_damage(spell.extra_damage_dice)
		expected = (1.0 - success) * average + (success * floorf(average / 2.0) if spell.half_on_save else 0.0)
	return {"id": target_id, "ally": target.get("team") == caster.get("team"), "save_chance": success,
		"save_bonus": bonus, "expected_damage": expected, "kill_chance": 0.0}

## Dexterity saves add half (+2) or three-quarters (+5) cover against the area's origin.
static func save_cover_bonus(caster: Dictionary, spell: SpellDefinition, point: Vector3, target: Dictionary) -> int:
	if spell.save_ability != &"dex":
		return 0
	var center: Vector3 = caster["position"] if spell.targeting == "self" else point
	var value: int = CombatSpace.current().cover(center, target["position"])
	return value if value < 99 else 0

## Timeline record for an accepted cast. Damage waits for the effect to arrive.
static func cast_pending(state: GameState, caster_id: String, spell: SpellDefinition, slot_level: int,
		target_ids: Array, point: Vector3) -> Dictionary:
	var caster: Dictionary = state.actors[caster_id]
	var origin: Vector3 = caster["position"]
	var travel: float = 0.25
	match spell.targeting:
		"creature":
			var target: Vector3 = state.actors[String(target_ids[0])]["position"]
			travel = origin.distance_to(target) / BOLT_SPEED_M_S
		"darts":
			for value: Variant in target_ids:
				travel = maxf(travel, origin.distance_to(state.actors[String(value)]["position"]) / DART_SPEED_M_S + 0.2)
		"point":
			travel = origin.distance_to(point) / BOLT_SPEED_M_S + 0.35
		"self":
			travel = 0.3
	var impact: float = RELEASE_TIME + travel
	var pending: Dictionary = {"type": "spell", "actor_id": caster_id, "spell_id": String(spell.id),
		"slot_level": slot_level, "target_ids": target_ids.duplicate(), "point": point if point.is_finite() else origin,
		"origin": origin, "elapsed": 0.0, "release_time": RELEASE_TIME, "impact_time": impact,
		"duration": impact + AFTER_IMPACT, "impacted": false, "reactions_decided": []}
	if spell.resolution == "attack":
		var weapon: Dictionary = attack_weapon(caster, spell)
		pending["weapon"] = weapon
	return pending

static func start_event(pending: Dictionary) -> Dictionary:
	return {"type": "start_spell", "actor_id": pending["actor_id"], "spell_id": pending["spell_id"],
		"slot_level": pending["slot_level"], "target_ids": pending["target_ids"].duplicate(),
		"point": pending["point"], "origin": pending["origin"], "release_time": pending["release_time"],
		"impact_time": pending["impact_time"], "duration": pending["duration"]}

## The moment the effect arrives. May hand control to a Shield reaction first.
static func resolve_impact(state: GameState, pending: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var spell: SpellDefinition = SpellBook.get_spell(String(pending["spell_id"]))
	var caster_id: String = String(pending["actor_id"])
	var events: Array[Dictionary] = []
	if spell == null or not state.actors.has(caster_id):
		pending["impacted"] = true
		return events
	match spell.resolution:
		"attack":
			pending["impacted"] = true
			var weapon: Dictionary = pending["weapon"]
			events.append_array(CombatRules.resolve_attack(state, caster_id, String(pending["target_ids"][0]), weapon, rng, pending))
		"auto":
			for value: Variant in pending["target_ids"]:
				var target_id: String = String(value)
				if not target_id in pending["reactions_decided"] and shield_option(state, target_id):
					pending["reactions_decided"].append(target_id)
					state.pending = reaction_pending(target_id, caster_id, pending, {"magic_missile": true})
					events.append(reaction_offer_event(state.pending))
					return events
			pending["impacted"] = true
			events.append_array(_resolve_darts(state, caster_id, spell, pending, rng))
		"save":
			pending["impacted"] = true
			events.append_array(_resolve_area(state, caster_id, spell, pending, rng))
		"heal":
			pending["impacted"] = true
			events.append_array(_resolve_heal(state, caster_id, spell, pending, rng))
		_:
			pending["impacted"] = true
			events.append_array(_resolve_effect(state, caster_id, spell, pending))
	return events

## "none" resolution with an effect id: the effect sits on each target until the
## caster's concentration ends (or the start of the caster's next turn otherwise).
## Class kits read it, e.g. Hunter's Mark adds 1d6 Force to the Ranger's weapon hits.
static func _apply_mark(state: GameState, caster_id: String, spell: SpellDefinition, pending: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if spell.effect == &"":
		return events
	for value: Variant in pending.get("target_ids", []):
		var target: Dictionary = state.actors.get(String(value), {})
		if target.is_empty() or not CombatRules.alive(target):
			continue
		ActiveEffects.add(target, {"kind": String(spell.effect), "source_id": caster_id, "spell_id": String(spell.id),
			"turn_of": caster_id, "until": "concentration" if spell.concentration else "start_of_turn"})
		events.append({"type": "effect", "actor_id": String(value), "source_id": caster_id, "kind": String(spell.effect)})
	return events

## Spells without a roll: buffs on allies (Bless, Shield of Faith, Barkskin, Aid,
## Resistance), self effects (Divine Favor, Wild Shape).
static func _resolve_effect(state: GameState, caster_id: String, spell: SpellDefinition,
		pending: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if spell.effect == &"" or spell.effect in [&"shield"]:
		return events
	if spell.targeting == "creature" and not spell.allies:
		return _apply_mark(state, caster_id, spell, pending)
	var targets: Array[String] = []
	if spell.targeting == "creature":
		targets.append(String(pending["target_ids"][0]))
	elif spell.area != "none":
		targets = area_targets(state, caster_id, spell, pending["point"])
	else:
		targets.append(caster_id)
	for target_id: String in targets:
		if state.actors.has(target_id) and CombatRules.alive(state.actors[target_id]):
			events.append_array(ClassEffects.apply_effect(state, caster_id, target_id, spell, int(pending["slot_level"])))
	return events

## Flat damage on top of the dice: Divine Spark's Wisdom, Potent Spellcasting.
static func flat_damage_bonus(caster: Dictionary, spell: SpellDefinition) -> int:
	var total: int = ClassEffects.cantrip_damage_bonus(caster, spell)
	if spell.add_spell_modifier:
		total += ClassEffects.spell_modifier(caster)
	return total

static func _resolve_darts(state: GameState, caster_id: String, spell: SpellDefinition,
		pending: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var per_target: Dictionary = {}
	var order: Array[String] = []
	for value: Variant in pending["target_ids"]:
		var target_id: String = String(value)
		if not per_target.has(target_id):
			order.append(target_id)
		per_target[target_id] = int(per_target.get(target_id, 0)) + 1
	var parsed: Dictionary = Dice.parse(spell.damage_dice)
	for target_id: String in order:
		var target: Dictionary = state.actors[target_id]
		if not CombatRules.alive(target):
			continue
		var darts: int = int(per_target[target_id])
		if ActiveEffects.has_kind(target, "shield"):
			events.append({"type": "spell_blocked", "actor_id": caster_id, "target_id": target_id, "spell_id": String(spell.id)})
			continue
		# All darts strike simultaneously: one roll per target, one damage instance per dart group.
		var modifiers: Array[RuleModifier] = [RuleModifier.new(spell.dart_bonus * darts, &"magic_missile")]
		var expression: String = "%dd%d" % [int(parsed["count"]) * darts, int(parsed["sides"])]
		events.append_array(_apply_damage_roll(state, caster_id, target_id, expression, spell.damage_type, modifiers, rng))
	events.append_array(CombatRules.check_combat_end(state))
	return events

static func _resolve_area(state: GameState, caster_id: String, spell: SpellDefinition,
		pending: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var caster: Dictionary = state.actors[caster_id]
	var point: Vector3 = pending["point"]
	var targets: Array[String] = []
	if spell.targeting == "creature":
		# Single-target saves (Sacred Flame, Inflict Wounds, Hold Person, Divine Spark).
		for value: Variant in pending["target_ids"]:
			if state.actors.has(String(value)) and CombatRules.alive(state.actors[String(value)]):
				targets.append(String(value))
	else:
		targets = area_targets(state, caster_id, spell, point)
	var dc: int = int(caster.get("spell_save_dc", 10))
	var damage_total: int = 0
	var extra_total: int = 0
	if not spell.damage_dice.is_empty() and not targets.is_empty():
		var expression: String = SpellRules.damage_expression(spell, int(caster.get("level", 1)), int(pending["slot_level"]))
		var flat: int = flat_damage_bonus(caster, spell)
		var flat_modifiers: Array[RuleModifier] = []
		if flat != 0:
			flat_modifiers.append(RuleModifier.new(flat, &"spellcasting"))
		var roll: DiceResult = Dice.roll(expression, rng, flat_modifiers)
		damage_total = maxi(0, roll.total)
		events.append({"type": "roll", "kind": "damage", "actor_id": caster_id, "target_id": "",
			"spell_id": String(spell.id), "roll": CombatRules.serialize_roll(roll),
			"damage_type": String(spell.damage_type), "amount": damage_total})
		if not spell.extra_damage_dice.is_empty():
			var extra_roll: DiceResult = Dice.roll(spell.extra_damage_dice, rng)
			extra_total = extra_roll.total
			events.append({"type": "roll", "kind": "damage", "actor_id": caster_id, "target_id": "",
				"spell_id": String(spell.id), "roll": CombatRules.serialize_roll(extra_roll),
				"damage_type": String(spell.extra_damage_type), "amount": extra_total})
	var sear: int = 0
	if spell.effect == &"turned" and caster.get("features", {}).has("sear_undead") and not targets.is_empty():
		# Sear Undead: Wisdom modifier d8 (at least one) radiant to every undead that fails.
		var sear_roll: DiceResult = Dice.roll("%dd8" % maxi(1, Abilities.modifier(ProgressionRules.score(caster, "wis"))), rng)
		sear = sear_roll.total
		events.append({"type": "roll", "kind": "damage", "actor_id": caster_id, "target_id": "",
			"feature_id": "sear_undead", "roll": CombatRules.serialize_roll(sear_roll), "damage_type": "radiant", "amount": sear})
	for target_id: String in targets:
		var target: Dictionary = state.actors[target_id]
		var extra: Array[RuleModifier] = ClassEffects.save_modifiers(state, target_id, rng)
		var cover: int = save_cover_bonus(caster, spell, point, target) if spell.targeting != "creature" else 0
		if cover > 0:
			extra.append(RuleModifier.new(cover, &"cover"))
		var save: Dictionary = SpellRules.roll_save(target, spell.save_ability, dc, rng, extra)
		events.append(ActiveEffects.save_event(caster_id, target_id, String(spell.id), save))
		var failed: bool = not bool(save["success"])
		if spell.effect == &"spirit_guardians":
			# The cast counts as this turn's one Spirit Guardians save for the creature.
			ActiveEffects.mark_aura_hit(state, caster_id, target_id)
		if not spell.damage_dice.is_empty():
			for part: Array in [[damage_total, spell.damage_type], [extra_total, spell.extra_damage_type]]:
				if int(part[0]) <= 0 and part[1] != spell.damage_type:
					continue
				var raw: int = int(part[0])
				if not failed:
					raw = floori(raw / 2.0) if spell.half_on_save else 0
				if spell.half_on_save and ClassKits.evades(target, spell.save_ability):
					# Evasion (Monk, Rogue): no damage on a success, half on a failure.
					raw = 0 if not failed else floori(int(part[0]) / 2.0)
				if (raw > 0 or failed) and CombatRules.alive(target):
					events.append_array(_apply_damage(state, caster_id, target_id, raw, part[1], rng))
		elif spell.effect == &"sleep" and failed:
			ActiveEffects.add(target, {"kind": "sleep", "stage": 1, "source_id": caster_id,
				"spell_id": String(spell.id), "until": "concentration", "save_dc": dc})
			events.append({"type": "condition", "actor_id": target_id, "condition": "incapacitated", "source_id": caster_id})
		if failed and sear > 0 and CombatRules.alive(target):
			events.append_array(_apply_damage(state, caster_id, target_id, sear, &"radiant", rng))
		if failed and CombatRules.alive(target) and spell.effect in [&"hold", &"entangle", &"faerie_fire", &"turned", &"frightened"]:
			events.append_array(ClassEffects.apply_effect(state, caster_id, target_id, spell, int(pending["slot_level"])))
	events.append_array(CombatRules.check_combat_end(state))
	return events

static func _resolve_heal(state: GameState, caster_id: String, spell: SpellDefinition,
		pending: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var targets: Array[String] = []
	if spell.targeting == "creature":
		targets.append(String(pending["target_ids"][0]))
	else:
		# Mass Healing Word, Mass Cure Wounds: the allies in the area.
		targets = area_targets(state, caster_id, spell, pending["point"])
	var events: Array[Dictionary] = []
	var caster: Dictionary = state.actors[caster_id]
	for target_id: String in targets:
		var target: Dictionary = state.actors.get(target_id, {})
		if not CombatRules.alive(target):
			continue
		if spell.effect == &"lay_on_hands":
			events.append_array(ClassEffects.lay_on_hands(state, caster_id, target_id))
			continue
		var modifiers: Array[RuleModifier] = [RuleModifier.new(ClassEffects.spell_modifier(caster), &"spellcasting")]
		var roll: DiceResult = Dice.roll(heal_expression(spell, int(pending["slot_level"]), int(caster.get("level", 1))), rng, modifiers)
		var before: int = int(target["hp"])
		target["hp"] = mini(int(target["max_hp"]), before + maxi(0, roll.total))
		events.append({"type": "roll", "kind": "healing", "actor_id": caster_id, "target_id": target_id, "spell_id": String(spell.id),
			"roll": CombatRules.serialize_roll(roll), "amount": roll.total})
		events.append({"type": "heal", "actor_id": target_id, "target_id": target_id, "source_id": caster_id,
			"spell_id": String(spell.id), "amount": int(target["hp"]) - before, "hp": target["hp"]})
	return events

static func _apply_damage_roll(state: GameState, source_id: String, target_id: String, expression: String,
		damage_type: StringName, modifiers: Array[RuleModifier], rng: RandomNumberGenerator) -> Array[Dictionary]:
	var target: Dictionary = state.actors[target_id]
	var damage: DamageRules.Result = DamageRules.roll(expression, damage_type, rng, modifiers, false, CombatRules.defenses_for(target))
	var events: Array[Dictionary] = [{"type": "roll", "kind": "damage", "actor_id": source_id, "target_id": target_id,
		"roll": CombatRules.serialize_roll(damage.roll), "damage_type": String(damage_type), "amount": damage.total}]
	events.append_array(_hp_loss(state, source_id, target_id, damage.total, damage_type, rng))
	return events

static func _apply_damage(state: GameState, source_id: String, target_id: String, raw: int,
		damage_type: StringName, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var target: Dictionary = state.actors[target_id]
	var damage: DamageRules.Result = DamageRules.apply(raw, damage_type, CombatRules.defenses_for(target))
	return _hp_loss(state, source_id, target_id, damage.total, damage_type, rng)

static func _hp_loss(state: GameState, source_id: String, target_id: String, amount: int,
		damage_type: StringName, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var target: Dictionary = state.actors[target_id]
	var was_alive: bool = CombatRules.alive(target)
	var lost: int = ClassEffects.lose_hp(state, target_id, amount, rng)
	var events: Array[Dictionary] = [{"type": "damage", "actor_id": source_id, "target_id": target_id,
		"amount": lost, "damage_type": String(damage_type), "hp": target["hp"]}]
	events.append_array(ActiveEffects.after_damage(state, target_id, lost, rng))
	if was_alive and not CombatRules.alive(target):
		events.append(NonlethalFights.fall_event(state, target_id, source_id))
	return events

## Shield can be cast by this creature right now (reaction, slot, prepared, able to act).
static func shield_option(state: GameState, reactor_id: String) -> bool:
	var reactor: Dictionary = state.actors.get(reactor_id, {})
	var spell: SpellDefinition = SpellBook.get_spell("shield")
	if reactor.is_empty() or spell == null or ActiveEffects.has_kind(reactor, "shield"):
		return false
	return availability_reason(state, reactor_id, spell).is_empty()

static func reaction_pending(reactor_id: String, attacker_id: String, resume: Dictionary, trigger: Dictionary) -> Dictionary:
	return {"type": "reaction", "reaction": "shield", "actor_id": reactor_id, "attacker_id": attacker_id,
		"trigger": trigger.duplicate(true), "resume": resume}

static func reaction_offer_event(pending: Dictionary) -> Dictionary:
	return {"type": "reaction_offer", "actor_id": pending["actor_id"], "attacker_id": pending["attacker_id"],
		"reaction": pending["reaction"], "trigger": pending["trigger"].duplicate(true)}
