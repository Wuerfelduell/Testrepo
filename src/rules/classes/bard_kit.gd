extends RefCounted
## SRD 5.2 Bard, levels 1-10, no subclass (ClassKits interface, see README.md).
## Spellcasting (Charisma, full caster) is the "bard" entry of ClassSpellcasting.
## Bardic Inspiration is a feature spell (data/spells/bardic_inspiration.tres, feature_resource
## "bardic_inspiration") so it gets ally targeting; its uses are features.bardic_inspiration.
## The inspired creature adds the die to a failed attack roll or save it could still turn
## into a success (ActiveEffects.inspire_roll), then the inspiration is used up.

const PRIORITY: Array[StringName] = [&"cha", &"dex", &"con", &"wis", &"int", &"str"]
const SKILLS: Dictionary = {"class": [&"performance", &"persuasion", &"deception"], "human": &"insight"}
const DATA_ONLY: Dictionary = {
	"jack_of_all_trades": "ability checks only add full proficiency so far",
	"countercharm": "no charm or fear effects on the party yet",
}
const INSPIRATION: String = "bardic_inspiration"
## Expertise: two more skills at levels 2 and 9.
const EXPERTISE_COUNT: int = 2
const MAGICAL_SECRETS_COUNT: int = 2

static func inspiration_die(level: int) -> int:
	if level >= 10:
		return 10
	return 8 if level >= 5 else 6

## Uses = Charisma modifier (at least one).
static func inspiration_max(actor: Dictionary) -> int:
	return maxi(1, Abilities.modifier(ClassKits.score(actor, "cha")))

static func activate(record: Dictionary) -> void:
	record["features"][INSPIRATION] = {"die": 6, "uses": 0, "max": 0, "recharge": "long"}

static func upgrade(record: Dictionary) -> void:
	refresh_derived(record)

static func advance(actor: Dictionary, level: int) -> void:
	var features: Dictionary = actor["features"]
	var inspiration: Dictionary = features.get(INSPIRATION, {"die": 6, "uses": 0, "max": 0})
	inspiration["die"] = inspiration_die(level)
	# Font of Inspiration (level 5): every use comes back on a Short Rest too.
	inspiration["recharge"] = "short" if level >= 5 else "long"
	features[INSPIRATION] = inspiration
	if level >= 5:
		features["font_of_inspiration"] = {}
	_sync_uses(actor)

## Spent uses stay spent when the maximum grows (a higher Charisma).
static func _sync_uses(actor: Dictionary) -> void:
	var inspiration: Dictionary = actor["features"].get(INSPIRATION, {})
	if inspiration.is_empty():
		return
	var maximum: int = inspiration_max(actor)
	inspiration["uses"] = clampi(int(inspiration.get("uses", 0)) + maximum - int(inspiration.get("max", 0)), 0, maximum)
	inspiration["max"] = maximum

static func refresh_derived(actor: Dictionary) -> void:
	actor["spell_modifier"] = Abilities.modifier(ClassKits.score(actor, "cha"))
	_sync_uses(actor)
	var spells: Array = actor.get("spells", [])
	if SpellBook.get_spell(INSPIRATION) != null and not INSPIRATION in spells:
		spells.append(INSPIRATION)
	for spell_id: Variant in actor.get("features", {}).get("magical_secrets", {}).get("spells", []):
		if not String(spell_id) in spells:
			spells.append(String(spell_id))
	actor["spells"] = spells

static func level_choices(actor: Dictionary, level: int) -> Array:
	var result: Array = []
	if level == 2 or level == 9:
		var options: Array[String] = []
		var expertise: Array = actor.get("skill_expertise", [])
		for skill: Variant in actor.get("skill_proficiencies", []):
			if not String(skill) in expertise and not String(skill) in options:
				options.append(String(skill))
		result.append({"key": "bard_expertise", "count": EXPERTISE_COUNT, "options": options,
			"title_key": "LEVELUP_SECTION_BARD_EXPERTISE", "option_prefix": "SHEET_SKILL_",
			"note_key": "LEVELUP_SECTION_BARD_EXPERTISE_NOTE"})
	if level == 10:
		result.append({"key": "magical_secrets", "count": MAGICAL_SECRETS_COUNT,
			"options": magical_secrets_options(actor, level), "title_key": "LEVELUP_SECTION_MAGICAL_SECRETS",
			"option_prefix": "", "note_key": "LEVELUP_SECTION_MAGICAL_SECRETS_NOTE"})
	return result

## Magical Secrets: spells of every other class list (Cleric, Druid, Wizard ...) up to
## the highest slot, that the Bard list does not already have.
static func magical_secrets_options(actor: Dictionary, level: int) -> Array[String]:
	var result: Array[String] = []
	var own: Array[String] = ClassSpellcasting.spell_list("bard")
	var highest: int = ClassSpellcasting.highest_slot("bard", level)
	for class_id: String in ClassSpellcasting.CASTERS:
		if class_id == "bard":
			continue
		for spell_id: String in ClassSpellcasting.spell_list(class_id):
			var spell: SpellDefinition = SpellBook.get_spell(spell_id)
			if spell.is_cantrip() or spell.level > highest or spell_id in own or spell_id in result or \
					spell_id in actor.get("spells", []):
				continue
			result.append(spell_id)
	return result

static func apply_level_choices(actor: Dictionary, _level: int, picks: Dictionary) -> void:
	if picks.has("bard_expertise"):
		var expertise: Array = actor.get("skill_expertise", []).duplicate()
		for skill: Variant in picks["bard_expertise"]:
			expertise.append(String(skill))
		actor["skill_expertise"] = expertise
	if picks.has("magical_secrets"):
		var secrets: Array = []
		for spell_id: Variant in picks["magical_secrets"]:
			secrets.append(String(spell_id))
		actor["features"]["magical_secrets"] = {"spells": secrets}

## Rests: ClassKits.recharge refills the uses (Long Rest, or Short Rest from level 5).
static func on_rest(actor: Dictionary, _rest: String) -> void:
	refresh_derived(actor)
