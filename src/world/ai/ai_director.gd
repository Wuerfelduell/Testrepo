class_name AIDirector
extends RefCounted
## The arena schedules decisions after animations; it never mutates actor data.

var last_candidates: Array[Dictionary] = []
var last_actor_id: String = ""

func decide(state: GameState, tactical_points: Array[Vector3] = []) -> Command:
	if state == null or state.mode != &"combat" or not state.pending.is_empty():
		return null
	var actor_id: String = state.current_actor_id()
	if not state.actors.has(actor_id) or state.actors[actor_id].get("team", "") != "enemy":
		return null
	last_actor_id = actor_id
	last_candidates = UtilityAI.consider(state, actor_id, tactical_points)
	if last_candidates.is_empty():
		return null
	return UtilityAI.command_for(last_candidates[0], actor_id)

func submit_turn(tactical_points: Array[Vector3] = []) -> Error:
	var command: Command = decide(Game.state, tactical_points)
	return CommandBus.submit(command) if command != null else ERR_UNAVAILABLE
