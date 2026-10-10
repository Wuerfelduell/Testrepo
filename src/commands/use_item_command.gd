class_name UseItemCommand
extends InventoryCommand
## Drinks a consumable. Potion of Healing (SRD 5.2): Bonus Action, regain 2d4 + 2 HP.

var item_id: String = ""

func _init(p_actor_id: String = "", p_item_id: String = "") -> void:
	super(p_actor_id)
	item_id = p_item_id

func validate(state: GameState) -> Error:
	if not ItemCatalog.has(item_id):
		return ERR_INVALID_PARAMETER
	return OK if EquipmentRules.use_reason(state, actor_id, item_id).is_empty() else ERR_UNAVAILABLE

func apply(state: GameState) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	var item: Dictionary = ItemCatalog.get_item(item_id)
	EquipmentRules.remove_item(actor, item_id)
	if state.mode == &"combat" and String(item.get("cost", "")) == "bonus_action":
		actor["bonus_available"] = false
	var bonus: Array[RuleModifier] = [RuleModifier.new(int(item.get("bonus", 0)), StringName(item_id))]
	var roll: DiceResult = Dice.roll(String(item["dice"]), Rng.rng, bonus)
	var before: int = int(actor["hp"])
	actor["hp"] = mini(int(actor["max_hp"]), before + maxi(0, roll.total))
	return {"events": [
		{"type": "roll", "kind": "healing", "actor_id": actor_id,
			"roll": CombatRules.serialize_roll(roll), "item_id": item_id},
		{"type": "heal", "actor_id": actor_id, "item_id": item_id,
			"amount": int(actor["hp"]) - before, "hp": actor["hp"]},
	]}

func to_dict() -> Dictionary:
	return {"type": "use_item", "actor_id": actor_id, "item_id": item_id}

func from_dict(data: Dictionary) -> Error:
	if data.get("type") != "use_item" or data.size() != 3 or not data.get("actor_id") is String or \
			String(data["actor_id"]).is_empty() or not data.get("item_id") is String:
		return ERR_INVALID_DATA
	actor_id = data["actor_id"]
	item_id = data["item_id"]
	return OK
