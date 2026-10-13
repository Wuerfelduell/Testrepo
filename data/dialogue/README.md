# Dialogue trees (campaign package 1)

One JSON file per conversation, named after its id (`crypt_prisoner.json`). A level hook
opens it with `"dialogue": "<id>"` in its level file (see data/encounters/crypt.json).
The owner writes all dialogue lines; every `[Placeholder: ...]` text is a slot for him.
Texts are the English source strings; a German translation can later key on them.

```json
{
	"version": 1,
	"id": "crypt_prisoner",
	"speaker": "Prisoner",
	"start": [
		{"if": [{"flag": "crypt_prisoner_promised"}], "node": "waiting"},
		{"node": "first"}
	],
	"nodes": {
		"first": {
			"text": "What the NPC says.",
			"effects": {"flags": {"met_prisoner": true}, "xp": 15},
			"choices": [
				{"text": "Plain answer", "next": "who"},
				{"text": "Answer with a check", "check": {"skill": "insight", "dc": 12, "success": "honest", "failure": "unsure"}},
				{"text": "Only for proficient heroes", "if": [{"proficient": "medicine"}], "next": "healed"},
				{"text": "An answer without next ends the conversation"}
			]
		}
	}
}
```

- **start**: the first entry whose `if` holds is where the conversation begins.
- **node**: `text` (required), optional `effects`, optional `choices`. A node without choices
  shows "End the conversation".
- **choice**: `text`, then `next` (another node), `check`, or nothing (ends). Optional `if`
  and `effects` (applied when picked).
- **check**: skill (SRD 5.2 skill id, e.g. `persuasion`), `dc` 1-30, `success` and
  `failure` nodes. Rolled with the hero's ability, proficiency and expertise and shown in the
  dice popup. Each check is rolled **once**: after that the answer is gone (RULE 4).
- **conditions** (`if`, all must hold): `{"flag": "x"}` flag set, `{"flag": "x", "is": false}`
  not set, `{"flag": "x", "is": "killed"}` exact value, `{"class": "wizard"}`,
  `{"proficient": "arcana"}`, and the party conditions below.
- **effects**: `flags` (set world flags, any value) and `xp` (paid once per node or choice,
  never farmed by repeating). Good choices and violent choices both give XP (DESIGN.md).
  Companions in the party get the same XP.
- **party** (package K4): effect `"recruit": "companion_a"` adds that companion to the party
  (4 at most, hero included), `"dismiss": "companion_a"` sends them away (they keep their
  state and can be recruited again). Conditions `{"in_party": "companion_a"}` (add
  `"is": false` for "not in the party") and `{"party_room": true}` / `false`. Companion ids
  come from data/companions/companions.json.
- Level hooks can disappear with `"hide_if": [conditions]`, checked when a conversation ends.

Flags live in `Game.state.world["flags"]` and are saved. `tests/unit/dialogue/` checks every
file in this folder, so a broken link between nodes fails the tests.
