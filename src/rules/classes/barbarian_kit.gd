extends RefCounted
## Barbarian, SRD 5.2 p. 28-30, levels 1-10 without subclass (ClassKits interface,
## see README.md). Rage, Unarmored Defense, Weapon Mastery, Danger Sense, Reckless
## Attack, Primal Knowledge, Extra Attack, Fast Movement, Feral Instinct, Instinctive
## Pounce and Brutal Strike.

const PRIORITY: Array[StringName] = [&"str", &"con", &"dex", &"wis", &"cha", &"int"]
const SKILLS: Dictionary = {"class": [&"athletics", &"intimidation"], "human": &"perception"}
const FEATURES: Array[String] = ["rage", "reckless_attack", "brutal_strike"]
## SRD 5.2 Barbarian table, index 0 = level 1.
const RAGES: Array[int] = [2, 2, 3, 3, 3, 4, 4, 4, 4, 4]
const RAGE_DAMAGE: Array[int] = [2, 2, 2, 2, 2, 2, 2, 2, 3, 3]
const MASTERIES: Array[int] = [2, 2, 2, 3, 3, 3, 3, 3, 3, 4]
const START_MASTERY: Array[String] = ["greataxe", "handaxe"]
const RAGE_RESISTANCES: Array[String] = ["bludgeoning", "piercing", "slashing"]
## Fast Movement (level 5): +10 feet without Heavy armour.
const FAST_MOVEMENT_M: float = 3.0
const DATA_ONLY: Dictionary = {
	"primal_knowledge": "the extra skill works; Strength for skill checks while raging needs skill checks in combat",
}

static func activate(record: Dictionary) -> void:
	record["features"]["weapon_mastery"] = {"weapons": START_MASTERY.duplicate()}

static func advance(actor: Dictionary, level: int) -> void:
	var features: Dictionary = actor["features"]
	var index: int = clampi(level, 1, 10) - 1
	ClassKits.set_uses(features, "rage", RAGES[index], "long", 1)
	features["rage"]["damage"] = RAGE_DAMAGE[index]
	if level >= 2:
		features["danger_sense"] = {}
		features["reckless_attack"] = {}
	if level >= 5:
		features["extra_attack"] = {"attacks": 2}
		features["fast_movement"] = {}
	if level >= 7:
		features["feral_instinct"] = {}
		features["instinctive_pounce"] = {}
	if level >= 9:
		features["brutal_strike"] = {"dice": "1d10"}

## Weapon Mastery grows at 4 and 10; Primal Knowledge (3) adds one Barbarian skill.
static func level_choices(actor: Dictionary, level: int) -> Array:
	var result: Array = []
	var extra: int = MASTERIES[clampi(level, 1, 10) - 1] - MASTERIES[clampi(level - 1, 1, 10) - 1]
	if extra > 0:
		result.append({"key": "weapon_mastery", "count": extra, "title_key": "LEVELUP_SECTION_MASTERY",
			"options": WeaponMasteries.options(actor, [&"simple", &"martial"]), "option_prefix": "ITEM_"})
	if level == 3:
		var definition: ClassDefinition = load("res://data/classes/barbarian.tres") as ClassDefinition
		var options: Array[String] = []
		for skill: StringName in definition.skill_choices:
			if not skill in actor.get("skill_proficiencies", []) and not String(skill) in actor.get("skill_proficiencies", []):
				options.append(String(skill))
		result.append({"key": "primal_knowledge", "count": 1, "title_key": "LEVELUP_SECTION_PRIMAL_KNOWLEDGE",
			"options": options, "option_prefix": "SHEET_SKILL_"})
	return result

static func apply_level_choices(actor: Dictionary, _level: int, picks: Dictionary) -> void:
	for item_id: Variant in picks.get("weapon_mastery", []):
		actor["features"]["weapon_mastery"]["weapons"].append(String(item_id))
	if picks.has("primal_knowledge"):
		var skills: Array = actor.get("skill_proficiencies", []).duplicate()
		for skill: Variant in picks["primal_knowledge"]:
			skills.append(StringName(String(skill)))
		actor["skill_proficiencies"] = skills

# --- Defense and movement ----------------------------------------------------

## Unarmored Defense: 10 + Dexterity + Constitution; a Shield still counts.
static func unarmored_ac(actor: Dictionary, shield: bool) -> int:
	return 10 + Abilities.modifier(ClassKits.score(actor, "dex")) + Abilities.modifier(ClassKits.score(actor, "con")) + \
		(2 if shield else 0)

static func speed_bonus_m(actor: Dictionary) -> float:
	if actor.get("features", {}).has("fast_movement") and not ClassKits.heavy_armor(actor):
		return FAST_MOVEMENT_M
	return 0.0

static func raging(actor: Dictionary) -> bool:
	return not actor.get("rage_state", {}).is_empty()

static func resistances(actor: Dictionary) -> Array:
	return RAGE_RESISTANCES.duplicate() if raging(actor) else []

## Rage: advantage on Strength saves. Danger Sense: advantage on Dexterity saves.
static func save_advantages(actor: Dictionary, ability: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	if ability == &"str" and raging(actor):
		result.append(&"rage")
	if ability == &"dex" and actor.get("features", {}).has("danger_sense") and \
			not CombatRules.conditions_for(actor).has(&"incapacitated"):
		result.append(&"danger_sense")
	return result

static func initiative_advantages(actor: Dictionary) -> Array[StringName]:
	return [&"feral_instinct"] if actor.get("features", {}).has("feral_instinct") else []

# --- Attacks ------------------------------------------------------------------

static func strength_attack(weapon: Dictionary) -> bool:
	if not weapon.get("spell_id", "") in ["", null]:
		return false
	for modifier: Dictionary in weapon.get("attack_modifiers", []):
		if String(modifier.get("source", "")) == "str":
			return true
	return false

static func reckless(actor: Dictionary) -> bool:
	return ActiveEffects.has_kind(actor, "reckless_attack")

static func attack_advantages(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> Array[StringName]:
	var attacker: Dictionary = state.actors[attacker_id]
	var result: Array[StringName] = WeaponMasteries.attack_advantages(state, attacker_id, target_id)
	# Brutal Strike gives up Reckless Attack's advantage on this one attack.
	if reckless(attacker) and strength_attack(weapon) and not bool(weapon.get("ranged", false)) and \
			not bool(attacker.get("brutal_pending", false)):
		result.append(&"reckless_attack")
	return result

## Reckless Attack: attack rolls against the Barbarian have advantage until its next turn.
static func incoming_advantages(state: GameState, _attacker_id: String, target_id: String, _weapon: Dictionary) -> Array[StringName]:
	return [&"reckless_attack"] if reckless(state.actors[target_id]) else []

## Rage Damage on Strength-based attacks.
static func damage_bonus(state: GameState, attacker_id: String, _target_id: String, weapon: Dictionary) -> Array:
	var attacker: Dictionary = state.actors[attacker_id]
	if raging(attacker) and strength_attack(weapon):
		return [{"amount": int(attacker["features"]["rage"].get("damage", 2)), "source": "rage"}]
	return []

static func extra_damage_dice(state: GameState, attacker_id: String, _target_id: String, weapon: Dictionary,
		_critical: bool) -> Array:
	var attacker: Dictionary = state.actors[attacker_id]
	if bool(attacker.get("brutal_pending", false)) and strength_attack(weapon):
		return [{"dice": String(attacker["features"]["brutal_strike"].get("dice", "1d10")), "source": "brutal_strike"}]
	return []

static func expected_extra_damage(state: GameState, attacker_id: String, _target_id: String, weapon: Dictionary) -> float:
	var attacker: Dictionary = state.actors[attacker_id]
	return 5.5 if bool(attacker.get("brutal_pending", false)) and strength_attack(weapon) else 0.0

static func after_attack(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		hit: bool, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var attacker: Dictionary = state.actors[attacker_id]
	var events: Array[Dictionary] = []
	attacker["attacked_this_turn"] = true
	if raging(attacker):
		# Attacking an enemy keeps the Rage going.
		attacker["rage_state"]["extended"] = true
	if bool(attacker.get("brutal_pending", false)) and strength_attack(weapon):
		attacker.erase("brutal_pending")
		var target: Dictionary = state.actors.get(target_id, {})
		if hit and not target.is_empty() and CombatRules.alive(target):
			# Hamstring Blow: the target's Speed drops by 4.5 m until the start of the Barbarian's next turn.
			ActiveEffects.add(target, {"kind": "speed_penalty", "amount": 4.5, "source_id": attacker_id,
				"turn_of": attacker_id, "until": "start_of_turn"})
			events.append({"type": "effect", "actor_id": target_id, "source_id": attacker_id, "kind": "hamstring_blow"})
	events.append_array(WeaponMasteries.after_attack(state, attacker_id, target_id, weapon, hit, rng))
	return events

# --- Turns --------------------------------------------------------------------

static func on_turn_start(state: GameState, actor_id: String) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	actor["attacked_this_turn"] = false
	actor.erase("brutal_pending")
	WeaponMasteries.on_turn_start(state, actor_id)
	if raging(actor):
		actor["rage_state"]["extended"] = false
	return []

## Rage ends when the Barbarian neither attacked nor extended it this turn, or after 10 rounds.
static func on_turn_end(state: GameState, actor_id: String, _rng: RandomNumberGenerator) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	WeaponMasteries.on_turn_end(state, actor_id)
	if not raging(actor):
		return []
	var rage: Dictionary = actor["rage_state"]
	rage["rounds"] = int(rage.get("rounds", 0)) + 1
	if not bool(rage.get("extended", false)) or int(rage["rounds"]) >= 10 or \
			not CombatRules.conditions_for(actor).can_act():
		return end_rage(actor, actor_id)
	return []

static func end_rage(actor: Dictionary, actor_id: String) -> Array[Dictionary]:
	if not raging(actor):
		return []
	actor.erase("rage_state")
	return [{"type": "feature_end", "actor_id": actor_id, "feature_id": "rage"}]

static func on_combat_end(state: GameState, actor_id: String) -> void:
	var actor: Dictionary = state.actors[actor_id]
	end_rage(actor, actor_id)
	actor.erase("brutal_pending")
	actor.erase("mastery_vex")
	ActiveEffects.remove_where(actor, func(effect: Dictionary) -> bool:
		return String(effect.get("kind", "")) == "reckless_attack")

static func on_rest(actor: Dictionary, _rest: String) -> void:
	actor.erase("rage_state")

# --- Hotbar -------------------------------------------------------------------

static func feature_buttons(actor: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var features: Dictionary = actor.get("features", {})
	for feature_id: String in FEATURES:
		if features.has(feature_id):
			result.append(feature_id)
	return result

static func feature_label(actor: Dictionary, feature_id: String) -> String:
	var rage: Dictionary = actor.get("features", {}).get("rage", {})
	match feature_id:
		"rage":
			if raging(actor):
				return TranslationServer.translate("FEATURE_RAGE_ACTIVE")
			return TranslationServer.translate("FEATURE_RAGE_BUTTON") % [int(rage.get("uses", 0)), int(rage.get("max", 0))]
		"reckless_attack":
			return TranslationServer.translate("FEATURE_RECKLESS_ATTACK_ON" if reckless(actor) else "FEATURE_RECKLESS_ATTACK_BUTTON")
		"brutal_strike":
			return TranslationServer.translate("FEATURE_BRUTAL_STRIKE_ON" if bool(actor.get("brutal_pending", false)) else "FEATURE_BRUTAL_STRIKE_BUTTON")
	return feature_id

static func feature_reason(state: GameState, actor_id: String, feature_id: String) -> String:
	if CombatRules.valid_actor_turn(state, actor_id) != OK:
		return "COMBAT_WAIT_TURN"
	var actor: Dictionary = state.actors[actor_id]
	if not CombatRules.conditions_for(actor).can_act():
		return "SPELL_REASON_INCAPACITATED"
	match feature_id:
		"rage":
			if raging(actor):
				return "FEATURE_RAGE_ALREADY"
			if ClassKits.heavy_armor(actor):
				return "FEATURE_RAGE_HEAVY_ARMOR"
			if not bool(actor.get("bonus_available", false)):
				return "COMBAT_NO_BONUS"
			if int(actor["features"]["rage"].get("uses", 0)) <= 0:
				return "FEATURE_NO_USES"
		"reckless_attack":
			if reckless(actor):
				return "FEATURE_RECKLESS_ATTACK_ALREADY"
			if bool(actor.get("attacked_this_turn", false)):
				return "FEATURE_RECKLESS_ATTACK_FIRST"
		"brutal_strike":
			if not reckless(actor):
				return "FEATURE_BRUTAL_STRIKE_NEEDS_RECKLESS"
			if bool(actor.get("brutal_pending", false)) or bool(actor.get("brutal_used", false)) and \
					int(actor.get("brutal_turn", -1)) == state.round_number:
				return "FEATURE_BRUTAL_STRIKE_ALREADY"
			if not CombatRules.can_use_action(actor) and int(actor.get("attacks_left", 0)) <= 0:
				return "COMBAT_NO_ACTION"
	return ""

static func use_feature(state: GameState, actor_id: String, feature_id: String, _rng: RandomNumberGenerator) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	var events: Array[Dictionary] = [{"type": "feature", "actor_id": actor_id, "feature_id": feature_id}]
	match feature_id:
		"rage":
			actor["bonus_available"] = false
			actor["features"]["rage"]["uses"] = int(actor["features"]["rage"]["uses"]) - 1
			actor["rage_state"] = {"extended": true, "rounds": 0}
			# Raging ends concentration (Barbarians have no spells, but potions or items may come).
			if not actor.get("concentration", {}).is_empty():
				events.append_array(ActiveEffects.end_concentration(state, actor_id, "rage"))
			if actor["features"].has("instinctive_pounce"):
				actor["move_left"] = float(actor.get("move_left", 0.0)) + float(actor.get("speed_m", 9.0)) * 0.5
		"reckless_attack":
			ActiveEffects.add(actor, {"kind": "reckless_attack", "source_id": actor_id, "turn_of": actor_id,
				"until": "start_of_turn"})
		"brutal_strike":
			# Once per turn: the next Strength attack drops Reckless Attack's advantage for +1d10 and Hamstring Blow.
			actor["brutal_pending"] = true
			actor["brutal_used"] = true
			actor["brutal_turn"] = state.round_number
	return events
