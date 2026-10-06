class_name DashCommand
extends Command

func validate(state: GameState) -> Error:
	var reason: Error = CombatRules.valid_actor_turn(state, actor_id)
	if reason != OK:
		return reason
	return OK if CombatRules.can_use_action(state.actors[actor_id]) else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	actor["action_available"] = false
	if not CombatRules.conditions_for(actor).speed_is_zero():
		actor["move_left"] = float(actor["move_left"]) + float(actor["speed_m"])
	return {"events": [{"type": "dash", "actor_id": actor_id}]}

func to_dict() -> Dictionary:
	return {"type": "dash", "actor_id": actor_id}
