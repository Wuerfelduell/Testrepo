extends GutTest

func test_all_srd_thresholds_below_at_and_above() -> void:
	var thresholds: Array[int] = [0,300,900,2700,6500,14000,23000,34000,48000,64000]
	for index: int in range(1, thresholds.size()):
		assert_eq(Progression.level_for_xp(thresholds[index] - 1), index)
		assert_eq(Progression.level_for_xp(thresholds[index]), index + 1)
		assert_eq(Progression.level_for_xp(thresholds[index] + 1), index + 1)
	assert_eq(Progression.level_for_xp(1000000), 10)

func test_exact_threshold_multilevel_awards_keep_reasons_and_each_gained_level() -> void:
	var progression: Progression = Progression.new()
	progression.grant_xp(299, "spared_the_prisoner")
	assert_eq(progression.level, 1)
	var exact: Progression.Award = progression.grant_xp(1, "found_the_truth")
	assert_eq(exact.previous_level, 1)
	assert_eq(exact.level, 2)
	assert_eq(exact.gained_levels, [2])
	var multi: Progression.Award = progression.grant_xp(6200, "combat_and_decision")
	assert_eq(multi.gained_levels, [3,4,5])
	assert_eq(progression.history()[0]["reason"], "spared_the_prisoner")
	assert_eq(progression.history()[1]["reason"], "found_the_truth")
	assert_eq(progression.xp, 6500)

func test_level_cap_preserves_xp_and_awards_without_extra_levels() -> void:
	var progression: Progression = Progression.new()
	progression.initialize_level(10)
	var award: Progression.Award = progression.grant_xp(21000, "resolved_the_conflict")
	assert_eq(progression.xp, 85000)
	assert_eq(progression.level, 10)
	assert_true(award.gained_levels.is_empty())
	assert_eq(award.reason, "resolved_the_conflict")

func test_invalid_awards_are_atomic_and_history_is_immutable_from_outside() -> void:
	var progression: Progression = Progression.new()
	progression.grant_xp(300, "decision")
	assert_false(progression.grant_xp(-1, "loss").is_valid())
	assert_false(progression.grant_xp(10, " ").is_valid())
	assert_false(progression.grant_xp(Progression.MAX_XP, "overflow").is_valid())
	assert_eq(progression.xp, 300)
	assert_eq(progression.history().size(), 1)
	var returned: Array[Dictionary] = progression.history()
	returned[0]["reason"] = "changed"
	assert_eq(progression.history()[0]["reason"], "decision")

func test_character_level_up_recalculates_hp_proficiency_saves_and_features() -> void:
	var fighter: ClassDefinition = load("res://data/classes/fighter.tres") as ClassDefinition
	var hero: CharacterSheet = CharacterSheet.create(fighter, 4,
		{&"str":16, &"dex":14, &"con":14, &"int":10, &"wis":10, &"cha":10})
	assert_eq(hero.maximum_hp(), 36)
	assert_eq(hero.proficiency_bonus(), 2)
	var award: Progression.Award = hero.grant_xp(3800, "negotiated_safe_passage")
	assert_eq(award.level, 5)
	assert_eq(hero.maximum_hp(), 44)
	assert_eq(hero.proficiency_bonus(), 3)
	assert_eq(hero.saving_throw_bonus(&"str"), 6)
	var ids: Array[StringName] = []
	for feature: Dictionary in hero.features():
		ids.append(feature["id"])
	assert_true(&"extra_attack" in ids)
	assert_true(&"tactical_shift" in ids)
	assert_eq(hero.xp_history()[0]["reason"], "negotiated_safe_passage")
