# Package 08 - Level-up and rests

Written by: Claude (coordinator), 13-10-2026
Status: ready - runs IN PARALLEL with 09, 10, 11 (Claude threads)

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
Levelling currently only counts XP (old problem: "bad level system"). Make levelling up a real
moment with real choices, and add resting, which several level-1 features already depend on.

## Tasks
1. **Level-up flow** for Fighter and Wizard, levels 2-10 (SRD 5.2): when XP crosses a threshold
   the hero gets a "Level up" button (not forced mid-combat). The level-up screen
   (`src/ui/levelup/`) shows what is gained (HP: roll the hit die with the 3D d20 popup or take
   the average, proficiency bonus, new features) and asks for every real choice: Ability Score
   Improvement or feat at level 4/8, Wizard new spells into the spellbook, Fighter Fighting Style.
2. **Fighter Fighting Style:** the owner chose **Great Weapon Fighting** (answer to Q34). Implement
   it in the rules and give the level-1 test Fighter a fitting two-handed weapon option.
3. **Feature logic** for Fighter and Wizard features up to level 5 (e.g. Action Surge, Extra
   Attack, Wizard spell slots per level, level 2/3 spells). Feature names from data/classes/,
   numbers from SRD 5.2. Anything beyond level 5 stays data only and is listed as such.
4. **Short rest:** spend Hit Dice to heal (roll shown in the dice popup), recharge short-rest
   features (Second Wind, Action Surge), Wizard Arcane Recovery. Only outside combat; enemies
   nearby block it. **Long rest:** full HP, slots and half Hit Dice; for now only at fixed rest
   points (package 10 places one in the crypt; expose a command it can call).
5. **Commands** for every state change (LevelUpCommand with all choices, ShortRestCommand,
   LongRestCommand), with JSON codec entries and validation.
6. **Tests:** threshold crossing, HP gain (roll/average), ASI caps at 20, spell selection
   rules, GWF reroll of 1s and 2s, rest recharge, rest blocked near enemies, save/load keeps the
   level-up choices.

## Done when
- A Fighter and a Wizard can be levelled from 1 to 5 with every choice, and rest works.
- Tests and CI green, CI screenshots of the level-up screen in docs/.
- Committed, pushed, logged.
