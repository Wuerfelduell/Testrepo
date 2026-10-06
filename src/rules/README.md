# Rules core — Auftrag 03

Pure GDScript logic on Godot 4.7.2. No Nodes, scenes, singleton references, UI strings or implicit randomness. Application code passes `Rng.rng`; tests seed the same generator through the existing Foundation. Resources use stable IDs and `FEATURE_*` keys. Feature `name` is source metadata, not ready-to-display text: presentation must translate the key.

## Boundaries and sources

Only the official **SRD 5.2**, not 5.1, the Player's Handbook, BG3 or third-party rules, supplies rules and numbers. See [SRD_ATTRIBUTION.md](SRD_ATTRIBUTION.md).

| Module | Source pages | Contract |
|---|---|---|
| `Dice`, `DiceResult`, `RuleModifier` | 5–8, 16 | Every die, kept index, signed modifier/source, natural d20 flags; critical extra dice in a separate group |
| `Abilities`, `Checks`, `CheckResult` | 6–9, 20–23 | Six abilities, 18 skills, level 1–10 proficiency, checks/saves vs. DC |
| `Attacks`, `DamageRules` | 7, 14–17, 191 | Natural 1/20, all 13 damage types, resistance before vulnerability, immunity |
| `ConditionState`, `RollContext` | 177, 182, 184, 186–187, 189, 191 | Seven requested conditions plus inherited incapacitation; source-specific removal |
| `TurnEconomy` | 9–10, 13–14, 178, 186 | Action, bonus action, reaction, movement, Dash, crawling and standing |
| `Initiative` | 13 | Dexterity check; **project adaptation:** tied total → higher Dexterity score → seeded shuffle |
| `ClassDefinition`, `data/classes/*.tres` | 28–82 | Twelve classes, core traits, tool/skill choices, non-subclass named features at levels 1–10 |
| `CharacterSheet`, `ArmorRules` | 19–23, 86, 92 | Human, one class, explicit skill choices, fixed HP, equipment AC and armor penalties |
| `Progression` | 23 | XP thresholds through level 10; reason-preserving award history and multi-level results |

## Using the core

```gdscript
var definition: ClassDefinition = load("res://data/classes/fighter.tres") as ClassDefinition
var hero: CharacterSheet = CharacterSheet.create(definition, 1, {
    &"str": 16, &"dex": 14, &"con": 14, &"int": 10, &"wis": 12, &"cha": 8,
})
hero.select_class_skills([&"athletics", &"perception"])
hero.select_human_skill(&"arcana")
hero.equip(&"chain_mail", true)
var check: CheckResult = Checks.skill_check(&"athletics", hero.ability_scores(),
    15, Rng.rng, hero.level, true, hero.context_for(&"str", &"athletics"))
var attack: Attacks.Result = Attacks.resolve(15,
    Abilities.modifiers_for(16, &"str", hero.level, true), Rng.rng,
    hero.context_for(&"str"))
if attack.is_valid() and attack.hit:
    var damage: DamageRules.Result = DamageRules.roll("1d8", &"slashing", Rng.rng,
        [RuleModifier.new(3, &"str")], attack.critical)
var award: Progression.Award = hero.grant_xp(300, "spared_the_prisoner")
```

Roll functions return an `error` ID and `is_valid()`. Automatic condition failures are valid failed checks with `roll == null`, `automatic_failure == true` and a reason; no RNG is consumed. Invalid input is rejected before drawing randomness. `CharacterSheet.create` returns null for invalid construction; selection/equipment/turn operations return false without consuming the resource. Ability identifiers supplied to sheet modifier/save accessors must be members of `Abilities.IDS`.

`Dice.roll` accepts `NdS` with zero or more signed integer constants, such as `1d20+5`, `2d6+3-1`, `8d6`. For named sources pass `RuleModifier` objects instead of hiding all bonuses in one expression. `Dice.d20` accepts arrays of advantage/disadvantage source IDs. Multiple sources never add dice; any source on both sides cancels to one d20. Natural flags refer to the kept die, not the sum. Parser limits (1000 dice, 1,000,000 sides/individual modifier, 256 characters) are resource guards, not game rules.

Damage represents **one damage instance of one type**. Aggregate contributions of the same type for that instance before applying defenses, rather than halving each individual die. Critical hits roll twice the dice, never twice the flat modifier. Negative damage totals become zero. Immunity overrides the final result. Repeated defense entries do not stack. The roll and pre-/post-resistance totals remain available for display.

Supply distance and whether a fear source is in line of sight from encounter geometry. `move(..., toward_fear=true)` must be set when a proposed voluntary move approaches any active fear source, even if unseen. Nonvisual senses, cover, weapon reach/range and legal action targeting belong to the encounter layer. Blinded sight checks assume physical sight. A stunned creature is incapacitated but **does not** have Speed 0 under SRD 5.2. Unconscious creatures drop held objects (effect flag), cannot concentrate/speak/act, automatically fail STR/DEX saves, and remain prone on waking. Scene/state code applies item drops and concentration termination when a condition starts.

Call `begin_turn` only at the start of **this actor's** turn: a spent reaction remains spent through other actors' turns. A bonus action needs an enabling rule. Conditions remain live, so removing restraint restores unspent movement. Distances use metres without rounding paths to a grid. Standing rounds half-speed in feet before converting; at 9 m speed it costs 4.5 m. Difficult terrain and crawling add their costs (3 metres of budget per metre when both apply). `ConditionState.stand_up` is a low-level state operation; use `TurnEconomy.stand_up` to pay movement.

Initiative results retain each d20 result and every tie shuffle draw. Sorting itself is deterministic and RNG-free. Callers pass participants in a reproducible order and must use unique IDs.

## Explicitly deferred

Class features are **names, keys and levels only**, including spellcasting entries. No subclasses, feature mechanics, spells, feats, backgrounds, multiclassing, inventory effects, combat commands or UI are implemented here. In particular, unarmored-defense formulas, extra attacks, expertise granted by a class, class speed increases and feature-granted armor training do not activate automatically. `Checks` already supports an explicit expertise argument for later feature integration.

The human base sheet has 9 m speed and an explicit extra skill choice. Human size, origin feat and class tool choices are exposed as pending metadata; no choices or ability-score improvements are silently invented. Human Resourceful/rest effects and feat effects belong to subsequent feature implementation. `maximum_hp`, AC and derived bonuses recalculate from current level/scores; the sheet does not manage current HP or heal on level-up. Starting at a higher level initializes XP to that level's minimum. The level cap does not discard earned XP, and every accepted award (including zero) keeps its original reason. History/input copies prevent UI mutation from changing stored data.

## Verification

Run the existing repository command: `tests/run_tests.sh` (override `GODOT_BIN` if needed). The workflow already includes `tests/unit/rules/` recursively. Rule tests cover all ten task areas using fixed seeds; source table expectations cover every class, armor formula and level threshold. No changes to Foundation, project settings, workflow or the parallel asset track are required.
