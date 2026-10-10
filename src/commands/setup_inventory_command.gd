class_name SetupInventoryCommand
extends InventoryCommand
## Gives a hero without inventory the starting kit of their class (data/items/items.json).

func validate(state: GameState) -> Error:
	if not state.actors.has(actor_id):
		return ERR_INVALID_PARAMETER
	var actor: Dictionary = state.actors[actor_id]
	if EquipmentRules.has_inventory(actor) or String(actor.get("class_id", "")).is_empty():
		return ERR_ALREADY_IN_USE
	if not state.pending.is_empty():
		return ERR_BUSY
	var probe: Dictionary = actor.duplicate(true)
	return OK if EquipmentRules.initialize(probe, String(actor["class_id"]), training_for(actor)) else ERR_INVALID_DATA

func apply(state: GameState) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	EquipmentRules.initialize(actor, String(actor["class_id"]), training_for(actor))
	return {"events": [equipment_event(actor_id, actor)]}

func to_dict() -> Dictionary:
	return {"type": "setup_inventory", "actor_id": actor_id}
