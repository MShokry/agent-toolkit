# State-file template — worked example

The single handoff surface. Every role reads this file and appends to it —
nothing is passed between roles by prose alone. Copy this shape to
`.agents/T-<id>.md` (or wherever this project keeps per-task state) and
fill it in per task.

```markdown
# T-<id> — <short title>

**Status:** draft | spec-approved | in-progress | blocked:question | blocked:spec | in-review | changes-requested | testing | done
**Owner right now:** planner | implementer | reviewer | tester | lead
**Implementer for this task:** <role/tool/model — e.g. "senior-dev (claude/sonnet)" or "builder (opencode/kimi-k2.7-code)">
**Reviewer for this task:** none yet — set by the lead before dispatching review; a model/vendor independent from the implementer
**Tester for this task:** none yet — set by the lead before dispatching test
**Dispatch session id:** none yet — set after the first dispatch call, reused for every later call on this task
**Wide-auto-approve mode:** off — only meaningful if the implementer's tool has one (see lessons-learned.md entry 1). On means it's used for this task's implement call, per the user's answer at spec approval. Off is the default; never turn this on without asking.
**Review loop count:** 0 / 2
**Test-fix loops:** 0 / 2
**Spec bounces:** 0 / 1
**Blocked since:** — <date + one line, set whenever Status becomes `blocked:*`, cleared when it isn't>
**Latest handoff:** <one line, overwritten by whichever role finishes last —
`<role> → <outcome in a few words> → next: <role>`. This is what the lead
reads between steps instead of the whole file.>

> **Who sets each Status** — every value has exactly one owner and one
> triggering event, or the field silently rots:
>
> | Status | Set by | When |
> | --- | --- | --- |
> | `draft` | planner | it starts writing this file |
> | `spec-approved` | lead | the user approves the spec |
> | `in-progress` | implementer | it starts implementing |
> | `blocked:question` | implementer, or lead | an open question needs the human |
> | `blocked:spec` | implementer | the spec is unbuildable; bounced to the planner |
> | `in-review` | implementer | the diff is ready to review |
> | `changes-requested` | lead | it routes a CHANGES_REQUESTED back |
> | `testing` | tester | it starts running suites |
> | `done` | lead | report step only: ledger closed, review PASS on record |

---

## Goal

<One paragraph. What the user actually wants, in their terms. Not a solution.>

**Simplest version considered:** <the smaller thing that could work, and why this spec is bigger — or "this is the smallest version". Planner only.>
**Blast radius:** <what breaks if this is wrong: which callers, which data, which users. Planner only.>

## Acceptance criteria

> Checkable statements only. "Works well" is not checkable. Only the
> planner writes this list, and no other role may edit the *text* of a
> criterion. Recording whether one was *met* is a separate job with a
> separate owner — the ledger below.

- [ ] AC1 —
- [ ] AC2 —

### Acceptance criteria ledger

> The **lead** fills this in at the report step, and nobody else. An AC may
> be ticked only when both evidence cells are non-empty — cite what is
> already in this file (a reviewer pass + file:line, a tester run + the test
> name). An AC the user agreed to drop gets `waived by user <date>`, never a
> tick.

| AC | Met? | Reviewer evidence | Test evidence |
| --- | --- | --- | --- |
| AC1 | [ ] | | |
| AC2 | [ ] | | |

## Constraints

> From this project's own root guidance file, restated here so no role has
> to remember them.

## Files in scope

> The planner sets this. The implementer may not touch a file outside it
> without appending to Open questions first and stopping.

| File | Why |
| --- | --- |

## New permissions/dependencies required

> Any addition to the project's permission surface or dependency list, with
> justification. Empty is the expected answer. A silent addition is an
> automatic CHANGES_REQUESTED.

| Item | Why it is unavoidable |
| --- | --- |

## Decisions log

> Append-only. Date, role, decision, and the reason. A decision without a
> reason is not a decision, it is a preference.

| When | Role | Decision | Why |
| --- | --- | --- | --- |

## Review verdicts

> Written by the reviewer only. PASS or CHANGES_REQUESTED, then numbered
> findings with file:line and severity.

### Pass 1 — <date> — verdict: <PASS | CHANGES_REQUESTED>

<findings, or "none">

## Test results

> Written by the tester only. Never edits source; reports and triages.

### Run 1 — <date>

- Command:
- Result:
- **Tests authored by:** <implementer this task | pre-existing | tester> —
  a suite the implementer wrote and the tester merely ran is a weaker signal
  than an independent one, and nobody reading this later can tell which they
  are looking at unless this line says so.
- Acceptance-criteria coverage:

  | AC | Covering test | Result |
  | --- | --- | --- |
  | AC1 | | |

  **ACs with no covering test:** <list them — an uncovered criterion is a
  finding, not a silence.>
- Failures with reproduction steps:

## Findings for docs

> Any role may append a line here when something learned in this task is
> true beyond this task. Format: `- [docs/SOME-DOC.md] one-line finding`.
> A findings-promotion script copies these into the named doc — no role
> edits project docs directly.

## Open questions

> Any role may append. The implementer must stop when it adds one here, set
> a blocked status, and record what it is blocked on and since when. Only
> the lead clears them. Prefix each with who it waits on — `[human]` or
> `[planner]` — so a session resumed tomorrow can tell at a glance.

- [ ]
```

## What each field is for, and why it's shaped this way

- **Owner right now** / **Latest handoff** exist so the lead never has to
  re-derive "what's the state of this task" by reading the whole file —
  one line, updated by whoever finishes a step, is the entire between-steps
  read.
- **Dispatch session id** exists only because some tools support continuing
  a session across multiple dispatches within one task (see
  `flow-example.md`'s "Dispatch-tool session policy") — if the tool(s) in
  use don't have that concept, drop this field rather than leaving a
  perpetually-empty one.
- **Wide-auto-approve mode** exists specifically so this decision is
  recorded per-task, not inferred from a dispatch command someone has to go
  find — see `lessons-learned.md` entry 1 for why this can never default
  to on.
- **Acceptance criteria** being planner-only-writable is what keeps them
  from drifting into something the implementer quietly redefines to match
  whatever it happened to build. The **ledger** is the other half of that:
  criteria nobody ever records an outcome for are a contract that never
  closes, which is how a pipeline ends up reporting "criteria met" from the
  lead's recollection rather than from evidence. Split the two jobs — the
  planner owns the text, the lead owns the outcome, the reviewer and tester
  supply the evidence, and the implementer touches neither.
- **The three budget counters** exist because a cap with nothing counting it
  is not a cap. Review loops are the one everybody thinks of; test-fix loops
  and spec bounces are the ones that get forgotten, and an unbudgeted
  test-fix loop plus a flaky suite is an infinite loop nothing notices.
  Whatever structural check you generate should read these and fail loudly.
- **Blocked since** + the `[human]`/`[planner]` prefix answer "what is this
  waiting on, and for how long" from the file alone. Without them, a task
  parked at a stop-and-ask gate lives only in the lead's conversation, and
  the next session — which may be a fresh one — cannot pick it back up.
- **Review verdicts** and **Test results** having their own dated,
  numbered sub-headings (Pass 1, Run 1, …) is what a structural
  verification script checks for — a duplicated or misplaced heading is
  exactly the failure mode that script exists to catch, cheaply, instead of
  a second agent eyeballing it.
