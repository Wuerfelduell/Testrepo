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

static func begin_turn(state: GameState, actor_id: String) -> Array[Dictionary]:
	# Spell effects lasting "until the start of your next turn" end before resources refresh.
	var events: Array[Dictionary] = ActiveEffects.on_turn_start(state, actor_id)
	var actor: Dictionary = state.actors[actor_id]
	actor["action_available"] = true
	actor["bonus_available"] = true
	actor["reaction_available"] = true
	actor["disengaged"] = false
	# Extra Attack: further attacks of an Attack action already taken this turn.
	actor["attacks_left"] = 0
	actor["moved_this_turn"] = false
	# Dual wielding: an Attack action with a Light weapon this turn, and the off-hand attack.
	actor["light_attack_made"] = false
	actor["offhand_used"] = false
	actor["move_left"] = 0.0 if conditions_for(actor).speed_is_zero() else \
		maxf(0.0, float(actor["speed_m"]) - ActiveEffects.speed_penalty(actor))
	if ActiveEffects.in_hostile_aura(state, actor_id) or DivineSpellEffects.slowing_zone(state, actor_id):
		# Spirit Guardians halve the speed of enemies inside (judged at the start of the turn).
		actor["move_left"] = float(actor["move_left"]) * 0.5
	events.append_array(reveal_hidden(state))
	events.append_array(ClassKits.on_turn_start(state, actor_id))
	return events

## SRD 5.2 Light property: after an Attack action with a Light weapon, one extra attack
## with a different Light weapon in the other hand as a Bonus Action (Nick mastery: no
## Bonus Action), without the ability modifier on its damage unless that is negative.
## "" when the actor may make it now, else a translation key.
static func offhand_reason(state: GameState, actor_id: String) -> String:
	var actor: Dictionary = state.actors.get(actor_id, {})
	var offhand: Dictionary = actor.get("off_hand_weapon", {})
	if offhand.is_empty():
		return "COMBAT_OFFHAND_NONE"
	if valid_actor_turn(state, actor_id) != OK:
		return "COMBAT_WAIT_TURN"
	if not "light" in actor.get("weapon", {}).get("properties", []):
		return "COMBAT_OFFHAND_NOT_LIGHT"
	if not bool(actor.get("light_attack_made", false)):
		return "COMBAT_OFFHAND_ATTACK_FIRST"
	if bool(actor.get("offhand_used", false)) or not conditions_for(actor).can_act():
		return "COMBAT_OFFHAND_USED"
	if offhand_needs_bonus(actor) and not bool(actor.get("bonus_available", false)):
		return "COMBAT_NO_BONUS"
	return ""

## Nick (Weapon Mastery): the off-hand attack is part of the Attack action.
static func offhand_needs_bonus(actor: Dictionary) -> bool:
	return WeaponMasteries.mastery_of(actor, actor.get("off_hand_weapon", {})) != "nick"

## The off-hand weapon as an attack: no positive ability modifier on the damage.
static func offhand_weapon(actor: Dictionary) -> Dictionary:
	var weapon: Dictionary = actor.get("off_hand_weapon", {}).duplicate(true)
	if weapon.is_empty():
		return weapon
	var kept: Array = []
	for modifier: Dictionary in weapon.get("damage_modifiers", []):
		if not String(modifier.get("source", "")) in ["str", "dex"] or int(modifier.get("amount", 0)) < 0:
			kept.append(modifier)
	weapon["damage_modifiers"] = kept
	weapon["damage_bonus"] = mini(0, int(weapon.get("damage_bonus", 0)))
	weapon["offhand"] = true
	return weapon

## Hiding needs Three-Quarters Cover or no line of sight from every enemy (SRD 5.2 Hide).
static func hidden_from_enemies(state: GameState, actor_id: String) -> bool:
	var actor: Dictionary = state.actors[actor_id]
	var geometry: CombatSpace = CombatSpace.current()
	for enemy_id: String in state.actors:
		var enemy: Dictionary = state.actors[enemy_id]
		if enemy.get("team") == actor.get("team") or not alive(enemy) or not conditions_for(enemy).can_act() or \
				conditions_for(enemy).has(&"blinded"):
			continue
		if geometry.cover(enemy["position"], actor["position"]) < 5:
			return false
	return true

## An enemy finds a hidden creature that stands in its open sight: checked at the start of
## every turn, so stepping out of hiding and striking in the same turn still works.
static func reveal_hidden(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		if ActiveEffects.has_kind(actor, ActiveEffects.HIDDEN) and \
				(not alive(actor) or not hidden_from_enemies(state, id)):
			ActiveEffects.remove_where(actor, func(effect: Dictionary) -> bool:
				return String(effect.get("kind", "")) == ActiveEffects.HIDDEN)
			events.append({"type": "hidden_end", "actor_id": id, "reason": "found"})
	return events

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
	if not alive(attacker) or not alive(target) or attacker.get("team") == target.get("team") or \
			DivineSpellEffects.untargetable(target):
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
	result["armor_class"] = ClassEffects.armor_class(target) + cover_value
	if cover_value >= 99 or not geometry.visible(origin, destination) or \
			distance > (long_range if ranged else reach) + EPSILON:
		return result
	var advantages: Array[StringName] = conditions_for(target).incoming_advantages(distance)
	advantages.append_array(ClassKits.attack_advantages(state, attacker_id, target_id, weapon))
	advantages.append_array(ClassEffects.attack_advantages(state, attacker_id, target_id, weapon))
	# Hidden, Steady Aim and a first strike (effects on the attacker); attacks against a hidden target.
	advantages.append_array(ActiveEffects.attack_advantages(attacker))
	var disadvantages: Array[StringName] = conditions_for(attacker).attack_disadvantages()
	disadvantages.append_array(ClassKits.attack_disadvantages(state, attacker_id, target_id, weapon))
	disadvantages.append_array(ActiveEffects.attack_disadvantages(attacker))
	disadvantages.append_array(ActiveEffects.incoming_disadvantages(target))
	disadvantages.append_array(DivineSpellEffects.attack_disadvantages(state, attacker_id, target_id))
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
	var bonus: int = ClassEffects.attack_bonus_estimate(attacker, weapon)
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
	if (conditions_for(target).has(&"unconscious") or conditions_for(target).has(&"paralyzed")) and distance <= 1.5:
		crit_chance = chance
	var parsed: Dictionary = Dice.parse(String(weapon["damage_dice"]))
	var average_dice: float = int(parsed["count"]) * (int(parsed["sides"]) + 1) / 2.0
	var flat_damage: int = 0
	for modifier: RuleModifier in parsed["modifiers"]:
		flat_damage += modifier.amount
	for modifier: RuleModifier in weapon_modifiers(weapon, "damage"):
		flat_damage += modifier.amount
	for modifier: RuleModifier in ClassKits.damage_bonus(state, attacker_id, target_id, weapon):
		flat_damage += modifier.amount
	for modifier: RuleModifier in DivineSpellEffects.damage_modifiers(attacker, weapon):
		flat_damage += modifier.amount
	result["chance"] = chance
	result["critical_chance"] = crit_chance
	var expected_damage: float = chance * maxf(0.0, average_dice + flat_damage) + crit_chance * average_dice
	for extra: Dictionary in weapon.get("extra_damage", []):
		expected_damage += chance * int(extra["amount"])
	expected_damage += chance * ClassKits.expected_extra_damage(state, attacker_id, target_id, weapon)
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

## SRD 5.2 Weapon Mastery Graze: a miss still deals the attack's ability modifier as
## damage of the weapon's type (never less than 0, no dice, not increased otherwise).
static func _graze(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var attacker: Dictionary = state.actors.get(attacker_id, {})
	if String(weapon.get("mastery", "")) != "graze" or not attacker.get("features", {}).has("weapon_mastery"):
		return events
	var ability: Dictionary = {}
	for modifier: Dictionary in weapon.get("damage_modifiers", []):
		if String(modifier.get("source", "")) in ["str", "dex"]:
			ability = modifier
	var amount: int = int(ability.get("amount", 0))
	var target: Dictionary = state.actors[target_id]
	if amount <= 0 or not alive(target):
		return events
	var result: DamageRules.Result = DamageRules.apply(amount, StringName(weapon["damage_type"]), defenses_for(target))
	var lost: int = ClassEffects.lose_hp(state, target_id, result.total, rng)
	var roll: DiceResult = DiceResult.new()
	roll.add_modifiers([RuleModifier.new(amount, &"graze")])
	events.append({"type": "roll", "kind": "damage", "actor_id": attacker_id, "target_id": target_id,
		"roll": serialize_roll(roll), "damage_type": weapon["damage_type"], "amount": lost, "graze": true})
	events.append({"type": "damage", "actor_id": attacker_id, "target_id": target_id,
		"amount": lost, "damage_type": weapon["damage_type"], "hp": target["hp"], "graze": true})
	events.append_array(ActiveEffects.after_damage(state, target_id, lost, rng))
	if int(target["hp"]) <= 0:
		events.append(NonlethalFights.fall_event(state, target_id, attacker_id))
		events.append_array(check_combat_end(state))
	return events

## SRD 5.2 Great Weapon Fighting: with a melee weapon held in two hands (Two-Handed or
## Versatile), a 1 or 2 on a damage die counts as a 3.
static func damage_die_minimum(attacker: Dictionary, weapon: Dictionary) -> int:
	if String(attacker.get("features", {}).get("fighting_style", "")) != "great_weapon_fighting":
		return 0
	if bool(weapon.get("ranged", false)) or not weapon.get("spell_id", "") in ["", null]:
		return 0
	var two_hands: bool = bool(weapon.get("two_handed_grip", false)) or "two_handed" in weapon.get("properties", [])
	return 3 if two_hands else 0

static func serialize_roll(roll: DiceResult) -> Dictionary:
	var groups: Array[Dictionary] = []
	for group: DiceResult.Group in roll.groups:
		groups.append({"sides": group.sides, "values": group.values.duplicate(),
			"kept_indices": group.kept_indices.duplicate(), "source": String(group.source),
			"critical": group.critical, "raised_indices": group.raised_indices.duplicate(),
			"rolled": group.rolled.duplicate()})
	var modifiers: Array[Dictionary] = []
	for modifier: RuleModifier in roll.modifiers:
		modifiers.append({"amount": modifier.amount, "source": String(modifier.source)})
	return {"groups": groups, "modifiers": modifiers, "total": roll.total,
		"natural_20": roll.natural_20, "natural_1": roll.natural_1, "mode": String(roll.mode),
		"advantage_sources": roll.advantage_sources.duplicate(),
		"disadvantage_sources": roll.disadvantage_sources.duplicate()}

static func resolve_impact(state: GameState, pending: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var attacker_id: String = pending["actor_id"]
	if not state.actors.has(attacker_id):
		return []
	var override_weapon: Dictionary = pending.get("weapon", {})
	var weapon: Dictionary = state.actors[attacker_id].get("weapon", {}) if override_weapon.is_empty() else override_weapon
	return resolve_attack(state, attacker_id, pending["target_id"], weapon, rng, pending)

## Rolls the attack. A hit that Shield could turn into a miss pauses here: the
## target's reaction decision (CastReactionCommand) completes it with finish_attack.
static func resolve_attack(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		rng: RandomNumberGenerator, source_pending: Dictionary = {}) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var preview: Dictionary = attack_preview(state, attacker_id, target_id, Vector3.INF, weapon)
	if not bool(preview["legal"]):
		return events
	var attacker: Dictionary = state.actors[attacker_id]
	var target: Dictionary = state.actors[target_id]
	var context: RollContext = RollContext.new()
	# Preview already combines all geometry and condition sources; passing the same
	# defender again would duplicate source labels. Its unconscious crit is handled below.
	context.advantages.assign(preview["advantages"])
	context.disadvantages.assign(preview["disadvantages"])
	var modifiers: Array[RuleModifier] = weapon_modifiers(weapon, "attack")
	modifiers.append_array(ClassEffects.attack_modifiers(attacker, rng, weapon))
	var attack: Attacks.Result = Attacks.resolve(int(preview["armor_class"]), modifiers, rng, context)
	ActiveEffects.consume_attack_riders(attacker)
	ClassEffects.consume_on_attacked(target)
	if not attack.hit and not ActiveEffects.inspire_roll(attacker, attack.roll, int(preview["armor_class"]), rng).is_empty():
		# Bardic Inspiration turned the miss into a hit (the die is in the roll's modifiers).
		attack.hit = true
	if attack.hit and (conditions_for(target).has(&"unconscious") or conditions_for(target).has(&"paralyzed")) \
			and float(preview["distance"]) <= 1.5:
		attack.critical = true
	var outcome: Dictionary = {"roll": serialize_roll(attack.roll), "armor_class": preview["armor_class"],
		"hit": attack.hit, "critical": attack.critical, "cover": preview["cover"],
		"natural_20": attack.roll.natural_20}
	if attack.hit and not attack.roll.natural_20 and attack.roll.total < int(preview["armor_class"]) + 5 \
			and SpellResolver.shield_option(state, target_id):
		state.pending = SpellResolver.reaction_pending(target_id, attacker_id, source_pending,
			{"attack": outcome, "weapon": weapon.duplicate(true), "target_id": target_id})
		events.append(SpellResolver.reaction_offer_event(state.pending))
		return events
	# A reaction that halves the damage (Rogue Uncanny Dodge) is offered before damage rolls.
	var halving: String = ClassKits.damage_halved_by(state, attacker_id, target_id, weapon) if attack.hit else ""
	if not halving.is_empty():
		state.pending = SpellResolver.reaction_pending(target_id, attacker_id, source_pending,
			{"attack": outcome, "weapon": weapon.duplicate(true), "target_id": target_id}, halving)
		events.append(SpellResolver.reaction_offer_event(state.pending))
		return events
	events.append_array(finish_attack(state, attacker_id, target_id, weapon, outcome, rng))
	return events

static func defenses_for(target: Dictionary) -> DamageRules.Defenses:
	var defenses: DamageRules.Defenses = DamageRules.Defenses.new()
	defenses.resistances.assign(target.get("resistances", []))
	defenses.vulnerabilities.assign(target.get("vulnerabilities", []))
	defenses.immunities.assign(target.get("immunities", []))
	var granted: Array = ClassKits.resistances(target)
	granted.append_array(DivineSpellEffects.resistances(target))
	for damage_type: Variant in granted:
		if not StringName(String(damage_type)) in defenses.resistances:
			defenses.resistances.append(StringName(String(damage_type)))
	return defenses

static func finish_attack(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		outcome: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target: Dictionary = state.actors[target_id]
	events.append({"type": "roll", "kind": "attack", "actor_id": attacker_id, "target_id": target_id,
		"roll": outcome["roll"], "armor_class": outcome["armor_class"],
		"hit": outcome["hit"], "critical": outcome["critical"], "cover": outcome["cover"],
		"spell_id": weapon.get("spell_id", "")})
	if not bool(outcome["hit"]):
		events.append_array(_graze(state, attacker_id, target_id, weapon, rng))
		events.append_array(ClassKits.after_attack(state, attacker_id, target_id, weapon, false, rng))
		return events
	var defenses: DamageRules.Defenses = defenses_for(target)
	# The target's accepted reaction halves this attack's damage (Rogue Uncanny Dodge).
	var halved_by: String = String(outcome.get("halved_by", ""))
	var damage_modifiers: Array[RuleModifier] = weapon_modifiers(weapon, "damage")
	damage_modifiers.append_array(ClassKits.damage_bonus(state, attacker_id, target_id, weapon))
	damage_modifiers.append_array(DivineSpellEffects.damage_modifiers(state.actors.get(attacker_id, {}), weapon))
	var damage: DamageRules.Result = DamageRules.roll(String(weapon["damage_dice"]),
		StringName(weapon["damage_type"]), rng, damage_modifiers, bool(outcome["critical"]), defenses,
		damage_die_minimum(state.actors.get(attacker_id, {}), weapon))
	var amount: int = _halve(damage.total, halved_by)
	events.append({"type": "roll", "kind": "damage", "actor_id": attacker_id, "target_id": target_id,
		"roll": serialize_roll(damage.roll), "damage_type": weapon["damage_type"], "amount": amount})
	# Class reactions that lower the damage of this hit (Monk Deflect Attacks).
	var reduction: Dictionary = ClassKits.damage_reduction(state, attacker_id, target_id, weapon, amount, rng)
	events.append_array(reduction.get("events", []))
	var lost: int = ClassEffects.lose_hp(state, target_id, maxi(0, amount - int(reduction.get("amount", 0))), rng)
	events.append({"type": "damage", "actor_id": attacker_id, "target_id": target_id,
		"amount": lost, "damage_type": weapon["damage_type"], "hp": target["hp"]})
	var total_damage: int = lost
	# A separate typed damage instance: flat riders are never critical dice.
	for extra: Dictionary in weapon.get("extra_damage", []):
		var extra_result: DamageRules.Result = DamageRules.apply(int(extra["amount"]),
			StringName(extra["damage_type"]), defenses)
		var extra_lost: int = ClassEffects.lose_hp(state, target_id, _halve(extra_result.total, halved_by), rng)
		total_damage += extra_lost
		var extra_roll: DiceResult = DiceResult.new()
		extra_roll.add_modifiers([RuleModifier.new(int(extra["amount"]), StringName(extra["source"]))])
		events.append({"type": "roll", "kind": "damage", "actor_id": attacker_id, "target_id": target_id,
			"roll": serialize_roll(extra_roll), "damage_type": extra["damage_type"], "amount": extra_lost})
		events.append({"type": "damage", "actor_id": attacker_id, "target_id": target_id,
			"amount": extra_lost, "damage_type": extra["damage_type"], "hp": target["hp"]})
	# Class dice riders (Sneak Attack, Hunter's Mark, Brutal Strike ...): own rolls, doubled on a crit.
	# The weapon copy carries how the attack roll went (Sneak Attack needs Advantage / no Disadvantage).
	var rider_weapon: Dictionary = weapon.duplicate(true)
	var roll_data: Dictionary = outcome.get("roll", {})
	rider_weapon["attack_roll"] = {"advantage": String(roll_data.get("mode", "normal")) == "advantage",
		"disadvantage": not roll_data.get("disadvantage_sources", []).is_empty()}
	for extra: Dictionary in ClassKits.extra_damage_dice(state, attacker_id, target_id, rider_weapon, bool(outcome["critical"])):
		var extra_type: StringName = StringName(String(extra.get("damage_type", weapon["damage_type"])))
		var rider: DamageRules.Result = DamageRules.roll(String(extra["dice"]), extra_type, rng, [],
			bool(outcome["critical"]), defenses)
		var rider_lost: int = ClassEffects.lose_hp(state, target_id, _halve(rider.total, halved_by), rng)
		total_damage += rider_lost
		var rider_roll: Dictionary = serialize_roll(rider.roll)
		for group: Dictionary in rider_roll["groups"]:
			group["source"] = String(extra.get("source", group["source"]))
		events.append({"type": "roll", "kind": "damage", "actor_id": attacker_id, "target_id": target_id,
			"roll": rider_roll, "damage_type": String(extra_type), "amount": rider_lost,
			"feature_id": String(extra.get("source", ""))})
		events.append({"type": "damage", "actor_id": attacker_id, "target_id": target_id,
			"amount": rider_lost, "damage_type": String(extra_type), "hp": target["hp"]})
	# Spell riders on a weapon hit (Divine Favor) and the Wolf form's Prone bite.
	var riders: Dictionary = ClassEffects.hit_riders(state, attacker_id, target_id, weapon, bool(outcome["critical"]), rng)
	events.append_array(riders["events"])
	total_damage += int(riders["damage"])
	events.append_array(ActiveEffects.after_damage(state, target_id, total_damage, rng))
	if int(target["hp"]) <= 0:
		events.append(NonlethalFights.fall_event(state, target_id, attacker_id))
		events.append_array(check_combat_end(state))
	else:
		events.append_array(ActiveEffects.on_hit(state, attacker_id, target_id, weapon))
	events.append_array(ClassKits.after_attack(state, attacker_id, target_id, weapon, true, rng))
	return events

static func _halve(amount: int, halved_by: String) -> int:
	return floori(amount / 2.0) if not halved_by.is_empty() else amount

## The run ends when the hero dies (permadeath). A fallen companion stays dead but the fight
## goes on (package K4). Records without a "hero" actor keep the old rule: any fallen ally.
static func check_combat_end(state: GameState) -> Array[Dictionary]:
	if NonlethalFights.active(state):
		return NonlethalFights.check_end(state)
	var enemy_alive: bool = false
	var has_hero: bool = state.actors.has("hero")
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		if actor.get("team") == "hero" and not alive(actor) and (id == "hero" or not has_hero):
			state.mode = &"defeat"
		elif actor.get("team") == "enemy" and alive(actor):
			enemy_alive = true
	if state.mode != &"defeat" and not enemy_alive:
		state.mode = &"exploration"
	var events: Array[Dictionary] = []
	if state.mode != &"combat":
		state.pending = {}
		ClassKits.on_combat_end(state)
		_drop_first_strikes(state)
		events.append({"type": "combat_end", "mode": String(state.mode)})
	return events

## An unused first strike (ActiveEffects.FIRST_STRIKE) does not carry into the next fight.
static func _drop_first_strikes(state: GameState) -> void:
	for id: String in state.actors:
		ActiveEffects.remove_where(state.actors[id], func(effect: Dictionary) -> bool:
			return String(effect.get("kind", "")) == ActiveEffects.FIRST_STRIKE)
