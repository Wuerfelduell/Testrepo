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
