class_name AdvanceCombatCommand
extends Command
## Authoritative animation timeline, driven by local simulation only, never network input.

var delta: float = 0.0

func _init(p_delta: float = 0.0) -> void:
	delta = p_delta

func validate(state: GameState) -> Error:
	if not is_finite(delta) or delta <= 0.0 or delta > 60.0:
		return ERR_INVALID_PARAMETER
	if state.pending.get("type") == "reaction":
		# Time stands still until the reacting creature decides (CastReactionCommand).
		return ERR_BUSY
	return OK if not state.pending.is_empty() else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var events: Array[Dictionary] = []
	var remaining: float = delta
	# The bounded actor roster also bounds interruptions. Delta never skips an impact.
	while remaining > CombatRules.EPSILON and not state.pending.is_empty():
		var pending: Dictionary = state.pending
		if pending["type"] == "attack":
			var until_end: float = float(pending["duration"]) - float(pending["elapsed"])
			var consumed: float = minf(remaining, until_end)
			pending["elapsed"] = float(pending["elapsed"]) + consumed
			remaining -= consumed
			if not bool(pending["impacted"]) and float(pending["elapsed"]) + CombatRules.EPSILON >= float(pending["impact_time"]):
				pending["impacted"] = true
				events.append_array(CombatRules.resolve_impact(state, pending, Rng.rng))
				if state.pending.is_empty() or state.pending.get("type") == "reaction":
					break
			if float(pending["elapsed"]) + CombatRules.EPSILON >= float(pending["duration"]):
				state.pending = pending.get("resume", {})
				if not state.pending.is_empty() and not CombatRules.alive(state.actors[state.pending["actor_id"]]):
					state.pending = {}
		elif pending["type"] == "spell":
			var until_spell_end: float = float(pending["duration"]) - float(pending["elapsed"])
			var spent: float = minf(remaining, until_spell_end)
			pending["elapsed"] = float(pending["elapsed"]) + spent
			remaining -= spent
			if not bool(pending["impacted"]) and float(pending["elapsed"]) + CombatRules.EPSILON >= float(pending["impact_time"]):
				events.append_array(SpellResolver.resolve_impact(state, pending, Rng.rng))
				if state.pending.is_empty() or state.pending.get("type") == "reaction":
					break
			if float(pending["elapsed"]) + CombatRules.EPSILON >= float(pending["duration"]):
				state.pending = {}
		elif pending["type"] == "reaction":
			break
		else:
			var crossings: Array = pending["interruptions"]
			var distance: float = float(pending["distance"])
			var next_distance: float = float(pending["length"])
			if not crossings.is_empty():
				next_distance = float(crossings[0]["distance"])
			var consumed: float = minf(remaining, maxf(0.0, next_distance - distance) / CombatRules.WALK_SPEED_M_S)
			pending["elapsed"] = float(pending["elapsed"]) + consumed
			pending["distance"] = minf(next_distance, distance + consumed * CombatRules.WALK_SPEED_M_S)
			remaining -= consumed
			var mover_id: String = pending["actor_id"]
			state.actors[mover_id]["position"] = CombatRules.position_on_path(pending["path"], float(pending["distance"]))
			if not crossings.is_empty() and float(pending["distance"]) + CombatRules.EPSILON >= next_distance:
				var crossing: Dictionary = crossings.pop_front()
				var enemy_id: String = crossing["actor_id"]
				if bool(state.actors[enemy_id].get("reaction_available", false)) and \
						bool(CombatRules.attack_preview(state, enemy_id, mover_id, Vector3.INF, crossing["weapon"])["legal"]):
					state.actors[enemy_id]["reaction_available"] = false
					state.pending = CombatRules.attack_pending(enemy_id, mover_id, true, crossing["weapon"])
					state.pending["resume"] = pending
					events.append(CombatRules.attack_start_event(state.pending))
			elif float(pending["distance"]) + CombatRules.EPSILON >= float(pending["length"]):
				state.pending = {}
				events.append({"type": "move_end", "actor_id": mover_id})
	return {"events": events}
