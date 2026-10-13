# Asset credits

All included third-party models and textures are from the free packages listed
below. No assets from the previous RPG repository, no purchased files and no
AI-generated models are included.

| Included files | Author | Source | Licence evidence |
|---|---|---|---|
| `characters/superhero_*`, related skin, eye and eyebrow textures | Quaternius | [Universal Base Characters](https://quaternius.itch.io/universal-base-characters) | CC0 1.0, original `License_Standard.txt` copied to `licenses/quaternius_base.txt` |
| `characters/*_peasant`, `characters/*_ranger`, clothing textures | Quaternius | [Modular Character Outfits – Fantasy](https://quaternius.itch.io/modular-character-outfits-fantasy) | CC0 1.0, original `License_Standard.txt` copied to `licenses/quaternius_outfits.txt` |
| `animations/universal.glb` | Quaternius; pack page also thanks animator Gonzalo Furnier | [Universal Animation Library](https://quaternius.itch.io/universal-animation-library) | CC0 1.0, original `License.txt` copied to `licenses/quaternius_animations.txt` |
| `dungeon/SM_*.glb`, `dungeon/textures/*` | Omie's Assets | [Free 3D Modular Dungeon Kit](https://omies-assets.itch.io/dungeonkit) | CC0 declared on the author's page for the free 17-piece demo; source note in `licenses/omies_source.txt` |

CC0 licence: <https://creativecommons.org/publicdomain/zero/1.0/>.

The Quaternius general website licence now differs from its pack pages. For the
included files, the downloaded archives themselves explicitly declare CC0 1.0;
their original licence files are preserved above. No claim is made that all future
Quaternius releases share that licence. `source_archives.json` records the hashes
of the exact archives inspected on 05 October 2026.

Adaptations: character glTF files converted to GLB, broken texture filenames
resolved from supplied PNGs, duplicate textures shared, large clothing maps reduced
to at most 1K; free dungeon FBX geometry converted with Godot to GLB, actual supplied
TGA maps converted to 512px PNGs, Unity metallic/smoothness channels converted to glTF
metallic/roughness. The geometry remains the authors' work.

The showcase scripts, camera, lighting and runtime animation retargeting are project
code. These are not third-party assets. Rules/SRD content is not included in this task.

### Adaptations for the enemy test (06 October 2026)

`characters/undead_cultist/` adapts the existing Quaternius Male Ranger parts and
the head/eyes of Superhero Male. Original source authors and pack-specific CC0
licence evidence remain as listed above. The source models are unchanged. Robe
deformation, compact derived albedo maps and eye emission are project adaptations.

`weapons/sword.glb` and `weapons/axe.glb` are project geometry, modelled procedurally
with Blender Python (`tools/build_enemy_test.py`), not AI-generated models.
Their material variations derive from Omie's existing CC0 dungeon props albedo;
`tools/prepare_enemy_textures.py` deterministically creates albedo, normal and ORM
maps. Neither generator requires new third-party geometry or textures.

### Adaptations for M1 art (10 October 2026, prompt 07)

`characters/enemy_*`, `characters/boss_cult_priest`, `characters/hero_*` adapt the
existing Quaternius Male/Female Ranger and Male Peasant parts and the heads/eyes of
Superhero Male/Female (CC0, licence evidence above). Helmets, plates, masks, horns,
cloaks, belts and the quiver are project geometry built by `tools/build_m1_art.py`.
Their derived albedo maps (`characters/m1_textures/`) come from the same CC0 textures
and Omie's CC0 dungeon props via `tools/prepare_m1_textures.py`.
The new weapons (dagger, scimitar, sickle, mace, spear, staff, priest staff, shortbow,
light crossbow, two shields) are project geometry from the same generator, not AI-generated.
Hit effects are procedural Godot particles (project code). No new third-party content.

### Audio (13 October 2026, package 11)

All sounds and music in `audio/` are CC0 (public domain) and were downloaded from the pages below.
`tools/build_audio.py` downloads the packs, cuts, mixes and loudness-normalises the clips and writes
OGG Vorbis files; several effects are layers of two CC0 clips (for example the bow shot, critical hit,
Shield and level-up), the drips are cut from one drip recording and the boss whispers are a ghostly
drone with whispered syllables and echoes placed over it. Credit is not required by CC0 but given here.

| Source | Author | Licence | Used for |
|---|---|---|---|
| https://kenney.nl/assets/rpg-audio | Kenney | CC0 | `sfx/hit_piercing_1`, `sfx/hit_piercing_2`, `sfx/loot_pickup_1`, `sfx/loot_pickup_2` |
| https://kenney.nl/assets/impact-sounds | Kenney | CC0 | `sfx/bow_shot_1`, `sfx/bow_shot_2`, `sfx/critical`, `sfx/footstep_stone_1`, `sfx/footstep_stone_2`, +9 more |
| https://kenney.nl/assets/interface-sounds | Kenney | CC0 | `sfx/ui_click_1`, `sfx/ui_click_2` |
| https://kenney.nl/assets/casino-audio | Kenney | CC0 | `sfx/dice_land_1`, `sfx/dice_land_2`, `sfx/dice_roll_1`, `sfx/dice_roll_2` |
| https://kenney.nl/assets/music-jingles | Kenney | CC0 | `sfx/dice_crit`, `sfx/dice_fumble`, `sfx/level_up` |
| https://opengameart.org/content/80-cc0-rpg-sfx | rubberduck | CC0 | `sfx/death_1`, `sfx/hit_fire`, `sfx/hit_slashing_1`, `sfx/hit_slashing_2`, `sfx/spell_cast`, +4 more |
| https://opengameart.org/content/80-cc0-creature-sfx | rubberduck | CC0 | `sfx/death_2` |
| https://opengameart.org/content/40-cc0-water-splash-slime-sfx | rubberduck | CC0 | `sfx/footstep_water_1`, `sfx/footstep_water_2`, `sfx/footstep_water_3` |
| https://opengameart.org/content/rpg-sound-pack | artisticdude | CC0 | `sfx/hit_force`, `sfx/spell_cast_arcane`, `sfx/swing_1`, `sfx/swing_2`, `sfx/swing_3` |
| https://opengameart.org/content/swishes-sound-pack | artisticdude | CC0 | `sfx/bow_shot_1`, `sfx/bow_shot_2`, `sfx/miss_1`, `sfx/miss_2` |
| https://opengameart.org/content/freeze-spell-0 | artisticdude | CC0 | `sfx/spell_cast_frost` |
| https://opengameart.org/content/ice-spells | bart | CC0 | `sfx/hit_cold`, `sfx/spell_impact_frost` |
| https://opengameart.org/content/cure-magic | someoneman | CC0 | `sfx/heal`, `sfx/level_up`, `sfx/spell_cast_sleep` |
| https://opengameart.org/content/3-dark-magic-spells | qubodup | CC0 | `sfx/spell_impact_arcane` |
| https://opengameart.org/content/ghost-breath | qubodup | CC0 | `sfx/spell_impact_sleep` |
| https://opengameart.org/content/4-atmospheric-ghostly-loops | qubodup (Independent.nu) | CC0 | `ambience/whispers` |
| https://opengameart.org/content/dripping-water-loop | qubodup | CC0 | `ambience/drip_1-3` |
| https://opengameart.org/content/fantozzis-footsteps-grasssand-stone | Fantozzi, uploaded by qubodup | CC0 | `sfx/footstep_dirt_1`, `sfx/footstep_dirt_2`, `sfx/footstep_dirt_3`, `sfx/footstep_dirt_4` |
| https://opengameart.org/content/loopable-dungeon-ambience | jaggedstone | CC0 | `ambience/room_tone` |
| https://opengameart.org/content/dialog-vocal-samples | mirceakitsune | CC0 | `ambience/whispers` |
| https://opengameart.org/content/fantasy-lament-for-a-warriors-soul | randommind | CC0 | `music/menu` |
| https://opengameart.org/content/dungeon-ambience | yd | CC0 | `music/exploration` |
| https://opengameart.org/content/battle-theme-a | cynicmusic | CC0 | `music/combat` |
| https://opengameart.org/content/determined-pursuit-epic-orchestra-loop | emmama | CC0 | `music/boss` |
| https://opengameart.org/content/medieval-victory-theme | randommind | CC0 | `music/victory` |
| https://opengameart.org/content/medieval-defeat-theme | randommind | CC0 | `music/death` |
