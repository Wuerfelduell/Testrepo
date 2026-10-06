class_name RuleModifier
extends RefCounted
## Stable source IDs are translated by the presentation layer, never here.

var amount: int = 0
var source: StringName = &""

func _init(value: int = 0, source_id: StringName = &"expression") -> void:
	amount = value
	source = source_id

func copy() -> RuleModifier:
	return RuleModifier.new(amount, source)
