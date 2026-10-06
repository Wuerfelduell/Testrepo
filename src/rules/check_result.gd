class_name CheckResult
extends RefCounted

var error: StringName = &""
var kind: StringName = &""
var ability: StringName = &""
var skill: StringName = &""
var dc: int = 0
var roll: DiceResult = null
var success: bool = false
var automatic_failure: bool = false
var reason: StringName = &""

func is_valid() -> bool:
	return error == &""
