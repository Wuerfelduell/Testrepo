class_name CombatRules
extends RefCounted
## Deterministic encounter rules. RNG is supplied only by commands at impact/start.

const EPSILON: float = 0.00001
const HEIGHT_ADVANTAGE_M: float = 1.5
const WALK_SPEED_M_S: float = 3.0
const ATTACK_DURATION: float = 0.8
const ATTACK_IMPACT_TIME: float = 0.4

static func alive(actor: Dictionary) -> bool:
	return int(actor.get("hp", 0)) > 0

static func conditions_for(actor: Dictionary) -> ConditionState:
	var conditions: ConditionState = ConditionState.new()
	for condition: String in actor.get("conditions", []):
		conditions.add(StringName(condition))
	return conditions

static func valid_actor_turn(state: GameState, actor_id: String) -> Error:
	if not state.actors.has(actor_id) or not alive(state.actors[actor_id]):
		return ERR_INVALID_PARAMETER
	if state.mode != &"combat" or state.current_actor_id() != actor_id:
		return ERR_UNAUTHORIZED
	if not state.pending.is_empty():
		return ERR_BUSY
	return OK

static func can_use_action(actor: Dictionary) -> bool:
	return bool(actor.get("action_available", false)) and conditions_for(actor).can_act()

static func begin_turn(state: GameState, actor_id: String) -> void:
	var actor: Dictionary = state.actors[actor_id]
	actor["action_available"] = true
	actor["bonus_available"] = true
	actor["reaction_available"] = true
	actor["disengaged"] = false
	actor["move_left"] = 0.0 if conditions_for(actor).speed_is_zero() else float(actor["speed_m"])

static func path_length(path: PackedVector3Array) -> float:
	var result: float = 0.0
	for index: int in range(1, path.size()):
		result += path[index - 1].distance_to(path[index])
	return result

static func position_on_path(path: PackedVector3Array, distance: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	var remaining: float = maxf(0.0, distance)
	for index: int in range(1, path.size()):
		var length: float = path[index - 1].distance_to(path[index])
		if length > EPSILON and remaining <= length:
			return path[index - 1].lerp(path[index], remaining / length)
		remaining -= length
	return path[path.size() - 1]

static func movement_path(state: GameState, actor_id: String, destination: Vector3) -> PackedVector3Array:
	if not destination.is_finite() or not state.actors.has(actor_id):
		return PackedVector3Array()
	var origin: Vector3 = state.actors[actor_id]["position"]
	var path: PackedVector3Array = CombatSpace.current().query_path(origin, destination)
	if path.size() < 2 or not path[0].is_equal_approx(origin) or path[-1].distance_to(destination) > 0.61:
		return PackedVector3Array()
	for point: Vector3 in path:
		if not point.is_finite():
			return PackedVector3Array()
	return path

static func move_cost(actor: Dictionary, path: PackedVector3Array) -> float:
	return path_length(path) * (2.0 if conditions_for(actor).has(&"prone") else 1.0)

static func weapon_valid(weapon: Dictionary) -> bool:
	if not weapon.get("ranged", false) is bool or not weapon.get("damage_dice") is String or \
			not weapon.get("damage_type") is String or Dice.parse(weapon["damage_dice"]).has("error") or \
			not StringName(weapon["damage_type"]) in DamageRules.TYPES:
		return false
	for field: String in ["reach", "range", "long_range"]:
		var value: Variant = weapon.get(field, 1.5 if field == "reach" else 0.0)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
			return false
	if bool(weapon.get("ranged", false)) and (float(weapon.get("range", 0.0)) <= 0.0 or \
			float(weapon.get("long_range", weapon.get("range", 0.0))) < float(weapon.get("range", 0.0))):
		return false
	for kind: String in ["attack", "damage"]:
		if weapon.has(kind + "_modifiers"):
			var modifiers: Variant = weapon[kind + "_modifiers"]
			if not modifiers is Array or modifiers.size() > Dice.MAX_DICE:
				return false
			for modifier: Variant in modifiers:
				if not modifier is Dictionary or not modifier.get("amount") is int or \
						not modifier.get("source") is String or String(modifier["source"]).is_empty() or \
						absi(int(modifier["amount"])) > Dice.MAX_MODIFIER:
					return false
		elif not weapon.get(kind + "_bonus", 0) is int or absi(int(weapon.get(kind + "_bonus", 0))) > Dice.MAX_MODIFIER:
			return false
	var extras: Variant = weapon.get("extra_damage", [])
	if not extras is Array or extras.size() > 16:
		return false
	for extra: Variant in extras:
		if not extra is Dictionary or not extra.get("amount") is int or int(extra["amount"]) < 0 or \
				int(extra["amount"]) > Dice.MAX_MODIFIER or not extra.get("damage_type") is String or \
				not StringName(extra["damage_type"]) in DamageRules.TYPES or not extra.get("source") is String or \
				String(extra["source"]).is_empty():
			return false
	return true

static func opportunity_weapon(actor: Dictionary) -> Dictionary:
	var primary: Dictionary = actor.get("weapon", {})
	if not bool(primary.get("ranged", false)) and weapon_valid(primary):
		return primary
	for alternative: Dictionary in actor.get("attacks", []):
		if not bool(alternative.get("ranged", false)) and weapon_valid(alternative):
			return alternative
	return {}

static func weapon_modifiers(weapon: Dictionary, kind: String) -> Array[RuleModifier]:
	var result: Array[RuleModifier] = []
	if weapon.has(kind + "_modifiers"):
		for modifier: Dictionary in weapon[kind + "_modifiers"]:
			result.append(RuleModifier.new(int(modifier["amount"]), StringName(modifier["source"])))
	else:
		result.append(RuleModifier.new(int(weapon.get(kind + "_bonus", 0)), StringName("weapon_" + kind)))
	return result

static func attack_preview(state: GameState, attacker_id: String, target_id: String,
		from_position: Vector3 = Vector3.INF, attack_weapon: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"chance": 0.0, "expected_damage": 0.0, "cover": 0,
		"advantage": 0, "legal": false, "distance": 0.0, "armor_class": 0,
		"advantages": [], "disadvantages": [], "critical_chance": 0.0}
	if attacker_id == target_id or not state.actors.has(attacker_id) or not state.actors.has(target_id):
		return result
	var attacker: Dictionary = state.actors[attacker_id]
	var target: Dictionary = state.actors[target_id]
	if not alive(attacker) or not alive(target) or attacker.get("team") == target.get("team"):
		return result
	var weapon: Dictionary = attacker.get("weapon", {}) if attack_weapon.is_empty() else attack_weapon
	if not attacker.get("position") is Vector3 or not target.get("position") is Vector3:
		return result
	if not weapon_valid(weapon) or not conditions_for(attacker).can_act():
		return result
	var origin: Vector3 = attacker["position"] if from_position == Vector3.INF else from_position
	var destination: Vector3 = target["position"]
	if not origin.is_finite() or not destination.is_finite():
		return result
	var distance: float = origin.distance_to(destination)
	var ranged: bool = bool(weapon.get("ranged", false))
	var reach: float = float(weapon.get("reach", 1.5))
	var normal_range: float = float(weapon.get("range", 0.0))
	var long_range: float = float(weapon.get("long_range", normal_range))
	var geometry: CombatSpace = CombatSpace.current()
	var cover_value: int = geometry.cover(origin, destination)
	result["cover"] = cover_value
	result["distance"] = distance
	result["armor_class"] = int(target.get("ac", 10)) + cover_value
	if cover_value >= 99 or not geometry.visible(origin, destination) or \
			distance > (long_range if ranged else reach) + EPSILON:
		return result
	var advantages: Array[StringName] = conditions_for(target).incoming_advantages(distance)
	var disadvantages: Array[StringName] = conditions_for(attacker).attack_disadvantages()
	disadvantages.append_array(conditions_for(target).incoming_disadvantages(distance))
	if ranged:
		if origin.y - destination.y >= HEIGHT_ADVANTAGE_M:
			advantages.append(&"height")
		if distance > normal_range:
			disadvantages.append(&"long_range")
		for enemy_id: String in state.actors:
			var enemy: Dictionary = state.actors[enemy_id]
			if enemy.get("team") != attacker.get("team") and alive(enemy) and \
					conditions_for(enemy).can_act() and not conditions_for(enemy).has(&"blinded") and \
					origin.distance_to(enemy["position"]) <= 1.5 + EPSILON and \
					geometry.visible(enemy["position"], origin):
				disadvantages.append(&"ranged_in_melee")
				break
	var advantage: int = 0
	if not advantages.is_empty() and disadvantages.is_empty():
		advantage = 1
	elif advantages.is_empty() and not disadvantages.is_empty():
		advantage = -1
	var bonus: int = 0
	for modifier: RuleModifier in weapon_modifiers(weapon, "attack"):
		bonus += modifier.amount
	var chance: float = clampf(float(21 + bonus - int(result["armor_class"])) / 20.0, 0.05, 0.95)
	var crit_chance: float = 0.05
	if advantage > 0:
		chance = 1.0 - pow(1.0 - chance, 2.0)
		crit_chance = 1.0 - pow(0.95, 2.0)
	elif advantage < 0:
		chance *= chance
		crit_chance = 0.0025
	if conditions_for(target).has(&"unconscious") and distance <= 1.5:
		crit_chance = chance
	var parsed: Dictionary = Dice.parse(String(weapon["damage_dice"]))
	var average_dice: float = int(parsed["count"]) * (int(parsed["sides"]) + 1) / 2.0
	var flat_damage: int = 0
	for modifier: RuleModifier in parsed["modifiers"]:
		flat_damage += modifier.amount
	for modifier: RuleModifier in weapon_modifiers(weapon, "damage"):
		flat_damage += modifier.amount
	result["chance"] = chance
	result["critical_chance"] = crit_chance
	var expected_damage: float = chance * maxf(0.0, average_dice + flat_damage) + crit_chance * average_dice
	for extra: Dictionary in weapon.get("extra_damage", []):
		expected_damage += chance * int(extra["amount"])
	result["expected_damage"] = expected_damage
	result["advantage"] = advantage
	result["advantages"] = advantages
	result["disadvantages"] = disadvantages
	result["legal"] = true
	return result

## First exit from each threatened sphere along the entire path, including enter-then-exit.
## At the boundary, the attack resolves just BEFORE the mover leaves melee reach.
static func opportunity_crossings(state: GameState, mover_id: String,
		path: PackedVector3Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var mover: Dictionary = state.actors[mover_id]
	if bool(mover.get("disengaged", false)):
		return result
	for enemy_id: String in state.actors:
		var enemy: Dictionary = state.actors[enemy_id]
		var weapon: Dictionary = opportunity_weapon(enemy)
		if weapon.is_empty():
			continue
		if enemy.get("team") == mover.get("team") or not alive(enemy) or \
				bool(weapon.get("ranged", false)) or not bool(enemy.get("reaction_available", false)) or \
				not conditions_for(enemy).can_act() or conditions_for(enemy).has(&"blinded"):
			continue
		var center: Vector3 = enemy["position"]
		var radius: float = float(weapon.get("reach", 1.5))
		var traveled: float = 0.0
		for index: int in range(1, path.size()):
			var direction: Vector3 = path[index] - path[index - 1]
			var length: float = direction.length()
			if length <= EPSILON:
				continue
			var offset: Vector3 = path[index - 1] - center
			var a: float = direction.length_squared()
			var b: float = 2.0 * offset.dot(direction)
			var c: float = offset.length_squared() - radius * radius
			var discriminant: float = b * b - 4.0 * a * c
			if discriminant > EPSILON:
				var exit_fraction: float = (-b + sqrt(discriminant)) / (2.0 * a)
				# Ending on the boundary does not leave reach. The following segment
				# handles an exit at fraction zero if movement continues outward.
				if exit_fraction >= -EPSILON and exit_fraction < 1.0 - EPSILON:
					var distance: float = traveled + maxf(0.0, exit_fraction) * length
					var position: Vector3 = position_on_path(path, distance)
					if CombatSpace.current().visible(center, position):
						result.append({"actor_id": enemy_id, "distance": distance, "position": position, "weapon": weapon.duplicate(true)})
						break
			traveled += length
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if is_equal_approx(float(left["distance"]), float(right["distance"])):
			return String(left["actor_id"]) < String(right["actor_id"])
		return float(left["distance"]) < float(right["distance"]))
	return result

static func attack_pending(attacker_id: String, target_id: String, opportunity: bool = false, weapon: Dictionary = {}) -> Dictionary:
	return {"type": "attack", "actor_id": attacker_id, "target_id": target_id,
		"elapsed": 0.0, "duration": ATTACK_DURATION, "impact_time": ATTACK_IMPACT_TIME,
		"impacted": false, "opportunity": opportunity, "weapon": weapon.duplicate(true)}

static func attack_start_event(pending: Dictionary) -> Dictionary:
	return {"type": "start_attack", "actor_id": pending["actor_id"], "target_id": pending["target_id"],
		"opportunity": pending["opportunity"], "duration": pending["duration"], "impact_time": pending["impact_time"],
		"weapon": pending.get("weapon", {}).duplicate(true)}

static func serialize_roll(roll: DiceResult) -> Dictionary:
	var groups: Array[Dictionary] = []
	for group: DiceResult.Group in roll.groups:
		groups.append({"sides": group.sides, "values": group.values.duplicate(),
			"kept_indices": group.kept_indices.duplicate(), "source": String(group.source),
			"critical": group.critical})
	var modifiers: Array[Dictionary] = []
	for modifier: RuleModifier in roll.modifiers:
		modifiers.append({"amount": modifier.amount, "source": String(modifier.source)})
	return {"groups": groups, "modifiers": modifiers, "total": roll.total,
		"natural_20": roll.natural_20, "natural_1": roll.natural_1, "mode": String(roll.mode),
		"advantage_sources": roll.advantage_sources.duplicate(),
		"disadvantage_sources": roll.disadvantage_sources.duplicate()}

static func resolve_impact(state: GameState, pending: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var attacker_id: String = pending["actor_id"]
	var target_id: String = pending["target_id"]
	var override_weapon: Dictionary = pending.get("weapon", {})
	var preview: Dictionary = attack_preview(state, attacker_id, target_id, Vector3.INF, override_weapon)
	if not bool(preview["legal"]):
		return events
	var attacker: Dictionary = state.actors[attacker_id]
	var target: Dictionary = state.actors[target_id]
	var weapon: Dictionary = attacker["weapon"] if override_weapon.is_empty() else override_weapon
	var context: RollContext = RollContext.new()
	# Preview already combines all geometry and condition sources; passing the same
	# defender again would duplicate source labels. Its unconscious crit is handled below.
	context.advantages.assign(preview["advantages"])
	context.disadvantages.assign(preview["disadvantages"])
	var attack: Attacks.Result = Attacks.resolve(int(preview["armor_class"]),
		weapon_modifiers(weapon, "attack"), rng, context)
	if attack.hit and conditions_for(target).has(&"unconscious") and float(preview["distance"]) <= 1.5:
		attack.critical = true
	events.append({"type": "roll", "kind": "attack", "actor_id": attacker_id, "target_id": target_id,
		"roll": serialize_roll(attack.roll), "armor_class": preview["armor_class"],
		"hit": attack.hit, "critical": attack.critical, "cover": preview["cover"]})
	if not attack.hit:
		return events
	var defenses: DamageRules.Defenses = DamageRules.Defenses.new()
	defenses.resistances.assign(target.get("resistances", []))
	defenses.vulnerabilities.assign(target.get("vulnerabilities", []))
	defenses.immunities.assign(target.get("immunities", []))
	var damage: DamageRules.Result = DamageRules.roll(String(weapon["damage_dice"]),
		StringName(weapon["damage_type"]), rng, weapon_modifiers(weapon, "damage"), attack.critical, defenses)
	events.append({"type": "roll", "kind": "damage", "actor_id": attacker_id, "target_id": target_id,
		"roll": serialize_roll(damage.roll), "damage_type": weapon["damage_type"], "amount": damage.total})
	target["hp"] = maxi(0, int(target["hp"]) - damage.total)
	events.append({"type": "damage", "actor_id": attacker_id, "target_id": target_id,
		"amount": damage.total, "damage_type": weapon["damage_type"], "hp": target["hp"]})
	# A separate typed damage instance: flat riders are never critical dice.
	for extra: Dictionary in weapon.get("extra_damage", []):
		var extra_result: DamageRules.Result = DamageRules.apply(int(extra["amount"]),
			StringName(extra["damage_type"]), defenses)
		target["hp"] = maxi(0, int(target["hp"]) - extra_result.total)
		var extra_roll: DiceResult = DiceResult.new()
		extra_roll.add_modifiers([RuleModifier.new(int(extra["amount"]), StringName(extra["source"]))])
		events.append({"type": "roll", "kind": "damage", "actor_id": attacker_id, "target_id": target_id,
			"roll": serialize_roll(extra_roll), "damage_type": extra["damage_type"], "amount": extra_result.total})
		events.append({"type": "damage", "actor_id": attacker_id, "target_id": target_id,
			"amount": extra_result.total, "damage_type": extra["damage_type"], "hp": target["hp"]})
	if int(target["hp"]) <= 0:
		events.append({"type": "death", "actor_id": target_id, "killer_id": attacker_id})
		events.append_array(check_combat_end(state))
	return events

static func check_combat_end(state: GameState) -> Array[Dictionary]:
	var enemy_alive: bool = false
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		if actor.get("team") == "hero" and not alive(actor):
			state.mode = &"defeat"
		elif actor.get("team") == "enemy" and alive(actor):
			enemy_alive = true
	if state.mode != &"defeat" and not enemy_alive:
		state.mode = &"exploration"
	var events: Array[Dictionary] = []
	if state.mode != &"combat":
		state.pending = {}
		events.append({"type": "combat_end", "mode": String(state.mode)})
	return events
