class_name LootTakeCommand
extends InventoryCommand
## Takes one item, or the gold ("gold"), from a body or a pile in reach.
## In combat this is the free object interaction of the turn (SRD 5.2), once per round.

var source_id: String = ""
var item_id: String = ""

func _init(p_actor_id: String = "", p_source_id: String = "", p_item_id: String = "") -> void:
	super(p_actor_id)
	source_id = p_source_id
	item_id = p_item_id

func validate(state: GameState) -> Error:
	if item_id != "gold" and not ItemCatalog.has(item_id):
		return ERR_INVALID_PARAMETER
	return OK if LootRules.take_reason(state, actor_id, source_id, item_id).is_empty() else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var taken: Dictionary = LootRules.take(state, actor_id, source_id, item_id)
	return {"events": [{"type": "loot_taken", "actor_id": actor_id, "source_id": source_id,
		"items": taken["items"], "gold": taken["gold"]}, equipment_event(actor_id, state.actors[actor_id])]}

func to_dict() -> Dictionary:
	return {"type": "loot_take", "actor_id": actor_id, "source_id": source_id, "item_id": item_id}

func from_dict(data: Dictionary) -> Error:
	if data.get("type") != "loot_take" or data.size() != 4 or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("source_id") is String or \
			not data.get("item_id") is String:
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	source_id = data["source_id"]
	item_id = data["item_id"]
	return OK
