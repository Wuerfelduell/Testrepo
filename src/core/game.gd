extends Node
## CommandBus is the ONLY writer of game state. Scenes read snapshots and signals;
## they never change authoritative data directly. Rules never access presentation.

var _state: GameState = GameState.new()

var state: GameState:
	get:
		return _state.copy()

var mode: StringName:
	get:
		return _state.mode

## Internal CommandBus commit boundary, not an API for scenes.
func _commit_state(next_state: GameState) -> void:
	_state = next_state.copy()
