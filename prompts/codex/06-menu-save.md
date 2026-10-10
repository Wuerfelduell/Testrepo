# Codex prompt 06 - Main menu, character creation, ironman save, death screen (M1)

Written by: Claude (coordinator), 10-10-2026
Status: ready - runs IN PARALLEL with 05 and 07

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
Turn the arena prototype into something that starts like a real game: main menu, hero
creation like in Baldur's Gate 3 (simplified for M1), permadeath with an ironman save.

## Tasks
1. **Main menu** (`scenes/menu/main_menu.tscn`, becomes the main scene in project.godot):
   NEW GAME, CONTINUE (only when an ironman save exists), OPTIONS, QUIT. Atmospheric
   background: a slow camera move through the existing dungeon kit with torchlight.
2. **Character creation** exactly as docs/UI.md section 5: class (Fighter, Wizard; show the
   other 10 classes greyed out as "coming later"), body M/F, look variants from the available
   human models (prompt 07 adds Fighter/Wizard looks in parallel and lists them in
   assets/characters/hero_looks.json - read that file if it exists, otherwise use the current
   models; the menu must pick up new looks without code changes), name, rotatable 3D preview with idle animation, class description and key
   stats. Ability scores: SRD 5.2 standard array, auto-assigned by class priority for M1
   (point buy comes in M2), skills: class defaults. Builds a CharacterSheet.
3. **Start the run:** "Begin" shows the permadeath line from docs/UI.md, then loads the arena
   with the created hero instead of the hard-coded Fighter (a small, additive change in
   src/world/arena.gd / the setup command). Prompt 05 makes the Wizard castable in parallel;
   if the Wizard is chosen before 05 is merged, it simply fights without spells.
4. **Ironman save** (`src/core/save_game.gd`): one slot in `user://`. Saves the whole
   GameState through its existing serialisation (add a version number) only when quitting to
   menu or closing the game. CONTINUE loads it. On death the save is deleted. A corrupt or
   newer-version save shows a clear message instead of crashing.
5. **Death screen** as docs/UI.md section 6, replacing the current "leave arena" path.
6. **Options** as docs/UI.md section 7 (resolution, fullscreen, volumes, dice popup speed,
   camera rotation speed), stored in `user://settings.cfg`, applied immediately.
7. **Victory:** when all enemies are dead, a short "Area cleared" banner, XP awarded through
   CharacterSheet.grant_xp with the reason shown, then back to exploration.
8. **Tests:** save/load round trip of a running combat, delete on death, version mismatch,
   settings persistence; integration check: menu -> creation -> arena -> death -> menu.

## Done when
- The Windows .exe starts in the main menu and the full loop works.
- Tests and CI green, CI screenshots of menu, creation and death screen in docs/.
- Committed, pushed, logged.
