# Codex prompt 01 - Better-quality 3D assets

Written by: Claude (coordinator), 05-10-2026
Status: ready to send FIRST (engine decided 05-10-2026: Godot 4, shipped as Windows .exe)

---

You are working on the repo Wuerfelduell/Testrepo. Read RULESET.md first and follow it strictly:
work directly on main, `git pull` before you start, commit + push when you are done, and log
your task in today's handover file in handover/ (format at the end of RULESET.md).
If anything is unclear, STOP and write the question into "Open questions for the owner" in
today's handover file instead of guessing (RULE 7).

## Goal
We are building a 3D, turn-based, dark-fantasy dungeon game in Godot 4 (latest stable 4.x release) (isometric camera,
in the style of Baldur's Gate 3). The game is planned for 3-5 months with quality over speed, so pick assets that can carry a
full game, not just a prototype. Your task is to assemble a set of 3D assets of BETTER quality
than the low-poly KayKit/Quaternius packs used in the old project, and to make them look good
in Godot. You do not write any gameplay code in this task.

## What "better quality" means here
- Consistent art style across ALL assets (no mix of styles).
- Characters fully rigged and animated: at least idle, walk, run, melee attack, ranged/cast,
  hit, death.
- Higher detail than flat-colour low-poly: real textures (PBR: albedo, normal, roughness).
- Dark, atmospheric look that fits violent and frightening scenes (RULE 5).

## Tasks
1. Research free assets with a licence that allows use in a game: CC0 preferred, CC-BY only
   if you record the attribution. Good places to look: Quaternius, KayKit, Kenney, Poly Haven
   (textures/HDRIs/models), OpenGameArt, itch.io (free, CC0). NO paid or "free for personal use
   only" assets, NO ripped assets from commercial games.
2. Pick ONE consistent set that covers:
   - playable human heroes (the player creates the hero in a start menu like in Baldur's Gate 3;
     race is human only, all 12 D&D classes): male and female human models, animated, with
     enough outfits/armour and weapons (swords, axes, bows, staffs, shields) to tell the
     classes apart
   - 3-4 enemy types (animated) + 1 boss (animated)
   - a dungeon kit: floor, walls, doors, pillars, stairs, props (torches, barrels, chests,
     bones, chains)
   - effects: blood/hit, magic, fire
3. Put the assets into `assets/` in Godot-friendly formats (.glb for models, .png textures).
   No ZIP files in the repo. Only add what is actually needed; keep the repo below 300 MB.
   If the total is above 50 MB, set up Git LFS for .glb/.png/.wav and say so in the handover.
4. Create a Godot 4 (latest stable 4.x release) project in the repo root (`project.godot`) if it does not exist yet, and an
   asset showcase scene `scenes/showcase/asset_showcase.tscn` that shows:
   - a small dungeon room built from the kit,
   - every hero and every enemy, each playing its animations (button or key to switch),
   - proper lighting: WorldEnvironment with SSAO, glow, fog/volumetric fog, tonemapping,
     torch lights with shadows. Lighting is where most of the "quality" comes from - spend
     time on it.
5. Write `assets/CREDITS.md`: every asset with source URL, author and licence.
6. Write `assets/README.md`: what is in the set, the animation clip names per character, and
   what is MISSING (e.g. no boss found in this style, no specific attack animation).

## Do not
- Do not copy dialogues or the companions (Bran, Vex, Elara, Tomas) from the old repo
  Wuerfelduell/dnd. The owner decided against that.
- Do not write gameplay code (movement, combat, AI). That comes in later prompts.
- Do not generate images or models with an AI yourself.

## Done when
- The showcase scene opens in Godot 4 (latest stable 4.x release) without errors and shows all assets lit and animated.
- CREDITS.md and README.md exist.
- Everything is committed and pushed to main, and logged in today's handover file.
