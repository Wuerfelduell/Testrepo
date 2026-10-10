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
@export_enum("attack", "save", "auto", "none") var resolution: String = "attack"
@export var save_ability: StringName = &""
@export var damage_dice: String = ""
@export var damage_type: StringName = &""
@export var half_on_save: bool = false
## Per dart for "darts" targeting: dice plus flat bonus.
@export var darts: int = 0
@export var dart_bonus: int = 0
## Cantrips multiply their dice count at character levels 5/11/17; slot spells add
## upcast_dice per slot level above their own.
@export var upcast_dice: String = ""
@export var upcast_darts: int = 0
@export var concentration: bool = false
@export var duration_rounds: int = 0
## Rider effect id interpreted by ActiveEffects: "speed_penalty", "sleep", "shield".
@export var effect: StringName = &""
@export var effect_amount: float = 0.0
## Only creatures of the caster's choice (Sleep) instead of everyone inside the area.
@export var chosen_creatures: bool = false
@export var vfx: StringName = &""

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
	if targeting == "darts" and darts <= 0:
		return false
	return true

func is_cantrip() -> bool:
	return level == 0
