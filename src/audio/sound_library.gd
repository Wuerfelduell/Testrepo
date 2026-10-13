class_name SoundLibrary
extends RefCounted
## Package 11: which sound belongs to which game event, and which music to which state.
## Pure data and pure functions: no nodes, no playback. AudioDirector plays what this returns,
## so tests can check every mapping without an audio device.

const SFX_DIR: String = "res://assets/audio/sfx/"
const MUSIC_DIR: String = "res://assets/audio/music/"
const AMBIENCE_DIR: String = "res://assets/audio/ambience/"

## Default surface for footsteps when a level registers nothing else (crypt stone).
const DEFAULT_SURFACE: String = "stone"
const SURFACES: Array[String] = ["stone", "dirt", "wood", "water"]
## Metres walked per footstep (an adult stride at combat walking speed).
const STEP_METRES: float = 0.8

## Damage types that have their own hit sound; every other type uses hit_generic.
const HIT_TYPES: Array[String] = ["slashing", "piercing", "bludgeoning", "fire", "cold", "force"]
## Spells with their own cast/impact sounds; unknown spells fall back to spell_cast/spell_impact.
const SPELLS: Array[String] = ["fire_bolt", "ray_of_frost", "magic_missile", "burning_hands", "sleep", "shield",
	"acid_splash", "poison_spray", "shatter", "fireball"]

## cue -> {"files": [paths, one picked at random], "volume_db": float, "bus": String}.
## Paths are relative to SFX_DIR unless they start with "res://".
## Effects sit around -6 dB, music is mixed lower (see MUSIC_VOLUME_DB) so combat stays readable.
const CUES: Dictionary = {
	"ui_click": {"files": ["ui_click_1.ogg", "ui_click_2.ogg"], "volume_db": -10.0, "bus": "UI"},
	"dice_roll": {"files": ["dice_roll_1.ogg", "dice_roll_2.ogg"], "volume_db": -6.0, "bus": "UI"},
	"dice_land": {"files": ["dice_land_1.ogg", "dice_land_2.ogg"], "volume_db": -4.0, "bus": "UI"},
	"dice_crit": {"files": ["dice_crit.ogg"], "volume_db": -4.0, "bus": "UI"},
	"dice_fumble": {"files": ["dice_fumble.ogg"], "volume_db": -4.0, "bus": "UI"},
	"footstep_stone": {"files": ["footstep_stone_1.ogg", "footstep_stone_2.ogg", "footstep_stone_3.ogg", "footstep_stone_4.ogg"], "volume_db": -14.0, "bus": "Effects"},
	"footstep_dirt": {"files": ["footstep_dirt_1.ogg", "footstep_dirt_2.ogg", "footstep_dirt_3.ogg", "footstep_dirt_4.ogg"], "volume_db": -14.0, "bus": "Effects"},
	"footstep_wood": {"files": ["footstep_wood_1.ogg", "footstep_wood_2.ogg", "footstep_wood_3.ogg", "footstep_wood_4.ogg"], "volume_db": -14.0, "bus": "Effects"},
	"footstep_water": {"files": ["footstep_water_1.ogg", "footstep_water_2.ogg", "footstep_water_3.ogg"], "volume_db": -12.0, "bus": "Effects"},
	"swing_melee": {"files": ["swing_1.ogg", "swing_2.ogg", "swing_3.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"shot_ranged": {"files": ["bow_shot_1.ogg", "bow_shot_2.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"hit_slashing": {"files": ["hit_slashing_1.ogg", "hit_slashing_2.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"hit_piercing": {"files": ["hit_piercing_1.ogg", "hit_piercing_2.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"hit_bludgeoning": {"files": ["hit_bludgeoning_1.ogg", "hit_bludgeoning_2.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"hit_fire": {"files": ["hit_fire.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"hit_cold": {"files": ["hit_cold.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"hit_force": {"files": ["hit_force.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"hit_generic": {"files": ["hit_bludgeoning_1.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"miss": {"files": ["miss_1.ogg", "miss_2.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"critical": {"files": ["critical.ogg"], "volume_db": -4.0, "bus": "Effects"},
	"death": {"files": ["death_1.ogg", "death_2.ogg"], "volume_db": -4.0, "bus": "Effects"},
	"spell_cast": {"files": ["spell_cast.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_fire_bolt": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_fire_bolt": {"files": ["spell_impact_fire.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_burning_hands": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_burning_hands": {"files": ["spell_impact_flames.ogg"], "volume_db": -5.0, "bus": "Effects"},
	"spell_cast_ray_of_frost": {"files": ["spell_cast_frost.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_ray_of_frost": {"files": ["spell_impact_frost.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_magic_missile": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_magic_missile": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_sleep": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_sleep": {"files": ["spell_impact_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_cast_shield": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	# Prompt 08 spells reuse existing files until they get their own.
	"spell_cast_acid_splash": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_acid_splash": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_poison_spray": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_poison_spray": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_shatter": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_shatter": {"files": ["spell_impact_arcane.ogg"], "volume_db": -5.0, "bus": "Effects"},
	"spell_cast_fireball": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_fireball": {"files": ["spell_impact_flames.ogg"], "volume_db": -4.0, "bus": "Effects"},
	"spell_blocked": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"heal": {"files": ["heal.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"level_up": {"files": ["level_up.ogg"], "volume_db": -4.0, "bus": "UI"},
	"loot_pickup": {"files": ["loot_pickup_1.ogg", "loot_pickup_2.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"amb_drip": {"files": ["res://assets/audio/ambience/drip_1.ogg", "res://assets/audio/ambience/drip_2.ogg", "res://assets/audio/ambience/drip_3.ogg"], "volume_db": -12.0, "bus": "Ambience"},
}

## Music state -> track. Looping states loop; "victory" is a stinger that hands back to exploration.
const MUSIC_STATES: Array[StringName] = [&"menu", &"exploration", &"combat", &"boss", &"victory", &"death"]
const MUSIC: Dictionary = {
	&"menu": {"file": "menu.ogg", "loop": true},
	&"exploration": {"file": "exploration.ogg", "loop": true},
	&"combat": {"file": "combat.ogg", "loop": true},
	&"boss": {"file": "boss.ogg", "loop": true},
	&"victory": {"file": "victory.ogg", "loop": false},
	&"death": {"file": "death.ogg", "loop": true},
}
const MUSIC_VOLUME_DB: float = -10.0
const CROSSFADE_SECONDS: float = 1.8

const AMBIENCE: Dictionary = {
	"room_tone": {"file": "room_tone.ogg", "volume_db": -16.0},
	"whispers": {"file": "whispers.ogg", "volume_db": -6.0},
}

static func cue_paths(cue: String) -> PackedStringArray:
	var paths: PackedStringArray = []
	if not CUES.has(cue):
		return paths
	for file: String in CUES[cue]["files"]:
		paths.append(file if file.begins_with("res://") else SFX_DIR + file)
	return paths

static func music_path(music_state: StringName) -> String:
	return MUSIC_DIR + String(MUSIC[music_state]["file"]) if MUSIC.has(music_state) else ""

static func ambience_path(id: String) -> String:
	return AMBIENCE_DIR + String(AMBIENCE[id]["file"]) if AMBIENCE.has(id) else ""

static func hit_cue(damage_type: String) -> String:
	return "hit_" + damage_type if damage_type in HIT_TYPES else "hit_generic"

static func spell_cue(spell_id: String, phase: String) -> String:
	var specific: String = "spell_%s_%s" % [phase, spell_id]
	return specific if CUES.has(specific) else "spell_" + phase

static func footstep_cue(surface: String) -> String:
	return "footstep_" + (surface if surface in SURFACES else DEFAULT_SURFACE)

## Sounds for one CommandBus event. Each entry is {"cue": String, "position": Vector3}
## (Vector3.INF = not positional). `state` is the committed state after the command.
static func cues_for_event(event: Dictionary, state: GameState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actor_at: Vector3 = actor_position(state, String(event.get("actor_id", "")))
	var target_at: Vector3 = actor_position(state, String(event.get("target_id", "")))
	match String(event.get("type", "")):
		"start_attack":
			var weapon: Dictionary = event.get("weapon", {})
			result.append(_cue("shot_ranged" if bool(weapon.get("ranged", false)) else "swing_melee", actor_at))
		"roll":
			if String(event.get("kind", "")) == "attack":
				if not bool(event.get("hit", false)):
					result.append(_cue("miss", target_at))
				elif bool(event.get("critical", false)):
					result.append(_cue("critical", target_at))
		"damage":
			result.append(_cue(hit_cue(String(event.get("damage_type", ""))), target_at))
		"death":
			result.append(_cue("death", actor_at))
		"start_spell":
			result.append(_cue(spell_cue(String(event.get("spell_id", "")), "cast"), actor_at))
		"reaction":
			if String(event.get("reaction", "")) == "shield":
				result.append(_cue("spell_cast_shield", actor_at))
		"spell_blocked":
			result.append(_cue("spell_blocked", target_at))
		"heal":
			result.append(_cue("heal", actor_at))
		"xp_awarded":
			# gained_levels is the list of new levels (AwardVictoryXpCommand), not a count.
			var gained: Variant = event.get("gained_levels", [])
			if (gained is Array and not (gained as Array).is_empty()) or ((gained is int or gained is float) and int(gained) > 0):
				result.append(_cue("level_up", Vector3.INF))
	return result

## Sounds for a whole command. Some packages (level-up, loot) are recognised by their
## command script name, so they need no audio code and no agreed event names.
static func cues_for_command(command_path: String, result: Dictionary, state: GameState) -> Array[Dictionary]:
	var cues: Array[Dictionary] = []
	var file: String = command_path.get_file()
	if file.begins_with("loot_take"):
		cues.append(_cue("loot_pickup", Vector3.INF))
	elif file.begins_with("level_up_"):
		cues.append(_cue("level_up", Vector3.INF))
	for event: Variant in result.get("events", []):
		if event is Dictionary:
			cues.append_array(cues_for_event(event, state))
	return cues

## Which track the state calls for. `current` keeps menu music while no run exists and
## lets the victory stinger finish before exploration music returns.
static func music_state_for(state: GameState, current: StringName) -> StringName:
	if state.actors.is_empty():
		return current
	match state.mode:
		&"combat":
			return &"boss" if boss_alive(state) else &"combat"
		&"defeat":
			return &"death"
		_:
			if current == &"combat" or current == &"boss" or current == &"victory":
				return &"victory"
			return &"exploration"

static func boss_alive(state: GameState) -> bool:
	return not boss_id(state).is_empty()

## First living boss: a record flagged "boss", or one whose model is a boss model.
static func boss_id(state: GameState) -> String:
	var ids: Array = state.actors.keys()
	ids.sort()
	for id: Variant in ids:
		var actor: Dictionary = state.actors[id]
		if actor.get("team") != "enemy" or int(actor.get("hp", 0)) <= 0:
			continue
		if bool(actor.get("boss", false)) or String(actor.get("model", "")).contains("/boss_"):
			return String(id)
	return ""

static func actor_position(state: GameState, actor_id: String) -> Vector3:
	if actor_id.is_empty() or not state.actors.has(actor_id):
		return Vector3.INF
	var position: Variant = state.actors[actor_id].get("position")
	return position if position is Vector3 else Vector3.INF

## Every cue an event can produce, for the coverage test.
static func all_event_cues() -> PackedStringArray:
	var cues: PackedStringArray = ["ui_click", "dice_roll", "dice_land", "dice_crit", "dice_fumble",
		"swing_melee", "shot_ranged", "miss", "critical", "death", "spell_cast", "spell_impact",
		"spell_blocked", "heal", "level_up", "loot_pickup", "hit_generic", "amb_drip"]
	for surface: String in SURFACES:
		cues.append(footstep_cue(surface))
	for damage_type: String in HIT_TYPES:
		cues.append(hit_cue(damage_type))
	for spell_id: String in SPELLS:
		cues.append(spell_cue(spell_id, "cast"))
		if spell_id != "shield":
			cues.append(spell_cue(spell_id, "impact"))
	return cues

static func _cue(cue: String, position: Vector3) -> Dictionary:
	return {"cue": cue, "position": position}
