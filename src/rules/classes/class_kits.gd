class_name ClassKits
extends RefCounted
## Registry for the classes beyond Fighter and Wizard. A class becomes playable as soon
## as res://src/rules/classes/<id>_kit.gd exists; shared code (character creation,
## HeroKit, ClassFeatures, ProgressionRules, RestRules, EquipmentRules, CombatRules,
## UseFeatureCommand, the combat HUD) asks this registry instead of naming classes.
## Every kit function is optional. The full interface is in src/rules/classes/README.md.

const KIT_PATH: String = "res://src/rules/classes/%s_kit.gd"
## Built before kits existed; they keep their own code paths.
const BUILT_IN: Array[String] = ["fighter", "wizard"]

## Spell effect modules whose hooks run for every actor, whatever its class (Longstrider,
## Spike Growth, Protection from Poison): the same hook names as kits, see README.md.
const EFFECT_MODULES: Array[String] = ["res://src/rules/spells/ranger_spells.gd"]

static var _kits: Dictionary = {}
static var _methods: Dictionary = {}
static var _modules: Array = []

## Calls `method` on every effect module that defines it; returns the non-null results.
static func call_modules(method: String, args: Array = []) -> Array:
	if _modules.is_empty():
		for path: String in EFFECT_MODULES:
			var script: Script = load(path) as Script
			var names: Dictionary = {}
			for entry: Dictionary in script.get_script_method_list():
				names[String(entry["name"])] = true
			_modules.append({"script": script, "methods": names})
	var results: Array = []
	for module: Dictionary in _modules:
		if module["methods"].has(method):
			var value: Variant = (module["script"] as Script).callv(method, args)
			if value != null:
				results.append(value)
	return results

static func kit(class_id: String) -> Script:
	if class_id.is_empty() or class_id in BUILT_IN:
		return null
	if not _kits.has(class_id):
		var path: String = KIT_PATH % class_id
		var script: Script = load(path) as Script if ResourceLoader.exists(path) else null
		_kits[class_id] = script
		var names: Dictionary = {}
		if script != null:
			for method: Dictionary in script.get_script_method_list():
				names[String(method["name"])] = true
		_methods[class_id] = names
	return _kits[class_id]

static func has_kit(class_id: String) -> bool:
	return kit(class_id) != null

static func has(class_id: String, method: String) -> bool:
	return kit(class_id) != null and _methods[class_id].has(method)

## Calls a kit's static function when the class has a kit and defines it.
static func call_kit(class_id: String, method: String, args: Array = [], fallback: Variant = null) -> Variant:
	if not has(class_id, method):
		return fallback
	return kit(class_id).callv(method, args)

static func constant(class_id: String, name: String, fallback: Variant = null) -> Variant:
	var script: Script = kit(class_id)
	if script == null:
		return fallback
	var constants: Dictionary = script.get_script_constant_map()
	return constants.get(name, fallback)

static func class_of(actor: Dictionary) -> String:
	return String(actor.get("class_id", ""))

# --- Creation ---------------------------------------------------------------

## Standard-array order, most important ability first (kit const PRIORITY).
static func priority(class_id: String) -> Array:
	return constant(class_id, "PRIORITY", [])

## {"class": [skill, ...], "human": skill} (kit const SKILLS).
static func default_skills(class_id: String) -> Dictionary:
	return constant(class_id, "SKILLS", {})

# --- Features and level-up --------------------------------------------------

static func implemented(class_id: String, feature_id: String, level: int) -> bool:
	if has(class_id, "implemented"):
		return bool(call_kit(class_id, "implemented", [feature_id, level]))
	var maximum: int = int(constant(class_id, "IMPLEMENTED_MAX_LEVEL", 10))
	return level <= maximum and not constant(class_id, "DATA_ONLY", {}).has(feature_id)

## Extra level-up picks of a kit class: [{"key", "count", "options": [id], "title_key",
## "option_prefix"}]. The level-up screen draws them; ProgressionRules validates them.
static func level_choices(actor: Dictionary, level: int) -> Array:
	return call_kit(class_of(actor), "level_choices", [actor, level], [])

# --- Equipment, armour and speed ---------------------------------------------

## A class AC formula without armour (Unarmored Defense). 0 = none.
static func unarmored_ac(actor: Dictionary, shield: bool) -> int:
	return int(call_kit(class_of(actor), "unarmored_ac", [actor, shield], 0))

## Extra AC entries [{"amount", "source"}] (Fighting Style Defense).
static func ac_bonus(actor: Dictionary, armor_id: StringName) -> Array:
	return call_kit(class_of(actor), "ac_bonus", [actor, armor_id], [])

static func speed_bonus_m(actor: Dictionary) -> float:
	return float(call_kit(class_of(actor), "speed_bonus_m", [actor], 0.0))

## Lets a class change a freshly built weapon record (Martial Arts die, Dexterity).
static func adjust_weapon(actor: Dictionary, record: Dictionary, item: Dictionary) -> void:
	call_kit(class_of(actor), "adjust_weapon", [actor, record, item])

# --- Combat hooks -----------------------------------------------------------

static func attack_advantages(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(call_kit(class_of(state.actors.get(attacker_id, {})), "attack_advantages",
		[state, attacker_id, target_id, weapon], []))
	# The target's own features can grant attackers advantage (Reckless Attack).
	result.append_array(call_kit(class_of(state.actors.get(target_id, {})), "incoming_advantages",
		[state, attacker_id, target_id, weapon], []))
	return result

static func attack_disadvantages(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(call_kit(class_of(state.actors.get(attacker_id, {})), "attack_disadvantages",
		[state, attacker_id, target_id, weapon], []))
	result.append_array(call_kit(class_of(state.actors.get(target_id, {})), "incoming_disadvantages",
		[state, attacker_id, target_id, weapon], []))
	return result

## Flat damage riders on a weapon hit, [{"amount", "source"}] (Rage Damage).
static func damage_bonus(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> Array[RuleModifier]:
	var result: Array[RuleModifier] = []
	var entries: Array = call_kit(class_of(state.actors.get(attacker_id, {})), "damage_bonus",
		[state, attacker_id, target_id, weapon], []).duplicate()
	for extra: Array in call_modules("damage_bonus", [state, attacker_id, target_id, weapon]):
		entries.append_array(extra)
	for entry: Dictionary in entries:
		result.append(RuleModifier.new(int(entry["amount"]), StringName(String(entry["source"]))))
	return result

## Flat attack roll bonus [{"amount", "source"}] from effects (Magic Weapon); preview and roll.
static func attack_bonus(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> Array[RuleModifier]:
	var result: Array[RuleModifier] = []
	var entries: Array = call_kit(class_of(state.actors.get(attacker_id, {})), "attack_bonus",
		[state, attacker_id, target_id, weapon], []).duplicate()
	for extra: Array in call_modules("attack_bonus", [state, attacker_id, target_id, weapon]):
		entries.append_array(extra)
	for entry: Dictionary in entries:
		result.append(RuleModifier.new(int(entry["amount"]), StringName(String(entry["source"]))))
	return result

## Extra dice on a weapon hit, [{"dice", "damage_type", "source"}]; doubled on a crit.
## A kit may spend resources here (once-per-turn riders), so call it only on a real hit.
static func extra_damage_dice(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		critical: bool) -> Array:
	var result: Array = call_kit(class_of(state.actors.get(attacker_id, {})), "extra_damage_dice",
		[state, attacker_id, target_id, weapon, critical], []).duplicate()
	for extra: Array in call_modules("extra_damage_dice", [state, attacker_id, target_id, weapon, critical]):
		result.append_array(extra)
	return result

## Average of the extra dice for previews; must not change state.
static func expected_extra_damage(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> float:
	var total: float = float(call_kit(class_of(state.actors.get(attacker_id, {})), "expected_extra_damage",
		[state, attacker_id, target_id, weapon], 0.0))
	for extra: Variant in call_modules("expected_extra_damage", [state, attacker_id, target_id, weapon]):
		total += float(extra)
	return total

## The target's kit may lower a weapon hit's damage with a reaction (Deflect Attacks):
## returns {"amount", "events"}.
static func damage_reduction(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		amount: int, rng: RandomNumberGenerator) -> Dictionary:
	return call_kit(class_of(state.actors.get(target_id, {})), "damage_reduction",
		[state, attacker_id, target_id, weapon, amount, rng], {})

## Evasion: half-damage saves of this ability deal nothing on a success, half on a failure.
static func evades(actor: Dictionary, ability: StringName) -> bool:
	return bool(call_kit(class_of(actor), "evades", [actor, ability], false))

static func initiative_advantages(actor: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(call_kit(class_of(actor), "initiative_advantages", [actor], []))
	return result

## Every kit actor when a fight ends (Rage ends, per-combat flags clear).
static func on_combat_end(state: GameState) -> void:
	for id: String in state.actors:
		call_kit(class_of(state.actors[id]), "on_combat_end", [state, id])
		call_modules("on_combat_end", [state, id])

## Spells a class may cast without a slot (Ranger Favored Enemy): kit free_casts(actor)
## returns {spell_id: feature_id}; that feature's "uses" pay for the cast.
static func free_cast_available(caster: Dictionary, spell_id: String) -> bool:
	var feature_id: String = String(call_kit(class_of(caster), "free_casts", [caster], {}).get(spell_id, ""))
	return not feature_id.is_empty() and int(caster.get("features", {}).get(feature_id, {}).get("uses", 0)) > 0

static func spend_free_cast(caster: Dictionary, spell_id: String) -> void:
	var feature_id: String = String(call_kit(class_of(caster), "free_casts", [caster], {}).get(spell_id, ""))
	var feature: Dictionary = caster.get("features", {}).get(feature_id, {})
	if not feature.is_empty():
		feature["uses"] = maxi(0, int(feature.get("uses", 0)) - 1)

## Before a weapon hit's damage: a target's reaction that could halve it (Rogue Uncanny
## Dodge). Returns that feature id, "" = none. Pure: CombatRules offers it as a reaction and
## CastReactionCommand spends the reaction when the target accepts.
static func damage_halved_by(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> String:
	return String(call_kit(class_of(state.actors.get(target_id, {})), "halve_attack_damage",
		[state, attacker_id, target_id, weapon], ""))

static func resistances(actor: Dictionary) -> Array:
	var result: Array = call_kit(class_of(actor), "resistances", [actor], []).duplicate()
	for extra: Array in call_modules("resistances", [actor]):
		result.append_array(extra)
	return result

## Flat bonuses on ability checks [{"amount", "source"}] (Pass without Trace on Stealth).
static func check_modifiers(actor: Dictionary, skill: String) -> Array[RuleModifier]:
	var result: Array[RuleModifier] = []
	var entries: Array = call_kit(class_of(actor), "check_modifiers", [actor, skill], []).duplicate()
	for extra: Array in call_modules("check_modifiers", [actor, skill]):
		entries.append_array(extra)
	for entry: Dictionary in entries:
		result.append(RuleModifier.new(int(entry["amount"]), StringName(String(entry["source"]))))
	return result

## After a creature finished a move along `path` (zones such as Spike Growth) -> events.
static func after_move(state: GameState, mover_id: String, path: Variant, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for extra: Array in call_modules("after_move", [state, mover_id, path, rng]):
		result.append_array(extra)
	return result

static func save_advantages(actor: Dictionary, ability: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(call_kit(class_of(actor), "save_advantages", [actor, ability], []))
	return result

static func on_turn_start(state: GameState, actor_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(call_kit(class_of(state.actors.get(actor_id, {})), "on_turn_start", [state, actor_id], []))
	return result

static func on_turn_end(state: GameState, actor_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(call_kit(class_of(state.actors.get(actor_id, {})), "on_turn_end", [state, actor_id, rng], []))
	for extra: Array in call_modules("on_turn_end", [state, actor_id, rng]):
		result.append_array(extra)
	return result

## After a weapon attack roll resolved (hit or miss), for both attacker and target kits.
static func after_attack(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		hit: bool, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(call_kit(class_of(state.actors.get(attacker_id, {})), "after_attack",
		[state, attacker_id, target_id, weapon, hit, rng], []))
	result.append_array(call_kit(class_of(state.actors.get(target_id, {})), "after_attacked",
		[state, attacker_id, target_id, weapon, hit, rng], []))
	for extra: Array in call_modules("after_attack", [state, attacker_id, target_id, weapon, hit, rng]):
		result.append_array(extra)
	return result

# --- Features used from the hotbar ------------------------------------------

## Every hotbar feature id any kit knows (kit const FEATURES), for decoding saved commands.
static func all_feature_ids() -> Array[String]:
	var result: Array[String] = []
	for class_id: String in HeroFactory.CLASS_ORDER:
		for feature_id: Variant in constant(class_id, "FEATURES", []):
			result.append(String(feature_id))
	return result

## Feature ids a kit puts on the combat hotbar, in order.
static func feature_buttons(actor: Dictionary) -> Array[String]:
	var result: Array[String] = []
	result.assign(call_kit(class_of(actor), "feature_buttons", [actor], []))
	return result

## "" when the feature can be used now, else a translation key with the reason.
static func feature_reason(state: GameState, actor_id: String, feature_id: String) -> String:
	var actor: Dictionary = state.actors.get(actor_id, {})
	if not feature_id in feature_buttons(actor):
		return "FEATURE_NO_USES"
	return String(call_kit(class_of(actor), "feature_reason", [state, actor_id, feature_id], "FEATURE_NO_USES"))

static func use_feature(state: GameState, actor_id: String, feature_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(call_kit(class_of(state.actors.get(actor_id, {})), "use_feature", [state, actor_id, feature_id, rng], []))
	return result

## Button text of a kit feature; defaults to FEATURE_<ID>_BUTTON with uses and maximum.
static func feature_label(actor: Dictionary, feature_id: String) -> String:
	if has(class_of(actor), "feature_label"):
		return String(call_kit(class_of(actor), "feature_label", [actor, feature_id]))
	var feature: Dictionary = actor.get("features", {}).get(feature_id, {})
	return TranslationServer.translate("FEATURE_%s_BUTTON" % feature_id.to_upper()) % [int(feature.get("uses", 0)), int(feature.get("max", 0))]

# --- Rests ------------------------------------------------------------------

## Features stored as {"uses", "max", "recharge": "short"|"long"} recharge without kit code:
## a Long Rest restores all; a Short Rest restores "short" features fully and "long"
## features by "short_regain" (0 unless set). Returns the recharged ids.
static func recharge(actor: Dictionary, rest: String) -> Array[String]:
	var recharged: Array[String] = []
	var features: Dictionary = actor.get("features", {})
	for feature_id: Variant in features:
		var feature: Variant = features[feature_id]
		if not feature is Dictionary or not feature.has("recharge") or not feature.has("max"):
			continue
		var before: int = int(feature.get("uses", 0))
		var maximum: int = int(feature["max"])
		if rest == "long" or String(feature["recharge"]) == "short":
			feature["uses"] = maximum
		else:
			feature["uses"] = mini(maximum, before + int(feature.get("short_regain", 0)))
		if int(feature["uses"]) > before:
			recharged.append(String(feature_id))
	call_kit(class_of(actor), "on_rest", [actor, rest])
	return recharged

# --- Shared helpers for kits ------------------------------------------------

## A feature counter that grows with level and keeps spent uses spent.
static func set_uses(features: Dictionary, feature_id: String, maximum: int, recharge_on: String,
		short_regain: int = 0) -> void:
	var feature: Dictionary = features.get(feature_id, {"uses": 0, "max": 0})
	feature["uses"] = clampi(int(feature.get("uses", 0)) + maximum - int(feature.get("max", 0)), 0, maximum)
	feature["max"] = maximum
	feature["recharge"] = recharge_on
	if short_regain > 0:
		feature["short_regain"] = short_regain
	features[feature_id] = feature

## Spell slots, attack bonus and save DC for a caster record. slots = slots per spell
## level at this class level (e.g. SpellRules.full_caster_slots or a half-caster table).
static func refresh_spellcasting(actor: Dictionary, ability: StringName, slots_max: Array) -> void:
	var level: int = int(actor.get("level", 1))
	var scores: Dictionary = actor.get("ability_scores", {})
	var score: int = int(scores.get(ability, scores.get(String(ability), 10)))
	var old_maximum: Array = actor.get("spell_slots_max", [])
	var slots: Array = actor.get("spell_slots", []).duplicate()
	for index: int in slots_max.size():
		var before: int = int(old_maximum[index]) if index < old_maximum.size() else 0
		var current: int = int(slots[index]) if index < slots.size() else 0
		if index >= slots.size():
			slots.append(0)
		slots[index] = clampi(current + int(slots_max[index]) - before, 0, int(slots_max[index]))
	actor["spell_slots"] = slots
	actor["spell_slots_max"] = slots_max.duplicate()
	actor["spell_ability"] = String(ability)
	actor["spell_attack_modifiers"] = SpellRules.spell_attack_modifiers(ability, score, level)
	actor["spell_attack_bonus"] = SpellRules.spell_attack_bonus(score, level)
	actor["spell_save_dc"] = SpellRules.spell_save_dc(score, level)
	if not actor.has("concentration"):
		actor["concentration"] = {}

static func score(actor: Dictionary, ability: String) -> int:
	var scores: Dictionary = actor.get("ability_scores", {})
	return int(scores.get(StringName(ability), scores.get(ability, 10)))

static func wears_armor(actor: Dictionary) -> bool:
	var armor: String = String(actor.get("armor", "none"))
	return not armor.is_empty() and armor != "none"

static func heavy_armor(actor: Dictionary) -> bool:
	var armor: StringName = StringName(String(actor.get("armor", "none")))
	return ArmorRules.ARMOR.has(armor) and ArmorRules.ARMOR[armor]["category"] == &"heavy"
