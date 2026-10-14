extends GutTest
## Ranger spells with module code (src/rules/spells/ranger_spells.gd) and Conjure Barrage.

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

## Changes the live state (Game.state hands out copies).
class Mutate extends Command:
	var change: Callable
	func _init(value: Callable) -> void:
		change = value
	func validate(_state: GameState) -> Error:
		return OK
	func apply(state: GameState) -> Dictionary:
		change.call(state)
		return {}

const RANGER_SPELLS: Array[String] = ["ensnaring_strike", "hail_of_thorns", "lightning_arrow", "conjure_barrage",
	"longstrider", "jump", "lesser_restoration", "protection_from_poison", "protection_from_energy", "goodberry",
	"spike_growth", "conjure_animals", "fog_cloud", "pass_without_trace"]

func enemy(position: Vector3, hp: int = 200) -> Dictionary:
	return {"team": "enemy", "position": position, "hp": hp, "max_hp": hp, "ac": 5, "dex": 1,
		"speed_m": 9.0, "move_left": 9.0, "action_available": true, "bonus_available": true,
		"reaction_available": true, "disengaged": false, "conditions": [], "effects": [],
		"ability_scores": {&"str": 1, &"dex": 1, &"con": 10, &"int": 10, &"wis": 10, &"cha": 10},
		"weapon": {"ranged": false, "reach": 1.5, "attack_bonus": 0, "damage_dice": "1d4",
			"damage_bonus": 0, "damage_type": "slashing"}}

## A created and levelled Ranger who knows every spell of this file.
func ranger(level: int = 1) -> Dictionary:
	var record: Dictionary = HeroKit.create(&"ranger", Vector3.ZERO)
	var definition: ClassDefinition = load("res://data/classes/ranger.tres") as ClassDefinition
	assert_true(EquipmentRules.initialize(record, "ranger", EquipmentRules.Training.for_actor(record, definition)))
	while int(record["level"]) < level:
		record["xp"] = 999999
		var plan: Dictionary = ProgressionRules.plan(record)
		var choices: Dictionary = {"hp": "average"}
		if bool(plan["asi"]):
			choices["feat"] = "ability_score_improvement"
			choices["ability_increases"] = {"dex": 2}
		if not plan["class_choices"].is_empty():
			choices["class_choices"] = {}
			for choice: Dictionary in plan["class_choices"]:
				choices["class_choices"][String(choice["key"])] = choice["options"].slice(0, int(choice["count"]))
		assert_eq(ProgressionRules.validate(record, choices), "")
		ProgressionRules.apply(record, "hero", choices, Rng.rng)
	for spell_id: String in RANGER_SPELLS:
		if not spell_id in record["spells"]:
			record["spells"].append(spell_id)
	return record

## Hero at the origin, enemies where given, hero's turn.
func start(hero: Dictionary, enemies: Dictionary) -> void:
	var state: GameState = GameState.new()
	state.mode = &"combat"
	hero["position"] = Vector3.ZERO
	state.actors = {"hero": hero}
	var order: Array[String] = ["hero"]
	for id: String in enemies:
		state.actors[id] = enemy(enemies[id])
		order.append(id)
	state.turn_order.assign(order)
	CommandBus.submit(Setup.new(state))
	Rng.set_seed(7)

func settle() -> void:
	for index: int in 8:
		if Game.state.pending.is_empty():
			return
		CommandBus.submit(AdvanceCombatCommand.new(0.5))

func cast(spell_id: String, targets: Array = [], point: Vector3 = Vector3.INF) -> Error:
	var result: Error = CommandBus.submit(CastSpellCommand.new("hero", spell_id, targets, point))
	settle()
	return result

func mutate(change: Callable) -> void:
	CommandBus.submit(Mutate.new(change))

func shoot(target_id: String, bonus: int) -> void:
	mutate(func(state: GameState) -> void:
		state.actors["hero"]["weapon"]["attack_modifiers"] = [{"amount": bonus, "source": "test"}])
	assert_eq(CommandBus.submit(AttackCommand.new("hero", target_id)), OK)
	settle()

func hp(id: String) -> int:
	return int(Game.state.actors[id]["hp"])

func before_each() -> void:
	CombatSpace.active = null

func after_each() -> void:
	CommandBus.submit(Setup.new(GameState.new()))

func test_every_ranger_spell_loads_and_is_on_the_ranger_list() -> void:
	var list: Array[String] = ClassSpellcasting.spell_list("ranger")
	for spell_id: String in RANGER_SPELLS:
		var spell: SpellDefinition = SpellBook.get_spell(spell_id)
		assert_not_null(spell, spell_id)
		assert_true(spell != null and spell.is_valid(), spell_id)
		assert_true(spell_id in list, spell_id)

func test_strike_spells_need_a_weapon_attack_on_that_target_first() -> void:
	start(ranger(), {"enemy": Vector3(6, 0, 0)})
	assert_ne(CommandBus.submit(CastSpellCommand.new("hero", "hail_of_thorns", ["enemy"])), OK)
	shoot("enemy", 60)
	assert_eq(cast("hail_of_thorns", ["enemy"]), OK)

func test_hail_of_thorns_hits_the_target_and_its_neighbour() -> void:
	start(ranger(), {"enemy": Vector3(6, 0, 0), "enemy_b": Vector3(7, 0, 0), "enemy_c": Vector3(12, 0, 0)})
	shoot("enemy", 60)
	var before: int = hp("enemy")
	assert_eq(cast("hail_of_thorns", ["enemy"]), OK)
	assert_lt(hp("enemy"), before)
	assert_lt(hp("enemy_b"), 200, "within 1.5 m of the target")
	assert_eq(hp("enemy_c"), 200, "too far away")
	assert_false(bool(Game.state.actors["hero"]["bonus_available"]))

func test_lightning_arrow_after_a_miss_deals_half_and_bursts() -> void:
	start(ranger(9), {"enemy": Vector3(6, 0, 0), "enemy_b": Vector3(8, 0, 0)})
	shoot("enemy", -60)
	assert_eq(hp("enemy"), 200, "the arrow missed")
	assert_eq(cast("lightning_arrow", ["enemy"]), OK)
	assert_between(hp("enemy"), 200 - 16, 198, "half of 4d8")
	assert_lt(hp("enemy_b"), 200, "within 3 m of the target")

func test_ensnaring_strike_restrains_and_hurts_each_turn() -> void:
	start(ranger(), {"enemy": Vector3(6, 0, 0)})
	shoot("enemy", 60)
	assert_eq(cast("ensnaring_strike", ["enemy"]), OK)
	var target: Dictionary = Game.state.actors["enemy"]
	assert_true("restrained" in target["conditions"])
	var before: int = hp("enemy")
	CommandBus.submit(EndTurnCommand.new("hero"))
	CommandBus.submit(EndTurnCommand.new("enemy"))
	assert_lt(hp("enemy"), before, "1d6 piercing at the end of its turn")

func test_longstrider_adds_speed_now_and_on_later_turns() -> void:
	start(ranger(), {"enemy": Vector3(20, 0, 0)})
	var speed: float = float(Game.state.actors["hero"]["speed_m"])
	var left: float = float(Game.state.actors["hero"]["move_left"])
	assert_eq(cast("longstrider", ["hero"]), OK)
	assert_almost_eq(float(Game.state.actors["hero"]["move_left"]), left + 3.0, 0.01)
	CommandBus.submit(EndTurnCommand.new("hero"))
	CommandBus.submit(EndTurnCommand.new("enemy"))
	assert_almost_eq(float(Game.state.actors["hero"]["move_left"]), speed + 3.0, 0.01)

func test_spike_growth_hurts_every_step_through_it() -> void:
	start(ranger(5), {"enemy": Vector3(20, 0, 0)})
	assert_eq(cast("spike_growth", [], Vector3(10, 0, 0)), OK)
	var state: GameState = Game.state
	var path: PackedVector3Array = [Vector3(20, 0, 0), Vector3(10, 0, 0)]
	state.actors["enemy"]["position"] = Vector3(10, 0, 0)
	var events: Array[Dictionary] = ClassKits.after_move(state, "enemy", path, Rng.rng)
	assert_false(events.is_empty())
	assert_between(int(state.actors["enemy"]["hp"]), 200 - 32, 200 - 8, "4 steps of 1.5 m: 8d4")

func test_conjure_animals_mauls_an_enemy_ending_its_turn_in_reach() -> void:
	start(ranger(9), {"enemy": Vector3(10, 0, 0)})
	assert_eq(cast("conjure_animals", [], Vector3(11, 0, 0)), OK)
	CommandBus.submit(EndTurnCommand.new("hero"))
	CommandBus.submit(EndTurnCommand.new("enemy"))
	assert_lt(hp("enemy"), 200, "Dexterity 1 fails the save")

func test_fog_cloud_blinds_creatures_inside() -> void:
	start(ranger(), {"enemy": Vector3(10, 0, 0)})
	assert_eq(cast("fog_cloud", [], Vector3(10, 0, 0)), OK)
	assert_true("blinded" in Game.state.actors["enemy"]["conditions"])
	assert_false("blinded" in Game.state.actors["hero"]["conditions"])

func test_pass_without_trace_adds_ten_to_stealth() -> void:
	start(ranger(5), {"enemy": Vector3(20, 0, 0)})
	assert_eq(cast("pass_without_trace"), OK)
	var bonus: Array[RuleModifier] = ClassKits.check_modifiers(Game.state.actors["hero"], "stealth")
	assert_eq(bonus.size(), 1)
	assert_eq(bonus[0].amount, 10)

func test_restoration_and_protection_spells() -> void:
	start(ranger(5), {"enemy": Vector3(20, 0, 0)})
	mutate(func(state: GameState) -> void: state.actors["hero"]["conditions"].append("poisoned"))
	assert_true("poisoned" in Game.state.actors["hero"]["conditions"])
	assert_eq(cast("lesser_restoration", ["hero"]), OK)
	assert_false("poisoned" in Game.state.actors["hero"]["conditions"])
	CommandBus.submit(EndTurnCommand.new("hero"))
	CommandBus.submit(EndTurnCommand.new("enemy"))
	assert_eq(cast("protection_from_poison", ["hero"]), OK)
	assert_true(&"poison" in CombatRules.defenses_for(Game.state.actors["hero"]).resistances)

func test_goodberry_fills_the_bag_with_berries_that_heal_one() -> void:
	start(ranger(), {"enemy": Vector3(20, 0, 0)})
	assert_eq(cast("goodberry"), OK)
	assert_eq(EquipmentRules.count(Game.state.actors["hero"], "goodberry"), 10)
	mutate(func(state: GameState) -> void: state.actors["hero"]["hp"] = 3)
	assert_eq(CommandBus.submit(UseItemCommand.new("hero", "goodberry")), OK)
	assert_eq(hp("hero"), 4)

func test_conjure_barrage_is_a_force_cone() -> void:
	start(ranger(9), {"enemy": Vector3(5, 0, 0), "enemy_b": Vector3(-5, 0, 0)})
	assert_eq(cast("conjure_barrage", [], Vector3(5, 0, 0)), OK)
	assert_lt(hp("enemy"), 200)
	assert_eq(hp("enemy_b"), 200, "behind the caster")
