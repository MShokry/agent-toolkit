# Migration 06 — Loop accounting, closing gate, and findings scope

Validator and script behavior change after v1.0.2. No task schema, role
authority, model assignment, permission, or directory layout changes.

## What changed

- `verify-state.sh` allows one review pass per counted loop: passes ≤ 1 +
  Review loop count used + Test-fix loops used. A third pass is no longer an
  automatic failure; a pass without a matching counter is. Tasks without the
  counter fields keep the historical two-pass ceiling.
- `done` requires the **latest** review pass to be PASS and, when the task has
  a Test results section, at least one recorded run unless every ledger row is
  waived. An uppercase `[X]` tick needs both evidence cells like `[x]`.
- `promote-findings.sh` writes only to Markdown under `docs/`, or the roots in
  a colon-separated `PROMOTE_DOC_ROOTS`, and refuses symlinked paths.
- `oc.sh` prefers the session id in the run's own output, warns when an id is
  only inferred, and handles TERM/INT by stopping the client and keeping the
  transcript (exit 124).

## Existing installation

1. At an inactive boundary, preview with `init.sh --update` and merge
   `verify-state.sh`, `promote-findings.sh`, `oc.sh`, and `roles/leader.md`.
2. Run `verify-state.sh` on open tasks. A newly reported failure is evidence
   to triage, not a formatting problem: a `done` task whose latest review
   requested changes, or with no recorded run, was closed early. Do not edit
   history, counters, or verdicts to make the check pass; reopen or record an
   explicit user waiver.
3. If the project keeps promoted findings outside `docs/`, have the owner set
   `PROMOTE_DOC_ROOTS` (for example `docs:handbook`) where the lead runs the
   script. Never add the repository root, `.agent-pipeline`, or a tool
   directory. Review files earlier promotions appended to outside `docs/`;
   remove text nobody approved.
4. Treat a session id reported with an "inferred" warning as unverified: confirm
   it against the transcript before binding or resuming.
5. Accept provenance with `--refresh-stamp` after the reviewed merge.

Plain init skips existing files. This migration does not authorize rewriting
task records, widening documentation roots, or changing permissions.
