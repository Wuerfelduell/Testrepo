# Package 11 - Music and sound

Written by: Claude (coordinator), 13-10-2026
Status: ready - runs IN PARALLEL with 08, 09, 10 (Claude threads)

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

## RULE 11 first
Before you start, tell the owner in one short message: original music is best made with a music
AI (e.g. Suno or Udio) or by a composer; Claude cannot compose good music. Propose: Claude
builds the whole audio system now and uses free CC0/CC-BY music and sound effects (e.g. Kenney,
OpenGameArt, Sonniss GDC bundles if the licence allows), and the owner can replace the music
tracks later with his own (e.g. from Suno - check its licence for commercial use). Then wait for
the owner's answer (RULE 7) before downloading anything. The system work below can start
immediately because it needs no decision.

## Tasks
1. **Audio system** `src/audio/` (autoload): buses Master, Music, Effects, Ambience, UI with
   the volumes from the existing options menu; music player with crossfade between states
   (menu, exploration, combat, boss, victory, death); positional 3D sound for world events.
2. **Event hooks:** listen to EventBus / CommandBus signals only (no audio code inside rules or
   commands): footsteps by surface, weapon swings, hits by damage type, misses, critical hits,
   deaths, spells (cast + impact per spell), **the d20 rolling and landing** in the dice popup,
   UI clicks, level-up fanfare, loot pick-up.
3. **Sound set:** fitting CC0/CC-BY sounds and 4-6 music tracks for the states above (after the
   owner's answer). OGG Vorbis, sensible loudness (no clipping, music quieter than effects).
   Licences in assets/CREDITS.md. Keep audio below ~20 MB.
4. **Ambience:** dungeon room tone, dripping water, distant whispers near the boss (RULE 5:
   frightening is allowed).
5. **Tests:** every mapped event has a sound, buses exist and react to the options, music state
   changes on combat start/end, no audio errors in headless CI (use the dummy driver).

## Done when
- Menu, exploration, combat, dice and spells all have sound and music with smooth transitions.
- Tests and CI green, licences documented, a short list of what is provisional.
- Committed, pushed, logged.
