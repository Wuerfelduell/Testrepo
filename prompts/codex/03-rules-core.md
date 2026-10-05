# Codex prompt 03 - Rules core (milestone M0/M1)

Written by: Claude (coordinator), 05-10-2026
Status: ready - runs IN PARALLEL with track A (prompts 01 -> 02) in a second Codex session

## Parallel work - file ownership (RULE 6)
This prompt runs at the same time as another Codex session doing prompts 01 and 02.
To avoid collisions you may ONLY create or change files in:
- `src/rules/`
- `data/classes/`
- `tests/unit/rules/`
- today's handover file (append only)
Do NOT touch project.godot, README.md, CREDITS.md, addons/, assets/, scenes/ or any other
folder - they belong to the other session. Before every push: `git pull --rebase`; if the
handover file conflicts, keep both entries.

---

You are working on the repo Wuerfelduell/Testrepo. Before you start:
- Read RULESET.md and follow it strictly: work directly on main, `git pull` before you start,
  commit + push when you are done, log your task in today's handover file in handover/
  (format at the end of RULESET.md).
- Read docs/DESIGN.md (the design document) and the newest file in handover/.
- If anything is unclear, STOP and write the question into "Open questions for the owner" in
  today's handover file instead of guessing (RULE 7).
- Engine: Godot 4 (latest stable 4.x), GDScript with static typing everywhere.
- The project (project.godot, GUT test framework, autoloads) may not exist yet - the other
  session creates it. Your code must not depend on it.
- Rules code produces no player-visible text; it returns data (the UI translates later).

## Goal
The D&D 5.5e rules as pure, fully tested logic in `src/rules/`. No Nodes, no scenes, no UI.
Every result object must keep enough detail that the UI can later show exactly how a roll
came about (pillar 1 in docs/DESIGN.md: "Dice are the heart").

## Legal (important)
Use ONLY the System Reference Document 5.2 (SRD 5.2, CC-BY-4.0) as the source for rules,
numbers and class features. Do not copy text from the Player's Handbook or Baldur's Gate 3.
Write the SRD 5.2 attribution into `src/rules/SRD_ATTRIBUTION.md` (the other session merges it
into CREDITS.md later).

## Tasks
1. **Dice:** parse and roll expressions like `1d20+5`, `2d6+3`, `8d6`. Result keeps every
   single die, every modifier with its source (e.g. "+3 STR", "+2 proficiency"), the total,
   and flags for natural 20 / natural 1. Advantage and disadvantage roll two d20 and keep both
   values (the UI shows both dice). Randomness: every rules function that rolls takes a `RandomNumberGenerator` parameter (no
   autoloads, no global state) - the game passes in its seeded one later.
2. **Abilities and checks:** six abilities and modifiers, proficiency bonus by level (1-10),
   the 18 skills, ability checks, skill checks and saving throws against a DC.
3. **Attacks and damage:** attack roll vs. AC (crit on natural 20 = double damage dice,
   natural 1 always misses), damage types, resistance, vulnerability, immunity.
4. **Conditions:** data model and effects for blinded, frightened, poisoned, prone,
   restrained, stunned, unconscious (effects on advantage/disadvantage, speed, actions).
5. **Turn economy:** action, bonus action, reaction, movement budget in metres
   (5e feet x 0.3, so 30 ft = 9 m), reset per turn.
6. **Initiative:** d20 + DEX, ties broken by DEX then by Rng, returns an ordered list.
7. **Classes:** data (`.tres` resources in `data/classes/`) for ALL 12 classes from the SRD 5.2:
   hit die, primary ability, saving throw proficiencies, armor/weapon proficiencies, skill
   choices, and the class feature list for levels 1-10 (names + level only for now; feature
   logic comes later). No subclasses.
8. **Character:** a `CharacterSheet` (RefCounted) built from class + level + ability scores
   (human only): HP (max hit die at level 1, then average), AC from armor, proficiencies,
   derived numbers.
9. **XP and levels:** SRD XP table up to level 10 (level cap). `grant_xp(amount, reason)` -
   the reason string is kept, because XP comes from decisions as well as kills (see design doc).
10. **Unit tests** in `tests/unit/rules/`, written for GUT (Godot Unit Test, `extends GutTest`),
    for every item above with fixed seeds, including edge cases (advantage +
    disadvantage cancel out, crit damage, resistance halves rounding down, level-up at
    exact XP threshold).

## Do not
- No spells yet (separate prompt later), no scenes, no UI, no AI.
- Do not invent rules. If the SRD is unclear on something, ask in the handover (RULE 7).

## Done when
- All 12 class resources exist and load.
- All tests pass. If the repo does not have GUT yet, run them in a temporary project OUTSIDE
  the repo (do not commit it) and say so in the handover.
- Committed, pushed to main, logged in today's handover file.
