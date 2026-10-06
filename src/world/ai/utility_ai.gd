class_name UtilityAI
extends RefCounted
## Read-only, deterministic tactical evaluation. No roll or state mutation here.
## Every returned command is validated normally by CommandBus before it can act.

const EPSILON: float = 0.05
const PERSONALITIES: Dictionary = {
	"brute": preload("res://data/ai/brute.tres"),
	"archer": preload("res://data/ai/archer.tres"),
	"coward": preload("res://data/ai/coward.tres"),
}

static func consider(state: GameState, actor_id: String,
		tactical_points: Array[Vector3] = []) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if state == null or not state.actors.has(actor_id) or not state.pending.is_empty() \
			or state.current_actor_id() != actor_id or state.mode != &"combat":
		return options
	var actor: Dictionary = state.actors[actor_id]
	if int(actor.get("hp", 0)) <= 0:
		return options
	var personality: AIPersonality = PERSONALITIES.get(str(actor.get("personality", "brute")),
		PERSONALITIES["brute"]) as AIPersonality
	var targets: Array[String] = _targets(state, actor)
	var origin: Vector3 = actor.get("position", Vector3.ZERO)
	var can_act: bool = CombatRules.can_use_action(actor)
	var current_offense: float = _best_offense(state, actor_id, origin, targets, personality)
	for target_id: String in targets:
		var attack: Dictionary = CombatRules.attack_preview(state, actor_id, target_id)
		if can_act and bool(attack.get("legal", false)):
			var kill: float = _kill_chance(actor, state.actors[target_id], attack)
			options.append({"kind": &"attack", "score": _attack_score(attack, kill, personality),
				"reason_key": &"AI_FINISH_TARGET" if kill >= 0.25 else &"AI_ATTACK_TARGET",
				"target_id": target_id, "destination": origin,
				"breakdown": {"hit_chance": attack.get("chance", 0.0),
					"expected_damage": attack.get("expected_damage", 0.0), "kill_chance": kill}})
	var budget: float = float(actor.get("move_left", 0.0))
	var speed: float = float(actor.get("speed_m", 0.0))
	if CombatRules.conditions_for(actor).speed_is_zero():
		budget = 0.0
		speed = 0.0
	var movement_multiplier: float = 2.0 if CombatRules.conditions_for(actor).has(&"prone") else 1.0
	var current_position_score: float = _position_score(state, actor_id, origin, targets, personality)
	var goals: Array[Vector3] = _goals(state, actor_id, targets, tactical_points, personality)
	var visited: Array[Vector3] = []
	var best_safe_escape: Dictionary = {}
	var best_dash: Dictionary = {}
	for goal: Vector3 in goals:
		var full_path: PackedVector3Array = _path(origin, goal)
		if full_path.size() < 2 or full_path[full_path.size() - 1].distance_to(goal) > 0.61:
			continue
		var full_cost: float = CombatRules.move_cost(actor, full_path)
		if full_cost <= EPSILON:
			continue
		if can_act and speed > EPSILON and full_cost > budget + EPSILON:
			var dash_path: PackedVector3Array = _clip_path(full_path, (budget + speed) / movement_multiplier)
			var dash_destination: Vector3 = dash_path[dash_path.size() - 1]
			var dash_cost: float = CombatRules.move_cost(actor, dash_path)
			if not _occupied(state, actor_id, dash_destination):
				var future: float = _best_offense(state, actor_id, dash_destination, targets, personality)
				var dash_gain: float = _position_score(state, actor_id, dash_destination, targets, personality) - current_position_score
				var dash_score: float = future * 0.5 + dash_gain - current_offense \
					+ _approach_gain(state, actor, origin, dash_destination, targets) * 0.5 \
					- _opportunity_cost(state, actor_id, dash_path, personality) - dash_cost * 0.15 - 0.5
				if best_dash.is_empty() or dash_score > float(best_dash["score"]):
					best_dash = {"kind": &"dash", "score": dash_score, "reason_key": &"AI_DASH",
						"target_id": "", "destination": dash_destination, "breakdown": {"path_cost": dash_cost}}
		if budget <= EPSILON:
			continue
		var path: PackedVector3Array = _clip_path(full_path, budget / movement_multiplier)
		if path.size() < 2:
			continue
		var destination: Vector3 = path[path.size() - 1]
		if origin.distance_to(destination) <= EPSILON or _occupied(state, actor_id, destination) \
				or _near_any(destination, visited):
			continue
		visited.append(destination)
		var cost: float = CombatRules.move_cost(actor, path)
		var future_offense: float = _best_offense(state, actor_id, destination, targets, personality)
		var position_gain: float = _position_score(state, actor_id, destination, targets, personality) - current_position_score
		var opportunity: float = _opportunity_cost(state, actor_id, path, personality)
		var progress: float = _approach_gain(state, actor, origin, destination, targets)
		var score: float = position_gain + progress * 0.5 - cost * 0.15
		if can_act:
			score += future_offense * 0.9
		else:
			score += (future_offense - current_offense) * 0.35
		var reason: StringName = _move_reason(state, actor, destination, targets)
		var candidate: Dictionary = {"kind": &"move", "score": score - opportunity,
			"reason_key": reason, "target_id": "", "destination": destination,
			"breakdown": {"path_cost": cost, "position_gain": position_gain,
				"projected_attack": future_offense, "opportunity_cost": opportunity,
				"danger": _danger(state, actor_id, destination, targets)}}
		options.append(candidate)
		# Disengage spends the action: evaluate the actual subsequent safe move,
		# without pretending that an attack remains available in that turn.
		var escape_score: float = position_gain + progress * 0.5 - cost * 0.15
		if can_act and not bool(actor.get("disengaged", false)) and opportunity > 0.0 \
				and _nearest_distance(state, destination, targets) > _nearest_distance(state, origin, targets) + 0.5:
			if best_safe_escape.is_empty() or escape_score > float(best_safe_escape["score"]):
				best_safe_escape = {"kind": &"disengage", "score": escape_score,
					"reason_key": &"AI_DISENGAGE", "target_id": "", "destination": destination,
					"breakdown": {"avoided_opportunity_cost": opportunity, "position_gain": position_gain}}
	if not best_safe_escape.is_empty():
		options.append(best_safe_escape)
	if not best_dash.is_empty():
		options.append(best_dash)
	options.append({"kind": &"end_turn", "score": 0.0, "reason_key": &"AI_END_TURN",
		"target_id": "", "destination": origin, "breakdown": {}})
	# Geometry may reject a clipped destination or a condition may forbid an
	# action. The AI obeys exactly the public command validation contract.
	for index: int in range(options.size() - 1, -1, -1):
		var command: Command = command_for(options[index], actor_id)
		if command == null or command.validate(state) != OK:
			options.remove_at(index)
	options.sort_custom(_higher_score)
	return options

static func choose(state: GameState, actor_id: String,
		tactical_points: Array[Vector3] = []) -> Command:
	var options: Array[Dictionary] = consider(state, actor_id, tactical_points)
	return command_for(options[0], actor_id) if not options.is_empty() else null

static func command_for(option: Dictionary, actor_id: String) -> Command:
	match StringName(option.get("kind", &"")):
		&"attack":
			return AttackCommand.new(actor_id, str(option["target_id"]))
		&"move":
			return MoveCommand.new(actor_id, option["destination"])
		&"dash":
			return DashCommand.new(actor_id)
		&"disengage":
			return DisengageCommand.new(actor_id)
		&"end_turn":
			return EndTurnCommand.new(actor_id)
	return null

static func _targets(state: GameState, actor: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in state.actors:
		var other: Dictionary = state.actors[key]
		if int(other.get("hp", 0)) > 0 and other.get("team", "") != actor.get("team", ""):
			result.append(str(key))
	result.sort()
	return result

static func _goals(state: GameState, actor_id: String, targets: Array[String],
		points: Array[Vector3], personality: AIPersonality) -> Array[Vector3]:
	var goals: Array[Vector3] = points.duplicate()
	var actor: Dictionary = state.actors[actor_id]
	var origin: Vector3 = actor.get("position", Vector3.ZERO)
	var weapon: Dictionary = actor.get("weapon", {})
	var ranged: bool = weapon.get("ranged", false)
	var desired: float = personality.preferred_distance if ranged else float(weapon.get("reach", 1.5)) * 0.85
	for target_id: String in targets:
		var target_position: Vector3 = state.actors[target_id].get("position", Vector3.ZERO)
		var away: Vector3 = (origin - target_position).normalized()
		if away.length_squared() < 0.1:
			away = Vector3.RIGHT
		goals.append(target_position + away * desired)
		# Side approaches and the opposite of an ally create real flank paths;
		# no unrequested flanking attack bonus is silently granted.
		for side: float in [-1.0, 1.0]:
			goals.append(target_position + away.rotated(Vector3.UP, side * PI * 0.5) * desired)
		for key: Variant in state.actors:
			var ally: Dictionary = state.actors[key]
			if str(key) != actor_id and ally.get("team", "") == actor.get("team", "") and int(ally.get("hp", 0)) > 0:
				var ally_position: Vector3 = ally.get("position", Vector3.ZERO)
				if ally_position.distance_to(target_position) <= 3.0:
					goals.append(target_position + (target_position - ally_position).normalized() * desired)
		if ranged or _low_hp(actor):
			var escape_budget: float = float(actor.get("move_left", 0.0))
			if CombatRules.can_use_action(actor):
				escape_budget += float(actor.get("speed_m", 0.0))
			goals.append(origin + away * escape_budget)
	return goals

static func _best_offense(state: GameState, actor_id: String, position: Vector3,
		targets: Array[String], personality: AIPersonality) -> float:
	# Projected tactical quality must remain measurable after spending an action.
	var preview_state: GameState = state.copy()
	preview_state.actors[actor_id]["action_available"] = true
	var best: float = 0.0
	for target_id: String in targets:
		var preview: Dictionary = CombatRules.attack_preview(preview_state, actor_id, target_id, position)
		if bool(preview.get("legal", false)):
			best = maxf(best, _attack_score(preview,
				_kill_chance(state.actors[actor_id], state.actors[target_id], preview), personality))
	return best

static func _attack_score(preview: Dictionary, kill: float, personality: AIPersonality) -> float:
	return float(preview.get("chance", 0.0)) * personality.hit_weight \
		+ float(preview.get("expected_damage", 0.0)) * personality.damage_weight \
		+ kill * personality.kill_weight

static func _position_score(state: GameState, actor_id: String, position: Vector3,
		targets: Array[String], personality: AIPersonality) -> float:
	var actor: Dictionary = state.actors[actor_id]
	var score: float = -_danger(state, actor_id, position, targets) * personality.danger_weight
	var cover: float = 0.0
	var height: float = 0.0
	for target_id: String in targets:
		var target_position: Vector3 = state.actors[target_id].get("position", Vector3.ZERO)
		if CombatSpace.active != null:
			cover += minf(float(CombatSpace.active.cover(target_position, position)), 5.0)
		height += clampf(position.y - target_position.y, 0.0, 3.0)
	if not targets.is_empty():
		score += cover / targets.size() * personality.cover_weight
		score += height / targets.size() * personality.height_weight
		var nearest: float = _nearest_distance(state, position, targets)
		score += minf(nearest, personality.preferred_distance) * personality.spacing_weight
		if _low_hp(actor):
			score += minf(nearest, 18.0) * personality.retreat_weight
	return score

static func _danger(state: GameState, _actor_id: String, position: Vector3, targets: Array[String]) -> float:
	var danger: float = 0.0
	for target_id: String in targets:
		var other: Dictionary = state.actors[target_id]
		var weapon: Dictionary = other.get("weapon", {})
		var other_position: Vector3 = other.get("position", Vector3.ZERO)
		var distance: float = position.distance_to(other_position)
		if bool(weapon.get("ranged", false)):
			if distance <= float(weapon.get("long_range", weapon.get("range", 24.0))) \
					and (CombatSpace.active == null or CombatSpace.active.visible(other_position, position)):
				danger += 1.0
			continue
		var reach: float = float(weapon.get("reach", 1.5))
		if distance <= reach + EPSILON:
			# Count reachable opponents, not proximity multipliers: this enemy
			# can already attack next turn from farther away using its movement.
			# Ranged spacing and opportunity attacks have their own score terms.
			danger += 1.0
			continue
		# Seek an attack position rather than the occupied actor center: the
		# real navigation adapter correctly forbids occupied destinations.
		var attack_position: Vector3 = position + (other_position - position).normalized() * reach * 0.9
		var path: PackedVector3Array = _path(other_position, attack_position)
		if path.size() >= 2 and path[path.size() - 1].distance_to(attack_position) <= 0.61 \
				and CombatRules.path_length(path) <= float(other.get("speed_m", 9.0)):
			danger += 1.0
	return danger

static func _opportunity_cost(state: GameState, actor_id: String, path: PackedVector3Array,
		personality: AIPersonality) -> float:
	var result: float = 0.0
	for crossing: Dictionary in CombatRules.opportunity_crossings(state, actor_id, path):
		var crossing_state: GameState = state.copy()
		crossing_state.actors[actor_id]["position"] = crossing["position"]
		if crossing.has("weapon"):
			crossing_state.actors[crossing["actor_id"]]["weapon"] = crossing["weapon"]
		var target: Dictionary = crossing_state.actors[crossing["actor_id"]]
		var preview: Dictionary = CombatRules.attack_preview(crossing_state, crossing["actor_id"], actor_id)
		var lethal_chance: float = _kill_chance(target, state.actors[actor_id], preview)
		result += float(preview.get("expected_damage", 0.0)) * personality.opportunity_weight
		# A frightened near-dead creature must not value a long dash more than
		# surviving its first step; a safe Disengage remains a real alternative.
		result += lethal_chance * maxf(80.0, personality.retreat_weight * 36.0)
	return result

static func _path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if CombatSpace.active == null:
		return PackedVector3Array()
	return CombatSpace.active.query_path(from, to)

static func _clip_path(path: PackedVector3Array, budget: float) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	if path.is_empty():
		return result
	result.append(path[0])
	var remaining: float = budget
	for index: int in range(1, path.size()):
		var distance: float = path[index - 1].distance_to(path[index])
		if distance <= EPSILON:
			continue
		if distance > remaining:
			if remaining > EPSILON:
				result.append(path[index - 1].lerp(path[index], remaining / distance))
			break
		result.append(path[index])
		remaining -= distance
	return result

static func _occupied(state: GameState, actor_id: String, position: Vector3) -> bool:
	for key: Variant in state.actors:
		var actor: Dictionary = state.actors[key]
		if str(key) != actor_id and int(actor.get("hp", 0)) > 0:
			var other: Vector3 = actor.get("position", Vector3.ZERO)
			if position.distance_to(other) < 0.8:
				return true
	return false

static func _near_any(position: Vector3, points: Array[Vector3]) -> bool:
	for point: Vector3 in points:
		if point.distance_to(position) < 0.2:
			return true
	return false

static func _nearest_distance(state: GameState, position: Vector3, targets: Array[String]) -> float:
	var result: float = INF
	for target_id: String in targets:
		var other: Vector3 = state.actors[target_id].get("position", Vector3.ZERO)
		result = minf(result, position.distance_to(other))
	return result

static func _approach_gain(state: GameState, actor: Dictionary, from: Vector3,
		to: Vector3, targets: Array[String]) -> float:
	var weapon: Dictionary = actor.get("weapon", {})
	if targets.is_empty() or bool(weapon.get("ranged", false)) or _low_hp(actor):
		return 0.0
	return _nearest_distance(state, from, targets) - _nearest_distance(state, to, targets)

static func _move_reason(state: GameState, actor: Dictionary, destination: Vector3,
		targets: Array[String]) -> StringName:
	var origin: Vector3 = actor.get("position", Vector3.ZERO)
	if _low_hp(actor) and _nearest_distance(state, destination, targets) > _nearest_distance(state, origin, targets):
		return &"AI_RETREAT"
	if destination.y > origin.y + 1.0:
		return &"AI_HIGH_GROUND"
	for target_id: String in targets:
		var target_position: Vector3 = state.actors[target_id].get("position", Vector3.ZERO)
		if CombatSpace.active != null and CombatSpace.active.cover(target_position, destination) \
				> CombatSpace.active.cover(target_position, origin):
			return &"AI_COVER"
	var weapon: Dictionary = actor.get("weapon", {})
	return &"AI_KEEP_DISTANCE" if bool(weapon.get("ranged", false)) else &"AI_FLANK"

static func _low_hp(actor: Dictionary) -> bool:
	return float(actor.get("hp", 0)) / maxf(float(actor.get("max_hp", 1)), 1.0) < 0.3

static func _kill_chance(actor: Dictionary, target: Dictionary, preview: Dictionary) -> float:
	var weapon: Dictionary = actor.get("weapon", {})
	var parsed: Dictionary = Dice.parse(str(weapon.get("damage_dice", "1d6")))
	if parsed.has("error"):
		return 0.0
	var bonus: int = 0
	for modifier: RuleModifier in CombatRules.weapon_modifiers(weapon, "damage"):
		bonus += modifier.amount
	for modifier: RuleModifier in parsed["modifiers"]:
		bonus += modifier.amount
	var damage_type: String = str(weapon.get("damage_type", ""))
	if damage_type in target.get("immunities", []):
		return 0.0
	var required: int = int(target.get("hp", 0))
	# Invert resistance-before-vulnerability, including its floor, to obtain
	# the exact minimum raw damage required for a lethal result.
	if damage_type in target.get("vulnerabilities", []):
		required = ceili(float(required) / 2.0)
	if damage_type in target.get("resistances", []):
		required *= 2
	required -= bonus
	var count: int = int(parsed["count"])
	var sides: int = int(parsed["sides"])
	var chance: float = float(preview.get("chance", 0.0))
	var critical: float = float(preview.get("critical_chance", 0.05))
	return maxf(0.0, chance - critical) * _dice_at_least(count, sides, required) \
		+ minf(chance, critical) * _dice_at_least(count * 2, sides, required)

static func _dice_at_least(count: int, sides: int, required: int) -> float:
	if required <= count:
		return 1.0
	if required > count * sides:
		return 0.0
	# Exact finite distribution with a sliding convolution; all combat weapons
	# are small. Guard unrealistic imported expressions without consuming RNG.
	if required > 4096 or count > 1000:
		return 0.0
	var distribution: PackedFloat64Array = PackedFloat64Array()
	distribution.resize(required)
	distribution[0] = 1.0
	for die: int in range(count):
		var next: PackedFloat64Array = PackedFloat64Array()
		next.resize(required)
		var window: float = 0.0
		for total: int in range(1, required):
			window += distribution[total - 1]
			if total - sides - 1 >= 0:
				window -= distribution[total - sides - 1]
			next[total] = window / sides
		distribution = next
	var below: float = 0.0
	for probability: float in distribution:
		below += probability
	return clampf(1.0 - below, 0.0, 1.0)

static func _higher_score(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["score"]), float(b["score"])):
		return float(a["score"]) > float(b["score"])
	# Stable tie breaking avoids invisible randomness and replay differences.
	return str(a["kind"]) + str(a["target_id"]) + str(a["destination"]) \
		< str(b["kind"]) + str(b["target_id"]) + str(b["destination"])
