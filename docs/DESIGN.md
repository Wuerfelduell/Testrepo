# Game Design Document

Written by: Claude (coordinator), 05-10-2026
Status: draft v1 - based on the owner's answers in handover/05-10-2026.md. The owner decides
everything; anything marked OPEN is not decided yet (RULE 7).

---

## 1. Vision

A party-based fantasy RPG in the spirit of Baldur's Gate 3: explore in real time, fight in
turns with real D&D 5e dice, make decisions that matter and get punished for the wrong ones.
Quality over speed: 3-5 months of work for a game the owner wants to play himself.

### Lessons from the old project (Wuerfelduell/dnd)
The old project failed because of: too little time and planning, a tiny map, UI not thought
through, dumb enemy AI, bad physics, no animations (capsules only, assets never imported),
a weak level system and dice that were only a log line. Every one of these gets its own
system and milestone below.

### Design pillars
1. **Dice are the heart.** Every roll is visible, readable and dramatic (3D/animated dice,
   modifiers broken down, advantage shown as two dice).
2. **Enemies think.** Enemies use cover, height, focus fire, flank, retreat and use their
   abilities. Losing to them feels fair.
3. **Decisions have teeth.** Wrong decisions are punished (RULE 4). Permadeath.
4. **It looks and moves alive.** Animated characters, lit and atmospheric levels, hit
   reactions, effects. No placeholder geometry in a milestone that is called "done".

## 2. Decisions so far

| Topic | Decision |
|---|---|
| Engine | Godot 4 (latest stable 4.x), GDScript, shipped as a Windows .exe |
| View | 3D, isometric camera like BG3 (rotate, zoom) |
| Rules | D&D 5e, adapted like in BG3 |
| Combat | Turn-based, free movement on the field (no grid) |
| Character | Created in the start menu like BG3. Race: human only. All 12 classes, no subclasses at first |
| Party | Singleplayer hero + recruitable NPC companions |
| Multiplayer | Later (online co-op up to 4, local 2-player). Not in the first release |
| Story | Fixed story. Story proposals come later; Claude asks the owner questions first |
| Death | Permadeath. Resurrection scrolls later |
| XP | Good decisions give XP. Wrong decisions can still give XP if you kill everyone |
| Language | English base game; German translation later |
| Setting | Mix of dark and classic fantasy, like BG3. Violent and frightening scenes (RULE 5) |
| Assets | Free-licensed (CC0 / CC-BY) 3D assets, see prompts/codex/01-better-assets.md |

## 3. Rules (D&D 5e)

- **Rules version:** D&D 5.5e (2024 rules), adapted like BG3. Owner decision 05-10-2026.
- **Legal basis:** the 2024 rules are published for free as the System Reference Document 5.2
  (CC-BY-4.0). Rules text, class features, spells and monsters are taken from the SRD 5.2;
  anything that is not in the SRD (e.g. most subclasses) is written in our own words, never
  copied from the Player's Handbook or from Baldur's Gate 3. Attribution goes into the credits.
- "Dungeons & Dragons" / "D&D" are trademarks: they must not be in the game's title or store
  page. Working title: "the RPG" (owner decision).
- Abilities STR/DEX/CON/INT/WIS/CHA, proficiency bonus, skills, saving throws, AC.
- Attack roll d20 + modifiers vs. AC; critical on 20; advantage / disadvantage.
- Action, bonus action, reaction, movement per turn. Opportunity attacks.
- Spell slots, cantrips, concentration, short and long rest.
- Conditions (prone, poisoned, frightened, restrained, ...).
- BG3-style additions: jump, shove, height advantage, throwing objects, surfaces
  (fire, ice, poison, water + lightning).
- **12 classes:** Barbarian, Bard, Cleric, Druid, Fighter, Monk, Paladin, Ranger, Rogue,
  Sorcerer, Warlock, Wizard. Subclasses later.
- Level cap: 10.

## 4. Core systems

| System | What it does | Fixes old problem |
|---|---|---|
| Rules core | Pure logic: dice, checks, attacks, spells, conditions. No UI, no scene code. Fully unit tested | dice not integrated |
| Dice presentation | Every roll shown on screen with breakdown; dramatic rolls for skill checks in dialogue | dice not integrated |
| Combat | Initiative, turns, free movement with a movement budget and a path preview, AoE templates, line of sight, cover, height | - |
| Enemy AI | Utility AI: scores every possible action (attack, spell, move to cover, heal, flee) per enemy type and personality | dumb AI |
| Physics | Godot physics only for what it is good at: thrown objects, falling, knockback, ragdolls on death. Game rules never depend on physics randomness | bad physics |
| Animation | Animation state machine per character: idle, walk, run, attack, cast, hit, death; root motion where available | no animations |
| Exploration | Real-time movement, party follows, stealth, traps, perception checks, interactable objects | small map |
| Dialogue | Branching dialogue with skill checks, consequences, flags and approval of companions | - |
| Companions | Recruitable NPCs, party of up to 4, control any party member in combat | - |
| Progression | XP, level-up screen with real choices, equipment, inventory, loot | bad level system |
| UI | Designed before it is built: wireframes first, then implementation. Hotbar, party portraits, initiative bar, tooltips with dice math | UI not thought through |
| Save | Ironman: one autosave slot per run, saving only on exit, so permadeath means something |
| Localisation | All text through translation keys (Godot `tr()`), English first |

### Multiplayer-ready architecture
Multiplayer is not built now, but two rules from day one keep it possible later:
1. Every player action is a **command** object (move, attack, cast, talk) that goes through
   one central place that validates and applies it. Later these commands are sent over the
   network instead of applied locally.
2. **Game state is separate from presentation.** The rules core never touches nodes, UI or
   animations; scenes only display the state.

## 5. Milestones

Each milestone ends with a playable build, a Grok review (owner sends the ZIP) and a short
playtest by the owner. Durations are a plan, not a promise.

| # | Name | Weeks | Content | Done when |
|---|---|---|---|---|
| M0 | Foundation | 1 | Asset set + showcase scene (prompt 01). Project structure, rules core skeleton, command system, automated tests, Windows export, Git LFS | Showcase scene runs, tests run headless, .exe builds |
| M1 | First slice | 2-4 | The first ~6 minutes of act 1 (one tenth of it): start menu, simple hero choice (Fighter or Wizard), one small map with height and cover, 1-2 fights against 3 enemy types with utility AI, visible dice, combat UI, real animations | The owner plays it 5 times in a row and wants more |
| M2 | Characters | 5-8 | Character creation (12 classes, human), levelling to the cap, spells, equipment, inventory, level-up screen | Every class playable in the arena |
| M3 | World and dialogue | 9-12 | Exploration, dialogue system with skill checks, recruitable companions, first real map region. Story outline must be decided before this milestone | First region playable from start to finish |
| M4 | Act 1 content | 13-17 | Full first act (~1 hour of play): maps, quests, NPCs, boss, loot, balancing, save system, audio | Act 1 playable in one go without placeholders |
| M5 | Polish and release | 18-20 | Bug fixing, performance, UI polish, playtests, release build | .exe the owner gives to others |
| Later | After release | - | Multiplayer, German translation, resurrection scrolls, subclasses, more acts, more races |

## 6. Team and roles

| Who | Does |
|---|---|
| Owner (Seb) | Decides everything, playtests every milestone, forwards prompts and ZIPs |
| Claude | Plans, writes this document and all Codex prompts, writes story proposals (after asking the owner), reviews Codex results |
| Codex | Writes the code and integrates assets, only from Claude's prompts |
| Grok | Reviews the repo ZIP neutrally after every milestone |
| Image / 3D AI (e.g. Meshy, Tripo, ChatGPT images) | Only if a needed model or image cannot be found as a free asset (RULE 11) |

## 7. Open questions

- Story: Claude asks the owner follow-up questions before M3. The first slice (M1) uses a
  neutral placeholder setting (a ruined crypt) until then - OPEN for the owner to change.

Decided 05-10-2026: level cap 10, ironman save, act 1 = about 1 hour of play, build one tenth
of it first (M1) and review.
