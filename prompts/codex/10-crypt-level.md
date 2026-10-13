# Package 10 - Crypt level with several encounters, real hero model, real portraits

Written by: Claude (coordinator), 13-10-2026
Status: ready - runs IN PARALLEL with 08, 09, 11 (Claude threads)

---

You are working on the repo Wuerfelduell/Testrepo (game title: Overcity). Before you start:
- Read RULESET.md and follow it strictly: work directly on main, `git pull` before you start,
  commit + push when you are done, log your task in today's handover file in handover/
  (create it with the HANDOVER FORMAT if it does not exist yet; append only).
- Read docs/DESIGN.md, docs/UI.md, docs/COMBAT.md, src/rules/README.md, assets/README.md and the
  newest handover file.
- RULE 7: if anything is unclear, ask instead of guessing (open question in today's handover
  and a short question to the owner). Owner rule: on a block, retry at most once, then tell the
  owner what is wrong.
- Keep the architecture: state changes only through commands on CommandBus, rules stay pure in
  src/rules/ with an injected RandomNumberGenerator, all visible text through translation keys,
  SRD 5.2 only for rules.
- Quality bar as before: tests for new logic, CI green (tests + Windows export/start), real CI
  screenshots for anything visible, honest list of what is provisional.
- Asset guideline: the whole assets/ folder stays below 100 MB (currently ~67 MB). Normal Git, no LFS.

## Four threads run at the same time (RULE 6)
Packages 08-11 run in parallel. Each owns its files. You may only change files you own plus
the shared files below. Never reformat or reorder code you do not own.

| Package | Owns |
|---|---|
| 08 Level-up and rests | src/rules/progression*.gd, src/rules/rest*.gd, src/rules/features/, data/classes/, src/commands/level_up_*, src/commands/*rest*, src/ui/levelup/, src/ui/rest/, tests/unit/progression/, tests/unit/rest/ |
| 09 Loot and carry weight | src/rules/items/, data/items/, src/commands/loot_*, src/commands/drop_*, src/commands/inventory_command.gd, src/ui/inventory/, src/world/loot/, tests/unit/items/ |
| 10 Crypt level, hero model, portraits | scenes/levels/, src/world/level*.gd, src/world/encounter*.gd, data/encounters/, src/world/combat_actor.gd, src/ui/combat_hud.gd, src/ui/portraits/, data/monsters/, tests/integration/check_level* |
| 11 Music and sound | src/audio/, assets/audio/, default_bus_layout.tres, src/ui/menu/options*.gd (volume wiring only), tests/unit/audio/ |

Shared (small, additive edits only; `git pull --rebase` before every push and keep BOTH sides on
a conflict; run the full test suite after every rebase): project.godot (autoloads/settings
lines only), src/core/game_state.gd, src/core/event_bus.gd (new signals only),
src/world/arena.gd, src/commands/command_codec.gd, localization/strings.csv (append rows only;
if the generated .translation conflicts, take theirs and re-import), README.md, CREDITS.md,
assets/CREDITS.md (append only), today's handover (append only).

## Goal
Right now there is one arena and one fight, the hero in the arena still uses the old base body,
and the HUD portraits show old faces. Build the first real level: the crypt from docs/DESIGN.md
M1 (the first ~6 minutes of act 1). The story is not decided yet, so the level is story-neutral:
rooms, encounters and dialogue *hooks* only, no story text.

## Tasks
1. **Crypt level** `scenes/levels/crypt/`: 4-6 connected rooms built from the dungeon kit
   (entrance, corridor with a trap, side chamber, ossuary, shrine room with the boss), with
   height, cover and narrow passages in every combat room. Main scene flow: menu -> character
   creation -> crypt (instead of the arena; keep the arena reachable as a debug option).
2. **Encounters as data** `data/encounters/`: 3 fights of rising difficulty using the three
   enemy types, plus the **Cult Priest boss** (give it an SRD 5.2 stat block - pick the closest
   SRD creature and say which). Enemies start in exploration poses (patrol, guarding, sleeping)
   and use the existing perception/initiative flow. Surviving enemies of a nearby room may join.
3. **Long-rest point:** one safe spot before the boss that calls the long-rest command from
   package 08 (if it is not merged yet, place the trigger and leave a TODO in the handover).
4. **Dialogue hooks:** 2-3 marked places (e.g. a wounded cultist, a locked cell with a
   prisoner, an inscription) with an interaction trigger that opens a placeholder line
   "Dialogue: <id>" - the real dialogue system and texts come later from the owner and Claude.
5. **Real hero model:** the hero in levels and arena uses the look chosen in character creation
   (assets/characters/hero_looks.json), not the old base body. Weapons from the equipped item.
6. **Real portraits:** HUD and initiative portraits are rendered from the actual 3D models
   (SubViewport snapshot of the head, cached), for heroes and every enemy type. No old faces.
7. **Camera and performance:** camera works in narrow rooms (walls between camera and hero fade
   or cut away like BG3); keep 60 FPS target on mid hardware, note the CI measurement.
8. **Tests:** integration check that walks the level start to boss with deterministic seeds,
   encounter spawn data validity, portrait generation for every model.

## Done when
- The crypt is playable from start to boss with 3 fights + boss, real hero model and portraits.
- Tests and CI green, CI screenshots of every room and of the HUD portraits in docs/.
- Committed, pushed, logged.
