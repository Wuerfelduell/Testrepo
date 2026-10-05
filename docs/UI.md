# UI / UX concept

Written by: Claude (coordinator), 05-10-2026
Status: draft v1 for milestone M1. The owner decides; changes welcome.
Why this exists: in the old project the UI was "not thought through". Every screen is designed
here first, then built (docs/DESIGN.md, section 4).

---

## 1. Principles

1. **The player always knows the odds.** Before any action: hit chance, damage dice, what it
   costs (action / bonus action / movement). After any action: the full dice breakdown.
2. **Nothing important only in a log.** The log is for reading back, never the only place
   something is shown.
3. **Few clicks.** Hover shows, left click does, right click / Esc cancels. Always.
4. **Dark, readable style.** Dark stone/parchment panels, gold accents for player things, red for
   enemies, white text at least 16 px at 1080p. Everything scales with resolution.
5. **Every string is a translation key** (English first, German later).

## 2. Combat HUD (1920x1080)

```
+----------------------------------------------------------------------------------+
| [P1][E1][E2][P2][E3]   <- initiative bar, active one big + gold frame, round no.  |
|                                                                                  |
|                                                                [Combat log  ^]   |
|                                                                [ last 6 lines ]  |
|                                                                                  |
|                      (3D scene, isometric)                                       |
|                                                                                  |
|                                                                                  |
| [Portrait]  HP 24/30 [#########---]   Conditions: (icons)                        |
| [ Party  ]  AC 16                                                                |
|            [1 Atk][2 Atk][3 Dash][4 Disen.][5 ...] ... [Q item][E item]          |
|            Action (o)  Bonus (o)  Reaction (o)  Move [=======---] 6.0 / 9 m      |
|                                                                   [ END TURN ]   |
+----------------------------------------------------------------------------------+
```

- **Initiative bar (top centre):** portraits in turn order. Hover = name, HP, conditions.
  Dead ones fade out. Shows "Round 3".
- **Hotbar (bottom centre):** actions as icons with number keys 1-0. Greyed out if not
  possible, tooltip says why ("No action left", "Out of range").
- **Resources:** action, bonus action, reaction as filled/empty circles; movement as a bar
  with metres. Spell slots later appear as small pips next to it.
- **End turn:** big button, also Space. If the player still has an action left, the button
  glows softly (no blocking pop-up).
- **Party portraits (bottom left):** one per party member, click to select (companions later).

## 3. Targeting and movement

- Hover ground: path line from the character, green while within movement, red beyond.
  Distance in metres at the cursor. Opportunity-attack danger: a small red sword icon on the
  path where you would leave an enemy's reach.
- Hover enemy with an attack selected: tooltip
  `Longsword - 65% to hit - 1d8+3 slashing` plus little icons for advantage (height, flanking)
  or disadvantage (cover, condition), each with its reason on hover.
- Area effects (later, spells): template on the ground, affected characters highlighted.

## 4. Dice popup (the heart, pillar 1)

Appears near the centre for about 1.5 s for every attack roll, check or save (skippable with a
click, speed adjustable in options):

```
          +--------------------------------------+
          |   [ d20: 14 ]   ( d20: 6 )            |  <- second die greyed = disadvantage/adv.
          |   +3 STR   +2 Proficiency             |
          |   ---------------------------------   |
          |   19   vs   AC 15        HIT          |
          +--------------------------------------+
```

- A real 3D d20 spins and tumbles visibly (owner decision), then lands showing the number.
- Natural 20: gold flash, "CRITICAL", slow-motion on the hit. Natural 1: red crack, "FUMBLE".
- Damage roll shows its dice right after, then floating damage numbers over the target
  (colour by damage type).
- Skill checks in dialogue (later) use the same popup, bigger, with the DC shown before rolling.

## 5. Start menu and character creation (M1: simplified)

```
 Main menu:   NEW GAME  /  CONTINUE (only if an ironman save exists)  /  OPTIONS  /  QUIT

 Creation:  +-----------------+   +-------------------------------+
            | CLASS           |   |                               |
            | > Fighter       |   |   3D preview of the hero,     |
            | > Wizard        |   |   rotatable, idle animation   |
            |  (10 more later)|   |                               |
            | BODY  [M] [F]   |   +-------------------------------+
            | LOOK  < 1/3 >   |   Class description + key stats
            | NAME  [______]  |   (HP, AC, main ability)
            +-----------------+               [ BACK ]   [ BEGIN ]
```

- M1 only offers Fighter and Wizard; all 12 classes, ability scores (point buy) and skill
  choices come in M2.
- Permadeath is stated clearly once on "Begin": "When you die, this run is over."

## 6. Death screen

Full screen fades to dark red, the hero's death animation plays, then: name, class, level,
how they died ("Slain by Skeleton Archer, round 4"), XP earned. Only button: MAIN MENU.
The save is deleted (ironman).

## 7. Options (M1 minimum)

Resolution, fullscreen, volume (master, music, effects), dice popup speed
(slow / normal / fast / off), camera rotation speed. Language comes with the German version.

## 8. Decisions

Decided 05-10-2026: real spinning 3D d20. HUD style is not a priority for now; Codex
picks a clean, readable style that fits the assets.
