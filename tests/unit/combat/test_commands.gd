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

class DetourSpace extends CombatSpace:
	func query_path(from: Vector3, to: Vector3) -> PackedVector3Array:
		return PackedVector3Array([from, Vector3(0, 0, 5), to])

var state: GameState
var observed_events: Array[Dictionary] = []

func actor(team: String, position: Vector3) -> Dictionary:
	return {"team": team, "position": position, "hp": 100, "max_hp": 100,
		"ac": 10, "dex": 14, "speed_m": 9.0, "move_left": 9.0,
		"action_available": true, "bonus_available": true, "reaction_available": true,
		"disengaged": false, "weapon": {"ranged": false, "reach": 1.5,
			"attack_bonus": 100, "damage_dice": "1d4", "damage_bonus": 3, "damage_type": "slashing"}}

func before_each() -> void:
	CombatSpace.active = null
	state = GameState.new()
	state.mode = &"combat"
	state.actors = {"hero": actor("hero", Vector3.ZERO), "enemy": actor("enemy", Vector3(1, 0, 0))}
	state.turn_order = ["hero", "enemy"]
	CommandBus.submit(Setup.new(state))
	Rng.set_seed(19)
	observed_events.clear()
	CommandBus.command_applied.connect(_collect)

func after_each() -> void:
	CommandBus.command_applied.disconnect(_collect)
	CommandBus.submit(Setup.new(GameState.new()))
	CombatSpace.active = null

func _collect(_command: Command, result: Dictionary) -> void:
	for event: Dictionary in result.get("events", []):
		observed_events.append(event)

func count_events(kind: String) -> int:
	var count: int = 0
	for event: Dictionary in observed_events:
		if event["type"] == kind:
			count += 1
	return count

func test_attack_reserves_action_but_applies_hp_and_rng_only_at_hit_frame_once() -> void:
	var before_rng: int = Rng.rng.state
	assert_eq(CommandBus.submit(AttackCommand.new("hero", "enemy")), OK)
	assert_eq(Game.state.actors["enemy"]["hp"], 100)
	assert_eq(Rng.rng.state, before_rng)
	assert_false(bool(Game.state.actors["hero"]["action_available"]))
	assert_eq(CommandBus.submit(EndTurnCommand.new("hero")), ERR_BUSY)
	CommandBus.submit(AdvanceCombatCommand.new(0.39))
	assert_eq(Game.state.actors["enemy"]["hp"], 100)
	CommandBus.submit(AdvanceCombatCommand.new(0.02))
	var hp: int = Game.state.actors["enemy"]["hp"]
	assert_lt(hp, 100)
	assert_eq(count_events("damage"), 1)
	CommandBus.submit(AdvanceCombatCommand.new(2.0))
	assert_eq(Game.state.actors["enemy"]["hp"], hp)
	assert_eq(count_events("damage"), 1)
	assert_true(Game.state.pending.is_empty())
	assert_eq(CommandBus.submit(AttackCommand.new("hero", "enemy")), ERR_UNAVAILABLE)

func test_move_uses_authoritative_detour_and_rejects_overspend_without_mutation() -> void:
	CombatSpace.active = DetourSpace.new()
	assert_eq(CommandBus.submit(MoveCommand.new("hero", Vector3(3, 0, 0))), ERR_UNAVAILABLE)
	assert_eq(Game.state.actors["hero"]["move_left"], 9.0)
	assert_eq(Game.state.actors["hero"]["position"], Vector3.ZERO)

func test_opportunity_attack_pauses_at_crossing_and_reaction_is_consumed_once() -> void:
	assert_eq(CommandBus.submit(MoveCommand.new("hero", Vector3(5, 0, 0))), OK)
	assert_eq(Game.state.actors["hero"]["move_left"], 4.0)
	assert_eq(Game.state.actors["hero"]["position"], Vector3.ZERO)
	CommandBus.submit(AdvanceCombatCommand.new(0.85))
	assert_eq(Game.state.pending["type"], "attack")
	assert_lt(Vector3(Game.state.actors["hero"]["position"]).distance_to(Vector3(2.5, 0, 0)), 0.00001)
	assert_false(bool(Game.state.actors["enemy"]["reaction_available"]))
	assert_eq(Game.state.actors["hero"]["hp"], 100)
	CommandBus.submit(AdvanceCombatCommand.new(4.0))
	assert_eq(Game.state.actors["hero"]["position"], Vector3(5, 0, 0))
	assert_eq(count_events("start_attack"), 1)
	assert_true(Game.state.pending.is_empty())

func test_disengage_prevents_oa_and_dash_spends_action_only_once() -> void:
	assert_eq(CommandBus.submit(DisengageCommand.new("hero")), OK)
	assert_eq(CommandBus.submit(DashCommand.new("hero")), ERR_UNAVAILABLE)
	assert_eq(CommandBus.submit(MoveCommand.new("hero", Vector3(5, 0, 0))), OK)
	CommandBus.submit(AdvanceCombatCommand.new(4.0))
	assert_eq(count_events("start_attack"), 0)
	assert_eq(Game.state.actors["hero"]["hp"], 100)
	CommandBus.submit(EndTurnCommand.new("hero"))
	assert_eq(CommandBus.submit(DashCommand.new("enemy")), OK)
	assert_eq(Game.state.actors["enemy"]["move_left"], 18.0)
	assert_eq(CommandBus.submit(DashCommand.new("enemy")), ERR_UNAVAILABLE)

func test_end_turn_skips_dead_and_resets_only_starting_actor_reaction() -> void:
	state.actors["dead"] = actor("enemy", Vector3(2, 0, 0))
	state.actors["dead"]["hp"] = 0
	state.actors["hero"]["reaction_available"] = false
	state.actors["enemy"]["reaction_available"] = false
	state.turn_order = ["hero", "dead", "enemy"]
	CommandBus.submit(Setup.new(state))
	assert_eq(CommandBus.submit(EndTurnCommand.new("hero")), OK)
	assert_eq(Game.state.current_actor_id(), "enemy")
	assert_true(bool(Game.state.actors["enemy"]["reaction_available"]))
	assert_false(bool(Game.state.actors["hero"]["reaction_available"]))
	CommandBus.submit(EndTurnCommand.new("enemy"))
	assert_eq(Game.state.round_number, 2)
	assert_true(bool(Game.state.actors["hero"]["reaction_available"]))

func test_last_enemy_death_returns_to_exploration_at_impact() -> void:
	state.actors["enemy"]["hp"] = 1
	CommandBus.submit(Setup.new(state))
	CommandBus.submit(AttackCommand.new("hero", "enemy"))
	CommandBus.submit(AdvanceCombatCommand.new(0.4))
	assert_eq(Game.mode, &"exploration")
	assert_eq(Game.state.actors["enemy"]["hp"], 0)
	assert_eq(count_events("death"), 1)
	assert_eq(count_events("combat_end"), 1)
	assert_true(Game.state.pending.is_empty())

func test_lethal_opportunity_attack_stops_move_and_ends_run() -> void:
	state.actors["hero"]["hp"] = 1
	CommandBus.submit(Setup.new(state))
	CommandBus.submit(MoveCommand.new("hero", Vector3(5, 0, 0)))
	CommandBus.submit(AdvanceCombatCommand.new(4.0))
	assert_eq(Game.mode, &"defeat")
	assert_lt(Vector3(Game.state.actors["hero"]["position"]).distance_to(Vector3(2.5, 0, 0)), 0.00001)
	assert_true(Game.state.pending.is_empty())

func test_start_combat_interrupts_exploration_motion_and_serializes_each_initiative_roll() -> void:
	state.mode = &"exploration"
	state.turn_order.clear()
	CommandBus.submit(Setup.new(state))
	CommandBus.submit(MoveCommand.new("hero", Vector3(0, 0, 5)))
	CommandBus.submit(AdvanceCombatCommand.new(0.2))
	var position: Vector3 = Game.state.actors["hero"]["position"]
	assert_eq(CommandBus.submit(StartCombatCommand.new()), OK)
	assert_eq(Game.mode, &"combat")
	assert_eq(Game.state.actors["hero"]["position"], position)
	assert_true(Game.state.pending.is_empty())
	assert_eq(Game.state.turn_order.size(), 2)
	assert_eq(count_events("roll"), 2)

func test_command_codec_accepts_actions_but_never_paths_dice_cover_or_internal_ticks() -> void:
	var originals: Array[Command] = [MoveCommand.new("hero", Vector3(2, 1, 3)),
		AttackCommand.new("hero", "enemy"), DashCommand.new("hero"), DisengageCommand.new("hero")]
	for original: Command in originals:
		var data: Dictionary = JSON.parse_string(JSON.stringify(original.to_dict()))
		var decoded: Command = CommandCodec.decode(data)
		assert_not_null(decoded)
		assert_eq(decoded.to_dict(), original.to_dict())
		data["cover"] = 0
		assert_null(CommandCodec.decode(data))
	for data: Dictionary in [{"type": "advance_combat", "delta": 1.0},
		{"type": "start_combat"}, {"type": "move", "actor_id": "hero", "destination": [1, 2]},
		{"type": "move", "actor_id": "hero", "destination": [1, "2", 3]},
		{"type": "attack", "actor_id": "hero", "target_id": "enemy", "dice": 20}]:
		assert_null(CommandCodec.decode(data))

func test_pending_snapshot_cannot_mutate_authoritative_timeline() -> void:
	CommandBus.submit(AttackCommand.new("hero", "enemy"))
	var snapshot: GameState = Game.state
	snapshot.pending["elapsed"] = 100.0
	assert_eq(Game.state.pending["elapsed"], 0.0)

func test_arena_setup_is_internal_one_shot_and_never_revives_defeated_run() -> void:
	CommandBus.submit(Setup.new(GameState.new()))
	assert_eq(CommandBus.submit(SetupArenaCommand.new()), OK)
	assert_eq(Game.state.actors.size(), 4)
	assert_eq(Game.state.actors["hero"]["hp"], 12)
	assert_eq(Game.state.actors["hero"]["ac"], 18)
	assert_eq(CommandBus.submit(SetupArenaCommand.new()), ERR_ALREADY_IN_USE)
	var defeated: GameState = GameState.new()
	defeated.mode = &"defeat"
	CommandBus.submit(Setup.new(defeated))
	assert_eq(CommandBus.submit(SetupArenaCommand.new()), ERR_ALREADY_IN_USE)
	assert_null(CommandCodec.decode(SetupArenaCommand.new().to_dict()))

func test_typed_flat_damage_rider_is_separate_and_not_critical_doubled() -> void:
	state.actors["hero"]["weapon"]["extra_damage"] = [{"amount": 1, "damage_type": "necrotic", "source": "ritual_sickle"}]
	state.actors["enemy"]["conditions"] = ["unconscious"]
	state.actors["enemy"]["resistances"] = ["slashing"]
	CommandBus.submit(Setup.new(state))
	CommandBus.submit(AttackCommand.new("hero", "enemy"))
	CommandBus.submit(AdvanceCombatCommand.new(0.4))
	var necrotic: int = 0
	for event: Dictionary in observed_events:
		if event["type"] == "damage" and event["damage_type"] == "necrotic":
			necrotic += int(event["amount"])
	assert_eq(necrotic, 1)
	assert_eq(count_events("damage"), 2)
