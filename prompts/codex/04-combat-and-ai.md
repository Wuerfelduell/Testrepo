# Codex prompt 04 - Combat system and enemy AI (milestone M1)

Written by: Claude (coordinator), 05-10-2026
Status: send AFTER prompts 02 AND 03 are both finished and pushed

---

You are working on the repo Wuerfelduell/Testrepo. Before you start:
- Read RULESET.md and follow it strictly: work directly on main, `git pull` before you start,
  commit + push when you are done, log your task in today's handover file in handover/
  (format at the end of RULESET.md).
- Read docs/DESIGN.md (the design document) and the newest file in handover/.
- If anything is unclear, STOP and write the question into "Open questions for the owner" in
  today's handover file instead of guessing (RULE 7).
- Engine: Godot 4 (latest stable 4.x), GDScript with static typing everywhere.
- All player-visible text goes through translation keys (`tr("KEY")`) in
  `localization/strings.csv` (English column first). No hard-coded UI strings.

## Goal
Turn-based combat with free movement like Baldur's Gate 3, on a test arena, using the assets
from prompt 01, the commands from prompt 02 and the rules from prompt 03. This is the part
that failed hardest in the old project (dumb AI, no animations, dice only in a log), so
quality matters more than speed here.

## Tasks
1. **Test arena** `scenes/arena/arena.tscn`: a dungeon room built from the asset kit, with
   different heights (a raised platform, stairs), cover (pillars, crates) and narrow
   passages. Lit like the showcase scene. Navigation mesh baked from the level.
2. **Camera:** isometric, rotate, zoom, pan, follows the active character, short focus on
   the target when an attack happens.
3. **Combat flow:** combat starts when an enemy sees the player (line of sight + range),
   initiative is rolled and shown as a portrait bar at the top. Exploration and combat
   modes switch cleanly.
4. **Commands** (all through CommandBus): `MoveCommand` (free movement along the navmesh,
   cost = path length in metres), `AttackCommand` (melee and ranged), `DashCommand`,
   `DisengageCommand`, `EndTurnCommand`. Opportunity attacks when leaving melee reach.
   Height advantage: attacker clearly higher than target gets advantage on ranged attacks.
   Cover: half cover +2 AC, three-quarters cover +5 AC (raycasts against cover objects).
5. **Player input:** hovering the ground shows the path and the remaining movement
   (green = reachable, red = not). Hovering an enemy shows hit chance in % and the damage
   dice. Click to move / attack, right click or Esc to cancel.
6. **Dice presentation:** every roll pops up on screen with the die result, each modifier
   with its source and the total vs. AC/DC; advantage shows both dice with the dropped one
   greyed out. Crits and fumbles get a stronger effect. Combat log on the side.
7. **Animations:** use the animation clips from the asset set: idle, walk/run while moving,
   attack synced with the hit (damage applies on the hit frame, not instantly), hit
   reaction, death. Floating damage numbers. No T-poses, no sliding.
8. **Enemy AI (utility AI)** in `src/world/ai/`: for each possible action (attack each target,
   move to cover, move to high ground, flank, dash, retreat when low HP) compute a score
   from: hit chance, expected damage, chance to kill, own danger after the move (how many
   enemies can reach it), cover and height. Pick the best. Each enemy type has a personality
   resource with weights (e.g. brute: aggressive; archer: keeps distance and seeks height;
   coward: flees below 30% HP). AI uses ONLY commands through CommandBus - it cannot cheat.
   Add a debug overlay (toggle F3) that shows the scores of the options considered.
9. **Three enemy types** using the enemy models from prompt 01, stats from SRD 5.2 monsters
   (e.g. skeleton, zombie, a ranged enemy). One hero: a level 1 Fighter built with
   CharacterSheet from prompt 03.
10. **Win / lose:** all enemies dead -> back to exploration. Hero at 0 HP -> death screen,
    run is over (permadeath, docs/DESIGN.md).
11. **Tests:** unit tests for movement cost, opportunity attacks, cover and height bonuses,
    and the AI choosing the obvious best option in fixed test situations (e.g. finishes off
    a target at 1 HP, a ranged enemy steps back instead of standing next to the hero).

## Do not
- No spells, no character creation, no inventory, no dialogue yet.
- No game rules inside scene scripts: rules stay in src/rules, state changes only via commands.

## Done when
- A full fight in the arena runs with no errors, all characters animated, every roll visible.
- The AI visibly uses cover and height and does not walk into obviously bad positions.
- Tests pass headless and in GitHub Actions.
- Committed, pushed to main, logged in today's handover file.
