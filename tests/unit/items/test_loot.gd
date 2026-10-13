extends GutTest

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
		state.loot_piles = fixture.loot_piles.duplicate(true)
		return {}

func before_each() -> void:
	CommandBus.submit(Setup.new(GameState.new()))
	assert_eq(CommandBus.submit(SetupArenaCommand.new()), OK)
	assert_eq(CommandBus.submit(SetupInventoryCommand.new("hero")), OK)

func after_each() -> void:
	CommandBus.submit(Setup.new(GameState.new()))

func hero() -> Dictionary:
	return Game.state.actors["hero"]

## Kills the bandit (rolling its loot like the arena does) and puts the hero at a distance.
func bandit_down(distance: float = 1.0, seed_value: int = 7) -> void:
	var state: GameState = Game.state
	state.actors["bandit"]["hp"] = 0
	state.actors["hero"]["position"] = (state.actors["bandit"]["position"] as Vector3) + Vector3(distance, 0, 0)
	state.mode = &"exploration"
	CommandBus.submit(Setup.new(state))
	Rng.set_seed(seed_value)
	assert_eq(CommandBus.submit(LootRollCommand.new("bandit")), OK)

func enter_combat() -> void:
	var state: GameState = Game.state
	state.mode = &"combat"
	state.turn_order.assign(["hero", "guard"])
	state.turn_index = 0
	state.actors["hero"]["action_available"] = true
	CommandBus.submit(Setup.new(state))

func test_loot_table_rolls_are_deterministic_with_a_seed() -> void:
	var first: RandomNumberGenerator = RandomNumberGenerator.new()
	first.seed = 42
	var second: RandomNumberGenerator = RandomNumberGenerator.new()
	second.seed = 42
	var a: Dictionary = LootRules.roll("bandit", first)
	assert_eq(a, LootRules.roll("bandit", second))
	# Stat block gear always drops; gold is 3d6.
	for item_id: String in ["light_crossbow", "scimitar", "leather"]:
		assert_true((a["items"] as Dictionary).has(item_id), item_id)
	assert_between(int(a["gold"]), 3, 18)
	var seen_ring: bool = false
	var seen_none: bool = false
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	for attempt: int in 60:
		var has_ring: bool = (LootRules.roll("bandit", rng)["items"] as Dictionary).has("silver_ring")
		seen_ring = seen_ring or has_ring
		seen_none = seen_none or not has_ring
	assert_true(seen_ring and seen_none, "Extras drop by chance, not always")

func test_roll_happens_once_and_only_for_dead_enemies() -> void:
	assert_eq(CommandBus.submit(LootRollCommand.new("bandit")), ERR_ALREADY_IN_USE, "Alive")
	assert_eq(CommandBus.submit(LootRollCommand.new("hero")), ERR_ALREADY_IN_USE, "Not an enemy")
	bandit_down()
	assert_eq(CommandBus.submit(LootRollCommand.new("bandit")), ERR_ALREADY_IN_USE, "Already rolled")

func test_living_and_distant_bodies_cannot_be_searched() -> void:
	assert_eq(LootRules.take_reason(Game.state, "hero", "bandit", "", true), "LOOT_REASON_ALIVE")
	bandit_down(8.0)
	assert_eq(LootRules.take_reason(Game.state, "hero", "bandit", "", true), "LOOT_REASON_TOO_FAR")
	assert_eq(LootRules.nearest(Game.state, "hero"), "")
	assert_eq(CommandBus.submit(LootTakeAllCommand.new("hero", "bandit")), ERR_UNAVAILABLE)

func test_take_one_item_then_everything_keeps_counts() -> void:
	bandit_down()
	assert_eq(LootRules.nearest(Game.state, "hero"), "bandit")
	var loot: Dictionary = LootRules.remaining(Game.state.actors["bandit"])
	var gold_before: int = int(hero()["gold"])
	var crossbows: int = EquipmentRules.count(hero(), "light_crossbow")
	assert_eq(CommandBus.submit(LootTakeCommand.new("hero", "bandit", "scimitar")), OK)
	assert_eq(EquipmentRules.count(hero(), "scimitar"), 1)
	assert_eq(CommandBus.submit(LootTakeCommand.new("hero", "bandit", "scimitar")), ERR_UNAVAILABLE)
	assert_eq(CommandBus.submit(LootTakeAllCommand.new("hero", "bandit")), OK)
	assert_eq(int(hero()["gold"]), gold_before + int(loot["gold"]))
	assert_eq(EquipmentRules.count(hero(), "light_crossbow"), crossbows + 1)
	for item_id: String in loot["items"]:
		assert_gte(EquipmentRules.count(hero(), item_id), int(loot["items"][item_id]), item_id)
	assert_false(LootRules.lootable(Game.state.actors["bandit"]))

func test_every_combat_take_costs_the_action() -> void:
	bandit_down()
	enter_combat()
	assert_eq(CommandBus.submit(LootTakeCommand.new("hero", "bandit", "scimitar")), OK)
	assert_false(bool(hero()["action_available"]), "Looting in combat costs the action")
	assert_eq(LootRules.take_reason(Game.state, "hero", "bandit", "leather"), "LOOT_REASON_NO_ACTION", "Every take costs an action")
	assert_eq(CommandBus.submit(LootTakeAllCommand.new("hero", "bandit")), ERR_UNAVAILABLE)
	var state: GameState = Game.state
	state.actors["hero"]["action_available"] = true
	CommandBus.submit(Setup.new(state))
	assert_eq(CommandBus.submit(LootTakeAllCommand.new("hero", "bandit")), OK)
	assert_false(bool(hero()["action_available"]))
	assert_eq(CommandBus.submit(DropItemCommand.new("hero", "dagger")), OK)
	var pile_id: String = Game.state.loot_piles.keys()[0]
	state = Game.state
	state.mode = &"exploration"
	CommandBus.submit(Setup.new(state))
	assert_eq(LootRules.take_reason(Game.state, "hero", pile_id, "dagger"), "", "Outside combat it is free")

func test_dropped_items_stay_on_the_ground_and_can_be_picked_up() -> void:
	var daggers: int = EquipmentRules.count(hero(), "dagger")
	assert_eq(CommandBus.submit(DropItemCommand.new("hero", "dagger")), OK)
	assert_eq(EquipmentRules.count(hero(), "dagger"), daggers - 1)
	assert_eq(Game.state.loot_piles.size(), 1)
	var pile_id: String = Game.state.loot_piles.keys()[0]
	assert_eq(int(Game.state.loot_piles[pile_id]["items"]["dagger"]), 1)
	assert_eq(LootRules.nearest(Game.state, "hero"), pile_id)
	assert_eq(CommandBus.submit(DropItemCommand.new("hero", "potion_of_healing")), OK)
	assert_eq(Game.state.loot_piles.size(), 1, "Drops at the same spot share one pile")
	assert_eq(CommandBus.submit(LootTakeAllCommand.new("hero", pile_id)), OK)
	assert_eq(EquipmentRules.count(hero(), "dagger"), daggers)
	assert_true(Game.state.loot_piles.is_empty(), "An empty pile disappears")
	assert_eq(CommandBus.submit(DropItemCommand.new("hero", "plate")), ERR_INVALID_PARAMETER)
	assert_eq(CommandBus.submit(DropItemCommand.new("hero", "mace")), ERR_UNAVAILABLE)

func test_save_round_trip_keeps_piles_and_looted_bodies() -> void:
	bandit_down()
	assert_eq(CommandBus.submit(LootTakeCommand.new("hero", "bandit", "gold")), OK)
	assert_eq(CommandBus.submit(DropItemCommand.new("hero", "dagger")), OK)
	var restored: GameState = GameState.from_dict(JSON.to_native(JSON.from_native(Game.state.to_dict())))
	assert_not_null(restored)
	assert_eq(int(LootRules.remaining(restored.actors["bandit"])["gold"]), 0)
	assert_eq(restored.loot_piles.size(), 1)
	assert_true(LootRules.lootable(restored.actors["bandit"]), "The body still holds its items")
	var old_save: Dictionary = Game.state.to_dict()
	old_save.erase("loot_piles")
	assert_not_null(GameState.from_dict(old_save), "Saves from before ground loot still load")

func test_carry_weight_slows_the_hero() -> void:
	# Fighter STR 16: 16 x 15 lb x 0.45 = 108 kg; slowed above, badly slowed above 216 kg.
	assert_almost_eq(EquipmentRules.capacity_kg(hero()), 108.0, 0.001)
	assert_eq(int(hero()["encumbrance"]), 0)
	assert_eq(float(hero()["speed_m"]), 9.0)
	var state: GameState = Game.state
	EquipmentRules.add_item(state.actors["hero"], "chain_mail", 4)
	EquipmentRules.refresh_speed(state.actors["hero"])
	CommandBus.submit(Setup.new(state))
	assert_eq(int(hero()["encumbrance"]), 1)
	assert_eq(float(hero()["speed_m"]), 6.0)
	var heavy: Dictionary = hero()
	EquipmentRules.add_item(heavy, "chain_mail", 5)
	EquipmentRules.refresh_speed(heavy)
	assert_eq(EquipmentRules.encumbrance(heavy), 2)
	assert_eq(float(heavy["speed_m"]), 3.0)
	assert_eq(CommandBus.submit(DropItemCommand.new("hero", "chain_mail")), OK)
	assert_eq(float(hero()["speed_m"]), 9.0, "Dropping below the limit restores speed")
	assert_eq(float(hero()["move_left"]), 9.0)

func test_codec_round_trips_loot_commands() -> void:
	for command: Command in [LootTakeCommand.new("hero", "bandit", "gold"), LootTakeAllCommand.new("hero", "pile_1"),
			DropItemCommand.new("hero", "dagger")]:
		var decoded: Command = CommandCodec.decode(command.to_dict())
		assert_not_null(decoded)
		assert_eq(decoded.to_dict(), command.to_dict())
	assert_null(CommandCodec.decode({"type": "loot_take", "actor_id": "hero", "item_id": ""}))
	assert_null(CommandCodec.decode({"type": "loot_roll", "actor_id": "bandit"}), "Rolling is never a client command")
