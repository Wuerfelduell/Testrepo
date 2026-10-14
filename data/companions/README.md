# Companions (campaign package K4)

`companions.json` lists every recruitable companion: the owner's Kael Dorn (fighter),
Lyra Vossen (wizard, half-elf) and Seren Nachtfall (rogue, dark elf; Fighter rules via
`fallback_class` until the Rogue class is playable). Their lines come from the owner's
dialogue document; `[Placeholder: ...]` lines are slots he still writes. The knight boy from the Underground City joins later as a short
4th companion (story decision R8) and gets an entry here when that part is built.

```json
{"id": "companion_kael", "short": "kael", "name": "Kael Dorn", "class_id": "fighter", "species": "human",
 "model": "res://assets/characters/hero_fighter_male/model.glb", "colors": {}, "dialogue": "companion_kael",
 "leaves_below": -3}
```

- **id** starts with `companion_` and is also the actor id in the game state.
- **short**: the name dialogue data uses (`"react": {"kael": ...}`, `"speaker": "kael"`,
  flags `kael_loyalty`, `kael_recruited`, `kael_left`).
- **class_id**: a playable class; **fallback_class** is used while class_id is not playable
  yet. Otherwise a playable class (`fighter` or `wizard` today). Level 1, standard array,
  class skills and starting kit, like a created hero (HeroFactory).
- **model**: any hero look scene; **colors**: per-piece colours (HeroColors), may be empty.
- **dialogue**: the conversation in data/dialogue/ that recruits them (effect `"recruit"`).
- **camp_dialogue**: what they say when the player talks to them in the party (right-click on
  their portrait, out of combat): the owner's camp talks (camp_<short>.json).

How the party works:
- Party = hero + up to 3 companions (`PartyRules.MAX_SIZE` = 4). The order is saved in
  `world["party"]`; a dismissed companion waits in `world["companions"]` with their HP, XP
  and gear and comes back unchanged.
- Out of combat the commanded member walks where you click and the others follow behind.
  Switch the commanded member with a click on their portrait (left, above the bars), a
  click on them in the world, or Tab.
- In combat every member rolls initiative; on a companion's turn the player commands them
  (no AI). Only the hero's death ends the run; a fallen companion stays dead (permadeath,
  resurrection scrolls later).
- Every living companion gets the same XP as the hero (fights and conversations).
- They wait on the Torplatz in Das Torviertel (hooks in data/encounters/torviertel.json);
  the hook disappears once they joined (`"hide_if": [{"in_party": id}]`). They travel with
  the hero between areas (AreaTravel moves every actor of the hero's team).

Loyalty, reactions and arguments (owner, 14-10-2026, docs/STORY.md "How Rabenfels reacts"):
- Loyalty is the counter flag `<short>_loyalty`. A dialogue effect `"react"` lets companions
  in the party comment on an answer and moves their loyalty once per answer; the line shows
  in the dialogue window, approve/disapprove in the combat log. With `leaves_below` set
  (Kael, Seren: -3) a companion whose loyalty drops below it leaves for good (`<short>_left`).
- `banter.json`: companions arguing among themselves. Each entry plays once, when both are
  in the party and alive, after a long rest (`"trigger": "rest"`) or on entering an area
  (`"arrive"`). Nodes name who speaks (`"speaker": "lyra"`); taking sides is a choice with
  `"react"`. The tree's start node must set flag `banter_<id>`.
- Parting (owner's part 7): dialogue effect `"leave": {"kael": "camp" | "parted" | "hostile"}`.
  Camp: waits (on the Torplatz until there is a real camp), no loyalty change. Parted: on good
  terms, can be recruited again. Hostile: `<short>_permanently_left`, never again. State flags
  per companion: `<short>_recruited`, `_active`, `_at_camp`, `_loyalty`,
  `_personal_quest_stage`, `_permanently_left`. Kind words count once, insults every time.
- "Show me your gear": effect `"inventory": "kael"` opens their inventory when the talk ends.
- Camp talks: high loyalty from +3, low from -2 (answers like "What do you think of me?").
- Camp events A-C are in banter.json (B only in the Torviertel, C once `vaelor_manuscript_found`).
- Training duels and the magical conflict are skill checks until the dialogue fight exists.
- Trial job ("Probeauftrag"): the companion joins with flag `<short>_trial`.
- Kael's recruit duel is a non-lethal fight (encounter kael_duel: an encounter member with "companion" fights with that companion's own sheet); flag kael_duel_fight says won or lost.
- Rumour-only answers need `kael_rumor_heard` / `seren_rumor_heard`, set by a district
  conversation (not written yet).
