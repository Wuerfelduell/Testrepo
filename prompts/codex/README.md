# Codex prompts

Written by Claude (coordinator). Codex has no coordinator of its own, so this table is the plan.
Prompts marked "parallel" can run in separate Codex sessions at the same time (each prompt has a
file ownership table). Everything else runs strictly one after the other (RULE 6).

| Track | Order | Prompt | Owns files | Status |
|---|---|---|---|---|
| A | 1 | [01 Better-quality 3D assets](01-better-assets.md) | assets/, scenes/showcase/, project.godot | partial – Q30 open |
| A | 2 | [02 Project foundation](02-foundation.md) | everything except track B's folders | done |
| A | 3 | [01b Test: build one enemy + two weapons](01b-enemy-test.md) | assets/, scenes/showcase/, src/showcase/, tools/ | done |
| B | 1 | [03 Rules core (5.5e / SRD 5.2)](03-rules-core.md) | src/rules/, data/classes/, tests/unit/rules/ | done |
| - | 3 | [04 Combat system and enemy AI](04-combat-and-ai.md) | - | done |
| C | 1 | [05 Wizard, spells, class features](05-wizard-spells.md) | see file ownership table in the prompt | ready - parallel |
| D | 1 | [06 Menu, character creation, save, death](06-menu-save.md) | see file ownership table in the prompt | ready - parallel |
| E | 1 | [07 Enemies, boss, looks, weapons, hit effects](07-enemies-art.md) | see file ownership table in the prompt | ready - parallel |
| - | next | 08 First map (crypt, ~6 minutes) + dialogue system - needs the owner's story answers | - | not written |

All sessions append to the same handover file: `git pull --rebase` before every push, keep both
entries on a conflict.
