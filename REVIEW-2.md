# Review 2 — the pipeline as a delivery organization

Third pass over `agent-toolkit`. `REVIEW.md` holds the first two (a
code/tooling pass, then an org-chart pass). **This file deliberately does
not repeat either** — where a finding here touches one of theirs, it says
so by id (`O1`…`O7`) and either extends or re-ranks it rather than
restating it. Part D at the bottom is feedback *on* `REVIEW.md`: what to
act on, what to neglect.

**Lens:** two questions, both asked from outside the code.

1. *Delivery.* The stated goal is "send a task to the team, get work back
   you can trust." Does the machine actually close that loop, or does it
   stop one step short?
2. *Harmony.* Read as a manager reading their own org: who is allowed to
   say no, who has to answer whom, where does a disagreement go to die.

**Method:** full read of every template, skill and doc, plus targeted
greps to test each claim before writing it down. Every finding below cites
the evidence that proves it. Nothing here is a style opinion.

Legend: ⬜ `[OPEN]` · ✅ `[DONE]` · 🔶 `[REC]` awaiting your call.

---

## Verdict, stated plainly

**The process design is strong. The delivery contract is not closed.**

This toolkit gets the hard parts right — one ledger, disjoint write
scopes, receipts-not-records, verification-as-script, honest documentation
of its own failures. Those are earned, and Part 2 of `REVIEW.md` is right
to call them harmony assets.

But trace one task end to end and a gap opens at the finish line. The
planner writes acceptance criteria as checkboxes. **Nothing in the system
ever ticks one.** No role is told to, one role is explicitly forbidden
from touching them, the tester never reads them, and `verify-state.sh`
never asks about them. The pipeline's final act is a lead *narrating* to
the user which criteria it believes are met — from memory, mid-run, with
no artifact backing the claim and nothing that would fail loudly if it
were wrong.

So on the "100% accurate" ambition, the honest read is this:

> Accuracy here comes from the **gates** (an independent reviewer, an
> independent tester, a human at spec and merge), not from the agents.
> The gates are well designed. What is missing is the **evidence ledger**
> that proves a gate was actually passed — and without it, the last mile
> of the pipeline runs on an agent's word, which is the one thing the rest
> of this toolkit is architected never to do.

That is the whole of D1–D3 below, and it is where the leverage is. Adding
roles, models or loops will not move accuracy. Closing the contract will.

---

# Part A — the delivery gap

## ⬜ D1 — Nobody closes the contract *(the headline finding)*

**Evidence.** `templates/agents-state/TEMPLATE.md.tmpl:36` defines
acceptance criteria as `- [ ] AC1 —`. A repo-wide grep for `- [x]`, "check
off", or "mark the criteri" returns **no instruction to any role**. Line
34 says "**No other role may edit them**" — which, read literally, forbids
the implementer and reviewer from even recording an outcome.
`feature.md.tmpl:334` then asks the lead for "acceptance criteria met
versus outstanding" with no stated source for that answer.

**Why it matters.** The acceptance criteria are the *only* thing in this
system that defines done. Everything else — the diff, the verdict, the
test run — is evidence *toward* them. Leaving them permanently unticked
means the ledger records the work but never records the judgment, and the
one summary the human actually reads is the one artifact nobody verified.
It is the multi-agent equivalent of a team with immaculate tickets that
nobody ever moves to Done.

**Fix (small, and it is the highest-value change in this review).**

1. Split the rule at line 34 into two: the planner owns the AC *text*
   (unchanged, still nobody else's to edit); the **lead** owns the AC
   *outcome*.
2. Add an evidence column so a tick is never an opinion:

   ```markdown
   ## Acceptance criteria ledger   (outcome: lead only; text: planner only)

   | AC | Met? | Reviewer evidence | Test evidence |
   | -- | ---- | ----------------- | ------------- |
   | AC1 | [x] | Pass 1, finding 0 — cited src/x.js:42 | Run 1, test "parses null" |
   | AC2 | [ ] | Pass 1 — "unverifiable from diff" | no covering test — see D3 |
   ```
3. **The rule that makes it real:** an AC may be ticked only when both
   columns are non-empty. Anything else is `[ ]` with the reason showing.
4. Teach `verify-state.sh` one more check: `Status: done` **and** an
   unticked AC with no `waived by user on <date>` note ⇒ fail loudly.
   Same trick it already plays on the Pass-3 loop cap, same cost (a grep),
   same guarantee (a script cannot hallucinate a pass).

**Cost:** ~15 lines of template, ~8 lines of shell, one smoke case.

## ⬜ D2 — Eight statuses, three of them ever set

**Evidence.** The status enum has 8 values
(`TEMPLATE.md.tmpl:10`). Grepping every template and skill for an
instruction to set one returns exactly three:

| Status | Who is told to set it |
| --- | --- |
| `spec-approved` | lead — `feature.md.tmpl:162` |
| `in-review` | senior-dev `:69`, builder `:111` |
| `blocked` | **senior-dev only** — `senior-dev.md.tmpl:30` |
| `draft`, `in-progress`, `changes-requested`, `testing`, **`done`** | **nobody** |

Three consequences, all live today:

- **`done` is unreachable.** The `status-board` skill's central rule —
  "only check off a box once a task's `Status:` actually reaches its
  terminal done value" — keys off a transition no role ever performs. The
  board can therefore never legitimately mark anything complete.
- **The two implementers disagree.** `senior-dev` sets `blocked` on an
  open question; `builder` is told to "append and stop" with no status
  change (`builder.md.tmpl`). These two roles are documented as doing "the
  identical job under the same rules" — so the same event leaves the
  ledger in two different states depending on which vendor ran.
- **`verify-state.sh` is reading a field that drifts.** Its
  placeholder-verdict check relaxes for `draft|spec-approved|in-progress|
  blocked` — statuses that are largely never set — so the check is
  softer in practice than it reads.

**Why it matters.** A shared status field that no one owns is worse than
no status field: every downstream rule that keys off it (the board, the
verifier, the human's glance at the top of the file) inherits a value
that is stale by construction. This is the classic "the board is a lie"
failure, and it is why nobody trusts the board.

**Fix.** One table in `TEMPLATE.md.tmpl`, directly under the Status line —
status, who sets it, on what event — then one matching line in each role
file, and one consistency check in `verify-state.sh`:

- `## Test results` has a `### Run` ⇒ Status must be at or past `testing`
- Status `done` ⇒ a `PASS` verdict exists **and** D1's ledger is closed

**Cost:** a table plus five one-line edits. Fixes O7's metric problem for
free too — once statuses are actually set, phase timing is derivable.

## ⬜ D3 — Verification inherits the author's definition of correct

**Evidence.** `tester.md.tmpl` never contains the string "acceptance
criteria" (verified by grep). It is told to run "this project's own test
command" and triage what fails. Nothing maps a test to an AC, nothing
reports which ACs have **no** covering test, and nothing records who
*wrote* the tests being run — while the implementer's scope routinely
includes test files.

**Why it matters.** This toolkit enforces cross-vendor independence for
**opinion** (the reviewer must be a different model family — stated on the
README's front page as the headline guarantee) and then does not enforce
it for **evidence**. "12/12 pass" from a suite the implementer authored,
against criteria the tester never read, is a green light with no
independence behind it. In a human team this is the QA function reporting
that the developer's own tests pass — technically true, organizationally
worthless, and *more* dangerous than no test step because it manufactures
confidence.

**Fix — cheap version first, and it captures most of the value:**

1. Give the tester the ACs. Add to its Output section a required table:
   `AC | covering test | result`, and an explicit line naming **every AC
   with no covering test**. An uncovered AC is a finding, not a silence.
2. Require a provenance line: *"tests exercised were authored by
   \<implementer|pre-existing|tester\>."* One sentence, and it tells the
   human exactly how much the green means.
3. Optional, where cheap: one negative control per new test (confirm it
   fails without the change). Charter this per task class (H1), don't
   mandate it globally.

**Cost:** ~12 lines in one role file. Note it also gives D1's ledger its
"Test evidence" column for free — D1 and D3 are one change, done together.

## ⬜ D4 — The review loop has no convergence rule

**Evidence.** `reviewer.md.tmpl` never mentions Pass 1, prior findings, or
the Decisions log (grep: zero hits). Its Inputs are the spec, the diff and
project docs (`:58-63`). A grep for "new finding" across the whole repo
returns nothing. The only loop control is the count itself
(`feature.md.tmpl:294`, `verify-state.sh` failing on a `### Pass 3`).

**Why it matters.** Two things follow, and both are recognizable
pathologies from human code review:

- **Moving goalposts.** Nothing stops Pass 2 from returning an entirely
  new set of findings about untouched code. When that happens the two-loop
  cap stops being a convergence guarantee and becomes an arbitrary cutoff
  — the pipeline stops not because the work converged but because it ran
  out of tickets.
- **Disagreement with no reader.** `senior-dev.md.tmpl` tells the
  implementer to record disagreement in the Decisions log because
  "unwritten disagreement resolves against you." But the reviewer is never
  told to read that log, and `feature.md.tmpl:306` tells the lead to
  "adjudicate on the written evidence" without telling it to *record* the
  adjudication anywhere. So written disagreement has no reader either. A
  team where the only channel for "I think you're wrong" is a log nobody
  is assigned to read is a team that has the form of due process and none
  of the function.

**Fix.** Three sentences, no new machinery:

1. Reviewer, Pass 2+: *"Close every Pass N-1 finding by number — fixed /
   withdrawn / disputed, with the author's Decisions-log reason quoted and
   answered. Read the Decisions log before you re-review."*
2. *"On Pass 2, a finding about code the diff did not change is
   admissible only at `critical` or `high`."* This is the standard
   professional norm; it just needs saying.
3. Lead, step 3: *"Record each adjudication in the Decisions log — the
   finding number, who prevailed, and why."*

**Cost:** three sentences across two files. Makes the existing two-loop cap
mean something.

## ⬜ D5 — Two structural dead ends: no way back, no way to wait

**Evidence.** `feature.md.tmpl:133` — "Do not proceed on silence" (correct)
— with no notion of a pending-decision queue: no timestamp, no
blocked-on-whom, no resumable question record. And the only route for a
bad spec is Open questions → the human; there is no path back to the
planner.

**(a) No return path to the planner.** When the implementer finds the spec
unbuildable, its options are comply or stop the world. Every spec defect
therefore costs a human interruption, however mechanical. A real team
returns the ticket to whoever wrote it. Recommend one **spec bounce**,
capped at one: implementer sets `blocked`, lead re-dispatches the planner
once with the objection, escalates only if the second spec is rejected
too. That trades a cheap planner call for a human interruption — the same
economics that already justify the two-loop review cap.

**(b) No way to be waiting.** `scripts/team.sh` resumes the lead's
conversation by default, which strongly implies overnight and
across-session runs. But a run that reaches a stop-and-ask gate just
stops, with the question living only in the lead's conversation. Resume
tomorrow and the state file cannot tell you what it was waiting for.
Recommend splitting `blocked` into `blocked:question` (needs the human)
and `blocked:spec` (bounced to the planner), and requiring the lead to
write the pending question plus a timestamp into *Open questions* and the
status board before it stops. Then "what is this waiting on, and since
when" is answerable without the lead's context — which is the entire
premise of the state file.

Composes with `REVIEW.md`'s **O4** (uncapped test loops): one shared
budget field covers the review loops, the test loops, and the spec bounce.
Do them as one edit.

---

# Part B — team harmony

## ⬜ H1 — Define task classes; stop making staffing an ad-hoc judgment

`REVIEW.md`'s **O1** (fork the session for high-stakes review) and **O3**
(bump the reviewer model on a big diff) are both correct, and both are
special cases of a gap neither names: **the roster is static and the lead
has no staffing lever.** Every task gets the same five roles, the same
models, the same session policy, the same depth — whether it is a typo fix
or a change to a permission block.

Rather than adding two more conditional rules to `feature.md`'s already
long step 3, define **task classes** once, per project, and let the lead
classify at spec approval (a judgment it is well placed to make, recorded
in one field the user can override):

| Class | Example | Session | Reviewer | Tests |
| --- | --- | --- | --- | --- |
| `routine` | copy change, one-file fix | reuse | default model | existing suite |
| `standard` | a normal feature | reuse | default model | AC coverage required (D3) |
| `sensitive` | permission blocks, auth, migrations, the pipeline's own files | **fork** — reviewer sees the diff, not the author's trace | **stronger/fallback model** | negative control required |

This resolves O1 and O3 together, gives the "measure it before assuming"
tradeoff a home other than good intentions, and turns two rules a lead
must remember into one field it must fill.

## ⬜ H2 — The role that decides scope is the least constrained

**Evidence.** `karpathy-guidelines` — simplicity first, surgical changes,
surface assumptions, minimum code — is loaded by the lead and **inlined
into `senior-dev` and `builder`** (2 hits each). `planner.md.tmpl`: **0
hits.**

The implementer is told twenty ways to keep a change small. The planner —
which decides *what gets built at all* and *how wide the file scope is* —
is told only to make criteria checkable and to split at ~7 ACs. Nobody on
this team is chartered to say "the simplest version of this is half the
scope," and the state file has nowhere to record that such a question was
even asked.

That is a leverage inversion: the cheapest place to remove work is before
implementation, and it is the one place with no minimalism rule.

**Fix.** Inline the same behavioral defaults into `planner.md.tmpl`, and
add two one-line fields to the spec:

- **Simplest version considered:** *\<what a smaller version would be, and
  why the spec is bigger than that\>*
- **Blast radius:** *\<what this can break if it is wrong\>*

Both are things a good planner already reasons about; the fields make the
reasoning reviewable and give the human something to push back on at the
approval gate other than the planner's own framing.

## ⬜ H3 — Nobody reviews the spec, and it is the cheapest place to catch a defect

Code gets two mandatory review passes. The spec — which every downstream
role treats as the contract — gets one glance from the human least
equipped to notice a missing AC, an over-wide file scope, or an empty
permissions table, because all they see is the planner's own summary of
the planner's own work.

**Do not add a reviewing agent for this.** The toolkit's own principle
applies exactly: *verification is a script, not a sixth agent.* Most spec
defects are structural and greppable. Add `scripts/verify-spec.sh`,
sibling to `verify-state.sh`, run by the lead in step 1 before showing the
user:

- Goal non-empty and not still the template's placeholder prose
- ≥1 AC, ≤7, and none containing "well", "properly", "robust", "correctly"
  (the classic uncheckable adjectives its own planner file calls out)
- *Files in scope* table non-empty, no unfilled `| |` row
- *New permissions required* explicitly filled or explicitly "none"
- H2's two new fields present

Zero LLM calls, cannot hallucinate a pass, and it catches the defect class
that otherwise costs a full implement→review loop to discover.

---

# Part C — the missing layer

## 🔶 C1 — There is no charter layer, and that is the real "business logic" gap

You asked whether any business or team logic needs updating. This is the
answer, and it is structural rather than a list of missing rules.

The toolkit has exactly two layers, and they are well separated:

- **Process (generic)** — owned by `templates/`. Deliberately never
  project-specific; `CLAUDE.md`'s Conventions enforce that.
- **Code content (project-specific)** — owned by the project's own
  `CLAUDE.md`/`AGENTS.md`. Every role reads it for constraints.

A third layer exists in every real team and has **no home here**: policy
that is project-specific but is not about code.

> What counts as done. Who may approve a merge. What happens when the
> approver is asleep. Which changes are sensitive. Who owns the tests.
> How many tasks may be in flight. What quality bar applies to a
> throwaway spike versus a payments change.

Today those answers are either absent (D1, D5), hardcoded generically in
`feature.md` prose where a project cannot vary them, or living in the
user's head. That is why so many findings in *both* reviews are "add a
sentence to `feature.md`": each is a policy decision being smuggled into
a process file that is supposed to be project-agnostic.

**Recommendation — `.agents/CHARTER.md`.** One screen, rendered by
`init.sh` from a handful of asked answers, read at preflight by the lead
and named by each role file alongside `CLAUDE.md`. Contents:

```markdown
# Team charter — <project>
Definition of done:     all ACs ticked with reviewer + test evidence (D1)
Merge authority:        <who>, always human
When the human is away: write the question + timestamp, stop, do not proceed
Task classes:           routine | standard | sensitive  (see H1 table)
Sensitive paths:        <globs — auto-promotes a task to `sensitive`>
Test ownership:         tests authored by <implementer|tester>; provenance
                        recorded every run (D3)
WIP limit:              one task per lead session; parallel work = parallel
                        projects, not parallel tasks in one pipeline  (O5)
Budgets:                review loops 2 · test loops N · spec bounces 1  (O4, D5)
```

This is worth doing for three compounding reasons:

1. It gives D1/D5/H1/O4/O5 a **single home** instead of five separate
   `feature.md` edits, and keeps `templates/` genuinely project-agnostic —
   which is a stated, load-bearing convention this toolkit already has.
2. It makes the policy **diffable and reviewable** by the human, which
   prose buried in a 346-line command file is not.
3. **It is what makes this a team generator rather than a toolchain
   generator.** `dev-team-generator`'s Step 1 interview currently asks
   seven questions and *all seven are tooling*: project name, which roles,
   which tool per role, models, source dirs, test command, auto-approve
   flag. It never asks what done means, who approves, what happens
   overnight, or who owns tests. The role prose it generates is already
   good and already generic — the charter is the only genuinely
   per-project output, and the interview does not ask for it. Add the
   charter questions to Step 1 and generate `CHARTER.md` as its first
   output, before the flow file.

---

# Part D — feedback on `REVIEW.md`

Asked for directly: what to act on, what to neglect.

## Re-rank

| Item | Current | Suggested | Why |
| --- | --- | --- | --- |
| **O4** loop budget | #1 | **#2** | Real bug, correct call. But budgeting a loop matters less than nobody ever declaring done (D1/D2). Ship it *with* D5's spec bounce as one shared counter. |
| **O1** independence | #2 | **fold into H1** | Re-frame it: the issue is not token cost, it is that the README's headline guarantee is diluted by a default nobody re-examines. A task class decides it once; "measure it on the first task" is not a mechanism. |
| **O3** reviewer bump | #2 | **fold into H1** | Same shape as O1. One classification field beats two conditional rules in step 3. |
| **O2** memory opt-ins | #2 | **keep** | Correct and cheap. Its "ask once at step 5" fix is the right size. |
| **O6** SYSTEM.md onboarding line | #3 | **keep, do it now** | One line, zero risk, and it is a real hole for a non-Claude lead. |

## Neglect

- **§4 — MODELS.md dated tables.** Keep them. They are explicitly dated,
  the principles above them age well, and deleting the numbers removes the
  part that teaches *how* to reason about credit burn. Revisit only if the
  numbers are ever wrong in a way that misleads.
- **§4 — `team-completion.bash`.** 32 lines, no maintenance surface, no
  behavior. Deleting it and keeping it are both free; spending a decision
  on it is the only actual cost. Keep it, stop tracking it.
- **§3.3 — shellcheck locally.** CI runs it on every push. "Not installed
  on the dev machine" is a laptop chore, not a project finding.
- **O7 — health metrics.** Do only the free half (report "loops used R/T"
  from the state file) and drop the rest. Once D2 makes statuses actually
  transition, phase timing becomes derivable at zero cost; until then any
  metrics work is instrumenting a field that does not move.
- **O5 — lead as SPOF.** Correct scope, accepted. It needs one sentence in
  the charter (C1) and no further thought.

## One structural note on the file itself

Part 1 is now ~90% `[DONE]` and reads as a changelog rather than a review.
Once the last items close, collapse it to a short "applied in the fix
pass" list — the value of a review file is its **open** items, and right
now they are outnumbered ~5:1 by resolved ones. (The ✅/⬜ marks added in
this pass are the interim fix.)

---

# Part E — sync debt is failing again, right now

## ⬜ S1 — Two live divergences, both introduced by the last two commits

`CLAUDE.md` names the three hand-synced flow copies and says "these have
diverged silently before." They have diverged silently again — verified by
grep, today:

| Rule | `feature.md.tmpl` | `SYSTEM.md` | `flow-example.md` | `lessons-learned.md` |
| --- | --- | --- | --- | --- |
| Ask before splitting a very large task (commit `6fdf372`) | ✅ | ❌ | ❌ | ✅ |

| Field | `TEMPLATE.md.tmpl` | `state-file-example.md` |
| --- | --- | --- |
| *Reviewer for this task* / *Tester for this task* (commit `79f0e14`) | ✅ | ❌ |

Both are the newest changes in the repo — which is the tell. The
convention is not failing on old debt, it is failing **on every new
change**, because the sync step depends on the author remembering a
five-bullet rule in `CLAUDE.md` at exactly the moment they are focused on
something else. There are now six surfaces carrying overlapping content
(three flow copies, two state-file copies, `lessons-learned.md`) and zero
automated checks across them.

**Fix — invariants, not text equality.** A ~30-line `test/invariants.sh`
in CI asserting that a small list of load-bearing rules is *present* in
every copy that must carry it:

```bash
# rule id | phrase to match | files that must all contain it
split-large-task | "split it into smaller tasks" | feature.md.tmpl SYSTEM.md flow-example.md
loop-cap-2       | "[Mm]aximum two loops|two failed loops" | feature.md.tmpl SYSTEM.md flow-example.md
merge-gate       | "[Nn]ever merge"                 | feature.md.tmpl SYSTEM.md flow-example.md
state-fields     | "Reviewer for this task"         | TEMPLATE.md.tmpl state-file-example.md
```

Adding a rule means adding one line to that table. It will not catch
wording drift, and it does not need to — it catches *omission*, which is
the failure mode that has now happened twice in a row. This is the same
argument the toolkit already makes for `verify-state.sh`: the check is
narrow, deterministic, free, and cannot forget.

---

# Priority

| # | Item | Size | Why here |
| --- | --- | --- | --- |
| 1 | **D1 + D3** — AC ledger with reviewer/test evidence, tester reads the ACs | ~25 lines + 1 smoke case | Closes the delivery contract. Everything else is secondary to this. |
| 2 | **D2** — status transition table + `verify-state` consistency check | ~15 lines | Makes the board and the verifier honest; unblocks O7 for free. |
| 3 | **S1** — invariants test in CI | ~30 lines | Stops the bleeding on a convention that just failed twice. |
| 4 | **D4** — review convergence rules | 3 sentences | Makes the existing loop cap mean something. |
| 5 | **O4 + D5** — one shared re-engagement budget (review / test / spec bounce) | ~20 lines | `REVIEW.md`'s real bug, plus the missing return path, as one edit. |
| 6 | **H3** — `verify-spec.sh` | ~40 lines | Cheapest defect catch in the whole pipeline. |
| 7 | **C1 + H1 + H2** — charter, task classes, planner minimalism | ~1 doc + 2 role edits | Gives every policy finding above a home; makes the generator generate a *team*. |
| 8 | **O2, O6** | small | Already correctly scoped in `REVIEW.md`. |

**If you only do three things:** D1+D3 (one change), D2, S1. Those are the
difference between "the team produces work" and "the team produces work
you can audit without re-reading it yourself."

---

# On keeping downstream projects up to date

A separate deliverable, and a real gap — there is no version stamp, no
changelog, and no signal about which upstream change is safety-critical.
The full staged plan is in [`docs/UPGRADING.md`](docs/UPGRADING.md).
