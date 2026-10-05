PROJECT RULESET
===============

These rules apply to every AI working on this project (Claude, Codex, Grok) and are permanent.
The project owner makes all decisions.


THE TEAM
--------
Owner          - The user. Makes every decision. Provides assets, dialogue choices and answers.
Coordinator    - Claude (Claude Code). Plans the work, splits tasks, writes the prompts for Codex.
Implementer    - Codex. Only works on prompts that come from the coordinator (forwarded by the owner).
Observer       - Grok. Receives repo ZIPs from the owner. Watches and gives an objective, neutral
                 assessment. Does not edit the repo.


RULES
-----

RULE 1 - Every AI may read and edit the repo
  Every AI may read and edit everything in this repo. No locked areas, no "that's not mine".
  Otherwise we end up where Forge ended up.
  - Grok has no direct repo access. It receives the repo as a ZIP from the owner and acts
    only as an objective observer.

RULE 2 - Every task produces written output
  After every task something is written (code). A task without written output was a useless task.
  - Exception: a task that has to stop because of an open question (Rule 7) is NOT useless,
    as long as the question is written into today's handover file.

RULE 3 - Every change is saved, pushed and logged
  Every change is committed and pushed, and logged in the handover - otherwise nobody knows
  what's going on.
  - Handover files live in the folder "handover/".
  - One file per day, named DD-MM-YYYY (example: handover/05-10-2026.md).
  - Every AI writes into today's file. If it doesn't exist yet, create it using the
    HANDOVER FORMAT at the end of this file.
  - If anything is unclear: read the NEWEST handover file (not necessarily yesterday's -
    there may be days without work).

RULE 4 - The game is NOT player-friendly
  Wrong decisions are punished.

RULE 5 - Violence and frightening scenes
  The game contains violent language and frightening scenes.

RULE 6 - Everyone works directly on main
  No branches, no cloning around. Only read and write directly.
  To prevent collisions:
  - Claude is the coordinator. Only prompts written by the coordinator are sent to Codex.
  - The coordinator makes sure no two AIs work on the same file at the same time.
  - Before every task: git pull. After every task: commit and push immediately.

RULE 7 - Ask about EVERYTHING that is not clear
  Anything that is not unambiguous gets asked. The owner makes the decisions.
  - No guessing, no "I assumed that...".
  - If the work has to wait for a decision, it waits.
  - Open questions go into the section "Open questions for the owner" of today's handover file.

RULE 8 - Everything is judged objectively
  When Grok, Claude or Codex changes something, the file is treated as if it were your own.
  No "the other AI did that". You own it and you fix it.

RULE 9 - Anything needed comes from the owner
  From assets to dialogue decisions: the owner is asked.

RULE 10 - Everyone should have fun with this project
  If this is not the case, it is MANDATORY to say so - or to make suggestions that make the
  project more fun.

RULE 11 - Say it BEFORE you start if another AI can do the task better
  If you think another AI can do a task better - for example images, videos, code or other
  assets - you MUST say so BEFORE you do anything.
  - Name which AI and why.
  - Then wait for the owner's decision (Rule 7).


COORDINATOR DUTIES (Claude)
---------------------------
- At the start of every session: git pull, then read the newest file in handover/.
- Plan the work and split it into tasks.
- Write the prompts for Codex. Only these prompts are sent to Codex.
- Make sure no two AIs ever work on the same file at the same time (Rule 6).
- At the end of every task: commit, push, and log it in today's handover file (Rule 3).


HANDOVER FORMAT
---------------
# Handover DD-MM-YYYY

## Current status
Short summary: where does the project stand right now?

## Open questions for the owner
- [ ] question (mark answered ones with [x])

## Log
One entry per task. Newest at the bottom.

### HH:MM - <Claude | Codex | Grok>
- Task:
- Changed files:
- What was done:
- Notes / next step:
