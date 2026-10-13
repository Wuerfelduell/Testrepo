class_name EncounterTriggerCommand
extends Command
## Internal: a dormant encounter noticed the hero (or hears a nearby fight). Its members
## become enemy actors. In exploration StartCombatCommand follows and rolls initiative
## for everyone; during combat the joiners roll their own initiative and enter the
## order at the end of the current round.

## Patrols move while unaware: the level passes where they are now (actor id -> Vector3).
var positions: Dictionary = {}

func _init(p_encounter_id: String = "", p_positions: Dictionary = {}) -> void:
	super(p_encounter_id)
	positions = p_positions.duplicate()

const PATROL_TOLERANCE_M: float = 0.75

func validate(state: GameState) -> Error:
	var dormant: Dictionary = state.world.get("dormant", {})
	if not dormant.has(actor_id) or (dormant[actor_id] as Dictionary).is_empty():
		return ERR_DOES_NOT_EXIST
	if not state.actors.has("hero") or not CombatRules.alive(state.actors["hero"]):
		return ERR_UNAVAILABLE
	if state.mode == &"exploration":
		if not state.pending.is_empty() and state.pending.get("type") != "move":
			return ERR_BUSY
	elif state.mode != &"combat" or not state.pending.is_empty():
		return ERR_BUSY
	for id: Variant in positions:
		var record: Dictionary = (dormant[actor_id] as Dictionary).get(String(id), {})
		var position: Variant = positions[id]
		if record.is_empty() or not position is Vector3 or not (position as Vector3).is_finite():
			return ERR_INVALID_DATA
		# Only a patrol can stand somewhere else than authored, and only on its route.
		if String(record.get("pose", "")) != "patrol" or \
				EncounterData.distance_to_route(record.get("patrol", []), position) > PATROL_TOLERANCE_M:
			return ERR_INVALID_DATA
	return OK

func apply(state: GameState) -> Dictionary:
	var dormant: Dictionary = state.world["dormant"]
	var members: Dictionary = dormant[actor_id]
	dormant.erase(actor_id)
	var triggered: Array = state.world.get("triggered", [])
	triggered.append(actor_id)
	state.world["triggered"] = triggered
	var ids: Array = members.keys()
	ids.sort()
	for id: String in ids:
		var record: Dictionary = members[id]
		if positions.has(id):
			record["position"] = positions[id]
		record.erase("patrol")
		record["pose"] = "aware"
		state.actors[id] = record
	var events: Array[Dictionary] = [{"type": "encounter_triggered", "encounter_id": actor_id,
		"actor_ids": ids, "joined_combat": state.mode == &"combat"}]
	if state.mode == &"combat":
		var participants: Array[Initiative.Participant] = []
		for id: String in ids:
			var participant: Initiative.Participant = Initiative.Participant.new(StringName(id), int(state.actors[id]["dex"]))
			participant.context.conditions = CombatRules.conditions_for(state.actors[id])
			participants.append(participant)
		var initiative: Initiative.Result = Initiative.roll(participants, Rng.rng)
		for entry: Initiative.Entry in initiative.ordered:
			state.turn_order.append(String(entry.id))
			events.append({"type": "roll", "kind": "initiative", "actor_id": String(entry.id),
				"roll": CombatRules.serialize_roll(entry.roll)})
	return {"events": events}

func to_dict() -> Dictionary:
	return {"type": "encounter_trigger", "actor_id": actor_id}
