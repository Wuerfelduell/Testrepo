class_name StartCombatCommand
extends Command
## Internal encounter transition. Never accepted from network CommandCodec.

func validate(state: GameState) -> Error:
	if state.mode != &"exploration":
		return ERR_UNAVAILABLE
	if not state.pending.is_empty() and state.pending.get("type") != "move":
		return ERR_BUSY
	var has_hero: bool = false
	var has_enemy: bool = false
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		if not CombatRules.alive(actor):
			continue
		if int(actor.get("dex", 0)) < 1 or int(actor.get("dex", 0)) > 30:
			return ERR_INVALID_DATA
		has_hero = has_hero or actor.get("team") == "hero"
		has_enemy = has_enemy or actor.get("team") == "enemy"
	return OK if has_hero and has_enemy else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var participants: Array[Initiative.Participant] = []
	var ids: Array = state.actors.keys()
	ids.sort()
	for id: String in ids:
		var actor: Dictionary = state.actors[id]
		if CombatRules.alive(actor):
			var participant: Initiative.Participant = Initiative.Participant.new(StringName(id), int(actor["dex"]))
			participant.context.conditions = CombatRules.conditions_for(actor)
			participants.append(participant)
	var initiative: Initiative.Result = Initiative.roll(participants, Rng.rng)
	var events: Array[Dictionary] = []
	state.pending = {}
	state.turn_order.clear()
	state.turn_index = 0
	state.round_number = 1
	state.mode = &"combat"
	for entry: Initiative.Entry in initiative.ordered:
		var id: String = String(entry.id)
		state.turn_order.append(id)
		events.append({"type": "roll", "kind": "initiative", "actor_id": id,
			"roll": CombatRules.serialize_roll(entry.roll)})
	events.append_array(CombatRules.begin_turn(state, state.current_actor_id()))
	return {"events": events, "turn_order": state.turn_order.duplicate(), "tie_breaks": initiative.tie_breaks}
