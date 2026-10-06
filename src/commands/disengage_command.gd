class_name DisengageCommand
extends Command

func validate(state: GameState) -> Error:
	var reason: Error = CombatRules.valid_actor_turn(state, actor_id)
	if reason != OK:
		return reason
	return OK if CombatRules.can_use_action(state.actors[actor_id]) else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	state.actors[actor_id]["action_available"] = false
	state.actors[actor_id]["disengaged"] = true
	return {"events": [{"type": "disengage", "actor_id": actor_id}]}

func to_dict() -> Dictionary:
	return {"type": "disengage", "actor_id": actor_id}
