class_name AttackCommand
extends Command

var target_id: String = ""

func _init(p_actor_id: String = "", p_target_id: String = "") -> void:
	actor_id = p_actor_id
	target_id = p_target_id

func validate(state: GameState) -> Error:
	var reason: Error = CombatRules.valid_actor_turn(state, actor_id)
	if reason != OK:
		return reason
	if not CombatRules.can_use_action(state.actors[actor_id]):
		return ERR_UNAVAILABLE
	if not bool(CombatRules.attack_preview(state, actor_id, target_id)["legal"]):
		return ERR_INVALID_PARAMETER
	return OK

func apply(state: GameState) -> Dictionary:
	state.actors[actor_id]["action_available"] = false
	state.pending = CombatRules.attack_pending(actor_id, target_id)
	return {"events": [CombatRules.attack_start_event(state.pending)]}

func to_dict() -> Dictionary:
	return {"type": "attack", "actor_id": actor_id, "target_id": target_id}

func from_dict(data: Dictionary) -> Error:
	if data.size() != 3 or data.get("type") != "attack" or not data.get("actor_id") is String or \
			not data.get("target_id") is String or String(data["actor_id"]).is_empty() or String(data["target_id"]).is_empty():
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	target_id = data["target_id"]
	return OK
