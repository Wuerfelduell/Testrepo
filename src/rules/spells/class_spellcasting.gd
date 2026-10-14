class_name ClassSpellcasting
extends RefCounted
## Spellcasting per class (SRD 5.2 class tables, levels 1-10). One entry per casting
## class; every other system asks this table instead of checking class ids.
## Pure: no Nodes, no singletons, no randomness.
##
## Entry keys:
##   ability      spellcasting ability ("int", "wis", "cha")
##   progression  slot table: "full" (Wizard, Cleric, Druid ...), "half" (Paladin, Ranger),
##                "pact" (Warlock Pact Magic: all slots of one level, back on a Short Rest)
##   cantrips     cantrips known per class level (index 0 = level 1)
##   prepared     prepared spells per class level
##   spellbook    true: prepares from a spellbook that grows by new_spells per level
##                (Wizard); false: prepares from the whole class list
##   new_spells   spellbook spells learned per level after the first
##   list         class spell list (ids); only ids that exist in data/spells/ count
##   start        castable list of a new level-1 hero (cantrips first, then prepared)
##   always       spells always prepared, not counted against the limit, with the
##                class level they arrive at ({"divine_smite": 2})

const CASTERS: Dictionary = {
	"wizard": {
		"ability": "int", "progression": "full", "spellbook": true, "new_spells": 2,
		"cantrips": [3, 3, 3, 4, 4, 4, 4, 4, 4, 5],
		"prepared": [4, 5, 6, 7, 9, 10, 11, 12, 14, 15],
		"list": ["fire_bolt", "ray_of_frost", "acid_splash", "poison_spray", "chill_touch", "shocking_grasp",
			"magic_missile", "burning_hands", "shield", "sleep", "thunderwave", "chromatic_orb", "ray_of_sickness",
			"color_spray", "grease", "hideous_laughter", "false_life", "mage_armor",
			"shatter", "scorching_ray", "hold_person", "blur", "invisibility", "web", "misty_step",
			"fireball", "lightning_bolt", "haste", "slow", "hypnotic_pattern", "fear", "vampiric_touch",
			"blight", "phantasmal_killer", "greater_invisibility", "black_tentacles", "dimension_door",
			"cone_of_cold", "hold_monster",
			"ice_knife", "protection_from_evil_and_good", "toll_the_dead", "blindness_deafness", "magic_weapon", "dispel_magic", "sleet_storm", "bestow_curse", "banishment", "stoneskin"],
		# The third cantrip, Poison Spray (1d12), is the owner's wish for a strong one (13-10-2026).
		"start": ["fire_bolt", "ray_of_frost", "poison_spray", "magic_missile", "burning_hands", "shield", "sleep"],
	},
	# Cleric, Druid, Paladin (thread "Kleriker, Paladin, Druide"); class features in
	# src/rules/classes/<id>_kit.gd. Channel Divinity, Lay on Hands and Wild Shape are
	# "always" feature spells (SpellDefinition.feature_resource), never picks.
	"cleric": {
		"ability": "wis", "progression": "full",
		"cantrips": [3, 3, 3, 4, 4, 4, 4, 4, 4, 5],
		"prepared": [4, 5, 6, 7, 9, 10, 11, 12, 14, 15],
		# 2024 list as far as the rules carry it (owner 14-10-2026: as many 5.5e spells as possible).
		"list": ["sacred_flame", "resistance", "guidance", "toll_the_dead", "word_of_radiance",
			"bless", "cure_wounds", "guiding_bolt", "healing_word", "inflict_wounds", "shield_of_faith", "bane",
			"command", "protection_from_evil_and_good",
			"aid", "hold_person", "spiritual_weapon", "prayer_of_healing", "blindness_deafness", "silence",
			"lesser_restoration",
			"mass_healing_word", "spirit_guardians", "beacon_of_hope", "bestow_curse", "dispel_magic",
			"banishment", "death_ward",
			"flame_strike", "mass_cure_wounds", "greater_restoration", "insect_plague", "contagion"],
		# Guidance helps the hero's skill checks in dialogues (DialogueChooseCommand.roll_check).
		"start": ["sacred_flame", "resistance", "guidance", "bless", "cure_wounds", "guiding_bolt", "healing_word"],
		"always": {"divine_spark": 2, "divine_spark_heal": 2, "turn_undead": 2},
	},
	"druid": {
		"ability": "wis", "progression": "full",
		"cantrips": [2, 2, 2, 3, 3, 3, 3, 3, 3, 4],
		"prepared": [4, 5, 6, 7, 9, 10, 11, 12, 14, 15],
		"list": ["produce_flame", "starry_wisp", "poison_spray", "resistance", "guidance", "thorn_whip",
			"cure_wounds", "healing_word", "entangle", "faerie_fire", "thunderwave", "ice_knife", "goodberry",
			"fog_cloud", "longstrider", "jump",
			"barkskin", "hold_person", "moonbeam", "flame_blade", "heat_metal", "lesser_restoration",
			"spike_growth", "pass_without_trace",
			"call_lightning", "dispel_magic", "sleet_storm",
			"blight", "ice_storm", "stoneskin",
			"mass_cure_wounds", "greater_restoration", "insect_plague", "contagion", "wrath_of_nature"],
		"start": ["produce_flame", "poison_spray", "cure_wounds", "healing_word", "entangle", "faerie_fire"],
		"always": {"wild_shape": 2, "revert_wild_shape": 2},
	},
	"paladin": {
		"ability": "cha", "progression": "half",
		"cantrips": [],
		"prepared": [2, 3, 4, 5, 6, 6, 7, 7, 9, 9],
		"list": ["bless", "cure_wounds", "divine_favor", "shield_of_faith", "command", "heroism",
			"protection_from_evil_and_good", "searing_smite", "thunderous_smite", "wrathful_smite", "compelled_duel",
			"aid", "magic_weapon", "shining_smite", "prayer_of_healing", "lesser_restoration",
			"blinding_smite", "crusaders_mantle", "aura_of_vitality", "elemental_weapon", "dispel_magic"],
		"start": ["bless", "divine_favor"],
		"always": {"lay_on_hands": 1, "abjure_foes": 9},
	},
	# Bard, Sorcerer, Warlock (thread "Barde, Zauberer, Hexenmeister"); class features in
	# src/rules/classes/<id>_kit.gd. "bardic_inspiration" is a class action cast through
	# the spell pipeline (a feature spell, always prepared), never a pick.
	"bard": {
		"ability": "cha", "progression": "full",
		"cantrips": [2, 2, 2, 3, 3, 3, 3, 3, 3, 4],
		"prepared": [4, 5, 6, 7, 9, 10, 11, 12, 14, 15],
		"list": ["vicious_mockery", "starry_wisp", "healing_word", "dissonant_whispers", "thunderwave",
			"sleep", "cure_wounds", "color_spray", "hideous_laughter", "shatter", "hold_person", "invisibility",
			"fear", "hypnotic_pattern", "slow", "phantasmal_killer", "greater_invisibility", "dimension_door",
			"hold_monster",
			"bane", "command", "heroism", "faerie_fire", "heat_metal", "silence", "blindness_deafness", "dispel_magic", "bestow_curse", "greater_restoration", "mass_cure_wounds"],
		"start": ["vicious_mockery", "starry_wisp", "healing_word", "dissonant_whispers", "thunderwave", "sleep"],
		"always": {"bardic_inspiration": 1},
	},
	"sorcerer": {
		"ability": "cha", "progression": "full",
		"cantrips": [4, 4, 4, 5, 5, 5, 5, 5, 5, 6],
		"prepared": [2, 4, 6, 7, 9, 10, 11, 12, 14, 15],
		"list": ["fire_bolt", "ray_of_frost", "shocking_grasp", "poison_spray", "acid_splash", "chill_touch",
			"sorcerous_burst", "magic_missile", "burning_hands", "shield", "sleep", "thunderwave", "chromatic_orb",
			"ray_of_sickness", "color_spray", "false_life", "mage_armor",
			"scorching_ray", "shatter", "hold_person", "blur", "invisibility", "web", "misty_step",
			"fireball", "lightning_bolt", "haste", "slow", "hypnotic_pattern", "fear", "vampiric_touch",
			"blight", "greater_invisibility", "dimension_door", "cone_of_cold", "hold_monster",
			"ice_knife", "blindness_deafness", "magic_weapon", "dispel_magic", "sleet_storm", "banishment", "stoneskin", "insect_plague"],
		"start": ["fire_bolt", "ray_of_frost", "shocking_grasp", "poison_spray", "magic_missile", "burning_hands"],
	},
	"warlock": {
		"ability": "cha", "progression": "pact",
		"cantrips": [2, 2, 2, 3, 3, 3, 3, 3, 3, 4],
		"prepared": [2, 3, 4, 5, 6, 7, 8, 9, 10, 10],
		"list": ["eldritch_blast", "poison_spray", "chill_touch", "hex", "arms_of_hadar",
			"hold_person", "invisibility", "misty_step", "fear", "hypnotic_pattern", "vampiric_touch",
			"blight", "dimension_door", "hold_monster",
			"protection_from_evil_and_good", "toll_the_dead", "bane", "dispel_magic", "banishment"],
		"start": ["eldritch_blast", "chill_touch", "hex", "arms_of_hadar"],
	},
	# Ranger (thread "Barbar, Mönch, Waldläufer"); features in src/rules/classes/ranger_kit.gd.
	# Favored Enemy: Hunter's Mark always prepared, free casts in the kit. Other list ids
	# appear as soon as another class thread adds them to data/spells/.
	"ranger": {
		"ability": "wis", "progression": "half",
		"cantrips": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"prepared": [2, 3, 4, 4, 6, 6, 7, 7, 9, 9],
		"list": ["hunters_mark", "cure_wounds", "entangle", "ensnaring_strike", "goodberry", "fog_cloud",
			"longstrider", "jump", "aid", "barkskin", "lesser_restoration", "spike_growth", "pass_without_trace"],
		"start": ["cure_wounds", "entangle"],
		"always": {"hunters_mark": 1},
	},
}

static func is_caster(class_id: String) -> bool:
	return CASTERS.has(class_id)

static func entry(class_id: String) -> Dictionary:
	return CASTERS.get(class_id, {})

static func ability(class_id: String) -> String:
	return String(entry(class_id).get("ability", ""))

static func uses_spellbook(class_id: String) -> bool:
	return bool(entry(class_id).get("spellbook", false))

static func new_spells_per_level(class_id: String) -> int:
	return int(entry(class_id).get("new_spells", 0))

static func _by_level(class_id: String, key: String, level: int) -> int:
	var table: Array = entry(class_id).get(key, [])
	if table.is_empty():
		return 0
	return int(table[clampi(level, 1, table.size()) - 1])

static func cantrips_known(class_id: String, level: int) -> int:
	return _by_level(class_id, "cantrips", level)

static func prepared_limit(class_id: String, level: int) -> int:
	return _by_level(class_id, "prepared", level)

## Extra cantrips from class choices (Cleric Thaumaturge, Druid Magician) live on the record.
static func cantrips_for(actor: Dictionary, level: int) -> int:
	var known: int = cantrips_known(String(actor.get("class_id", "")), level)
	return known + int(actor.get("features", {}).get("bonus_cantrips", {}).get("count", 0)) if known > 0 else 0

## Spell slots per spell level (index 0 = 1st-level slots) for this class level.
static func slots(class_id: String, level: int) -> Array[int]:
	match String(entry(class_id).get("progression", "")):
		"full":
			return SpellRules.full_caster_slots(level)
		"half":
			return SpellRules.half_caster_slots(level)
		"pact":
			return SpellRules.pact_slots(level)
	return [] as Array[int]

static func highest_slot(class_id: String, level: int) -> int:
	return slots(class_id, level).size()

## Class list ids that exist in data/spells/.
static func spell_list(class_id: String) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in entry(class_id).get("list", []):
		if SpellBook.get_spell(String(value)) != null:
			result.append(String(value))
	return result

static func start_spells(class_id: String) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in entry(class_id).get("start", []):
		if SpellBook.get_spell(String(value)) != null:
			result.append(String(value))
	return result

## Spells always prepared at this level (Paladin Divine Smite); never count against the limit.
static func always_prepared(class_id: String, level: int) -> Array[String]:
	var result: Array[String] = []
	var always: Dictionary = entry(class_id).get("always", {})
	for spell_id: String in always:
		if level >= int(always[spell_id]) and SpellBook.get_spell(spell_id) != null:
			result.append(spell_id)
	return result

## Level-1+ spells of the class list that fit the highest slot of this level.
static func spell_options(class_id: String, level: int, excluded: Array) -> Array[String]:
	var result: Array[String] = []
	var highest: int = highest_slot(class_id, level)
	var always: Array[String] = always_prepared(class_id, level)
	for spell_id: String in spell_list(class_id):
		var spell: SpellDefinition = SpellBook.get_spell(spell_id)
		if not spell.is_cantrip() and spell.level <= highest and not spell_id in excluded and not spell_id in always:
			result.append(spell_id)
	return result

static func cantrip_options(class_id: String, excluded: Array) -> Array[String]:
	var result: Array[String] = []
	for spell_id: String in spell_list(class_id):
		if SpellBook.get_spell(spell_id).is_cantrip() and not spell_id in excluded:
			result.append(spell_id)
	return result

## What the caster may prepare from: the Wizard's spellbook, or the whole class list
## up to the highest slot for every other class.
static func preparable(actor: Dictionary, level: int = -1) -> Array[String]:
	var class_id: String = String(actor.get("class_id", ""))
	var at_level: int = level if level > 0 else int(actor.get("level", 1))
	if uses_spellbook(class_id):
		return ClassFeatures.spellbook(actor)
	return spell_options(class_id, at_level, [])

## Sets slots, attack bonus, save DC and the castable list of a new caster record.
static func activate(record: Dictionary) -> void:
	var class_id: String = String(record.get("class_id", ""))
	var level: int = int(record.get("level", 1))
	var spells: Array = start_spells(class_id)
	spells.append_array(always_prepared(class_id, level))
	record["spells"] = spells
	record["spell_ability"] = ability(class_id)
	record["concentration"] = {}
	refresh(record)

## Recalculates slots (new slots arrive full, spent ones stay spent), attack bonus and DC.
static func refresh(actor: Dictionary) -> void:
	var class_id: String = String(actor.get("class_id", ""))
	if not is_caster(class_id):
		return
	var level: int = int(actor.get("level", 1))
	var key: StringName = StringName(ability(class_id))
	var scores: Dictionary = actor.get("ability_scores", {})
	var score: int = int(SpellRules._lookup(scores, key, 10))
	var maximum: Array[int] = slots(class_id, level)
	var old_maximum: Array = actor.get("spell_slots_max", [])
	var current: Array = actor.get("spell_slots", []).duplicate()
	var fresh: Array = []
	for index: int in maximum.size():
		var before: int = int(old_maximum[index]) if index < old_maximum.size() else 0
		var left: int = int(current[index]) if index < current.size() else 0
		fresh.append(clampi(left + maximum[index] - before, 0, maximum[index]))
	actor["spell_slots"] = fresh
	actor["spell_slots_max"] = maximum.duplicate()
	actor["spell_ability"] = String(key)
	actor["spell_attack_modifiers"] = SpellRules.spell_attack_modifiers(key, score, level)
	actor["spell_attack_bonus"] = SpellRules.spell_attack_bonus(score, level)
	actor["spell_save_dc"] = SpellRules.spell_save_dc(score, level)
	for spell_id: String in always_prepared(class_id, level):
		if not spell_id in actor.get("spells", []):
			actor["spells"].append(spell_id)
