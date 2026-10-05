# Codex prompts

Written by Claude (coordinator). Codex has no coordinator of its own, so this table is the plan.
Two Codex sessions can run at the same time, one per track. Within a track: strictly one after
the other, the next prompt only after the previous one is pushed (RULE 6).

| Track | Order | Prompt | Owns files | Status |
|---|---|---|---|---|
| A | 1 | [01 Better-quality 3D assets](01-better-assets.md) | assets/, scenes/showcase/, project.godot | partial – Q30 open |
| A | 2 | [02 Project foundation](02-foundation.md) | everything except track B's folders | after 01 |
| B | 1 | [03 Rules core (5.5e / SRD 5.2)](03-rules-core.md) | src/rules/, data/classes/, tests/unit/rules/ | ready - parallel to track A |
| - | 3 | [04 Combat system and enemy AI](04-combat-and-ai.md) | - | after 02 AND 03 |
| - | 4 | 05 First slice (written after 04) | - | not written |

Both tracks append to the same handover file: `git pull --rebase` before every push, keep both
entries on a conflict.
