# Codex prompt 05 - Wizard, spells and level-1 class features (milestone M1)

Written by: Claude (coordinator), 10-10-2026
Status: ready - runs IN PARALLEL with 06 and 07

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
The first slice offers two heroes: Fighter and Wizard (docs/DESIGN.md, M1). The Fighter
exists; class features are not active yet and the Wizard cannot cast. Make both classes play
like they should at level 1, using SRD 5.2 only.

## Tasks
1. **Spell rules** in `src/rules/spells/` (pure): spell data model (level, school, casting
   time, range in metres, area shape, attack roll or saving throw, damage dice, scaling),
   spell slots, spell attack bonus and save DC from the casting ability, cantrips,
   concentration (break on damage via CON save), reaction spells.
2. **Spells as data** in `data/spells/` from SRD 5.2: cantrips Fire Bolt, Ray of Frost;
   level 1 Magic Missile, Burning Hands, Shield, Sleep. If one of them is not in the SRD 5.2,
   pick an SRD alternative and say so in the handover.
3. **Commands:** `CastSpellCommand` (validates slot, range, line of sight, target or area),
   reaction hook for Shield (offered when the Wizard is hit, before damage), JSON codec.
4. **Level-1 class features as commands:** Fighter Second Wind (bonus action heal) and
   Fighter Weapon Mastery for the equipped weapon; Wizard Arcane Recovery on rest (data only
   until rests exist). Use the FEATURE_* keys from data/classes/.
5. **Targeting** (`src/world/spell_targeting.gd`): area templates on the ground (cone, sphere,
   line), affected characters highlighted, hit chance or "DC 13 DEX save" shown before casting,
   as described in docs/UI.md section 3.
6. **HUD:** spell buttons in the hotbar with slot pips, greyed out with a reason when not
   possible; the dice popup shows saving throws (target rolls vs. DC) the same way as attacks.
7. **Spell effects** in `src/world/vfx/spells/`: projectile for Fire Bolt / Ray of Frost,
   three darts for Magic Missile, cone of fire for Burning Hands, shield shimmer, sleep mist.
   Damage applies when the effect hits, not at cast time. Use the existing cast clip.
8. **AI:** extend the utility AI so a spellcaster enemy (e.g. the Cultist, if its SRD stat
   block has spells) scores spell options too, including "don't hit allies with areas".
9. **Arena test switch:** a debug key (F4) swaps the arena hero between Fighter and Wizard,
   until prompt 06 delivers character creation.
10. **Tests:** slot spending, save DC math, area targeting (who is inside a cone), Shield
    timing, concentration breaking, Magic Missile auto-hit, AI not burning its allies.

## Done when
- Wizard and Fighter are both fully playable in the arena with their level-1 options.
- Tests and CI green, CI screenshots of a spell being targeted and cast in docs/.
- Committed, pushed, logged.
