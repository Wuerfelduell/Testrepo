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
	var actor: Dictionary = state.actors[actor_id]
	if not CombatRules.can_use_action(actor) and \
			not (int(actor.get("attacks_left", 0)) > 0 and CombatRules.conditions_for(actor).can_act()):
		return ERR_UNAVAILABLE
	if not bool(CombatRules.attack_preview(state, actor_id, target_id)["legal"]):
		return ERR_INVALID_PARAMETER
	return OK

func apply(state: GameState) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	if bool(actor.get("action_available", false)):
		# Extra Attack (Fighter 5): the Attack action holds more than one attack.
		actor["action_available"] = false
		actor["attacks_left"] = ClassFeatures.attacks_per_action(actor) - 1
	else:
		actor["attacks_left"] = int(actor["attacks_left"]) - 1
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
