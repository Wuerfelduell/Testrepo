# Codex prompt 01b - Test: build one enemy and two weapons yourself

Written by: Claude (coordinator), 06-10-2026
Status: ready - runs IN PARALLEL with prompt 03 (different files)

---

You are working on the repo Wuerfelduell/Testrepo. Before you start:
- Read RULESET.md and follow it strictly: work directly on main, `git pull` before you start,
  commit + push when you are done, log your task in today's handover file in handover/.
- Read docs/DESIGN.md, assets/README.md and the newest file in handover/.
- If anything is unclear, STOP and write the question into "Open questions for the owner" in
  today's handover file instead of guessing (RULE 7).

## Why this test
Prompt 01 showed that the free asset packs have no enemies, no weapons and no class armour
(open question Q30). Before the owner spends money, we test whether you can build what is
missing yourself from what is already in the repo, in the SAME style and quality. The owner
looks at the result and decides. An honest "this does not look good enough" is a valid result.

## File ownership (RULE 6)
Another Codex session works on prompt 03 at the same time. You may ONLY change:
`assets/`, `scenes/showcase/`, `src/showcase/`, `tools/`, `docs/` (screenshots only) and
today's handover file (append only). Do NOT touch project.godot, src/rules/, data/classes/,
tests/unit/rules/, src/core/, src/commands/. Before every push: `git pull --rebase`; on a
handover conflict keep both entries.

## Tasks
1. **Check the free outfit pack again.** The itch.io page of "Modular Character Outfits -
   Fantasy" (https://quaternius.itch.io/modular-character-outfits-fantasy) says the free
   standard version contains 12 outfits with 62 modular parts. You only found peasant and
   ranger. Find out which is true and write the exact list into assets/README.md. If more
   outfits are free, add the ones that fit classes (e.g. knight, wizard, cleric) to the
   showcase.
2. **One humanoid enemy: "Undead Cultist".** Build it ONLY from the existing base bodies,
   outfits and textures (Blender scripted via Python, or in Godot):
   - same skeleton as the heroes, so all 42 existing animations work without retargeting
   - new look: hooded/ragged robe from existing outfit parts, decayed grey-green skin
     (texture/material work), glowing eyes (emissive), optional bone or rope details
   - must read as an enemy from the isometric camera at normal zoom
3. **Two weapons: a sword and an axe**, modelled with a Blender Python script, textured to
   match the dungeon (PBR: albedo, normal, roughness/metal), max ~1500 triangles each.
   Attach them to the hand bone so they move with `Sword_Attack` and the other animations.
   Give the cultist the axe and one hero model the sword.
4. **Showcase:** add the cultist and both weapons to the showcase scene, next to the existing
   models, with the same lighting. Save screenshots (normal zoom and close-up) to
   `docs/enemy-test-*.png`.
5. **Honest assessment** in the handover: how close is it to the quality of the hero models,
   what looks weak, how long would 3 more humanoid enemies + 1 boss take this way, and which
   things (non-humanoid monsters, class armour) you think cannot be done well this way.

## Do not
- No purchases, no new downloads of paid content, no AI-generated models.
- Do not overwrite or rename the existing models.

## Done when
- Cultist and weapons are visible and animated in the showcase without errors.
- Screenshots are in docs/, assessment is in the handover, assets/README.md is updated.
- Committed, pushed to main, logged.
