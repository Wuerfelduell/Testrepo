# Package 09 - Loot and carry weight

Written by: Claude (coordinator), 13-10-2026
Status: ready - runs IN PARALLEL with 08, 10, 11 (Claude threads)

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
The owner answered Q32: defeated enemies drop loot that you pick up, like in BG3, and carry
weight matters: too much weight slows you down.

## Tasks
1. **Loot drops:** when an enemy dies, its equipped weapon/armour and a loot table roll
   (gold, potions, small items) become a lootable container on its body (glowing outline on
   hover). Loot tables as data in `data/items/`, per monster role. Every roll through Rng.
2. **Loot window:** click the body (in range, outside combat or as a free interaction in
   combat - decide by SRD and say so) to open a loot window: take one, take all, compare with
   equipped item. Drag and drop into the existing inventory.
3. **Carry weight:** SRD 5.2 carrying capacity (Strength score x 15 lb, shown in kg and lb?
   - ask the owner which unit; default kg, 1 lb = 0.45 kg). Above the limit the hero is
   **slowed**: movement reduced (default: -3 m per turn, and -6 m above double; name the exact
   numbers in the handover as a project rule, since SRD 5.2 has no encumbrance variant). Show the
   weight bar in the inventory and a "Slowed" condition icon in the HUD.
4. **Drop and sell-ready:** drop items on the ground (they stay in the level as loot), item
   value in gold stored for a later merchant.
5. **Commands:** LootTakeCommand, LootTakeAllCommand, DropItemCommand; save/load keeps
   dropped items and looted bodies.
6. **Tests:** loot table determinism with a seed, weight limits and slowdown thresholds,
   taking/dropping keeps item counts consistent, save/load round trip.

## Done when
- Enemies in the arena drop loot, it can be taken and dropped, weight slows the hero.
- Tests and CI green, CI screenshots of the loot window and an overloaded inventory in docs/.
- Committed, pushed, logged.
