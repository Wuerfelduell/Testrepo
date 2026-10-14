extends RefCounted
## Ranger, SRD 5.2 p. 57-59, levels 1-10 without subclass (ClassKits interface, see
## README.md). Spellcasting comes from ClassSpellcasting ("ranger", half caster, Wisdom).
## Here: Favored Enemy (free Hunter's Mark casts and its damage), Weapon Mastery, Deft
## Explorer, Fighting Style (Archery or Defense), Extra Attack, Roving, Expertise.

const PRIORITY: Array[StringName] = [&"dex", &"wis", &"con", &"str", &"int", &"cha"]
const SKILLS: Dictionary = {"class": [&"perception", &"stealth", &"survival"], "human": &"athletics"}
## SRD 5.2 Ranger table, index 0 = level 1.
const FAVORED_ENEMY: Array[int] = [2, 2, 2, 2, 3, 3, 3, 3, 4, 4]
const START_MASTERY: Array[String] = ["longbow", "scimitar"]
## Fighting Styles with rules behind them; Two-Weapon Fighting waits for off-hand attacks,
## Druidic Warrior for Druid cantrips.
const FIGHTING_STYLES: Array[String] = ["archery", "defense"]
const ROVING_M: float = 3.0
const HUNTERS_MARK_DICE: String = "1d6"
const DATA_ONLY: Dictionary = {
	"tireless": "no temporary hit points or exhaustion in play yet",
}

static func activate(record: Dictionary) -> void:
	record["features"]["weapon_mastery"] = {"weapons": START_MASTERY.duplicate()}

static func advance(actor: Dictionary, level: int) -> void:
	var features: Dictionary = actor["features"]
	ClassKits.set_uses(features, "favored_enemy", FAVORED_ENEMY[clampi(level, 1, 10) - 1], "long")
	if level >= 5:
		features["extra_attack"] = {"attacks": 2}
	if level >= 6:
		features["roving"] = {}

static func level_choices(actor: Dictionary, level: int) -> Array:
	var result: Array = []
	var skills: Array[String] = []
	for skill: Variant in actor.get("skill_proficiencies", []):
		if not String(skill) in actor.get("skill_expertise", []):
			skills.append(String(skill))
	if level == 2:
		result.append({"key": "deft_explorer", "count": 1, "title_key": "LEVELUP_SECTION_DEFT_EXPLORER",
			"options": skills, "option_prefix": "SHEET_SKILL_"})
		if String(actor.get("features", {}).get("fighting_style", "")).is_empty():
			result.append({"key": "fighting_style", "count": 1, "title_key": "LEVELUP_SECTION_RANGER_STYLE",
				"options": FIGHTING_STYLES.duplicate(), "option_prefix": "FEAT_"})
	if level == 9:
		result.append({"key": "expertise", "count": 2, "title_key": "LEVELUP_SECTION_RANGER_EXPERTISE",
			"options": skills, "option_prefix": "SHEET_SKILL_"})
	return result

static func apply_level_choices(actor: Dictionary, _level: int, picks: Dictionary) -> void:
	var expertise: Array = actor.get("skill_expertise", []).duplicate()
	for key: String in ["deft_explorer", "expertise"]:
		for skill: Variant in picks.get(key, []):
			expertise.append(String(skill))
	actor["skill_expertise"] = expertise
	for style: Variant in picks.get("fighting_style", []):
		actor["features"]["fighting_style"] = String(style)

# --- Equipment ---------------------------------------------------------------

## Fighting Style Archery: +2 to attack rolls with Ranged weapons.
static func adjust_weapon(actor: Dictionary, record: Dictionary, _item: Dictionary) -> void:
	if String(actor.get("features", {}).get("fighting_style", "")) == "archery" and bool(record.get("ranged", false)):
		record["attack_modifiers"].append({"amount": 2, "source": "archery"})
		record["attack_bonus"] = int(record["attack_bonus"]) + 2

## Fighting Style Defense: +1 AC while wearing armour.
static func ac_bonus(actor: Dictionary, armor_id: StringName) -> Array:
	if String(actor.get("features", {}).get("fighting_style", "")) == "defense" and armor_id != &"none":
		return [{"amount": 1, "source": "defense"}]
	return []

static func speed_bonus_m(actor: Dictionary) -> float:
	if actor.get("features", {}).has("roving") and not ClassKits.heavy_armor(actor):
		return ROVING_M
	return 0.0

# --- Favored Enemy and Hunter's Mark -----------------------------------------

static func free_casts(_actor: Dictionary) -> Dictionary:
	return {"hunters_mark": "favored_enemy"}

static func marked_by(target: Dictionary, attacker_id: String) -> bool:
	for effect: Dictionary in ActiveEffects.effects(target):
		if String(effect.get("kind", "")) == "hunters_mark" and String(effect.get("source_id", "")) == attacker_id:
			return true
	return false

## Hunter's Mark: 1d6 Force on every weapon hit against the marked creature.
static func extra_damage_dice(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		_critical: bool) -> Array:
	if not weapon.get("spell_id", "") in ["", null] or not marked_by(state.actors.get(target_id, {}), attacker_id):
		return []
	return [{"dice": HUNTERS_MARK_DICE, "damage_type": "force", "source": "hunters_mark"}]

static func expected_extra_damage(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary) -> float:
	return 3.5 if not extra_damage_dice(state, attacker_id, target_id, weapon, false).is_empty() else 0.0

# --- Weapon Mastery -------------------------------------------------------------

static func attack_advantages(state: GameState, attacker_id: String, target_id: String, _weapon: Dictionary) -> Array[StringName]:
	return WeaponMasteries.attack_advantages(state, attacker_id, target_id)

static func after_attack(state: GameState, attacker_id: String, target_id: String, weapon: Dictionary,
		hit: bool, rng: RandomNumberGenerator) -> Array[Dictionary]:
	return WeaponMasteries.after_attack(state, attacker_id, target_id, weapon, hit, rng)

static func on_turn_start(state: GameState, actor_id: String) -> Array[Dictionary]:
	WeaponMasteries.on_turn_start(state, actor_id)
	return []

static func on_turn_end(state: GameState, actor_id: String, _rng: RandomNumberGenerator) -> Array[Dictionary]:
	WeaponMasteries.on_turn_end(state, actor_id)
	return []

static func on_combat_end(state: GameState, actor_id: String) -> void:
	state.actors[actor_id].erase("mastery_vex")
