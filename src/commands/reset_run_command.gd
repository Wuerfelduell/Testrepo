class_name ResetRunCommand
extends Command
## Internal: clears the run when the player returns to the main menu or starts anew.

func _init() -> void:
	super("game")

func validate(_state: GameState) -> Error:
	return OK

func apply(state: GameState) -> Dictionary:
	state.actors = {}
	state.pending = {}
	state.turn_order.clear()
	state.turn_index = 0
	state.round_number = 1
	state.mode = &"exploration"
	return {"events": [{"type": "run_reset"}]}

func to_dict() -> Dictionary:
	return {"type": "reset_run", "actor_id": actor_id}
