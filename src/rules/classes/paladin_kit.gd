extends RefCounted
## Paladin (SRD 5.2, levels 1-10, no subclass). Spells: ClassSpellcasting["paladin"]
## (half caster); Lay on Hands and Abjure Foes are feature spells (ClassEffects), the
## Auras live in ClassEffects.save_modifiers / fear_immune.
## Divine Smite is a toggle: armed, the next melee weapon hit on the Paladin's turn spends
## the bonus action and the free use (Paladin's Smite) or the lowest spell slot.
## Follows BG3: Fighting Style is picked at level 2 (Defense, Dueling, Great Weapon
## Fighting); no Weapon Mastery.

const PRIORITY: Array[StringName] = [&"str", &"cha", &"con", &"wis", &"dex", &"int"]
const SKILLS: Dictionary = {"class": [&"athletics", &"persuasion"], "human": &"perception"}
const DATA_ONLY: Dictionary = {
	"faithful_steed": "no summoned creatures in play yet",
}
const FEATURES: Array[String] = ["divine_smite"]
const SMITE_TYPES: Array[StringName] = [&"fiend", &"undead"]
const FIGHTING_STYLES: Array[String] = ["defense", "dueling", "great_weapon_fighting"]
const DUELING_BONUS: int = 2

static func advance(actor: Dictionary, level: int) -> void:
	var features: Dictionary = actor["features"]
	# The pool is "uses": hit points left to give (5 x Paladin level).
	ClassKits.set_uses(features, "lay_on_hands", 5 * level, "long")
	if level >= 2:
		ClassKits.set_uses(features, "divine_smite", 1, "long")
		features["divine_smite"]["armed"] = bool(features["divine_smite"].get("armed", false))
	if level >= 3:
		ClassKits.set_uses(features, "channel_divinity", 2, "long", 1)
	if level >= 5:
		features["extra_attack"] = {"attacks": 2}
	if level >= 6:
		features["aura_of_protection"] = {}
	if level >= 10:
		features["aura_of_courage"] = {}

static func level_choices(actor: Dictionary, level: int) -> Array:
	if level == 2 and String(actor.get("features", {}).get("fighting_style", "")).is_empty():
		return [{"key": "fighting_style", "count": 1, "title_key": "LEVELUP_SECTION_RANGER_STYLE",
			"options": FIGHTING_STYLES.duplicate(), "option_prefix": "FEAT_"}]
	return []

static func apply_level_choices(actor: Dictionary, _level: int, picks: Dictionary) -> void:
	for style: Variant in picks.get("fighting_style", []):
		actor["features"]["fighting_style"] = String(style)

## Fighting Style Dueling: +2 damage with a melee weapon held in one hand.
static func damage_bonus(state: GameState, attacker_id: String, _target_id: String, weapon: Dictionary) -> Array:
	var attacker: Dictionary = state.actors[attacker_id]
	if String(attacker.get("features", {}).get("fighting_style", "")) != "dueling":
		return []
	if bool(weapon.get("ranged", false)) or not weapon.get("spell_id", "") in ["", null] or \
			bool(weapon.get("two_handed_grip", false)) or "two_handed" in weapon.get("properties", []):
		return []
	return [{"amount": DUELING_BONUS, "source": "dueling"}]

## Fighting Style Defense: +1 AC while wearing armour.
static func ac_bonus(actor: Dictionary, armor_id: StringName) -> Array:
	if String(actor.get("features", {}).get("fighting_style", "")) == "defense" and armor_id != &"none":
		return [{"amount": 1, "source": "defense"}]
	return []

# --- Divine Smite --------------------------------------------------------------

## Slot level the next smite would use: 1 for the free use, else the lowest slot; 0 = none.
static func _smite_slot(state: GameState, attacker_id: String, weapon: Dictionary) -> int:
	var attacker: Dictionary = state.actors.get(attacker_id, {})
	var smite: Dictionary = attacker.get("features", {}).get("divine_smite", {})
	if not bool(smite.get("armed", false)) or bool(weapon.get("ranged", false)) or \
			not String(weapon.get("spell_id", "")).is_empty() or not bool(attacker.get("bonus_available", false)) or \
			state.current_actor_id() != attacker_id:
		return 0
	if int(smite.get("uses", 0)) > 0:
		return 1
	return SpellRules.lowest_slot(attacker.get("spell_slots", []), 1)

static func _smite_dice(state: GameState, target_id: String, slot_level: int) -> int:
	var target: Dictionary = state.actors.get(target_id, {})
	var bonus: int = 1 if StringName(String(target.get("creature_type", "humanoid"))) in SMITE_TYPES else 0
	return 2 + (slot_level - 1) + bonus

static func extra_damage_dice(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		critical: bool) -> Array:
	var slot_level: int = _smite_slot(state, attacker_id, weapon)
	if slot_level <= 0:
		return []
	var attacker: Dictionary = state.actors[attacker_id]
	var smite: Dictionary = attacker["features"]["divine_smite"]
	if int(smite.get("uses", 0)) > 0:
		smite["uses"] = int(smite["uses"]) - 1
	else:
		SpellRules.spend_slot(attacker["spell_slots"], slot_level)
	smite["armed"] = false
	attacker["bonus_available"] = false
	return [{"dice": "%dd8" % _smite_dice(state, target_id, slot_level), "damage_type": "radiant", "source": "divine_smite"}]

static func expected_extra_damage(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> float:
	var slot_level: int = _smite_slot(state, attacker_id, weapon)
	return 4.5 * _smite_dice(state, target_id, slot_level) if slot_level > 0 else 0.0

static func feature_buttons(actor: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if actor.get("features", {}).has("divine_smite"):
		result.append("divine_smite")
	return result

static func feature_reason(state: GameState, actor_id: String, feature_id: String) -> String:
	if CombatRules.valid_actor_turn(state, actor_id) != OK:
		return "INV_REASON_NOT_YOUR_TURN"
	var actor: Dictionary = state.actors[actor_id]
	var smite: Dictionary = actor["features"].get(feature_id, {})
	if bool(smite.get("armed", false)):
		return ""
	if int(smite.get("uses", 0)) <= 0 and SpellRules.lowest_slot(actor.get("spell_slots", []), 1) <= 0:
		return "SPELL_REASON_NO_SLOT"
	return ""

static func use_feature(state: GameState, actor_id: String, feature_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var smite: Dictionary = state.actors[actor_id]["features"][feature_id]
	smite["armed"] = not bool(smite.get("armed", false))
	return [{"type": "feature_toggle", "actor_id": actor_id, "feature_id": feature_id, "armed": smite["armed"]}]

static func feature_label(actor: Dictionary, feature_id: String) -> String:
	var smite: Dictionary = actor.get("features", {}).get(feature_id, {})
	return TranslationServer.translate("FEATURE_DIVINE_SMITE_ARMED" if bool(smite.get("armed", false)) else "FEATURE_DIVINE_SMITE_BUTTON")

static func on_combat_end(state: GameState, actor_id: String) -> void:
	var smite: Dictionary = state.actors[actor_id].get("features", {}).get("divine_smite", {})
	smite["armed"] = false
