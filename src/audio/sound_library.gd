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
	"acid_splash", "poison_spray", "shatter", "fireball", "healing_word", "spirit_guardians",
	# Cleric, Paladin and Druid spells (reuse existing files until they get their own).
	"sacred_flame", "resistance", "produce_flame", "starry_wisp", "bless", "cure_wounds",
	"guiding_bolt", "inflict_wounds", "shield_of_faith", "divine_favor", "entangle", "faerie_fire",
	"aid", "barkskin", "hold_person", "mass_healing_word", "call_lightning", "blight", "ice_storm",
	"flame_strike", "mass_cure_wounds", "divine_spark", "divine_spark_heal", "turn_undead",
	"abjure_foes", "lay_on_hands", "wild_shape", "revert_wild_shape", "guidance",
	"hunters_mark",
	# 2024 Cleric, Paladin and Druid spells (existing files by element).
	"toll_the_dead", "word_of_radiance", "thorn_whip", "bane", "command", "heroism",
	"protection_from_evil_and_good", "ice_knife", "searing_smite", "thunderous_smite", "wrathful_smite",
	"compelled_duel", "spiritual_weapon", "spiritual_weapon_strike", "prayer_of_healing", "blindness_deafness",
	"moonbeam", "flame_blade", "flame_blade_strike", "heat_metal", "heat_metal_repeat", "shining_smite",
	"magic_weapon", "silence", "beacon_of_hope", "bestow_curse", "dispel_magic", "sleet_storm",
	"blinding_smite", "crusaders_mantle", "aura_of_vitality", "aura_of_vitality_heal", "elemental_weapon",
	"banishment", "death_ward", "stoneskin", "greater_restoration", "insect_plague", "contagion",
	"wrath_of_nature",
	# Bard, Sorcerer, Warlock spells (existing sound files, see CUES).
	"eldritch_blast", "vicious_mockery", "shocking_grasp", "chill_touch", "dissonant_whispers", "thunderwave", "hex",
	"arms_of_hadar", "scorching_ray", "lightning_bolt", "phantasmal_killer", "cone_of_cold", "hold_monster",
	"bardic_inspiration"]

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
	# Cult Priest spells (prompt 10 follow-up) reuse existing files until they get their own.
	"spell_cast_healing_word": {"files": ["heal.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_healing_word": {"files": ["heal.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_spirit_guardians": {"files": ["spell_cast_sleep.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_impact_spirit_guardians": {"files": ["spell_impact_arcane.ogg"], "volume_db": -5.0, "bus": "Effects"},
	# Cleric, Paladin and Druid spells reuse existing files until they get their own.
	"spell_cast_guidance": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_guidance": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_sacred_flame": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_sacred_flame": {"files": ["spell_impact_fire.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_resistance": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_resistance": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_produce_flame": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_produce_flame": {"files": ["spell_impact_fire.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_starry_wisp": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_starry_wisp": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_bless": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_bless": {"files": ["heal.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_cure_wounds": {"files": ["heal.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_cure_wounds": {"files": ["heal.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_guiding_bolt": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_guiding_bolt": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_inflict_wounds": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_inflict_wounds": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_shield_of_faith": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_shield_of_faith": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_divine_favor": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_divine_favor": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_entangle": {"files": ["spell_cast.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_entangle": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_faerie_fire": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_faerie_fire": {"files": ["spell_impact_sleep.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_aid": {"files": ["heal.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_aid": {"files": ["heal.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_barkskin": {"files": ["spell_cast.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_barkskin": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_hold_person": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_hold_person": {"files": ["spell_impact_sleep.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_mass_healing_word": {"files": ["heal.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_mass_healing_word": {"files": ["heal.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_call_lightning": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_call_lightning": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_blight": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_blight": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_ice_storm": {"files": ["spell_cast_frost.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_ice_storm": {"files": ["spell_impact_frost.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_flame_strike": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_flame_strike": {"files": ["spell_impact_flames.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_mass_cure_wounds": {"files": ["heal.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_mass_cure_wounds": {"files": ["heal.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_divine_spark": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_divine_spark": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_divine_spark_heal": {"files": ["heal.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_divine_spark_heal": {"files": ["heal.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_turn_undead": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_turn_undead": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_abjure_foes": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_abjure_foes": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_lay_on_hands": {"files": ["heal.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_lay_on_hands": {"files": ["heal.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_wild_shape": {"files": ["spell_cast.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_wild_shape": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_revert_wild_shape": {"files": ["spell_cast.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_revert_wild_shape": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	# Ranger (class kits) reuses existing files until it gets its own.
	"spell_cast_hunters_mark": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_hunters_mark": {"files": ["spell_impact.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_cast_toll_the_dead": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_toll_the_dead": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_word_of_radiance": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_word_of_radiance": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_thorn_whip": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_thorn_whip": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_bane": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_bane": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_command": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_command": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_heroism": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_heroism": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_protection_from_evil_and_good": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_protection_from_evil_and_good": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_ice_knife": {"files": ["spell_cast_frost.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_ice_knife": {"files": ["spell_impact_frost.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_searing_smite": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_searing_smite": {"files": ["spell_impact_fire.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_thunderous_smite": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_thunderous_smite": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_wrathful_smite": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_wrathful_smite": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_compelled_duel": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_compelled_duel": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_spiritual_weapon": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_spiritual_weapon": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_spiritual_weapon_strike": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_spiritual_weapon_strike": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_prayer_of_healing": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_prayer_of_healing": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_blindness_deafness": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_blindness_deafness": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_moonbeam": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_moonbeam": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_flame_blade": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_flame_blade": {"files": ["spell_impact_fire.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_flame_blade_strike": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_flame_blade_strike": {"files": ["spell_impact_fire.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_heat_metal": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_heat_metal": {"files": ["spell_impact_fire.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_heat_metal_repeat": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_heat_metal_repeat": {"files": ["spell_impact_fire.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_shining_smite": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_shining_smite": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_magic_weapon": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_magic_weapon": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_silence": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_silence": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_beacon_of_hope": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_beacon_of_hope": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_bestow_curse": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_bestow_curse": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_dispel_magic": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_dispel_magic": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_sleet_storm": {"files": ["spell_cast_frost.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_sleet_storm": {"files": ["spell_impact_frost.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_blinding_smite": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_blinding_smite": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_crusaders_mantle": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_crusaders_mantle": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_aura_of_vitality": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_aura_of_vitality": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_aura_of_vitality_heal": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_aura_of_vitality_heal": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_elemental_weapon": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_elemental_weapon": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_banishment": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_banishment": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_death_ward": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_death_ward": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_stoneskin": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_stoneskin": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_greater_restoration": {"files": ["spell_shield.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_greater_restoration": {"files": ["spell_shield.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_insect_plague": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_insect_plague": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_contagion": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_contagion": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_wrath_of_nature": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_wrath_of_nature": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_eldritch_blast": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_eldritch_blast": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_vicious_mockery": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_vicious_mockery": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_shocking_grasp": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_shocking_grasp": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_chill_touch": {"files": ["spell_cast_frost.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_chill_touch": {"files": ["spell_impact_frost.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_dissonant_whispers": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_dissonant_whispers": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_thunderwave": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_thunderwave": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_hex": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_hex": {"files": ["spell_impact.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_arms_of_hadar": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_arms_of_hadar": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_scorching_ray": {"files": ["spell_cast_fire.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_scorching_ray": {"files": ["spell_impact_fire.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_lightning_bolt": {"files": ["spell_cast_arcane.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_lightning_bolt": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_phantasmal_killer": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_phantasmal_killer": {"files": ["spell_impact_arcane.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_cone_of_cold": {"files": ["spell_cast_frost.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_cone_of_cold": {"files": ["spell_impact_frost.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_hold_monster": {"files": ["spell_cast_sleep.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_hold_monster": {"files": ["spell_impact_sleep.ogg"], "volume_db": -6.0, "bus": "Effects"},
	"spell_cast_bardic_inspiration": {"files": ["heal.ogg"], "volume_db": -8.0, "bus": "Effects"},
	"spell_impact_bardic_inspiration": {"files": ["heal.ogg"], "volume_db": -6.0, "bus": "Effects"},
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
