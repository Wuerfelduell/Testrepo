class_name EndTurnCommand
extends Command
## Minimal turn-order example only; no combat actions or rules yet.

func validate(state: GameState) -> Error:
	if actor_id.is_empty() or not state.actors.has(actor_id):
		return ERR_INVALID_PARAMETER
	if state.turn_order.is_empty() or state.current_actor_id() != actor_id:
		return ERR_UNAUTHORIZED
	for id: String in state.turn_order:
		if not state.actors.has(id):
			return ERR_INVALID_DATA
	return OK

func apply(state: GameState) -> Dictionary:
	state.turn_index = (state.turn_index + 1) % state.turn_order.size()
	if state.turn_index == 0:
		state.round_number += 1
	return {"previous_actor_id": actor_id, "actor_id": state.current_actor_id(),
		"round_number": state.round_number}

func to_dict() -> Dictionary:
	return {"type": "end_turn", "actor_id": actor_id}
