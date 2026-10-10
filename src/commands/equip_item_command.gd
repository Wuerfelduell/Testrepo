class_name EquipItemCommand
extends InventoryCommand
## Moves an item from the bag into its equipment slot. Weapon swaps are free on your own turn;
## armour and shields cannot be changed during combat.

var item_id: String = ""

func _init(p_actor_id: String = "", p_item_id: String = "") -> void:
	super(p_actor_id)
	item_id = p_item_id

func validate(state: GameState) -> Error:
	if not ItemCatalog.has(item_id):
		return ERR_INVALID_PARAMETER
	return OK if EquipmentRules.equip_reason(state, actor_id, item_id).is_empty() else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	EquipmentRules.equip(actor, item_id, training_for(actor))
	return {"events": [equipment_event(actor_id, actor)]}

func to_dict() -> Dictionary:
	return {"type": "equip_item", "actor_id": actor_id, "item_id": item_id}

func from_dict(data: Dictionary) -> Error:
	if data.get("type") != "equip_item" or data.size() != 3 or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("item_id") is String:
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	item_id = data["item_id"]
	return OK
