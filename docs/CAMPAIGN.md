# Campaign plan: start of act 1 in the Overcity

Planned 13-10-2026 (Claude, thread "Kampagne"), from docs/STORY.md. Act 1 is long and built in
small packages. The owner writes every dialogue line; packages only add placeholder lines.

| # | Package | Depends on | Parallel? | Status |
|---|---|---|---|---|
| K1 | **Dialogue system**: trees in data/dialogue/, skill checks in the dice popup, flags, XP for choices, crypt hooks wired | - | - | done 13-10-2026 |
| K2 | **First Overcity district**: walkable start district with NPC hooks (placeholder dialogues), the hero's new start point | K1 for talking only | yes, alongside K1/K3/K4 | done 13-10-2026: Das Torviertel (gate district), Quaternius Medieval Village kit; asset source and name are Claude's recommendations, owner may still change them |
| K3 | **Quests and travel**: quest log, travel between district and crypt, per-area state in the save, the crypt becomes the cultist side quest reached from the district | K1 (flags) | yes, alongside K2 if K2 leaves run_flow.gd to K3 | done 13-10-2026; K2 added the Torviertel <-> crypt exits and the new game start |
| K4 | **Companions**: recruit through dialogue, party up to 4, control in combat, approval hooks | K1 | yes, alongside K2/K3 | open |

File ownership for parallel threads: K2 owns new files for its district (src/world/level_<district>.gd,
data/encounters/<district>.json, scenes/levels/<district>/, new assets). K3 owns
src/ui/menu/run_flow.gd, src/core/save_game.gd and the travel/quest files. K4 owns party code in
src/world/arena.gd and src/ui/combat_hud.gd. Everyone may append to data/dialogue/ and
localization/strings.csv.

K3 format: exits in a level file (`"exits": [{"id", "position", "to": "<level json>", "arrive": [x,y,z], "if": [...]}]`),
quests in data/quests/ (README there), journal on J. Areas the hero left are kept in
`world["areas"]`; actors on the hero's team travel along.

Open for the owner (not blocking K1): name of the first Overcity district; where the hero
starts the game; who the three Overcity companions are (the crypt prisoner is only a placeholder
NPC so far).
