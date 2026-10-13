class_name PartyRegroupCommand
extends Command
## Internal (package K4): after a level loads, companions who stand off the walkable ground
## (e.g. around an area's arrival point) step to free spots next to the hero. Only the
## level scene submits it, once its navigation is ready; never accepted from the network.

func _init() -> void:
	super("hero")

func validate(state: GameState) -> Error:
	if state.mode != &"exploration" or not state.pending.is_empty():
		return ERR_UNAVAILABLE
	if not state.actors.has("hero") or not CombatRules.alive(state.actors["hero"]):
		return ERR_UNAVAILABLE
	return OK if not stranded(state).is_empty() else ERR_ALREADY_EXISTS

func apply(state: GameState) -> Dictionary:
	var events: Array[Dictionary] = []
	var hero: Vector3 = state.actors["hero"]["position"]
	for id: String in stranded(state):
		# Move the companion out of the way first so its own old spot never blocks.
		var was: Vector3 = state.actors[id]["position"]
		state.actors[id]["position"] = Vector3(0, -1000, 0)
		var spot: Vector3 = PartyRules.free_spot(state, hero, Vector3.FORWARD)
		if spot.is_equal_approx(hero):
			# No free spot next to the hero: at least stand on the nearest walkable point.
			spot = CombatSpace.current().closest_point(was)
		state.actors[id]["position"] = spot if spot.is_finite() else was
		events.append({"type": "party_regrouped", "actor_id": id, "position": state.actors[id]["position"]})
	return {"events": events}

## Living companions whose feet are not on the navigation mesh.
static func stranded(state: GameState) -> Array[String]:
	var result: Array[String] = []
	var space: CombatSpace = CombatSpace.current()
	for id: String in PartyRules.living_members(state):
		if id == "hero":
			continue
		var position: Vector3 = state.actors[id]["position"]
		var closest: Vector3 = space.closest_point(position)
		if not closest.is_finite() or Vector2(closest.x - position.x, closest.z - position.z).length() > 0.12 or \
				absf(closest.y - position.y) > 0.6:
			result.append(id)
	return result

func to_dict() -> Dictionary:
	return {"type": "party_regroup", "actor_id": actor_id}
