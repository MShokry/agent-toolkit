---
name: status-board
description: Keep a project's top-level status board in sync with per-task state files in a planner/implementer/reviewer/tester pipeline. Load alongside `delegate` in the lead's own session, or apply this prompt manually in a project that already has a per-task state-file pipeline without the rest of this toolkit.
---

# Status board

A per-task state file (`.agents/T-<id>.md`, or whatever a project calls it)
is easy to keep current — each role updates its own file as it works. The
project-wide status board (a top-level `README.md`, `STATUS.md`, or
`TASKS.md` checklist) is not: nothing forces anyone to open every task file
and roll the status up, so it silently drifts, and answering "what's the
current state of everything" means reading every task file by hand.

This skill is the fix. It is independent of `init.sh` — usable in any
project with a per-task state-file pipeline, this toolkit's or not.

## The rule

Whenever a step in the task pipeline finishes (spec approval, implement,
review, test — any point where a task's `Status:` field changes), update
the project's top-level status board **in the same turn, before moving
on**. Do this every time, not only when a task reaches its final state.

The status board is a single table — one row per active task: task id
(linked to its state file), title, current `Status:` value, and which item
in the longer-term plan/checklist it corresponds to (find the mapping by
keyword, not by assuming a 1:1 order). A reader should get the total status
of every in-flight task from this one table, without opening any other
file.

Only check off a box in a longer-term plan/checklist once the corresponding
task's `Status:` actually reaches its terminal "done" value — not when
review merely passes, not when implementation merely finishes. A task that
is reviewed-but-not-tested, or tested-but-unmerged, is still in progress;
its checklist box stays unchecked and its status board row says so
explicitly (e.g. "in-review (changes requested)", "testing", "in-review
(PASS, awaiting merge)") rather than going silent.

**This rule only works if something actually sets the terminal status.**
Check that before relying on it: a pipeline where no role is told to set
`done` — which is easy to ship and hard to notice — makes this rule
unfireable, and the board then silently under-reports every finished task.
One role owns each status value; if you can't name which role sets the
terminal one, fix that first (see the state-file template's own transition
table if it has one).

Distinguish *why* a task is blocked in its row, too — waiting on a human
decision is a different thing from bounced back for a re-plan, and a board
that shows both as plain "blocked" can't tell you which ones you personally
are holding up. Include how long it has been parked; that is the number that
makes a stalled task visible.

If a task's real-world scope doesn't map to any existing checklist item
(new work discovered mid-project, not in the original plan), say so in the
status board row instead of leaving it blank or forcing a fit.

## Applying it

1. Find the project's top-level status/README file and its per-task state
   files.
2. Add an "Active tasks" table to the status file: task id, title, live
   `Status:`, checklist-line mapping.
3. In this project's pipeline instructions (`.claude/commands/feature.md`
   if scaffolded from this toolkit — see that template's step 5, "Report",
   for where the line goes), add one line to every step that currently says
   "report to the user" or "merge": update the table first, every time —
   not just at the end.
