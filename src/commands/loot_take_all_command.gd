class_name LootTakeAllCommand
extends InventoryCommand
## Takes everything from a body or a pile in reach. In combat this is the Utilize action.

var source_id: String = ""

func _init(p_actor_id: String = "", p_source_id: String = "") -> void:
	super(p_actor_id)
	source_id = p_source_id

func validate(state: GameState) -> Error:
	return OK if LootRules.take_reason(state, actor_id, source_id, "", true).is_empty() else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var taken: Dictionary = LootRules.take(state, actor_id, source_id, "", true)
	return {"events": [{"type": "loot_taken", "actor_id": actor_id, "source_id": source_id,
		"items": taken["items"], "gold": taken["gold"]}, equipment_event(actor_id, state.actors[actor_id])]}

func to_dict() -> Dictionary:
	return {"type": "loot_take_all", "actor_id": actor_id, "source_id": source_id}

func from_dict(data: Dictionary) -> Error:
	if data.get("type") != "loot_take_all" or data.size() != 3 or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("source_id") is String:
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	source_id = data["source_id"]
	return OK
