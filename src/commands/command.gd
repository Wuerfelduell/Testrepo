class_name Command
extends RefCounted
## Commands carry data only. Each concrete command must validate before applying.

var actor_id: String = ""

func _init(p_actor_id: String = "") -> void:
	actor_id = p_actor_id

func validate(_state: GameState) -> Error:
	return ERR_UNAVAILABLE

func apply(_state: GameState) -> Dictionary:
	return {}

func to_dict() -> Dictionary:
	return {"type": "command", "actor_id": actor_id}

## Deserializes fields into this instance; command type selection is explicit.
func from_dict(data: Dictionary) -> Error:
	if data.get("type") != to_dict()["type"] or not data.get("actor_id") is String:
		return ERR_INVALID_DATA
	if data.size() != 2 or String(data["actor_id"]).is_empty():
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	return OK
