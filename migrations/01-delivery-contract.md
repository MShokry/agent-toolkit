# 01 — Delivery contract (ledger, budgets, split blocked status)

Applies to: `.agents/TEMPLATE.md`, `scripts/verify-state.sh`,
`scripts/verify-spec.sh` (new), every role file, and any in-flight
`.agents/T-*.md`.

Introduced in v0.3.0. Safe to skip entirely for tasks already at Status
`done`; apply to in-flight tasks before their next pipeline step.

## New header fields (add under **Implementer for this task:**)

```
**Test-fix loops:** 0 / 2
**Spec bounces:** 0 / 1
**Blocked since:** —
```

(`*Reviewer for this task:*` / `*Tester for this task:*` arrived earlier —
add them too if missing.)

## New section, directly under `## Acceptance criteria`

```
### Acceptance criteria ledger

| AC | Met? | Reviewer evidence | Test evidence |
| --- | --- | --- | --- |
| AC1 | [ ] | | |
```

One row per criterion, ids matching the list above. Only the lead fills
it — at step 5, citing reviewer + tester evidence already in the file. A
box may be ticked only when both evidence cells are filled; a criterion
the user dropped gets `waived by user <date>`, never a tick.

## Status enum change

`blocked` is now two values:

- `blocked:question` — waiting on the human (also fill *Blocked since*,
  prefix the Open questions entry with `[human]`)
- `blocked:spec` — spec unbuildable, bounced to the planner (max 1)

Bare `blocked` still validates — it is kept precisely so in-flight files
don't break. Rename when convenient; nothing forces it.

## New script

`scripts/verify-spec.sh` — run it once after the planner writes the spec,
before showing it to the user (`feature.md` step 1). Copy it from the
toolkit checkout or re-run init without `--update` to add just that file.

## Why backward compatibility is deliberate

The new `verify-state.sh` treats every added field as optional: absent
budget counters are skipped, an absent ledger gives the done-gate nothing
to check, bare `blocked` validates. So you can take the new script before
the new template and in-flight tasks keep passing. What you do not get
until you take the template is the guarantee — no ledger means nothing
refuses a premature `done`. Installed vs load-bearing: know which one your
project is running.
