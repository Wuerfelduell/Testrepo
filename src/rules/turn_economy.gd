class_name TurnEconomy
extends RefCounted
## begin_turn resets ONLY this creature, including its reaction (SRD p. 10).
## Conditions are live: recovery during the turn restores unspent opportunities.

var conditions: ConditionState = ConditionState.new()
var base_speed_m: float = 9.0
var action_spent: bool = false
var bonus_action_spent: bool = false
var reaction_spent: bool = false
var movement_spent_m: float = 0.0
var additional_movement_m: float = 0.0

func begin_turn(speed_m: float) -> bool:
	if not is_finite(speed_m) or speed_m < 0.0:
		return false
	base_speed_m = speed_m
	action_spent = false
	bonus_action_spent = false
	reaction_spent = false
	movement_spent_m = 0.0
	additional_movement_m = 0.0
	return true

func speed_m() -> float:
	return 0.0 if conditions.speed_is_zero() else base_speed_m

func remaining_m() -> float:
	if conditions.speed_is_zero():
		return 0.0
	return maxf(0.0, speed_m() + additional_movement_m - movement_spent_m)

func spend_action() -> bool:
	if action_spent or not conditions.can_act():
		return false
	action_spent = true
	return true

func spend_bonus_action(granted_by_rule: bool) -> bool:
	if not granted_by_rule or bonus_action_spent or not conditions.can_act():
		return false
	bonus_action_spent = true
	return true

func spend_reaction() -> bool:
	if reaction_spent or not conditions.can_act():
		return false
	reaction_spent = true
	return true

func dash() -> bool:
	if not spend_action():
		return false
	additional_movement_m += speed_m()
	return true

func move(distance_m: float, difficult_terrain: bool = false, toward_fear: bool = false) -> bool:
	if not is_finite(distance_m) or distance_m < 0.0 or conditions.speed_is_zero():
		return false
	if toward_fear and not conditions.can_approach_fear():
		return false
	# Crawling and difficult terrain each add one foot per foot moved (SRD p. 178).
	var multiplier: float = 1.0 + (1.0 if difficult_terrain else 0.0) + (1.0 if conditions.has(&"prone") else 0.0)
	var cost: float = distance_m * multiplier
	if cost > remaining_m() + 0.000001:
		return false
	movement_spent_m += cost
	return true

func stand_up() -> bool:
	if not conditions.has(&"prone") or speed_m() <= 0.0:
		return false
	# Round in source units (feet), then convert. Never round 4.5 m down to 4 m.
	var cost: float = floor((speed_m() / 0.3 + 0.000001) / 2.0) * 0.3
	if cost > remaining_m() + 0.000001:
		return false
	if not conditions.stand_up():
		return false
	movement_spent_m += cost
	return true
