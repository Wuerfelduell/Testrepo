class_name CastReactionCommand
extends Command
## Answers a reaction offer (currently Shield). The paused attack or Magic Missile
## resumes immediately with the decision applied.

var accept: bool = false

func _init(p_actor_id: String = "", p_accept: bool = false) -> void:
	actor_id = p_actor_id
	accept = p_accept

func validate(state: GameState) -> Error:
	if not state.actors.has(actor_id):
		return ERR_INVALID_PARAMETER
	if state.pending.get("type") != "reaction":
		return ERR_UNAVAILABLE
	if String(state.pending.get("actor_id", "")) != actor_id:
		return ERR_UNAUTHORIZED
	if accept and not SpellResolver.shield_option(state, actor_id):
		return ERR_UNAVAILABLE
	return OK

func apply(state: GameState) -> Dictionary:
	var offer: Dictionary = state.pending
	var trigger: Dictionary = offer.get("trigger", {})
	var events: Array[Dictionary] = []
	var reactor: Dictionary = state.actors[actor_id]
	if accept:
		var spell: SpellDefinition = SpellBook.get_spell("shield")
		var slot: int = SpellRules.lowest_slot(reactor["spell_slots"], spell.level)
		SpellRules.spend_slot(reactor["spell_slots"], slot)
		reactor["reaction_available"] = false
		ActiveEffects.add(reactor, {"kind": "shield", "amount": int(spell.effect_amount), "source_id": actor_id,
			"spell_id": "shield", "until": "start_of_turn", "turn_of": actor_id})
		events.append({"type": "cast_reaction", "actor_id": actor_id, "spell_id": "shield", "slot_level": slot})
	else:
		events.append({"type": "reaction_declined", "actor_id": actor_id})
	state.pending = offer.get("resume", {})
	if trigger.has("attack"):
		var outcome: Dictionary = trigger["attack"].duplicate(true)
		if accept:
			# Offered only when +5 AC turns this exact roll into a miss.
			outcome["armor_class"] = int(outcome["armor_class"]) + int(SpellBook.get_spell("shield").effect_amount)
			outcome["hit"] = false
			outcome["critical"] = false
		events.append_array(CombatRules.finish_attack(state, String(offer["attacker_id"]),
			String(trigger["target_id"]), trigger["weapon"], outcome, Rng.rng))
	return {"events": events}

func to_dict() -> Dictionary:
	return {"type": "cast_reaction", "actor_id": actor_id, "accept": accept}

func from_dict(data: Dictionary) -> Error:
	if data.size() != 3 or data.get("type") != "cast_reaction" or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("accept") is bool:
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	accept = data["accept"]
	return OK
