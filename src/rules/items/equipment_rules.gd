class_name EquipmentRules
extends RefCounted
## Inventory and equipment on plain actor records. Pure: no nodes, no global RNG.
## Actor fields: "inventory" [{item, count}], "equipment" {main_hand, off_hand, armor}, "gold".
## Equipping recalculates the derived combat values ("weapon", "attacks", "ac", "speed_m").

const BASE_SPEED_M: float = 9.0

class Training extends RefCounted:
	var armor: Array[StringName] = []
	var weapons: Array[StringName] = []

	static func from_class(definition: ClassDefinition) -> Training:
		var result: Training = Training.new()
		if definition != null:
			result.armor = definition.armor_training.duplicate()
			result.weapons = definition.weapon_proficiencies.duplicate()
		return result

static func has_inventory(actor: Dictionary) -> bool:
	return actor.get("equipment") is Dictionary and actor.get("inventory") is Array

## Gives a fresh hero its class starting kit. Returns false when the kit is invalid.
static func initialize(actor: Dictionary, class_id: String, training: Training) -> bool:
	var kit: Dictionary = ItemCatalog.starting_kit(class_id)
	var equipment: Dictionary = {"main_hand": "", "off_hand": "", "armor": ""}
	for slot: String in kit.get("equipped", {}):
		var item_id: String = String(kit["equipped"][slot])
		if not slot in ItemCatalog.SLOTS or ItemCatalog.slot_for(ItemCatalog.get_item(item_id)) != slot:
			return false
		equipment[slot] = item_id
	if equipment["main_hand"] == "":
		return false
	actor["equipment"] = equipment
	actor["inventory"] = []
	actor["gold"] = int(kit.get("gold", 0))
	for item_id: String in kit.get("bag", {}):
		if not ItemCatalog.has(item_id):
			return false
		add_item(actor, item_id, int(kit["bag"][item_id]))
	refresh_weapon(actor, training)
	refresh_armor(actor, training)
	return true

static func count(actor: Dictionary, item_id: String) -> int:
	for entry: Dictionary in actor.get("inventory", []):
		if String(entry["item"]) == item_id:
			return int(entry["count"])
	return 0

static func add_item(actor: Dictionary, item_id: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	var inventory: Array = actor.get("inventory", [])
	for entry: Dictionary in inventory:
		if String(entry["item"]) == item_id:
			entry["count"] = int(entry["count"]) + amount
			return
	inventory.append({"item": item_id, "count": amount})
	actor["inventory"] = inventory

static func remove_item(actor: Dictionary, item_id: String, amount: int = 1) -> bool:
	var inventory: Array = actor.get("inventory", [])
	for index: int in range(inventory.size()):
		var entry: Dictionary = inventory[index]
		if String(entry["item"]) != item_id:
			continue
		if int(entry["count"]) < amount:
			return false
		entry["count"] = int(entry["count"]) - amount
		if int(entry["count"]) == 0:
			inventory.remove_at(index)
		return true
	return false

static func total_weight_kg(actor: Dictionary) -> float:
	var total: float = 0.0
	for entry: Dictionary in actor.get("inventory", []):
		total += float(ItemCatalog.get_item(String(entry["item"])).get("weight_kg", 0.0)) * int(entry["count"])
	var equipment: Dictionary = actor.get("equipment", {})
	for slot: String in equipment:
		total += float(ItemCatalog.get_item(String(equipment[slot])).get("weight_kg", 0.0))
	return total

## Locked while an attack or move is resolving, during someone else's turn and after death.
static func _turn_reason(state: GameState, actor_id: String) -> String:
	if not state.actors.has(actor_id) or not has_inventory(state.actors[actor_id]):
		return "INV_REASON_NO_INVENTORY"
	if not CombatRules.alive(state.actors[actor_id]) or state.mode == &"defeat":
		return "INV_REASON_DEAD"
	if not state.pending.is_empty():
		return "INV_REASON_BUSY"
	if state.mode == &"combat" and state.current_actor_id() != actor_id:
		return "INV_REASON_NOT_YOUR_TURN"
	return ""

## Empty string when allowed, otherwise a translation key with the reason.
static func equip_reason(state: GameState, actor_id: String, item_id: String) -> String:
	var reason: String = _turn_reason(state, actor_id)
	if not reason.is_empty():
		return reason
	var actor: Dictionary = state.actors[actor_id]
	if count(actor, item_id) <= 0:
		return "INV_REASON_NOT_OWNED"
	var item: Dictionary = ItemCatalog.get_item(item_id)
	var slot: String = ItemCatalog.slot_for(item)
	if slot.is_empty():
		return "INV_REASON_NOT_EQUIPPABLE"
	var equipment: Dictionary = actor["equipment"]
	var in_combat: bool = state.mode == &"combat"
	# SRD 5.2: donning or doffing armour takes minutes, a shield takes an action. Not mid-fight.
	if in_combat and slot != "main_hand":
		return "INV_REASON_ARMOR_IN_COMBAT"
	if slot == "off_hand" and ItemCatalog.two_handed(ItemCatalog.get_item(String(equipment["main_hand"]))):
		return "INV_REASON_TWO_HANDED"
	if in_combat and ItemCatalog.two_handed(item) and String(equipment["off_hand"]) != "":
		return "INV_REASON_SHIELD_IN_COMBAT"
	return ""

static func unequip_reason(state: GameState, actor_id: String, slot: String) -> String:
	var reason: String = _turn_reason(state, actor_id)
	if not reason.is_empty():
		return reason
	if not slot in ItemCatalog.SLOTS:
		return "INV_REASON_NOT_EQUIPPABLE"
	if String(state.actors[actor_id]["equipment"].get(slot, "")) == "":
		return "INV_REASON_SLOT_EMPTY"
	if slot == "main_hand":
		return "INV_REASON_KEEP_WEAPON"
	if state.mode == &"combat":
		return "INV_REASON_ARMOR_IN_COMBAT"
	return ""

static func use_reason(state: GameState, actor_id: String, item_id: String) -> String:
	var reason: String = _turn_reason(state, actor_id)
	if not reason.is_empty():
		return reason
	var actor: Dictionary = state.actors[actor_id]
	if count(actor, item_id) <= 0:
		return "INV_REASON_NOT_OWNED"
	var item: Dictionary = ItemCatalog.get_item(item_id)
	if String(item.get("type", "")) != "consumable":
		return "INV_REASON_NOT_USABLE"
	if int(actor.get("hp", 0)) >= int(actor.get("max_hp", 0)):
		return "INV_REASON_FULL_HP"
	# SRD 5.2: drinking a potion is a Bonus Action.
	if state.mode == &"combat" and String(item.get("cost", "")) == "bonus_action" and \
			not bool(actor.get("bonus_available", false)):
		return "INV_REASON_NO_BONUS_ACTION"
	return ""

## Moves the item from the bag into its slot; the previous item goes back into the bag.
static func equip(actor: Dictionary, item_id: String, training: Training) -> void:
	var item: Dictionary = ItemCatalog.get_item(item_id)
	var slot: String = ItemCatalog.slot_for(item)
	var equipment: Dictionary = actor["equipment"]
	remove_item(actor, item_id)
	if String(equipment[slot]) != "":
		add_item(actor, String(equipment[slot]))
	equipment[slot] = item_id
	var armor_changed: bool = slot != "main_hand"
	if slot == "main_hand" and ItemCatalog.two_handed(item) and String(equipment["off_hand"]) != "":
		add_item(actor, String(equipment["off_hand"]))
		equipment["off_hand"] = ""
		armor_changed = true
	refresh_weapon(actor, training)
	# A weapon swap never touches AC, so temporary AC effects from other systems survive it.
	if armor_changed:
		refresh_armor(actor, training)

static func unequip(actor: Dictionary, slot: String, training: Training) -> void:
	var equipment: Dictionary = actor["equipment"]
	add_item(actor, String(equipment[slot]))
	equipment[slot] = ""
	refresh_weapon(actor, training)
	if slot != "main_hand":
		refresh_armor(actor, training)

static func _score(actor: Dictionary, ability: String) -> int:
	var scores: Dictionary = actor.get("ability_scores", {})
	return int(scores.get(StringName(ability), scores.get(ability, 10)))

## The combat record of a weapon in this actor's hands, in the format CombatRules reads.
static func weapon_record(actor: Dictionary, item_id: String, training: Training, off_hand_free: bool) -> Dictionary:
	var item: Dictionary = ItemCatalog.get_item(item_id)
	var ranged: bool = String(item["kind"]) == "ranged"
	var ability: String = "dex" if ranged else "str"
	if "finesse" in item.get("properties", []) and _score(actor, "dex") > _score(actor, "str"):
		ability = "dex"
	var ability_mod: int = Abilities.modifier(_score(actor, ability))
	var proficient: bool = StringName(String(item["category"])) in training.weapons
	var proficiency: int = int(actor.get("proficiency_bonus", 2)) if proficient else 0
	var versatile: bool = off_hand_free and item.has("versatile_dice")
	var attack_modifiers: Array[Dictionary] = [{"amount": ability_mod, "source": ability}]
	if proficient:
		attack_modifiers.append({"amount": proficiency, "source": "proficiency"})
	return {
		"id": item_id, "item_id": item_id, "name_key": String(item["name_key"]), "ranged": ranged,
		"reach": 1.5, "range": float(item.get("range", 0.0)), "long_range": float(item.get("long_range", 0.0)),
		"attack_bonus": ability_mod + proficiency,
		"damage_dice": String(item["versatile_dice"] if versatile else item["damage_dice"]),
		"damage_bonus": ability_mod, "damage_type": String(item["damage_type"]),
		"attack_modifiers": attack_modifiers,
		"damage_modifiers": [{"amount": ability_mod, "source": ability}],
		"model": _model(item), "mastery": String(item.get("mastery", "")),
		"properties": item.get("properties", []).duplicate(), "proficient": proficient,
		"two_handed_grip": versatile,
	}

## Weapons whose model is not built yet are simply not drawn in the hand.
static func _model(item: Dictionary) -> String:
	var path: String = String(item.get("model", ""))
	return path if not path.is_empty() and ResourceLoader.exists(path) else ""

static func refresh_weapon(actor: Dictionary, training: Training) -> void:
	var equipment: Dictionary = actor["equipment"]
	var record: Dictionary = weapon_record(actor, String(equipment["main_hand"]), training,
		String(equipment["off_hand"]) == "")
	actor["weapon"] = record
	actor["attacks"] = [record.duplicate(true)]

static func refresh_armor(actor: Dictionary, training: Training) -> void:
	var equipment: Dictionary = actor["equipment"]
	var armor_id: StringName = &"none"
	if String(equipment["armor"]) != "":
		armor_id = StringName(String(ItemCatalog.get_item(String(equipment["armor"]))["armor_id"]))
	var shield: bool = String(equipment["off_hand"]) == "shield"
	var result: ArmorRules.Result = ArmorRules.calculate(armor_id, _score(actor, "dex"),
		_score(actor, "str"), training.armor, shield)
	if not result.is_valid():
		return
	actor["ac"] = result.armor_class
	actor["armor"] = String(armor_id)
	actor["shield"] = shield
	actor["can_cast_spells"] = result.can_cast_spells
	actor["armor_untrained"] = result.strength_dexterity_disadvantage
	var breakdown: Array[Dictionary] = []
	for modifier: RuleModifier in result.breakdown:
		breakdown.append({"amount": modifier.amount, "source": String(modifier.source)})
	actor["ac_breakdown"] = breakdown
	var previous_speed: float = float(actor.get("speed_m", BASE_SPEED_M))
	actor["speed_m"] = maxf(0.0, BASE_SPEED_M - result.speed_penalty_m)
	if float(actor.get("move_left", previous_speed)) >= previous_speed:
		actor["move_left"] = actor["speed_m"]
