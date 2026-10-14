class_name RestRules
extends RefCounted
## Short and Long Rest on plain hero records (SRD 5.2 rules glossary, Fighter and
## Wizard tables). Pure: no Nodes or singletons; dice only through the supplied generator.
## Rests are instant here: there is no world clock yet.

## Living enemies closer than this keep the party from resting.
const SAFE_DISTANCE_M: float = 20.0
## SRD 5.2: a Long Rest restores ALL spent Hit Point Dice (the 2014 rule was half).
const LONG_REST_HIT_DICE_FRACTION: float = 1.0

static func ensure_hit_dice(actor: Dictionary) -> void:
	if actor.get("hit_dice") is Dictionary:
		return
	var level: int = int(actor.get("level", 1))
	actor["hit_dice"] = {"die": ProgressionRules.hit_die(actor), "max": level, "left": level}

static func enemies_nearby(state: GameState, actor_id: String) -> bool:
	var actor: Dictionary = state.actors.get(actor_id, {})
	if not actor.get("position") is Vector3:
		return false
	for id: String in state.actors:
		var other: Dictionary = state.actors[id]
		if other.get("team") == "enemy" and CombatRules.alive(other) and other.get("position") is Vector3 and \
				(other["position"] as Vector3).distance_to(actor["position"]) < SAFE_DISTANCE_M:
			return true
	return false

## Shared conditions for both rests: "" or a REST_REASON_* key.
static func rest_reason(state: GameState, actor_id: String) -> String:
	var actor: Dictionary = state.actors.get(actor_id, {})
	if actor.is_empty() or actor.get("team") != "hero" or not CombatRules.alive(actor) or \
			not ClassFeatures.is_active_class(actor):
		return "REST_REASON_UNKNOWN"
	if state.mode != &"exploration":
		return "REST_REASON_COMBAT"
	if not state.pending.is_empty():
		return "REST_REASON_BUSY"
	if enemies_nearby(state, actor_id):
		return "REST_REASON_ENEMIES"
	return ""

static func hit_dice_left(actor: Dictionary) -> int:
	if actor.get("hit_dice") is Dictionary:
		return int(actor["hit_dice"].get("left", 0))
	return int(actor.get("level", 1))

static func arcane_recovery_available(actor: Dictionary) -> bool:
	var feature: Dictionary = actor.get("features", {}).get("arcane_recovery", {})
	return not feature.is_empty() and not bool(feature.get("used", false))

static func memorize_available(actor: Dictionary) -> bool:
	return actor.get("features", {}).has("memorize_spell")

static func short_rest_reason(state: GameState, actor_id: String, hit_dice: int,
		arcane_slots: Array[int], memorize: Array[String]) -> String:
	var reason: String = rest_reason(state, actor_id)
	if not reason.is_empty():
		return reason
	var actor: Dictionary = state.actors[actor_id]
	if hit_dice < 0 or hit_dice > hit_dice_left(actor):
		return "REST_REASON_HIT_DICE"
	if not arcane_slots.is_empty():
		if not arcane_recovery_available(actor):
			return "REST_REASON_ARCANE"
		var slots: Array = actor.get("spell_slots", []).duplicate()
		if not SpellRules.arcane_recovery(slots, actor.get("spell_slots_max", []), int(actor.get("level", 1)), arcane_slots):
			return "REST_REASON_ARCANE"
	if not memorize.is_empty():
		if not memorize_available(actor) or memorize.size() != 2:
			return "REST_REASON_MEMORIZE"
		var prepared: Array[String] = ClassFeatures.prepared_spells(actor)
		if not memorize[0] in prepared or memorize[1] in prepared or \
				not memorize[1] in ClassFeatures.spellbook(actor):
			return "REST_REASON_MEMORIZE"
	return ""

## Hit Point Dice: each die + Con modifier. Second Wind regains one use, Action Surge
## all uses, Arcane Recovery and Memorize Spell happen when requested.
static func short_rest(actor: Dictionary, actor_id: String, hit_dice: int, arcane_slots: Array[int],
		memorize: Array[String], rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	ensure_hit_dice(actor)
	var dice: Dictionary = actor["hit_dice"]
	var constitution: int = Abilities.modifier(ProgressionRules.score(actor, "con"))
	var healed_total: int = 0
	for index: int in hit_dice:
		var modifiers: Array[RuleModifier] = []
		if constitution != 0:
			modifiers.append(RuleModifier.new(constitution, &"con"))
		var roll: DiceResult = Dice.roll("1d%d" % int(dice["die"]), rng, modifiers)
		dice["left"] = int(dice["left"]) - 1
		var healed: int = clampi(roll.total, 0, int(actor["max_hp"]) - int(actor["hp"]))
		actor["hp"] = int(actor["hp"]) + healed
		healed_total += healed
		events.append({"type": "roll", "kind": "healing", "actor_id": actor_id, "target_id": actor_id,
			"feature_id": "hit_dice", "roll": CombatRules.serialize_roll(roll), "amount": healed})
	var features: Dictionary = actor.get("features", {})
	var recharged: Array[String] = []
	if features.has("second_wind"):
		var second_wind: Dictionary = features["second_wind"]
		if int(second_wind["uses"]) < int(second_wind["max"]):
			second_wind["uses"] = int(second_wind["uses"]) + 1
			recharged.append("second_wind")
	if features.has("action_surge"):
		var surge: Dictionary = features["action_surge"]
		if int(surge["uses"]) < int(surge["max"]):
			surge["uses"] = int(surge["max"])
			recharged.append("action_surge")
	recharged.append_array(ClassEffects.short_rest(actor))
	if not arcane_slots.is_empty():
		SpellRules.arcane_recovery(actor["spell_slots"], actor["spell_slots_max"], int(actor.get("level", 1)), arcane_slots)
		features["arcane_recovery"]["used"] = true
		recharged.append("arcane_recovery")
	if not memorize.is_empty():
		var prepared: Array[String] = ClassFeatures.prepared_spells(actor)
		prepared[prepared.find(memorize[0])] = memorize[1]
		ClassFeatures.set_prepared(actor, prepared)
	events.append({"type": "rest", "rest": "short", "actor_id": actor_id, "healed": healed_total,
		"hit_dice_spent": hit_dice, "recharged": recharged, "hp": actor["hp"]})
	return events

static func long_rest_reason(state: GameState, actor_id: String, prepared: Array[String]) -> String:
	var reason: String = rest_reason(state, actor_id)
	if not reason.is_empty() or prepared.is_empty():
		return reason
	var actor: Dictionary = state.actors[actor_id]
	var class_id: String = String(actor.get("class_id", ""))
	if not ClassSpellcasting.is_caster(class_id) or \
			prepared.size() > ClassSpellcasting.prepared_limit(class_id, int(actor.get("level", 1))):
		return "REST_REASON_PREPARED"
	var book: Array[String] = ClassSpellcasting.preparable(actor)
	var seen: Array[String] = []
	for spell_id: String in prepared:
		if not spell_id in book or spell_id in seen:
			return "REST_REASON_PREPARED"
		seen.append(spell_id)
	return ""

## Full HP, all spell slots, all Hit Point Dice (SRD 5.2), every feature use. A
## prepared caster may change the prepared list (empty = unchanged).
static func long_rest(actor: Dictionary, actor_id: String, prepared: Array[String] = []) -> Array[Dictionary]:
	ensure_hit_dice(actor)
	var dice: Dictionary = actor["hit_dice"]
	var restored: int = maxi(1, floori(int(dice["max"]) * LONG_REST_HIT_DICE_FRACTION))
	dice["left"] = mini(int(dice["max"]), int(dice["left"]) + restored)
	var healed: int = int(actor["max_hp"]) - int(actor["hp"])
	actor["hp"] = int(actor["max_hp"])
	if actor.has("spell_slots_max"):
		actor["spell_slots"] = actor["spell_slots_max"].duplicate()
	var features: Dictionary = actor.get("features", {})
	for feature_id: String in ["second_wind", "action_surge"]:
		if features.has(feature_id):
			features[feature_id]["uses"] = int(features[feature_id]["max"])
	if features.has("arcane_recovery"):
		features["arcane_recovery"]["used"] = false
	ClassEffects.long_rest(actor)
	if not prepared.is_empty():
		ClassFeatures.set_prepared(actor, prepared)
	return [{"type": "rest", "rest": "long", "actor_id": actor_id, "healed": healed,
		"hit_dice_left": dice["left"], "hp": actor["hp"]}]
