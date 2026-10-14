class_name LootRules
extends RefCounted
## Loot on bodies and on the ground. Pure: randomness only through the RNG passed in.
## A source is either a defeated creature (actor id) or a pile on the ground (GameState.loot_piles).
##
## Project rule (owner, 13-10-2026): in combat, on your own turn, every take (one item, the gold
## or everything) costs your action. Outside combat it is free.

const RANGE_M: float = 3.0
const PILE_MERGE_M: float = 1.5

## What a creature of this kind leaves: its stat block gear, rolled gold and rolled extras.
static func roll(monster_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var table: Dictionary = ItemCatalog.monster_loot(monster_id)
	var result: Dictionary = {"items": {}, "gold": 0}
	for item_id: String in table.get("gear", {}):
		if ItemCatalog.has(item_id):
			_add(result, item_id, int(table["gear"][item_id]))
	if not String(table.get("gold", "")).is_empty():
		var gold: DiceResult = Dice.roll(String(table["gold"]), rng)
		if gold.is_valid():
			result["gold"] = gold.total
	for entry: Dictionary in table.get("rolls", []):
		if rng.randf() < float(entry.get("chance", 0.0)) and ItemCatalog.has(String(entry["item"])):
			_add(result, String(entry["item"]), int(entry.get("count", 1)))
	return result

static func _add(loot: Dictionary, item_id: String, amount: int) -> void:
	loot["items"][item_id] = int(loot["items"].get(item_id, 0)) + amount

static func is_pile(source_id: String) -> bool:
	return source_id.begins_with("pile_")

static func source(state: GameState, source_id: String) -> Dictionary:
	if is_pile(source_id):
		return state.loot_piles.get(source_id, {})
	return state.actors.get(source_id, {})

## Remaining loot: {"items": {item_id: count}, "gold": int}.
static func remaining(record: Dictionary) -> Dictionary:
	if record.get("loot") is Dictionary:
		return (record["loot"] as Dictionary).duplicate(true)
	if record.has("items"):
		return {"items": (record["items"] as Dictionary).duplicate(true), "gold": int(record.get("gold", 0))}
	if String(record.get("team", "")) != "enemy":
		return {"items": {}, "gold": 0}
	# Not rolled yet (e.g. died before loot existed): the stat block gear only.
	var table: Dictionary = ItemCatalog.monster_loot(String(record.get("definition_id", record.get("id", ""))))
	var result: Dictionary = {"items": {}, "gold": 0}
	for item_id: String in table.get("gear", {}):
		if ItemCatalog.has(item_id):
			_add(result, item_id, int(table["gear"][item_id]))
	return result

static func is_empty(loot: Dictionary) -> bool:
	return (loot.get("items", {}) as Dictionary).is_empty() and int(loot.get("gold", 0)) <= 0

static func lootable(record: Dictionary) -> bool:
	if record.is_empty():
		return false
	if not record.has("items") and CombatRules.alive(record):
		return false
	return not is_empty(remaining(record))

static func _distance(actor: Dictionary, record: Dictionary) -> float:
	var from: Vector3 = actor.get("position", Vector3.ZERO)
	var to: Vector3 = record.get("position", Vector3.ZERO)
	return from.distance_to(to)

## Every lootable source with its position (bodies and piles).
static func sources(state: GameState) -> Dictionary:
	var result: Dictionary = {}
	for id: String in state.actors:
		if lootable(state.actors[id]):
			result[id] = state.actors[id].get("position", Vector3.ZERO)
	for id: String in state.loot_piles:
		if lootable(state.loot_piles[id]):
			result[id] = state.loot_piles[id].get("position", Vector3.ZERO)
	return result

## The closest lootable source within reach of the actor, or "".
static func nearest(state: GameState, actor_id: String) -> String:
	if not state.actors.has(actor_id):
		return ""
	var best: String = ""
	var best_distance: float = RANGE_M
	var positions: Dictionary = sources(state)
	for id: String in positions:
		if id == actor_id:
			continue
		var distance: float = (state.actors[actor_id].get("position", Vector3.ZERO) as Vector3).distance_to(positions[id])
		if distance <= best_distance:
			best = id
			best_distance = distance
	return best

## The lootable source closest to a point on the ground (mouse hover), or "".
static func source_at(state: GameState, point: Vector3, radius: float = 1.0) -> String:
	var best: String = ""
	var best_distance: float = radius
	var positions: Dictionary = sources(state)
	for id: String in positions:
		var distance: float = Vector2(point.x - positions[id].x, point.z - positions[id].z).length()
		if distance <= best_distance:
			best = id
			best_distance = distance
	return best

## item_id: an item or "gold"; take_all for everything. Empty string = allowed.
static func take_reason(state: GameState, actor_id: String, source_id: String, item_id: String,
		take_all: bool = false) -> String:
	var reason: String = EquipmentRules.turn_reason(state, actor_id)
	if not reason.is_empty():
		return reason
	var record: Dictionary = source(state, source_id)
	if record.is_empty() or source_id == actor_id:
		return "LOOT_REASON_NOTHING"
	if not is_pile(source_id) and CombatRules.alive(record):
		return "LOOT_REASON_ALIVE"
	if _distance(state.actors[actor_id], record) > RANGE_M:
		return "LOOT_REASON_TOO_FAR"
	var loot: Dictionary = remaining(record)
	if is_empty(loot):
		return "LOOT_REASON_NOTHING"
	if not take_all:
		if item_id == "gold" and int(loot.get("gold", 0)) <= 0:
			return "LOOT_REASON_NOTHING"
		if item_id != "gold" and not (loot["items"] as Dictionary).has(item_id):
			return "LOOT_REASON_NOTHING"
	if state.mode == &"combat":
		var actor: Dictionary = state.actors[actor_id]
		if not CombatRules.can_use_action(actor):
			return "LOOT_REASON_NO_ACTION"
	return ""

## Moves loot onto the actor and pays the combat cost. Returns what was taken.
static func take(state: GameState, actor_id: String, source_id: String, item_id: String,
		take_all: bool = false) -> Dictionary:
	var actor: Dictionary = state.actors[actor_id]
	var record: Dictionary = source(state, source_id)
	var loot: Dictionary = remaining(record)
	var taken: Dictionary = {"items": {}, "gold": 0}
	if take_all or item_id == "gold":
		taken["gold"] = int(loot["gold"])
		Money.change(actor, int(loot["gold"]) * Money.CP_PER_GP)
		loot["gold"] = 0
	var items: Dictionary = loot["items"]
	for id: String in items.keys():
		if take_all or item_id == id:
			EquipmentRules.add_item(actor, id, int(items[id]))
			taken["items"][id] = int(items[id])
			items.erase(id)
	if is_pile(source_id):
		if is_empty(loot):
			state.loot_piles.erase(source_id)
		else:
			record["items"] = loot["items"]
			record["gold"] = loot["gold"]
	else:
		record["loot"] = loot
	if state.mode == &"combat":
		actor["action_available"] = false
	EquipmentRules.refresh_speed(actor)
	return taken

## Drops one item at the actor's feet: onto a pile within reach, or a new pile.
## Returns the pile id.
static func drop(state: GameState, actor_id: String, item_id: String) -> String:
	var actor: Dictionary = state.actors[actor_id]
	var at: Vector3 = actor.get("position", Vector3.ZERO)
	EquipmentRules.remove_item(actor, item_id)
	EquipmentRules.refresh_speed(actor)
	var pile_id: String = ""
	var next: int = 1
	for id: String in state.loot_piles:
		next = maxi(next, id.trim_prefix("pile_").to_int() + 1)
		if pile_id.is_empty() and (state.loot_piles[id].get("position", Vector3.ZERO) as Vector3).distance_to(at) <= PILE_MERGE_M:
			pile_id = id
	if pile_id.is_empty():
		pile_id = "pile_%d" % next
		state.loot_piles[pile_id] = {"position": at, "items": {}, "gold": 0}
	var pile: Dictionary = state.loot_piles[pile_id]
	pile["items"][item_id] = int(pile["items"].get(item_id, 0)) + 1
	return pile_id
