extends RefCounted
## Monk, SRD 5.2 p. 49-51, levels 1-10 without subclass (ClassKits interface, see
## README.md). Martial Arts, Unarmored Defense, Monk's Focus (Flurry of Blows, Patient
## Defense, Step of the Wind), Unarmored Movement, Uncanny Metabolism, Deflect Attacks,
## Extra Attack, Stunning Strike, Evasion and Heightened Focus.

const PRIORITY: Array[StringName] = [&"dex", &"wis", &"con", &"str", &"int", &"cha"]
const SKILLS: Dictionary = {"class": [&"acrobatics", &"insight"], "human": &"perception"}
const FEATURES: Array[String] = ["martial_arts", "flurry_of_blows", "patient_defense", "step_of_the_wind",
	"stunning_strike"]
## Martial Arts die and Unarmored Movement per level (index 0 = level 1).
const MARTIAL_ARTS_DIE: Array[int] = [6, 6, 6, 6, 8, 8, 8, 8, 8, 8]
const UNARMORED_MOVEMENT_M: Array[float] = [0.0, 3.0, 3.0, 3.0, 3.0, 4.5, 4.5, 4.5, 4.5, 6.0]
const DEFLECT_TYPES: Array[String] = ["bludgeoning", "piercing", "slashing"]
const DATA_ONLY: Dictionary = {
	"slow_fall": "there is no falling damage in play",
	"empowered_strikes": "attacks always use the weapon's damage type",
	"acrobatic_movement": "no walls or water to run along yet",
	"self_restoration": "charmed, frightened and poisoned end on their own; no exhaustion yet",
}

static func martial_arts_die(actor: Dictionary) -> int:
	return MARTIAL_ARTS_DIE[clampi(int(actor.get("level", 1)), 1, 10) - 1]

static func unarmored(actor: Dictionary) -> bool:
	return not ClassKits.wears_armor(actor) and not bool(actor.get("shield", false))

static func focus_dc(actor: Dictionary) -> int:
	return 8 + Abilities.modifier(ClassKits.score(actor, "wis")) + int(actor.get("proficiency_bonus", 2))

static func activate(_record: Dictionary) -> void:
	pass

static func advance(actor: Dictionary, level: int) -> void:
	var features: Dictionary = actor["features"]
	features["martial_arts"] = {"die": MARTIAL_ARTS_DIE[clampi(level, 1, 10) - 1]}
	if level >= 2:
		ClassKits.set_uses(features, "focus", level, "short")
		features["flurry_of_blows"] = {"strikes": 3 if level >= 10 else 2}
		features["patient_defense"] = {}
		features["step_of_the_wind"] = {}
		ClassKits.set_uses(features, "uncanny_metabolism", 1, "long")
	if level >= 3:
		features["deflect_attacks"] = {}
	if level >= 5:
		features["extra_attack"] = {"attacks": 2}
		features["stunning_strike"] = {}
	if level >= 7:
		features["evasion"] = {}

# --- Defense and movement ----------------------------------------------------

## Unarmored Defense: 10 + Dexterity + Wisdom, without armour and without a Shield.
static func unarmored_ac(actor: Dictionary, shield: bool) -> int:
	if shield:
		return 0
	return 10 + Abilities.modifier(ClassKits.score(actor, "dex")) + Abilities.modifier(ClassKits.score(actor, "wis"))

static func speed_bonus_m(actor: Dictionary) -> float:
	if not unarmored(actor):
		return 0.0
	return UNARMORED_MOVEMENT_M[clampi(int(actor.get("level", 1)), 1, 10) - 1]

static func evades(actor: Dictionary, ability: StringName) -> bool:
	return ability == &"dex" and actor.get("features", {}).has("evasion") and \
		not CombatRules.conditions_for(actor).has(&"incapacitated")

# --- Martial Arts on weapon records -----------------------------------------

## Monk weapons: Simple melee weapons and Martial melee weapons with the Light property.
static func monk_weapon(item: Dictionary) -> bool:
	if String(item.get("kind", "")) != "melee":
		return false
	return String(item.get("category", "")) == "simple" or "light" in item.get("properties", [])

## Martial Arts: Dexterity instead of Strength if higher, the Martial Arts die if it is
## bigger, and proficiency with Light Martial weapons (SRD 5.2 Monk weapon training).
static func adjust_weapon(actor: Dictionary, record: Dictionary, item: Dictionary) -> void:
	if not monk_weapon(item):
		return
	record["monk_weapon"] = true
	if not bool(record.get("proficient", false)):
		var proficiency: int = int(actor.get("proficiency_bonus", 2))
		record["proficient"] = true
		record["attack_modifiers"].append({"amount": proficiency, "source": "proficiency"})
		record["attack_bonus"] = int(record["attack_bonus"]) + proficiency
	if not unarmored(actor) and actor.has("armor"):
		return
	var dex: int = Abilities.modifier(ClassKits.score(actor, "dex"))
	var used: Dictionary = record["damage_modifiers"][0]
	if String(used.get("source", "")) == "str" and dex > int(used["amount"]):
		var delta: int = dex - int(used["amount"])
		for kind: String in ["attack", "damage"]:
			for modifier: Dictionary in record[kind + "_modifiers"]:
				if String(modifier.get("source", "")) == "str":
					modifier["source"] = "dex"
					modifier["amount"] = dex
			record[kind + "_bonus"] = int(record[kind + "_bonus"]) + delta
	var die: int = MARTIAL_ARTS_DIE[clampi(int(actor.get("level", 1)), 1, 10) - 1]
	var parsed: Dictionary = Dice.parse(String(record["damage_dice"]))
	if int(parsed.get("count", 1)) == 1 and int(parsed.get("sides", 0)) < die:
		record["damage_dice"] = "1d%d" % die
		record["martial_arts_die"] = true

# --- Attacks ------------------------------------------------------------------

static func attack_advantages(state: GameState, attacker_id: String, target_id: String, _weapon: Dictionary) -> Array[StringName]:
	var mark: Dictionary = state.actors[attacker_id].get("stun_mark", {})
	return [&"stunning_strike"] if String(mark.get("target_id", "")) == target_id else []

## Patient Defense with Focus: the Dodge action until the start of the Monk's next turn.
static func incoming_disadvantages(state: GameState, attacker_id: String, target_id: String, _weapon: Dictionary) -> Array[StringName]:
	var target: Dictionary = state.actors[target_id]
	if ActiveEffects.has_kind(target, "dodge") and CombatRules.conditions_for(target).can_act():
		var attacker: Dictionary = state.actors.get(attacker_id, {})
		if attacker.get("position") is Vector3 and target.get("position") is Vector3 and \
				CombatSpace.current().visible(attacker["position"], target["position"]):
			return [&"dodge"]
	return []

static func save_advantages(actor: Dictionary, ability: StringName) -> Array[StringName]:
	if ability == &"dex" and ActiveEffects.has_kind(actor, "dodge"):
		return [&"dodge"]
	return []

static func after_attack(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		hit: bool, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var attacker: Dictionary = state.actors[attacker_id]
	var events: Array[Dictionary] = []
	if String(attacker.get("stun_mark", {}).get("target_id", "")) == target_id:
		attacker.erase("stun_mark")
	var target: Dictionary = state.actors.get(target_id, {})
	if not hit or target.is_empty() or not CombatRules.alive(target) or not bool(weapon.get("monk_weapon", false)):
		return events
	# Stunning Strike: armed from the hotbar, once per turn, 1 Focus Point.
	if not bool(attacker.get("stunning_armed", false)) or bool(attacker.get("stunning_used", false)) or \
			int(attacker["features"].get("focus", {}).get("uses", 0)) <= 0:
		return events
	attacker["features"]["focus"]["uses"] = int(attacker["features"]["focus"]["uses"]) - 1
	attacker["stunning_used"] = true
	attacker["stunning_armed"] = false
	var save: Dictionary = SpellRules.roll_save(target, &"con", focus_dc(attacker), rng)
	events.append(ActiveEffects.save_event(attacker_id, target_id, "stunning_strike", save))
	if bool(save["success"]):
		# Half Speed and advantage on the next attack against it, until the Monk's next turn.
		ActiveEffects.add(target, {"kind": "speed_penalty", "amount": float(target.get("speed_m", 9.0)) * 0.5,
			"source_id": attacker_id, "turn_of": attacker_id, "until": "start_of_turn"})
		attacker["stun_mark"] = {"target_id": target_id}
		events.append({"type": "effect", "actor_id": target_id, "source_id": attacker_id, "kind": "stunning_strike"})
	else:
		ActiveEffects.add(target, {"kind": "stunning_strike", "condition": "stunned", "source_id": attacker_id,
			"turn_of": attacker_id, "until": "start_of_turn"})
		events.append({"type": "condition", "actor_id": target_id, "condition": "stunned", "source_id": attacker_id})
	return events

## Deflect Attacks: the Reaction lowers a bludgeoning, piercing or slashing hit by
## 1d10 + Dexterity + Monk level. Used automatically while the Reaction is free.
static func damage_reduction(state: GameState, _attacker_id: String, target_id: String, weapon: Dictionary,
		amount: int, rng: RandomNumberGenerator) -> Dictionary:
	var monk: Dictionary = state.actors[target_id]
	if amount <= 0 or not monk.get("features", {}).has("deflect_attacks") or \
			not bool(monk.get("reaction_available", false)) or not CombatRules.conditions_for(monk).can_act() or \
			not String(weapon.get("damage_type", "")) in DEFLECT_TYPES or not weapon.get("spell_id", "") in ["", null]:
		return {}
	monk["reaction_available"] = false
	var dex: int = Abilities.modifier(ClassKits.score(monk, "dex"))
	var roll: DiceResult = Dice.roll("1d10", rng, [RuleModifier.new(dex, &"dex"),
		RuleModifier.new(int(monk.get("level", 1)), &"monk_level")])
	var reduced: int = mini(amount, maxi(0, roll.total))
	return {"amount": reduced, "events": [{"type": "roll", "kind": "deflect", "actor_id": target_id,
		"target_id": target_id, "feature_id": "deflect_attacks", "roll": CombatRules.serialize_roll(roll), "amount": reduced}]}

# --- Turns --------------------------------------------------------------------

static func on_turn_start(state: GameState, actor_id: String) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	actor.erase("stunning_used")
	actor.erase("stun_mark")
	var events: Array[Dictionary] = []
	# Uncanny Metabolism: on the Monk's first turn of a fight (the SRD says when rolling
	# Initiative), all Focus Points return and it heals Martial Arts die + Monk level.
	var metabolism: Dictionary = actor.get("features", {}).get("uncanny_metabolism", {})
	if not bool(actor.get("metabolism_checked", false)) and int(metabolism.get("uses", 0)) > 0:
		actor["metabolism_checked"] = true
		var focus: Dictionary = actor["features"].get("focus", {})
		if int(focus.get("uses", 0)) < int(focus.get("max", 0)):
			metabolism["uses"] = int(metabolism["uses"]) - 1
			focus["uses"] = int(focus["max"])
			# begin_turn has no generator, so the die counts as its fixed average (rounded up).
			var amount: int = int(martial_arts_die(actor) * 0.5) + 1 + int(actor.get("level", 1))
			var healed: int = mini(amount, int(actor["max_hp"]) - int(actor["hp"]))
			actor["hp"] = int(actor["hp"]) + healed
			events.append({"type": "feature", "actor_id": actor_id, "feature_id": "uncanny_metabolism"})
			events.append({"type": "heal", "actor_id": actor_id, "target_id": actor_id, "amount": healed, "hp": actor["hp"]})
	return events

static func on_combat_end(state: GameState, actor_id: String) -> void:
	var actor: Dictionary = state.actors[actor_id]
	for key: String in ["stunning_used", "stunning_armed", "stun_mark", "metabolism_checked"]:
		actor.erase(key)

# --- Hotbar -------------------------------------------------------------------

static func feature_buttons(actor: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var features: Dictionary = actor.get("features", {})
	for feature_id: String in FEATURES:
		if features.has(feature_id):
			result.append(feature_id)
	return result

static func feature_label(actor: Dictionary, feature_id: String) -> String:
	var focus: Dictionary = actor.get("features", {}).get("focus", {})
	var points: String = TranslationServer.translate("FEATURE_FOCUS_POINTS") % [int(focus.get("uses", 0)), int(focus.get("max", 0))]
	match feature_id:
		"martial_arts":
			return TranslationServer.translate("FEATURE_MARTIAL_ARTS_BUTTON")
		"stunning_strike":
			var key: String = "FEATURE_STUNNING_STRIKE_ON" if bool(actor.get("stunning_armed", false)) else "FEATURE_STUNNING_STRIKE_BUTTON"
			return TranslationServer.translate(key) + "\n" + points
	return TranslationServer.translate("FEATURE_%s_BUTTON" % feature_id.to_upper()) + "\n" + points

static func feature_reason(state: GameState, actor_id: String, feature_id: String) -> String:
	if CombatRules.valid_actor_turn(state, actor_id) != OK:
		return "COMBAT_WAIT_TURN"
	var actor: Dictionary = state.actors[actor_id]
	if not CombatRules.conditions_for(actor).can_act():
		return "SPELL_REASON_INCAPACITATED"
	var focus: int = int(actor["features"].get("focus", {}).get("uses", 0))
	if feature_id == "stunning_strike":
		if bool(actor.get("stunning_used", false)):
			return "FEATURE_STUNNING_STRIKE_USED"
		return "" if focus > 0 or bool(actor.get("stunning_armed", false)) else "FEATURE_NO_FOCUS"
	if not bool(actor.get("bonus_available", false)):
		return "COMBAT_NO_BONUS"
	if feature_id != "martial_arts" and focus <= 0:
		return "FEATURE_NO_FOCUS"
	return ""

static func spend_focus(actor: Dictionary) -> void:
	actor["features"]["focus"]["uses"] = int(actor["features"]["focus"]["uses"]) - 1

static func use_feature(state: GameState, actor_id: String, feature_id: String, _rng: RandomNumberGenerator) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	var events: Array[Dictionary] = [{"type": "feature", "actor_id": actor_id, "feature_id": feature_id}]
	match feature_id:
		"martial_arts":
			# Bonus Action strike; the attack itself is the next click on an enemy.
			actor["bonus_available"] = false
			actor["attacks_left"] = int(actor.get("attacks_left", 0)) + 1
		"flurry_of_blows":
			actor["bonus_available"] = false
			spend_focus(actor)
			actor["attacks_left"] = int(actor.get("attacks_left", 0)) + int(actor["features"]["flurry_of_blows"].get("strikes", 2))
		"patient_defense":
			# With Focus: Disengage and Dodge.
			actor["bonus_available"] = false
			spend_focus(actor)
			actor["disengaged"] = true
			ActiveEffects.add(actor, {"kind": "dodge", "source_id": actor_id, "turn_of": actor_id, "until": "start_of_turn"})
		"step_of_the_wind":
			# With Focus: Dash and Disengage.
			actor["bonus_available"] = false
			spend_focus(actor)
			actor["disengaged"] = true
			actor["move_left"] = float(actor.get("move_left", 0.0)) + float(actor.get("speed_m", 9.0))
		"stunning_strike":
			actor["stunning_armed"] = not bool(actor.get("stunning_armed", false))
	return events
