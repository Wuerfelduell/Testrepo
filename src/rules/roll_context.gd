class_name RollContext
extends RefCounted

var advantages: Array[StringName] = []
var disadvantages: Array[StringName] = []
var conditions: ConditionState = ConditionState.new()
var fear_source_visible: bool = false
var requires_sight: bool = false

func is_valid() -> bool:
	return conditions != null
