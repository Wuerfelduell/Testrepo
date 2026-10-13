class_name MonsterDefinition
extends Resource
## SRD 5.2 stat-block data. Behaviour weights and test art do not change its rules.
## Distances follow the existing project's conversion of 5 feet to 1.5 metres.

const SOURCE_URL: String = "https://media.dndbeyond.com/compendium-images/srd/5.2/SRD_CC_v5.2.pdf"

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var srd_name: String = ""
@export var srd_page: int = 0
@export var hit_points: int = 1
@export var armor_class: int = 10
@export var ability_scores: Dictionary = {}
@export var speed_m: float = 9.0
@export var proficiency_bonus: int = 2
@export var skills: Dictionary = {}
@export var saving_throws: Dictionary = {}
@export var passive_perception: int = 10
@export var challenge_rating: String = "1/8"
@export var experience: int = 25
@export var attacks: Array[Dictionary] = []
## Multiattack: attacks per Attack action (any mix of the entries in `attacks`).
@export_range(1, 4) var multiattack: int = 1
## Spellcasting: spell id -> uses per day (0 = at will). Uses replace spell slots.
@export var spells: Dictionary = {}
@export var spell_save_dc: int = 0
## Spellcasting ability modifier, added to healing spells.
@export var spell_modifier: int = 0
@export_enum("brute", "archer", "coward") var personality: String = "brute"
@export var model: String = "res://assets/characters/undead_cultist/model.glb"
@export var model_is_provisional: bool = true

func is_valid() -> bool:
	return id != &"" and name_key != &"" and srd_page > 0 and hit_points > 0 and \
		armor_class > 0 and Abilities.valid_scores(ability_scores) and \
		is_finite(speed_m) and speed_m > 0.0 and not attacks.is_empty()

## Deep-copy into plain data: GameState must never contain mutable Resources.
func create_actor(actor_id: String, start_position: Vector3) -> Dictionary:
	if not is_valid() or actor_id.is_empty() or not start_position.is_finite():
		return {}
	var record: Dictionary = {
		"id": actor_id, "definition_id": String(id), "team": "enemy",
		"name_key": String(name_key), "position": start_position,
		"hp": hit_points, "max_hp": hit_points, "ac": armor_class,
		"dex": int(ability_scores[&"dex"]), "speed_m": speed_m,
		"move_left": speed_m, "action_available": true,
		"bonus_available": true, "reaction_available": true, "disengaged": false,
		"weapon": attacks[0].duplicate(true), "attacks": attacks.duplicate(true),
		"model": model, "model_is_provisional": model_is_provisional,
		"personality": personality, "conditions": [],
		"ability_scores": ability_scores.duplicate(true), "skills": skills.duplicate(true),
		"saving_throws": saving_throws.duplicate(true),
		"passive_perception": passive_perception, "proficiency_bonus": proficiency_bonus,
		"creature_type": "humanoid", "challenge_rating": challenge_rating, "experience": experience,
		"srd_name": srd_name, "srd_page": srd_page, "source_url": SOURCE_URL,
	}
	if multiattack > 1:
		record["features"] = {"extra_attack": {"attacks": multiattack}}
		# "Two attacks, using Mace or Radiant Flame in any combination."
		record["chooses_attack"] = true
	if not spells.is_empty():
		var uses: Dictionary = {}
		for spell_id: Variant in spells:
			if int(spells[spell_id]) > 0:
				uses[String(spell_id)] = int(spells[spell_id])
		record["spells"] = spells.keys().map(func(spell_id: Variant) -> String: return String(spell_id))
		record["spell_uses"] = uses
		record["spell_uses_max"] = uses.duplicate()
		record["spell_save_dc"] = spell_save_dc
		record["spell_modifier"] = spell_modifier
		record["concentration"] = {}
	return record
