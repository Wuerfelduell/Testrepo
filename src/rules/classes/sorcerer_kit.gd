extends RefCounted
## SRD 5.2 Sorcerer, levels 1-10, no subclass (ClassKits interface, see README.md).
## Spellcasting (Charisma, full caster) is the "sorcerer" entry of ClassSpellcasting.
## Innate Sorcery (bonus action, 1 minute): spell save DC +1 and advantage on spell
## attack rolls. Font of Magic: Sorcery Points (= level, Long Rest) turn into spell slots
## and back. Metamagic is armed from the hotbar before casting: the points are spent at
## once, the next spell this turn uses it, an unused one is refunded at the end of the turn.

const PRIORITY: Array[StringName] = [&"cha", &"con", &"dex", &"wis", &"int", &"str"]
const SKILLS: Dictionary = {"class": [&"arcana", &"persuasion"], "human": &"perception"}
const DATA_ONLY: Dictionary = {}
## Metamagic options with rules behind them (SpellResolver reads actor["metamagic"]) and
## their Sorcery Point cost.
const METAMAGIC: Dictionary = {"quickened": 2, "distant": 1, "careful": 1, "heightened": 2}
## Font of Magic: Sorcery Points needed to create a slot of each level (SRD 5.2 table).
const SLOT_COST: Dictionary = {1: 2, 2: 3, 3: 5, 4: 6, 5: 7}
const INNATE_ROUNDS: int = 10
const INNATE_USES: int = 2
const FEATURES: Array[String] = ["innate_sorcery", "font_create_slot", "font_gain_points",
	"metamagic_quickened", "metamagic_distant", "metamagic_careful", "metamagic_heightened"]

static func activate(record: Dictionary) -> void:
	record["features"]["innate_sorcery"] = {"uses": INNATE_USES, "max": INNATE_USES, "recharge": "long"}

static func upgrade(_record: Dictionary) -> void:
	pass

static func advance(actor: Dictionary, level: int) -> void:
	var features: Dictionary = actor["features"]
	if not features.has("innate_sorcery"):
		features["innate_sorcery"] = {"uses": INNATE_USES, "max": INNATE_USES, "recharge": "long"}
	if level >= 2:
		ClassKits.set_uses(features, "sorcery_points", level, "long")
		if not features.has("metamagic"):
			features["metamagic"] = {"known": []}
	if level >= 5 and not features.has("sorcerous_restoration"):
		features["sorcerous_restoration"] = {"used": false}
	if level >= 7:
		features["sorcery_incarnate"] = {}

static func refresh_derived(actor: Dictionary) -> void:
	actor["spell_modifier"] = Abilities.modifier(ClassKits.score(actor, "cha"))
	# ClassSpellcasting.refresh just set the plain DC; Innate Sorcery adds its +1 again.
	if innate_active(actor):
		actor["spell_save_dc"] = int(actor.get("spell_save_dc", 10)) + 1

static func innate_active(actor: Dictionary) -> bool:
	return ActiveEffects.has_kind(actor, "innate_sorcery")

static func known_metamagic(actor: Dictionary) -> Array:
	return actor.get("features", {}).get("metamagic", {}).get("known", [])

static func points(actor: Dictionary) -> int:
	return int(actor.get("features", {}).get("sorcery_points", {}).get("uses", 0))

static func _spend_points(actor: Dictionary, amount: int) -> void:
	var feature: Dictionary = actor["features"]["sorcery_points"]
	feature["uses"] = int(feature["uses"]) - amount

# --- Level-up ----------------------------------------------------------------

## Metamagic: two options at level 2, two more at level 10.
static func level_choices(actor: Dictionary, level: int) -> Array:
	if level != 2 and level != 10:
		return []
	var options: Array[String] = []
	for option: String in METAMAGIC:
		if not option in known_metamagic(actor):
			options.append(option)
	return [{"key": "metamagic", "count": 2, "options": options, "title_key": "LEVELUP_SECTION_METAMAGIC",
		"option_prefix": "METAMAGIC_", "note_key": "LEVELUP_SECTION_METAMAGIC_NOTE"}]

static func apply_level_choices(actor: Dictionary, _level: int, picks: Dictionary) -> void:
	if not picks.has("metamagic"):
		return
	var metamagic: Dictionary = actor["features"].get("metamagic", {"known": []})
	var known: Array = metamagic.get("known", []).duplicate()
	for option: Variant in picks["metamagic"]:
		known.append(String(option))
	metamagic["known"] = known
	actor["features"]["metamagic"] = metamagic

# --- Hotbar features ---------------------------------------------------------

static func feature_buttons(actor: Dictionary) -> Array[String]:
	var result: Array[String] = ["innate_sorcery"]
	var features: Dictionary = actor.get("features", {})
	if features.has("sorcery_points"):
		result.append_array(["font_create_slot", "font_gain_points"])
	for option: Variant in known_metamagic(actor):
		result.append("metamagic_" + String(option))
	return result

## Font of Magic: the highest spent slot level (up to 5th) the points can pay for.
static func slot_to_create(actor: Dictionary) -> int:
	var slots: Array = actor.get("spell_slots", [])
	var maximum: Array = actor.get("spell_slots_max", [])
	for index: int in range(mini(5, maximum.size()) - 1, -1, -1):
		var level: int = index + 1
		if int(slots[index]) < int(maximum[index]) and points(actor) >= int(SLOT_COST[level]):
			return level
	return 0

static func feature_reason(state: GameState, actor_id: String, feature_id: String) -> String:
	var actor: Dictionary = state.actors[actor_id]
	var reason: Error = CombatRules.valid_actor_turn(state, actor_id)
	if reason != OK:
		return "COMBAT_WAIT_TURN"
	if not CombatRules.conditions_for(actor).can_act():
		return "SPELL_REASON_INCAPACITATED"
	match feature_id:
		"innate_sorcery":
			if innate_active(actor):
				return "FEATURE_ALREADY_ACTIVE"
			if not bool(actor.get("bonus_available", false)):
				return "COMBAT_NO_BONUS"
			var uses: int = int(actor["features"]["innate_sorcery"].get("uses", 0))
			# Sorcery Incarnate (level 7): 2 Sorcery Points when no use is left.
			if uses <= 0 and not (actor["features"].has("sorcery_incarnate") and points(actor) >= 2):
				return "FEATURE_NO_USES"
		"font_create_slot":
			if not bool(actor.get("bonus_available", false)):
				return "COMBAT_NO_BONUS"
			if slot_to_create(actor) == 0:
				return "FEATURE_FONT_NO_SLOT"
		"font_gain_points":
			var feature: Dictionary = actor["features"].get("sorcery_points", {})
			if int(feature.get("uses", 0)) >= int(feature.get("max", 0)):
				return "FEATURE_FONT_POINTS_FULL"
			if SpellRules.lowest_slot(actor.get("spell_slots", []), 1) == 0:
				return "SPELL_REASON_NO_SLOT"
		_:
			var option: String = feature_id.trim_prefix("metamagic_")
			if not option in known_metamagic(actor):
				return "FEATURE_NO_USES"
			if not String(actor.get("metamagic", "")).is_empty():
				return "FEATURE_METAMAGIC_ARMED"
			if points(actor) < int(METAMAGIC[option]):
				return "FEATURE_NO_POINTS"
	return ""

static func use_feature(state: GameState, actor_id: String, feature_id: String, _rng: RandomNumberGenerator) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	var features: Dictionary = actor["features"]
	match feature_id:
		"innate_sorcery":
			actor["bonus_available"] = false
			var innate: Dictionary = features["innate_sorcery"]
			if int(innate.get("uses", 0)) > 0:
				innate["uses"] = int(innate["uses"]) - 1
			else:
				_spend_points(actor, 2)
			ActiveEffects.add(actor, {"kind": "innate_sorcery", "source_id": actor_id, "until": "rounds",
				"rounds_left": INNATE_ROUNDS})
			actor["spell_save_dc"] = int(actor.get("spell_save_dc", 10)) + 1
		"font_create_slot":
			actor["bonus_available"] = false
			var level: int = slot_to_create(actor)
			_spend_points(actor, int(SLOT_COST[level]))
			actor["spell_slots"][level - 1] = int(actor["spell_slots"][level - 1]) + 1
			return [{"type": "feature", "actor_id": actor_id, "feature_id": feature_id, "slot_level": level}]
		"font_gain_points":
			var slot: int = SpellRules.lowest_slot(actor["spell_slots"], 1)
			SpellRules.spend_slot(actor["spell_slots"], slot)
			var feature: Dictionary = features["sorcery_points"]
			feature["uses"] = mini(int(feature["max"]), int(feature["uses"]) + slot)
			return [{"type": "feature", "actor_id": actor_id, "feature_id": feature_id, "slot_level": slot}]
		_:
			var option: String = feature_id.trim_prefix("metamagic_")
			_spend_points(actor, int(METAMAGIC[option]))
			actor["metamagic"] = option
	return [{"type": "feature", "actor_id": actor_id, "feature_id": feature_id}]

static func feature_label(actor: Dictionary, feature_id: String) -> String:
	var features: Dictionary = actor.get("features", {})
	match feature_id:
		"innate_sorcery":
			var innate: Dictionary = features.get("innate_sorcery", {})
			return TranslationServer.translate("FEATURE_INNATE_SORCERY_BUTTON") % [int(innate.get("uses", 0)), int(innate.get("max", 0))]
		"font_create_slot", "font_gain_points":
			var feature: Dictionary = features.get("sorcery_points", {})
			return TranslationServer.translate("FEATURE_%s_BUTTON" % feature_id.to_upper()) % [int(feature.get("uses", 0)), int(feature.get("max", 0))]
	var option: String = feature_id.trim_prefix("metamagic_")
	var armed: bool = String(actor.get("metamagic", "")) == option
	return TranslationServer.translate("FEATURE_METAMAGIC_BUTTON_ARMED" if armed else "FEATURE_METAMAGIC_BUTTON") % \
		[TranslationServer.translate("METAMAGIC_" + option.to_upper()), int(METAMAGIC.get(option, 0))]

# --- Combat hooks ------------------------------------------------------------

## Innate Sorcery: advantage on spell attack rolls.
static func attack_advantages(state: GameState, attacker_id: String, _target_id: String, weapon: Dictionary) -> Array[StringName]:
	if weapon.has("spell_id") and innate_active(state.actors.get(attacker_id, {})):
		return [&"innate_sorcery"]
	return []

## Shocking Grasp: a hit creature cannot take reactions until its next turn.
static func after_attack(state: GameState, _attacker_id: String, target_id: String, weapon: Dictionary,
		hit: bool, _rng: RandomNumberGenerator) -> Array[Dictionary]:
	if hit and String(weapon.get("spell_id", "")) == "shocking_grasp" and state.actors.has(target_id):
		state.actors[target_id]["reaction_available"] = false
		return [{"type": "effect", "actor_id": target_id, "kind": "no_reactions", "spell_id": "shocking_grasp"}]
	return []

## Innate Sorcery lasts 1 minute (10 rounds), counted at the start of the sorcerer's turns.
static func on_turn_start(state: GameState, actor_id: String) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	var events: Array[Dictionary] = []
	for effect: Dictionary in ActiveEffects.effects(actor):
		if String(effect.get("kind", "")) == "innate_sorcery":
			effect["rounds_left"] = int(effect.get("rounds_left", 1)) - 1
	if ActiveEffects.remove_where(actor, func(effect: Dictionary) -> bool:
			return String(effect.get("kind", "")) == "innate_sorcery" and int(effect.get("rounds_left", 0)) <= 0) > 0:
		actor["spell_save_dc"] = int(actor.get("spell_save_dc", 11)) - 1
		events.append({"type": "effects_expired", "actor_id": actor_id})
	return events

## Metamagic armed but not used this turn: the points come back.
static func on_turn_end(state: GameState, actor_id: String, _rng: RandomNumberGenerator) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	var option: String = String(actor.get("metamagic", ""))
	if not option.is_empty():
		actor.erase("metamagic")
		var feature: Dictionary = actor["features"].get("sorcery_points", {})
		if not feature.is_empty():
			feature["uses"] = mini(int(feature["max"]), int(feature["uses"]) + int(METAMAGIC.get(option, 0)))
	return []

# --- Rests -------------------------------------------------------------------

## Sorcerous Restoration (level 5): a Short Rest gives back half the level in Sorcery
## Points, once per Long Rest. A Long Rest ends Innate Sorcery and armed Metamagic.
static func on_rest(actor: Dictionary, rest: String) -> void:
	var features: Dictionary = actor.get("features", {})
	if rest == "long":
		if features.has("sorcerous_restoration"):
			features["sorcerous_restoration"]["used"] = false
		if ActiveEffects.remove_where(actor, func(effect: Dictionary) -> bool:
				return String(effect.get("kind", "")) == "innate_sorcery") > 0:
			actor["spell_save_dc"] = int(actor.get("spell_save_dc", 11)) - 1
		actor.erase("metamagic")
		return
	var restoration: Dictionary = features.get("sorcerous_restoration", {})
	var points_feature: Dictionary = features.get("sorcery_points", {})
	if restoration.is_empty() or bool(restoration.get("used", false)) or points_feature.is_empty():
		return
	var regain: int = floori(int(actor.get("level", 1)) / 2.0)
	if int(points_feature["uses"]) < int(points_feature["max"]):
		points_feature["uses"] = mini(int(points_feature["max"]), int(points_feature["uses"]) + regain)
		restoration["used"] = true
