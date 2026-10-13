class_name ItemText
extends RefCounted
## Tooltip text for items. The player always sees the numbers (docs/UI.md 1.1).

static func type_line(item: Dictionary) -> String:
	match String(item.get("type", "")):
		"weapon":
			return tr_key("ITEM_TYPE_%s_%s" % [String(item["category"]).to_upper(), String(item["kind"]).to_upper()])
		"armor":
			var data: Dictionary = ArmorRules.ARMOR[StringName(String(item["armor_id"]))]
			return tr_key("ITEM_TYPE_ARMOR_" + String(data["category"]).to_upper())
		"shield":
			return tr_key("ITEM_TYPE_SHIELD")
		"valuable":
			return tr_key("ITEM_TYPE_VALUABLE")
	return tr_key("ITEM_TYPE_CONSUMABLE")

## BBCode lines: stats first, then properties, weight and value.
static func stat_lines(item: Dictionary, actor: Dictionary, training: EquipmentRules.Training) -> PackedStringArray:
	var lines: PackedStringArray = []
	match String(item.get("type", "")):
		"weapon":
			var record: Dictionary = EquipmentRules.weapon_record(actor, String(item["id"]), training,
				String(actor.get("equipment", {}).get("off_hand", "")) == "" or ItemCatalog.two_handed(item))
			var damage: String = "%s%s" % [record["damage_dice"], _signed(int(record["damage_bonus"]))]
			lines.append("[color=#f3d38a]%s[/color]" % (tr_key("ITEM_ATTACK_LINE") % [
				int(record["attack_bonus"]), damage, tr_key("DAMAGE_" + String(item["damage_type"]).to_upper())]))
			if item.has("versatile_dice"):
				lines.append(tr_key("ITEM_VERSATILE") % [String(item["damage_dice"]), String(item["versatile_dice"])])
			if String(item["kind"]) == "ranged":
				lines.append(tr_key("ITEM_RANGE") % [float(item["range"]), float(item["long_range"])])
			var properties: PackedStringArray = []
			for property: Variant in item.get("properties", []):
				if String(property) != "versatile":
					properties.append(tr_key("ITEM_PROPERTY_" + String(property).to_upper()))
			if not properties.is_empty():
				lines.append(", ".join(properties))
			if not String(item.get("mastery", "")).is_empty():
				lines.append(tr_key("ITEM_MASTERY") % tr_key("ITEM_MASTERY_" + String(item["mastery"]).to_upper()))
			if not bool(record["proficient"]):
				lines.append("[color=#ed867d]%s[/color]" % tr_key("ITEM_NOT_PROFICIENT"))
		"armor":
			var data: Dictionary = ArmorRules.ARMOR[StringName(String(item["armor_id"]))]
			if String(data["category"]) == "heavy":
				lines.append("[color=#f3d38a]%s[/color]" % (tr_key("ITEM_AC_HEAVY") % int(data["base"])))
			elif int(data["dex_cap"]) < 10:
				lines.append("[color=#f3d38a]%s[/color]" % (tr_key("ITEM_AC_DEX_CAP") % [int(data["base"]), int(data["dex_cap"])]))
			else:
				lines.append("[color=#f3d38a]%s[/color]" % (tr_key("ITEM_AC_DEX") % int(data["base"])))
			if int(data["strength"]) > 0:
				lines.append(tr_key("ITEM_STRENGTH_REQUIREMENT") % int(data["strength"]))
			if bool(data["stealth"]):
				lines.append(tr_key("ITEM_STEALTH_DISADVANTAGE"))
			if not StringName(String(data["category"])) in training.armor:
				lines.append("[color=#ed867d]%s[/color]" % tr_key("ITEM_UNTRAINED_ARMOR"))
		"shield":
			lines.append("[color=#f3d38a]%s[/color]" % tr_key("ITEM_SHIELD_AC"))
			if not &"shield" in training.armor:
				lines.append("[color=#ed867d]%s[/color]" % tr_key("ITEM_UNTRAINED_SHIELD"))
		"consumable":
			lines.append("[color=#9ed5ac]%s[/color]" % (tr_key("ITEM_HEAL") % [String(item["dice"]), int(item.get("bonus", 0))]))
			lines.append(tr_key("ITEM_COST_BONUS_ACTION"))
	lines.append("[color=#9aa1ad]%s[/color]" % (tr_key("ITEM_WEIGHT_VALUE") % [float(item.get("weight_kg", 0.0)), int(item.get("value_gp", 0))]))
	return lines

## "Equipped: ..." comparison for weapons, armour and shields, empty for other items.
static func compare_line(item: Dictionary, actor: Dictionary, training: EquipmentRules.Training) -> String:
	var equipment: Dictionary = actor.get("equipment", {})
	match String(item.get("type", "")):
		"weapon":
			var current: Dictionary = actor.get("weapon", {})
			if current.is_empty() or String(current.get("item_id", "")) == String(item["id"]):
				return ""
			return "[color=#9aa1ad]%s[/color]" % (tr_key("ITEM_COMPARE_WEAPON") % [tr_key(String(current.get("name_key", ""))),
				int(current.get("attack_bonus", 0)), String(current.get("damage_dice", "")) + _signed(int(current.get("damage_bonus", 0)))])
		"armor", "shield":
			var armor_id: StringName = &"none"
			var shield: bool = String(equipment.get("off_hand", "")) == "shield"
			if String(item["type"]) == "armor":
				armor_id = StringName(String(item["armor_id"]))
			else:
				shield = true
				if String(equipment.get("armor", "")) != "":
					armor_id = StringName(String(ItemCatalog.get_item(String(equipment["armor"]))["armor_id"]))
			var scores: Dictionary = actor.get("ability_scores", {})
			var dex: int = int(scores.get(&"dex", scores.get("dex", 10)))
			var strength: int = int(scores.get(&"str", scores.get("str", 10)))
			var with_item: int = ArmorRules.calculate(armor_id, dex, strength, training.armor, shield).armor_class
			var now: int = int(actor.get("ac", 10))
			var color: String = "#9ed5ac" if with_item > now else ("#ed867d" if with_item < now else "#9aa1ad")
			return "[color=%s]%s[/color]" % [color, tr_key("ITEM_COMPARE_AC") % [now, with_item]]
	return ""

static func _signed(value: int) -> String:
	if value == 0:
		return ""
	return "%+d" % value

static func tr_key(key: String) -> String:
	return MenuStyle.text(key)
