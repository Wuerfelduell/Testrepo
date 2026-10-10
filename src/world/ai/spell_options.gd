class_name SpellOptions
extends RefCounted
## Spell candidates for the utility AI. Read-only and RNG-free like UtilityAI:
## every option is validated as a normal CastSpellCommand before it can act.
## Slots are a resource, so levelled spells must beat cantrips by a margin, and
## area spells are scored against every ally they would catch.

const SLOT_COST: float = 7.0
const ALLY_HIT_PENALTY: float = 60.0
const SLEEP_VALUE: float = 9.0

static func is_caster(actor: Dictionary) -> bool:
	return not actor.get("spells", []).is_empty()

static func consider(state: GameState, actor_id: String, targets: Array[String],
		personality: AIPersonality) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var actor: Dictionary = state.actors[actor_id]
	if not is_caster(actor) or not CombatRules.can_use_action(actor):
		return options
	for spell_id: String in actor.get("spells", []):
		var spell: SpellDefinition = SpellBook.get_spell(spell_id)
		if spell == null or spell.casting_time == "reaction" or \
				not SpellResolver.availability_reason(state, actor_id, spell).is_empty():
			continue
		var cost: float = 0.0 if spell.is_cantrip() else SLOT_COST * spell.level
		match spell.targeting:
			"creature":
				for target_id: String in targets:
					var preview: Dictionary = SpellResolver.preview(state, actor_id, spell_id, 0, [target_id])
					if not bool(preview["legal"]):
						continue
					var entry: Dictionary = preview["targets"][0]
					var expression: String = SpellRules.damage_expression(spell, int(actor.get("level", 1)), 0)
					var kill: float = float(entry["chance"]) * _at_least(expression, 0, int(state.actors[target_id]["hp"]))
					var score: float = float(entry["chance"]) * personality.hit_weight \
						+ float(entry["expected_damage"]) * personality.damage_weight + kill * personality.kill_weight - cost
					if spell.effect == &"speed_penalty":
						score += float(entry["chance"]) * 0.5
					options.append(_option(spell_id, [target_id], Vector3.INF, score,
						&"AI_FINISH_TARGET" if kill >= 0.25 else &"AI_CAST_SPELL",
						{"hit_chance": entry["chance"], "expected_damage": entry["expected_damage"], "kill_chance": kill, "slot_cost": cost}))
			"darts":
				for plan: Array in _dart_plans(state, actor_id, spell, targets):
					var preview: Dictionary = SpellResolver.preview(state, actor_id, spell_id, 0, plan)
					if not bool(preview["legal"]):
						continue
					var damage: float = 0.0
					var kills: float = 0.0
					for entry: Dictionary in preview["targets"]:
						damage += float(entry["expected_damage"])
						var darts: int = int(entry["darts"])
						var parsed: Dictionary = Dice.parse(spell.damage_dice)
						kills += _at_least("%dd%d" % [int(parsed["count"]) * darts, int(parsed["sides"])],
							spell.dart_bonus * darts, int(state.actors[String(entry["id"])]["hp"]))
					var score: float = personality.hit_weight + damage * personality.damage_weight + kills * personality.kill_weight - cost
					options.append(_option(spell_id, plan, Vector3.INF, score,
						&"AI_FINISH_TARGET" if kills >= 0.25 else &"AI_CAST_SPELL",
						{"hit_chance": 1.0, "expected_damage": damage, "kill_chance": kills, "slot_cost": cost}))
			"self", "point":
				if spell.area == "none":
					continue
				for target_id: String in targets:
					var aim: Vector3 = state.actors[target_id]["position"]
					var preview: Dictionary = SpellResolver.preview(state, actor_id, spell_id, 0, [], aim)
					if not bool(preview["legal"]) or preview["targets"].is_empty():
						continue
					var value: float = 0.0
					var allies_hit: int = 0
					var damage: float = 0.0
					for entry: Dictionary in preview["targets"]:
						var other: Dictionary = state.actors[String(entry["id"])]
						var fail: float = 1.0 - float(entry["save_chance"])
						var worth: float = float(entry["expected_damage"]) * personality.damage_weight
						if not spell.damage_dice.is_empty():
							worth += fail * _at_least(SpellRules.damage_expression(spell, int(actor.get("level", 1)), 0), 0, int(other["hp"])) * personality.kill_weight
						elif spell.effect == &"sleep" and not CombatRules.conditions_for(other).has(&"incapacitated"):
							worth += fail * SLEEP_VALUE
						if bool(entry["ally"]):
							allies_hit += 1
							value -= worth * 2.0
						else:
							value += worth
							damage += float(entry["expected_damage"])
					# Hitting an ally with an area is never worth it for a sane caster.
					value -= ALLY_HIT_PENALTY * allies_hit
					if spell.concentration and not actor.get("concentration", {}).is_empty():
						value -= SLEEP_VALUE
					options.append(_option(spell_id, [], aim, value - cost,
						&"AI_AREA_ALLIES" if allies_hit > 0 else &"AI_CAST_AREA",
						{"expected_damage": damage, "allies_hit": float(allies_hit), "slot_cost": cost}))
	return options

## Best cantrip value from a hypothetical position, so movement scoring keeps
## casters in spell range instead of walking them into melee.
static func best_offense(state: GameState, actor_id: String, position: Vector3,
		targets: Array[String], personality: AIPersonality) -> float:
	var actor: Dictionary = state.actors[actor_id]
	var best: float = 0.0
	for spell_id: String in actor.get("spells", []):
		var spell: SpellDefinition = SpellBook.get_spell(spell_id)
		if spell == null or not spell.is_cantrip() or spell.resolution != "attack":
			continue
		var weapon: Dictionary = SpellResolver.attack_weapon(actor, spell)
		for target_id: String in targets:
			var preview: Dictionary = CombatRules.attack_preview(state, actor_id, target_id, position, weapon)
			if bool(preview.get("legal", false)):
				best = maxf(best, float(preview["chance"]) * personality.hit_weight \
					+ float(preview["expected_damage"]) * personality.damage_weight)
	return best

static func command_for(option: Dictionary, actor_id: String) -> Command:
	return CastSpellCommand.new(actor_id, String(option["spell_id"]), option.get("target_ids", []),
		option.get("point", Vector3.INF))

static func _option(spell_id: String, target_ids: Array, point: Vector3, score: float,
		reason: StringName, breakdown: Dictionary) -> Dictionary:
	return {"kind": &"cast_spell", "spell_id": spell_id, "target_ids": target_ids.duplicate(),
		"point": point, "score": score, "reason_key": reason,
		"target_id": String(target_ids[0]) if not target_ids.is_empty() else spell_id,
		"destination": point if point.is_finite() else Vector3.ZERO, "breakdown": breakdown}

## All darts on one target, plus a greedy plan that finishes the weakest first.
static func _dart_plans(state: GameState, actor_id: String, spell: SpellDefinition,
		targets: Array[String]) -> Array[Array]:
	var plans: Array[Array] = []
	var count: int = SpellRules.dart_count(spell, SpellResolver.effective_slot(state.actors[actor_id], spell, 0))
	var by_hp: Array[String] = targets.duplicate()
	by_hp.sort_custom(func(a: String, b: String) -> bool: return int(state.actors[a]["hp"]) < int(state.actors[b]["hp"]))
	for target_id: String in targets:
		var single: Array = []
		for dart: int in count:
			single.append(target_id)
		plans.append(single)
	var spread: Array = []
	var dart_average: float = SpellRules.average_damage(spell.damage_dice, spell.dart_bonus)
	for target_id: String in by_hp:
		var needed: int = ceili(float(state.actors[target_id]["hp"]) / dart_average)
		for dart: int in mini(needed, count - spread.size()):
			spread.append(target_id)
		if spread.size() >= count:
			break
	while not spread.is_empty() and spread.size() < count:
		spread.append(spread[0])
	if spread.size() == count and not spread in plans:
		plans.append(spread)
	return plans

static func _at_least(expression: String, flat: int, required: int) -> float:
	var parsed: Dictionary = Dice.parse(expression)
	if parsed.has("error"):
		return 0.0
	return UtilityAI._dice_at_least(int(parsed["count"]), int(parsed["sides"]), required - flat)
