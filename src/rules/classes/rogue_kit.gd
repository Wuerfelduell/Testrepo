extends RefCounted
## Rogue (SRD 5.2, levels 1-10, no subclass). The owner's companion Seren Nachtfall is a
## Rogue. Sneak Attack and Uncanny Dodge work automatically (BG3 default); the hotbar has
## Hide, the Cunning Action bonus actions, Steady Aim and the Cunning Strike picker.

const PRIORITY: Array[StringName] = [&"dex", &"con", &"wis", &"int", &"cha", &"str"]
const SKILLS: Dictionary = {"class": [&"stealth", &"perception", &"acrobatics", &"sleight_of_hand"],
	"human": &"investigation"}
const IMPLEMENTED_MAX_LEVEL: int = 10
const DATA_ONLY: Dictionary = {"thieves_cant": "no secret messages in play yet"}
const FEATURES: Array[String] = ["hide", "cunning_dash", "cunning_disengage", "cunning_hide",
	"steady_aim", "cunning_strike"]
## SRD 5.2 Hide: a DC 15 Dexterity (Stealth) check.
const HIDE_DC: int = 15
## Level 1 Expertise when creation does not choose: the first two the Rogue is proficient in.
const EXPERTISE_DEFAULT: Array[String] = ["stealth", "perception", "acrobatics", "sleight_of_hand"]
## Cunning Strike options (level 5); each costs 1d6 of the Sneak Attack dice.
const CUNNING_STRIKES: Array[String] = ["poison", "trip", "withdraw"]
## Weapon Mastery: two kinds of weapons, the starting Dagger (Nick) and Shortbow (Vex).
const MASTERY: Array[String] = ["dagger", "shortbow"]

# --- Record life cycle -------------------------------------------------------

static func activate(record: Dictionary) -> void:
	record["features"]["weapon_mastery"] = {"weapons": MASTERY.duplicate()}
	record["features"]["thieves_cant"] = {}
	if record.get("skill_expertise", []).is_empty():
		record["skill_expertise"] = default_expertise(record)

static func upgrade(record: Dictionary) -> void:
	if not record["features"].has("weapon_mastery"):
		record["features"]["weapon_mastery"] = {"weapons": MASTERY.duplicate()}

static func advance(actor: Dictionary, level: int) -> void:
	var features: Dictionary = actor["features"]
	features["sneak_attack"] = {"dice": sneak_attack_dice(level)}
	if level >= 2:
		features["cunning_action"] = {}
	if level >= 3:
		features["steady_aim"] = {}
	if level >= 5:
		# The chosen strike survives level-ups; "" = plain Sneak Attack.
		features["cunning_strike"] = {"choice": String(features.get("cunning_strike", {}).get("choice", ""))}
		features["uncanny_dodge"] = {}
	if level >= 7:
		features["evasion"] = {}
		features["reliable_talent"] = {}

## Passive Perception counts Expertise (HeroKit builds it from the sheet without).
static func refresh_derived(actor: Dictionary) -> void:
	var proficiency: int = Abilities.proficiency_bonus(int(actor.get("level", 1)))
	var skills: Array = actor.get("skill_proficiencies", []).map(func(skill: Variant) -> String: return String(skill))
	var expertise: Array = actor.get("skill_expertise", []).map(func(skill: Variant) -> String: return String(skill))
	actor["passive_perception"] = 10 + Abilities.modifier(ClassKits.score(actor, "wis")) + \
		(proficiency if "perception" in skills else 0) + (proficiency if "perception" in expertise else 0)

## Level 6 Expertise: two more proficient skills.
static func level_choices(actor: Dictionary, level: int) -> Array:
	if level != 6:
		return []
	var expertise: Array = actor.get("skill_expertise", []).map(func(skill: Variant) -> String: return String(skill))
	var options: Array[String] = []
	for skill: Variant in actor.get("skill_proficiencies", []):
		if not String(skill) in expertise and not String(skill) in options:
			options.append(String(skill))
	return [{"key": "expertise", "count": 2, "options": options, "title_key": "LEVELUP_SECTION_EXPERTISE_ROGUE",
		"option_prefix": "SHEET_SKILL_", "note_key": "LEVELUP_SECTION_EXPERTISE_ROGUE_NOTE"}]

static func apply_level_choices(actor: Dictionary, _level: int, picks: Dictionary) -> void:
	var expertise: Array = actor.get("skill_expertise", []).duplicate()
	for skill: Variant in picks.get("expertise", []):
		if not String(skill) in expertise:
			expertise.append(String(skill))
	actor["skill_expertise"] = expertise

static func default_expertise(actor: Dictionary) -> Array[String]:
	var owned: Array[String] = []
	for skill: Variant in actor.get("skill_proficiencies", []):
		owned.append(String(skill))
	var result: Array[String] = []
	for skill: String in EXPERTISE_DEFAULT + owned:
		if skill in owned and not skill in result and result.size() < 2:
			result.append(skill)
	return result

static func sneak_attack_dice(level: int) -> int:
	return ceili(clampi(level, 1, 20) / 2.0)

# --- Equipment ---------------------------------------------------------------

## SRD 5.2 Rogue weapon training: Simple weapons and Martial weapons with Finesse or Light.
static func adjust_weapon(actor: Dictionary, record: Dictionary, item: Dictionary) -> void:
	var properties: Array = item.get("properties", [])
	if bool(record.get("proficient", false)) or String(item.get("category", "")) != "martial" or \
			not ("finesse" in properties or "light" in properties):
		return
	var proficiency: int = int(actor.get("proficiency_bonus", 2))
	record["proficient"] = true
	record["attack_bonus"] = int(record["attack_bonus"]) + proficiency
	record["attack_modifiers"].append({"amount": proficiency, "source": "proficiency"})

# --- Combat ------------------------------------------------------------------

static func attack_advantages(state: GameState, attacker_id: String, target_id: String, _weapon: Dictionary) -> Array[StringName]:
	return WeaponMasteries.attack_advantages(state, attacker_id, target_id)

static func on_turn_start(state: GameState, actor_id: String) -> Array[Dictionary]:
	WeaponMasteries.on_turn_start(state, actor_id)
	return []

static func on_turn_end(state: GameState, actor_id: String, _rng: RandomNumberGenerator) -> Array[Dictionary]:
	WeaponMasteries.on_turn_end(state, actor_id)
	return []

## SRD 5.2 Sneak Attack: once per turn, a Finesse or Ranged weapon hit with Advantage, or
## without Disadvantage while an ally who can act stands within 1.5 m of the target.
static func extra_damage_dice(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		_critical: bool) -> Array:
	var roll: Dictionary = weapon.get("attack_roll", {})
	var dice: int = _sneak_dice(state, attacker_id, target_id, weapon, bool(roll.get("advantage", false)),
		bool(roll.get("disadvantage", false)))
	if dice <= 0:
		return []
	var attacker: Dictionary = state.actors[attacker_id]
	attacker["sneak_attack_turn"] = ActiveEffects.turn_key(state)
	var strike: String = _strike_choice(attacker, state.actors[target_id])
	if not strike.is_empty():
		# The strike's effect follows once the damage is dealt (after_attack).
		attacker["cunning_strike_pending"] = {"target_id": target_id, "strike": strike}
		dice -= 1
	if dice <= 0:
		return []
	return [{"dice": "%dd6" % dice, "source": "sneak_attack"}]

## Preview: Advantage from hiding, Steady Aim or Vex, else an ally next to the target.
static func expected_extra_damage(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> float:
	var attacker: Dictionary = state.actors.get(attacker_id, {})
	var advantage: bool = not ActiveEffects.attack_advantages(attacker).is_empty() or \
		not WeaponMasteries.attack_advantages(state, attacker_id, target_id).is_empty()
	var dice: int = _sneak_dice(state, attacker_id, target_id, weapon, advantage, false)
	if dice > 0 and not _strike_choice(attacker, state.actors.get(target_id, {})).is_empty():
		dice -= 1
	return dice * 3.5

static func after_attack(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		hit: bool, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = WeaponMasteries.after_attack(state, attacker_id, target_id, weapon, hit, rng)
	var attacker: Dictionary = state.actors[attacker_id]
	var pending: Dictionary = attacker.get("cunning_strike_pending", {})
	attacker.erase("cunning_strike_pending")
	if hit and String(pending.get("target_id", "")) == target_id and CombatRules.alive(state.actors.get(target_id, {})):
		events.append_array(_apply_strike(state, attacker_id, target_id, String(pending["strike"]), rng))
	return events

## Uncanny Dodge (level 5): the Rogue's reaction halves a hit from an attacker it can see.
static func halve_attack_damage(state: GameState, attacker_id: String, target_id: String, _weapon: Dictionary) -> String:
	var target: Dictionary = state.actors.get(target_id, {})
	var attacker: Dictionary = state.actors.get(attacker_id, {})
	if not target.get("features", {}).has("uncanny_dodge") or not bool(target.get("reaction_available", false)):
		return ""
	var conditions: ConditionState = CombatRules.conditions_for(target)
	if not conditions.can_act() or conditions.has(&"blinded") or not CombatRules.alive(target):
		return ""
	if not CombatSpace.current().visible(target["position"], attacker["position"]):
		return ""
	target["reaction_available"] = false
	return "uncanny_dodge"

## Evasion (level 7): Dexterity saves against half-damage effects.
static func evades(actor: Dictionary, ability: StringName) -> bool:
	return actor.get("features", {}).has("evasion") and ability == &"dex" and \
		CombatRules.conditions_for(actor).can_act()

static func _sneak_dice(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		advantage: bool, disadvantage: bool) -> int:
	var attacker: Dictionary = state.actors.get(attacker_id, {})
	var dice: int = int(attacker.get("features", {}).get("sneak_attack", {}).get("dice", 0))
	if dice <= 0 or not weapon.get("spell_id", "") in ["", null]:
		return 0
	if not bool(weapon.get("ranged", false)) and not "finesse" in weapon.get("properties", []):
		return 0
	if String(attacker.get("sneak_attack_turn", "")) == ActiveEffects.turn_key(state):
		return 0
	if advantage:
		return dice
	if disadvantage:
		return 0
	var target: Dictionary = state.actors.get(target_id, {})
	for ally_id: String in state.actors:
		var ally: Dictionary = state.actors[ally_id]
		if ally_id == attacker_id or ally_id == target_id or ally.get("team") != attacker.get("team") or \
				not CombatRules.alive(ally) or not CombatRules.conditions_for(ally).can_act():
			continue
		if (ally["position"] as Vector3).distance_to(target["position"]) <= 1.5 + CombatRules.EPSILON:
			return dice
	return 0

## The picked Cunning Strike, if the target can be affected (Trip: Large or smaller).
static func _strike_choice(attacker: Dictionary, target: Dictionary) -> String:
	var choice: String = String(attacker.get("features", {}).get("cunning_strike", {}).get("choice", ""))
	if not choice in CUNNING_STRIKES:
		return ""
	if choice == "trip" and String(target.get("size", "medium")) in ["huge", "gargantuan"]:
		return ""
	return choice

## SRD 5.2: Cunning Strike save DC = 8 + Dexterity modifier + Proficiency Bonus.
static func strike_dc(attacker: Dictionary) -> int:
	return 8 + Abilities.modifier(ClassKits.score(attacker, "dex")) + int(attacker.get("proficiency_bonus", 2))

static func _apply_strike(state: GameState, attacker_id: String, target_id: String, strike: String,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = [{"type": "feature", "actor_id": attacker_id, "target_id": target_id,
		"feature_id": "cunning_strike", "strike": strike}]
	var attacker: Dictionary = state.actors[attacker_id]
	var target: Dictionary = state.actors[target_id]
	var dc: int = strike_dc(attacker)
	match strike:
		"poison":
			# Poisoned for 1 minute; the target repeats the save at the end of each of its turns.
			var save: Dictionary = SpellRules.roll_save(target, &"con", dc, rng)
			events.append(ActiveEffects.save_event(attacker_id, target_id, "cunning_strike_poison", save))
			if not bool(save["success"]) and not ActiveEffects.has_kind(target, ActiveEffects.CUNNING_POISON):
				ActiveEffects.add(target, {"kind": ActiveEffects.CUNNING_POISON, "condition": "poisoned", "source_id": attacker_id, "save_dc": dc})
				events.append({"type": "condition", "actor_id": target_id, "condition": "poisoned", "source_id": attacker_id})
		"trip":
			# Prone like Topple: until the target's next turn starts, which then has half Speed.
			var save: Dictionary = SpellRules.roll_save(target, &"dex", dc, rng)
			events.append(ActiveEffects.save_event(attacker_id, target_id, "cunning_strike_trip", save))
			if not bool(save["success"]) and not CombatRules.conditions_for(target).has(&"prone"):
				ActiveEffects.add(target, {"kind": "cunning_trip", "condition": "prone", "source_id": attacker_id,
					"turn_of": target_id, "until": "start_of_turn"})
				ActiveEffects.add(target, {"kind": "speed_penalty", "amount": float(target.get("speed_m", 9.0)) * 0.5,
					"source_id": attacker_id, "turn_of": attacker_id, "until": "start_of_turn"})
				events.append({"type": "condition", "actor_id": target_id, "condition": "prone", "source_id": attacker_id})
		"withdraw":
			# Up to half Speed right away without opportunity attacks.
			attacker["move_left"] = float(attacker.get("move_left", 0.0)) + float(attacker.get("speed_m", 9.0)) * 0.5
			attacker["disengaged"] = true
	return events

# --- Hotbar ------------------------------------------------------------------

## Hide (action) until Cunning Action turns it into bonus actions; then Steady Aim and the
## Cunning Strike picker, in the order the Rogue gains them.
static func feature_buttons(actor: Dictionary) -> Array[String]:
	var features: Dictionary = actor.get("features", {})
	var result: Array[String] = []
	if features.has("cunning_action"):
		result.append_array(["cunning_dash", "cunning_disengage", "cunning_hide"])
	else:
		result.append("hide")
	if features.has("steady_aim"):
		result.append("steady_aim")
	if features.has("cunning_strike"):
		result.append("cunning_strike")
	return result

static func feature_reason(state: GameState, actor_id: String, feature_id: String) -> String:
	var actor: Dictionary = state.actors[actor_id]
	var unavailable: String = "FEATURE_%s_UNAVAILABLE" % feature_id.to_upper()
	if feature_id == "cunning_strike":
		return "" if state.mode != &"defeat" else unavailable
	if CombatRules.valid_actor_turn(state, actor_id) != OK:
		return "COMBAT_WAIT_TURN"
	if not CombatRules.conditions_for(actor).can_act():
		return unavailable
	if not bool(actor.get("action_available" if feature_id == "hide" else "bonus_available", false)):
		return unavailable
	if feature_id in ["hide", "cunning_hide"] and (ActiveEffects.has_kind(actor, ActiveEffects.HIDDEN) or \
			not CombatRules.hidden_from_enemies(state, actor_id)):
		return unavailable
	if feature_id == "steady_aim" and bool(actor.get("moved_this_turn", false)):
		return unavailable
	return ""

static func use_feature(state: GameState, actor_id: String, feature_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	var events: Array[Dictionary] = []
	match feature_id:
		"hide", "cunning_hide":
			actor["action_available" if feature_id == "hide" else "bonus_available"] = false
			events.append_array(hide(actor, actor_id, rng))
		"cunning_dash":
			actor["bonus_available"] = false
			if not CombatRules.conditions_for(actor).speed_is_zero():
				actor["move_left"] = float(actor["move_left"]) + float(actor["speed_m"])
			events.append({"type": "dash", "actor_id": actor_id, "feature_id": feature_id})
		"cunning_disengage":
			actor["bonus_available"] = false
			actor["disengaged"] = true
			events.append({"type": "disengage", "actor_id": actor_id, "feature_id": feature_id})
		"steady_aim":
			actor["bonus_available"] = false
			actor["move_left"] = 0.0
			ActiveEffects.add(actor, {"kind": ActiveEffects.STEADY_AIM, "source_id": actor_id,
				"turn_of": actor_id, "until": "end_of_turn"})
			events.append({"type": "feature", "actor_id": actor_id, "feature_id": feature_id})
		"cunning_strike":
			var feature: Dictionary = actor["features"]["cunning_strike"]
			var options: Array[String] = [""]
			options.append_array(CUNNING_STRIKES)
			feature["choice"] = options[(options.find(String(feature.get("choice", ""))) + 1) % options.size()]
			events.append({"type": "feature", "actor_id": actor_id, "feature_id": feature_id, "strike": feature["choice"]})
	return events

static func feature_label(actor: Dictionary, feature_id: String) -> String:
	var label: String = TranslationServer.translate("FEATURE_%s_BUTTON" % feature_id.to_upper())
	if feature_id == "cunning_strike":
		var choice: String = String(actor.get("features", {}).get("cunning_strike", {}).get("choice", ""))
		label = label % TranslationServer.translate("CUNNING_STRIKE_" + (choice.to_upper() if not choice.is_empty() else "NONE"))
	return label

## SRD 5.2 Hide: DC 15 Dexterity (Stealth). On a success the Rogue is hidden (Invisible):
## Advantage on its attacks, Disadvantage on attacks against it, until it attacks, casts a
## spell or an enemy sees it in the open.
static func hide(actor: Dictionary, actor_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: CheckResult = ClassFeatures.skill_check(actor, "stealth", HIDE_DC, rng)
	var event: Dictionary = {"type": "roll", "kind": "check", "actor_id": actor_id, "skill": "stealth",
		"dc": HIDE_DC, "success": result.success}
	if result.roll != null:
		event["roll"] = CombatRules.serialize_roll(result.roll)
	var events: Array[Dictionary] = [event]
	if result.success:
		ActiveEffects.add(actor, {"kind": ActiveEffects.HIDDEN, "source_id": actor_id, "dc": result.roll.total})
		events.append({"type": "hidden", "actor_id": actor_id})
	else:
		events.append({"type": "hide_failed", "actor_id": actor_id})
	return events
