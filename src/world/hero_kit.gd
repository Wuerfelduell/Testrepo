class_name HeroKit
extends RefCounted
## Builds plain-data hero actor records for the arena, with active level-1 class
## features (Fighter: Second Wind, Weapon Mastery; Wizard: Spellcasting, Arcane
## Recovery). Character creation can pass its own ability scores and skills.

const CLASSES: Array[StringName] = [&"fighter", &"wizard"]
const DEFAULT_SCORES: Dictionary = {
	&"fighter": {&"str": 16, &"dex": 14, &"con": 14, &"int": 10, &"wis": 12, &"cha": 8},
	&"wizard": {&"str": 10, &"dex": 13, &"con": 14, &"int": 15, &"wis": 12, &"cha": 8},
}
const DEFAULT_SKILLS: Dictionary = {
	&"fighter": [&"athletics", &"perception"], &"wizard": [&"arcana", &"investigation"],
}
const DEFAULT_HUMAN_SKILL: Dictionary = {&"fighter": &"arcana", &"wizard": &"perception"}
## SRD 5.2 Wizard, level 1: cantrips and prepared level-1 spells for the first slice.
const WIZARD_SPELLS: Array[String] = ["fire_bolt", "ray_of_frost", "magic_missile", "burning_hands", "shield", "sleep"]

static func create(class_id: StringName, position: Vector3 = Vector3(0, 0, 7), scores: Dictionary = {},
		class_skills: Array[StringName] = [], human_skill: StringName = &"") -> Dictionary:
	if not class_id in CLASSES:
		return {}
	var definition: ClassDefinition = load("res://data/classes/%s.tres" % class_id) as ClassDefinition
	var chosen_scores: Dictionary = scores if not scores.is_empty() else DEFAULT_SCORES[class_id]
	var sheet: CharacterSheet = CharacterSheet.create(definition, 1, chosen_scores)
	if sheet == null:
		return {}
	var skills: Array[StringName] = class_skills.duplicate()
	if skills.is_empty():
		skills.assign(DEFAULT_SKILLS[class_id])
	var extra_skill: StringName = human_skill if human_skill != &"" else DEFAULT_HUMAN_SKILL[class_id]
	# These explicit skills do not silently activate feats or other deferred choices.
	if not sheet.select_class_skills(skills) or not sheet.select_human_skill(extra_skill):
		return {}
	if class_id == &"fighter" and not sheet.equip(&"chain_mail", true):
		return {}
	var proficiency: int = sheet.proficiency_bonus()
	var weapon: Dictionary = _fighter_longsword(sheet) if class_id == &"fighter" else HeroFactory._weapon("wizard", sheet)
	var record: Dictionary = {
		"id": "hero", "team": "hero", "name_key": "ACTOR_" + String(class_id).to_upper(),
		"position": position, "hp": sheet.maximum_hp(), "max_hp": sheet.maximum_hp(),
		"ac": sheet.armor_class(), "dex": int(sheet.ability_scores()[&"dex"]),
		"speed_m": sheet.speed_m(), "move_left": sheet.speed_m(),
		"action_available": true, "bonus_available": true, "reaction_available": true,
		"disengaged": false, "weapon": weapon, "attacks": [weapon.duplicate(true)],
		"model": "res://assets/characters/superhero_male_fullbody/model.glb",
		"model_is_provisional": true, "personality": "", "conditions": [], "effects": [],
		"class_id": String(sheet.class_id), "level": sheet.level, "species": String(sheet.species),
		"ability_scores": sheet.ability_scores(), "proficiency_bonus": proficiency,
		"save_proficiencies": sheet.saving_throw_proficiencies(),
		"skill_proficiencies": sheet.skill_proficiencies(), "passive_perception": sheet.passive_perception(),
		"armor": String(sheet.armor), "shield": sheet.shield,
		"pending_character_choices": sheet.pending_choices(), "class_features_active": false,
	}
	return activate(record)

## Adds the active level-1 class features to any hero record (the test hero or one
## from character creation): Fighter Second Wind and Weapon Mastery, Wizard
## spellcasting and Arcane Recovery. Records of other classes are returned unchanged.
static func activate(source: Dictionary) -> Dictionary:
	var record: Dictionary = source.duplicate(true)
	var class_id: String = String(record.get("class_id", ""))
	if not StringName(class_id) in CLASSES or (bool(record.get("class_features_active", false)) and record.has("features")):
		return record
	var level: int = int(record.get("level", 1))
	var definition: ClassDefinition = load("res://data/classes/%s.tres" % class_id) as ClassDefinition
	record["save_proficiencies"] = definition.saving_throws.duplicate()
	record["proficiency_bonus"] = Abilities.proficiency_bonus(level)
	record["class_features_active"] = true
	if not record.has("effects"):
		record["effects"] = []
	var choices: Array = record.get("pending_character_choices", []).duplicate()
	if class_id == "fighter":
		var uses: int = SpellRules.second_wind_uses(level)
		record["features"] = {"second_wind": {"uses": uses, "max": uses},
			"weapon_mastery": {"weapons": ["longsword"]}}
		# Fighting Style (a feat) and the other two mastery weapons wait for the owner.
		choices.append(&"fighting_style")
		choices.append(&"weapon_mastery_kinds")
	else:
		var intelligence: int = int(SpellRules._lookup(record.get("ability_scores", {}), &"int", 10))
		var slots: Array[int] = SpellRules.full_caster_slots(level)
		record["features"] = {"arcane_recovery": {"used": false}}
		record["spells"] = WIZARD_SPELLS.duplicate()
		record["spell_ability"] = "int"
		record["spell_slots"] = slots.duplicate()
		record["spell_slots_max"] = slots.duplicate()
		record["spell_attack_modifiers"] = SpellRules.spell_attack_modifiers(&"int", intelligence, level)
		record["spell_attack_bonus"] = SpellRules.spell_attack_bonus(intelligence, level)
		record["spell_save_dc"] = SpellRules.spell_save_dc(intelligence, level)
		record["concentration"] = {}
		if String(record.get("personality", "")).is_empty():
			# Only used when the arena auto-plays the hero: keep range like a caster should.
			record["personality"] = "archer"
		# SRD 5.2 Wizards know three cantrips at level 1; the third is a creation choice.
		choices.append(&"wizard_cantrip")
	record["pending_character_choices"] = choices
	return record

static func _fighter_longsword(sheet: CharacterSheet) -> Dictionary:
	var strength: int = sheet.ability_modifier(&"str")
	var proficiency: int = sheet.proficiency_bonus()
	return {
		"id": "longsword", "name_key": "WEAPON_LONGSWORD", "ranged": false,
		"reach": 1.5, "range": 0.0, "long_range": 0.0,
		"attack_bonus": strength + proficiency, "damage_dice": "1d8",
		"damage_bonus": strength, "damage_type": "slashing",
		"attack_modifiers": [{"amount": strength, "source": "str"},
			{"amount": proficiency, "source": "proficiency"}],
		"damage_modifiers": [{"amount": strength, "source": "str"}],
		"mastery": "sap", "model": "res://assets/weapons/sword.glb",
	}
