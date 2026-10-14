class_name RollContext
extends RefCounted

var advantages: Array[StringName] = []
var disadvantages: Array[StringName] = []
var conditions: ConditionState = ConditionState.new()
var fear_source_visible: bool = false
var requires_sight: bool = false
## Reliable Talent (Rogue 7): a d20 below this counts as this number (0 = off).
var minimum_d20: int = 0

func is_valid() -> bool:
	return conditions != null
