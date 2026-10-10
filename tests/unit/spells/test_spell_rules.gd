extends GutTest
## Pure spell math: DCs, slots, scaling, area templates, concentration DC, saves.

func test_save_dc_and_attack_bonus_follow_srd_formula() -> void:
	# INT 16 (+3), level 1 (+2): DC 13, +5 to hit.
	assert_eq(SpellRules.spell_save_dc(16, 1), 13)
	assert_eq(SpellRules.spell_attack_bonus(16, 1), 5)
	assert_eq(SpellRules.spell_save_dc(20, 5), 8 + 5 + 3)
	assert_eq(SpellRules.spell_save_dc(8, 1), 9)

func test_full_caster_slot_table() -> void:
	assert_eq(SpellRules.full_caster_slots(1), [2])
	assert_eq(SpellRules.full_caster_slots(3), [4, 2])
	assert_eq(SpellRules.full_caster_slots(10), [4, 3, 3, 3, 2])
	assert_eq(SpellRules.full_caster_slots(11), [])

func test_slot_spending_never_goes_negative() -> void:
	var slots: Array = [2, 0]
	assert_true(SpellRules.spend_slot(slots, 1))
	assert_true(SpellRules.spend_slot(slots, 1))
	assert_false(SpellRules.spend_slot(slots, 1))
	assert_false(SpellRules.spend_slot(slots, 2))
	assert_false(SpellRules.spend_slot(slots, 3))
	assert_eq(slots, [0, 0])
	assert_eq(SpellRules.lowest_slot([0, 1], 1), 2)
	assert_eq(SpellRules.lowest_slot([0, 0], 1), 0)

func test_cantrip_and_upcast_scaling() -> void:
	var bolt: SpellDefinition = SpellBook.get_spell("fire_bolt")
	assert_eq(SpellRules.damage_expression(bolt, 1, 0), "1d10")
	assert_eq(SpellRules.damage_expression(bolt, 5, 0), "2d10")
	assert_eq(SpellRules.damage_expression(bolt, 11, 0), "3d10")
	var hands: SpellDefinition = SpellBook.get_spell("burning_hands")
	assert_eq(SpellRules.damage_expression(hands, 1, 1), "3d6")
	assert_eq(SpellRules.damage_expression(hands, 3, 2), "4d6")
	var missile: SpellDefinition = SpellBook.get_spell("magic_missile")
	assert_eq(SpellRules.dart_count(missile, 1), 3)
	assert_eq(SpellRules.dart_count(missile, 2), 4)

func test_all_six_spells_load_as_valid_srd_data() -> void:
	for id: String in HeroKit.WIZARD_SPELLS:
		var spell: SpellDefinition = SpellBook.get_spell(id)
		assert_not_null(spell, id)
		assert_true(spell.is_valid(), id)
	assert_eq(SpellBook.get_spell("shield").casting_time, "reaction")
	assert_true(SpellBook.get_spell("sleep").concentration)
	assert_null(SpellBook.get_spell("../classes/wizard"))
	assert_null(SpellBook.get_spell("wish"))

func test_cone_contains_only_points_inside_its_widening_width() -> void:
	var origin: Vector3 = Vector3.ZERO
	var forward: Vector3 = Vector3(0, 0, -1)
	assert_true(SpellRules.in_cone(origin, forward, 4.5, Vector3(0, 0, -3)))
	# Width equals distance: at 4 m the half width is 2 m (+ body tolerance).
	assert_true(SpellRules.in_cone(origin, forward, 4.5, Vector3(2.1, 0, -4)))
	assert_false(SpellRules.in_cone(origin, forward, 4.5, Vector3(2.6, 0, -4)))
	assert_false(SpellRules.in_cone(origin, forward, 4.5, Vector3(0, 0, -5.2)))
	assert_false(SpellRules.in_cone(origin, forward, 4.5, Vector3(0, 0, 2)), "behind the caster")
	assert_false(SpellRules.in_cone(origin, forward, 4.5, Vector3(1.0, 0, -0.5)), "beside the caster")
	assert_false(SpellRules.in_cone(origin, forward, 4.5, Vector3(0, 3, -2)), "far above the cone")

func test_sphere_and_line_templates() -> void:
	assert_true(SpellRules.in_sphere(Vector3(5, 0, 0), 1.5, Vector3(6.5, 0, 0)))
	assert_false(SpellRules.in_sphere(Vector3(5, 0, 0), 1.5, Vector3(7.0, 0, 0)))
	assert_true(SpellRules.in_line(Vector3.ZERO, Vector3.RIGHT, 9.0, 1.5, Vector3(8, 0, 0.9)))
	assert_false(SpellRules.in_line(Vector3.ZERO, Vector3.RIGHT, 9.0, 1.5, Vector3(8, 0, 1.2)))

func test_concentration_dc_is_ten_or_half_damage_capped_at_thirty() -> void:
	assert_eq(SpellRules.concentration_dc(1), 10)
	assert_eq(SpellRules.concentration_dc(21), 10)
	assert_eq(SpellRules.concentration_dc(22), 11)
	assert_eq(SpellRules.concentration_dc(100), 30)

func test_save_modifiers_for_heroes_and_stat_blocks() -> void:
	var wizard: Dictionary = HeroKit.create(&"wizard")
	assert_eq(SpellRules.save_bonus(wizard, &"int"), 4, "INT 15 +2, proficient +2")
	assert_eq(SpellRules.save_bonus(wizard, &"dex"), 1)
	var cultist: Dictionary = (load("res://data/monsters/cultist.tres") as MonsterDefinition).create_actor("c", Vector3.ZERO)
	assert_eq(SpellRules.save_bonus(cultist, &"wis"), 2)
	assert_eq(SpellRules.save_bonus(cultist, &"dex"), 1)

func test_unconscious_creatures_fail_dex_saves_without_rng() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4
	var before: int = rng.state
	var target: Dictionary = {"ability_scores": {&"dex": 20}, "conditions": ["unconscious"]}
	var save: Dictionary = SpellRules.roll_save(target, &"dex", 5, rng)
	assert_false(bool(save["success"]))
	assert_true(bool(save["automatic"]))
	assert_eq(rng.state, before)

func test_save_success_chance() -> void:
	assert_almost_eq(SpellRules.save_success_chance(2, 13), 0.5, 0.001)
	assert_almost_eq(SpellRules.save_success_chance(0, 25), 0.0, 0.001)
	assert_almost_eq(SpellRules.save_success_chance(2, 13, 1), 0.75, 0.001)
