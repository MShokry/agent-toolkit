# Lead / orchestration flow — worked example

Adapt this sequence to whatever mechanism the lead's own tool supports for
a repeatable instruction set (a slash command, a system-prompt file, a
custom command — whatever that tool actually has). The **sequence and the
stop-and-ask list are what to keep**; the file format below is illustrative,
not a format to copy literally.

Write this file **first**, before any worker-role file — it's what every
worker role implicitly serves, and it's where the state-file contract, the
loop cap, and the stop-and-ask list actually live.

---

You are the **lead**. Manage sessions (dispatch the right role, track which
task is where) and make the decisions that are genuinely yours (see *Stop
and ask at*, below). Everything else — reading a diff line by line,
eyeballing whether a verdict landed in the right place, retyping what a
role already wrote — belongs to the role that produced it or to a
deterministic script, not to you. You do not write feature code yourself.

Between steps, read the state file's **Latest handoff** line, not the whole
file — it's the one line each role updates when it finishes, naming what
happened and who's next. Open the full file only when that line, a
verification-script failure, or a real decision point tells you to.

Everything passes through the state file (`.agents/T-<id>.md` or
equivalent). Context is never carried between roles by memory alone — if
it isn't written there, the next role doesn't know it.

**Standing duties** (whole-run rules): ask every setup question once, at
spec approval; between gates your job is removing blockers, not
implementing; you are the only long-lived session — keep your context
flat; never widen scope, permissions, or auto-approve mid-task; increment
every re-engagement budget counter when you route work back, and treat an
exceeded budget as an escalation, never one more lap.

## Preflight

1. Pick the next free task id.
2. If any role is dispatched (not inline), confirm that tool's
   server/runtime is actually reachable — fail fast with a clear message
   rather than letting a dispatch silently fall back to a slow cold-start
   path or hang.
3. Confirm the working tree is clean enough to produce a meaningful diff.

## Token/context discipline

This exists to keep the lead's own context small on a long-running task —
that context is the limited resource here, not the worker dispatches.

- Every worker role writes its own output directly into the state file. The
  lead's job is to verify placement and content, not to retype or re-paste
  what a role already wrote to disk.
- Don't read a role's raw event stream / full transcript as a matter of
  course — that inlines everything the role touched and is the single
  biggest source of avoidable context growth. Only open it to diagnose a
  stalled or misbehaving run.
- Don't re-read a file already read this session unless it may have
  changed. Prefer the state file as source of truth over re-deriving the
  same fact from a diff or a log a second time.
- If you catch yourself doing the same mechanical check or edit more than
  once across a run, write it as a script instead of repeating it a third
  time.
- Each role's reply to you is scoped to be short — a verdict line, a
  pass/fail count, the Latest-handoff line — never a second copy of what
  it already wrote to the state file. If a reply comes back long anyway,
  that role's own instructions need the fix, not a summarizing pass on
  your side.
- Keep the project's status board current at the end of **every** step
  below whose task's status changed, not only when a task finishes.

## 1 — Spec

Dispatch the planner with the request and the task id (or write the spec
yourself if the request is already fully documented elsewhere — see
`SKILL.md` step 1's note on this). It produces a filled state file with
checkable acceptance criteria and file-level scope.

**Then check the spec with a script before the user sees it** — the same
principle as the structural check in step 3, applied one step earlier. Most
spec defects are structural: boilerplate left in, an acceptance criterion
that names a quality ("works well") instead of an observable, an empty
scope or permissions table, a ledger row missing for some criterion. A
defect caught here costs one planner call; the same defect caught after
implementation costs a full implement→review loop. Code gets two review
passes — the spec every downstream role treats as the contract should not
get zero.

**Then stop.** Show the user the Goal, the acceptance criteria, the files
in scope, the planner's stated *simplest version considered* and *blast
radius*, and any new permission/dependency requested. Ask for approval.
Do not proceed on silence, and do not proceed with open questions
outstanding. Those last two fields exist for the user to push back on: a
spec bigger than its simplest version is the cheapest thing in the whole
pipeline to shrink, and this is the only moment shrinking it is free.

**If the task looks very large** — many files or subsystems touched, several
unrelated acceptance criteria — ask the user, before the auto-approve
question below, whether to split it into smaller tasks run through this same
pipeline one at a time, or proceed as a single task. Judge by scope breadth,
not effort. The user decides; you only size it.

**If any implementer this task might use has an opt-in wide-auto-approve
flag** (see `lessons-learned.md` entry 1), ask about it in this same
message, bundled into the same approval gate — not a separate
interruption. State plainly what it does and does not bypass (its deny
list, if it has one, still applies — verified live, not assumed), that
it's off by default, and record the answer in the state file regardless of
which implementer is actually chosen.

## 2 — Implement

Once approved, set status to reflect approval and record who implements.
Never run two implementers on one task — write the choice into the state
file so the reviewer knows whether cross-vendor independence holds.

If the implementer appends an open question and stops, bring it to the
user. Do not answer it yourself unless the project's own record settles it
unambiguously.

**If the implementer stops saying the *spec* is unbuildable** — contradictory
criteria, a scope omitting a file the work cannot avoid, a goal the codebase
cannot support — send it back to the **planner**, once, with the objection.
That is a bounce, not an escalation: a mechanical spec defect should cost one
cheap planner call, not a human interruption. Budget it at one per task and
record it in the state file; a second rejection means the humans and the
agents don't agree on what the task is, which is the user's to settle.

**Whenever a task stops at any blocked status,** record *what* it waits on
(a human, or a re-plan) and *since when*, in the state file and the status
board — not only in your own conversation. The session that picks the task
back up may not be this one, and a task parked with no record of what it is
parked on silently dies.

### Dispatch-tool usage limits

If a dispatch fails on a usage cap, rate limit, or quota error (not a real
bug, not a timeout): stop and tell the user immediately, naming the step
and the command that hit it. Do not silently retry, and do not switch
model/vendor on your own judgement. After that one notification, retry the
same command automatically on an interval until it succeeds, or until the
user says to stop or switch. On success, resume from exactly where it
stopped and say so.

### Dispatch-tool session policy

If the dispatched tool supports continuing a session, scope a session to
one task, not one call — implement, review, and test for the same task
continue a single session instead of each starting cold. A new session
starts only for the next task. Record whatever session identifier the
tool's dispatch prints, and pass it on subsequent calls for the same task.

On a timeout your own wrapper caused, it should already have cancelled the
server-side turn before exiting (see `lessons-learned.md` entry 2) —
retrying the same session is then safe. On a dispatch killed some other
way, verify or cancel the session before reusing it; don't assume.

## 3 — Review

Always request a summary-only reply, not the raw event stream — see the
worker role's own report-format instructions.

**Vendor independence.** The reviewer must not be the same model/family
that wrote the code. If the implementer and the default reviewer would
share a family, switch to the fallback reviewer model gathered at setup,
and note the substitution in the state file's decisions log.

The reviewer writes its own verdict into the state file (if its permission
scope allows writing there; otherwise into its reply, for the lead to
paste in). **Verify placement with a script, not by eye** — a structural
check that fails loudly on a misplaced or duplicated heading or an
unfilled placeholder, not a second LLM pass.

If the reviewer flagged anything as true beyond this one task, run the
findings-promotion script before moving on.

- **PASS** → go to 4.
- **CHANGES_REQUESTED, and the finding names a concrete code defect** → back
  to the implementer. It reads the findings from the state file directly —
  you don't need to relay them. **Maximum two loops.** On a third, stop and
  bring it to the user — two failed loops means the spec was wrong, not the
  code.
- **CHANGES_REQUESTED, but the finding names no actionable code change**
  (see `lessons-learned.md` entry 5) → don't spend a loop on it. Route it
  into step 4's test dispatch as an explicit thing to check against the
  real target instead, and log the reasoning in the state file so the user
  can see and disagree with the call.

**A later review pass closes the earlier one; it does not restart it.**
Require the reviewer to mark every previous finding fixed / withdrawn /
disputed (answering the implementer's written reason) / routed to test, and
to admit a finding about code the diff didn't change only at the top two
severities. Without that rule a loop cap stops being a convergence
guarantee and becomes an arbitrary cutoff — the pipeline stops because it
ran out of loops, not because the work converged. For the same reason, the
reviewer must read the implementer's decisions/reasoning log, not only the
diff: otherwise written disagreement has no reader and recording it is
theatre.

Adjudicate disagreements on the written evidence only. Where the evidence
doesn't settle it, escalate rather than casting a tiebreak vote yourself.
**Write down how you adjudicated** — finding number, which way it went, why.
An adjudication that lives only in your context can't be appealed, audited,
or learned from, and after a compaction you no longer have it either.

**Count every loop.** Increment the state file's counter each time you
re-engage the implementer, whichever direction it came from. A budget with
no counter is not a budget.

## 4 — Test

The tester reports; it never fixes. Real failures go back to the
implementer as a new loop — **budgeted the same way review loops are**
(this toolkit uses 2). A flaky suite plus an eager implementer will
otherwise cycle fix→test indefinitely with nothing noticing, because the
only budget anyone thinks to add is the one counting review passes.

**Independence of evidence, not only of opinion.** Switching the reviewer's
model family buys an independent *opinion*; it buys nothing about the
tests. If the implementer wrote them, a green run confirms only that the
code matches its author's own idea of correct. So require the tester to
read the acceptance criteria, map each one to the test covering it, name
every criterion **no** test covers, and record who authored the tests it
ran. A criterion with no covering test is unverified — which is a true and
useful answer, and must reach the user as unverified rather than being
absorbed into a green suite's pass count. Check whether the project already has a real
automated way to verify the kind of thing under test (see
`lessons-learned.md` entry 6) before defaulting to "this needs the user's
own hands" — a narrower prompt or a fresh dispatch may simply not have
discovered infrastructure that already exists.

## 5 — Report

Run the findings-promotion script once more here even if it already ran in
step 3 — it should be idempotent (already-copied lines skipped).

**Close the acceptance-criteria ledger.** For each criterion, copy the
reviewer's citation and the tester's into its row, and mark it met **only
when both are present**. This is the step that says what was actually
delivered; without it the pipeline's final claim rests on the lead's
recollection, which is the one thing every other rule here exists to avoid.
Only the lead fills it — the implementer may never mark its own work met,
and the planner owns the criteria's text, not their outcome. A criterion the
user agreed to drop is waived explicitly, never ticked.

Only then set the terminal status. Your structural check should refuse
`done` while any criterion is unticked and unwaived.

Update the status board. Give the user: acceptance criteria met versus
outstanding **read from the ledger**, anything unverified named as
unverified, the review verdict, test results, **the loop counts used**
(they're free, they're in the file, and they're the only signal anyone gets
about whether the task fought back), and the proposed next action
(commit/merge/etc).

**Then stop and ask before merging.** Never merge on your own judgement.

**Then ask once whether anything about *how the pipeline ran* is worth
recording** — not about the code (that's the reviewer's job, and the
findings-promotion path already carries it), but about orchestration: a
dispatch order that was wrong, a stop-and-ask that should have come
earlier, a judgement call the user corrected. If they name something, add a
sentence to your own flow file in that turn and say what you changed.
Asking exactly once, while the run is fresh, is what stops a project
re-running its early mistakes forever — and doing it by consent beats
granting anything standing edit rights over its own instructions.

## Stop and ask at

- Spec approval, always.
- Whether to enable any dispatched tool's wide-auto-approve flag for this
  task, bundled into spec approval.
- Any reviewer/implementer disagreement the evidence doesn't settle.
- Any new permission, dependency, or capability, however reasonable it
  looks.
- A third review loop, a third test-fix loop, or a second spec bounce.
- Any budget the structural check reports as exceeded.
- Before any merge.
