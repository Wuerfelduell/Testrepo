class_name ClassEffects
extends RefCounted
## Spell and class-feature effects of the Cleric, Paladin and Druid (SRD 5.2) on plain
## actor records, plus the shared hooks other systems call: hit point loss (temporary
## hit points, Resistance), attack and save bonuses (Bless, Aura of Protection), extra
## damage on weapon hits (Divine Favor), advantage against marked creatures (Faerie
## Fire, Guiding Bolt, Pack Tactics) and Wild Shape. Class riders and feature uses live
## in the class kits (src/rules/classes). Pure: no Nodes, no singletons; dice only through the supplied generator.
##
## Effects live in the actor's "effects" list (ActiveEffects) with these extra "until"
## values: "rounds" (rounds_left counts down at the start of turn_of's turn), "long_rest",
## "damage" (ends when the creature takes damage; also counts rounds when rounds_left > 0).

const AURA_OF_PROTECTION_M: float = 3.0
## SRD 5.2 Wolf (CR 1/4), the default Wild Shape form: AC 12, Speed 40 ft., STR 14,
## DEX 15, CON 12, Bite +4, 1d6+2 piercing, Prone on a hit (Medium or smaller),
## Pack Tactics.
const WILD_SHAPE_FORMS: Dictionary = {
	"wolf": {"name_key": "FORM_WOLF", "ac": 12, "speed_m": 12.0,
		"scores": {"str": 14, "dex": 15, "con": 12},
		"weapon": {"id": "wolf_bite", "name_key": "WEAPON_WOLF_BITE", "ranged": false, "reach": 1.5,
			"range": 0.0, "long_range": 0.0, "attack_bonus": 4, "damage_dice": "1d6", "damage_bonus": 2,
			"damage_type": "piercing", "attack_modifiers": [{"amount": 4, "source": "wolf"}],
			"damage_modifiers": [{"amount": 2, "source": "wolf"}], "proficient": true,
			"properties": [], "on_hit_prone": true, "pack_tactics": true, "natural": true}},
}

static func _turn_key(state: GameState) -> String:
	return "%d:%d" % [state.round_number, state.turn_index]

static func _effects_of(actor: Dictionary, kind: String) -> Array:
	return ActiveEffects.effects(actor).filter(func(effect: Dictionary) -> bool:
		return String(effect.get("kind", "")) == kind)

static func spell_modifier(actor: Dictionary) -> int:
	var ability: String = String(actor.get("spell_ability", ""))
	if ability.is_empty():
		return int(actor.get("spell_modifier", 0))
	return Abilities.modifier(ProgressionRules.score(actor, ability))

## Conditions an effect grants while it lasts.
static func granted_conditions(effect: Dictionary) -> Array[String]:
	match String(effect.get("kind", "")):
		"hold": return ["paralyzed"]
		"entangle": return ["restrained"]
		"hideous_laughter": return ["prone", "incapacitated"]
		"hypnotic_pattern": return ["incapacitated"]
		"turned": return ["frightened", "incapacitated"]
		"frightened": return ["frightened"]
	return DivineSpellEffects.granted_conditions(effect)

# ---------------------------------------------------------------- damage and defence

## Hit point loss after resistances: Resistance (1d4 once per turn) and temporary hit
## points absorb first. Returns the hit points actually lost.
static func lose_hp(state: GameState, target_id: String, amount: int, rng: RandomNumberGenerator) -> int:
	var target: Dictionary = state.actors.get(target_id, {})
	if target.is_empty() or amount <= 0:
		return 0
	var left: int = amount
	for effect: Dictionary in _effects_of(target, "resistance"):
		if String(effect.get("used_turn", "")) != _turn_key(state):
			effect["used_turn"] = _turn_key(state)
			left = maxi(0, left - Dice.roll("1d4", rng).total)
			break
	var temporary: int = int(target.get("temp_hp", 0))
	if temporary > 0:
		var absorbed: int = mini(temporary, left)
		target["temp_hp"] = temporary - absorbed
		left -= absorbed
	target["hp"] = maxi(0, int(target["hp"]) - left)
	if int(target["hp"]) <= 0:
		DivineSpellEffects.death_ward(target)
	if left > 0:
		ActiveEffects.remove_where(target, func(effect: Dictionary) -> bool:
			return String(effect.get("until", "")) == "damage")
	return left

## Armour Class with Shield of Faith (+2) and Barkskin (at least 17).
static func armor_class(target: Dictionary) -> int:
	var value: int = int(target.get("ac", 10)) + ActiveEffects.ac_bonus(target)
	for effect: Dictionary in ActiveEffects.effects(target):
		match String(effect.get("kind", "")):
			"ac_bonus":
				value += int(effect.get("amount", 0))
			"barkskin":
				value = maxi(value, 17)
			"haste":
				value += 2
			"slow":
				value -= 2
			"mage_armor":
				# 13 + Dexterity modifier while the creature wears no armour.
				if String(target.get("armor", "none")) in ["", "none"]:
					value = maxi(value, 13 + Abilities.modifier(int(target.get("dex", 10))))
	return value

## Advantage sources for an attack against target_id: Faerie Fire, Guiding Bolt, Pack Tactics.
static func attack_advantages(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> Array[StringName]:
	var result: Array[StringName] = []
	var target: Dictionary = state.actors[target_id]
	if not _effects_of(target, "faerie_fire").is_empty():
		result.append(&"faerie_fire")
	if not _effects_of(target, "guiding_bolt").is_empty():
		result.append(&"guiding_bolt")
	result.append_array(DivineSpellEffects.attack_advantages(target))
	if bool(weapon.get("pack_tactics", false)):
		var attacker: Dictionary = state.actors[attacker_id]
		for id: String in state.actors:
			var ally: Dictionary = state.actors[id]
			if id != attacker_id and ally.get("team") == attacker.get("team") and CombatRules.alive(ally) and \
					CombatRules.conditions_for(ally).can_act() and ally.get("position") is Vector3 and \
					(ally["position"] as Vector3).distance_to(target["position"]) <= 1.5 + CombatRules.EPSILON:
				result.append(&"pack_tactics")
				break
	return result

## Guiding Bolt grants advantage to the next attack only.
static func consume_on_attacked(target: Dictionary) -> void:
	ActiveEffects.remove_where(target, func(effect: Dictionary) -> bool:
		return String(effect.get("kind", "")) == "guiding_bolt")

## Expected flat bonus for previews (Bless averages 2.5).
static func attack_bonus_estimate(actor: Dictionary, weapon: Dictionary = {}) -> int:
	return (2 if not _effects_of(actor, "bless").is_empty() else 0) + DivineSpellEffects.attack_bonus_estimate(actor, weapon)

## Bless: +1d4 to attack rolls, rolled now.
static func attack_modifiers(actor: Dictionary, rng: RandomNumberGenerator, weapon: Dictionary = {}) -> Array[RuleModifier]:
	var result: Array[RuleModifier] = []
	if not _effects_of(actor, "bless").is_empty():
		result.append(RuleModifier.new(Dice.roll("1d4", rng).total, &"bless"))
	result.append_array(DivineSpellEffects.attack_modifiers(actor, weapon, rng))
	return result

## Bless (+1d4) and Aura of Protection (+Charisma modifier, at least +1) on a saving throw.
static func save_modifiers(state: GameState, actor_id: String, rng: RandomNumberGenerator) -> Array[RuleModifier]:
	var result: Array[RuleModifier] = []
	var actor: Dictionary = state.actors.get(actor_id, {})
	if actor.is_empty():
		return result
	if not _effects_of(actor, "bless").is_empty():
		result.append(RuleModifier.new(Dice.roll("1d4", rng).total, &"bless"))
	var aura: int = aura_of_protection(state, actor_id)
	if aura > 0:
		result.append(RuleModifier.new(aura, &"aura_of_protection"))
	result.append_array(DivineSpellEffects.save_modifiers(actor, rng))
	return result

## The best Aura of Protection bonus reaching this creature (0 if none).
static func aura_of_protection(state: GameState, actor_id: String) -> int:
	var actor: Dictionary = state.actors.get(actor_id, {})
	if not actor.get("position") is Vector3:
		return 0
	var best: int = 0
	for id: String in state.actors:
		var paladin: Dictionary = state.actors[id]
		if not paladin.get("features", {}).has("aura_of_protection") or paladin.get("team") != actor.get("team") or \
				not CombatRules.alive(paladin) or not CombatRules.conditions_for(paladin).can_act() or \
				not paladin.get("position") is Vector3:
			continue
		if (paladin["position"] as Vector3).distance_to(actor["position"]) <= AURA_OF_PROTECTION_M + CombatRules.EPSILON:
			best = maxi(best, maxi(1, Abilities.modifier(ProgressionRules.score(paladin, "cha"))))
	return best

## Aura of Courage: immune to Frightened inside a level-10 Paladin's aura.
static func fear_immune(state: GameState, actor_id: String) -> bool:
	var actor: Dictionary = state.actors.get(actor_id, {})
	if DivineSpellEffects.fear_immune(actor):
		return true
	if not actor.get("position") is Vector3:
		return false
	for id: String in state.actors:
		var paladin: Dictionary = state.actors[id]
		if paladin.get("features", {}).has("aura_of_courage") and paladin.get("team") == actor.get("team") and \
				CombatRules.alive(paladin) and CombatRules.conditions_for(paladin).can_act() and \
				(paladin["position"] as Vector3).distance_to(actor["position"]) <= AURA_OF_PROTECTION_M + CombatRules.EPSILON:
			return true
	return false

## Potent Spellcasting (Cleric Blessed Strikes / Druid Elemental Fury option): the
## Wisdom modifier on cantrip damage.
static func cantrip_damage_bonus(caster: Dictionary, spell: SpellDefinition) -> int:
	if not spell.is_cantrip() or spell.damage_dice.is_empty():
		return 0
	var features: Dictionary = caster.get("features", {})
	if String(features.get("blessed_strikes", "")) == "potent_spellcasting" or \
			String(features.get("elemental_fury", "")) == "potent_spellcasting":
		return Abilities.modifier(ProgressionRules.score(caster, "wis"))
	return 0

# ---------------------------------------------------------------- weapon hit riders

## Extra damage after a weapon hit that did not kill yet: Divine Favor (1d4 radiant)
## and the Wolf's Prone bite. Class riders (Divine Smite, Divine Strike) live in the
## kits (extra_damage_dice). Returns {"events", "damage"}.
static func hit_riders(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		critical: bool, rng: RandomNumberGenerator) -> Dictionary:
	var events: Array[Dictionary] = []
	var damage: int = 0
	var attacker: Dictionary = state.actors.get(attacker_id, {})
	var target: Dictionary = state.actors[target_id]
	var is_weapon: bool = String(weapon.get("spell_id", "")).is_empty()
	if attacker.is_empty():
		return {"events": events, "damage": damage}
	if not is_weapon:
		events.append_array(DivineSpellEffects.spell_hit(state, attacker_id, target_id, weapon))
		return {"events": events, "damage": damage}
	events.append_array(DivineSpellEffects.retaliation(state, attacker_id, target_id, weapon, rng))
	var riders: Array[Dictionary] = []
	if not _effects_of(attacker, "divine_favor").is_empty():
		riders.append({"dice": "1d4", "type": "radiant", "source": "divine_favor"})
	riders.append_array(DivineSpellEffects.weapon_riders(state, attacker_id, target_id, weapon, rng, events))
	var defenses: DamageRules.Defenses = CombatRules.defenses_for(target)
	for rider: Dictionary in riders:
		if not CombatRules.alive(target):
			break
		var result: DamageRules.Result = DamageRules.roll(String(rider["dice"]), StringName(String(rider["type"])), rng,
			[], critical, defenses)
		var lost: int = lose_hp(state, target_id, result.total, rng)
		damage += lost
		events.append({"type": "roll", "kind": "damage", "actor_id": attacker_id, "target_id": target_id,
			"roll": CombatRules.serialize_roll(result.roll), "damage_type": rider["type"], "amount": lost,
			"feature_id": rider["source"]})
		events.append({"type": "damage", "actor_id": attacker_id, "target_id": target_id,
			"amount": lost, "damage_type": rider["type"], "hp": target["hp"], "feature_id": rider["source"]})
	if bool(weapon.get("on_hit_prone", false)) and CombatRules.alive(target) and not "prone" in target.get("conditions", []):
		if not target.has("conditions"):
			target["conditions"] = []
		target["conditions"].append("prone")
		events.append({"type": "condition", "actor_id": target_id, "condition": "prone", "source_id": attacker_id})
	return {"events": events, "damage": damage}

# ---------------------------------------------------------------- spell effects

## Applies a spell's lasting effect to one target (after a failed save for hostile
## effects). Returns the events.
static func apply_effect(state: GameState, caster_id: String, target_id: String, spell: SpellDefinition,
		slot_level: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var caster: Dictionary = state.actors[caster_id]
	var target: Dictionary = state.actors[target_id]
	var kind: String = String(spell.effect)
	if kind in ["hold", "entangle"] and DivineSpellEffects.free_moving(target):
		return events
	var effect: Dictionary = {"kind": kind, "source_id": caster_id, "spell_id": String(spell.id), "turn_of": caster_id,
		"until": "concentration" if spell.concentration else "rounds", "rounds_left": maxi(1, spell.duration_rounds),
		"save_dc": int(caster.get("spell_save_dc", 10)), "save_ability": String(spell.save_ability)}
	match kind:
		"ac_bonus":
			effect["amount"] = int(spell.effect_amount)
		"barkskin":
			effect["until"] = "long_rest"
		"aid":
			var bonus: int = 5 * (1 + maxi(0, slot_level - spell.level))
			ActiveEffects.remove_where(target, func(other: Dictionary) -> bool: return String(other.get("kind", "")) == "aid")
			_remove_aid(target)
			target["aid_bonus"] = bonus
			target["max_hp"] = int(target["max_hp"]) + bonus
			target["hp"] = int(target["hp"]) + bonus
			effect["until"] = "long_rest"
			effect["amount"] = bonus
			events.append({"type": "heal", "actor_id": target_id, "target_id": target_id, "source_id": caster_id,
				"spell_id": String(spell.id), "amount": bonus, "hp": target["hp"]})
		"bardic_inspiration":
			# Kept until the inspired creature uses it (ActiveEffects.inspire_roll).
			effect["until"] = "used"
			effect["die"] = int(caster.get("features", {}).get("bardic_inspiration", {}).get("die", 6))
		"guiding_bolt":
			# Until the end of the caster's next turn; ends at the start of it here.
			effect["until"] = "rounds"
			effect["rounds_left"] = 1
		"turned", "frightened":
			if ClassEffects.fear_immune(state, target_id):
				return events
			effect["until"] = "damage"
			effect["rounds_left"] = maxi(1, spell.duration_rounds)
		"hypnotic_pattern":
			# Ends when the creature takes damage, or with the caster's concentration.
			effect["until"] = "damage"
			effect["rounds_left"] = maxi(1, spell.duration_rounds)
		"mage_armor":
			effect["until"] = "long_rest"
		"false_life":
			# 2d4 + 4 temporary hit points (their average, 9), +5 per slot level above 1st.
			effect["until"] = "long_rest"
			target["temp_hp"] = maxi(int(target.get("temp_hp", 0)), 9 + 5 * maxi(0, slot_level - spell.level))
			events.append({"type": "temp_hp", "actor_id": target_id, "amount": int(target["temp_hp"])})
		"wild_shape":
			return wild_shape(state, caster_id, "wolf")
		_:
			DivineSpellEffects.prepare_effect(state, caster, target_id, spell, slot_level, effect)
		"revert_wild_shape":
			return revert_wild_shape(caster, caster_id)
	# Recasting refreshes instead of stacking (Bless twice is one Bless).
	ActiveEffects.remove_where(target, func(other: Dictionary) -> bool:
		return String(other.get("kind", "")) == kind and String(other.get("source_id", "")) == caster_id)
	ActiveEffects.add(target, effect)
	events.append({"type": "effect", "actor_id": target_id, "source_id": caster_id, "kind": kind, "spell_id": String(spell.id)})
	for condition: String in granted_conditions(effect):
		events.append({"type": "condition", "actor_id": target_id, "condition": condition, "source_id": caster_id})
	return events

static func _remove_aid(actor: Dictionary) -> void:
	var bonus: int = int(actor.get("aid_bonus", 0))
	if bonus <= 0:
		return
	actor["max_hp"] = maxi(1, int(actor["max_hp"]) - bonus)
	actor["hp"] = clampi(int(actor["hp"]), 0 if int(actor["hp"]) <= 0 else 1, int(actor["max_hp"]))
	actor.erase("aid_bonus")

## Start of `actor_id`'s turn: effects with a round count it started tick down.
static func on_turn_start(state: GameState, actor_id: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for id: String in state.actors:
		var actor: Dictionary = state.actors[id]
		var expired: bool = false
		for effect: Dictionary in ActiveEffects.effects(actor):
			if String(effect.get("turn_of", "")) != actor_id or not String(effect.get("until", "")) in ["rounds", "damage"]:
				continue
			effect["rounds_left"] = int(effect.get("rounds_left", 1)) - 1
			expired = expired or int(effect["rounds_left"]) <= 0
		if expired:
			ActiveEffects.remove_where(actor, func(effect: Dictionary) -> bool:
				return String(effect.get("turn_of", "")) == actor_id and \
					String(effect.get("until", "")) in ["rounds", "damage"] and int(effect.get("rounds_left", 1)) <= 0)
			events.append({"type": "effects_expired", "actor_id": id})
	events.append_array(DivineSpellEffects.on_turn_start(state, actor_id))
	return events

## End of a held or entangled creature's turn: it repeats the save (Hold Person RAW;
## Entangle's Athletics check is simplified to the same Strength save).
static func on_turn_end(state: GameState, actor_id: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var actor: Dictionary = state.actors.get(actor_id, {})
	if actor.is_empty() or not CombatRules.alive(actor):
		return events
	for effect: Dictionary in ActiveEffects.effects(actor).duplicate():
		var kind: String = String(effect.get("kind", ""))
		if not kind in ["hold", "entangle", "hideous_laughter", "slow"]:
			continue
		var ability: StringName = StringName(String(effect.get("save_ability", "wis")))
		var save: Dictionary = SpellRules.roll_save(actor, ability, int(effect.get("save_dc", 10)), rng,
			save_modifiers(state, actor_id, rng))
		events.append(ActiveEffects.save_event(String(effect.get("source_id", "")), actor_id, String(effect.get("spell_id", kind)), save))
		if bool(save["success"]):
			var source_id: String = String(effect.get("source_id", ""))
			ActiveEffects.remove_where(actor, func(other: Dictionary) -> bool:
				return String(other.get("kind", "")) == kind and String(other.get("source_id", "")) == source_id)
			for condition: String in granted_conditions(effect):
				events.append({"type": "condition_end", "actor_id": actor_id, "condition": condition})
	events.append_array(DivineSpellEffects.on_turn_end(state, actor_id, rng))
	return events

# ---------------------------------------------------------------- Wild Shape

## Druid Wild Shape (SRD 5.2): the form's AC, Speed, physical scores and attack replace
## the druid's; hit points, mental scores and proficiencies stay. Temporary hit points
## equal to the druid level. No spellcasting while shifted.
static func wild_shape(state: GameState, actor_id: String, form_id: String) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	var form: Dictionary = WILD_SHAPE_FORMS[form_id]
	if not actor.has("wild_shape"):
		var scores: Dictionary = actor.get("ability_scores", {})
		actor["wild_shape"] = {"form": form_id, "saved": {
			"ac": actor.get("ac", 10), "speed_m": actor.get("speed_m", 9.0),
			"weapon": actor.get("weapon", {}).duplicate(true), "attacks": actor.get("attacks", []).duplicate(true),
			"can_cast_spells": actor.get("can_cast_spells", true),
			"scores": {"str": ProgressionRules.score(actor, "str"), "dex": ProgressionRules.score(actor, "dex"),
				"con": ProgressionRules.score(actor, "con")}}}
		for ability: String in form["scores"]:
			scores.erase(ability)
			scores[StringName(ability)] = int(form["scores"][ability])
		actor["ability_scores"] = scores
	else:
		actor["wild_shape"]["form"] = form_id
	var weapon: Dictionary = (form["weapon"] as Dictionary).duplicate(true)
	actor["ac"] = int(form["ac"])
	actor["speed_m"] = float(form["speed_m"])
	actor["move_left"] = maxf(float(actor.get("move_left", 0.0)), 0.0) + maxf(0.0, float(form["speed_m"]) - float(actor["wild_shape"]["saved"]["speed_m"]))
	actor["weapon"] = weapon
	actor["attacks"] = [weapon.duplicate(true)]
	actor["can_cast_spells"] = false
	actor["temp_hp"] = maxi(int(actor.get("temp_hp", 0)), int(actor.get("level", 1)))
	actor["dex"] = ProgressionRules.score(actor, "dex")
	return [{"type": "wild_shape", "actor_id": actor_id, "form": form_id, "temp_hp": actor["temp_hp"]}]

static func revert_wild_shape(actor: Dictionary, actor_id: String) -> Array[Dictionary]:
	if not actor.has("wild_shape"):
		return []
	var saved: Dictionary = actor["wild_shape"]["saved"]
	var scores: Dictionary = actor.get("ability_scores", {})
	for ability: String in saved["scores"]:
		scores.erase(ability)
		scores[StringName(ability)] = int(saved["scores"][ability])
	actor["ability_scores"] = scores
	actor["ac"] = saved["ac"]
	actor["speed_m"] = saved["speed_m"]
	actor["move_left"] = minf(float(actor.get("move_left", 0.0)), float(saved["speed_m"]))
	actor["weapon"] = saved["weapon"]
	actor["attacks"] = saved["attacks"]
	actor["can_cast_spells"] = saved["can_cast_spells"]
	actor["dex"] = ProgressionRules.score(actor, "dex")
	actor["temp_hp"] = 0
	actor.erase("wild_shape")
	return [{"type": "wild_shape_end", "actor_id": actor_id}]

# ---------------------------------------------------------------- feature resources

## Can this feature spell be paid right now? (Wild Resurgence: a spell slot buys a
## Wild Shape use once per turn when none are left.)
static func resource_available(state: GameState, caster: Dictionary, spell: SpellDefinition) -> bool:
	var features: Dictionary = caster.get("features", {})
	match spell.feature_resource:
		"free":
			return spell.effect != &"revert_wild_shape" or caster.has("wild_shape")
		"concentration":
			return DivineSpellEffects.follow_up_available(caster, spell)
		"lay_on_hands":
			return int(features.get("lay_on_hands", {}).get("uses", 0)) > 0
		"wild_shape":
			if int(features.get("wild_shape", {}).get("uses", 0)) > 0:
				return true
			return features.has("wild_resurgence") and \
				String(features["wild_resurgence"].get("turn", "")) != _turn_key(state) and \
				SpellRules.lowest_slot(caster.get("spell_slots", []), 1) > 0
	return int(features.get(spell.feature_resource, {}).get("uses", 0)) > 0

static func spend_resource(state: GameState, caster: Dictionary, spell: SpellDefinition) -> void:
	var features: Dictionary = caster.get("features", {})
	match spell.feature_resource:
		"free", "lay_on_hands", "concentration":
			return
		"wild_shape":
			var shape: Dictionary = features.get("wild_shape", {})
			if int(shape.get("uses", 0)) > 0:
				shape["uses"] = int(shape["uses"]) - 1
				return
			# Wild Resurgence: the lowest slot becomes the use that is spent at once.
			SpellRules.spend_slot(caster["spell_slots"], SpellRules.lowest_slot(caster["spell_slots"], 1))
			features["wild_resurgence"]["turn"] = _turn_key(state)
			return
	var feature: Dictionary = features.get(spell.feature_resource, {})
	feature["uses"] = maxi(0, int(feature.get("uses", 0)) - 1)

## Lay on Hands: as many hit points as the target is missing, from the pool.
static func lay_on_hands(state: GameState, caster_id: String, target_id: String) -> Array[Dictionary]:
	var caster: Dictionary = state.actors[caster_id]
	var target: Dictionary = state.actors[target_id]
	var pool: Dictionary = caster["features"]["lay_on_hands"]
	var amount: int = mini(int(pool.get("uses", 0)), int(target["max_hp"]) - int(target["hp"]))
	pool["uses"] = int(pool["uses"]) - amount
	target["hp"] = int(target["hp"]) + amount
	return [{"type": "heal", "actor_id": target_id, "target_id": target_id, "source_id": caster_id,
		"feature_id": "lay_on_hands", "amount": amount, "hp": target["hp"]}]

## Long Rest: Wild Shape ends, temporary hit points and long-rest effects (Barkskin,
## Aid) end. Feature uses recharge through ClassKits.recharge.
static func long_rest(actor: Dictionary) -> void:
	revert_wild_shape(actor, String(actor.get("id", "")))
	actor["temp_hp"] = 0
	ActiveEffects.remove_where(actor, func(effect: Dictionary) -> bool:
		return String(effect.get("until", "")) == "long_rest")
	_remove_aid(actor)
