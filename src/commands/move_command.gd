class_name MoveCommand
extends Command
## Reserve the complete approved route immediately; positions advance on the timeline.
## If an opportunity attack kills the mover, untraveled reserved budget is irrelevant.

var destination: Vector3 = Vector3.ZERO

func _init(p_actor_id: String = "", p_destination: Vector3 = Vector3.ZERO) -> void:
	actor_id = p_actor_id
	destination = p_destination

func validate(state: GameState) -> Error:
	if not state.actors.has(actor_id) or not destination.is_finite():
		return ERR_INVALID_PARAMETER
	var actor: Dictionary = state.actors[actor_id]
	if not CombatRules.alive(actor) or CombatRules.conditions_for(actor).speed_is_zero():
		return ERR_UNAVAILABLE
	if state.mode == &"combat":
		var reason: Error = CombatRules.valid_actor_turn(state, actor_id)
		if reason != OK:
			return reason
	elif state.mode != &"exploration" or actor.get("team") != "hero":
		return ERR_UNAUTHORIZED
	elif not state.pending.is_empty():
		return ERR_BUSY
	var path: PackedVector3Array = CombatRules.movement_path(state, actor_id, destination)
	if path.is_empty() or CombatRules.path_length(path) <= CombatRules.EPSILON:
		return ERR_INVALID_DATA
	if state.mode == &"combat" and CombatRules.move_cost(actor, path) > float(actor.get("move_left", 0.0)) + CombatRules.EPSILON:
		return ERR_UNAVAILABLE
	return OK

func apply(state: GameState) -> Dictionary:
	var path: PackedVector3Array = CombatRules.movement_path(state, actor_id, destination)
	var cost: float = CombatRules.move_cost(state.actors[actor_id], path)
	var crossings: Array[Dictionary] = []
	if state.mode == &"combat":
		state.actors[actor_id]["move_left"] = maxf(0.0, float(state.actors[actor_id]["move_left"]) - cost)
		crossings = CombatRules.opportunity_crossings(state, actor_id, path)
	var length: float = CombatRules.path_length(path)
	state.pending = {"type": "move", "actor_id": actor_id, "path": path,
		"elapsed": 0.0, "duration": length / CombatRules.WALK_SPEED_M_S,
		"distance": 0.0, "length": length, "interruptions": crossings}
	return {"events": [{"type": "start_move", "actor_id": actor_id, "path": path, "cost": cost}]}

func to_dict() -> Dictionary:
	return {"type": "move", "actor_id": actor_id, "destination": [destination.x, destination.y, destination.z]}

func from_dict(data: Dictionary) -> Error:
	if data.size() != 3 or data.get("type") != "move" or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("destination") is Array:
		return ERR_INVALID_DATA
	var values: Array = data["destination"]
	if values.size() != 3:
		return ERR_INVALID_DATA
	for value: Variant in values:
		if not (value is float or value is int) or not is_finite(float(value)):
			return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	destination = Vector3(float(values[0]), float(values[1]), float(values[2]))
	return OK
