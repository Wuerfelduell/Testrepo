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
