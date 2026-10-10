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

static func _signed(value: int) -> String:
	if value == 0:
		return ""
	return "%+d" % value

static func tr_key(key: String) -> String:
	return MenuStyle.text(key)
