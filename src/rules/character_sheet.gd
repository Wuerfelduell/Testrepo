class_name CharacterSheet
extends RefCounted
## A single-class, human base sheet. Choices are explicit, never auto-selected.
## Class feature / feat / background effects are not implemented in prompt 03.

var _class: ClassDefinition = null
var _scores: Dictionary = {}
var _progression: Progression = Progression.new()
var _class_skills: Array[StringName] = []
var _human_skill: StringName = &""
var armor: StringName = &"none"
var shield: bool = false
var conditions: ConditionState = ConditionState.new()

var level: int:
	get:
		return _progression.level
var xp: int:
	get:
		return _progression.xp
var class_id: StringName:
	get:
		return _class.id
var species: StringName:
	get:
		return &"human"

static func create(definition: ClassDefinition, start_level: int, scores: Dictionary) -> CharacterSheet:
	if definition == null or start_level < 1 or start_level > 10 or not Abilities.valid_scores(scores):
		return null
	if not definition.hit_die in [6, 8, 10, 12] or definition.id == &"":
		return null
	var result: CharacterSheet = CharacterSheet.new()
	result._class = definition.duplicate(true) as ClassDefinition
	result._scores = scores.duplicate(true)
	result._progression.initialize_level(start_level)
	return result

func ability_scores() -> Dictionary:
	return _scores.duplicate()

func set_ability_score(ability: StringName, value: int) -> bool:
	if not ability in Abilities.IDS or value < 1 or value > 30:
		return false
	_scores[ability] = value
	return true

func ability_modifier(ability: StringName) -> int:
	return Abilities.modifier(_scores[ability])

func proficiency_bonus() -> int:
	return Abilities.proficiency_bonus(level)

func hit_die() -> int:
	return _class.hit_die

func maximum_hp() -> int:
	var constitution: int = ability_modifier(&"con")
	var first_level: int = _class.hit_die + constitution
	var per_level: int = maxi(1, floori(_class.hit_die / 2.0) + 1 + constitution)
	return first_level + (level - 1) * per_level

func select_class_skills(skills: Array[StringName]) -> bool:
	if not _class.valid_skill_choices(skills) or (_human_skill != &"" and _human_skill in skills):
		return false
	_class_skills = skills.duplicate()
	return true

func select_human_skill(skill: StringName) -> bool:
	if not Abilities.SKILLS.has(skill) or skill in _class_skills:
		return false
	_human_skill = skill
	return true

func skill_proficiencies() -> Array[StringName]:
	var result: Array[StringName] = _class_skills.duplicate()
	if _human_skill != &"":
		result.append(_human_skill)
	return result

func saving_throw_proficiencies() -> Array[StringName]:
	return _class.saving_throws.duplicate()

func armor_training() -> Array[StringName]:
	return _class.armor_training.duplicate()

func weapon_proficiencies() -> Array[StringName]:
	return _class.weapon_proficiencies.duplicate()

func skill_bonus(skill: StringName) -> int:
	if not Abilities.SKILLS.has(skill):
		return 0
	return ability_modifier(Abilities.SKILLS[skill]) + (proficiency_bonus() if skill in skill_proficiencies() else 0)

func saving_throw_bonus(ability: StringName) -> int:
	return ability_modifier(ability) + (proficiency_bonus() if ability in _class.saving_throws else 0)

func passive_perception() -> int:
	return 10 + skill_bonus(&"perception")

func equip(armor_id: StringName, use_shield: bool = false) -> bool:
	if not ArmorRules.ARMOR.has(armor_id):
		return false
	armor = armor_id
	shield = use_shield
	return true

func armor_result() -> ArmorRules.Result:
	return ArmorRules.calculate(armor, _scores[&"dex"], _scores[&"str"], _class.armor_training, shield)

func armor_class() -> int:
	return armor_result().armor_class

func speed_m() -> float:
	if conditions.speed_is_zero():
		return 0.0
	return maxf(0.0, 9.0 - armor_result().speed_penalty_m)

func context_for(ability: StringName, skill: StringName = &"", fear_visible: bool = false,
		requires_sight: bool = false) -> RollContext:
	var result: RollContext = RollContext.new()
	result.conditions = conditions
	result.fear_source_visible = fear_visible
	result.requires_sight = requires_sight
	var equipped: ArmorRules.Result = armor_result()
	if ability in [&"str", &"dex"] and equipped.strength_dexterity_disadvantage:
		result.disadvantages.append(&"untrained_armor")
	if ability == &"dex" and skill == &"stealth" and equipped.stealth_disadvantage:
		result.disadvantages.append(&"armor_stealth")
	return result

func features() -> Array[Dictionary]:
	return _class.features_through_level(level)

func pending_choices() -> Array[StringName]:
	var result: Array[StringName] = [&"human_size", &"human_origin_feat"]
	if _class_skills.is_empty():
		result.append(&"class_skills")
	if _human_skill == &"":
		result.append(&"human_skill")
	if _class.tool_choice_count > 0:
		result.append(&"class_tools")
	return result

func grant_xp(amount: int, reason: String) -> Progression.Award:
	return _progression.grant_xp(amount, reason)

func xp_history() -> Array[Dictionary]:
	return _progression.history()
