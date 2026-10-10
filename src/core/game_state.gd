class_name GameState
extends RefCounted
## Data only. Actor records contain data values, never Nodes or Resources.

var actors: Dictionary = {}
var pending: Dictionary = {}
var turn_order: Array[String] = []
var turn_index: int = 0
var round_number: int = 1
var mode: StringName = &"exploration"

func current_actor_id() -> String:
	if turn_order.is_empty() or turn_index < 0 or turn_index >= turn_order.size():
		return ""
	return turn_order[turn_index]

func copy() -> GameState:
	var result: GameState = GameState.new()
	result.actors = actors.duplicate(true)
	result.pending = pending.duplicate(true)
	result.turn_order = turn_order.duplicate()
	result.turn_index = turn_index
	result.round_number = round_number
	result.mode = mode
	return result

## Plain-data snapshot for the ironman save (see SaveGame). Values stay Variants;
## SaveGame encodes them without objects, so Vector3/StringName survive a round trip.
func to_dict() -> Dictionary:
	return {"actors": actors.duplicate(true), "pending": pending.duplicate(true),
		"turn_order": turn_order.duplicate(), "turn_index": turn_index,
		"round_number": round_number, "mode": mode}

## Returns null for anything that is not a complete snapshot from to_dict().
static func from_dict(data: Dictionary) -> GameState:
	if not data.get("actors") is Dictionary or not data.get("pending") is Dictionary or \
			not data.get("turn_order") is Array or not data.get("turn_index") is int or \
			not data.get("round_number") is int or not (data.get("mode") is StringName or data.get("mode") is String):
		return null
	var result: GameState = GameState.new()
	for id: Variant in data["actors"]:
		if not id is String or not data["actors"][id] is Dictionary:
			return null
	for id: Variant in data["turn_order"]:
		if not id is String or not data["actors"].has(id):
			return null
	result.actors = (data["actors"] as Dictionary).duplicate(true)
	result.pending = (data["pending"] as Dictionary).duplicate(true)
	result.turn_order.assign(data["turn_order"])
	result.turn_index = data["turn_index"]
	result.round_number = data["round_number"]
	result.mode = StringName(data["mode"])
	return result
