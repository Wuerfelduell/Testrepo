class_name LongRestCommand
extends Command
## Long Rest for every living hero: full HP, spell slots, Hit Point Dice and feature
## uses. The world only offers it at a rest point (package 10 calls this command);
## a Wizard may pass a new prepared list (empty = unchanged).

var prepared: Array[String] = []

func _init(p_actor_id: String = "", p_prepared: Array[String] = []) -> void:
	actor_id = p_actor_id
	prepared = p_prepared.duplicate()

func validate(state: GameState) -> Error:
	match RestRules.long_rest_reason(state, actor_id, prepared):
		"":
			return OK
		"REST_REASON_UNKNOWN", "REST_REASON_PREPARED":
			return ERR_INVALID_PARAMETER
	return ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var events: Array[Dictionary] = []
	var ids: Array = state.actors.keys()
	ids.sort()
	for id: String in ids:
		var actor: Dictionary = state.actors[id]
		if actor.get("team") == "hero" and CombatRules.alive(actor) and ClassFeatures.is_active_class(actor):
			events.append_array(RestRules.long_rest(actor, id, prepared if id == actor_id else ([] as Array[String])))
	return {"events": events}

func to_dict() -> Dictionary:
	return {"type": "long_rest", "actor_id": actor_id, "prepared": prepared.duplicate()}

func from_dict(data: Dictionary) -> Error:
	if data.size() != 3 or data.get("type") != "long_rest" or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("prepared") is Array or data["prepared"].size() > 32:
		return ERR_INVALID_DATA
	var spells: Array[String] = []
	for value: Variant in data["prepared"]:
		if not value is String or String(value).length() > 64:
			return ERR_INVALID_DATA
		spells.append(String(value))
	actor_id = data["actor_id"]
	prepared = spells
	return OK
