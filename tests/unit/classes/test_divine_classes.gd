extends GutTest
## Cleric, Paladin and Druid (SRD 5.2): creation, class features, feature spells
## (Divine Spark, Lay on Hands, Wild Shape), Divine Smite and Divine Strike, rests.

class Setup extends Command:
	var fixture: GameState
	func _init(value: GameState) -> void:
		fixture = value
	func validate(_state: GameState) -> Error:
		return OK
	func apply(state: GameState) -> Dictionary:
		state.actors = fixture.actors.duplicate(true)
		state.pending = {}
		state.turn_order = fixture.turn_order.duplicate()
		state.turn_index = fixture.turn_index
		state.round_number = fixture.round_number
		state.mode = fixture.mode
		return {}

var events: Array[Dictionary] = []

func before_each() -> void:
	CombatSpace.active = null
	Rng.set_seed(777)
	events.clear()
	CommandBus.command_applied.connect(_collect)

func after_each() -> void:
	CommandBus.command_applied.disconnect(_collect)
	CommandBus.submit(Setup.new(GameState.new()))
	CombatSpace.active = null

func _collect(_command: Command, result: Dictionary) -> void:
	for event: Dictionary in result.get("events", []):
		events.append(event)

func hero(class_id: StringName, level: int = 1, position: Vector3 = Vector3.ZERO) -> Dictionary:
	var record: Dictionary = HeroKit.create(class_id, position)
	for next: int in range(2, level + 1):
		record["level"] = next
		ClassFeatures.advance(record, next)
		ProgressionRules.refresh_derived(record)
	return record

func dummy(position: Vector3) -> Dictionary:
	var record: Dictionary = HeroKit.create(&"fighter", position)
	record["team"] = "enemy"
	record["hp"] = 200
	record["max_hp"] = 200
	return record

func start(actors: Dictionary, order: Array[String]) -> void:
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = actors
	state.turn_order = order
	CommandBus.submit(Setup.new(state))

func finish() -> void:
	for step: int in 80:
		if Game.state.pending.is_empty():
			return
		CommandBus.submit(AdvanceCombatCommand.new(0.1))

func test_all_three_classes_are_playable_with_their_kits() -> void:
	for class_id: String in ["cleric", "paladin", "druid"]:
		assert_true(HeroFactory.is_playable(class_id), class_id)
		var look: Dictionary = HeroLooks.for_class(class_id, "female")[0]
		var record: Dictionary = HeroFactory.build_record(class_id, look, "Test")
		assert_true(HeroFactory.valid_record(record), class_id)
		var kit: Dictionary = ItemCatalog.starting_kit(class_id)
		assert_eq(String(kit["equipped"]["off_hand"]), "shield", class_id)
		for spell_id: String in ClassSpellcasting.spell_list(class_id):
			assert_true(SpellBook.get_spell(spell_id).is_valid(), spell_id)

func test_cleric_starts_with_wisdom_spells_and_protector_training() -> void:
	var cleric: Dictionary = hero(&"cleric")
	assert_eq(String(cleric["spell_ability"]), "wis")
	assert_eq(cleric["spell_slots_max"], [2])
	assert_true("sacred_flame" in cleric["spells"])
	assert_true("bless" in cleric["spells"])
	assert_eq(String(cleric["features"]["divine_order"]), "protector")
	var training: EquipmentRules.Training = EquipmentRules.Training.for_actor(cleric, ClassFeatures.definition("cleric"))
	assert_true(&"heavy" in training.armor)
	assert_true(&"martial" in training.weapons)

func test_cleric_channel_divinity_grows_and_recharges() -> void:
	var cleric: Dictionary = hero(&"cleric", 6)
	assert_eq(int(cleric["features"]["channel_divinity"]["max"]), 3)
	assert_true("divine_spark" in cleric["spells"])
	assert_true("turn_undead" in cleric["spells"])
	assert_false("divine_spark" in ClassFeatures.prepared_spells(cleric), "Always prepared, never counted")
	cleric["features"]["channel_divinity"]["uses"] = 0
	ClassKits.recharge(cleric, "short")
	assert_eq(int(cleric["features"]["channel_divinity"]["uses"]), 1)
	RestRules.long_rest(cleric, "cleric")
	assert_eq(int(cleric["features"]["channel_divinity"]["uses"]), 3)

func test_divine_spark_spends_channel_divinity_not_a_slot() -> void:
	var cleric: Dictionary = hero(&"cleric", 2)
	start({"cleric": cleric, "foe": dummy(Vector3(0, 0, -4))}, ["cleric", "foe"])
	assert_eq(CommandBus.submit(CastSpellCommand.new("cleric", "divine_spark", ["foe"])), OK)
	finish()
	var after: Dictionary = Game.state.actors["cleric"]
	assert_eq(int(after["features"]["channel_divinity"]["uses"]), 1)
	assert_eq(after["spell_slots"], after["spell_slots_max"])
	assert_lt(int(Game.state.actors["foe"]["hp"]), 200)

func test_divine_strike_once_per_turn() -> void:
	var cleric: Dictionary = hero(&"cleric", 7)
	assert_eq(String(cleric["features"]["blessed_strikes"]), "divine_strike")
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = {"cleric": cleric, "foe": dummy(Vector3(0, 0, -1))}
	state.turn_order = ["cleric", "foe"]
	var weapon: Dictionary = cleric["weapon"]
	assert_eq(ClassKits.extra_damage_dice(state, "cleric", "foe", weapon, false).size(), 1)
	assert_eq(ClassKits.extra_damage_dice(state, "cleric", "foe", weapon, false).size(), 0)

func test_paladin_lay_on_hands_heals_from_the_pool() -> void:
	var paladin: Dictionary = hero(&"paladin", 2)
	assert_eq(int(paladin["features"]["lay_on_hands"]["max"]), 10)
	assert_eq(paladin["spell_slots_max"], [2])
	assert_true("lay_on_hands" in paladin["spells"])
	var ally: Dictionary = HeroKit.create(&"fighter", Vector3(0, 0, -1))
	ally["hp"] = int(ally["max_hp"]) - 4
	start({"paladin": paladin, "ally": ally}, ["paladin", "ally"])
	assert_eq(CommandBus.submit(CastSpellCommand.new("paladin", "lay_on_hands", ["ally"])), OK)
	finish()
	assert_eq(int(Game.state.actors["ally"]["hp"]), int(ally["max_hp"]))
	assert_eq(int(Game.state.actors["paladin"]["features"]["lay_on_hands"]["uses"]), 6)

func test_paladin_defense_style_adds_armour_class() -> void:
	var paladin: Dictionary = hero(&"paladin", 2)
	assert_eq(String(paladin["features"]["fighting_style"]), "defense")
	assert_eq(ClassKits.ac_bonus(paladin, &"chain_mail"), [{"amount": 1, "source": "defense"}])
	assert_eq(ClassKits.ac_bonus(paladin, &"none"), [])

func test_divine_smite_uses_the_free_use_then_a_slot() -> void:
	var paladin: Dictionary = hero(&"paladin", 2)
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = {"paladin": paladin, "foe": dummy(Vector3(0, 0, -1))}
	state.turn_order = ["paladin", "foe"]
	paladin["bonus_available"] = true
	paladin["action_available"] = true
	var weapon: Dictionary = paladin["weapon"]
	assert_eq(ClassKits.extra_damage_dice(state, "paladin", "foe", weapon, false), [], "Not armed")
	ClassKits.use_feature(state, "paladin", "divine_smite", Rng.rng)
	var dice: Array = ClassKits.extra_damage_dice(state, "paladin", "foe", weapon, false)
	assert_eq(String(dice[0]["dice"]), "2d8")
	assert_eq(int(paladin["features"]["divine_smite"]["uses"]), 0)
	assert_false(bool(paladin["bonus_available"]))
	assert_eq(paladin["spell_slots"], [2], "The free use spends no slot")
	paladin["bonus_available"] = true
	ClassKits.use_feature(state, "paladin", "divine_smite", Rng.rng)
	assert_eq(ClassKits.extra_damage_dice(state, "paladin", "foe", weapon, false).size(), 1)
	assert_eq(paladin["spell_slots"], [1])

func test_aura_of_protection_adds_charisma_to_ally_saves() -> void:
	var paladin: Dictionary = hero(&"paladin", 6)
	var ally: Dictionary = HeroKit.create(&"fighter", Vector3(0, 0, -2))
	var state: GameState = GameState.new()
	state.actors = {"paladin": paladin, "ally": ally}
	var bonus: int = maxi(1, Abilities.modifier(ProgressionRules.score(paladin, "cha")))
	assert_eq(ClassEffects.aura_of_protection(state, "ally"), bonus)
	ally["position"] = Vector3(0, 0, -6)
	assert_eq(ClassEffects.aura_of_protection(state, "ally"), 0)

func test_druid_magician_gets_a_third_cantrip() -> void:
	var druid: Dictionary = hero(&"druid")
	assert_eq(ClassSpellcasting.cantrips_for(druid, 1), 3)
	assert_eq(ClassFeatures.known_cantrips(druid).size(), 3)
	assert_false(druid["features"].has("wild_shape"))

func test_wild_shape_turns_the_druid_into_a_wolf_and_back() -> void:
	var druid: Dictionary = hero(&"druid", 2)
	assert_eq(int(druid["features"]["wild_shape"]["max"]), 2)
	start({"druid": druid, "foe": dummy(Vector3(0, 0, -6))}, ["druid", "foe"])
	assert_eq(CommandBus.submit(CastSpellCommand.new("druid", "wild_shape", [])), OK)
	finish()
	var wolf: Dictionary = Game.state.actors["druid"]
	assert_true(wolf.has("wild_shape"))
	assert_eq(int(wolf["ac"]), 12)
	assert_eq(String(wolf["weapon"]["id"]), "wolf_bite")
	assert_eq(int(wolf["temp_hp"]), 2)
	assert_eq(int(wolf["features"]["wild_shape"]["uses"]), 1)
	assert_eq(SpellResolver.availability_reason(Game.state, "druid", SpellBook.get_spell("entangle"), 0, true),
		"SPELL_REASON_WILD_SHAPE")
	assert_ne(EquipmentRules.turn_reason(Game.state, "druid"), "")
	var snapshot: GameState = Game.state
	ClassKits.on_combat_end(snapshot)
	wolf = snapshot.actors["druid"]
	assert_false(wolf.has("wild_shape"))
	assert_eq(int(wolf["ac"]), int(druid["ac"]))

func test_bless_adds_to_saves_of_up_to_three_allies() -> void:
	var cleric: Dictionary = hero(&"cleric")
	var allies: Dictionary = {"cleric": cleric}
	for index: int in 3:
		allies["ally_%d" % index] = HeroKit.create(&"fighter", Vector3(index + 1, 0, 0))
	start(allies, ["cleric", "ally_0", "ally_1", "ally_2"])
	assert_eq(CommandBus.submit(CastSpellCommand.new("cleric", "bless", [], Vector3(0, 0, 1))), OK)
	finish()
	var blessed: int = 0
	for id: String in Game.state.actors:
		if ActiveEffects.has_kind(Game.state.actors[id], "bless"):
			blessed += 1
	assert_eq(blessed, 3)
	assert_eq(ClassEffects.save_modifiers(Game.state, "cleric", Rng.rng).size(), 1)

func test_guidance_helps_the_clerics_dialogue_checks() -> void:
	var cleric: Dictionary = hero(&"cleric")
	assert_eq(ClassFeatures.known_cantrips(cleric).size(), 3)
	assert_true("guidance" in cleric["spells"])
	var event: Dictionary = DialogueChooseCommand.roll_check(cleric, "insight", 12)
	var sources: Array = event["roll"]["modifiers"].map(func(modifier: Dictionary) -> String: return modifier["source"])
	assert_true("guidance" in sources)
	var fighter: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	var plain: Dictionary = DialogueChooseCommand.roll_check(fighter, "insight", 12)
	assert_false("guidance" in plain["roll"]["modifiers"].map(func(modifier: Dictionary) -> String: return modifier["source"]))
