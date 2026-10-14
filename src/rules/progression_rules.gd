class_name ProgressionRules
extends RefCounted
## Level-up on plain hero records (SRD 5.2 level advancement; spell numbers per class
## come from ClassSpellcasting).
## Pure: no Nodes or singletons; randomness only through the supplied generator.
## One apply() is one level. Every choice is recorded in "level_choices" so a saved
## hero keeps them; "hp_gains" keeps the hit die result of every level after the first.

const MAX_LEVEL: int = 10
const ABILITY_CAP: int = 20
const HP_MODES: Array[String] = ["roll", "average"]
const FEATS: Array[String] = ["ability_score_improvement", "skilled", "great_weapon_fighting"]
const SKILLED_COUNT: int = 3
const NEW_SPELLS_PER_LEVEL: int = 2
const CHOICE_KEYS: Array[String] = ["hp", "feat", "ability_increases", "skills", "fighting_style",
	"expertise", "spellbook", "cantrips", "prepared"]

static func xp_level(actor: Dictionary) -> int:
	return Progression.level_for_xp(maxi(0, int(actor.get("xp", 0))))

## True when the hero has enough XP for its next level. Never forced: the player
## opens the level-up screen outside combat.
static func can_level_up(actor: Dictionary) -> bool:
	var level: int = int(actor.get("level", 1))
	return ClassFeatures.is_active_class(actor) and actor.get("team") == "hero" and \
		CombatRules.alive(actor) and level < MAX_LEVEL and xp_level(actor) > level

static func score(actor: Dictionary, ability: String) -> int:
	var scores: Dictionary = actor.get("ability_scores", {})
	return int(scores.get(StringName(ability), scores.get(ability, 10)))

static func _set_score(actor: Dictionary, ability: String, value: int) -> void:
	var scores: Dictionary = actor.get("ability_scores", {})
	scores.erase(ability)
	scores[StringName(ability)] = value
	actor["ability_scores"] = scores

static func _strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	if values is Array:
		for value: Variant in values:
			result.append(String(value))
	return result

static func hit_die(actor: Dictionary) -> int:
	var source: ClassDefinition = ClassFeatures.definition(String(actor.get("class_id", "")))
	return source.hit_die if source != null else 0

## SRD 5.2 fixed value per level: half the die plus one.
static func average_gain(die: int) -> int:
	return floori(die / 2.0) + 1

## Level 1: full die + Con. Every later level: its die result + Con, at least 1.
## A higher Constitution raises every level at once, as in the SRD.
static func maximum_hp(actor: Dictionary) -> int:
	var die: int = hit_die(actor)
	var constitution: int = Abilities.modifier(score(actor, "con"))
	var level: int = int(actor.get("level", 1))
	var gains: Array = actor.get("hp_gains", [])
	var total: int = die + constitution
	for index: int in range(level - 1):
		var gain: int = int(gains[index]) if index < gains.size() else average_gain(die)
		total += maxi(1, gain + constitution)
	return total

## Everything the next level gives and asks for. The level-up screen draws this;
## validate() checks choices against the same plan.
static func plan(actor: Dictionary) -> Dictionary:
	var level: int = int(actor.get("level", 1)) + 1
	var class_id: String = String(actor.get("class_id", ""))
	var die: int = hit_die(actor)
	var result: Dictionary = {"level": level, "class_id": class_id, "hit_die": die,
		"average": average_gain(die), "con_modifier": Abilities.modifier(score(actor, "con")),
		"proficiency_before": Abilities.proficiency_bonus(level - 1),
		"proficiency_after": Abilities.proficiency_bonus(mini(level, MAX_LEVEL)),
		"features": [], "asi": false, "feat_options": [], "skill_options": [],
		"skilled_count": 0, "fighting_style": false, "fighting_style_options": [],
		"expertise": false, "expertise_options": [], "spellbook_count": 0, "spellbook_options": [],
		"cantrip_count": 0, "cantrip_options": [], "prepared_limit": 0,
		"slots_before": [], "slots_after": []}
	var source: ClassDefinition = ClassFeatures.definition(class_id)
	if source == null or level > MAX_LEVEL:
		return result
	for feature: Dictionary in source.features_at_level(level):
		var id: String = String(feature["id"])
		result["features"].append({"id": id, "name_key": String(feature["name_key"]),
			"active": ClassFeatures.implemented(id, level)})
		if id == "ability_score_improvement":
			result["asi"] = true
		elif id == "scholar":
			result["expertise"] = true
	var features: Dictionary = actor.get("features", {})
	var skills: Array[String] = _strings(actor.get("skill_proficiencies", []))
	if bool(result["asi"]):
		result["feat_options"] = ["ability_score_improvement", "skilled"]
		if class_id == "fighter" and String(features.get("fighting_style", "")).is_empty():
			result["feat_options"].append("great_weapon_fighting")
		for skill: StringName in Abilities.SKILLS:
			if not String(skill) in skills:
				result["skill_options"].append(String(skill))
		result["skilled_count"] = mini(SKILLED_COUNT, result["skill_options"].size())
	# Hook for heroes that still lack their level-1 Fighting Style (older records).
	if class_id == "fighter" and String(features.get("fighting_style", "")).is_empty():
		result["fighting_style"] = true
		result["fighting_style_options"] = ClassFeatures.FIGHTING_STYLES.duplicate()
	if bool(result["expertise"]):
		var expertise: Array[String] = _strings(actor.get("skill_expertise", []))
		for skill: String in ClassFeatures.SCHOLAR_SKILLS:
			if skill in skills and not skill in expertise:
				result["expertise_options"].append(skill)
		result["expertise"] = not result["expertise_options"].is_empty()
	if ClassSpellcasting.is_caster(class_id):
		var cantrips: Array[String] = ClassFeatures.known_cantrips(actor)
		if ClassSpellcasting.uses_spellbook(class_id):
			var book: Array[String] = ClassFeatures.spellbook(actor)
			result["spellbook_options"] = ClassSpellcasting.spell_options(class_id, level, book)
			result["spellbook_count"] = mini(ClassSpellcasting.new_spells_per_level(class_id), result["spellbook_options"].size())
		result["cantrip_options"] = ClassSpellcasting.cantrip_options(class_id, cantrips)
		var new_cantrips: int = ClassSpellcasting.cantrips_for(actor, level) - ClassSpellcasting.cantrips_for(actor, level - 1)
		result["cantrip_count"] = clampi(new_cantrips, 0, result["cantrip_options"].size())
		result["prepared_limit"] = ClassSpellcasting.prepared_limit(class_id, level)
		result["slots_before"] = ClassSpellcasting.slots(class_id, level - 1)
		result["slots_after"] = ClassSpellcasting.slots(class_id, level)
	return result

## What the next level may prepare from: the spellbook plus this level-up's new
## spellbook spells (Wizard), or the class list up to the new highest slot.
static func preparable_after(actor: Dictionary, new_spells: Array) -> Array[String]:
	var class_id: String = String(actor.get("class_id", ""))
	var level: int = int(actor.get("level", 1)) + 1
	var result: Array[String] = ClassSpellcasting.preparable(actor, level)
	for value: Variant in new_spells:
		if not String(value) in result:
			result.append(String(value))
	if not ClassSpellcasting.uses_spellbook(class_id):
		result = ClassSpellcasting.spell_options(class_id, level, [])
	return result

## The prepared list a level-up keeps when the player does not choose one: the old
## list plus the new spellbook spells, up to the new limit.
## Classes without a spellbook fill free places from their class list, in list order.
static func default_prepared(actor: Dictionary, new_spells: Array) -> Array[String]:
	var class_id: String = String(actor.get("class_id", ""))
	var level: int = int(actor.get("level", 1)) + 1
	var limit: int = ClassSpellcasting.prepared_limit(class_id, level)
	var result: Array[String] = ClassFeatures.prepared_spells(actor)
	var candidates: Array = new_spells.duplicate()
	if not ClassSpellcasting.uses_spellbook(class_id):
		candidates.append_array(ClassSpellcasting.spell_options(class_id, level, []))
	for value: Variant in candidates:
		if result.size() < limit and not String(value) in result:
			result.append(String(value))
	return result

## "" when the choices are complete and legal, else a LEVELUP_REASON_* key.
static func validate(actor: Dictionary, choices: Dictionary) -> String:
	if not can_level_up(actor):
		return "LEVELUP_REASON_NOT_READY"
	for key: Variant in choices:
		if not key is String or not String(key) in CHOICE_KEYS:
			return "LEVELUP_REASON_INVALID"
	if not String(choices.get("hp", "")) in HP_MODES:
		return "LEVELUP_REASON_HP"
	var next: Dictionary = plan(actor)
	var feat: String = String(choices.get("feat", ""))
	if bool(next["asi"]):
		if not feat in next["feat_options"]:
			return "LEVELUP_REASON_FEAT"
		if feat != "ability_score_improvement" and choices.has("ability_increases"):
			return "LEVELUP_REASON_INVALID"
		if feat != "skilled" and choices.has("skills"):
			return "LEVELUP_REASON_INVALID"
		if feat == "ability_score_improvement":
			var reason: String = _validate_increases(actor, choices.get("ability_increases"))
			if not reason.is_empty():
				return reason
		elif feat == "skilled" and not _picks_valid(choices.get("skills"), next["skill_options"], int(next["skilled_count"])):
			return "LEVELUP_REASON_SKILLS"
		elif feat == "great_weapon_fighting" and choices.has("fighting_style"):
			return "LEVELUP_REASON_INVALID"
	elif choices.has("feat") or choices.has("ability_increases") or choices.has("skills"):
		return "LEVELUP_REASON_INVALID"
	var style_from_feat: bool = feat == "great_weapon_fighting"
	if bool(next["fighting_style"]) and not style_from_feat:
		if not String(choices.get("fighting_style", "")) in next["fighting_style_options"]:
			return "LEVELUP_REASON_STYLE"
	elif choices.has("fighting_style"):
		return "LEVELUP_REASON_INVALID"
	if bool(next["expertise"]):
		if not String(choices.get("expertise", "")) in next["expertise_options"]:
			return "LEVELUP_REASON_EXPERTISE"
	elif choices.has("expertise"):
		return "LEVELUP_REASON_INVALID"
	if not _picks_valid(choices.get("spellbook", []), next["spellbook_options"], int(next["spellbook_count"])):
		return "LEVELUP_REASON_SPELLBOOK"
	if not _picks_valid(choices.get("cantrips", []), next["cantrip_options"], int(next["cantrip_count"])):
		return "LEVELUP_REASON_CANTRIPS"
	if choices.has("prepared"):
		if not ClassSpellcasting.is_caster(String(actor.get("class_id", ""))):
			return "LEVELUP_REASON_INVALID"
		var book: Array[String] = preparable_after(actor, choices.get("spellbook", []))
		var prepared: Variant = choices["prepared"]
		if not prepared is Array or prepared.size() > int(next["prepared_limit"]) or \
				not _picks_valid(prepared, book, prepared.size()):
			return "LEVELUP_REASON_PREPARED"
	return ""

static func _picks_valid(picks: Variant, options: Array, count: int) -> bool:
	if not picks is Array or picks.size() != count:
		return false
	var seen: Array[String] = []
	for value: Variant in picks:
		if not (value is String or value is StringName) or not String(value) in options or String(value) in seen:
			return false
		seen.append(String(value))
	return true

## Ability Score Improvement: +2 to one score or +1 to two, none above 20.
static func _validate_increases(actor: Dictionary, increases: Variant) -> String:
	if not increases is Dictionary or increases.is_empty() or increases.size() > 2:
		return "LEVELUP_REASON_ASI"
	var total: int = 0
	for ability: Variant in increases:
		var amount: Variant = increases[ability]
		if not (ability is String or ability is StringName) or not StringName(ability) in Abilities.IDS:
			return "LEVELUP_REASON_ASI"
		if not amount is int or int(amount) < 1 or int(amount) > 2:
			return "LEVELUP_REASON_ASI"
		if score(actor, String(ability)) + int(amount) > ABILITY_CAP:
			return "LEVELUP_REASON_ASI_CAP"
		total += int(amount)
	return "" if total == 2 else "LEVELUP_REASON_ASI"

## Applies one level. Call only after validate() returned "". Returns events: a
## "roll" for a rolled hit die (shown in the dice popup) and one "level_up".
static func apply(actor: Dictionary, actor_id: String, choices: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var next: Dictionary = plan(actor)
	var level: int = int(next["level"])
	var old_maximum: int = int(actor.get("max_hp", maximum_hp(actor)))
	var gain: int = int(next["average"])
	if String(choices["hp"]) == "roll":
		var constitution: int = int(next["con_modifier"])
		var modifiers: Array[RuleModifier] = []
		if constitution != 0:
			modifiers.append(RuleModifier.new(constitution, &"con"))
		var roll: DiceResult = Dice.roll("1d%d" % int(next["hit_die"]), rng, modifiers)
		gain = roll.groups[0].values[0]
		events.append({"type": "roll", "kind": "hit_points", "actor_id": actor_id, "target_id": actor_id,
			"roll": CombatRules.serialize_roll(roll), "amount": maxi(1, roll.total)})
	var gains: Array = actor.get("hp_gains", []).duplicate()
	while gains.size() < level - 2:
		gains.append(int(next["average"]))
	gains.append(gain)
	actor["hp_gains"] = gains
	var feats: Array = actor.get("feats", []).duplicate()
	match String(choices.get("feat", "")):
		"ability_score_improvement":
			var increases: Dictionary = choices["ability_increases"]
			for ability: Variant in increases:
				_set_score(actor, String(ability), score(actor, String(ability)) + int(increases[ability]))
			feats.append("ability_score_improvement")
		"skilled":
			var skills: Array = actor.get("skill_proficiencies", []).duplicate()
			for skill: Variant in choices["skills"]:
				skills.append(StringName(String(skill)))
			actor["skill_proficiencies"] = skills
			feats.append("skilled")
		"great_weapon_fighting":
			actor["features"]["fighting_style"] = "great_weapon_fighting"
			feats.append("great_weapon_fighting")
	actor["feats"] = feats
	if choices.has("fighting_style"):
		actor["features"]["fighting_style"] = String(choices["fighting_style"])
	if not String(actor["features"].get("fighting_style", "")).is_empty():
		actor["pending_character_choices"] = actor.get("pending_character_choices", []).filter(
			func(choice: Variant) -> bool: return String(choice) != "fighting_style")
	if choices.has("expertise"):
		var expertise: Array = actor.get("skill_expertise", []).duplicate()
		expertise.append(String(choices["expertise"]))
		actor["skill_expertise"] = expertise
	if ClassSpellcasting.is_caster(String(actor.get("class_id", ""))):
		var new_spells: Array[String] = _strings(choices.get("spellbook", []))
		var prepared: Array[String] = _strings(choices["prepared"]) if choices.has("prepared") \
			else default_prepared(actor, new_spells)
		if ClassSpellcasting.uses_spellbook(String(actor.get("class_id", ""))):
			var book: Array[String] = ClassFeatures.spellbook(actor)
			book.append_array(new_spells)
			actor["spellbook"] = book
		var castable: Array = ClassFeatures.known_cantrips(actor)
		castable.append_array(_strings(choices.get("cantrips", [])))
		castable.append_array(prepared)
		actor["spells"] = castable
	actor["level"] = level
	ClassFeatures.advance(actor, level)
	refresh_derived(actor)
	var new_maximum: int = maximum_hp(actor)
	actor["max_hp"] = new_maximum
	actor["hp"] = clampi(int(actor.get("hp", 0)) + new_maximum - old_maximum, 1, new_maximum)
	var history: Array = actor.get("level_choices", []).duplicate(true)
	history.append({"level": level, "choices": choices.duplicate(true), "hp_gain": gain})
	actor["level_choices"] = history
	events.append({"type": "level_up", "actor_id": actor_id, "level": level,
		"max_hp": new_maximum, "hp_gained": new_maximum - old_maximum,
		"proficiency_bonus": int(actor["proficiency_bonus"])})
	return events

## Recalculates every value that depends on level or ability scores.
static func refresh_derived(actor: Dictionary) -> void:
	var level: int = int(actor.get("level", 1))
	var proficiency: int = Abilities.proficiency_bonus(level)
	actor["proficiency_bonus"] = proficiency
	actor["dex"] = score(actor, "dex")
	var skills: Array[String] = _strings(actor.get("skill_proficiencies", []))
	var expertise: Array[String] = _strings(actor.get("skill_expertise", []))
	actor["passive_perception"] = 10 + Abilities.modifier(score(actor, "wis")) + \
		(proficiency if "perception" in skills else 0) + (proficiency if "perception" in expertise else 0)
	RestRules.ensure_hit_dice(actor)
	var dice: Dictionary = actor["hit_dice"]
	dice["left"] = clampi(int(dice["left"]) + level - int(dice["max"]), 0, level)
	dice["max"] = level
	var source: ClassDefinition = ClassFeatures.definition(String(actor.get("class_id", "")))
	if EquipmentRules.has_inventory(actor) and source != null:
		var training: EquipmentRules.Training = EquipmentRules.Training.from_class(source)
		EquipmentRules.refresh_weapon(actor, training)
		EquipmentRules.refresh_armor(actor, training)
	else:
		for weapon: Variant in [actor.get("weapon", {})] + actor.get("attacks", []):
			_refresh_weapon_modifiers(actor, weapon as Dictionary, proficiency)
	ClassSpellcasting.refresh(actor)

## Heroes without an inventory keep their weapon record; only its numbers move.
static func _refresh_weapon_modifiers(actor: Dictionary, weapon: Dictionary, proficiency: int) -> void:
	if weapon.is_empty():
		return
	for kind: String in ["attack", "damage"]:
		var total: int = 0
		for modifier: Dictionary in weapon.get(kind + "_modifiers", []):
			var source: String = String(modifier.get("source", ""))
			if source == "proficiency":
				modifier["amount"] = proficiency
			elif StringName(source) in Abilities.IDS:
				modifier["amount"] = Abilities.modifier(score(actor, source))
			total += int(modifier["amount"])
		if weapon.has(kind + "_modifiers"):
			weapon[kind + "_bonus"] = total
