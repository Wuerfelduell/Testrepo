class_name ActiveEffects
extends RefCounted
## Timed spell and feature effects stored as plain data on actor records:
## {"kind", "source_id", "spell_id", "until": "start_of_turn"|"end_of_turn"|"concentration",
##  "turn_of", "amount", "stage", "save_dc"}. Conditions an effect grants are kept in
## the actor's "conditions" list and removed only when no other effect still grants them.

const SAP: StringName = &"sap"
## Rogue: Hide (SRD 5.2 Invisible while hidden), Steady Aim, Cunning Strike Poison.
const HIDDEN: String = "hidden"
const STEADY_AIM: String = "steady_aim"
const CUNNING_POISON: String = "cunning_poison"
## A conversation that ends in a fight can grant the hero advantage on its first attack
## (owner's Vaelor dialogue: he hesitates, or breaks down). Set by EncounterTriggerCommand.
const FIRST_STRIKE: String = "first_strike"

static func effects(actor: Dictionary) -> Array:
	return actor.get("effects", [])

static func add(actor: Dictionary, effect: Dictionary) -> void:
	if not actor.has("effects"):
		actor["effects"] = []
	actor["effects"].append(effect.duplicate(true))
	for condition: String in granted_conditions(effect):
		if not condition in actor.get("conditions", []):
			if not actor.has("conditions"):
				actor["conditions"] = []
			actor["conditions"].append(condition)

static func granted_condition(effect: Dictionary) -> String:
	var conditions: Array[String] = granted_conditions(effect)
	return conditions[0] if not conditions.is_empty() else ""

## Every condition an effect grants (class effects may grant several: Turn Undead).
static func granted_conditions(effect: Dictionary) -> Array[String]:
	if effect.has("condition"):
		# Class features (Stunning Strike) name the condition they grant.
		return [String(effect["condition"])]
	if String(effect.get("kind", "")) == "sleep":
		return ["unconscious" if int(effect.get("stage", 1)) >= 2 else "incapacitated"]
	return ClassEffects.granted_conditions(effect)

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
		for condition: String in granted_conditions(effect):
			var still_granted: bool = false
			for other: Dictionary in kept:
				if condition in granted_conditions(other):
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

## Effects that give disadvantage on the creature's next attack roll only.
const NEXT_ATTACK_DISADVANTAGE: Array[String] = ["sap", "vicious_mockery"]

static func attack_disadvantages(actor: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for kind: String in NEXT_ATTACK_DISADVANTAGE:
		if has_kind(actor, kind):
			result.append(StringName(kind))
	return result

## Advantage sources the attacker carries: hidden, Steady Aim and a first strike.
static func attack_advantages(actor: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	for kind: String in [HIDDEN, STEADY_AIM, FIRST_STRIKE]:
		if has_kind(actor, kind):
			result.append(StringName(kind))
	return result

## Attacks against a hidden creature have Disadvantage (SRD 5.2 Invisible).
static func incoming_disadvantages(target: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	if has_kind(target, HIDDEN):
		result.append(&"target_hidden")
	return result

## Sap, Vicious Mockery, Steady Aim and a first strike affect only the next attack roll;
## making an attack roll ends hiding.
static func consume_attack_riders(actor: Dictionary) -> void:
	remove_where(actor, func(effect: Dictionary) -> bool:
		var kind: String = String(effect.get("kind", ""))
		return kind in NEXT_ATTACK_DISADVANTAGE or kind in [HIDDEN, STEADY_AIM, FIRST_STRIKE])

## Bardic Inspiration: a failed attack roll or saving throw that the die could still
## turn into a success rolls it, adds it to the d20 roll and uses the inspiration up.
## Returns the roll event fields ({} when not used). needed = the AC or DC to reach.
static func inspire_roll(actor: Dictionary, roll: DiceResult, needed: int, rng: RandomNumberGenerator) -> Dictionary:
	if roll == null or not roll.is_valid() or roll.natural_1 or roll.total >= needed:
		return {}
	for effect: Dictionary in effects(actor):
		if String(effect.get("kind", "")) != "bardic_inspiration":
			continue
		var die: int = maxi(4, int(effect.get("die", 6)))
		if roll.total + die < needed:
			return {}
		var bonus: DiceResult = Dice.roll("1d%d" % die, rng)
		roll.add_modifiers([RuleModifier.new(bonus.total, &"bardic_inspiration")])
		remove_where(actor, func(other: Dictionary) -> bool: return String(other.get("kind", "")) == "bardic_inspiration")
		return {"die": die, "amount": bonus.total}
	return {}

## Riders of a save spell on a creature that failed the save: Vicious Mockery's
## disadvantage on its next attack (Hold Person and co. are ClassEffects.apply_effect).
static func save_rider(state: GameState, caster_id: String, target_id: String, spell: SpellDefinition,
		_dc: int) -> Array[Dictionary]:
	var target: Dictionary = state.actors[target_id]
	match String(spell.effect):
		"vicious_mockery":
			add(target, {"kind": "vicious_mockery", "source_id": caster_id, "spell_id": String(spell.id),
				"until": "start_of_turn", "turn_of": caster_id})
			return [{"type": "effect", "actor_id": target_id, "source_id": caster_id, "kind": "vicious_mockery"}]
	return []

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
	events.append_array(ClassEffects.on_turn_start(state, actor_id))
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
	remove_where(actor, func(effect: Dictionary) -> bool: return String(effect.get("until", "")) == "end_of_turn")
	# Cunning Strike Poison: the poisoned creature repeats the CON save at the end of each turn.
	for effect: Dictionary in effects(actor).duplicate():
		if String(effect.get("kind", "")) != CUNNING_POISON:
			continue
		var poison_save: Dictionary = SpellRules.roll_save(actor, &"con", int(effect.get("save_dc", 10)), rng)
		events.append(save_event(String(effect.get("source_id", "")), actor_id, "cunning_strike_poison", poison_save))
		if bool(poison_save["success"]):
			remove_where(actor, func(other: Dictionary) -> bool: return String(other.get("kind", "")) == CUNNING_POISON)
			events.append({"type": "condition_end", "actor_id": actor_id, "condition": "poisoned"})
	events.append_array(ClassEffects.on_turn_end(state, actor_id, rng))
	for effect: Dictionary in effects(actor).duplicate():
		if String(effect.get("kind", "")) != "sleep" or int(effect.get("stage", 1)) != 1:
			continue
		var save: Dictionary = SpellRules.roll_save(actor, &"wis", int(effect.get("save_dc", 10)), rng,
			ClassEffects.save_modifiers(state, actor_id, rng))
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
		"success": save["success"], "automatic": save.get("automatic", false), "reason": save.get("reason", ""), "roll": save["roll"]}

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
	var save: Dictionary = SpellRules.roll_save(target, &"con", SpellRules.concentration_dc(amount), rng,
		ClassEffects.save_modifiers(state, target_id, rng))
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

## Spirit Guardians: the concentrating caster's aura spell, or null.
static func aura_spell(caster: Dictionary) -> SpellDefinition:
	var concentration: Dictionary = caster.get("concentration", {})
	if concentration.is_empty() or not CombatRules.alive(caster):
		return null
	var spell: SpellDefinition = SpellBook.get_spell(String(concentration.get("spell_id", "")))
	return spell if spell != null and spell.effect == &"spirit_guardians" else null

## The emanation moves with its caster; walls (no line of sight) shield a creature.
static func in_aura(caster: Dictionary, spell: SpellDefinition, position: Vector3) -> bool:
	var center: Vector3 = caster["position"]
	return SpellRules.in_sphere(center, spell.area_size_m, position) and CombatSpace.current().visible(center, position)

## True while an enemy's Spirit Guardians surround this creature (its speed is halved there).
static func in_hostile_aura(state: GameState, actor_id: String) -> bool:
	var actor: Dictionary = state.actors.get(actor_id, {})
	if not actor.get("position") is Vector3:
		return false
	for id: String in state.actors:
		var caster: Dictionary = state.actors[id]
		var spell: SpellDefinition = aura_spell(caster)
		if spell != null and caster.get("team") != actor.get("team") and in_aura(caster, spell, actor["position"]):
			return true
	return false

## A creature makes the Spirit Guardians save only once per turn.
static func mark_aura_hit(state: GameState, caster_id: String, target_id: String) -> void:
	var concentration: Dictionary = state.actors[caster_id].get("concentration", {})
	if concentration.is_empty():
		return
	if not concentration.has("aura_hits"):
		concentration["aura_hits"] = {}
	concentration["aura_hits"][target_id] = _turn_key(state)

static func _turn_key(state: GameState) -> String:
	return turn_key(state)

## Identifies the current turn ("round:index"), e.g. for once-per-turn features.
static func turn_key(state: GameState) -> String:
	return "%d:%d" % [state.round_number, state.turn_index]

## Spirit Guardians after `actor_id` moved (moved = true) or ends its turn: the mover entering an enemy
## aura, or a moving caster bringing its aura onto enemies. Each creature saves once per
## turn (WIS, half damage on a success).
static func aura_triggers(state: GameState, actor_id: String, rng: RandomNumberGenerator,
		moved: bool = true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.mode != &"combat" or not state.actors.has(actor_id):
		return events
	var ids: Array = state.actors.keys()
	ids.sort()
	for caster_id: String in ids:
		var caster: Dictionary = state.actors[caster_id]
		var spell: SpellDefinition = aura_spell(caster)
		if spell == null:
			continue
		# The caster ending its own turn hurts nobody; only its movement carries the aura.
		if caster_id == actor_id and not moved:
			continue
		var targets: Array = ids if caster_id == actor_id else [actor_id]
		for target_id: String in targets:
			var target: Dictionary = state.actors[target_id]
			if target_id == caster_id or target.get("team") == caster.get("team") or not CombatRules.alive(target) \
					or not in_aura(caster, spell, target["position"]):
				continue
			var hits: Dictionary = caster["concentration"].get("aura_hits", {})
			if String(hits.get(target_id, "")) == _turn_key(state):
				continue
			mark_aura_hit(state, caster_id, target_id)
			var slot_level: int = int(caster["concentration"].get("slot_level", spell.level))
			var roll: DiceResult = Dice.roll(SpellRules.damage_expression(spell, int(caster.get("level", 1)), slot_level), rng)
			events.append({"type": "roll", "kind": "damage", "actor_id": caster_id, "target_id": target_id,
				"spell_id": String(spell.id), "roll": CombatRules.serialize_roll(roll),
				"damage_type": String(spell.damage_type), "amount": roll.total})
			var save: Dictionary = SpellRules.roll_save(target, spell.save_ability, int(caster.get("spell_save_dc", 10)), rng,
				ClassEffects.save_modifiers(state, target_id, rng))
			events.append(save_event(caster_id, target_id, String(spell.id), save))
			var raw: int = floori(roll.total / 2.0) if bool(save["success"]) else roll.total
			events.append_array(SpellResolver._apply_damage(state, caster_id, target_id, raw, spell.damage_type, rng))
			if aura_spell(caster) == null:
				break
	if not events.is_empty():
		events.append_array(CombatRules.check_combat_end(state))
	return events
