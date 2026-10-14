class_name CastSpellCommand
extends Command
## Spends the casting time and slot now; damage and saves happen when the effect
## arrives on the timeline (AdvanceCombatCommand -> SpellResolver.resolve_impact).

var spell_id: String = ""
## 0 picks the lowest available slot that can cast the spell.
var slot_level: int = 0
var target_ids: Array[String] = []
var point: Vector3 = Vector3.INF

func _init(p_actor_id: String = "", p_spell_id: String = "", p_target_ids: Array = [],
		p_point: Vector3 = Vector3.INF, p_slot_level: int = 0) -> void:
	actor_id = p_actor_id
	spell_id = p_spell_id
	target_ids.assign(p_target_ids)
	point = p_point
	slot_level = p_slot_level

func validate(state: GameState) -> Error:
	var reason: Error = CombatRules.valid_actor_turn(state, actor_id)
	if reason != OK:
		return reason
	var spell: SpellDefinition = SpellBook.get_spell(spell_id)
	if spell == null or spell.casting_time == "reaction":
		return ERR_INVALID_PARAMETER
	if not SpellResolver.availability_reason(state, actor_id, spell, slot_level).is_empty():
		return ERR_UNAVAILABLE
	if not bool(SpellResolver.preview(state, actor_id, spell_id, slot_level, target_ids, point)["legal"]):
		return ERR_INVALID_PARAMETER
	return OK

func apply(state: GameState) -> Dictionary:
	var spell: SpellDefinition = SpellBook.get_spell(spell_id)
	var caster: Dictionary = state.actors[actor_id]
	var events: Array[Dictionary] = []
	# Class free casts (Ranger Favored Enemy: Hunter's Mark) are used before slots.
	var free_cast: bool = slot_level == 0 and ClassKits.free_cast_available(caster, spell_id)
	var used_slot: int = SpellResolver.effective_slot(caster, spell, slot_level)
	# Casting a spell ends hiding (SRD 5.2 Hide).
	if ActiveEffects.remove_where(caster, func(effect: Dictionary) -> bool:
			return String(effect.get("kind", "")) == ActiveEffects.HIDDEN) > 0:
		events.append({"type": "hidden_end", "actor_id": actor_id, "reason": "spell"})
	match SpellResolver.casting_time(caster, spell):
		"action": caster["action_available"] = false
		"bonus_action": caster["bonus_available"] = false
	if spell.is_feature():
		ClassEffects.spend_resource(state, caster, spell)
	elif SpellResolver.free_cast(caster, spell):
		# Divine Intervention: this one spell needs no slot.
		var intervention: Dictionary = caster["features"]["divine_intervention"]
		intervention["armed"] = false
		intervention["uses"] = maxi(0, int(intervention.get("uses", 0)) - 1)
	elif caster.get("spell_uses", {}).has(spell_id):
		caster["spell_uses"][spell_id] = int(caster["spell_uses"][spell_id]) - 1
	elif free_cast:
		ClassKits.spend_free_cast(caster, spell_id)
	elif used_slot > 0:
		SpellRules.spend_slot(caster["spell_slots"], used_slot)
	if spell.concentration:
		# A new concentration spell ends the previous one.
		events.append_array(ActiveEffects.end_concentration(state, actor_id, "new_spell"))
		caster["concentration"] = {"spell_id": spell_id, "rounds_left": spell.duration_rounds, "slot_level": used_slot}
	state.pending = SpellResolver.cast_pending(state, actor_id, spell, used_slot, target_ids, point)
	# Armed Metamagic is spent on this spell (the pending keeps it for the impact).
	caster.erase("metamagic")
	events.append(SpellResolver.start_event(state.pending))
	return {"events": events}

func to_dict() -> Dictionary:
	return {"type": "cast_spell", "actor_id": actor_id, "spell_id": spell_id, "slot_level": slot_level,
		"target_ids": target_ids.duplicate(), "point": [point.x, point.y, point.z] if point.is_finite() else []}

func from_dict(data: Dictionary) -> Error:
	if data.size() != 6 or data.get("type") != "cast_spell" or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("spell_id") is String or \
			not (data.get("slot_level") is int or data.get("slot_level") is float) or \
			not data.get("target_ids") is Array or not data.get("point") is Array:
		return ERR_INVALID_DATA
	var level: float = float(data["slot_level"])
	if level != floorf(level) or level < 0 or level > 9:
		return ERR_INVALID_DATA
	var ids: Array = data["target_ids"]
	if ids.size() > 16:
		return ERR_INVALID_DATA
	for value: Variant in ids:
		if not value is String or String(value).is_empty():
			return ERR_INVALID_DATA
	var values: Array = data["point"]
	var parsed_point: Vector3 = Vector3.INF
	if not values.is_empty():
		if values.size() != 3:
			return ERR_INVALID_DATA
		for value: Variant in values:
			if not (value is float or value is int) or not is_finite(float(value)):
				return ERR_INVALID_DATA
		parsed_point = Vector3(float(values[0]), float(values[1]), float(values[2]))
	actor_id = data["actor_id"]
	spell_id = data["spell_id"]
	slot_level = int(level)
	target_ids.assign(ids)
	point = parsed_point
	return OK
