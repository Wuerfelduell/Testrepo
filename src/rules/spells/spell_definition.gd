class_name SpellDefinition
extends Resource
## SRD 5.2 spell data. Distances use the project conversion of 5 feet to 1.5 metres.
## Pure data: SpellRules and SpellResolver interpret it, presentation reads name_key/vfx.

const SCHOOLS: Array[String] = ["abjuration", "conjuration", "divination", "enchantment",
	"evocation", "illusion", "necromancy", "transmutation"]

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var srd_name: String = ""
## Page numbers are added once checked against the SRD 5.2 PDF; srd_name is authoritative.
@export var srd_page: int = 0
## 0 is a cantrip.
@export_range(0, 9) var level: int = 0
@export var school: String = "evocation"
@export_enum("action", "bonus_action", "reaction") var casting_time: String = "action"
## "self" spells use range 0 and an area that starts at the caster.
@export_enum("creature", "point", "self", "darts") var targeting: String = "creature"
@export var range_m: float = 0.0
@export_enum("none", "cone", "sphere", "line") var area: String = "none"
## Cone length, sphere radius or line length.
@export var area_size_m: float = 0.0
@export var line_width_m: float = 1.5
## "darts" + "attack" are beams: one attack roll per beam (Eldritch Blast, Scorching Ray).
@export_enum("attack", "save", "auto", "heal", "none") var resolution: String = "attack"
@export var save_ability: StringName = &""
@export var damage_dice: String = ""
@export var damage_type: StringName = &""
@export var half_on_save: bool = false
## "heal" resolution: dice of hit points restored, plus the caster's spellcasting modifier.
@export var heal_dice: String = ""
## Per dart for "darts" targeting: dice plus flat bonus.
@export var darts: int = 0
@export var dart_bonus: int = 0
## Cantrips multiply their dice count at character levels 5/11/17; slot spells add
## upcast_dice per slot level above their own.
@export var upcast_dice: String = ""
@export var upcast_darts: int = 0
@export var concentration: bool = false
@export var duration_rounds: int = 0
## Rider effect id interpreted by ActiveEffects: "speed_penalty", "sleep", "shield",
## "spirit_guardians" (an aura around the concentrating caster), and the class effects
## of ClassEffects ("bless", "ac_bonus", "barkskin", "divine_favor", "faerie_fire",
## "guiding_bolt", "hold", "entangle", "resistance", "aid", "turned", "frightened",
## "lay_on_hands", "wild_shape", "revert_wild_shape").
@export var effect: StringName = &""
@export var effect_amount: float = 0.0
## Only creatures of the caster's choice (Sleep) instead of everyone inside the area.
@export var chosen_creatures: bool = false
@export var vfx: StringName = &""
## Class features that use the spell pipeline (targeting, preview, AI, hotbar) but spend
## a feature resource instead of a slot: "channel_divinity", "lay_on_hands", "wild_shape",
## or "free" (no cost). They are never cantrips or prepared spells.
@export var feature_resource: String = ""
## One damage/heal die more at each of these caster levels (Divine Spark: 7, 13, 18).
@export var scale_levels: Array[int] = []
## Adds the caster's spellcasting modifier to damage (Divine Spark).
@export var add_spell_modifier: bool = false
## A second damage type rolled with the first (Flame Strike, Ice Storm); halves together.
@export var extra_damage_dice: String = ""
@export var extra_damage_type: StringName = &""
## Spells for the caster's side (Bless, Aid, Shield of Faith, Mass Healing Word): allies
## only, the caster included. Areas take at most max_targets (0 = no limit) plus
## upcast_targets per slot level. A "none" creature spell without it is a mark on a foe.
@export var allies: bool = false
@export var max_targets: int = 0
@export var upcast_targets: int = 0
## Only creatures of these types are affected (Turn Undead: undead). Empty = any.
@export var creature_types: Array[StringName] = []

func is_valid() -> bool:
	if id == &"" or name_key == &"" or srd_name.is_empty() or srd_page < 0 or not school in SCHOOLS:
		return false
	if not is_finite(range_m) or range_m < 0.0 or not is_finite(area_size_m) or area_size_m < 0.0:
		return false
	if area != "none" and area_size_m <= 0.0:
		return false
	if not damage_dice.is_empty():
		if Dice.parse(damage_dice).has("error") or not damage_type in DamageRules.TYPES:
			return false
	if not upcast_dice.is_empty() and Dice.parse(upcast_dice).has("error"):
		return false
	if resolution == "save" and not save_ability in Abilities.IDS:
		return false
	if resolution == "heal" and ((targeting != "creature" and area == "none") or \
			(not heal_dice.is_empty() and Dice.parse(heal_dice).has("error")) or (heal_dice.is_empty() and effect != &"lay_on_hands")):
		return false
	if not extra_damage_dice.is_empty() and (Dice.parse(extra_damage_dice).has("error") or not extra_damage_type in DamageRules.TYPES):
		return false
	if targeting == "darts" and darts <= 0:
		return false
	return true

func is_cantrip() -> bool:
	return level == 0 and feature_resource.is_empty()

func is_feature() -> bool:
	return not feature_resource.is_empty()
