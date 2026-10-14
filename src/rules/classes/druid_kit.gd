extends RefCounted
## Druid (SRD 5.2, levels 1-10, no subclass). Spells: ClassSpellcasting["druid"];
## Wild Shape and its revert are feature spells (ClassEffects.wild_shape, only the Wolf
## form for now). Wild Resurgence: ClassEffects.resource_available spends a slot for a
## Wild Shape use once per turn when none are left.
## Follows BG3: no Primal Order and no Elemental Fury.

const PRIORITY: Array[StringName] = [&"wis", &"con", &"dex", &"int", &"str", &"cha"]
const SKILLS: Dictionary = {"class": [&"nature", &"perception"], "human": &"insight"}
const DATA_ONLY: Dictionary = {
	"druidic": "no secret messages in play yet",
	"wild_companion": "no summoned creatures in play yet",
}

static func advance(actor: Dictionary, level: int) -> void:
	var features: Dictionary = actor["features"]
	if level >= 2:
		# One use back on a Short Rest, all on a Long Rest.
		ClassKits.set_uses(features, "wild_shape", 3 if level >= 6 else 2, "long", 1)
	if level >= 5:
		features["wild_resurgence"] = features.get("wild_resurgence", {})

static func on_combat_end(state: GameState, actor_id: String) -> void:
	ClassEffects.revert_wild_shape(state.actors[actor_id], actor_id)

## Wild Shape ends when the Druid is Incapacitated (or falls to 0 hit points).
static func on_turn_start(state: GameState, actor_id: String) -> Array[Dictionary]:
	var actor: Dictionary = state.actors[actor_id]
	if actor.has("wild_shape") and (not CombatRules.alive(actor) or CombatRules.conditions_for(actor).has(&"incapacitated")):
		return ClassEffects.revert_wild_shape(actor, actor_id)
	return []
