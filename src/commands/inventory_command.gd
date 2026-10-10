class_name InventoryCommand
extends Command
## Shared base for inventory commands: the actor's class decides weapon and armour training.

static func training_for(actor: Dictionary) -> EquipmentRules.Training:
	var path: String = "res://data/classes/%s.tres" % String(actor.get("class_id", ""))
	if String(actor.get("class_id", "")).is_empty() or not ResourceLoader.exists(path):
		return EquipmentRules.Training.new()
	return EquipmentRules.Training.from_class(load(path) as ClassDefinition)

static func equipment_event(actor_id: String, actor: Dictionary) -> Dictionary:
	return {"type": "equipment_changed", "actor_id": actor_id,
		"equipment": actor["equipment"].duplicate(true),
		"model": String(actor["weapon"].get("model", ""))}
