extends RefCounted
## SRD 5.2 Warlock, levels 1-10, no subclass (ClassKits interface, see README.md).
## Pact Magic is the "warlock" entry of ClassSpellcasting ("pact" slots: all of one level);
## every pact slot comes back on a Short Rest. Eldritch Invocations are picked at
## level-up; the ones with rules behind them work through the kit hooks below, the
## others are listed with "(no effect in play yet)" in their hint.

const PRIORITY: Array[StringName] = [&"cha", &"con", &"dex", &"wis", &"int", &"str"]
const SKILLS: Dictionary = {"class": [&"arcana", &"intimidation"], "human": &"perception"}
const DATA_ONLY: Dictionary = {
	"contact_patron": "no patrons to contact yet",
}
## Invocations known per warlock level (SRD 5.2 table, index 0 = level 1).
const INVOCATIONS_KNOWN: Array[int] = [1, 3, 3, 3, 5, 5, 6, 6, 7, 7]
## Invocation -> lowest warlock level, and the invocation it needs first.
const INVOCATIONS: Dictionary = {
	"armor_of_shadows": {"level": 1},
	"eldritch_mind": {"level": 1},
	"pact_of_the_blade": {"level": 1},
	"beguiling_influence": {"level": 1},
	"agonizing_blast": {"level": 2},
	"devils_sight": {"level": 2},
	"mask_of_many_faces": {"level": 2},
	"misty_visions": {"level": 2},
	"otherworldly_leap": {"level": 2},
	"eyes_of_the_rune_keeper": {"level": 2},
	"thirsting_blade": {"level": 5, "requires": "pact_of_the_blade"},
	"one_with_shadows": {"level": 5},
	"ascendant_step": {"level": 5},
	"gift_of_the_depths": {"level": 5},
}
## Invocations without rules in play yet (darkness, disguises, climbing, water ...).
const INVOCATIONS_DATA_ONLY: Array[String] = ["devils_sight", "mask_of_many_faces", "misty_visions",
	"otherworldly_leap", "eyes_of_the_rune_keeper", "one_with_shadows", "ascendant_step", "gift_of_the_depths"]
## A level-1 warlock from character creation starts with this one (no pick screen there).
const DEFAULT_INVOCATION: String = "eldritch_mind"
const FEATURES: Array[String] = ["magical_cunning"]

static func invocations(actor: Dictionary) -> Array:
	return actor.get("features", {}).get("eldritch_invocations", {}).get("known", [])

static func has_invocation(actor: Dictionary, invocation: String) -> bool:
	return invocation in invocations(actor)

static func activate(record: Dictionary) -> void:
	record["features"]["eldritch_invocations"] = {"known": [DEFAULT_INVOCATION]}

static func upgrade(_record: Dictionary) -> void:
	pass

static func advance(actor: Dictionary, level: int) -> void:
	var features: Dictionary = actor["features"]
	if not features.has("eldritch_invocations"):
		features["eldritch_invocations"] = {"known": [DEFAULT_INVOCATION]}
	if level >= 2:
		ClassKits.set_uses(features, "magical_cunning", 1, "long")
	_apply_invocations(actor)

static func refresh_derived(actor: Dictionary) -> void:
	actor["spell_modifier"] = Abilities.modifier(ClassKits.score(actor, "cha"))
	_apply_invocations(actor)

## Standing effects of the known invocations on the record.
static func _apply_invocations(actor: Dictionary) -> void:
	var features: Dictionary = actor["features"]
	if has_invocation(actor, "beguiling_influence"):
		var skills: Array = actor.get("skill_proficiencies", []).duplicate()
		for skill: StringName in [&"deception", &"persuasion"]:
			if not skill in skills and not String(skill) in skills:
				skills.append(skill)
		actor["skill_proficiencies"] = skills
	if has_invocation(actor, "thirsting_blade") and has_invocation(actor, "pact_of_the_blade"):
		features["extra_attack"] = {"attacks": 2}

# --- Level-up ----------------------------------------------------------------

static func level_choices(actor: Dictionary, level: int) -> Array:
	var known: Array = invocations(actor)
	var count: int = INVOCATIONS_KNOWN[clampi(level, 1, 10) - 1] - known.size()
	if count <= 0:
		return []
	var options: Array[String] = []
	for invocation: String in INVOCATIONS:
		var entry: Dictionary = INVOCATIONS[invocation]
		if invocation in known or level < int(entry["level"]):
			continue
		# Thirsting Blade may be picked together with Pact of the Blade (validated on apply).
		options.append(invocation)
	return [{"key": "invocations", "count": count, "options": options, "title_key": "LEVELUP_SECTION_INVOCATIONS",
		"option_prefix": "INVOCATION_", "note_key": "LEVELUP_SECTION_INVOCATIONS_NOTE"}]

static func apply_level_choices(actor: Dictionary, level: int, picks: Dictionary) -> void:
	if not picks.has("invocations"):
		return
	var invocations_feature: Dictionary = actor["features"].get("eldritch_invocations", {"known": []})
	var known: Array = invocations_feature.get("known", []).duplicate()
	for value: Variant in picks["invocations"]:
		known.append(String(value))
	# Thirsting Blade without Pact of the Blade has no effect; it stays listed.
	invocations_feature["known"] = known
	actor["features"]["eldritch_invocations"] = invocations_feature
	advance(actor, level)

# --- Equipment ---------------------------------------------------------------

## Armor of Shadows: Mage Armor at will, 13 + Dex without armour.
static func unarmored_ac(actor: Dictionary, _shield: bool) -> int:
	if not has_invocation(actor, "armor_of_shadows"):
		return 0
	return 13 + Abilities.modifier(ClassKits.score(actor, "dex"))

## Pact of the Blade: a melee pact weapon attacks with Charisma, always proficient.
static func adjust_weapon(actor: Dictionary, record: Dictionary, _item: Dictionary) -> void:
	if not has_invocation(actor, "pact_of_the_blade") or bool(record.get("ranged", false)):
		return
	var charisma: int = Abilities.modifier(ClassKits.score(actor, "cha"))
	var used: int = int(record.get("damage_bonus", 0))
	if charisma <= used and bool(record.get("proficient", false)):
		return
	var proficiency: int = int(actor.get("proficiency_bonus", 2))
	record["attack_modifiers"] = [{"amount": charisma, "source": "cha"}, {"amount": proficiency, "source": "proficiency"}]
	record["damage_modifiers"] = [{"amount": charisma, "source": "cha"}]
	record["attack_bonus"] = charisma + proficiency
	record["damage_bonus"] = charisma
	record["proficient"] = true
	record["pact_weapon"] = true

# --- Combat hooks ------------------------------------------------------------

## Agonizing Blast: Charisma modifier on every Eldritch Blast beam.
static func damage_bonus(state: GameState, attacker_id: String, _target_id: String, weapon: Dictionary) -> Array:
	var actor: Dictionary = state.actors.get(attacker_id, {})
	if String(weapon.get("spell_id", "")) == "eldritch_blast" and has_invocation(actor, "agonizing_blast"):
		return [{"amount": Abilities.modifier(ClassKits.score(actor, "cha")), "source": "agonizing_blast"}]
	return []

static func _hexed(state: GameState, attacker_id: String, target_id: String) -> bool:
	for effect: Dictionary in ActiveEffects.effects(state.actors.get(target_id, {})):
		if String(effect.get("kind", "")) == "hex" and String(effect.get("source_id", "")) == attacker_id:
			return true
	return false

## Hex: 1d6 necrotic on every hit against the hexed creature.
static func extra_damage_dice(state: GameState, attacker_id: String, target_id: String, _weapon: Dictionary,
		_critical: bool) -> Array:
	if _hexed(state, attacker_id, target_id):
		return [{"dice": "1d6", "damage_type": "necrotic", "source": "hex"}]
	return []

static func expected_extra_damage(state: GameState, attacker_id: String, target_id: String, _weapon: Dictionary) -> float:
	return 3.5 if _hexed(state, attacker_id, target_id) else 0.0

## Eldritch Mind: advantage on Constitution saves to keep concentration.
static func save_advantages(actor: Dictionary, ability: StringName) -> Array[StringName]:
	if ability == &"con" and has_invocation(actor, "eldritch_mind") and not actor.get("concentration", {}).is_empty():
		return [&"eldritch_mind"]
	return []

# --- Hotbar: Magical Cunning -------------------------------------------------

static func feature_buttons(actor: Dictionary) -> Array[String]:
	return ["magical_cunning"] if actor.get("features", {}).has("magical_cunning") else []

## Half the pact slots (rounded up), as many as are spent.
static func cunning_slots(actor: Dictionary) -> int:
	var slots: Array = actor.get("spell_slots", [])
	var maximum: Array = actor.get("spell_slots_max", [])
	if maximum.is_empty():
		return 0
	var pact: int = maximum.size() - 1
	return mini(ceili(int(maximum[pact]) / 2.0), int(maximum[pact]) - int(slots[pact]))

## Magical Cunning (level 2): the 1-minute rite is an action here, so it also works in combat.
static func feature_reason(state: GameState, actor_id: String, _feature_id: String) -> String:
	var actor: Dictionary = state.actors[actor_id]
	if CombatRules.valid_actor_turn(state, actor_id) != OK:
		return "COMBAT_WAIT_TURN"
	if not bool(actor.get("action_available", false)) or not CombatRules.conditions_for(actor).can_act():
		return "COMBAT_NO_ACTION"
	if int(actor["features"]["magical_cunning"].get("uses", 0)) <= 0:
		return "FEATURE_NO_USES"
	if cunning_slots(actor) <= 0:
		return "FEATURE_SLOTS_FULL"
	return ""

static func use_feature(state: GameState, actor_id: String, feature_id: String, _rng: RandomNumberGenerator) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	var regained: int = cunning_slots(actor)
	var pact: int = actor["spell_slots_max"].size() - 1
	actor["spell_slots"][pact] = int(actor["spell_slots"][pact]) + regained
	actor["action_available"] = false
	actor["features"]["magical_cunning"]["uses"] = int(actor["features"]["magical_cunning"]["uses"]) - 1
	return [{"type": "feature", "actor_id": actor_id, "feature_id": feature_id, "slots": regained}]

# --- Rests -------------------------------------------------------------------

## Pact Magic: every pact slot comes back on a Short Rest (and a Long Rest).
static func on_rest(actor: Dictionary, _rest: String) -> void:
	if actor.has("spell_slots_max"):
		actor["spell_slots"] = actor["spell_slots_max"].duplicate()
