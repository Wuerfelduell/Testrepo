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
		return {}

var events: Array[Dictionary] = []

func before_each() -> void:
	CommandBus.submit(Setup.new(GameState.new()))
	assert_eq(CommandBus.submit(SetupArenaCommand.new()), OK)
	assert_eq(CommandBus.submit(SetupInventoryCommand.new("hero")), OK)
	events.clear()
	CommandBus.command_applied.connect(_collect)

func after_each() -> void:
	CommandBus.command_applied.disconnect(_collect)
	CommandBus.submit(Setup.new(GameState.new()))

func _collect(_command: Command, result: Dictionary) -> void:
	for event: Dictionary in result.get("events", []):
		events.append(event)

func hero() -> Dictionary:
	return Game.state.actors["hero"]

func enter_combat(hero_turn: bool = true) -> void:
	var state: GameState = Game.state
	state.mode = &"combat"
	state.turn_order.assign(["hero", "guard"] if hero_turn else ["guard", "hero"])
	state.turn_index = 0
	CommandBus.submit(Setup.new(state))

func test_catalog_items_and_kits_are_valid() -> void:
	assert_gt(ItemCatalog.ids().size(), 10)
	for item_id: String in ItemCatalog.ids():
		assert_true(ItemCatalog.valid_item(ItemCatalog.get_item(item_id)), item_id)
	for class_id: String in ["fighter", "wizard", "default"]:
		var kit: Dictionary = ItemCatalog.starting_kit(class_id)
		assert_true(ItemCatalog.has(String(kit["equipped"]["main_hand"])), class_id)
		for item_id: String in kit["bag"]:
			assert_true(ItemCatalog.has(item_id), item_id)

func test_fighter_kit_keeps_the_arena_hero_numbers() -> void:
	var actor: Dictionary = hero()
	assert_eq(actor["equipment"], {"main_hand": "longsword", "off_hand": "shield", "armor": "chain_mail"})
	assert_eq(int(actor["ac"]), 18)
	assert_eq(float(actor["speed_m"]), 9.0)
	assert_eq(int(actor["weapon"]["attack_bonus"]), 5)
	assert_eq(String(actor["weapon"]["damage_dice"]), "1d8")
	assert_eq(int(actor["weapon"]["damage_bonus"]), 3)
	assert_eq(String(actor["weapon"]["model"]), "res://assets/weapons/sword.glb")
	assert_true(CombatRules.weapon_valid(actor["weapon"]))
	assert_eq(EquipmentRules.count(actor, "potion_of_healing"), 2)
	assert_eq(CommandBus.submit(SetupInventoryCommand.new("hero")), ERR_ALREADY_IN_USE)

func test_two_handed_crossbow_puts_the_shield_in_the_bag() -> void:
	assert_eq(CommandBus.submit(EquipItemCommand.new("hero", "light_crossbow")), OK)
	var actor: Dictionary = hero()
	assert_eq(actor["equipment"]["main_hand"], "light_crossbow")
	assert_eq(actor["equipment"]["off_hand"], "")
	assert_eq(EquipmentRules.count(actor, "shield"), 1)
	assert_eq(EquipmentRules.count(actor, "longsword"), 1)
	assert_eq(EquipmentRules.count(actor, "light_crossbow"), 0)
	assert_eq(int(actor["ac"]), 16)
	assert_true(bool(actor["weapon"]["ranged"]))
	# DEX 14: +2, proficient (simple) +2.
	assert_eq(int(actor["weapon"]["attack_bonus"]), 4)
	assert_eq(float(actor["weapon"]["range"]), 24.0)
	assert_true(CombatRules.weapon_valid(actor["weapon"]))
	assert_eq(events[0]["type"], "equipment_changed")
	assert_eq(CommandBus.submit(EquipItemCommand.new("hero", "shield")), ERR_UNAVAILABLE)
	assert_eq(EquipmentRules.equip_reason(Game.state, "hero", "shield"), "INV_REASON_TWO_HANDED")

func test_versatile_weapon_uses_bigger_die_with_free_off_hand() -> void:
	assert_eq(CommandBus.submit(UnequipItemCommand.new("hero", "off_hand")), OK)
	assert_eq(String(hero()["weapon"]["damage_dice"]), "1d10")
	assert_eq(int(hero()["ac"]), 16)
	assert_eq(CommandBus.submit(EquipItemCommand.new("hero", "shield")), OK)
	assert_eq(String(hero()["weapon"]["damage_dice"]), "1d8")
	assert_eq(int(hero()["ac"]), 18)

func test_main_hand_is_never_empty() -> void:
	assert_eq(CommandBus.submit(UnequipItemCommand.new("hero", "main_hand")), ERR_UNAVAILABLE)
	assert_eq(EquipmentRules.unequip_reason(Game.state, "hero", "main_hand"), "INV_REASON_KEEP_WEAPON")

func test_finesse_dagger_uses_dexterity_when_higher() -> void:
	assert_eq(CommandBus.submit(EquipItemCommand.new("hero", "dagger")), OK)
	# STR 16 (+3) beats DEX 14 (+2), so finesse still picks STR.
	assert_eq(String(hero()["weapon"]["damage_modifiers"][0]["source"]), "str")
	var actor: Dictionary = hero()
	actor["ability_scores"][&"dex"] = 18
	var record: Dictionary = EquipmentRules.weapon_record(actor, "dagger", InventoryCommand.training_for(actor), true)
	assert_eq(String(record["damage_modifiers"][0]["source"]), "dex")
	assert_eq(int(record["attack_bonus"]), 6)

func test_combat_locks_armour_but_allows_weapon_swap_on_own_turn() -> void:
	enter_combat(true)
	assert_eq(EquipmentRules.unequip_reason(Game.state, "hero", "armor"), "INV_REASON_ARMOR_IN_COMBAT")
	assert_eq(CommandBus.submit(UnequipItemCommand.new("hero", "off_hand")), ERR_UNAVAILABLE)
	assert_eq(EquipmentRules.equip_reason(Game.state, "hero", "light_crossbow"), "INV_REASON_SHIELD_IN_COMBAT")
	var action_before: bool = bool(hero()["action_available"])
	assert_eq(CommandBus.submit(EquipItemCommand.new("hero", "dagger")), OK)
	assert_eq(String(hero()["weapon"]["id"]), "dagger")
	assert_eq(bool(hero()["action_available"]), action_before)
	assert_eq(int(hero()["ac"]), 18)

func test_nothing_changes_on_someone_elses_turn() -> void:
	enter_combat(false)
	assert_eq(EquipmentRules.equip_reason(Game.state, "hero", "dagger"), "INV_REASON_NOT_YOUR_TURN")
	assert_eq(CommandBus.submit(EquipItemCommand.new("hero", "dagger")), ERR_UNAVAILABLE)

func test_potion_heals_two_d4_plus_two_and_costs_a_bonus_action() -> void:
	var state: GameState = Game.state
	state.actors["hero"]["hp"] = 1
	CommandBus.submit(Setup.new(state))
	enter_combat(true)
	Rng.set_seed(4)
	assert_eq(CommandBus.submit(UseItemCommand.new("hero", "potion_of_healing")), OK)
	var healed: int = int(hero()["hp"]) - 1
	assert_between(healed, 4, 10)
	assert_false(bool(hero()["bonus_available"]))
	assert_eq(EquipmentRules.count(hero(), "potion_of_healing"), 1)
	assert_eq(events[0]["kind"], "healing")
	assert_eq(int(events[0]["roll"]["total"]), healed)
	assert_eq(EquipmentRules.use_reason(Game.state, "hero", "potion_of_healing"), "INV_REASON_NO_BONUS_ACTION")

func test_potion_is_capped_and_refused_at_full_health() -> void:
	assert_eq(EquipmentRules.use_reason(Game.state, "hero", "potion_of_healing"), "INV_REASON_FULL_HP")
	var state: GameState = Game.state
	state.actors["hero"]["hp"] = int(state.actors["hero"]["max_hp"]) - 1
	CommandBus.submit(Setup.new(state))
	assert_eq(CommandBus.submit(UseItemCommand.new("hero", "potion_of_healing")), OK)
	assert_eq(int(hero()["hp"]), int(hero()["max_hp"]))
	assert_true(bool(hero()["bonus_available"]), "Outside combat a potion costs nothing")

func test_wizard_kit_and_untrained_armour() -> void:
	var actor: Dictionary = {"class_id": "wizard", "proficiency_bonus": 2, "hp": 6, "max_hp": 6,
		"ability_scores": {&"str": 8, &"dex": 14, &"con": 14, &"int": 15, &"wis": 12, &"cha": 10}}
	var training: EquipmentRules.Training = InventoryCommand.training_for(actor)
	assert_true(EquipmentRules.initialize(actor, "wizard", training))
	assert_eq(actor["equipment"]["main_hand"], "quarterstaff")
	assert_eq(int(actor["ac"]), 12)
	assert_eq(String(actor["weapon"]["damage_dice"]), "1d8", "Versatile staff in two hands")
	assert_true(bool(actor["can_cast_spells"]))
	EquipmentRules.add_item(actor, "chain_mail")
	EquipmentRules.equip(actor, "chain_mail", training)
	assert_true(bool(actor["armor_untrained"]))
	assert_false(bool(actor["can_cast_spells"]))
	# STR 8 < 13: speed penalty.
	assert_eq(float(actor["speed_m"]), 6.0)

func test_codec_round_trips_inventory_commands() -> void:
	var commands: Array[Command] = [SetupInventoryCommand.new("hero"), EquipItemCommand.new("hero", "dagger"),
		UnequipItemCommand.new("hero", "off_hand"), UseItemCommand.new("hero", "potion_of_healing")]
	for command: Command in commands:
		var decoded: Command = CommandCodec.decode(command.to_dict())
		assert_not_null(decoded)
		assert_eq(decoded.to_dict(), command.to_dict())
	assert_null(CommandCodec.decode({"type": "equip_item", "actor_id": "hero"}))
	assert_null(CommandCodec.decode({"type": "use_item", "actor_id": "hero", "item_id": 3}))
	assert_eq(CommandBus.submit(EquipItemCommand.new("hero", "no_such_item")), ERR_INVALID_PARAMETER)
