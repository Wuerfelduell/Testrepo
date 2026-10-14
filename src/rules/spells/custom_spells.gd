class_name CustomSpells
extends RefCounted
## Spells whose rules do not fit the data-driven resolutions ("custom" resolution): a
## module script lists its spell ids in const SPELLS and implements
##   preview(state, caster_id, spell, result, target_ids, point) -> result (legal, reason_key, targets)
##   resolve(state, caster_id, spell, pending, rng) -> events
## The same modules may also implement ClassKits hooks (ClassKits.EFFECT_MODULES).

const MODULES: Array[String] = ["res://src/rules/spells/ranger_spells.gd"]

static var _owners: Dictionary = {}

static func module_for(spell_id: String) -> Script:
	if _owners.is_empty():
		for path: String in MODULES:
			var script: Script = load(path) as Script
			for id: Variant in script.get_script_constant_map().get("SPELLS", []):
				_owners[String(id)] = script
	return _owners.get(spell_id) as Script

static func preview(state: GameState, caster_id: String, spell: SpellDefinition, result: Dictionary,
		target_ids: Array, point: Vector3) -> Dictionary:
	var module: Script = module_for(String(spell.id))
	if module == null:
		return result
	return module.call("preview", state, caster_id, spell, result, target_ids, point)

static func resolve(state: GameState, caster_id: String, spell: SpellDefinition, pending: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var module: Script = module_for(String(spell.id))
	if module != null:
		events.assign(module.call("resolve", state, caster_id, spell, pending, rng))
	return events
