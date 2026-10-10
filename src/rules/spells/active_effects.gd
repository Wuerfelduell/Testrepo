class_name ActiveEffects
extends RefCounted
## Timed spell and feature effects stored as plain data on actor records:
## {"kind", "source_id", "spell_id", "until": "start_of_turn"|"end_of_turn"|"concentration",
##  "turn_of", "amount", "stage", "save_dc"}. Conditions an effect grants are kept in
## the actor's "conditions" list and removed only when no other effect still grants them.

const SAP: StringName = &"sap"

static func effects(actor: Dictionary) -> Array:
	return actor.get("effects", [])

static func add(actor: Dictionary, effect: Dictionary) -> void:
	if not actor.has("effects"):
		actor["effects"] = []
	actor["effects"].append(effect.duplicate(true))
	var condition: String = granted_condition(effect)
	if not condition.is_empty() and not condition in actor.get("conditions", []):
		if not actor.has("conditions"):
			actor["conditions"] = []
		actor["conditions"].append(condition)

static func granted_condition(effect: Dictionary) -> String:
	if String(effect.get("kind", "")) == "sleep":
		return "unconscious" if int(effect.get("stage", 1)) >= 2 else "incapacitated"
	return ""

static func has_kind(actor: Dictionary, kind: String) -> bool:
	for effect: Dictionary in effects(actor):
		if String(effect.get("kind", "")) == kind:
			return true
	return false

## Removes every effect matching the predicate and resynchronizes granted conditions.
static func remove_where(actor: Dictionary, predicate: Callable) -> int:
	var kept: Array = []
	var removed: Array = []
	for effect: Dictionary in effects(actor):
		if predicate.call(effect):
			removed.append(effect)
		else:
			kept.append(effect)
	if removed.is_empty():
		return 0
	actor["effects"] = kept
	for effect: Dictionary in removed:
		var condition: String = granted_condition(effect)
		if condition.is_empty():
			continue
		var still_granted: bool = false
		for other: Dictionary in kept:
			if granted_condition(other) == condition:
				still_granted = true
		if not still_granted:
			actor.get("conditions", []).erase(condition)
	return removed.size()

static func ac_bonus(actor: Dictionary) -> int:
	var total: int = 0
	for effect: Dictionary in effects(actor):
		if String(effect.get("kind", "")) == "shield":
			total += int(effect.get("amount", 0))
	return total

static func attack_disadvantages(actor: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	if has_kind(actor, String(SAP)):
		result.append(SAP)
	return result

## Sap affects only the next attack roll.
static func consume_attack_riders(actor: Dictionary) -> void:
	remove_where(actor, func(effect: Dictionary) -> bool: return String(effect.get("kind", "")) == String(SAP))

static func speed_penalty(actor: Dictionary) -> float:
	var total: float = 0.0
	for effect: Dictionary in effects(actor):
		if String(effect.get("kind", "")) == "speed_penalty":
			total += float(effect.get("amount", 0.0))
	return total

## Effects that last "until the start of X's next turn" end now; X's concentration ticks.
static func on_turn_start(state: GameState, actor_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for id: String in state.actors:
		var removed: int = remove_where(state.actors[id], func(effect: Dictionary) -> bool:
			return String(effect.get("until", "")) == "start_of_turn" and String(effect.get("turn_of", "")) == actor_id)
		if removed > 0:
			events.append({"type": "effects_expired", "actor_id": id})
	var caster: Dictionary = state.actors.get(actor_id, {})
	var concentration: Dictionary = caster.get("concentration", {})
	if not concentration.is_empty():
		concentration["rounds_left"] = int(concentration.get("rounds_left", 1)) - 1
		if int(concentration["rounds_left"]) <= 0:
			events.append_array(end_concentration(state, actor_id, "duration"))
	return events

## Sleep: a creature that is still incapacitated repeats the save at the end of its turn.
static func on_turn_end(state: GameState, actor_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var actor: Dictionary = state.actors.get(actor_id, {})
	if actor.is_empty() or not CombatRules.alive(actor):
		return events
	for effect: Dictionary in effects(actor).duplicate():
		if String(effect.get("kind", "")) != "sleep" or int(effect.get("stage", 1)) != 1:
			continue
		var save: Dictionary = SpellRules.roll_save(actor, &"wis", int(effect.get("save_dc", 10)), rng)
		events.append(save_event(String(effect.get("source_id", "")), actor_id, String(effect.get("spell_id", "sleep")), save))
		var source_id: String = String(effect.get("source_id", ""))
		remove_where(actor, func(other: Dictionary) -> bool:
			return String(other.get("kind", "")) == "sleep" and String(other.get("source_id", "")) == source_id)
		if bool(save["success"]):
			events.append({"type": "condition_end", "actor_id": actor_id, "condition": "incapacitated"})
		else:
			var deeper: Dictionary = effect.duplicate(true)
			deeper["stage"] = 2
			add(actor, deeper)
			events.append({"type": "condition", "actor_id": actor_id, "condition": "unconscious", "source_id": source_id})
	return events

static func save_event(caster_id: String, target_id: String, spell_id: String, save: Dictionary) -> Dictionary:
	return {"type": "roll", "kind": "save", "actor_id": target_id, "caster_id": caster_id,
		"target_id": target_id, "spell_id": spell_id, "ability": save["ability"], "dc": save["dc"],
		"success": save["success"], "automatic": save.get("automatic", false), "roll": save["roll"]}

## Called once per damage instance after HP changed: Sleep ends on a damaged
## creature, and a concentrating creature makes a CON save (or loses it at 0 HP).
static func after_damage(state: GameState, target_id: String, amount: int,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: Dictionary = state.actors.get(target_id, {})
	if target.is_empty() or amount <= 0:
		return events
	if remove_where(target, func(effect: Dictionary) -> bool: return String(effect.get("kind", "")) == "sleep") > 0:
		events.append({"type": "condition_end", "actor_id": target_id, "condition": "sleep"})
	var concentration: Dictionary = target.get("concentration", {})
	if concentration.is_empty():
		return events
	if not CombatRules.alive(target):
		events.append_array(end_concentration(state, target_id, "unconscious"))
		return events
	var save: Dictionary = SpellRules.roll_save(target, &"con", SpellRules.concentration_dc(amount), rng)
	var event: Dictionary = save_event(target_id, target_id, String(concentration.get("spell_id", "")), save)
	event["concentration"] = true
	events.append(event)
	if not bool(save["success"]):
		events.append_array(end_concentration(state, target_id, "damage"))
	return events

static func end_concentration(state: GameState, caster_id: String, reason: String) -> Array[Dictionary]:
	var caster: Dictionary = state.actors.get(caster_id, {})
	var concentration: Dictionary = caster.get("concentration", {})
	if concentration.is_empty():
		return []
	var spell_id: String = String(concentration.get("spell_id", ""))
	caster["concentration"] = {}
	for id: String in state.actors:
		remove_where(state.actors[id], func(effect: Dictionary) -> bool:
			return String(effect.get("source_id", "")) == caster_id and String(effect.get("until", "")) == "concentration")
	return [{"type": "concentration_end", "actor_id": caster_id, "spell_id": spell_id, "reason": reason}]

## Riders after a hit that did not kill: spell riders (Ray of Frost) and the
## Fighter's Weapon Mastery property of the weapon (Longsword: Sap).
static func on_hit(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: Dictionary = state.actors[target_id]
	for rider: Dictionary in weapon.get("on_hit", []):
		var effect: Dictionary = rider.duplicate(true)
		effect["source_id"] = attacker_id
		effect["turn_of"] = attacker_id
		effect["spell_id"] = String(weapon.get("spell_id", ""))
		add(target, effect)
		events.append({"type": "effect", "actor_id": target_id, "source_id": attacker_id, "kind": effect["kind"]})
	var attacker: Dictionary = state.actors[attacker_id]
	var mastery: String = String(weapon.get("mastery", ""))
	if mastery == "sap" and attacker.get("features", {}).has("weapon_mastery"):
		remove_where(target, func(effect: Dictionary) -> bool:
			return String(effect.get("kind", "")) == String(SAP) and String(effect.get("source_id", "")) == attacker_id)
		add(target, {"kind": String(SAP), "source_id": attacker_id, "turn_of": attacker_id, "until": "start_of_turn"})
		events.append({"type": "effect", "actor_id": target_id, "source_id": attacker_id, "kind": String(SAP)})
	return events
