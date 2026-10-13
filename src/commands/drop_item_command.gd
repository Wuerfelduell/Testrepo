class_name DropItemCommand
extends InventoryCommand
## Drops one item from the bag at the hero's feet. It stays there as loot (GameState.loot_piles).

var item_id: String = ""

func _init(p_actor_id: String = "", p_item_id: String = "") -> void:
	super(p_actor_id)
	item_id = p_item_id

func validate(state: GameState) -> Error:
	if not ItemCatalog.has(item_id):
		return ERR_INVALID_PARAMETER
	return OK if EquipmentRules.drop_reason(state, actor_id, item_id).is_empty() else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var pile_id: String = LootRules.drop(state, actor_id, item_id)
	return {"events": [{"type": "item_dropped", "actor_id": actor_id, "item_id": item_id, "pile_id": pile_id},
		equipment_event(actor_id, state.actors[actor_id])]}

func to_dict() -> Dictionary:
	return {"type": "drop_item", "actor_id": actor_id, "item_id": item_id}

func from_dict(data: Dictionary) -> Error:
	if data.get("type") != "drop_item" or data.size() != 3 or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("item_id") is String:
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	item_id = data["item_id"]
	return OK
