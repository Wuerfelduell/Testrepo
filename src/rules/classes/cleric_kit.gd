extends RefCounted
## Cleric (SRD 5.2, levels 1-10, no subclass). Spells: ClassSpellcasting["cleric"];
## spell effects (Bless, Spirit Guardians, Turn Undead ...): ClassEffects.
## Channel Divinity is paid by Divine Spark and Turn Undead (feature spells).
## Defaults until the owner decides: Divine Order Protector (heavy armour, martial
## weapons), Blessed Strikes Divine Strike.

const PRIORITY: Array[StringName] = [&"wis", &"con", &"str", &"dex", &"cha", &"int"]
const SKILLS: Dictionary = {"class": [&"insight", &"medicine"], "human": &"perception"}
const DATA_ONLY: Dictionary = {}
const FEATURES: Array[String] = ["divine_intervention"]

static func _turn_key(state: GameState) -> String:
	return "%d:%d" % [state.round_number, state.turn_index]

static func activate(record: Dictionary) -> void:
	var features: Dictionary = record["features"]
	features["divine_order"] = "protector"
	features["extra_training"] = {"armor": ["heavy"], "weapons": ["martial"]}

static func advance(actor: Dictionary, level: int) -> void:
	var features: Dictionary = actor["features"]
	if level >= 2:
		# One use back on a Short Rest, all on a Long Rest.
		ClassKits.set_uses(features, "channel_divinity", 3 if level >= 6 else 2, "long", 1)
	if level >= 5:
		features["sear_undead"] = {}
	if level >= 7 and not features.has("blessed_strikes"):
		features["blessed_strikes"] = "divine_strike"
	if level >= 10:
		ClassKits.set_uses(features, "divine_intervention", 1, "long")
		features["divine_intervention"]["armed"] = bool(features["divine_intervention"].get("armed", false))

# --- Divine Strike: 1d8 radiant once on each of the Cleric's turns ------------

static func _strike_ready(state: GameState, attacker_id: String, weapon: Dictionary) -> bool:
	var attacker: Dictionary = state.actors.get(attacker_id, {})
	return String(attacker.get("features", {}).get("blessed_strikes", "")) == "divine_strike" and \
		String(weapon.get("spell_id", "")).is_empty() and state.current_actor_id() == attacker_id and \
		String(attacker.get("divine_strike_turn", "")) != _turn_key(state)

static func extra_damage_dice(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		critical: bool) -> Array:
	if not _strike_ready(state, attacker_id, weapon):
		return []
	state.actors[attacker_id]["divine_strike_turn"] = _turn_key(state)
	return [{"dice": "1d8", "damage_type": "radiant", "source": "divine_strike"}]

static func expected_extra_damage(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> float:
	return 4.5 if _strike_ready(state, attacker_id, weapon) else 0.0

# --- Divine Intervention: the next Cleric spell of level 1-5 needs no slot ----

static func feature_buttons(actor: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if actor.get("features", {}).has("divine_intervention"):
		result.append("divine_intervention")
	return result

static func feature_reason(state: GameState, actor_id: String, feature_id: String) -> String:
	if CombatRules.valid_actor_turn(state, actor_id) != OK:
		return "INV_REASON_NOT_YOUR_TURN"
	var feature: Dictionary = state.actors[actor_id]["features"].get(feature_id, {})
	if int(feature.get("uses", 0)) <= 0 and not bool(feature.get("armed", false)):
		return "FEATURE_NO_USES"
	return ""

## A toggle: SpellResolver.free_cast spends the use when the spell is cast.
static func use_feature(state: GameState, actor_id: String, feature_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var feature: Dictionary = state.actors[actor_id]["features"][feature_id]
	feature["armed"] = not bool(feature.get("armed", false))
	return [{"type": "feature_toggle", "actor_id": actor_id, "feature_id": feature_id, "armed": feature["armed"]}]

static func feature_label(actor: Dictionary, feature_id: String) -> String:
	var feature: Dictionary = actor.get("features", {}).get(feature_id, {})
	if bool(feature.get("armed", false)):
		return TranslationServer.translate("FEATURE_DIVINE_INTERVENTION_ARMED")
	return TranslationServer.translate("FEATURE_DIVINE_INTERVENTION_BUTTON") % [int(feature.get("uses", 0)), int(feature.get("max", 0))]

static func on_combat_end(state: GameState, actor_id: String) -> void:
	var feature: Dictionary = state.actors[actor_id].get("features", {}).get("divine_intervention", {})
	feature["armed"] = false
	state.actors[actor_id].erase("divine_strike_turn")
