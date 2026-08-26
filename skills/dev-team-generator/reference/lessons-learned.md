# Lessons learned

Each entry below cost something to learn — a live verification, a near-miss,
or an actual incident — before it became a rule. They're written generalized
(not OpenCode-specific) so they apply to whatever tool ends up dispatched.
When you port one of these into a generated file, port the *mechanism and
the reason*, not any tool-specific flag name that happens to appear here as
the worked example.

## 1. A "wide auto-approve" flag is opt-in per task, never a standing default

Many non-interactive CLI tools have some flag that auto-approves anything
not explicitly denied, instead of hanging forever on a permission prompt
nothing can answer (OpenCode's `--auto` is the worked example this toolkit
verified live). That flag is genuinely useful — it's what ends the
"dispatch hangs on an un-allowlisted command, someone notices, widens the
allowlist, retries" cycle — but it is also, by the tool's own admission
usually, "dangerous."

- Default is off.
- Turning it on for a task is the **user's** call, asked explicitly, bundled
  into whatever approval gate already exists (don't invent a second
  interruption point for it) — never the lead's or implementer's own
  judgement call, not even after a timeout.
- **A very large task compounds this risk rather than just scaling it** — a
  wide, hard-to-review diff plus unattended permission approval across all
  of it, at once. Before asking about the flag on a task that looks very
  large (many files or subsystems, several unrelated acceptance criteria),
  ask the user first whether to split it into smaller tasks run through the
  pipeline one at a time, or proceed as a single task. Same judgement call
  as above: the lead sizes it, the user decides.
- **Verify live, before trusting it, that the tool's own explicit deny-list
  still blocks even with the flag on.** Don't take the tool's docs' word for
  it. The verification this toolkit did: dispatch a throwaway agent with a
  deny-listed command, turn the auto-approve flag on, confirm the call is
  still refused and the refusal names the specific deny rule. If a tool's
  auto-approve flag turns out to bypass its own deny-list too, that's a
  materially different (and worse) risk profile than what's described
  above — find out before recommending it, not after.
- Record which tasks had it on, and why, in the state file — not just in
  the dispatch command.

## 2. A killed dispatch may not be a finished dispatch — check before reusing its session

If the dispatched tool has any concept of a server-side session/turn that
outlives the CLI client process (OpenCode's `--attach` sessions are the
worked example), then killing the *client* does not necessarily cancel the
*turn*. A killed-but-not-cancelled turn can leave an orphaned
in-progress message with no completion marker — and reusing that session
for the next call risks two calls racing on it, which is a real, previously
observed failure mode (two writes racing on the same session produced a
collision that looked like an unrelated server error).

- Bound every dispatch with a hard wall-clock timeout.
- On a timeout **your own wrapper caused**, actively cancel the server-side
  turn if the tool exposes a way to (an abort/cancel endpoint or command),
  using whatever session id the wrapper can determine — verify this live:
  confirm the cancelled turn actually shows as completed/aborted afterward,
  don't just assume the cancel call succeeding means the turn stopped.
  Once verified, retrying the same session immediately is safe.
- On a dispatch that was killed **some other way** — interrupted by hand,
  the host process manager stopped it, the machine slept — the same
  orphaned-turn risk applies but your wrapper's own auto-cancel-on-timeout
  logic never ran. Check the session's actual state (or just cancel it
  unconditionally, if that's cheap and idempotent) before reusing it. Don't
  assume "it's not running anymore because nothing is polling it" —
  verify, the way this toolkit verified via the tool's own session-state
  API: fetch the last message, confirm it either completed normally or
  show it explicitly aborted, before sending the next one into that
  session.

## 3. Don't assume a CLI streams its own output incrementally — verify before building anything that depends on it

An idle/no-output watchdog (kill a dispatch if its output file hasn't grown
in N seconds, on the theory that "no output" means "stuck") is an
attractive-looking hardening pattern. It is **only safe if the underlying
tool actually flushes output incrementally as it works.** This toolkit
built one, tested it against a synthetic harness (passed), then tested it
against the *real* installed tool doing genuinely long, successfully
progressing work — and found the tool's own CLI batches all output until
the entire turn completes, even with an explicit line-buffered format flag
and OS-level `stdbuf` forcing. The output file sat at zero bytes through
over a dozen seconds of real, correct work. Deploying the watchdog as
designed would have killed every long-but-successful run, which is strictly
worse than the flat timeout it was meant to improve on.

- If you're about to build anything whose correctness depends on "this
  tool streams output as it goes," check that assumption against the
  actual installed version of that tool, with genuinely long real work, not
  a quick synthetic test — synthetic tests can pass on the logic while the
  underlying I/O assumption is still wrong.
- If it turns out not to stream incrementally, a flat timeout (bounded,
  simple, no false-positive risk) is the better and current design — say so
  plainly rather than shipping the fancier mechanism anyway.
- If you do find a tool that streams incrementally and want to build an
  idle-watchdog for it, re-verify against that tool's actual version before
  reusing this note as precedent — the finding above is tool-and-version
  specific, not a general property of CLI tools.

## 4. Implementer testing: scoped to fast/deterministic, not banned, not unlimited

Don't swing to either extreme:

- **Not a full ban.** A deterministic local check (a type check, a linter,
  a test suite that runs in seconds) is cheap — CPU-seconds, not a paid
  LLM call — and catching an obvious break before it ever reaches the
  reviewer/tester saves a whole loop. Banning it outright optimizes for the
  wrong cost.
- **Not unlimited either.** Slow, environment-heavy suites (full e2e,
  integration against real external services) are the dedicated tester
  role's job, run once, independently, as the record the state file
  trusts. The implementer's own local run is informational — it does not
  replace the tester's run, and should say so explicitly in its own report
  rather than implying its self-check is the verified result.
- The actual distinction driving this: avoiding a second *paid agent
  call* re-verifying what the first one already claimed is the thing worth
  being economical about (per this skill's "verification is a script, not
  a sixth agent" principle) — a second **script run** is not that, and
  reasoning about the two as if they were the same cost is how this rule
  gets over-tightened into a full ban that then has to be walked back.

## 5. Not every reviewer finding is worth a full implementer loop

`CHANGES_REQUESTED` is the default routing back to the implementer — but a
finding that names no concrete code defect (e.g. "I can't confirm this
platform API is supported on the actual target from the docs I checked,
verify before shipping") isn't something a code change can address. Sending
it back anyway burns a review-loop slot on a call the implementer has no
action for.

- If a finding is genuinely non-actionable as a code change, route it to
  wherever it *can* be resolved instead (usually: the test/verification
  step, as an explicit thing to check against the real target) — but do
  this transparently, logged in the state file with the reasoning, not by
  silently downgrading the verdict. The user should be able to see and
  disagree with the call.
- This is a judgment call the lead makes on the evidence in hand, not a
  license to wave away a finding that's inconvenient — the bar is "no code
  change could address this," not "this seems minor."

## 6. Check for a real test harness before assuming only manual verification is possible

"No browser/runtime on `PATH`" is not the same as "no way to drive a real
instance of the target." A project may already have a managed/bundled
runtime (a test framework's own downloaded browser binaries, a container
image, a local emulator) that a plain `which <tool>` check won't find,
because it isn't meant to be found that way — and the project may already
have a *working* automated-testing convention for exactly this (an existing
`e2e/` directory, a CI config, a documented manual-checklist policy) that a
fresh dispatch, working from a narrower prompt, won't discover on its own.
Before concluding "this needs the user's own hands," check: does this
project already have automated infrastructure for driving the real target,
and does the current task's verification need actually fit what that
infrastructure can reach? If yes, use it — a real automated check against
the actual artifact is stronger evidence than asking a human to click
through the same thing by hand, and is worth the extra effort to wire up
correctly (get the exact selectors/shape right by reading the actual
generated UI/output, not by guessing).

## 7. Non-destructive scaffolding, with a path to reconcile later

Never silently overwrite a file the user or a prior run may have
customized. Skip-if-exists is the safe default for first generation; for a
later re-run against a project that's drifted from what this pipeline would
now generate, offer a diff-only mode — render the current version to a
temp location, `diff -u` against the live file, write nothing — so the
human (or an agent working with the human) can merge deliberately instead
of either blindly overwriting or blindly staying stale forever.

## 8. First-run, project-specific customization: ask once, then never again

A freshly generated pipeline's role/flow files start out generic — they
don't yet know this project's own sharp edges (a hard rule that isn't in
the root guidance file yet, a permission boundary worth calling out
explicitly). Rather than leaving that gap open indefinitely or re-asking
every run, gate a single customization prompt behind a marker written only
on first generation (never on a later re-run/update) and cleared only once
the human answers it. This keeps the ask-once property without needing
anything heavier than a marker file.

## 9. "Receipt not record" applies role-to-role — and is worth extending to the lead's own report, deliberately, not by default

Every worker role's reply to the lead should be short: a verdict line, a
pass/fail count, the one-line handoff field — never a second copy of what
it already wrote to the state file. This is settled and load-bearing (see
`reference/flow-example.md`).

Whether the **lead's own report to the human** should get the same
compression is a live, unresolved question this toolkit has raised but not
settled — the human is not re-reading a state file the way the next role
is, so some of the state file's content genuinely needs to reach them
somewhere, and over-compressing that report risks hiding the "blocked,
unverified, or needs a decision" signal the human actually needs to act on.
If you're generating a lead flow and asked to tighten its human-facing
report, treat this as a real design decision to make with the user, not an
obvious extension of the role-to-role rule — get their answer on what to
keep versus compress before changing it.

## 10. In a permission map, prefer enumerated-safe over broad-allow-with-narrow-denies

A permission map shaped like `"tool *": allow` plus specific
`"tool dangerous*": deny` exceptions only blocks the dangerous calls if
the runtime resolves narrow rules over broad ones — first-match,
most-specific-match, and last-match-wins are all real designs, and a map
that reads correctly under one precedence rule silently fails under
another. This is the same class of assumption as verifying permission
enforcement live, but at the within-one-map level: even a runtime that
enforces *some* deterministic ordering can enforce a different one than
the file's visual order implies.

- Prefer enumerating the safe commands explicitly (the read-only verbs
  the role's rhythm actually needs) and letting everything else fall
  through to "ask" or the tool's equivalent. The safe path then never
  depends on precedence at all — there is no broad allow for a narrow
  deny to outrank.
- Keep the explicit denies anyway, even when they look redundant under
  the "ask" catch-all: wide auto-approve flags (entry 1) typically
  bypass "ask"-level entries while still honoring explicit denies, so
  the denies are what holds with the flag on.
- If a role genuinely needs broad access plus exceptions, that is a
  live-verification requirement, not a config detail: dispatch it, make
  it try the denied thing, confirm the refusal names the deny rule.

## 11. Anything a script writes from agent-authored content gets its paths treated as untrusted

When a deterministic script copies or writes to a path that originated in
agent-written state (a findings line naming a doc, an output location a
role chose), that path is untrusted input even with no adversary in the
loop — a confused agent is enough. `../..` segments or absolute paths let
a well-meaning finding write outside the repo, defeating whatever
write-scoping the pipeline set up everywhere else.

- Refuse absolute paths and any `..` path segment; skip loudly rather
  than silently normalizing.
- Anchor the script itself to the repo root (the way dispatch wrappers
  do) so relative paths have exactly one meaning no matter the caller's
  CWD.

## 12. A contract nobody closes is a pipeline that can't say what it delivered

Acceptance criteria are the whole point of the spec — and it is startlingly
easy to build a pipeline where **nobody ever records whether one was met.**
This toolkit shipped exactly that: the planner wrote criteria as checkboxes,
one rule said no other role may edit them, no role was told to tick one, the
tester never read them, and the final report asked the lead for "criteria met
versus outstanding" with no artifact behind that answer. Every role did its
job and the contract still never closed.

- Give the criteria a **ledger**: one row each, with the reviewer's citation
  (`file:line`) and the tester's (which test) in **separate** columns.
- **Split ownership of text and outcome.** The planner owns the criterion's
  wording and may not record outcomes; the lead owns the outcome and writes
  nothing but what the reviewer and tester already put in the file; the
  implementer may never mark its own work met.
- **A tick requires both evidence cells.** No evidence, no tick —
  "unverified" is a true, useful answer, and a tick that hides it is the
  exact failure this prevents.
- Have the structural check **refuse the terminal status** while any
  criterion is unticked and unwaived. That single check is the difference
  between a pipeline that produces work and one that can tell you what it
  produced.

## 13. Every status needs exactly one owner, or the field rots silently

A status enum is cheap to write and easy to leave half-wired. This toolkit
shipped **eight** status values of which only **three** were ever set by any
role — including the terminal `done`, which nothing set at all, while a
separate status-board rule said "only check off a task once its status
reaches done." That rule could never fire. Worse, the two implementers
disagreed: one set a blocked status on an open question, the other just
stopped, so the same event left the ledger in two different states depending
on which vendor ran.

- Write a **transition table** into the state-file template itself: status,
  who sets it, on what event. One row per value, no exceptions.
- Then check the obvious consistencies in the structural script (test
  results present ⇒ status is at least "testing"; terminal status ⇒ the
  contract is closed). Cheap greps, and they catch the drift that makes
  every downstream reader — board, script, human — inherit a stale value.
- **Duplicated roles must transition identically.** If two tools run "the
  same role," diff their instructions for status handling specifically; it
  is the first thing to diverge and the last thing anyone notices.

## 14. Budget every path back to the implementer, not just the one you thought of

A review-loop cap is the obvious anti-thrash rule and most designs have it.
The paths that get forgotten are the other ways the same implementer gets
re-engaged: **test failures** (fix → test → fail → fix …) and **spec
defects**. This toolkit capped review loops structurally — a script failed
loudly on a third review pass — while test failures routed back "as a new
loop" with no cap, no counter, and no check. A flaky suite plus an eager
implementer could cycle forever and nothing in the system would notice,
because the only budget in the file counted review passes.

- Enumerate **every** edge that re-engages the implementer and give each one
  a counter in the state file, with the cap written next to the count
  (`0 / 2`) so the reader needs no outside knowledge.
- Have the structural script parse and enforce them. A budget with nothing
  counting it is not a budget, it is a sentence in a document.
- Blowing a budget is an **escalation to the human**, never a reason to keep
  looping — two failed laps means the spec is wrong, the suite is wrong, or
  the environment is, and none of those are fixed by a third lap.

## 15. Give a bad spec a way back to the planner, not only up to the human

If the implementer's only options are "comply" or "stop the world," every
spec defect — including trivially mechanical ones — costs a human
interruption. Real teams return the ticket to whoever wrote it.

- Add a **bounce**: the implementer records concretely which criterion or
  scope line is unbuildable and why, sets a distinct blocked status, and the
  lead re-dispatches the **planner** once with that objection.
- **Cap it at one.** A second rejection is no longer a planning problem, it
  is a "we don't agree what this task is" problem, and that is the human's
  to settle.
- Keep the two blocked states distinct (waiting-on-human vs bounced-to-
  planner). One undifferentiated "blocked" cannot tell a status board — or
  tomorrow's session — which of the two it is looking at.

## 16. A stopped task needs to say what it is waiting on, and since when

"Do not proceed on silence" is the right rule at an approval gate, and it
quietly assumes the human is about to answer. When they are not — overnight,
next week — the pipeline just stops, and if the pending question lives only
in the lead's conversation, a resumed or fresh session cannot tell what the
task is parked on. The state file is the only thing that survives; the
conversation is not.

- Record **what** it waits on (prefix the open question `[human]` /
  `[planner]`) and **since when** (a dated field), in the state file and the
  status board, at the moment you stop.
- This costs one line and is the difference between a task that resumes and
  a task that silently dies at a gate nobody remembers opening.

## 17. Independence of *opinion* is not independence of *evidence*

Switching the reviewer to a different model family is a real control, and it
is the one everyone implements — this toolkit put it on its own front page.
It buys an independent **opinion** about the diff. It buys **nothing** about
the tests: if the implementer wrote them, a green run confirms only that the
code matches its author's own idea of correct. That is a weaker claim than
the pass count implies, and no reader can tell the difference unless the file
says so.

- Make the tester **read the acceptance criteria** — a suite that exercises
  none of them is not evidence, however green.
- Require an **AC → covering test → result** table, and an explicit list of
  criteria **no** test covers. An uncovered criterion is a finding, not a
  silence.
- Require a **test-authorship line** (`implementer this task` /
  `pre-existing` / `tester`). One field, and it tells every later reader how
  much the green is worth.
- Never let the tester edit a test to make it pass. If a test looks wrong,
  that is a finding for someone else to act on.

## 18. A second review pass must close the first, not restart it

A loop cap only guarantees convergence if each pass is *about* the previous
one. Nothing stops a reviewer from returning an entirely new set of findings
about untouched code on pass 2 — and when that happens the cap stops being a
convergence guarantee and becomes an arbitrary cutoff: the pipeline stops
because it ran out of loops, not because the work converged. This is the
oldest pathology in human code review (moving goalposts) and it transfers
intact.

- Require each later pass to **close every earlier finding by number**:
  fixed / withdrawn / disputed / routed elsewhere. An unmentioned finding is
  treated as withdrawn.
- Admit findings about **code the diff didn't change** on a later pass only
  at the top severities. Smaller ones go to the findings-for-docs path.
- Point the reviewer at the implementer's **decisions/reasoning log**, not
  only the diff. If the implementer is told that unwritten disagreement
  resolves against it, something must actually read what it writes —
  otherwise the disagreement channel is theatre, and the author learns to
  stop using it.
- Have the lead **write down each adjudication** (finding number, which way,
  why). An adjudication living only in the lead's context cannot be
  appealed or audited, and does not survive a compaction.

## 19. Check the spec with a script too, not just the code

Code gets review passes; the spec that every downstream role treats as the
contract typically gets one glance from the human least equipped to notice a
missing criterion, an over-wide file scope, or an empty permissions table —
because all they see is the planner's own summary of the planner's own work.

Most spec defects are **structural**, which means they are greppable and do
not need an LLM: boilerplate left unfilled, zero criteria (or more than the
role's own splitting threshold), a criterion built on an adjective
("robust", "works well", "properly") rather than an observable, an empty
scope table, a permissions table that is neither filled nor explicitly
"none", a ledger row missing for some criterion.

- Write the spec-checker as a sibling of the state-checker and run it before
  the human sees the spec. Same principle as "verification is a script, not
  a sixth agent," applied one step earlier in the pipeline.
- Keep it to **structure, never quality** — it cannot tell you a criterion is
  wrong, only that it is missing or unmeasurable on its face. Judging whether
  the spec is *right* stays the human's job at the approval gate; the script
  just guarantees they are looking at a finished spec.
- A spec defect caught here costs one planner call. The same defect caught
  after implementation costs a full implement→review loop.

## 20. The role that decides scope needs the minimalism rules most

Behavioral defaults — simplicity first, surgical changes, state assumptions,
verifiable success criteria — get inlined into the implementer, because that
is where code gets written. This toolkit did exactly that for both its
implementers and gave the **planner** none of them. But the planner decides
*what gets built at all* and *how wide the file scope is*: work never scoped
costs nothing to implement, review, or test, and removing a file from scope
during planning is free where discovering it was unnecessary in review costs
a loop.

That is a leverage inversion — the cheapest place to remove work had the
fewest rules about removing it.

- Inline the same behavioral defaults into the planner, phrased for scope
  rather than code.
- Add two fields the human reads at the approval gate: **the simplest
  version considered** (and why the spec is bigger), and **the blast
  radius** (what breaks if this is wrong). Both are things a good planner
  already reasons about; the fields make that reasoning reviewable instead
  of internal, and give the human something concrete to push back on other
  than the planner's own framing.
