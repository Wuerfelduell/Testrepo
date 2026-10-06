class_name DiceResult
extends RefCounted

class Group extends RefCounted:
	var sides: int = 0
	var sign: int = 1
	var values: Array[int] = []
	var kept_indices: Array[int] = []
	var source: StringName = &"expression"
	var critical: bool = false

var error: StringName = &""
var expression: String = ""
var groups: Array[Group] = []
var modifiers: Array[RuleModifier] = []
var advantage_sources: Array[StringName] = []
var disadvantage_sources: Array[StringName] = []
var mode: StringName = &"normal"
var total: int = 0
var natural: int = 0
var natural_20: bool = false
var natural_1: bool = false

func is_valid() -> bool:
	return error == &""

func add_modifiers(values: Array[RuleModifier]) -> void:
	for modifier: RuleModifier in values:
		modifiers.append(modifier.copy())
		total += modifier.amount

func record_natural(value: int) -> void:
	natural = value
	natural_20 = value == 20
	natural_1 = value == 1
