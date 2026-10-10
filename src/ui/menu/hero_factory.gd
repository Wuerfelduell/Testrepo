class_name HeroFactory
extends RefCounted
## Builds the created hero for M1: SRD 5.2 standard array assigned by class priority
## (point buy comes in M2), class default skills, starting gear. Output is the same plain
## actor record SetupArenaCommand uses for its test Fighter.

const CLASS_ORDER: Array[String] = ["fighter", "wizard", "barbarian", "bard", "cleric", "druid",
	"monk", "paladin", "ranger", "rogue", "sorcerer", "warlock"]
const PLAYABLE: Array[String] = ["fighter", "wizard"]
const STANDARD_ARRAY: Array[int] = [15, 14, 13, 12, 10, 8]
const PRIORITY: Dictionary = {
	"fighter": [&"str", &"con", &"dex", &"wis", &"int", &"cha"],
	"wizard": [&"int", &"con", &"dex", &"wis", &"str", &"cha"],
}
const SKILLS: Dictionary = {
	"fighter": {"class": [&"athletics", &"perception"], "human": &"insight"},
	"wizard": {"class": [&"arcana", &"investigation"], "human": &"perception"},
}
const MAX_NAME_LENGTH: int = 24
const STAFF_MODEL: String = "res://assets/weapons/staff.glb"

static func is_playable(class_id: String) -> bool:
	return class_id in PLAYABLE

static func standard_scores(class_id: String) -> Dictionary:
	var result: Dictionary = {}
	var order: Array = PRIORITY.get(class_id, [])
	for index: int in order.size():
		result[order[index]] = STANDARD_ARRAY[index]
	return result

static func clean_name(raw: String) -> String:
	return raw.strip_edges().left(MAX_NAME_LENGTH)

static func create_sheet(class_id: String) -> CharacterSheet:
	if not is_playable(class_id):
		return null
	var definition: ClassDefinition = load("res://data/classes/%s.tres" % class_id) as ClassDefinition
	var sheet: CharacterSheet = CharacterSheet.create(definition, 1, standard_scores(class_id))
	if sheet == null:
		return null
	var class_skills: Array[StringName] = []
	class_skills.assign(SKILLS[class_id]["class"])
	if not sheet.select_class_skills(class_skills) or not sheet.select_human_skill(SKILLS[class_id]["human"]):
		return null
	var equipped: bool = sheet.equip(&"chain_mail", true) if class_id == "fighter" else sheet.equip(&"none")
	return sheet if equipped else null

## Summary for the creation screen: hp, ac, main ability, ability scores.
static func summary(class_id: String) -> Dictionary:
	var sheet: CharacterSheet = create_sheet(class_id)
	if sheet == null:
		return {}
	var main: StringName = PRIORITY[class_id][0]
	return {"hp": sheet.maximum_hp(), "ac": sheet.armor_class(), "main_ability": main,
		"scores": sheet.ability_scores(), "skills": sheet.skill_proficiencies(), "speed_m": sheet.speed_m()}

## Returns {} when the class, look or name is not valid.
static func build_record(class_id: String, look: Dictionary, hero_name: String) -> Dictionary:
	var display_name: String = clean_name(hero_name)
	var sheet: CharacterSheet = create_sheet(class_id)
	var scene: String = String(look.get("scene", ""))
	if sheet == null or display_name.is_empty() or not ResourceLoader.exists(scene):
		return {}
	var weapon: Dictionary = _weapon(class_id, sheet)
	return {
		"id": "hero", "team": "hero", "name_key": display_name, "display_name": display_name,
		"position": Vector3(0, 0, 7), "hp": sheet.maximum_hp(), "max_hp": sheet.maximum_hp(),
		"ac": sheet.armor_class(), "dex": int(sheet.ability_scores()[&"dex"]),
		"speed_m": sheet.speed_m(), "move_left": sheet.speed_m(),
		"action_available": true, "bonus_available": true, "reaction_available": true,
		"disengaged": false, "weapon": weapon, "attacks": [weapon.duplicate(true)],
		"model": scene, "model_is_provisional": true, "personality": "", "conditions": [],
		"body": String(look.get("body", "")), "look_id": String(look.get("id", "")),
		"class_id": String(sheet.class_id), "level": sheet.level, "species": String(sheet.species),
		"xp": sheet.xp, "xp_history": sheet.xp_history(),
		"ability_scores": sheet.ability_scores(), "proficiency_bonus": sheet.proficiency_bonus(),
		"skill_proficiencies": sheet.skill_proficiencies(), "passive_perception": sheet.passive_perception(),
		"armor": String(sheet.armor), "shield": sheet.shield,
		"pending_character_choices": sheet.pending_choices(), "class_features_active": false,
	}

static func valid_record(record: Dictionary) -> bool:
	for key: String in ["id", "team", "name_key", "position", "hp", "max_hp", "ac", "dex",
			"speed_m", "move_left", "weapon", "attacks", "model", "class_id", "ability_scores"]:
		if not record.has(key):
			return false
	return record["id"] == "hero" and record["team"] == "hero" and int(record["hp"]) > 0 and \
		record["position"] is Vector3 and ResourceLoader.exists(String(record["model"])) and \
		Abilities.valid_scores(record["ability_scores"])

static func _weapon(class_id: String, sheet: CharacterSheet) -> Dictionary:
	var proficiency: int = sheet.proficiency_bonus()
	var strength: int = sheet.ability_modifier(&"str")
	if class_id == "fighter":
		return {
			"id": "longsword", "name_key": "WEAPON_LONGSWORD", "ranged": false,
			"reach": 1.5, "range": 0.0, "long_range": 0.0,
			"attack_bonus": strength + proficiency, "damage_dice": "1d8",
			"damage_bonus": strength, "damage_type": "slashing",
			"attack_modifiers": [{"amount": strength, "source": "str"},
				{"amount": proficiency, "source": "proficiency"}],
			"damage_modifiers": [{"amount": strength, "source": "str"}],
			"model": "res://assets/weapons/sword.glb",
		}
	# SRD Quarterstaff (simple melee, 1d6 bludgeoning). The art package adds a staff model;
	# until it exists the Wizard fights bare-handed visually.
	var staff: Dictionary = {
		"id": "quarterstaff", "name_key": "WEAPON_QUARTERSTAFF", "ranged": false,
		"reach": 1.5, "range": 0.0, "long_range": 0.0,
		"attack_bonus": strength + proficiency, "damage_dice": "1d6",
		"damage_bonus": strength, "damage_type": "bludgeoning",
		"attack_modifiers": [{"amount": strength, "source": "str"},
			{"amount": proficiency, "source": "proficiency"}],
		"damage_modifiers": [{"amount": strength, "source": "str"}],
	}
	if ResourceLoader.exists(STAFF_MODEL):
		staff["model"] = STAFF_MODEL
	return staff
