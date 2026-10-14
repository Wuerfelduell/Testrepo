class_name ClassFeatures
extends RefCounted
## Active Fighter and Wizard features up to level 5 (SRD 5.2 class tables) on plain
## hero records. Pure: no Nodes, no singletons, no randomness. Features above level 5
## stay names in data/classes/ only (see DATA_ONLY).

## Playable classes with active features (HeroFactory.PLAYABLE is this list).
const ACTIVE_CLASSES: Array[String] = ["fighter", "wizard"]
const IMPLEMENTED_MAX_LEVEL: int = 5
## Scholar: expertise in one of these skills the Wizard is proficient in.
const SCHOLAR_SKILLS: Array[String] = ["arcana", "history", "investigation", "medicine", "nature", "religion"]
## Fighting Style feats with rules behind them (CombatRules.damage_die_minimum).
const FIGHTING_STYLES: Array[String] = ["great_weapon_fighting"]
## Features through level 5 that are listed but have no effect in play yet, and why.
const DATA_ONLY: Dictionary = {
	"tactical_mind": "no ability checks in play yet",
	"weapon_mastery": "only the starting weapon's mastery; the other choices wait for the owner",
	"ritual_adept": "no rituals in play yet",
}

static func is_active_class(actor: Dictionary) -> bool:
	return String(actor.get("class_id", "")) in ACTIVE_CLASSES

static func definition(class_id: String) -> ClassDefinition:
	var path: String = "res://data/classes/%s.tres" % class_id
	if not class_id in ACTIVE_CLASSES or not ResourceLoader.exists(path):
		return null
	return load(path) as ClassDefinition

## Feature ids gained at exactly this level, as listed in data/classes/.
static func feature_ids_at(class_id: String, level: int) -> Array[String]:
	var result: Array[String] = []
	var source: ClassDefinition = definition(class_id)
	if source != null:
		for feature: Dictionary in source.features_at_level(level):
			result.append(String(feature["id"]))
	return result

static func implemented(feature_id: String, level: int) -> bool:
	return level <= IMPLEMENTED_MAX_LEVEL and not DATA_ONLY.has(feature_id)

static func action_surge_uses(fighter_level: int) -> int:
	if fighter_level >= 17:
		return 2
	return 1 if fighter_level >= 2 else 0

## Extra Attack: two attacks whenever the Attack action is taken.
static func attacks_per_action(actor: Dictionary) -> int:
	return int(actor.get("features", {}).get("extra_attack", {}).get("attacks", 1))

## Spell counts and lists per class live in ClassSpellcasting; these keep the Wizard names.
static func wizard_cantrips(level: int) -> int:
	return ClassSpellcasting.cantrips_known("wizard", level)

static func wizard_prepared(level: int) -> int:
	return ClassSpellcasting.prepared_limit("wizard", level)

## The Wizard's spellbook (level 1+ spells). Older records only had the prepared list.
static func spellbook(actor: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var source: Array = actor.get("spellbook", []) if actor.has("spellbook") else actor.get("spells", [])
	for value: Variant in source:
		var spell: SpellDefinition = SpellBook.get_spell(String(value))
		if spell != null and not spell.is_cantrip() and not String(value) in result:
			result.append(String(value))
	return result

static func known_cantrips(actor: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in actor.get("spells", []):
		var spell: SpellDefinition = SpellBook.get_spell(String(value))
		if spell != null and spell.is_cantrip():
			result.append(String(value))
	return result

## Prepared level-1+ spells, without the always-prepared ones (they never count).
static func prepared_spells(actor: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var always: Array[String] = ClassSpellcasting.always_prepared(String(actor.get("class_id", "")), int(actor.get("level", 1)))
	for value: Variant in actor.get("spells", []):
		var spell: SpellDefinition = SpellBook.get_spell(String(value))
		if spell != null and not spell.is_cantrip() and not String(value) in always:
			result.append(String(value))
	return result

## Writes cantrips + prepared + always-prepared spells back into the castable "spells" list.
static func set_prepared(actor: Dictionary, prepared: Array) -> void:
	var castable: Array = []
	for spell_id: String in known_cantrips(actor):
		castable.append(spell_id)
	for value: Variant in prepared:
		castable.append(String(value))
	for spell_id: String in ClassSpellcasting.always_prepared(String(actor.get("class_id", "")), int(actor.get("level", 1))):
		if not spell_id in castable:
			castable.append(spell_id)
	actor["spells"] = castable

## Level-1+ Wizard spells that exist in data and fit the highest slot of this level.
static func wizard_spell_options(level: int, excluded: Array) -> Array[String]:
	return ClassSpellcasting.spell_options("wizard", level, excluded)

static func wizard_cantrip_options(excluded: Array) -> Array[String]:
	return ClassSpellcasting.cantrip_options("wizard", excluded)

## Feature records of a new hero of this class (HeroKit.activate). Uses scale with the level.
static func start_features(class_id: String, level: int) -> Dictionary:
	match class_id:
		"fighter":
			var uses: int = SpellRules.second_wind_uses(level)
			# Fighting Style chosen by the owner (Q34): Great Weapon Fighting.
			return {"second_wind": {"uses": uses, "max": uses},
				"weapon_mastery": {"weapons": ["greatsword", "longsword"]}, "fighting_style": HeroKit.FIGHTER_STYLE}
		"wizard":
			return {"arcane_recovery": {"used": false}}
	return {}

## Character choices a new hero of this class still owes (shown as pending).
static func start_choices(class_id: String) -> Array:
	match class_id:
		"fighter":
			# The third mastery weapon still waits for the owner.
			return [&"weapon_mastery_kinds"]
	return []

## Brings the feature records of an active class up to the given level. Uses gained
## by a level are available at once; spent uses stay spent.
static func advance(actor: Dictionary, level: int) -> void:
	if not actor.get("features") is Dictionary:
		actor["features"] = {}
	var features: Dictionary = actor["features"]
	match String(actor.get("class_id", "")):
		"fighter":
			var second_wind: Dictionary = features.get("second_wind", {"uses": 0, "max": 0})
			var maximum: int = SpellRules.second_wind_uses(level)
			second_wind["uses"] = clampi(int(second_wind.get("uses", 0)) + maximum - int(second_wind.get("max", 0)), 0, maximum)
			second_wind["max"] = maximum
			features["second_wind"] = second_wind
			var surges: int = action_surge_uses(level)
			if surges > 0:
				var surge: Dictionary = features.get("action_surge", {"uses": 0, "max": 0})
				surge["uses"] = clampi(int(surge.get("uses", 0)) + surges - int(surge.get("max", 0)), 0, surges)
				surge["max"] = surges
				features["action_surge"] = surge
			if level >= 5:
				features["extra_attack"] = {"attacks": 2}
				features["tactical_shift"] = {}
		"wizard":
			if level >= 5:
				features["memorize_spell"] = {}
