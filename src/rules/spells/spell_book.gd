class_name SpellBook
extends RefCounted
## Loads SRD spell data from data/spells by id. Ids from the network are checked
## against a strict pattern before any path is built.

const DIRECTORY: String = "res://data/spells/"
static var _cache: Dictionary = {}

static func get_spell(spell_id: String) -> SpellDefinition:
	if _cache.has(spell_id):
		return _cache[spell_id]
	var pattern: RegEx = RegEx.create_from_string("^[a-z][a-z_]{0,40}$")
	if pattern.search(spell_id) == null:
		return null
	var path: String = DIRECTORY + spell_id + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var spell: SpellDefinition = load(path) as SpellDefinition
	if spell == null or not spell.is_valid() or String(spell.id) != spell_id:
		return null
	_cache[spell_id] = spell
	return spell
