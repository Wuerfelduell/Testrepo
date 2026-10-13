# Companions (campaign package K4)

`companions.json` lists every recruitable companion. All three are **placeholders** until
the owner decides who the three Overcity companions are (docs/STORY.md); the owner writes
their dialogues himself. The knight boy from the Underground City joins later as a short
4th companion (story decision R8) and gets an entry here when that part is built.

```json
{"id": "companion_a", "name": "Companion A", "class_id": "fighter",
 "model": "res://assets/characters/hero_fighter_female/model.glb", "colors": {}, "dialogue": "companion_a"}
```

- **id** starts with `companion_` and is also the actor id in the game state.
- **class_id**: a playable class (`fighter` or `wizard` today). Level 1, standard array,
  class skills and starting kit, like a created hero (HeroFactory).
- **model**: any hero look scene; **colors**: per-piece colours (HeroColors), may be empty.
- **dialogue**: the conversation in data/dialogue/ that recruits them (effect `"recruit"`).

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
