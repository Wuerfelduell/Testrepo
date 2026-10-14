extends GutTest
## Barbarian, Monk and Ranger kits (src/rules/classes/) and the ClassKits plumbing.

class Setup extends Command:
	var fixture: GameState
	func _init(value: GameState) -> void:
		fixture = value
	func validate(_state: GameState) -> Error:
		return OK
	func apply(state: GameState) -> Dictionary:
		state.actors = fixture.actors.duplicate(true)
		state.pending = fixture.pending.duplicate(true)
		state.turn_order = fixture.turn_order.duplicate()
		state.turn_index = fixture.turn_index
		state.round_number = fixture.round_number
		state.mode = fixture.mode
		return {}

func enemy(position: Vector3, hp: int = 200) -> Dictionary:
	return {"team": "enemy", "position": position, "hp": hp, "max_hp": hp, "ac": 5, "dex": 10,
		"speed_m": 9.0, "move_left": 9.0, "action_available": true, "bonus_available": true,
		"reaction_available": true, "disengaged": false, "conditions": [], "effects": [],
		"ability_scores": {&"str": 10, &"dex": 10, &"con": 1, &"int": 10, &"wis": 10, &"cha": 10},
		"weapon": {"ranged": false, "reach": 1.5, "attack_bonus": 40, "damage_dice": "1d4",
			"damage_bonus": 10, "damage_type": "slashing"}}

func start(hero: Dictionary, others: Dictionary = {}, hero_first: bool = true) -> void:
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = {"hero": hero, "enemy": enemy(Vector3(1, 0, 0))}
	for id: String in others:
		state.actors[id] = others[id]
	state.turn_order.assign(["hero", "enemy"] if hero_first else ["enemy", "hero"])
	CommandBus.submit(Setup.new(state))
	Rng.set_seed(91)

## A created hero with its starting gear, as the arena builds it.
func hero(class_id: String, level: int = 1) -> Dictionary:
	var record: Dictionary = HeroKit.create(StringName(class_id), Vector3.ZERO)
	var definition: ClassDefinition = load("res://data/classes/%s.tres" % class_id) as ClassDefinition
	assert_true(EquipmentRules.initialize(record, class_id, EquipmentRules.Training.for_actor(record, definition)))
	while int(record["level"]) < level:
		record["xp"] = 999999
		var plan: Dictionary = ProgressionRules.plan(record)
		var choices: Dictionary = {"hp": "average"}
		if bool(plan["asi"]):
			choices["feat"] = "ability_score_improvement"
			choices["ability_increases"] = {String(HeroFactory.priority(class_id)[0]): 2}
		if not plan["class_choices"].is_empty():
			choices["class_choices"] = {}
			for choice: Dictionary in plan["class_choices"]:
				choices["class_choices"][String(choice["key"])] = choice["options"].slice(0, int(choice["count"]))
		if int(plan["cantrip_count"]) > 0:
			choices["cantrips"] = plan["cantrip_options"].slice(0, int(plan["cantrip_count"]))
		record["xp"] = 999999
		assert_eq(ProgressionRules.validate(record, choices), "", "level %d choices" % (int(record["level"]) + 1))
		ProgressionRules.apply(record, "hero", choices, Rng.rng)
	return record

func before_each() -> void:
	CombatSpace.active = null

func after_each() -> void:
	CommandBus.submit(Setup.new(GameState.new()))

# --- Registry and creation -----------------------------------------------------------

func test_the_three_classes_are_playable_through_their_kits() -> void:
	for class_id: String in ["barbarian", "monk", "ranger"]:
		assert_true(HeroFactory.is_playable(class_id), class_id)
		assert_true(ClassFeatures.is_active(class_id), class_id)
		assert_false(HeroFactory.summary(class_id).is_empty(), class_id)

func test_barbarian_starts_unarmored_with_greataxe_and_two_rages() -> void:
	var barbarian: Dictionary = hero("barbarian")
	assert_eq(barbarian["max_hp"], 14, "d12 + Con 2")
	assert_eq(barbarian["ac"], 13, "10 + Dex 1 + Con 2")
	assert_eq(barbarian["weapon"]["id"], "greataxe")
	assert_eq(barbarian["weapon"]["damage_dice"], "1d12")
	assert_eq(barbarian["features"]["rage"]["uses"], 2)
	assert_eq(barbarian["features"]["weapon_mastery"]["weapons"], ["greataxe", "handaxe"])
	assert_eq(HeroFactory.summary("barbarian")["ac"], 13, "creation shows Unarmored Defense")

func test_monk_uses_dexterity_and_martial_arts_with_the_spear() -> void:
	var monk: Dictionary = hero("monk")
	assert_eq(monk["ac"], 14, "10 + Dex 2 + Wis 2")
	assert_eq(monk["weapon"]["id"], "spear")
	assert_eq(monk["weapon"]["attack_modifiers"][0]["source"], "dex")
	assert_eq(monk["weapon"]["attack_bonus"], 4, "Dex 2 + proficiency 2")
	assert_true(bool(monk["weapon"]["monk_weapon"]))

func test_monk_gets_light_martial_weapons_and_the_bigger_die_later() -> void:
	var monk: Dictionary = hero("monk", 5)
	EquipmentRules.add_item(monk, "shortsword")
	var definition: ClassDefinition = load("res://data/classes/monk.tres") as ClassDefinition
	EquipmentRules.equip(monk, "shortsword", EquipmentRules.Training.for_actor(monk, definition))
	assert_true(bool(monk["weapon"]["proficient"]), "Light Martial weapons are Monk weapons")
	assert_eq(monk["weapon"]["damage_dice"], "1d8", "Martial Arts d8 at level 5 replaces the d6")
	assert_eq(monk["features"]["focus"]["max"], 5)
	assert_eq(monk["speed_m"], 12.0, "Unarmored Movement +3 m")

func test_ranger_is_a_half_caster_with_hunters_mark_always_prepared() -> void:
	var ranger: Dictionary = hero("ranger")
	assert_eq(ranger["ac"], 14, "studded leather 12 + Dex 2")
	assert_eq(ranger["weapon"]["id"], "longbow")
	assert_eq(ranger["spell_slots"], [2])
	assert_true("hunters_mark" in ranger["spells"])
	assert_eq(ranger["features"]["favored_enemy"]["uses"], 2)
	assert_eq(ranger["spell_save_dc"], 12, "8 + Wis 2 + proficiency 2")

func test_all_three_level_to_ten_with_valid_choices() -> void:
	for class_id: String in ["barbarian", "monk", "ranger"]:
		var record: Dictionary = hero(class_id, 10)
		assert_eq(record["level"], 10, class_id)
		assert_eq(record["features"]["extra_attack"]["attacks"], 2, class_id)
	var barbarian: Dictionary = hero("barbarian", 10)
	assert_eq(barbarian["features"]["weapon_mastery"]["weapons"].size(), 4)
	assert_eq(barbarian["features"]["rage"]["max"], 4)
	assert_eq(barbarian["features"]["rage"]["damage"], 3)
	assert_eq(barbarian["skill_proficiencies"].size(), 4, "Primal Knowledge added one skill")
	var ranger: Dictionary = hero("ranger", 10)
	assert_eq(ranger["skill_expertise"].size(), 3, "Deft Explorer 1 + Expertise 2")
	assert_eq(ranger["features"]["fighting_style"], "archery")
	assert_eq(ranger["spell_slots_max"], [4, 3, 2])
	assert_eq(ranger["weapon"]["attack_modifiers"][-1]["source"], "archery")

# --- Barbarian in combat -------------------------------------------------------------

func test_rage_resists_weapons_and_adds_damage() -> void:
	start(hero("barbarian"))
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "rage")), OK)
	var barbarian: Dictionary = Game.state.actors["hero"]
	assert_false(bool(barbarian["bonus_available"]))
	assert_eq(barbarian["features"]["rage"]["uses"], 1)
	assert_true("slashing" in CombatRules.defenses_for(barbarian).resistances)
	assert_eq(ClassKits.damage_bonus(Game.state, "hero", "enemy", barbarian["weapon"])[0].amount, 2)
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "rage")), ERR_UNAVAILABLE)

func test_rage_ends_after_a_turn_without_attacking() -> void:
	start(hero("barbarian"))
	CommandBus.submit(UseFeatureCommand.new("hero", "rage"))
	CommandBus.submit(EndTurnCommand.new("hero"))
	assert_true(load("res://src/rules/classes/barbarian_kit.gd").raging(Game.state.actors["hero"]), "the turn it starts counts")
	CommandBus.submit(EndTurnCommand.new("enemy"))
	CommandBus.submit(EndTurnCommand.new("hero"))
	assert_false(load("res://src/rules/classes/barbarian_kit.gd").raging(Game.state.actors["hero"]), "no attack on the next turn ends it")

func test_reckless_attack_gives_advantage_both_ways() -> void:
	start(hero("barbarian"))
	assert_ne(CommandBus.submit(UseFeatureCommand.new("hero", "reckless_attack")), OK, "level 2 feature")
	var barbarian: Dictionary = hero("barbarian", 2)
	start(barbarian)
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "reckless_attack")), OK)
	var own: Dictionary = CombatRules.attack_preview(Game.state, "hero", "enemy")
	assert_true(&"reckless_attack" in own["advantages"])
	var incoming: Dictionary = CombatRules.attack_preview(Game.state, "enemy", "hero")
	assert_true(&"reckless_attack" in incoming["advantages"])

func test_danger_sense_gives_advantage_on_dexterity_saves() -> void:
	var barbarian: Dictionary = hero("barbarian", 2)
	assert_eq(ClassKits.save_advantages(barbarian, &"dex"), [&"danger_sense"])
	assert_eq(ClassKits.save_advantages(barbarian, &"wis"), [])

func test_rage_recharges_one_use_on_a_short_rest() -> void:
	var barbarian: Dictionary = hero("barbarian")
	barbarian["features"]["rage"]["uses"] = 0
	ClassKits.recharge(barbarian, "short")
	assert_eq(barbarian["features"]["rage"]["uses"], 1)
	ClassKits.recharge(barbarian, "long")
	assert_eq(barbarian["features"]["rage"]["uses"], 2)

func test_cleave_swings_at_a_second_enemy_once_per_turn() -> void:
	var barbarian: Dictionary = hero("barbarian")
	barbarian["weapon"]["attack_modifiers"] = [{"amount": 60, "source": "str"}]
	start(barbarian, {"enemy_b": enemy(Vector3(1, 0, 1))})
	assert_eq(CommandBus.submit(AttackCommand.new("hero", "enemy")), OK)
	CommandBus.submit(AdvanceCombatCommand.new(1.0))
	assert_lt(int(Game.state.actors["enemy_b"]["hp"]), 200, "the cleave hit the second enemy")
	assert_true(bool(Game.state.actors["hero"]["cleave_used"]))

# --- Monk in combat ------------------------------------------------------------------

func test_martial_arts_and_flurry_add_attacks() -> void:
	start(hero("monk", 2))
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "flurry_of_blows")), OK)
	var monk: Dictionary = Game.state.actors["hero"]
	assert_eq(monk["attacks_left"], 2)
	assert_eq(monk["features"]["focus"]["uses"], 1)
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "martial_arts")), ERR_UNAVAILABLE, "bonus action spent")
	assert_eq(CommandBus.submit(AttackCommand.new("hero", "enemy")), OK)
	assert_eq(Game.state.actors["hero"]["attacks_left"], 2, "the Attack action keeps the flurry strikes")

func test_patient_defense_dodges() -> void:
	start(hero("monk", 2))
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "patient_defense")), OK)
	var incoming: Dictionary = CombatRules.attack_preview(Game.state, "enemy", "hero")
	assert_true(&"dodge" in incoming["disadvantages"])
	assert_true(bool(Game.state.actors["hero"]["disengaged"]))

func test_deflect_attacks_lowers_weapon_damage_with_the_reaction() -> void:
	start(hero("monk", 3))
	var state: GameState = Game.state
	var result: Dictionary = ClassKits.damage_reduction(state, "enemy", "hero",
		{"damage_type": "slashing"}, 20, Rng.rng)
	assert_between(int(result["amount"]), 6, 15, "1d10 + Dex 2 + level 3")
	assert_false(bool(state.actors["hero"]["reaction_available"]))
	assert_true(ClassKits.damage_reduction(state, "enemy", "hero", {"damage_type": "slashing"}, 20, Rng.rng).is_empty())

func test_stunning_strike_spends_focus_and_stuns_on_a_failed_save() -> void:
	var monk: Dictionary = hero("monk", 5)
	monk["weapon"]["attack_modifiers"] = [{"amount": 60, "source": "dex"}]
	start(monk)
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "stunning_strike")), OK)
	assert_eq(CommandBus.submit(AttackCommand.new("hero", "enemy")), OK)
	CommandBus.submit(AdvanceCombatCommand.new(1.0))
	var target: Dictionary = Game.state.actors["enemy"]
	assert_eq(Game.state.actors["hero"]["features"]["focus"]["uses"], 4)
	assert_true("stunned" in target["conditions"] or ActiveEffects.speed_penalty(target) > 0.0)

func test_evasion_turns_half_damage_into_none() -> void:
	assert_true(ClassKits.evades(hero("monk", 7), &"dex"))
	assert_false(ClassKits.evades(hero("monk", 6), &"dex"))

# --- Ranger --------------------------------------------------------------------------

func test_hunters_mark_is_free_with_favored_enemy_and_adds_force_damage() -> void:
	var ranger: Dictionary = hero("ranger")
	ranger["position"] = Vector3(0, 0, 0)
	start(ranger)
	assert_eq(CommandBus.submit(CastSpellCommand.new("hero", "hunters_mark", ["enemy"])), OK)
	for index: int in 4:
		CommandBus.submit(AdvanceCombatCommand.new(0.5))
	var caster: Dictionary = Game.state.actors["hero"]
	assert_eq(caster["features"]["favored_enemy"]["uses"], 1)
	assert_eq(caster["spell_slots"], [2], "no slot spent")
	assert_true(ActiveEffects.has_kind(Game.state.actors["enemy"], "hunters_mark"))
	var riders: Array = ClassKits.extra_damage_dice(Game.state, "hero", "enemy", caster["weapon"], false)
	assert_eq(riders[0]["dice"], "1d6")
	assert_eq(riders[0]["damage_type"], "force")

func test_defense_style_adds_armor_class() -> void:
	var ranger: Dictionary = hero("ranger")
	ranger["features"]["fighting_style"] = "defense"
	var definition: ClassDefinition = load("res://data/classes/ranger.tres") as ClassDefinition
	EquipmentRules.refresh_armor(ranger, EquipmentRules.Training.for_actor(ranger, definition))
	assert_eq(ranger["ac"], 15)

func test_vex_gives_advantage_on_the_next_attack() -> void:
	var ranger: Dictionary = hero("ranger")
	ranger["weapon"] = EquipmentRules.weapon_record(ranger, "shortsword", EquipmentRules.Training.for_actor(ranger,
		load("res://data/classes/ranger.tres") as ClassDefinition), true)
	ranger["features"]["weapon_mastery"]["weapons"].append("shortsword")
	ranger["weapon"]["attack_modifiers"] = [{"amount": 60, "source": "dex"}]
	start(ranger)
	CommandBus.submit(AttackCommand.new("hero", "enemy"))
	CommandBus.submit(AdvanceCombatCommand.new(1.0))
	assert_true(&"vex" in CombatRules.attack_preview(Game.state, "hero", "enemy")["advantages"])
