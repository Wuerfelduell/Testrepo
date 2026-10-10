class_name UnequipItemCommand
extends InventoryCommand
## Moves the item in an equipment slot back into the bag.

var slot: String = ""

func _init(p_actor_id: String = "", p_slot: String = "") -> void:
	super(p_actor_id)
	slot = p_slot

func validate(state: GameState) -> Error:
	return OK if EquipmentRules.unequip_reason(state, actor_id, slot).is_empty() else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	EquipmentRules.unequip(actor, slot, training_for(actor))
	return {"events": [equipment_event(actor_id, actor)]}

func to_dict() -> Dictionary:
	return {"type": "unequip_item", "actor_id": actor_id, "slot": slot}

func from_dict(data: Dictionary) -> Error:
	if data.get("type") != "unequip_item" or data.size() != 3 or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("slot") is String:
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	slot = data["slot"]
	return OK
