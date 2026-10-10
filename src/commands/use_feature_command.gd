class_name UseFeatureCommand
extends Command
## Level-1 class features that are actions of their own: Fighter Second Wind
## (bonus action) and Wizard Arcane Recovery (only during a short rest, which
## does not exist yet, so it is validated and tested but never available in play).

const FEATURES: Array[String] = ["second_wind", "arcane_recovery"]

var feature_id: String = ""
var slot_levels: Array[int] = []

func _init(p_actor_id: String = "", p_feature_id: String = "", p_slot_levels: Array[int] = []) -> void:
	actor_id = p_actor_id
	feature_id = p_feature_id
	slot_levels = p_slot_levels.duplicate()

func validate(state: GameState) -> Error:
	if not feature_id in FEATURES:
		return ERR_INVALID_PARAMETER
	if not state.actors.has(actor_id):
		return ERR_INVALID_PARAMETER
	var actor: Dictionary = state.actors[actor_id]
	var feature: Dictionary = actor.get("features", {}).get(feature_id, {})
	if feature.is_empty():
		return ERR_UNAVAILABLE
	match feature_id:
		"second_wind":
			var reason: Error = CombatRules.valid_actor_turn(state, actor_id)
			if reason != OK:
				return reason
			if not bool(actor.get("bonus_available", false)) or not CombatRules.conditions_for(actor).can_act() \
					or int(feature.get("uses", 0)) <= 0:
				return ERR_UNAVAILABLE
		"arcane_recovery":
			if state.mode != &"short_rest" or bool(feature.get("used", false)):
				return ERR_UNAVAILABLE
			var slots: Array = actor.get("spell_slots", []).duplicate()
			if not SpellRules.arcane_recovery(slots, actor.get("spell_slots_max", []), int(actor.get("level", 1)), slot_levels):
				return ERR_INVALID_PARAMETER
	return OK

func apply(state: GameState) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	var feature: Dictionary = actor["features"][feature_id]
	var events: Array[Dictionary] = []
	match feature_id:
		"second_wind":
			actor["bonus_available"] = false
			feature["uses"] = int(feature["uses"]) - 1
			var roll: DiceResult = Dice.roll(SpellRules.second_wind_expression(int(actor.get("level", 1))), Rng.rng)
			var healed: int = mini(roll.total, int(actor["max_hp"]) - int(actor["hp"]))
			actor["hp"] = int(actor["hp"]) + healed
			events.append({"type": "roll", "kind": "healing", "actor_id": actor_id, "target_id": actor_id,
				"feature_id": feature_id, "roll": CombatRules.serialize_roll(roll), "amount": healed})
			events.append({"type": "heal", "actor_id": actor_id, "target_id": actor_id, "amount": healed, "hp": actor["hp"]})
		"arcane_recovery":
			SpellRules.arcane_recovery(actor["spell_slots"], actor["spell_slots_max"], int(actor.get("level", 1)), slot_levels)
			feature["used"] = true
			events.append({"type": "feature", "actor_id": actor_id, "feature_id": feature_id})
	return {"events": events}

func to_dict() -> Dictionary:
	return {"type": "use_feature", "actor_id": actor_id, "feature_id": feature_id, "slot_levels": slot_levels.duplicate()}

func from_dict(data: Dictionary) -> Error:
	if data.size() != 4 or data.get("type") != "use_feature" or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("feature_id") is String or \
			not String(data["feature_id"]) in FEATURES or not data.get("slot_levels") is Array:
		return ERR_INVALID_DATA
	var levels: Array = data["slot_levels"]
	if levels.size() > 9:
		return ERR_INVALID_DATA
	var parsed: Array[int] = []
	for value: Variant in levels:
		if not (value is int or value is float) or float(value) != floorf(float(value)) or int(value) < 1 or int(value) > 9:
			return ERR_INVALID_DATA
		parsed.append(int(value))
	actor_id = data["actor_id"]
	feature_id = data["feature_id"]
	slot_levels = parsed
	return OK
