# Class kits

Fighter and Wizard were built before this folder existed and keep their own code.
Every other class lives in one kit script: `src/rules/classes/<class_id>_kit.gd`
(`class_id` as in `data/classes/<class_id>.tres`). The moment the file exists the class
is playable: character creation enables it, HeroKit/HeroFactory build it, the level-up
screen, rests, equipment and combat call into it. Nobody edits a shared class list.

A kit is a script with only `static` functions and constants (no `class_name` needed).
Everything is optional; leave out what the class does not need.

## Constants

| Name | Meaning |
|---|---|
| `PRIORITY: Array[StringName]` | Standard array order (15, 14, 13, 12, 10, 8), main ability first. **Required.** |
| `SKILLS: Dictionary` | `{"class": [two class skills], "human": skill}` defaults. **Required.** |
| `IMPLEMENTED_MAX_LEVEL: int` | Features up to this level count as active (default 10). |
| `DATA_ONLY: Dictionary` | `feature_id -> why` for listed features without rules yet. |
| `FEATURES: Array[String]` | Every hotbar feature id the kit can show (for save decoding). |

## Starting gear

`data/items/class_<class_id>.json`, same shape as `data/items/items.json`:
`{"items": {...new items...}, "starting_kits": {"<class_id>": {"equipped": {...}, "bag": {...}, "gold": n}}}`.
Item ids must not repeat existing ones. The main-hand weapon, armour and shield of the
kit are what creation shows (HP, AC) and what the hero starts with.

## Functions (all static)

Record life cycle
- `activate(record)` level-1 setup after the shared part (saves, proficiency, `features = {}`).
- `upgrade(record)` an already active record from an older save.
- `advance(actor, level)` feature records for this level (called on creation and each level-up).
- `refresh_derived(actor)` values that depend on level/scores (spell slots, DCs).
  `ClassKits.refresh_spellcasting(actor, &"wis", slots)` does the caster part.
- `level_choices(actor, new_level) -> Array` extra level-up picks:
  `{"key", "count", "options": [ids], "title_key" (has one %d), "option_prefix" (tr prefix, "" = spell ids), "note_key"?}`.
- `apply_level_choices(actor, new_level, picks: Dictionary)` picks = key -> [ids].

Equipment
- `unarmored_ac(actor, shield) -> int` AC without armour, 0 = none (better value wins).
- `speed_bonus_m(actor) -> float`
- `adjust_weapon(actor, record, item)` change a built weapon record (Martial Arts).

Combat (state = GameState)
- `attack_advantages / attack_disadvantages(state, attacker_id, target_id, weapon) -> Array[StringName]` (attacker's kit)
- `incoming_advantages / incoming_disadvantages(...)` (target's kit, e.g. Reckless Attack)
- `damage_bonus(state, attacker_id, target_id, weapon) -> [{"amount", "source"}]` flat bonus on a hit
- `extra_damage_dice(state, attacker_id, target_id, weapon, critical) -> [{"dice", "damage_type"?, "source"}]`
  called once per real hit (may spend once-per-turn resources); `expected_extra_damage(...)` for previews, no state change
- `resistances(actor) -> Array` damage types
- `save_advantages(actor, ability) -> Array[StringName]`
- `on_turn_start(state, actor_id)`, `on_turn_end(state, actor_id, rng)` -> events
- `after_attack(state, attacker_id, target_id, weapon, hit, rng)` / `after_attacked(...)` -> events

Hotbar features (UseFeatureCommand with any id the kit lists)
- `feature_buttons(actor) -> Array[String]`
- `feature_reason(state, actor_id, feature_id) -> String` "" = usable, else a translation key
- `use_feature(state, actor_id, feature_id, rng) -> Array[Dictionary]` events
- `feature_label(actor, feature_id) -> String` optional; default `tr("FEATURE_<ID>_BUTTON") % [uses, max]`
- Hover text: `FEATURE_<ID>_HINT`.

Rests
- A feature stored as `{"uses", "max", "recharge": "short"|"long", "short_regain"?}` recharges
  without kit code (`ClassKits.set_uses` keeps spent uses spent when it grows).
- `on_rest(actor, "short"|"long")` for anything else.
