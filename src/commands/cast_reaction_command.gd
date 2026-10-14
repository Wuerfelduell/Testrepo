class_name CastReactionCommand
extends Command
## Answers a reaction offer: Shield, or a class reaction that halves a hit's damage (Rogue
## Uncanny Dodge). The paused attack or Magic Missile resumes immediately with the decision applied.

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
	if accept and not available(state):
		return ERR_UNAVAILABLE
	return OK

## Whether the offered reaction can still be taken.
func available(state: GameState) -> bool:
	var offer: Dictionary = state.pending
	if String(offer.get("reaction", "shield")) == "shield":
		return SpellResolver.shield_option(state, actor_id)
	var trigger: Dictionary = offer.get("trigger", {})
	return bool(state.actors[actor_id].get("reaction_available", false)) and \
		ClassKits.damage_halved_by(state, String(offer.get("attacker_id", "")), actor_id, trigger.get("weapon", {})) == String(offer["reaction"])

## The answer the game gives for creatures the player does not control: always take it.
static func auto_accept(state: GameState, reactor_id: String) -> bool:
	if String(state.pending.get("reaction", "shield")) == "shield":
		return SpellResolver.shield_option(state, reactor_id)
	var command: CastReactionCommand = CastReactionCommand.new(reactor_id, true)
	return command.available(state)

func apply(state: GameState) -> Dictionary:
	var offer: Dictionary = state.pending
	var trigger: Dictionary = offer.get("trigger", {})
	var events: Array[Dictionary] = []
	var reactor: Dictionary = state.actors[actor_id]
	var reaction: String = String(offer.get("reaction", "shield"))
	if reaction != "shield":
		# Uncanny Dodge: the reaction halves the damage of this hit.
		state.pending = offer.get("resume", {})
		var halved: Dictionary = trigger["attack"].duplicate(true)
		if accept:
			reactor["reaction_available"] = false
			halved["halved_by"] = reaction
			events.append({"type": "feature", "actor_id": actor_id, "feature_id": reaction,
				"source_id": String(offer["attacker_id"])})
		else:
			events.append({"type": "reaction_declined", "actor_id": actor_id})
		events.append_array(CombatRules.finish_attack(state, String(offer["attacker_id"]),
			String(trigger["target_id"]), trigger["weapon"], halved, Rng.rng))
		return {"events": events}
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
