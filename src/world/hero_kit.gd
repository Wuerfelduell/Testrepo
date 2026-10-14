class_name HeroKit
extends RefCounted
## Builds plain-data hero actor records for the arena, with active level-1 class
## features (Fighter: Second Wind, Weapon Mastery; Wizard: Spellcasting, Arcane
## Recovery). Character creation can pass its own ability scores and skills.

## Playable classes are ClassFeatures.ACTIVE_CLASSES. The tables below only hold the
## test heroes' own values; other classes use character creation's defaults.
const DEFAULT_SCORES: Dictionary = {
	&"fighter": {&"str": 16, &"dex": 14, &"con": 14, &"int": 10, &"wis": 12, &"cha": 8},
	&"wizard": {&"str": 10, &"dex": 13, &"con": 14, &"int": 15, &"wis": 12, &"cha": 8},
}
const DEFAULT_SKILLS: Dictionary = {
	&"fighter": [&"athletics", &"perception"], &"wizard": [&"arcana", &"investigation"],
}
const DEFAULT_HUMAN_SKILL: Dictionary = {&"fighter": &"arcana", &"wizard": &"perception"}
const FIGHTER_STYLE: String = "great_weapon_fighting"
## Arena auto-play personality of classes that should keep their distance.
const AUTO_PERSONALITY: Dictionary = {"wizard": "archer"}
## SRD 5.2 Wizard, level 1: three cantrips and the prepared level-1 spells (the same list
## as ClassSpellcasting "start"). The third cantrip, Poison Spray (1d12), is the owner's
## wish for a strong one (13-10-2026).
const WIZARD_CANTRIP: String = "poison_spray"
const WIZARD_SPELLS: Array[String] = ["fire_bolt", "ray_of_frost", WIZARD_CANTRIP, "magic_missile",
	"burning_hands", "shield", "sleep"]

static func create(class_id: StringName, position: Vector3 = Vector3(0, 0, 7), scores: Dictionary = {},
		class_skills: Array[StringName] = [], human_skill: StringName = &"") -> Dictionary:
	if not HeroFactory.is_playable(String(class_id)):
		return {}
	var definition: ClassDefinition = load("res://data/classes/%s.tres" % class_id) as ClassDefinition
	var chosen_scores: Dictionary = scores if not scores.is_empty() else \
		DEFAULT_SCORES.get(class_id, HeroFactory.standard_scores(String(class_id)))
	var sheet: CharacterSheet = CharacterSheet.create(definition, 1, chosen_scores)
	if sheet == null:
		return {}
	var skills: Array[StringName] = class_skills.duplicate()
	var kit_skills: Dictionary = HeroFactory.default_skills(String(class_id))
	if skills.is_empty():
		skills.assign(DEFAULT_SKILLS.get(class_id, kit_skills.get("class", [])))
	var extra_skill: StringName = human_skill if human_skill != &"" else \
		StringName(DEFAULT_HUMAN_SKILL.get(class_id, kit_skills.get("human", &"")))
	# These explicit skills do not silently activate feats or other deferred choices.
	if not sheet.select_class_skills(skills) or not sheet.select_human_skill(extra_skill):
		return {}
	if not HeroFactory.equip_starting_armor(sheet, String(class_id)):
		return {}
	var proficiency: int = sheet.proficiency_bonus()
	var weapon: Dictionary = HeroFactory._weapon(String(class_id), sheet)
	var record: Dictionary = {
		"id": "hero", "team": "hero", "name_key": "ACTOR_" + String(class_id).to_upper(),
		"position": position, "hp": sheet.maximum_hp(), "max_hp": sheet.maximum_hp(),
		"ac": sheet.armor_class(), "dex": int(sheet.ability_scores()[&"dex"]),
		"speed_m": sheet.speed_m(), "move_left": sheet.speed_m(),
		"action_available": true, "bonus_available": true, "reaction_available": true,
		"disengaged": false, "weapon": weapon, "attacks": [weapon.duplicate(true)],
		"model": default_model(String(class_id)), "model_is_provisional": true, "personality": "", "conditions": [], "effects": [],
		"class_id": String(sheet.class_id), "level": sheet.level, "species": String(sheet.species),
		"ability_scores": sheet.ability_scores(), "proficiency_bonus": proficiency,
		"save_proficiencies": sheet.saving_throw_proficiencies(),
		"skill_proficiencies": sheet.skill_proficiencies(), "passive_perception": sheet.passive_perception(),
		"armor": String(sheet.armor), "shield": sheet.shield,
		"pending_character_choices": sheet.pending_choices(), "class_features_active": false,
	}
	return activate(record)

## The test hero wears the class's first male look from character creation, never the
## old base body (package 10). Falls back to the base body only if no look exists.
static func default_model(class_id: String) -> String:
	var looks: Array[Dictionary] = HeroLooks.for_class(class_id, "male")
	return String(looks[0]["scene"]) if not looks.is_empty() else "res://assets/characters/superhero_male_fullbody/model.glb"

## Adds the active level-1 class features to any hero record (the test hero or one
## from character creation): Fighter Second Wind and Weapon Mastery, Wizard
## spellcasting and Arcane Recovery. Records of other classes are returned unchanged.
static func activate(source: Dictionary) -> Dictionary:
	var record: Dictionary = source.duplicate(true)
	var class_id: String = String(record.get("class_id", ""))
	if ClassKits.has_kit(class_id):
		return _activate_kit(record, class_id)
	if not HeroFactory.is_playable(class_id):
		return record
	if bool(record.get("class_features_active", false)) and record.has("features"):
		# Heroes saved before the Fighting Style existed still receive it.
		if class_id == "fighter" and not record["features"].has("fighting_style"):
			record["features"]["fighting_style"] = FIGHTER_STYLE
			record["pending_character_choices"] = record.get("pending_character_choices", []).filter(
				func(choice: Variant) -> bool: return String(choice) != "fighting_style")
		# Wizards saved with two cantrips receive the third one.
		if class_id == "wizard" and record.has("spells") and not WIZARD_CANTRIP in record["spells"]:
			var spells: Array = record["spells"].duplicate()
			spells.insert(mini(2, spells.size()), WIZARD_CANTRIP)
			record["spells"] = spells
			record["pending_character_choices"] = record.get("pending_character_choices", []).filter(
				func(choice: Variant) -> bool: return String(choice) != "wizard_cantrip")
		return record
	var level: int = int(record.get("level", 1))
	var definition: ClassDefinition = load("res://data/classes/%s.tres" % class_id) as ClassDefinition
	record["save_proficiencies"] = definition.saving_throws.duplicate()
	record["proficiency_bonus"] = Abilities.proficiency_bonus(level)
	record["class_features_active"] = true
	if not record.has("effects"):
		record["effects"] = []
	var choices: Array = record.get("pending_character_choices", []).duplicate()
	record["features"] = ClassFeatures.start_features(class_id, level)
	choices.append_array(ClassFeatures.start_choices(class_id))
	if ClassSpellcasting.is_caster(class_id):
		ClassSpellcasting.activate(record)
	if String(record.get("personality", "")).is_empty() and AUTO_PERSONALITY.has(class_id):
		# Only used when the arena auto-plays the hero: keep range like a caster should.
		record["personality"] = AUTO_PERSONALITY[class_id]
	record["pending_character_choices"] = choices
	return record

## Kit classes: shared level-1 setup, then the kit's own activate(record); older
## records already active get the kit's upgrade(record) instead.
static func _activate_kit(record: Dictionary, class_id: String) -> Dictionary:
	if bool(record.get("class_features_active", false)) and record.has("features"):
		ClassKits.call_kit(class_id, "upgrade", [record])
		return record
	var level: int = int(record.get("level", 1))
	var definition: ClassDefinition = load("res://data/classes/%s.tres" % class_id) as ClassDefinition
	record["save_proficiencies"] = definition.saving_throws.duplicate()
	record["proficiency_bonus"] = Abilities.proficiency_bonus(level)
	record["class_features_active"] = true
	if not record.has("effects"):
		record["effects"] = []
	record["features"] = {}
	ClassKits.call_kit(class_id, "activate", [record])
	if ClassSpellcasting.is_caster(class_id):
		ClassSpellcasting.activate(record)
	ClassFeatures.advance(record, level)
	ClassKits.call_kit(class_id, "refresh_derived", [record])
	if not EquipmentRules.has_inventory(record):
		# Records without an inventory yet: class AC formula and speed bonus right away
		# (EquipmentRules.refresh_armor/refresh_speed take over once gear is set up).
		if String(record.get("armor", "none")) in ["", "none"]:
			record["ac"] = maxi(int(record.get("ac", 10)), ClassKits.unarmored_ac(record, bool(record.get("shield", false))))
		record["speed_m"] = float(record.get("speed_m", 9.0)) + ClassKits.speed_bonus_m(record)
		record["move_left"] = record["speed_m"]
	return record

## SRD 5.2 Greatsword (martial, two-handed, 2d6 slashing, mastery Graze): the owner's
## choice for the Fighter's start, so Great Weapon Fighting works from the first swing.
static func fighter_weapon(sheet: CharacterSheet) -> Dictionary:
	var strength: int = sheet.ability_modifier(&"str")
	var proficiency: int = sheet.proficiency_bonus()
	return {
		"id": "greatsword", "item_id": "greatsword", "name_key": "ITEM_GREATSWORD", "ranged": false,
		"reach": 1.5, "range": 0.0, "long_range": 0.0,
		"attack_bonus": strength + proficiency, "damage_dice": "2d6",
		"damage_bonus": strength, "damage_type": "slashing",
		"attack_modifiers": [{"amount": strength, "source": "str"},
			{"amount": proficiency, "source": "proficiency"}],
		"damage_modifiers": [{"amount": strength, "source": "str"}],
		"mastery": "graze", "properties": ["heavy", "two_handed"], "proficient": true,
		"model": "res://assets/weapons/greatsword.glb",
	}
