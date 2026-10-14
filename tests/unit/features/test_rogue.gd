extends GutTest
## Rogue (SRD 5.2, levels 1-10, no subclass): creation, starting kit, Sneak Attack,
## Cunning Action, Hide, Steady Aim, Cunning Strike, Uncanny Dodge, Evasion,
## Reliable Talent, Vex and level-up with Expertise.

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

## Three-quarters cover between everyone.
class CoverSpace extends CombatSpace:
	func cover(_from: Vector3, _to: Vector3) -> int:
		return 5

const Kit: Script = preload("res://src/rules/classes/rogue_kit.gd")

func enemy(position: Vector3, hp: int = 60) -> Dictionary:
	return {"team": "enemy", "position": position, "hp": hp, "max_hp": hp, "ac": 5, "dex": 10,
		"speed_m": 9.0, "move_left": 9.0, "action_available": true, "bonus_available": true,
		"reaction_available": true, "disengaged": false, "conditions": [], "effects": [],
		"ability_scores": {&"str": 10, &"dex": 10, &"con": 10, &"int": 10, &"wis": 10, &"cha": 10},
		"weapon": {"ranged": false, "reach": 1.5, "attack_bonus": 4, "damage_dice": "1d4",
			"damage_bonus": 0, "damage_type": "slashing"}}

func rogue(level: int = 1, position: Vector3 = Vector3.ZERO) -> Dictionary:
	var record: Dictionary = HeroKit.create(&"rogue", position)
	record["level"] = level
	record["proficiency_bonus"] = Abilities.proficiency_bonus(level)
	ClassFeatures.advance(record, level)
	return record

func state_with(actors: Dictionary, order: Array[String] = ["hero", "enemy"]) -> GameState:
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = actors
	state.turn_order = order
	return state

func start(actors: Dictionary, order: Array[String] = ["hero", "enemy"]) -> void:
	CommandBus.submit(Setup.new(state_with(actors, order)))
	Rng.set_seed(77)

func hit(mode: String = "normal", disadvantage: bool = false, critical: bool = false) -> Dictionary:
	return {"roll": {"mode": mode, "disadvantage_sources": ["sap"] if disadvantage else [], "groups": [],
		"modifiers": [], "total": 15}, "armor_class": 5, "hit": true, "critical": critical, "cover": 0}

func rng(seed_value: int = 5) -> RandomNumberGenerator:
	var result: RandomNumberGenerator = RandomNumberGenerator.new()
	result.seed = seed_value
	return result

func sneak_rolls(events: Array[Dictionary]) -> Array[Dictionary]:
	return events.filter(func(event: Dictionary) -> bool:
		return event.get("type") == "roll" and String(event.get("feature_id", "")) == "sneak_attack")

func before_each() -> void:
	CombatSpace.active = null

func after_each() -> void:
	CombatSpace.active = null
	CommandBus.submit(Setup.new(GameState.new()))

func test_rogue_is_a_playable_class_with_level_one_features() -> void:
	assert_true(HeroFactory.is_playable("rogue"))
	assert_true(ClassKits.has_kit("rogue"))
	var record: Dictionary = HeroKit.create(&"rogue")
	assert_eq(record["class_id"], "rogue")
	assert_eq(record["hp"], 10, "d8 + Con 2")
	assert_eq(record["ac"], 13, "leather 11 + Dex 2")
	assert_eq(record["weapon"]["item_id"], "dagger")
	assert_eq(record["weapon"]["attack_bonus"], 4, "finesse uses Dex 2 + proficiency 2")
	assert_eq(record["features"]["sneak_attack"]["dice"], 1)
	assert_true(record["features"].has("weapon_mastery"))
	assert_false(record["features"].has("cunning_action"), "Cunning Action comes at level 2")
	assert_eq(record["skill_expertise"], ["stealth", "perception"])
	assert_eq(record["passive_perception"], 15, "10 + Wis 1 + proficiency 2 + expertise 2")
	assert_eq(record["save_proficiencies"], [&"dex", &"int"])

func test_character_creation_builds_a_rogue_record() -> void:
	var looks: Array[Dictionary] = HeroLooks.for_class("rogue", "female")
	assert_eq(looks.size(), 1)
	assert_eq(looks[0]["id"], "rogue_hood", "the rogue's own look, not the fallback body")
	var built: Dictionary = HeroFactory.build_record("rogue", looks[0], "Seren")
	assert_true(HeroFactory.valid_record(built))
	var record: Dictionary = HeroKit.activate(built)
	assert_eq(record["ac"], 13)
	assert_eq(int(record["ability_scores"][&"dex"]), 15)
	assert_eq(record["skill_proficiencies"].size(), 5, "four class skills and the human skill")
	assert_eq(HeroFactory.summary("rogue")["main_ability"], &"dex")

func test_starting_kit_is_two_daggers_shortbow_and_leather() -> void:
	var record: Dictionary = HeroKit.create(&"rogue")
	var training: EquipmentRules.Training = InventoryCommand.training_for(record)
	assert_true(EquipmentRules.initialize(record, "rogue", training))
	assert_eq(record["equipment"]["main_hand"], "dagger")
	assert_eq(record["equipment"]["off_hand"], "dagger", "the second dagger in the off hand")
	assert_eq(record["equipment"]["armor"], "leather")
	assert_eq(record["off_hand_weapon"]["item_id"], "dagger")
	assert_eq(EquipmentRules.count(record, "shortbow"), 1)
	assert_eq(record["ac"], 13)
	EquipmentRules.equip(record, "shortbow", training)
	assert_true(bool(record["weapon"]["proficient"]))
	assert_eq(record["weapon"]["mastery"], "vex")

func test_rogue_weapon_training_covers_martial_finesse_and_light_weapons() -> void:
	var record: Dictionary = rogue(1)
	var training: EquipmentRules.Training = InventoryCommand.training_for(record)
	var scimitar: Dictionary = EquipmentRules.weapon_record(record, "scimitar", training, true)
	assert_true(bool(scimitar["proficient"]))
	assert_eq(int(scimitar["attack_bonus"]), 4, "Dex 2 + proficiency 2")
	assert_false(bool(EquipmentRules.weapon_record(record, "greatsword", training, true)["proficient"]))
	assert_true(bool(EquipmentRules.weapon_record(record, "dagger", training, true)["proficient"]))

func test_sneak_attack_dice_follow_the_rogue_table() -> void:
	assert_eq(Kit.sneak_attack_dice(1), 1)
	assert_eq(Kit.sneak_attack_dice(2), 1)
	assert_eq(Kit.sneak_attack_dice(3), 2)
	assert_eq(Kit.sneak_attack_dice(5), 3)
	assert_eq(Kit.sneak_attack_dice(10), 5)
	assert_eq(rogue(9)["features"]["sneak_attack"]["dice"], 5)

func test_sneak_attack_with_advantage_once_per_turn() -> void:
	var state: GameState = state_with({"hero": rogue(3), "enemy": enemy(Vector3(1, 0, 0))})
	var weapon: Dictionary = state.actors["hero"]["weapon"]
	var events: Array[Dictionary] = CombatRules.finish_attack(state, "hero", "enemy", weapon, hit("advantage"), rng())
	var sneak: Array[Dictionary] = sneak_rolls(events)
	assert_eq(sneak.size(), 1)
	assert_eq(sneak[0]["roll"]["groups"][0]["values"].size(), 2, "level 3: 2d6")
	assert_eq(sneak[0]["roll"]["groups"][0]["source"], "sneak_attack")
	events = CombatRules.finish_attack(state, "hero", "enemy", weapon, hit("advantage"), rng())
	assert_eq(sneak_rolls(events).size(), 0, "only once per turn")
	state.turn_index = 1
	events = CombatRules.finish_attack(state, "hero", "enemy", weapon, hit("advantage"), rng())
	assert_eq(sneak_rolls(events).size(), 1, "again on another turn (e.g. an opportunity attack)")

func test_sneak_attack_critical_doubles_the_dice() -> void:
	var state: GameState = state_with({"hero": rogue(1), "enemy": enemy(Vector3(1, 0, 0))})
	var events: Array[Dictionary] = CombatRules.finish_attack(state, "hero", "enemy", state.actors["hero"]["weapon"],
		hit("advantage", false, true), rng())
	assert_eq(sneak_rolls(events)[0]["roll"]["groups"].size(), 2, "critical: the sneak attack dice are rolled twice")

func test_sneak_attack_from_an_ally_next_to_the_target() -> void:
	var ally: Dictionary = enemy(Vector3(2, 0, 0))
	ally["team"] = "hero"
	var state: GameState = state_with({"hero": rogue(1), "enemy": enemy(Vector3(1, 0, 0)), "ally": ally})
	var weapon: Dictionary = state.actors["hero"]["weapon"]
	assert_eq(Kit._sneak_dice(state, "hero", "enemy", weapon, false, false), 1)
	assert_eq(Kit._sneak_dice(state, "hero", "enemy", weapon, false, true), 0, "not with disadvantage")
	state.actors["ally"]["conditions"] = ["incapacitated"]
	assert_eq(Kit._sneak_dice(state, "hero", "enemy", weapon, false, false), 0, "the ally must be able to act")
	state.actors["ally"]["conditions"] = []
	state.actors["ally"]["position"] = Vector3(5, 0, 0)
	assert_eq(Kit._sneak_dice(state, "hero", "enemy", weapon, false, false), 0, "the ally is too far away")

func test_sneak_attack_needs_a_finesse_or_ranged_weapon() -> void:
	var state: GameState = state_with({"hero": rogue(1), "enemy": enemy(Vector3(1, 0, 0))})
	var club: Dictionary = state.actors["hero"]["weapon"].duplicate(true)
	club["properties"] = []
	assert_eq(Kit._sneak_dice(state, "hero", "enemy", club, true, false), 0)
	club["ranged"] = true
	assert_eq(Kit._sneak_dice(state, "hero", "enemy", club, true, false), 1)
	var fighter: Dictionary = HeroKit.create(&"fighter")
	state.actors["hero"] = fighter
	assert_eq(Kit._sneak_dice(state, "hero", "enemy", fighter["weapon"], true, false), 0, "only Rogues")

func test_cunning_action_dash_and_disengage_cost_the_bonus_action() -> void:
	start({"hero": rogue(1), "enemy": enemy(Vector3(1, 0, 0))})
	assert_ne(CommandBus.submit(UseFeatureCommand.new("hero", "cunning_dash")), OK, "level 1 has no Cunning Action")
	start({"hero": rogue(2), "enemy": enemy(Vector3(1, 0, 0))})
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "cunning_dash")), OK)
	var hero: Dictionary = Game.state.actors["hero"]
	assert_eq(float(hero["move_left"]), 18.0)
	assert_false(bool(hero["bonus_available"]))
	assert_true(bool(hero["action_available"]), "the action stays free for an attack")
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "cunning_disengage")), ERR_UNAVAILABLE, "bonus action spent")
	start({"hero": rogue(2), "enemy": enemy(Vector3(1, 0, 0))})
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "cunning_disengage")), OK)
	assert_true(bool(Game.state.actors["hero"]["disengaged"]))

func test_hide_needs_cover_and_a_stealth_check() -> void:
	start({"hero": rogue(2), "enemy": enemy(Vector3(1, 0, 0))})
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "cunning_hide")), ERR_UNAVAILABLE, "in the open")
	CombatSpace.active = CoverSpace.new()
	var hidden_seed: int = -1
	for seed_value: int in range(1, 40):
		start({"hero": rogue(2), "enemy": enemy(Vector3(1, 0, 0))})
		Rng.set_seed(seed_value)
		assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "cunning_hide")), OK)
		assert_false(bool(Game.state.actors["hero"]["bonus_available"]))
		if ActiveEffects.has_kind(Game.state.actors["hero"], ActiveEffects.HIDDEN):
			hidden_seed = seed_value
			break
	assert_true(hidden_seed > 0, "Stealth +6 against DC 15 succeeds for some seed")
	var preview: Dictionary = CombatRules.attack_preview(Game.state, "hero", "enemy")
	assert_true(&"hidden" in preview["advantages"])
	var against: Dictionary = CombatRules.attack_preview(Game.state, "enemy", "hero")
	assert_true(&"target_hidden" in against["disadvantages"])
	var state: GameState = Game.state.copy()
	state.actors["enemy"]["ac"] = 30
	CombatRules.resolve_attack(state, "hero", "enemy", state.actors["hero"]["weapon"], rng())
	assert_false(ActiveEffects.has_kind(state.actors["hero"], ActiveEffects.HIDDEN), "attacking ends hiding")

func test_enemy_in_open_sight_finds_the_hidden_rogue() -> void:
	var hero: Dictionary = rogue(2)
	ActiveEffects.add(hero, {"kind": ActiveEffects.HIDDEN, "source_id": "hero"})
	var state: GameState = state_with({"hero": hero, "enemy": enemy(Vector3(4, 0, 0))})
	CombatSpace.active = CoverSpace.new()
	assert_eq(CombatRules.reveal_hidden(state).size(), 0, "still behind cover")
	CombatSpace.active = null
	var events: Array[Dictionary] = CombatRules.reveal_hidden(state)
	assert_eq(events[0]["type"], "hidden_end")
	assert_false(ActiveEffects.has_kind(state.actors["hero"], ActiveEffects.HIDDEN))

func test_steady_aim_gives_advantage_only_before_moving() -> void:
	var moved: Dictionary = rogue(3)
	moved["moved_this_turn"] = true
	start({"hero": moved, "enemy": enemy(Vector3(1, 0, 0))})
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "steady_aim")), ERR_UNAVAILABLE)
	start({"hero": rogue(3), "enemy": enemy(Vector3(1, 0, 0))})
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "steady_aim")), OK)
	var hero: Dictionary = Game.state.actors["hero"]
	assert_eq(float(hero["move_left"]), 0.0)
	assert_true(&"steady_aim" in CombatRules.attack_preview(Game.state, "hero", "enemy")["advantages"])
	assert_eq(ClassKits.expected_extra_damage(Game.state, "hero", "enemy", hero["weapon"]), 7.0,
		"advantage enables Sneak Attack (2d6) in the preview")
	var state: GameState = Game.state.copy()
	ActiveEffects.on_turn_end(state, "hero", rng())
	assert_false(ActiveEffects.has_kind(state.actors["hero"], ActiveEffects.STEADY_AIM), "ends with the turn")

## Hits until one lands (a natural 1 always misses); returns the events of that attack.
func land_hit(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> Array[Dictionary]:
	for seed_value: int in range(1, 30):
		var events: Array[Dictionary] = CombatRules.resolve_attack(state, attacker_id, target_id, weapon, rng(seed_value))
		if events.any(func(event: Dictionary) -> bool: return event.get("type") == "reaction_offer" or bool(event.get("hit", false))):
			return events
	return []

func damage_total(events: Array[Dictionary]) -> int:
	return int(events.filter(func(event: Dictionary) -> bool: return event.get("kind") == "damage")[0]["roll"]["total"])

func test_uncanny_dodge_asks_first_then_halves_and_spends_the_reaction() -> void:
	var hero: Dictionary = rogue(5)
	hero["hp"] = 40
	var state: GameState = state_with({"hero": hero, "enemy": enemy(Vector3(1, 0, 0))})
	var weapon: Dictionary = state.actors["enemy"]["weapon"].duplicate(true)
	weapon["attack_bonus"] = 30
	weapon["damage_dice"] = "2d6+9"
	var offer: Array[Dictionary] = land_hit(state, "enemy", "hero", weapon)
	assert_eq(offer[-1]["type"], "reaction_offer", "the Rogue is asked before damage")
	assert_eq(state.pending["reaction"], "uncanny_dodge")
	assert_eq(int(state.actors["hero"]["hp"]), 40, "no damage before the answer")
	var events: Array[Dictionary] = CastReactionCommand.new("hero", true).apply(state)["events"]
	assert_eq(int(state.actors["hero"]["hp"]), 40 - floori(damage_total(events) / 2.0), "damage halved")
	assert_false(bool(state.actors["hero"]["reaction_available"]))
	assert_true(events.any(func(event: Dictionary) -> bool: return event.get("feature_id") == "uncanny_dodge"))
	assert_true(state.pending.is_empty())
	var hp: int = int(state.actors["hero"]["hp"])
	events = land_hit(state, "enemy", "hero", weapon)
	assert_true(state.pending.is_empty(), "no reaction left: no question")
	assert_eq(int(state.actors["hero"]["hp"]), hp - damage_total(events), "full damage")

func test_declining_uncanny_dodge_keeps_the_reaction() -> void:
	var hero: Dictionary = rogue(5)
	hero["hp"] = 40
	var state: GameState = state_with({"hero": hero, "enemy": enemy(Vector3(1, 0, 0))})
	var weapon: Dictionary = state.actors["enemy"]["weapon"].duplicate(true)
	weapon["attack_bonus"] = 30
	land_hit(state, "enemy", "hero", weapon)
	assert_eq(CastReactionCommand.new("hero", false).validate(state), OK)
	var events: Array[Dictionary] = CastReactionCommand.new("hero", false).apply(state)["events"]
	assert_eq(int(state.actors["hero"]["hp"]), 40 - damage_total(events))
	assert_true(bool(state.actors["hero"]["reaction_available"]))
	assert_false(CastReactionCommand.auto_accept(state, "hero"), "nothing pending any more")

func armed_rogue(level: int = 1) -> Dictionary:
	var record: Dictionary = rogue(level)
	assert_true(EquipmentRules.initialize(record, "rogue", InventoryCommand.training_for(record)))
	return record

func test_off_hand_attack_after_a_light_attack_costs_the_bonus_action() -> void:
	var hero: Dictionary = armed_rogue()
	hero["features"]["weapon_mastery"]["weapons"] = ["shortbow"]
	var state: GameState = state_with({"hero": hero, "enemy": enemy(Vector3(1, 0, 0))})
	CombatRules.begin_turn(state, "hero")
	var offhand: AttackCommand = AttackCommand.new("hero", "enemy", AttackCommand.OFF_HAND)
	assert_eq(CombatRules.offhand_reason(state, "hero"), "COMBAT_OFFHAND_ATTACK_FIRST")
	assert_eq(offhand.validate(state), ERR_UNAVAILABLE)
	AttackCommand.new("hero", "enemy").apply(state)
	state.pending = {}
	assert_eq(offhand.validate(state), OK)
	var weapon: Dictionary = AttackCommand.weapon_for(state.actors["hero"], AttackCommand.OFF_HAND)
	assert_eq(int(weapon["damage_bonus"]), 0, "no Dex bonus on the off-hand damage")
	assert_true(weapon["damage_modifiers"].all(func(modifier: Dictionary) -> bool: return modifier["source"] != "dex"))
	assert_eq(int(weapon["attack_bonus"]), 4, "the attack roll keeps Dex and proficiency")
	offhand.apply(state)
	assert_false(bool(state.actors["hero"]["bonus_available"]), "a Bonus Action without Nick")
	assert_eq(state.pending["weapon"]["item_id"], "dagger")
	state.pending = {}
	assert_eq(CombatRules.offhand_reason(state, "hero"), "COMBAT_OFFHAND_USED", "once per turn")

func test_nick_makes_the_off_hand_attack_free() -> void:
	var state: GameState = state_with({"hero": armed_rogue(), "enemy": enemy(Vector3(1, 0, 0))})
	CombatRules.begin_turn(state, "hero")
	AttackCommand.new("hero", "enemy").apply(state)
	state.pending = {}
	assert_false(CombatRules.offhand_needs_bonus(state.actors["hero"]), "the Rogue masters the dagger (Nick)")
	AttackCommand.new("hero", "enemy", AttackCommand.OFF_HAND).apply(state)
	assert_true(bool(state.actors["hero"]["bonus_available"]), "Cunning Action stays free")

func test_off_hand_needs_light_weapons_in_both_hands() -> void:
	var hero: Dictionary = armed_rogue()
	var training: EquipmentRules.Training = InventoryCommand.training_for(hero)
	EquipmentRules.add_item(hero, "mace")
	EquipmentRules.equip(hero, "mace", training)
	var state: GameState = state_with({"hero": hero, "enemy": enemy(Vector3(1, 0, 0))})
	CombatRules.begin_turn(state, "hero")
	assert_eq(CombatRules.offhand_reason(state, "hero"), "COMBAT_OFFHAND_NOT_LIGHT", "the mace is not Light")
	assert_eq(EquipmentRules.equip_reason(state, "hero", "shortbow", "off_hand"), "INV_REASON_NOT_EQUIPPABLE")
	EquipmentRules.equip(hero, "shortbow", training)
	assert_eq(hero["equipment"]["off_hand"], "", "a two-handed bow frees the off hand")
	assert_false(hero.has("off_hand_weapon"))
	EquipmentRules.equip(hero, "dagger", training)
	EquipmentRules.equip(hero, "dagger", training, "off_hand")
	assert_eq(hero["equipment"]["off_hand"], "dagger")
	assert_eq(hero["equipment"]["main_hand"], "dagger")
	EquipmentRules.add_item(hero, "shield")
	EquipmentRules.equip(hero, "shield", training)
	assert_eq(hero["equipment"]["off_hand"], "shield", "a shield replaces the off-hand dagger")
	assert_false(hero.has("off_hand_weapon"))

func test_evasion_turns_dex_saves_for_half_into_none_or_half() -> void:
	assert_true(ClassKits.evades(rogue(7), &"dex"))
	assert_false(ClassKits.evades(rogue(7), &"con"))
	assert_false(ClassKits.evades(rogue(6), &"dex"))
	assert_false(ClassKits.evades(HeroKit.create(&"fighter"), &"dex"))

func test_reliable_talent_raises_low_d20_rolls_on_proficient_checks() -> void:
	var talented: Dictionary = rogue(7)
	var generator: RandomNumberGenerator = rng(3)
	for index: int in 40:
		var result: CheckResult = ClassFeatures.skill_check(talented, "acrobatics", 30, generator)
		assert_true(result.roll.groups[0].values[0] >= 10)
	var untrained: int = 99
	for index: int in 40:
		var result: CheckResult = ClassFeatures.skill_check(talented, "arcana", 30, generator)
		untrained = mini(untrained, result.roll.groups[0].values[0])
	assert_true(untrained < 10, "skills without proficiency are not raised")

func test_expertise_doubles_proficiency_on_checks() -> void:
	var record: Dictionary = rogue(1)
	var result: CheckResult = ClassFeatures.skill_check(record, "stealth", 10, rng())
	var bonus: int = result.roll.total - result.roll.groups[0].values[0]
	assert_eq(bonus, 6, "Dex 2 + proficiency 2 x 2")

func test_vex_gives_advantage_on_the_next_attack_against_the_same_target() -> void:
	var hero: Dictionary = rogue(1)
	var training: EquipmentRules.Training = InventoryCommand.training_for(hero)
	EquipmentRules.initialize(hero, "rogue", training)
	EquipmentRules.equip(hero, "shortbow", training)
	var state: GameState = state_with({"hero": hero, "enemy": enemy(Vector3(8, 0, 0)), "other": enemy(Vector3(-8, 0, 0))})
	var events: Array[Dictionary] = CombatRules.finish_attack(state, "hero", "enemy", hero["weapon"], hit(), rng())
	assert_true(events.any(func(event: Dictionary) -> bool: return event.get("kind") == "vex"))
	assert_true(&"vex" in CombatRules.attack_preview(state, "hero", "enemy")["advantages"])
	assert_false(&"vex" in CombatRules.attack_preview(state, "hero", "other")["advantages"])
	var miss: Dictionary = hit()
	miss["hit"] = false
	CombatRules.finish_attack(state, "hero", "enemy", hero["weapon"], miss, rng())
	assert_false(&"vex" in CombatRules.attack_preview(state, "hero", "enemy")["advantages"], "only the next attack")

func test_vex_lasts_until_the_end_of_the_rogues_next_turn() -> void:
	var hero: Dictionary = rogue(1)
	hero["mastery_vex"] = {"target_id": "enemy", "fresh": true}
	var state: GameState = state_with({"hero": hero, "enemy": enemy(Vector3(1, 0, 0))})
	ClassKits.on_turn_end(state, "hero", rng())
	assert_true(state.actors["hero"].has("mastery_vex"), "kept through the turn it was gained")
	ClassKits.on_turn_start(state, "hero")
	ClassKits.on_turn_end(state, "hero", rng())
	assert_false(state.actors["hero"].has("mastery_vex"))

func test_cunning_strike_cycles_and_trades_a_die_for_its_effect() -> void:
	start({"hero": rogue(5), "enemy": enemy(Vector3(1, 0, 0))})
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "cunning_strike")), OK)
	assert_eq(Game.state.actors["hero"]["features"]["cunning_strike"]["choice"], "poison")
	CommandBus.submit(UseFeatureCommand.new("hero", "cunning_strike"))
	assert_eq(Game.state.actors["hero"]["features"]["cunning_strike"]["choice"], "trip")
	var tripped: bool = false
	for seed_value: int in range(1, 30):
		var state: GameState = Game.state.copy()
		var events: Array[Dictionary] = CombatRules.finish_attack(state, "hero", "enemy",
			state.actors["hero"]["weapon"], hit("advantage"), rng(seed_value))
		assert_eq(sneak_rolls(events)[0]["roll"]["groups"][0]["values"].size(), 2, "3d6 minus 1d6 for the strike")
		if "prone" in state.actors["enemy"]["conditions"]:
			tripped = true
			CombatRules.begin_turn(state, "enemy")
			assert_false("prone" in state.actors["enemy"]["conditions"], "stands up on its turn")
			assert_eq(float(state.actors["enemy"]["move_left"]), 4.5, "standing costs half the Speed")
			break
	assert_true(tripped, "DC 13 against Dex +0 fails for some seed")
	assert_eq(Kit.strike_dc(Game.state.actors["hero"]), 13)
	CommandBus.submit(UseFeatureCommand.new("hero", "cunning_strike"))
	CommandBus.submit(UseFeatureCommand.new("hero", "cunning_strike"))
	assert_eq(Game.state.actors["hero"]["features"]["cunning_strike"]["choice"], "", "back to plain Sneak Attack")

func test_cunning_strike_poison_poisons_until_a_save_succeeds() -> void:
	var hero: Dictionary = rogue(5)
	hero["features"]["cunning_strike"]["choice"] = "poison"
	var poisoned: bool = false
	for seed_value: int in range(1, 30):
		var state: GameState = state_with({"hero": hero.duplicate(true), "enemy": enemy(Vector3(1, 0, 0))})
		CombatRules.finish_attack(state, "hero", "enemy", state.actors["hero"]["weapon"], hit("advantage"), rng(seed_value))
		if "poisoned" in state.actors["enemy"]["conditions"]:
			poisoned = true
			for turn: int in 30:
				ActiveEffects.on_turn_end(state, "enemy", rng(seed_value + turn))
			assert_false("poisoned" in state.actors["enemy"]["conditions"], "a repeated CON save ends it")
			break
	assert_true(poisoned)

func test_level_up_to_ten_with_rogue_expertise_at_six() -> void:
	var hero: Dictionary = HeroKit.create(&"rogue")
	hero["xp"] = 999999
	var generator: RandomNumberGenerator = rng()
	for level: int in range(2, 11):
		var plan: Dictionary = ProgressionRules.plan(hero)
		var choices: Dictionary = {"hp": "average"}
		if bool(plan["asi"]):
			choices["feat"] = "ability_score_improvement"
			choices["ability_increases"] = {"dex": 2} if ProgressionRules.score(hero, "dex") <= 18 else {"con": 2}
		if level == 6:
			assert_eq(plan["class_choices"].size(), 1)
			var expertise: Dictionary = plan["class_choices"][0]
			assert_eq(expertise["key"], "expertise")
			assert_eq(int(expertise["count"]), 2)
			assert_false("stealth" in expertise["options"], "already an expert")
			assert_eq(ProgressionRules.validate(hero, choices), "LEVELUP_REASON_CLASS_CHOICE")
			choices["class_choices"] = {"expertise": ["acrobatics"]}
			assert_eq(ProgressionRules.validate(hero, choices), "LEVELUP_REASON_CLASS_CHOICE", "two skills")
			choices["class_choices"] = {"expertise": ["acrobatics", "sleight_of_hand"]}
		assert_eq(ProgressionRules.validate(hero, choices), "", "level %d" % level)
		for feature: Dictionary in plan["features"]:
			assert_true(bool(feature["active"]) or feature["id"] == "thieves_cant", "%s is built" % feature["id"])
		ProgressionRules.apply(hero, "hero", choices, generator)
	assert_eq(int(hero["level"]), 10)
	assert_eq(hero["features"]["sneak_attack"]["dice"], 5)
	for feature_id: String in ["cunning_action", "steady_aim", "cunning_strike", "uncanny_dodge", "evasion", "reliable_talent"]:
		assert_true(hero["features"].has(feature_id), feature_id)
	assert_eq(hero["skill_expertise"].size(), 4)
	assert_eq(int(hero["ability_scores"][&"dex"]), 19, "two ASIs into Dex: 15 -> 17 -> 19")
	# d8: 8 + 2 at level 1, then 5 + Con per level (Con 14 -> 16 at the third ASI).
	assert_eq(int(hero["max_hp"]), ProgressionRules.maximum_hp(hero))
