class_name Progression
extends RefCounted

const XP_THRESHOLDS: Array[int] = [0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000]
const MAX_XP: int = 9223372036854775807

class Award extends RefCounted:
	var error: StringName = &""
	var amount: int = 0
	var reason: String = ""
	var previous_xp: int = 0
	var total_xp: int = 0
	var previous_level: int = 1
	var level: int = 1
	var gained_levels: Array[int] = []

	func is_valid() -> bool:
		return error == &""

var _xp: int = 0
var _history: Array[Dictionary] = []

var xp: int:
	get:
		return _xp
var level: int:
	get:
		return level_for_xp(_xp)

static func level_for_xp(amount: int) -> int:
	for index: int in range(XP_THRESHOLDS.size() - 1, -1, -1):
		if amount >= XP_THRESHOLDS[index]:
			return index + 1
	return 1

func initialize_level(start_level: int) -> bool:
	if start_level < 1 or start_level > 10 or _xp != 0 or not _history.is_empty():
		return false
	_xp = XP_THRESHOLDS[start_level - 1]
	return true

func history() -> Array[Dictionary]:
	return _history.duplicate(true)

func grant_xp(amount: int, reason: String) -> Award:
	var result: Award = Award.new()
	result.amount = amount
	result.reason = reason
	result.previous_xp = _xp
	result.total_xp = _xp
	result.previous_level = level
	result.level = level
	if amount < 0 or amount > MAX_XP - _xp or reason.strip_edges().is_empty():
		result.error = &"invalid_xp_award"
		return result
	_xp += amount
	result.total_xp = _xp
	result.level = level
	for new_level: int in range(result.previous_level + 1, result.level + 1):
		result.gained_levels.append(new_level)
	_history.append({"amount": amount, "reason": reason, "previous_xp": result.previous_xp,
		"total_xp": result.total_xp, "previous_level": result.previous_level, "level": result.level})
	return result
