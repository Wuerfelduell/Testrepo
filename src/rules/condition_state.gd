class_name ConditionState
extends RefCounted
## Basic physical sight only. Encounter code supplies fear visibility/distances.
## Independent sources prevent ending one effect from removing another.

const IDS: Array[StringName] = [&"blinded", &"frightened", &"poisoned", &"prone",
	&"restrained", &"stunned", &"unconscious", &"incapacitated"]
var _sources: Dictionary[StringName, Array] = {}

func add(condition: StringName, source: StringName = &"default") -> bool:
	if not condition in IDS or source == &"":
		return false
	if not _sources.has(condition):
		_sources[condition] = []
	if not source in _sources[condition]:
		_sources[condition].append(source)
	if condition == &"unconscious":
		add(&"prone", &"unconscious_fall")
	return true

func remove(condition: StringName, source: StringName = &"default") -> bool:
	if not _sources.has(condition) or not source in _sources[condition]:
		return false
	_sources[condition].erase(source)
	if _sources[condition].is_empty():
		_sources.erase(condition)
	return true

func has(condition: StringName) -> bool:
	if condition == &"incapacitated":
		return _sources.has(condition) or has(&"stunned") or has(&"unconscious")
	if condition == &"prone" and has(&"unconscious"):
		return true
	return _sources.has(condition)

func source_ids(condition: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_sources.get(condition, []))
	return result

func can_act() -> bool:
	return not has(&"incapacitated")

func speed_is_zero() -> bool:
	return has(&"restrained") or has(&"unconscious")

func can_speak() -> bool:
	return not has(&"incapacitated")

func can_concentrate() -> bool:
	return not has(&"incapacitated")

func must_drop_held_items() -> bool:
	return has(&"unconscious")

func is_aware() -> bool:
	return not has(&"unconscious")

func can_approach_fear() -> bool:
	return not has(&"frightened")

func automatically_fails_save(ability: StringName) -> bool:
	return ability in [&"str", &"dex"] and (has(&"stunned") or has(&"unconscious"))

func check_disadvantages(fear_visible: bool = false) -> Array[StringName]:
	var result: Array[StringName] = []
	if has(&"poisoned"):
		result.append(&"poisoned")
	if has(&"frightened") and fear_visible:
		result.append(&"frightened")
	return result

func attack_disadvantages(fear_visible: bool = false) -> Array[StringName]:
	var result: Array[StringName] = check_disadvantages(fear_visible)
	for condition: StringName in [&"blinded", &"prone", &"restrained"]:
		if has(condition):
			result.append(condition)
	return result

func incoming_advantages(distance_m: float) -> Array[StringName]:
	var result: Array[StringName] = []
	for condition: StringName in [&"blinded", &"restrained", &"stunned", &"unconscious"]:
		if has(condition):
			result.append(condition)
	if has(&"prone") and distance_m <= 1.5:
		result.append(&"prone_near")
	return result

func incoming_disadvantages(distance_m: float) -> Array[StringName]:
	var result: Array[StringName] = []
	if has(&"prone") and distance_m > 1.5:
		result.append(&"prone_far")
	return result

func stand_up() -> bool:
	if speed_is_zero() or not has(&"prone"):
		return false
	_sources.erase(&"prone")
	return true
