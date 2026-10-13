extends GutTest
## Prompt 08: Short Rest (Hit Point Dice, Second Wind, Action Surge, Arcane Recovery,
## Memorize Spell) and Long Rest, both blocked in combat and near enemies.

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

func enemy(position: Vector3, hp: int = 11) -> Dictionary:
	return {"team": "enemy", "position": position, "hp": hp, "max_hp": 11, "ac": 12, "dex": 10,
		"speed_m": 9.0, "move_left": 9.0, "conditions": []}

func use(hero: Dictionary, enemy_position: Vector3 = Vector3(60, 0, 0), mode: StringName = &"exploration") -> void:
	var state: GameState = GameState.new()
	state.mode = mode
	state.actors = {"hero": hero, "enemy": enemy(enemy_position)}
	state.turn_order = ["hero", "enemy"]
	CommandBus.submit(Setup.new(state))
	Rng.set_seed(99)

func fighter(level: int) -> Dictionary:
	var record: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	record["level"] = level
	record["hp_gains"] = []
	for index: int in level - 1:
		record["hp_gains"].append(6)
	ClassFeatures.advance(record, level)
	ProgressionRules.refresh_derived(record)
	record["max_hp"] = ProgressionRules.maximum_hp(record)
	record["hp"] = record["max_hp"]
	return record

func wizard(level: int) -> Dictionary:
	var record: Dictionary = HeroKit.create(&"wizard", Vector3.ZERO)
	record["level"] = level
	ClassFeatures.advance(record, level)
	ProgressionRules.refresh_derived(record)
	record["max_hp"] = ProgressionRules.maximum_hp(record)
	record["hp"] = record["max_hp"]
	return record

func current() -> Dictionary:
	return Game.state.actors["hero"]

func after_each() -> void:
	CommandBus.submit(Setup.new(GameState.new()))

func test_short_rest_spends_hit_dice_and_heals() -> void:
	var hero: Dictionary = fighter(3)
	hero["hp"] = 4
	use(hero)
	var events: Array = []
	var listener: Callable = func(_command: Command, result: Dictionary) -> void: events.append_array(result.get("events", []))
	CommandBus.command_applied.connect(listener)
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 2)), OK)
	CommandBus.command_applied.disconnect(listener)
	var rolls: Array = events.filter(func(event: Dictionary) -> bool: return event["type"] == "roll")
	assert_eq(rolls.size(), 2, "one dice popup roll per Hit Point Die")
	var healed: int = 0
	for roll: Dictionary in rolls:
		assert_eq(roll["roll"]["groups"][0]["sides"], 10)
		assert_eq(roll["roll"]["modifiers"][0], {"amount": 2, "source": "con"})
		healed += int(roll["amount"])
	assert_eq(current()["hp"], 4 + healed)
	assert_between(healed, 6, 24)
	assert_eq(current()["hit_dice"]["left"], 1)
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 2)), ERR_INVALID_PARAMETER, "only one die left")

func test_short_rest_recharges_second_wind_by_one_and_action_surge_fully() -> void:
	var hero: Dictionary = fighter(2)
	hero["features"]["second_wind"]["uses"] = 0
	hero["features"]["action_surge"]["uses"] = 0
	use(hero)
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0)), OK)
	assert_eq(current()["features"]["second_wind"]["uses"], 1)
	assert_eq(current()["features"]["action_surge"]["uses"], 1)

func test_no_rest_in_combat_or_near_enemies() -> void:
	use(fighter(1), Vector3(60, 0, 0), &"combat")
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0)), ERR_UNAVAILABLE)
	assert_eq(CommandBus.submit(LongRestCommand.new("hero")), ERR_UNAVAILABLE)
	use(fighter(1), Vector3(12, 0, 0))
	assert_eq(RestRules.rest_reason(Game.state, "hero"), "REST_REASON_ENEMIES")
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0)), ERR_UNAVAILABLE)
	assert_eq(CommandBus.submit(LongRestCommand.new("hero")), ERR_UNAVAILABLE)
	use(fighter(1), Vector3(RestRules.SAFE_DISTANCE_M + 1.0, 0, 0))
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0)), OK)

func test_dead_enemies_do_not_block_rest() -> void:
	var state: GameState = GameState.new()
	state.actors = {"hero": fighter(1), "enemy": enemy(Vector3(2, 0, 0), 0)}
	CommandBus.submit(Setup.new(state))
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0)), OK)

func test_arcane_recovery_during_short_rest_once_per_long_rest() -> void:
	var hero: Dictionary = wizard(3)
	hero["spell_slots"] = [0, 0]
	use(hero)
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0, [2, 1])), ERR_INVALID_PARAMETER,
		"level 3: slots worth 2 levels at most")
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0, [2])), OK)
	assert_eq(current()["spell_slots"], [0, 1])
	assert_true(bool(current()["features"]["arcane_recovery"]["used"]))
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0, [1])), ERR_INVALID_PARAMETER)
	assert_eq(CommandBus.submit(LongRestCommand.new("hero")), OK)
	assert_false(bool(current()["features"]["arcane_recovery"]["used"]))
	assert_eq(current()["spell_slots"], [4, 2])

func test_memorize_spell_swaps_one_prepared_spell_after_a_short_rest() -> void:
	var hero: Dictionary = wizard(5)
	hero["spellbook"] = ["magic_missile", "burning_hands", "shield", "sleep", "fireball"]
	use(hero)
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0, [], ["sleep", "fireball"])), OK)
	assert_has(current()["spells"], "fireball")
	assert_does_not_have(current()["spells"], "sleep")
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0, [], ["fireball", "shatter"])), ERR_INVALID_PARAMETER,
		"only spells from the book")
	var low: Dictionary = wizard(4)
	use(low)
	assert_eq(CommandBus.submit(ShortRestCommand.new("hero", 0, [], ["sleep", "magic_missile"])), ERR_INVALID_PARAMETER,
		"Memorize Spell needs level 5")

func test_long_rest_restores_everything() -> void:
	var hero: Dictionary = fighter(4)
	hero["hp"] = 3
	hero["hit_dice"]["left"] = 0
	hero["features"]["second_wind"]["uses"] = 0
	hero["features"]["action_surge"]["uses"] = 0
	use(hero)
	assert_eq(CommandBus.submit(LongRestCommand.new("hero")), OK)
	var rested: Dictionary = current()
	assert_eq(rested["hp"], rested["max_hp"])
	assert_eq(rested["hit_dice"]["left"], 4, "SRD 5.2: all spent Hit Point Dice return")
	assert_eq(rested["features"]["second_wind"]["uses"], 3)
	assert_eq(rested["features"]["action_surge"]["uses"], 1)

func test_long_rest_can_change_prepared_spells() -> void:
	var hero: Dictionary = wizard(3)
	hero["spellbook"] = ["magic_missile", "burning_hands", "shield", "sleep", "shatter"]
	use(hero)
	assert_eq(CommandBus.submit(LongRestCommand.new("hero", ["shatter", "fireball"] as Array[String])), ERR_INVALID_PARAMETER)
	assert_eq(CommandBus.submit(LongRestCommand.new("hero", ["shatter", "shield"] as Array[String])), OK)
	assert_eq(ClassFeatures.prepared_spells(current()), ["shatter", "shield"])
	assert_has(current()["spells"], "fire_bolt", "cantrips stay")

func test_rest_commands_round_trip_through_the_codec() -> void:
	for command: Command in [ShortRestCommand.new("hero", 2, [1], ["sleep", "fireball"]),
			LongRestCommand.new("hero", ["shield"] as Array[String])]:
		var decoded: Command = CommandCodec.decode(JSON.parse_string(JSON.stringify(command.to_dict())))
		assert_not_null(decoded)
		assert_eq(decoded.to_dict(), command.to_dict())
	assert_null(CommandCodec.decode({"type": "short_rest", "actor_id": "hero", "hit_dice": -1, "arcane_slots": [], "memorize": []}))
	assert_null(CommandCodec.decode({"type": "short_rest", "actor_id": "hero", "hit_dice": 1.5, "arcane_slots": [], "memorize": []}))
	assert_null(CommandCodec.decode({"type": "long_rest", "actor_id": "hero", "prepared": [3]}))
