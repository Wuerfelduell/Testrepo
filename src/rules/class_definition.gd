class_name ClassDefinition
extends Resource
## Core class traits only; features are metadata, not active implementations.

@export var id: StringName = &""
@export var hit_die: int = 0
@export var primary_abilities: Array[StringName] = []
@export_enum("single", "and", "or") var primary_mode: String = "single"
@export var saving_throws: Array[StringName] = []
@export var armor_training: Array[StringName] = []
@export var weapon_proficiencies: Array[StringName] = []
@export var tool_proficiencies: Array[StringName] = []
@export var tool_choice_count: int = 0
@export var tool_choice_categories: Array[StringName] = []
@export var skill_choice_count: int = 0
@export var skill_choices: Array[StringName] = []
@export var features: Array[Dictionary] = []
@export var srd_page: int = 0

func features_at_level(level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for feature: Dictionary in features:
		if feature["level"] == level:
			result.append(feature.duplicate(true))
	return result

func features_through_level(level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for feature: Dictionary in features:
		if feature["level"] <= level:
			result.append(feature.duplicate(true))
	return result

func valid_skill_choices(selected: Array[StringName]) -> bool:
	if selected.size() != skill_choice_count:
		return false
	var unique: Array[StringName] = []
	for skill: StringName in selected:
		if not skill in skill_choices or skill in unique:
			return false
		unique.append(skill)
	return true
