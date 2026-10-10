class_name ItemCatalog
extends RefCounted
## SRD 5.2 equipment as data (data/items/items.json). Pure lookups, no scene access.

const PATH: String = "res://data/items/items.json"
const TYPES: Array[String] = ["weapon", "armor", "shield", "consumable"]
const SLOTS: Array[String] = ["main_hand", "off_hand", "armor"]

static var _items: Dictionary = {}
static var _kits: Dictionary = {}

static func _ensure_loaded() -> void:
	if not _items.is_empty():
		return
	var text: String = FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("Item catalog could not be parsed: " + PATH)
		return
	for id: String in (parsed as Dictionary).get("items", {}):
		var item: Dictionary = parsed["items"][id]
		if valid_item(item):
			var copy: Dictionary = item.duplicate(true)
			copy["id"] = id
			_items[id] = copy
		else:
			push_error("Invalid item in catalog: " + id)
	_kits = (parsed as Dictionary).get("starting_kits", {}).duplicate(true)

static func valid_item(item: Dictionary) -> bool:
	if not String(item.get("type", "")) in TYPES or not item.get("name_key") is String:
		return false
	if not (item.get("weight_kg", 0.0) is float or item.get("weight_kg", 0) is int):
		return false
	match String(item["type"]):
		"weapon":
			if not String(item.get("category", "")) in ["simple", "martial"] or \
					not String(item.get("kind", "")) in ["melee", "ranged"]:
				return false
			if Dice.parse(String(item.get("damage_dice", ""))).has("error") or \
					not StringName(String(item.get("damage_type", ""))) in DamageRules.TYPES:
				return false
			if item.has("versatile_dice") and Dice.parse(String(item["versatile_dice"])).has("error"):
				return false
			if item["kind"] == "ranged" and float(item.get("range", 0.0)) <= 0.0:
				return false
		"armor":
			if not ArmorRules.ARMOR.has(StringName(String(item.get("armor_id", "")))):
				return false
		"consumable":
			if String(item.get("effect", "")) != "heal" or Dice.parse(String(item.get("dice", ""))).has("error"):
				return false
	return true

static func has(item_id: String) -> bool:
	_ensure_loaded()
	return _items.has(item_id)

static func get_item(item_id: String) -> Dictionary:
	_ensure_loaded()
	return _items.get(item_id, {}).duplicate(true)

static func ids() -> Array[String]:
	_ensure_loaded()
	var result: Array[String] = []
	result.assign(_items.keys())
	return result

static func starting_kit(class_id: String) -> Dictionary:
	_ensure_loaded()
	return _kits.get(class_id, _kits.get("default", {})).duplicate(true)

## Which equipment slot an item goes into; empty for items that are used, not worn.
static func slot_for(item: Dictionary) -> String:
	match String(item.get("type", "")):
		"weapon": return "main_hand"
		"shield": return "off_hand"
		"armor": return "armor"
	return ""

static func two_handed(item: Dictionary) -> bool:
	return "two_handed" in item.get("properties", [])
