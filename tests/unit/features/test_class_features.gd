extends GutTest
## Fighter Second Wind and Weapon Mastery (Sap), Wizard Arcane Recovery.

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

func enemy(position: Vector3) -> Dictionary:
	return {"team": "enemy", "position": position, "hp": 60, "max_hp": 60, "ac": 5, "dex": 10,
		"speed_m": 9.0, "move_left": 9.0, "action_available": true, "bonus_available": true,
		"reaction_available": true, "disengaged": false, "conditions": [],
		"ability_scores": {&"str": 10, &"dex": 10, &"con": 10, &"int": 10, &"wis": 10, &"cha": 10},
		"weapon": {"ranged": false, "reach": 1.5, "attack_bonus": 4, "damage_dice": "1d4", "damage_bonus": 0, "damage_type": "slashing"}}

func start(hero: Dictionary) -> void:
	var state: GameState = GameState.new()
	state.mode = &"combat"
	state.actors = {"hero": hero, "enemy": enemy(Vector3(1, 0, 0))}
	state.turn_order = ["hero", "enemy"]
	CommandBus.submit(Setup.new(state))
	Rng.set_seed(77)

func before_each() -> void:
	CombatSpace.active = null

func after_each() -> void:
	CommandBus.submit(Setup.new(GameState.new()))

func test_fighter_has_active_level_one_features() -> void:
	var fighter: Dictionary = HeroKit.create(&"fighter")
	assert_true(bool(fighter["class_features_active"]))
	assert_eq(fighter["features"]["second_wind"]["uses"], 2)
	assert_eq(fighter["weapon"]["mastery"], "sap")
	assert_eq(fighter["hp"], 12)
	assert_eq(fighter["ac"], 18)

func test_second_wind_heals_as_bonus_action_and_spends_a_use() -> void:
	var fighter: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	fighter["hp"] = 2
	start(fighter)
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "second_wind")), OK)
	var hero: Dictionary = Game.state.actors["hero"]
	assert_between(int(hero["hp"]), 4, 12, "1d10+1 healing, capped at maximum")
	assert_false(bool(hero["bonus_available"]))
	assert_true(bool(hero["action_available"]), "the action stays free")
	assert_eq(hero["features"]["second_wind"]["uses"], 1)
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "second_wind")), ERR_UNAVAILABLE)

func test_second_wind_never_heals_above_maximum() -> void:
	var fighter: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	fighter["hp"] = 11
	start(fighter)
	CommandBus.submit(UseFeatureCommand.new("hero", "second_wind"))
	assert_eq(Game.state.actors["hero"]["hp"], 12)

func test_wizard_cannot_use_second_wind() -> void:
	start(HeroKit.create(&"wizard", Vector3.ZERO))
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "second_wind")), ERR_UNAVAILABLE)

func test_sap_gives_the_hit_target_disadvantage_on_its_next_attack_only() -> void:
	var fighter: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	fighter["weapon"]["attack_modifiers"] = [{"amount": 50, "source": "str"}]
	start(fighter)
	assert_eq(CommandBus.submit(AttackCommand.new("hero", "enemy")), OK)
	CommandBus.submit(AdvanceCombatCommand.new(1.0))
	var target: Dictionary = Game.state.actors["enemy"]
	assert_true(ActiveEffects.has_kind(target, "sap"))
	var preview: Dictionary = CombatRules.attack_preview(Game.state, "enemy", "hero")
	assert_has(preview["disadvantages"], &"sap")
	assert_eq(CommandBus.submit(EndTurnCommand.new("hero")), OK)
	assert_eq(CommandBus.submit(AttackCommand.new("enemy", "hero")), OK)
	CommandBus.submit(AdvanceCombatCommand.new(1.0))
	assert_false(ActiveEffects.has_kind(Game.state.actors["enemy"], "sap"), "consumed by its attack roll")

func test_sap_expires_at_the_start_of_the_fighters_next_turn() -> void:
	var fighter: Dictionary = HeroKit.create(&"fighter", Vector3.ZERO)
	fighter["weapon"]["attack_modifiers"] = [{"amount": 50, "source": "str"}]
	start(fighter)
	CommandBus.submit(AttackCommand.new("hero", "enemy"))
	CommandBus.submit(AdvanceCombatCommand.new(1.0))
	CommandBus.submit(EndTurnCommand.new("hero"))
	assert_true(ActiveEffects.has_kind(Game.state.actors["enemy"], "sap"))
	CommandBus.submit(EndTurnCommand.new("enemy"))
	assert_false(ActiveEffects.has_kind(Game.state.actors["enemy"], "sap"))

func test_arcane_recovery_budget_and_limits() -> void:
	assert_eq(SpellRules.arcane_recovery_budget(1), 1)
	assert_eq(SpellRules.arcane_recovery_budget(5), 3)
	var slots: Array = [0, 0, 0]
	assert_true(SpellRules.arcane_recovery(slots, [4, 3, 2], 5, [1, 2]))
	assert_eq(slots, [1, 1, 0])
	assert_false(SpellRules.arcane_recovery(slots, [4, 3, 2], 5, [3, 1]), "over budget")
	var full: Array = [2]
	assert_false(SpellRules.arcane_recovery(full, [2], 1, [1]), "cannot exceed the maximum")
	var high: Array = [4, 3, 3, 3, 2, 0]
	assert_false(SpellRules.arcane_recovery(high, [4, 3, 3, 3, 2, 1], 10, [6]), "no 6th-level slots")

func test_arcane_recovery_needs_a_short_rest() -> void:
	var wizard: Dictionary = HeroKit.create(&"wizard", Vector3.ZERO)
	wizard["spell_slots"] = [0]
	start(wizard)
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "arcane_recovery", [1])), ERR_UNAVAILABLE)
	var resting: GameState = Game.state
	resting.mode = &"short_rest"
	CommandBus.submit(Setup.new(resting))
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "arcane_recovery", [1])), OK)
	assert_eq(Game.state.actors["hero"]["spell_slots"], [1])
	assert_eq(CommandBus.submit(UseFeatureCommand.new("hero", "arcane_recovery", [1])), ERR_UNAVAILABLE, "once per long rest")

func test_feature_codec_round_trip_and_rejections() -> void:
	var command: Command = CommandCodec.decode(UseFeatureCommand.new("hero", "second_wind").to_dict())
	assert_true(command is UseFeatureCommand)
	assert_null(CommandCodec.decode({"type": "use_feature", "actor_id": "hero", "feature_id": "wish", "slot_levels": []}))
	assert_null(CommandCodec.decode({"type": "use_feature", "actor_id": "hero", "feature_id": "second_wind", "slot_levels": [0]}))

func test_created_heroes_get_their_features_in_the_arena_setup() -> void:
	var created: Dictionary = HeroFactory.build_record("wizard",
		{"scene": "res://assets/characters/superhero_male_fullbody/model.glb"}, "Mira")
	assert_false(bool(created["class_features_active"]))
	var active: Dictionary = HeroKit.activate(created)
	assert_true(bool(active["class_features_active"]))
	assert_eq(active["spell_slots"], [2])
	assert_eq(active["spell_save_dc"], 12, "standard array INT 15")
	assert_eq(active["name_key"], "Mira")
	assert_eq(HeroKit.activate(active), active, "activating twice changes nothing")

func test_untrained_armour_blocks_spellcasting() -> void:
	var wizard: Dictionary = HeroKit.create(&"wizard", Vector3.ZERO)
	wizard["can_cast_spells"] = false
	start(wizard)
	assert_eq(SpellResolver.availability_reason(Game.state, "hero", SpellBook.get_spell("fire_bolt")), "SPELL_REASON_ARMOR")
