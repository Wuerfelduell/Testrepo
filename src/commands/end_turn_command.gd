class_name EndTurnCommand
extends Command

func validate(state: GameState) -> Error:
	if actor_id.is_empty() or not state.actors.has(actor_id):
		return ERR_INVALID_PARAMETER
	if state.turn_order.is_empty() or state.current_actor_id() != actor_id:
		return ERR_UNAUTHORIZED
	for id: String in state.turn_order:
		if not state.actors.has(id):
			return ERR_INVALID_DATA
	if state.mode == &"defeat":
		return ERR_UNAVAILABLE
	if not state.pending.is_empty():
		return ERR_BUSY
	if state.mode == &"combat" and not CombatRules.alive(state.actors[actor_id]):
		return ERR_UNAVAILABLE
	return OK

func apply(state: GameState) -> Dictionary:
	var events: Array[Dictionary] = []
	if state.mode == &"combat":
		events.append_array(ActiveEffects.on_turn_end(state, actor_id, Rng.rng))
	for index: int in range(state.turn_order.size()):
		state.turn_index = (state.turn_index + 1) % state.turn_order.size()
		if state.turn_index == 0:
			state.round_number += 1
		if state.mode != &"combat" or CombatRules.alive(state.actors[state.current_actor_id()]):
			break
	if state.mode == &"combat":
		events.append_array(CombatRules.begin_turn(state, state.current_actor_id()))
	var result: Dictionary = {"previous_actor_id": actor_id, "actor_id": state.current_actor_id(),
		"round_number": state.round_number}
	if not events.is_empty():
		result["events"] = events
	return result

func to_dict() -> Dictionary:
	return {"type": "end_turn", "actor_id": actor_id}
