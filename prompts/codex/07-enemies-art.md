# Codex prompt 07 - Enemies, boss, class looks, weapons and hit effects (M1 art)

Written by: Claude (coordinator), 10-10-2026
Status: ready - runs IN PARALLEL with 05 and 06

---

You are working on the repo Wuerfelduell/Testrepo. Before you start:
- Read RULESET.md and follow it strictly: work directly on main, `git pull` before you start,
  commit + push when you are done, log your task in today's handover file in handover/
  (create it with the HANDOVER FORMAT if it does not exist yet).
- Read docs/DESIGN.md, docs/UI.md, docs/COMBAT.md, src/rules/README.md and the newest
  handover file.
- If anything is unclear, STOP and write the question into "Open questions for the owner" in
  today's handover file instead of guessing (RULE 7).
- Keep the architecture: state changes only through commands on CommandBus, rules stay pure in
  src/rules/ with an injected RandomNumberGenerator, all visible text through translation keys.
- Same quality bar as prompt 04: tests for new logic, CI green (tests + Windows export/start),
  real screenshots from CI for anything visible, honest list of what is provisional.

## Three Codex sessions run at the same time (RULE 6)
Prompts 05, 06 and 07 run in parallel. Each owns its files (table below). You may only change
files you own, plus the shared files listed under "Shared". Never reformat or reorder code you
do not own.

| Prompt | Owns |
|---|---|
| 05 Wizard, spells, class features | src/rules/spells/, data/spells/, src/commands/cast_*, src/commands/use_feature_*, src/world/vfx/spells/, src/world/spell_targeting.gd, src/ui/combat_hud.gd, tests/unit/spells/, tests/unit/features/ |
| 06 Menu, character creation, save, death | project.godot, src/ui/menu/, scenes/menu/, src/core/save_game.gd, src/ui/death_screen.gd, src/ui/options*.gd, tests/unit/save/, tests/integration/check_menu* |
| 07 Enemies, armour, weapons, hit effects | assets/, tools/, src/showcase/, data/monsters/, src/world/combat_actor.gd, src/world/vfx/hits/, docs/*.png of its own |

Shared (small, additive edits only, then `git pull --rebase` and keep BOTH sides on conflicts):
src/core/game_state.gd, src/world/arena.gd, src/commands/command_codec.gd,
localization/strings.csv (append rows only; if strings.en.translation conflicts, take theirs and
re-import so it is regenerated from the merged CSV), README.md, CREDITS.md, today's handover
(append only). Run the full test suite after every rebase, before pushing.

## Goal
The 01b test showed that humanoid enemies built from our existing bodies and outfits on the
shared 65-bone rig work in the current style (docs/enemy-test-closeup.png). Use exactly that
method to close the art gaps of the first slice (open question Q30). No purchases, no
AI-generated models, no new downloads of paid content.

## Tasks
1. **Three distinct humanoid enemies** matching the SRD roles in data/monsters/: Guard,
   Bandit, Cultist. Each needs its own silhouette readable at normal isometric zoom (helmet vs.
   hood vs. bandana/mask, shield vs. dual blades vs. robe), own colours and materials, and
   fitting weapons. Not just recolours.
2. **One humanoid boss:** "Cult Priest" with a clearly bigger, more threatening silhouette
   (scale, horns/crown of bone, long staff, cloak), emissive details. Stats come later; the
   model goes into data/monsters/ as a visual-only entry for now.
3. **Hero looks:** a Fighter look (armour pieces built from existing parts plus scripted
   plates: pauldrons, breastplate, shield) and a Wizard look (long robe, hood/hat option,
   staff), each for male and female bodies. Prompt 06 offers these in character creation;
   put them in `assets/characters/` with a small manifest it can read
   (`assets/characters/hero_looks.json`: class, body, look id, scene path).
4. **Weapons** (Blender Python, same PBR approach as the sword/axe): shield, dagger, mace,
   spear, staff, shortbow, light crossbow. Bound to the hand bones; ranged enemies get a bow or
   crossbow so the provisional ranged gesture now holds a real weapon.
5. **Hit effects** in `src/world/vfx/hits/`: blood spray on hit (it is a violent game, RULE 5),
   sparks on a blocked/missed melee hit, a heavier effect on critical hits, dust on death.
6. **Wire it in:** the arena uses the three distinct enemy models instead of the shared test
   model (via data/monsters/ and src/world/combat_actor.gd).
7. **Showcase:** add every new model and weapon; CI screenshots at normal zoom and close-up.
8. **Honest assessment** in the handover, like in 01b: what looks good, what is weak, and what
   still cannot be done this way (non-humanoid monsters).

## Done when
- The arena shows three visually distinct enemies with fitting weapons and hit effects.
- Hero looks and the manifest exist for prompt 06.
- Assets stay below the size where Git LFS is needed, or LFS is set up and documented.
- Tests and CI green, screenshots in docs/, committed, pushed, logged.
