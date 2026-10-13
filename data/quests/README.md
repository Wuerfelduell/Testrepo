# Quests (campaign package K3)

One JSON file per quest. A quest has no saved state of its own: it is computed from the world
flags (set by dialogue effects, `visited_<level>` when an area is entered, `defeated_<actor id>`
when an enemy's XP is paid). Conditions use the dialogue format (data/dialogue/README.md).

```json
{
	"version": 1,
	"id": "crypt_prisoner",
	"title": "The prisoner behind the gate",
	"start_if": [{"flag": "crypt_prisoner_key_hint"}],
	"stages": [
		{"text": "First journal text."},
		{"if": [{"flag": "crypt_prisoner_promised"}], "text": "Later text: the last stage whose if holds is shown."}
	],
	"done_if": [{"flag": "crypt_prisoner_freed"}],
	"done_text": "Shown when done.",
	"failed_if": [{"flag": "crypt_prisoner_refused"}],
	"failed_text": "Shown when failed (failing wins over done)."
}
```

The owner writes titles and texts; `[Placeholder]` marks the slots. The journal opens with J.
