extends GutTest

const SCORES: Dictionary = {&"str": 16, &"dex": 14, &"con": 14, &"int": 10, &"wis": 12, &"cha": 8}
const CLASSES: Array[String] = ["barbarian", "bard", "cleric", "druid", "fighter", "monk", "paladin", "ranger", "rogue", "sorcerer", "warlock", "wizard"]

func definition(id: String) -> ClassDefinition:
	return load("res://data/classes/%s.tres" % id) as ClassDefinition

func test_all_twelve_resources_load_with_exact_hit_dice_primary_abilities_and_saves() -> void:
	# Independent SRD 5.2 core-trait table expectations, pp. 28–77.
	var expected: Array[Array] = [[12,"str","str con"], [8,"cha","dex cha"], [8,"wis","wis cha"],
		[8,"wis","int wis"], [10,"str dex","str con"], [8,"dex wis","str dex"],
		[10,"str cha","wis cha"], [10,"dex wis","str dex"], [8,"dex","dex int"],
		[6,"cha","con cha"], [8,"cha","wis cha"], [6,"int","int wis"]]
	for index: int in range(CLASSES.size()):
		var data: ClassDefinition = definition(CLASSES[index])
		assert_not_null(data, CLASSES[index])
		if data == null:
			continue
		assert_eq(data.id, StringName(CLASSES[index]))
		assert_eq(data.hit_die, expected[index][0])
		assert_eq(" ".join(data.primary_abilities), expected[index][1])
		assert_eq(" ".join(data.saving_throws), expected[index][2])
	assert_eq(definition("fighter").primary_mode, "or")
	assert_eq(definition("monk").primary_mode, "and")
	assert_eq(definition("paladin").primary_mode, "and")
	assert_eq(definition("ranger").primary_mode, "and")

func test_armor_weapon_and_tool_training_match_2024_core_traits() -> void:
	var armor: Array[String] = ["light medium shield", "light", "light medium shield", "light shield",
		"light medium heavy shield", "", "light medium heavy shield", "light medium shield", "light", "", "light", ""]
	var weapons: Array[String] = ["simple martial", "simple", "simple", "simple", "simple martial",
		"simple martial_light", "simple martial", "simple martial", "simple martial_finesse_or_light", "simple", "simple", "simple"]
	for index: int in range(CLASSES.size()):
		assert_eq(" ".join(definition(CLASSES[index]).armor_training), armor[index])
		assert_eq(" ".join(definition(CLASSES[index]).weapon_proficiencies), weapons[index])
	assert_eq(" ".join(definition("rogue").tool_proficiencies), "thieves_tools")
	assert_eq(" ".join(definition("druid").tool_proficiencies), "herbalism_kit")
	assert_eq(definition("bard").tool_choice_count, 3)
	assert_eq(definition("monk").tool_choice_count, 1)

func test_exact_class_skill_pools_and_choice_counts() -> void:
	var counts: Array[int] = [2,3,2,2,2,2,2,3,4,2,2,2]
	var pools: Array[String] = [
		"animal_handling athletics intimidation nature perception survival",
		"acrobatics animal_handling arcana athletics deception history insight intimidation investigation medicine nature perception performance persuasion religion sleight_of_hand stealth survival",
		"history insight medicine persuasion religion",
		"animal_handling arcana insight medicine nature perception religion survival",
		"acrobatics animal_handling athletics history insight intimidation persuasion perception survival",
		"acrobatics athletics history insight religion stealth",
		"athletics insight intimidation medicine persuasion religion",
		"animal_handling athletics insight investigation nature perception stealth survival",
		"acrobatics athletics deception insight intimidation investigation perception persuasion sleight_of_hand stealth",
		"arcana deception insight intimidation persuasion religion",
		"arcana deception history intimidation investigation nature religion",
		"arcana history insight investigation medicine nature religion"]
	for index: int in range(CLASSES.size()):
		var data: ClassDefinition = definition(CLASSES[index])
		assert_eq(data.skill_choice_count, counts[index])
		assert_eq(" ".join(data.skill_choices), pools[index])
		assert_true(data.valid_skill_choices(data.skill_choices.slice(0, counts[index])))
		assert_false(data.valid_skill_choices([]))

func test_complete_feature_counts_by_level_and_no_subclasses() -> void:
	# Rows count named features only, excluding all subclass rows as requested.
	var counts: Array[Array] = [[3,2,1,1,2,0,2,1,1,0], [2,2,0,1,1,0,1,1,1,1],
		[2,1,0,1,1,0,1,1,0,1], [3,2,0,1,1,0,1,1,0,0], [3,2,0,1,2,1,0,1,2,0],
		[2,3,1,2,2,1,1,1,1,2], [3,2,1,1,2,1,0,1,1,1], [3,2,0,1,1,1,0,1,1,1],
		[4,1,1,1,2,1,2,1,0,1], [2,2,0,1,1,0,1,1,0,1], [2,1,0,1,0,0,0,1,1,0],
		[3,1,0,1,1,0,0,1,0,0]]
	for index: int in range(CLASSES.size()):
		var data: ClassDefinition = definition(CLASSES[index])
		for level: int in range(1,11):
			assert_eq(data.features_at_level(level).size(), counts[index][level-1], "%s L%d" % [data.id, level])
		for feature: Dictionary in data.features:
			assert_between(feature["level"], 1, 10)
			assert_false(String(feature["name"]).to_lower().contains("subclass"))
			assert_true(String(feature["name_key"]).begins_with("FEATURE_"))
			assert_false(String(feature["name"]).is_empty())
	assert_eq(definition("cleric").features_at_level(10)[0]["name"], "Divine Intervention")
	assert_eq(definition("rogue").features_at_level(7)[1]["name"], "Reliable Talent")
	assert_eq(definition("ranger").features_at_level(10)[0]["name"], "Tireless")
	assert_eq(definition("wizard").features_at_level(5)[0]["name"], "Memorize Spell")
	assert_eq(definition("warlock").features_at_level(9)[0]["name"], "Contact Patron")

func test_hp_for_every_class_at_levels_one_and_ten() -> void:
	var expected_first: Array[int] = [14,10,10,10,12,10,12,12,10,8,10,8]
	var expected_tenth: Array[int] = [95,73,73,73,84,73,84,84,73,62,73,62]
	for index: int in range(CLASSES.size()):
		var first: CharacterSheet = CharacterSheet.create(definition(CLASSES[index]), 1, SCORES)
		var tenth: CharacterSheet = CharacterSheet.create(definition(CLASSES[index]), 10, SCORES)
		assert_eq(first.maximum_hp(), expected_first[index])
		assert_eq(tenth.maximum_hp(), expected_tenth[index])
		assert_eq(first.species, &"human")
		assert_eq(tenth.level, 10)
		assert_eq(tenth.xp, 64000)
		assert_eq(tenth.proficiency_bonus(), 4)

func test_hp_minimum_gain_and_constitution_recalculation() -> void:
	var scores: Dictionary = SCORES.duplicate()
	scores[&"con"] = 1
	var wizard: CharacterSheet = CharacterSheet.create(definition("wizard"), 10, scores)
	assert_eq(wizard.maximum_hp(), 10) # 6-5 at L1, minimum 1 at each further level
	var fighter: CharacterSheet = CharacterSheet.create(definition("fighter"), 8, SCORES)
	var before: int = fighter.maximum_hp()
	fighter.set_ability_score(&"con", 16)
	assert_eq(fighter.maximum_hp(), before + 8)

func test_class_and_human_skills_are_explicit_choices_with_no_duplicates() -> void:
	var hero: CharacterSheet = CharacterSheet.create(definition("fighter"), 5, SCORES)
	assert_true(&"class_skills" in hero.pending_choices())
	assert_true(hero.skill_proficiencies().is_empty())
	assert_false(hero.select_class_skills([&"athletics", &"athletics"]))
	assert_false(hero.select_class_skills([&"arcana", &"stealth"]))
	assert_true(hero.select_class_skills([&"athletics", &"perception"]))
	assert_false(hero.select_human_skill(&"athletics"))
	assert_true(hero.select_human_skill(&"arcana"))
	assert_false(&"class_skills" in hero.pending_choices())
	assert_false(&"human_skill" in hero.pending_choices())
	assert_eq(hero.skill_bonus(&"athletics"), 6)
	assert_eq(hero.skill_bonus(&"arcana"), 3)
	assert_eq(hero.passive_perception(), 14)
	assert_eq(hero.saving_throw_bonus(&"str"), 6)
	assert_eq(hero.saving_throw_bonus(&"wis"), 1)

func test_character_copies_input_scores_resource_and_returned_metadata() -> void:
	var scores: Dictionary = SCORES.duplicate()
	var data: ClassDefinition = definition("fighter").duplicate(true) as ClassDefinition
	var hero: CharacterSheet = CharacterSheet.create(data, 5, scores)
	scores[&"str"] = 1
	data.hit_die = 6
	assert_eq(hero.ability_modifier(&"str"), 3)
	assert_eq(hero.hit_die(), 10)
	var returned: Dictionary = hero.ability_scores()
	returned[&"str"] = 2
	var features: Array[Dictionary] = hero.features()
	features[0]["name"] = "changed"
	assert_eq(hero.ability_modifier(&"str"), 3)
	assert_ne(hero.features()[0]["name"], "changed")

func test_all_armor_formulas_shield_training_and_strength_penalties() -> void:
	var expected: Dictionary = {&"none":12, &"padded":13, &"leather":13, &"studded_leather":14,
		&"hide":14, &"chain_shirt":15, &"scale_mail":16, &"breastplate":16, &"half_plate":17,
		&"ring_mail":14, &"chain_mail":16, &"splint":17, &"plate":18}
	for id: StringName in expected:
		var result: ArmorRules.Result = ArmorRules.calculate(id, 14, 16, [&"light", &"medium", &"heavy", &"shield"], true)
		assert_eq(result.armor_class, expected[id] + 2, id)
		assert_eq(result.speed_penalty_m, 0.0)
	assert_eq(ArmorRules.calculate(&"half_plate", 20, 10, [&"medium"]).armor_class, 17)
	assert_eq(ArmorRules.calculate(&"half_plate", 8, 10, [&"medium"]).armor_class, 14)
	assert_eq(ArmorRules.calculate(&"plate", 8, 15, [&"heavy"]).armor_class, 18)
	assert_eq(ArmorRules.calculate(&"chain_mail", 10, 12, [&"heavy"]).speed_penalty_m, 3.0)
	assert_eq(ArmorRules.calculate(&"none", 14, 10, [], true).armor_class, 12)

func test_untrained_armor_disadvantage_applies_only_to_strength_dexterity_and_blocks_spells() -> void:
	var hero: CharacterSheet = CharacterSheet.create(definition("wizard"), 1, SCORES)
	assert_true(hero.equip(&"chain_mail", true))
	assert_eq(hero.armor_class(), 16)
	assert_false(hero.armor_result().can_cast_spells)
	assert_true(&"untrained_armor" in hero.context_for(&"str").disadvantages)
	assert_true(&"untrained_armor" in hero.context_for(&"dex").disadvantages)
	assert_true(hero.context_for(&"wis").disadvantages.is_empty())
	assert_true(&"armor_stealth" in hero.context_for(&"dex", &"stealth").disadvantages)
	assert_false(&"armor_stealth" in hero.context_for(&"wis", &"stealth").disadvantages)

func test_human_speed_conditions_equipment_and_invalid_character_inputs() -> void:
	var hero: CharacterSheet = CharacterSheet.create(definition("fighter"), 1, SCORES)
	assert_eq(hero.speed_m(), 9.0)
	hero.set_ability_score(&"str", 10)
	hero.equip(&"plate")
	assert_eq(hero.speed_m(), 6.0)
	hero.conditions.add(&"restrained")
	assert_eq(hero.speed_m(), 0.0)
	assert_false(hero.equip(&"unknown"))
	assert_false(hero.set_ability_score(&"str", 31))
	assert_null(CharacterSheet.create(null, 1, SCORES))
	assert_null(CharacterSheet.create(definition("fighter"), 11, SCORES))
	assert_null(CharacterSheet.create(definition("fighter"), 1, {}))
