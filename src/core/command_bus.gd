extends Node

signal command_applied(command: Command, result: Dictionary)
signal command_rejected(command: Command, reason: Error)

var _submitting: bool = false

func submit(command: Command) -> Error:
	if command == null:
		command_rejected.emit(command, ERR_INVALID_PARAMETER)
		return ERR_INVALID_PARAMETER
	if _submitting:
		# Do not emit synchronously here: rejection listeners may submit again.
		command_rejected.emit.call_deferred(command, ERR_BUSY)
		return ERR_BUSY
	_submitting = true
	# Validation receives a separate snapshot: even a faulty validator cannot
	# mutate the authoritative state or the state that will be applied.
	var reason: Error = command.validate(Game.state)
	if reason != OK:
		command_rejected.emit(command, reason)
		_submitting = false
		return reason
	var next_state: GameState = Game.state
	var result: Dictionary = command.apply(next_state)
	Game._commit_state(next_state)
	command_applied.emit(command, result.duplicate(true))
	EventBus.state_changed.emit()
	_submitting = false
	return OK
