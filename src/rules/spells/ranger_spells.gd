extends RefCounted
## Ranger spells (SRD 5.2 / 2024 rules) that need their own code: "custom" resolution
## (CustomSpells) plus the ClassKits effect hooks that make their effects work for any
## creature (ClassKits.EFFECT_MODULES). Pure: no Nodes, no singletons; dice only through
## the supplied generator.
##
## Strike spells (Ensnaring Strike, Hail of Thorns, Lightning Arrow) are cast as a Bonus
## Action right after a weapon attack, as in the 2024 rules: they target a creature this
## creature hit (or, for Lightning Arrow, also missed) with a weapon this turn.
## Zones (Spike Growth, Conjure Animals, Fog Cloud) live in the caster's concentration
## record ("zone"), so they end with concentration.

const SPELLS: Array[String] = ["ensnaring_strike", "hail_of_thorns", "lightning_arrow", "longstrider", "jump",
	"lesser_restoration", "protection_from_poison", "protection_from_energy", "goodberry", "spike_growth",
	"conjure_animals", "fog_cloud", "pass_without_trace"]
const STRIKES: String = "weapon_strikes"
## Lesser Restoration ends one of these, first match wins.
const RESTORABLE: Array[String] = ["paralyzed", "poisoned", "blinded", "deafened"]
const PASS_WITHOUT_TRACE_M: float = 9.0
const PASS_WITHOUT_TRACE_BONUS: int = 10
const SPIKE_STEP_M: float = 1.5
const SAMPLE_M: float = 0.25
## No element picker yet: Protection from Energy guards against Fire.
const DEFAULT_ENERGY: String = "fire"
const GOODBERRIES: int = 10
## Hail of Thorns: the target and creatures within 5 ft; Lightning Arrow: within 10 ft.
const HAIL_RADIUS_M: float = 1.5
const LIGHTNING_RADIUS_M: float = 3.0

# ---------------------------------------------------------------- preview

static func preview(state: GameState, caster_id: String, spell: SpellDefinition, result: Dictionary,
		target_ids: Array, point: Vector3) -> Dictionary:
	var caster: Dictionary = state.actors[caster_id]
	var slot_level: int = int(result["slot_level"])
	var reach_m: float = SpellResolver.spell_range(caster, spell)
	var id: String = String(spell.id)
	match id:
		"ensnaring_strike", "hail_of_thorns", "lightning_arrow":
			if target_ids.size() != 1:
				return _fail(result, "SPELL_REASON_PICK_TARGET")
			var target_id: String = String(target_ids[0])
			if not state.actors.has(target_id) or not CombatRules.alive(state.actors[target_id]) or \
					not target_id in struck(state, caster_id, id):
				return _fail(result, "SPELL_REASON_NOT_STRUCK")
			var center: Vector3 = state.actors[target_id]["position"]
			if id == "ensnaring_strike":
				result["targets"] = [SpellResolver._save_entry(state, caster, target_id, spell, slot_level, center)]
			elif id == "hail_of_thorns":
				var entries: Array = []
				for other_id: String in creatures_near(state, center, HAIL_RADIUS_M, caster_id):
					entries.append(SpellResolver._save_entry(state, caster, other_id, spell, slot_level, center))
				result["targets"] = entries
			else:
				var hit: bool = target_id in struck(state, caster_id, "ranged_hit")
				var average: float = SpellRules.average_damage(lightning_primary(spell, caster, slot_level))
				var entries: Array = [{"id": target_id, "ally": false, "chance": 1.0,
					"expected_damage": average if hit else floorf(average / 2.0)}]
				for other_id: String in creatures_near(state, center, LIGHTNING_RADIUS_M, caster_id):
					if other_id != target_id:
						entries.append(SpellResolver._save_entry(state, caster, other_id, spell, slot_level, center))
				result["targets"] = entries
		"longstrider", "jump", "lesser_restoration", "protection_from_poison", "protection_from_energy":
			if target_ids.size() != 1:
				return _fail(result, "SPELL_REASON_PICK_TARGET")
			if not SpellResolver._valid_heal_target(state, caster_id, String(target_ids[0]), reach_m):
				return _fail(result, "SPELL_REASON_TARGET")
			result["targets"] = [{"id": String(target_ids[0]), "ally": true, "chance": 1.0, "expected_damage": 0.0}]
		"goodberry":
			result["targets"] = []
		"pass_without_trace":
			var entries: Array = []
			for ally_id: String in allies_near(state, caster_id, PASS_WITHOUT_TRACE_M):
				entries.append({"id": ally_id, "ally": true, "chance": 1.0, "expected_damage": 0.0})
			result["targets"] = entries
		"spike_growth", "conjure_animals", "fog_cloud":
			if not point.is_finite():
				return _fail(result, "SPELL_REASON_PICK_POINT")
			var origin: Vector3 = caster["position"]
			if origin.distance_to(point) > reach_m + CombatRules.EPSILON:
				return _fail(result, "SPELL_REASON_RANGE")
			if not CombatSpace.current().visible(origin, point):
				return _fail(result, "SPELL_REASON_SIGHT")
			var entries: Array = []
			for other_id: String in creatures_near(state, point, spell.area_size_m, ""):
				var other: Dictionary = state.actors[other_id]
				var ally: bool = other.get("team") == caster.get("team")
				if id == "conjure_animals":
					if not ally:
						entries.append(SpellResolver._save_entry(state, caster, other_id, spell, slot_level, point))
				else:
					entries.append({"id": other_id, "ally": ally, "chance": 1.0, "expected_damage": 0.0})
			result["targets"] = entries
		_:
			return result
	result["legal"] = true
	result["reason_key"] = ""
	return result

static func _fail(result: Dictionary, reason: String) -> Dictionary:
	result["reason_key"] = reason
	return result

# ---------------------------------------------------------------- impact

static func resolve(state: GameState, caster_id: String, spell: SpellDefinition, pending: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var caster: Dictionary = state.actors[caster_id]
	var slot_level: int = int(pending.get("slot_level", spell.level))
	var target_ids: Array = pending.get("target_ids", [])
	var target_id: String = String(target_ids[0]) if not target_ids.is_empty() else ""
	match String(spell.id):
		"ensnaring_strike":
			events.append_array(_ensnare(state, caster_id, target_id, spell, slot_level, rng))
		"hail_of_thorns":
			if state.actors.has(target_id):
				var area: Dictionary = pending.duplicate()
				area["target_ids"] = creatures_near(state, state.actors[target_id]["position"], HAIL_RADIUS_M, caster_id)
				events.append_array(SpellResolver._resolve_area(state, caster_id, spell, area, rng))
		"lightning_arrow":
			events.append_array(_lightning_arrow(state, caster_id, target_id, spell, pending, rng))
		"longstrider":
			events.append_array(_speed_bonus(state, caster_id, target_id, spell, {"until": "long_rest"}))
		"jump":
			events.append_array(_speed_bonus(state, caster_id, target_id, spell,
				{"until": "rounds", "rounds_left": maxi(1, spell.duration_rounds)}))
		"lesser_restoration":
			events.append_array(_restore(state, target_id, RESTORABLE, true))
		"protection_from_poison":
			events.append_array(_restore(state, target_id, ["poisoned"], false))
			events.append_array(_add(state, caster_id, target_id, spell, {"until": "long_rest"}))
		"protection_from_energy":
			events.append_array(_add(state, caster_id, target_id, spell,
				{"until": "concentration", "damage_type": DEFAULT_ENERGY}))
		"goodberry":
			EquipmentRules.add_item(caster, "goodberry", GOODBERRIES)
			events.append({"type": "effect", "actor_id": caster_id, "source_id": caster_id, "kind": "goodberry",
				"spell_id": "goodberry", "amount": GOODBERRIES})
		"pass_without_trace":
			for ally_id: String in allies_near(state, caster_id, PASS_WITHOUT_TRACE_M):
				events.append_array(_add(state, caster_id, ally_id, spell, {"until": "concentration"}))
		"spike_growth", "conjure_animals", "fog_cloud":
			var concentration: Dictionary = caster.get("concentration", {})
			if String(concentration.get("spell_id", "")) == String(spell.id):
				concentration["zone"] = {"spell_id": String(spell.id), "center": pending["point"],
					"radius": spell.area_size_m, "slot_level": slot_level, "hits": {}}
				events.append({"type": "effect", "actor_id": caster_id, "source_id": caster_id,
					"kind": String(spell.id), "spell_id": String(spell.id)})
				events.append_array(sync_fog(state))
	if not events.is_empty():
		events.append_array(CombatRules.check_combat_end(state))
	return events

## Ensnaring Strike: Strength save or Restrained (the "entangle" effect: the creature repeats
## the save at the end of its turns) and 1d6 Piercing per turn while ensnared.
static func _ensnare(state: GameState, caster_id: String, target_id: String, spell: SpellDefinition,
		slot_level: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: Dictionary = state.actors.get(target_id, {})
	if target.is_empty() or not CombatRules.alive(target):
		return events
	var dc: int = int(state.actors[caster_id].get("spell_save_dc", 10))
	var save: Dictionary = SpellRules.roll_save(target, spell.save_ability, dc, rng,
		ClassEffects.save_modifiers(state, target_id, rng))
	events.append(ActiveEffects.save_event(caster_id, target_id, String(spell.id), save))
	if bool(save["success"]):
		# Nothing left to hold: the spell ends instead of tying up concentration.
		events.append_array(ActiveEffects.end_concentration(state, caster_id, "ended"))
		return events
	var effect: Dictionary = {"kind": "entangle", "source_id": caster_id, "spell_id": String(spell.id),
		"turn_of": caster_id, "until": "concentration", "save_dc": dc, "save_ability": String(spell.save_ability),
		"slot_level": slot_level}
	ActiveEffects.add(target, effect)
	events.append({"type": "effect", "actor_id": target_id, "source_id": caster_id, "kind": "ensnaring_strike",
		"spell_id": String(spell.id)})
	events.append({"type": "condition", "actor_id": target_id, "condition": "restrained", "source_id": caster_id})
	return events

## Primary target dice: two d8 more than the area (4d8 against 2d8 at level 3).
static func lightning_primary(spell: SpellDefinition, caster: Dictionary, slot_level: int) -> String:
	var parsed: Dictionary = Dice.parse(SpellRules.damage_expression(spell, int(caster.get("level", 1)), slot_level))
	return "%dd%d" % [int(parsed["count"]) + 2, int(parsed["sides"])]

## Lightning Arrow: the attacked creature takes the lightning (half if the attack missed),
## everyone else within 3 m makes a Dexterity save against the smaller burst.
static func _lightning_arrow(state: GameState, caster_id: String, target_id: String, spell: SpellDefinition,
		pending: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: Dictionary = state.actors.get(target_id, {})
	if target.is_empty():
		return events
	var caster: Dictionary = state.actors[caster_id]
	var center: Vector3 = target["position"]
	var hit: bool = target_id in struck(state, caster_id, "ranged_hit")
	if CombatRules.alive(target):
		var roll: DiceResult = Dice.roll(lightning_primary(spell, caster, int(pending["slot_level"])), rng)
		var amount: int = roll.total if hit else floori(roll.total / 2.0)
		events.append({"type": "roll", "kind": "damage", "actor_id": caster_id, "target_id": target_id,
			"spell_id": String(spell.id), "roll": CombatRules.serialize_roll(roll),
			"damage_type": String(spell.damage_type), "amount": amount})
		events.append_array(SpellResolver._apply_damage(state, caster_id, target_id, amount, spell.damage_type, rng))
	var others: Array[String] = []
	for other_id: String in creatures_near(state, center, LIGHTNING_RADIUS_M, caster_id):
		if other_id != target_id:
			others.append(other_id)
	if not others.is_empty():
		var area: Dictionary = pending.duplicate()
		area["target_ids"] = others
		events.append_array(SpellResolver._resolve_area(state, caster_id, spell, area, rng))
	return events

static func _add(state: GameState, caster_id: String, target_id: String, spell: SpellDefinition,
		extra: Dictionary) -> Array[Dictionary]:
	var target: Dictionary = state.actors.get(target_id, {})
	if target.is_empty() or not CombatRules.alive(target):
		return []
	var effect: Dictionary = {"kind": String(spell.id), "source_id": caster_id, "spell_id": String(spell.id),
		"turn_of": caster_id}
	effect.merge(extra, true)
	# Recasting refreshes instead of stacking.
	ActiveEffects.remove_where(target, func(other: Dictionary) -> bool:
		return String(other.get("spell_id", "")) == String(spell.id))
	ActiveEffects.add(target, effect)
	return [{"type": "effect", "actor_id": target_id, "source_id": caster_id, "kind": String(spell.id),
		"spell_id": String(spell.id)}]

## Longstrider (+3 m) and Jump (+6 m): the target moves further every turn, at once on its own turn.
static func _speed_bonus(state: GameState, caster_id: String, target_id: String, spell: SpellDefinition,
		extra: Dictionary) -> Array[Dictionary]:
	var target: Dictionary = state.actors.get(target_id, {})
	if target.is_empty() or not CombatRules.alive(target):
		return []
	var had: float = 0.0
	for effect: Dictionary in ActiveEffects.effects(target):
		if String(effect.get("spell_id", "")) == String(spell.id):
			had = float(effect.get("amount", 0.0))
	ActiveEffects.remove_where(target, func(other: Dictionary) -> bool:
		return String(other.get("spell_id", "")) == String(spell.id))
	var effect: Dictionary = {"kind": "speed_bonus", "amount": spell.effect_amount, "source_id": caster_id,
		"spell_id": String(spell.id), "turn_of": caster_id}
	effect.merge(extra, true)
	ActiveEffects.add(target, effect)
	if state.mode == &"combat" and not state.turn_order.is_empty() and state.current_actor_id() == target_id:
		target["move_left"] = float(target.get("move_left", 0.0)) + spell.effect_amount - had
	return [{"type": "effect", "actor_id": target_id, "source_id": caster_id, "kind": String(spell.id),
		"spell_id": String(spell.id)}]

## Ends the first listed condition (Lesser Restoration) or all of them, with the effects that grant it.
static func _restore(state: GameState, target_id: String, conditions: Array, first_only: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: Dictionary = state.actors.get(target_id, {})
	if target.is_empty():
		return events
	for condition: String in conditions:
		if not condition in target.get("conditions", []):
			continue
		ActiveEffects.remove_where(target, func(effect: Dictionary) -> bool:
			return condition in ActiveEffects.granted_conditions(effect))
		target.get("conditions", []).erase(condition)
		events.append({"type": "condition_end", "actor_id": target_id, "condition": condition})
		if first_only:
			break
	return events

# ---------------------------------------------------------------- areas

## Living creatures whose centre is within radius_m of center (except `skip_id`).
static func creatures_near(state: GameState, center: Vector3, radius_m: float, skip_id: String) -> Array[String]:
	var result: Array[String] = []
	var ids: Array = state.actors.keys()
	ids.sort()
	for id: String in ids:
		var other: Dictionary = state.actors[id]
		if id == skip_id or not CombatRules.alive(other) or not other.get("position") is Vector3:
			continue
		if center.distance_to(other["position"]) <= radius_m + CombatRules.EPSILON:
			result.append(id)
	return result

## The caster and its living allies within range_m.
static func allies_near(state: GameState, caster_id: String, range_m: float) -> Array[String]:
	var result: Array[String] = []
	var caster: Dictionary = state.actors[caster_id]
	for id: String in creatures_near(state, caster["position"], range_m, ""):
		if state.actors[id].get("team") == caster.get("team"):
			result.append(id)
	return result

## Every active zone: [{"caster_id", "zone"}].
static func zones(state: GameState, spell_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = state.actors.keys()
	ids.sort()
	for id: String in ids:
		var zone: Dictionary = state.actors[id].get("concentration", {}).get("zone", {})
		if not zone.is_empty() and (spell_id.is_empty() or String(zone["spell_id"]) == spell_id):
			result.append({"caster_id": id, "zone": zone})
	return result

static func in_zone(zone: Dictionary, position: Vector3) -> bool:
	return (zone["center"] as Vector3).distance_to(position) <= float(zone["radius"]) + CombatRules.EPSILON

## Metres of the path inside the zone, sampled every SAMPLE_M.
static func distance_inside(zone: Dictionary, path: PackedVector3Array) -> float:
	var inside: float = 0.0
	for index: int in range(1, path.size()):
		var from: Vector3 = path[index - 1]
		var to: Vector3 = path[index]
		var length: float = from.distance_to(to)
		var steps: int = maxi(1, ceili(length / SAMPLE_M))
		for step: int in steps:
			var middle: Vector3 = from.lerp(to, (step + 0.5) / steps)
			if in_zone(zone, middle):
				inside += length / steps
	return inside

## Fog Cloud: creatures inside a fog are Blinded (they cannot see out, nobody sees in).
static func sync_fog(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var fogs: Array[Dictionary] = zones(state, "fog_cloud")
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		if not actor.get("position") is Vector3:
			continue
		var source_id: String = ""
		for entry: Dictionary in fogs:
			if in_zone(entry["zone"], actor["position"]):
				source_id = String(entry["caster_id"])
		var inside: bool = ActiveEffects.has_kind(actor, "fog_cloud")
		if not source_id.is_empty() and not inside:
			ActiveEffects.add(actor, {"kind": "fog_cloud", "condition": "blinded", "source_id": source_id,
				"spell_id": "fog_cloud", "turn_of": source_id, "until": "concentration"})
			events.append({"type": "condition", "actor_id": id, "condition": "blinded", "source_id": source_id})
		elif source_id.is_empty() and inside:
			ActiveEffects.remove_where(actor, func(effect: Dictionary) -> bool:
				return String(effect.get("kind", "")) == "fog_cloud")
			events.append({"type": "condition_end", "actor_id": id, "condition": "blinded"})
	return events

## Conjure Animals: a creature of the caster's choice (its enemies) entering the pack's
## reach or ending its turn there saves once per turn against 3d10 Slashing.
static func _pack_attack(state: GameState, entry: Dictionary, target_id: String,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var caster_id: String = String(entry["caster_id"])
	var zone: Dictionary = entry["zone"]
	var caster: Dictionary = state.actors[caster_id]
	var target: Dictionary = state.actors[target_id]
	if target.get("team") == caster.get("team") or not CombatRules.alive(target) or \
			String(zone["hits"].get(target_id, "")) == ActiveEffects.turn_key(state):
		return events
	zone["hits"][target_id] = ActiveEffects.turn_key(state)
	var spell: SpellDefinition = SpellBook.get_spell("conjure_animals")
	var save: Dictionary = SpellRules.roll_save(target, spell.save_ability, int(caster.get("spell_save_dc", 10)), rng,
		ClassEffects.save_modifiers(state, target_id, rng))
	events.append(ActiveEffects.save_event(caster_id, target_id, "conjure_animals", save))
	if not bool(save["success"]):
		var expression: String = SpellRules.damage_expression(spell, int(caster.get("level", 1)), int(zone["slot_level"]))
		events.append_array(SpellResolver._apply_damage_roll(state, caster_id, target_id, expression,
			spell.damage_type, [], rng))
	return events

# ---------------------------------------------------------------- hooks (ClassKits.EFFECT_MODULES)

## Remembers which creatures this attacker hit or missed with a weapon this turn.
static func after_attack(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		hit: bool, _rng: RandomNumberGenerator) -> Array[Dictionary]:
	var attacker: Dictionary = state.actors.get(attacker_id, {})
	if attacker.is_empty() or not String(weapon.get("spell_id", "")).is_empty():
		return []
	var key: String = ActiveEffects.turn_key(state)
	if String(attacker.get(STRIKES, {}).get("turn", "")) != key:
		attacker[STRIKES] = {"turn": key, "hit": [], "missed": [], "ranged_hit": [], "ranged_missed": []}
	var strikes: Dictionary = attacker[STRIKES]
	var ranged: bool = bool(weapon.get("ranged", false))
	for list: String in ["hit" if hit else "missed", ("ranged_hit" if hit else "ranged_missed") if ranged else ""]:
		if not list.is_empty() and not target_id in strikes[list]:
			strikes[list].append(target_id)
	return []

## Creatures the caster struck this turn that a strike spell may follow up on.
static func struck(state: GameState, caster_id: String, kind: String) -> Array:
	var strikes: Dictionary = state.actors.get(caster_id, {}).get(STRIKES, {})
	if String(strikes.get("turn", "")) != ActiveEffects.turn_key(state):
		return []
	match kind:
		"ensnaring_strike", "hit":
			return strikes["hit"]
		"hail_of_thorns", "ranged_hit":
			return strikes["ranged_hit"]
		"lightning_arrow":
			return strikes["ranged_hit"] + strikes["ranged_missed"]
	return []

static func resistances(actor: Dictionary) -> Array:
	var result: Array = []
	for effect: Dictionary in ActiveEffects.effects(actor):
		match String(effect.get("kind", "")):
			"protection_from_poison":
				result.append("poison")
			"protection_from_energy":
				result.append(String(effect.get("damage_type", DEFAULT_ENERGY)))
	return result

static func check_modifiers(actor: Dictionary, skill: String) -> Array:
	if skill == "stealth" and ActiveEffects.has_kind(actor, "pass_without_trace"):
		return [{"amount": PASS_WITHOUT_TRACE_BONUS, "source": "pass_without_trace"}]
	return []

## End of a creature's turn: Ensnaring Strike's thorns, the Conjure Animals pack.
static func on_turn_end(state: GameState, actor_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var actor: Dictionary = state.actors.get(actor_id, {})
	if actor.is_empty() or not CombatRules.alive(actor):
		return events
	for effect: Dictionary in ActiveEffects.effects(actor).duplicate():
		if String(effect.get("spell_id", "")) != "ensnaring_strike" or not CombatRules.alive(actor):
			continue
		var source_id: String = String(effect.get("source_id", ""))
		var dice: int = 1 + maxi(0, int(effect.get("slot_level", 1)) - 1)
		events.append_array(SpellResolver._apply_damage_roll(state, source_id, actor_id, "%dd6" % dice, &"piercing", [], rng))
	if actor.get("position") is Vector3:
		for entry: Dictionary in zones(state, "conjure_animals"):
			if in_zone(entry["zone"], actor["position"]):
				events.append_array(_pack_attack(state, entry, actor_id, rng))
	if not events.is_empty():
		events.append_array(CombatRules.check_combat_end(state))
	return events

## After a move: Spike Growth (2d4 Piercing per 1.5 m inside), the Conjure Animals pack
## (entering its reach), Fog Cloud (Blinded inside).
static func after_move(state: GameState, mover_id: String, path: Variant, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var mover: Dictionary = state.actors.get(mover_id, {})
	if mover.is_empty() or not path is PackedVector3Array:
		return events
	for entry: Dictionary in zones(state):
		if not CombatRules.alive(mover):
			break
		var zone: Dictionary = entry["zone"]
		match String(zone["spell_id"]):
			"spike_growth":
				var steps: int = floori((distance_inside(zone, path) + CombatRules.EPSILON) / SPIKE_STEP_M)
				if steps > 0:
					events.append_array(SpellResolver._apply_damage_roll(state, String(entry["caster_id"]), mover_id,
						"%dd4" % (2 * steps), &"piercing", [], rng))
			"conjure_animals":
				if distance_inside(zone, path) > 0.0:
					events.append_array(_pack_attack(state, entry, mover_id, rng))
	events.append_array(sync_fog(state))
	if not events.is_empty():
		events.append_array(CombatRules.check_combat_end(state))
	return events

static func on_combat_end(state: GameState, actor_id: String) -> void:
	state.actors[actor_id].erase(STRIKES)
