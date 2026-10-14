class_name EquipItemCommand
extends InventoryCommand
## Moves an item from the bag into its equipment slot. Weapon swaps are free on your own turn;
## armour and shields cannot be changed during combat. slot "off_hand" puts a Light weapon
## into the off hand (dual wielding).

var item_id: String = ""
var slot: String = ""

func _init(p_actor_id: String = "", p_item_id: String = "", p_slot: String = "") -> void:
	super(p_actor_id)
	item_id = p_item_id
	slot = p_slot

func validate(state: GameState) -> Error:
	if not ItemCatalog.has(item_id):
		return ERR_INVALID_PARAMETER
	return OK if EquipmentRules.equip_reason(state, actor_id, item_id, slot).is_empty() else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	EquipmentRules.equip(actor, item_id, training_for(actor), slot)
	return {"events": [equipment_event(actor_id, actor)]}

func to_dict() -> Dictionary:
	var data: Dictionary = {"type": "equip_item", "actor_id": actor_id, "item_id": item_id}
	if not slot.is_empty():
		data["slot"] = slot
	return data

func from_dict(data: Dictionary) -> Error:
	var has_slot: bool = data.has("slot")
	if data.get("type") != "equip_item" or data.size() != (4 if has_slot else 3) or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("item_id") is String or \
			(has_slot and data["slot"] != "off_hand"):
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	item_id = data["item_id"]
	slot = String(data.get("slot", ""))
	return OK
