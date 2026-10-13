class_name LevelUpCommand
extends Command
## One level for a hero whose XP crossed the next threshold, with every choice the
## level asks for (see ProgressionRules.plan). Only outside combat.

var choices: Dictionary = {}

func _init(p_actor_id: String = "", p_choices: Dictionary = {}) -> void:
	actor_id = p_actor_id
	choices = p_choices.duplicate(true)

func validate(state: GameState) -> Error:
	if not state.actors.has(actor_id):
		return ERR_INVALID_PARAMETER
	if state.mode != &"exploration" or not state.pending.is_empty():
		return ERR_UNAVAILABLE
	var reason: String = ProgressionRules.validate(state.actors[actor_id], choices)
	if reason == "LEVELUP_REASON_NOT_READY":
		return ERR_UNAVAILABLE
	return OK if reason.is_empty() else ERR_INVALID_PARAMETER

func apply(state: GameState) -> Dictionary:
	return {"events": ProgressionRules.apply(state.actors[actor_id], actor_id, choices, Rng.rng)}

func to_dict() -> Dictionary:
	return {"type": "level_up", "actor_id": actor_id, "choices": choices.duplicate(true)}

## Strict decoding: known keys and plain types only; JSON numbers become ints.
func from_dict(data: Dictionary) -> Error:
	if data.size() != 3 or data.get("type") != "level_up" or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("choices") is Dictionary:
		return ERR_INVALID_DATA
	var parsed: Dictionary = {}
	var source: Dictionary = data["choices"]
	for key: Variant in source:
		if not key is String or not String(key) in ProgressionRules.CHOICE_KEYS:
			return ERR_INVALID_DATA
		var value: Variant = source[key]
		match String(key):
			"hp", "feat", "fighting_style", "expertise":
				if not value is String or String(value).length() > 64:
					return ERR_INVALID_DATA
				parsed[key] = value
			"ability_increases":
				if not value is Dictionary or value.size() > 6:
					return ERR_INVALID_DATA
				var increases: Dictionary = {}
				for ability: Variant in value:
					var amount: Variant = value[ability]
					if not ability is String or not (amount is int or amount is float) or \
							float(amount) != floorf(float(amount)) or absf(float(amount)) > 30.0:
						return ERR_INVALID_DATA
					increases[ability] = int(amount)
				parsed[key] = increases
			_:
				if not value is Array or value.size() > 32:
					return ERR_INVALID_DATA
				var names: Array = []
				for entry: Variant in value:
					if not entry is String or String(entry).length() > 64:
						return ERR_INVALID_DATA
					names.append(entry)
				parsed[key] = names
	actor_id = data["actor_id"]
	choices = parsed
	return OK
