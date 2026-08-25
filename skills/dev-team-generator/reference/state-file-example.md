# State-file template — worked example

The single handoff surface. Every role reads this file and appends to it —
nothing is passed between roles by prose alone. Copy this shape to
`.agents/T-<id>.md` (or wherever this project keeps per-task state) and
fill it in per task.

```markdown
# T-<id> — <short title>

**Status:** draft | spec-approved | in-progress | in-review | changes-requested | testing | done
**Owner right now:** planner | implementer | reviewer | tester | lead
**Implementer for this task:** <role/tool/model — e.g. "senior-dev (claude/sonnet)" or "builder (opencode/kimi-k2.7-code)">
**Dispatch session id:** none yet — set after the first dispatch call, reused for every later call on this task
**Wide-auto-approve mode:** off — only meaningful if the implementer's tool has one (see lessons-learned.md entry 1). On means it's used for this task's implement call, per the user's answer at spec approval. Off is the default; never turn this on without asking.
**Review loop count:** 0 / 2
**Latest handoff:** <one line, overwritten by whichever role finishes last —
`<role> → <outcome in a few words> → next: <role>`. This is what the lead
reads between steps instead of the whole file.>

---

## Goal

<One paragraph. What the user actually wants, in their terms. Not a solution.>

## Acceptance criteria

> Checkable statements only. "Works well" is not checkable. Only the
> planner writes these. No other role may edit them.

- [ ] AC1 —
- [ ] AC2 —

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
- Failures with reproduction steps:

## Findings for docs

> Any role may append a line here when something learned in this task is
> true beyond this task. Format: `- [docs/SOME-DOC.md] one-line finding`.
> A findings-promotion script copies these into the named doc — no role
> edits project docs directly.

## Open questions

> Any role may append. The implementer must stop when it adds one here.
> Only the lead clears them.

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
  whatever it happened to build.
- **Review verdicts** and **Test results** having their own dated,
  numbered sub-headings (Pass 1, Run 1, …) is what a structural
  verification script checks for — a duplicated or misplaced heading is
  exactly the failure mode that script exists to catch, cheaply, instead of
  a second agent eyeballing it.
