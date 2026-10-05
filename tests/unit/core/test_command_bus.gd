extends GutTest

class SetupCommand extends Command:
	func validate(_state: GameState) -> Error:
		return OK

	func apply(state: GameState) -> Dictionary:
		state.actors = {"hero": {"hp": 12, "position": Vector3.ZERO},
			"companion": {"hp": 9, "position": Vector3.ONE}}
		state.turn_order = ["hero", "companion"]
		state.turn_index = 0
		state.round_number = 1
		return {}

class BadValidator extends Command:
	func validate(state: GameState) -> Error:
		state.actors["hero"]["hp"] = 0
		return ERR_INVALID_DATA

class MutatingValidator extends Command:
	func validate(state: GameState) -> Error:
		state.actors["hero"]["hp"] = 0
		return OK

func before_each() -> void:
	CommandBus.submit(SetupCommand.new())
	watch_signals(CommandBus)
	watch_signals(EventBus)

func test_valid_command_advances_turn_and_notifies_after_commit() -> void:
	var command: EndTurnCommand = EndTurnCommand.new("hero")
	assert_eq(CommandBus.submit(command), OK)
	assert_eq(Game.state.current_actor_id(), "companion")
	assert_eq(Game.state.round_number, 1)
	assert_signal_emitted_with_parameters(CommandBus, "command_applied", [command,
		{"previous_actor_id": "hero", "actor_id": "companion", "round_number": 1}])
	assert_signal_emitted(EventBus, "state_changed")
	assert_signal_not_emitted(CommandBus, "command_rejected")

func test_turn_wrap_increments_round() -> void:
	CommandBus.submit(EndTurnCommand.new("hero"))
	CommandBus.submit(EndTurnCommand.new("companion"))
	assert_eq(Game.state.current_actor_id(), "hero")
	assert_eq(Game.state.round_number, 2)

func test_wrong_actor_is_rejected_without_state_change() -> void:
	var command: EndTurnCommand = EndTurnCommand.new("companion")
	assert_eq(CommandBus.submit(command), ERR_UNAUTHORIZED)
	assert_eq(Game.state.current_actor_id(), "hero")
	assert_eq(Game.state.round_number, 1)
	assert_signal_emitted_with_parameters(CommandBus, "command_rejected", [command, ERR_UNAUTHORIZED])
	assert_signal_not_emitted(CommandBus, "command_applied")
	assert_signal_not_emitted(EventBus, "state_changed")

func test_unknown_actor_null_and_base_commands_are_rejected() -> void:
	assert_eq(CommandBus.submit(EndTurnCommand.new("unknown")), ERR_INVALID_PARAMETER)
	assert_eq(CommandBus.submit(null), ERR_INVALID_PARAMETER)
	assert_eq(CommandBus.submit(Command.new("hero")), ERR_UNAVAILABLE)
	assert_eq(Game.state.current_actor_id(), "hero")

func test_validation_cannot_change_authoritative_or_applied_state() -> void:
	assert_eq(CommandBus.submit(BadValidator.new()), ERR_INVALID_DATA)
	assert_eq(Game.state.actors["hero"]["hp"], 12)
	assert_eq(CommandBus.submit(MutatingValidator.new()), OK)
	assert_eq(Game.state.actors["hero"]["hp"], 12)

func test_presentation_snapshot_cannot_mutate_game() -> void:
	var snapshot: GameState = Game.state
	snapshot.actors["hero"]["hp"] = 0
	snapshot.turn_order.clear()
	assert_eq(Game.state.actors["hero"]["hp"], 12)
	assert_eq(Game.state.current_actor_id(), "hero")

func test_serialized_command_round_trips_through_json() -> void:
	var original: EndTurnCommand = EndTurnCommand.new("hero")
	var data: Dictionary = JSON.parse_string(JSON.stringify(original.to_dict()))
	var decoded: Command = CommandCodec.decode(data)
	assert_not_null(decoded)
	assert_eq(decoded.to_dict(), original.to_dict())
	assert_eq(CommandBus.submit(decoded), OK)
	assert_eq(Game.state.current_actor_id(), "companion")

func test_malformed_network_data_is_rejected() -> void:
	for data: Dictionary in [{}, {"type": "res://evil.gd", "actor_id": "hero"},
		{"type": "end_turn", "actor_id": 2}, {"type": "end_turn", "actor_id": ""},
		{"type": "end_turn", "actor_id": "hero", "extra": true}]:
		assert_null(CommandCodec.decode(data))

func test_invalid_turn_order_is_rejected() -> void:
	var state: GameState = GameState.new()
	state.actors = {"hero": {}}
	var command: EndTurnCommand = EndTurnCommand.new("hero")
	assert_ne(command.validate(state), OK)
	state.turn_order = ["hero", "missing"]
	assert_eq(command.validate(state), ERR_INVALID_DATA)
	state.turn_order = ["hero"]
	state.turn_index = -1
	assert_ne(command.validate(state), OK)

func test_signal_observer_sees_committed_state_and_cannot_reenter() -> void:
	var observed: Array[String] = []
	var reentrant_results: Array[int] = []
	var listener: Callable = func(_command: Command, _result: Dictionary) -> void:
		observed.append(Game.state.current_actor_id())
		reentrant_results.append(CommandBus.submit(EndTurnCommand.new("companion")))
	CommandBus.command_applied.connect(listener)
	CommandBus.submit(EndTurnCommand.new("hero"))
	CommandBus.command_applied.disconnect(listener)
	assert_eq(observed, ["companion"])
	assert_eq(reentrant_results, [ERR_BUSY])
	assert_eq(Game.state.current_actor_id(), "companion")
	await get_tree().process_frame
	assert_signal_emitted(CommandBus, "command_rejected")
