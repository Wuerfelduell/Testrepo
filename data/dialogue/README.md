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
  Give the choice an `"id"` when the same check answer stands in several nodes (a menu the
  hero returns to): all choices with that id share one roll.
- **conditions** (`if`, all must hold): `{"flag": "x"}` flag set, `{"flag": "x", "is": false}`
  not set, `{"flag": "x", "is": "killed"}` exact value, `{"class": "wizard"}`,
  `{"proficient": "arcana"}`, `{"any": [conditions]}` (one of them), and the counter, money,
  item and party conditions below.
- **effects**: `flags` (set world flags, any value) and `xp` (paid once per node or choice,
  never farmed by repeating). Good choices and violent choices both give XP (DESIGN.md).
  Companions in the party get the same XP. All other effects happen every time the node is
  entered or the answer picked, so guard rewards with a flag.
- **counters**: `"add": {"garrik_relationship": -1}` adds to a flag (unset = 0). Condition
  `{"flag": "garrik_relationship", "min": 1}` and/or `"max": -3` compares it.
- **money** (owner's economy: copper, silver, gold; 10 cp = 1 sp, 100 cp = 1 gp):
  `"money": -5` pays 5 copper, `"money": 3500` gives 35 silver. An answer that costs more
  than the hero has is hidden. Condition `{"money": 100}` needs at least 100 cp (1 gp).
- **items**: `"item": {"wanted_poster": 1}` gives, `-1` hands over (hidden when the hero
  lacks it). Condition `{"item": "sealed_package"}` (`"is": false` = not carried). Item ids
  come from data/items/items.json; story items have `"type": "quest"`.
- **damage**: `"damage": {"dice": "1d4", "type": "bludgeoning"}` hurts the hero, but never
  below 1 HP: a conversation never ends the run.
- **fight**: `"fight": {"encounter": "gate_guards", "nonlethal": true}` ends the conversation
  and starts that encounter of the current level (see below).
- **party** (package K4): effect `"recruit": "companion_a"` adds that companion to the party
  (4 at most, hero included), `"dismiss": "companion_a"` sends them away (they keep their
  state and can be recruited again). Conditions `{"in_party": "companion_a"}` (add
  `"is": false` for "not in the party") and `{"party_room": true}` / `false`. Companion ids
  come from data/companions/companions.json.
- Level hooks can disappear with `"hide_if": [conditions]`, checked when a conversation ends.

Design rules (owner, 14-10-2026, docs/STORY.md "How Rabenfels reacts"): one successful roll
never buys loyalty; consequences come from each NPC's personality and interests, not from a
good/evil scale; a failed check never blocks the main story, the information stays reachable
elsewhere. Write consequences as flags or counters (e.g. `garrik_threatened`, `player_cruelty`)
so later conversations can react to them.

Flags live in `Game.state.world["flags"]` and are saved. `tests/unit/dialogue/` checks every
file in this folder, so a broken link between nodes fails the tests.
