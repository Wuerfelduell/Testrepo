extends GutTest

func test_condition_sources_do_not_stack_and_removal_is_source_specific() -> void:
	var conditions: ConditionState = ConditionState.new()
	assert_false(conditions.add(&"invented"))
	conditions.add(&"poisoned", &"a")
	conditions.add(&"poisoned", &"a")
	conditions.add(&"poisoned", &"b")
	assert_eq(conditions.source_ids(&"poisoned").size(), 2)
	assert_eq(conditions.attack_disadvantages().size(), 1)
	conditions.remove(&"poisoned", &"a")
	assert_true(conditions.has(&"poisoned"))
	assert_false(conditions.remove(&"poisoned", &"a"))
	conditions.remove(&"poisoned", &"b")
	assert_false(conditions.has(&"poisoned"))

func test_all_requested_conditions_load_and_unconscious_state_effects() -> void:
	var conditions: ConditionState = ConditionState.new()
	for id: StringName in [&"blinded", &"frightened", &"poisoned", &"prone", &"restrained", &"stunned", &"unconscious"]:
		assert_true(conditions.add(id))
		assert_true(conditions.has(id))
	assert_false(conditions.can_speak())
	assert_false(conditions.can_concentrate())
	assert_false(conditions.is_aware())
	assert_true(conditions.must_drop_held_items())

func test_action_bonus_reaction_are_independent_and_reset_on_own_turn() -> void:
	var turn: TurnEconomy = TurnEconomy.new()
	assert_true(turn.begin_turn(9.0))
	assert_true(turn.spend_action())
	assert_false(turn.spend_action())
	assert_false(turn.spend_bonus_action(false))
	assert_true(turn.spend_bonus_action(true))
	assert_false(turn.spend_bonus_action(true))
	assert_true(turn.spend_reaction())
	assert_false(turn.spend_reaction())
	turn.begin_turn(9.0)
	assert_true(turn.spend_action())
	assert_true(turn.spend_bonus_action(true))
	assert_true(turn.spend_reaction())

func test_incapacitated_blocks_all_action_types_and_recovery_does_not_spend_them() -> void:
	for id: StringName in [&"stunned", &"unconscious", &"incapacitated"]:
		var turn: TurnEconomy = TurnEconomy.new()
		turn.conditions.add(id)
		turn.begin_turn(9.0)
		assert_false(turn.spend_action())
		assert_false(turn.spend_bonus_action(true))
		assert_false(turn.spend_reaction())
		turn.conditions.remove(id)
		assert_true(turn.spend_action())

func test_stunned_does_not_reduce_speed_under_2024_rules() -> void:
	var turn: TurnEconomy = TurnEconomy.new()
	turn.conditions.add(&"stunned")
	turn.begin_turn(9.0)
	assert_eq(turn.speed_m(), 9.0)
	assert_true(turn.move(9.0))
	assert_false(turn.dash())

func test_restrained_blocks_movement_not_actions_and_live_recovery_restores_budget() -> void:
	var turn: TurnEconomy = TurnEconomy.new()
	turn.begin_turn(9.0)
	turn.move(3.0)
	turn.conditions.add(&"restrained")
	assert_eq(turn.remaining_m(), 0.0)
	assert_false(turn.move(0.1))
	assert_true(turn.spend_action())
	turn.conditions.remove(&"restrained")
	assert_eq(turn.remaining_m(), 6.0)

func test_movement_exact_budget_difficult_terrain_and_dash() -> void:
	var turn: TurnEconomy = TurnEconomy.new()
	turn.begin_turn(9.0)
	assert_true(turn.move(2.0, true))
	assert_eq(turn.remaining_m(), 5.0)
	assert_false(turn.move(5.01))
	assert_true(turn.move(5.0))
	assert_almost_eq(turn.remaining_m(), 0.0, 0.000001)
	assert_true(turn.dash())
	assert_eq(turn.remaining_m(), 9.0)
	assert_false(turn.dash())
	assert_true(turn.move(9.0))

func test_prone_crawling_stacks_with_difficult_terrain_and_standing_costs_half_speed() -> void:
	var turn: TurnEconomy = TurnEconomy.new()
	turn.begin_turn(9.0)
	turn.conditions.add(&"prone")
	assert_true(turn.move(1.0, true))
	assert_eq(turn.remaining_m(), 6.0)
	assert_true(turn.stand_up())
	assert_almost_eq(turn.remaining_m(), 1.5, 0.000001)
	assert_false(turn.conditions.has(&"prone"))
	assert_false(turn.stand_up())

func test_standing_rounds_feet_before_conversion_and_fails_with_no_speed() -> void:
	var turn: TurnEconomy = TurnEconomy.new()
	turn.begin_turn(7.5) # 25 feet; standing costs floor(12.5) feet = 3.6 m
	turn.conditions.add(&"prone")
	assert_true(turn.stand_up())
	assert_almost_eq(turn.remaining_m(), 3.9, 0.000001)
	turn.conditions.add(&"unconscious")
	assert_false(turn.stand_up())
	turn.conditions.remove(&"unconscious")
	turn.conditions.add(&"restrained")
	assert_false(turn.stand_up())
	turn.conditions.remove(&"restrained")
	turn.begin_turn(0.0)
	assert_false(turn.stand_up())

func test_frightened_cannot_approach_even_when_fear_source_not_visible() -> void:
	var turn: TurnEconomy = TurnEconomy.new()
	turn.begin_turn(9.0)
	turn.conditions.add(&"frightened", &"dragon")
	assert_true(turn.conditions.check_disadvantages(false).is_empty())
	assert_false(turn.move(1.0, false, true))
	assert_true(turn.move(1.0, false, false))
	assert_eq(turn.remaining_m(), 8.0)

func test_invalid_movement_does_not_reset_or_refund_budget() -> void:
	var turn: TurnEconomy = TurnEconomy.new()
	turn.begin_turn(9.0)
	turn.move(3.0)
	assert_false(turn.begin_turn(-1.0))
	assert_false(turn.begin_turn(INF))
	assert_false(turn.move(-1.0))
	assert_false(turn.move(NAN))
	assert_false(turn.move(INF))
	assert_eq(turn.remaining_m(), 6.0)
