# Codex prompt 02 - Project foundation (milestone M0)

Written by: Claude (coordinator), 05-10-2026
Status: send AFTER prompt 01 is finished and pushed (both touch project.godot - RULE 6).
Prompt 03 may be running in parallel in another Codex session: do not touch src/rules/,
data/classes/ or tests/unit/rules/. Before every push: `git pull --rebase`; if the handover file
conflicts, keep both entries. When you are done, merge src/rules/SRD_ATTRIBUTION.md (if it
exists) into CREDITS.md.

---

You are working on the repo Wuerfelduell/Testrepo. Before you start:
- Read RULESET.md and follow it strictly: work directly on main, `git pull` before you start,
  commit + push when you are done, log your task in today's handover file in handover/
  (format at the end of RULESET.md).
- Read docs/DESIGN.md (the design document) and the newest file in handover/.
- If anything is unclear, STOP and write the question into "Open questions for the owner" in
  today's handover file instead of guessing (RULE 7).
- Engine: Godot 4 (latest stable 4.x), GDScript with static typing everywhere.
- All player-visible text goes through translation keys (`tr("KEY")`) in
  `localization/strings.csv` (English column first). No hard-coded UI strings.

## Goal
Build the technical foundation every later feature sits on. No gameplay yet. The two
architecture rules from docs/DESIGN.md section 4 ("Multiplayer-ready architecture") are the
most important part of this task.

## Tasks
1. **Folder structure** (keep what prompt 01 created under assets/ and scenes/showcase/):
   ```
   src/core/        autoloads: Game (state + mode), EventBus, CommandBus, Rng
   src/rules/       pure rules logic - OWNED BY PROMPT 03, which runs in parallel in another
                    Codex session. Do not create or change files there.
   src/commands/    command classes
   src/world/       scene-side code (actors, camera, level)
   src/ui/          UI code
   data/            .tres resources (classes, weapons, monsters)
   localization/    strings.csv
   tests/unit/      unit tests
   ```
2. **Command system** (the core of multiplayer-readiness):
   - `Command` base class (RefCounted) with `actor_id`, `validate(state) -> Error/result`,
     `apply(state)`, and `to_dict()` / `from_dict()` so a command can later be sent over the
     network.
   - `CommandBus` autoload: the ONLY way game state changes. `submit(command)` validates,
     applies, then emits `command_applied(command, result)`. Rejected commands emit
     `command_rejected(command, reason)`.
   - One example command `EndTurnCommand` with a test.
3. **State vs. presentation:** a `GameState` object (RefCounted, owned by the `Game` autoload)
   holds all game data (actors, HP, positions, turn order). Scenes read it and listen to
   signals; they never change it directly. Write this rule as a comment at the top of
   `src/core/game.gd`.
4. **Seedable randomness:** `Rng` autoload wrapping RandomNumberGenerator, with `set_seed()`
   and a public `rng: RandomNumberGenerator` property. All randomness in the game must go
   through it (tests need reproducible dice); rules functions receive `Rng.rng` as a parameter.
5. **Tests:** add GUT (Godot Unit Test, MIT licence) under `addons/gut/`. Tests must run
   headless: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`.
   Add `tests/run_tests.sh` for that command (use `-ginclude_subdirs` so tests/unit/rules/ runs too). Write tests for CommandBus and Rng.
6. **GitHub Actions:** `.github/workflows/tests.yml` that downloads the same Godot version,
   imports the project and runs the tests on every push to main.
7. **Windows export:** add an `export_presets.cfg` with a "Windows Desktop" preset that
   builds `build/TheRPG.exe` with the .pck embedded. Add `build/` to .gitignore.
   Document the export steps in README.md.
8. **Localization:** `localization/strings.csv` with columns `keys,en` (a `de` column comes
   later), registered in project settings. Add the keys you use.
9. **Project settings:** window 1920x1080, project name "The RPG", input actions for camera
   (rotate, zoom, pan), select, cancel, end turn - defined in project.godot, not in code.
10. Update README.md: how to open the project, run tests, export the .exe.

## Do not
- No gameplay, no rules logic, no combat. That comes in prompts 03 and 04.
- Do not remove or change the assets or the showcase scene from prompt 01.

## Done when
- Project opens without errors or warnings, the tests pass headless and in GitHub Actions.
- The Windows export builds a single .exe that starts (it can show the showcase scene).
- Committed, pushed to main, logged in today's handover file.
