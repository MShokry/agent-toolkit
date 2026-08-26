# Changelog

Impact tags, in descending order of "drop what you are doing":
`[contract]` › `[safety]` › `[process]` › `[docs]`.

A downstream project (or its AI lead — run `/toolkit-update`) reads this
file *first* and the diffs second. See `docs/UPGRADING.md` for the full
update workflow. Version bumps mean: **MAJOR** = state-file contract /
role authority / script interface changed; **MINOR** = new template,
script, flag, or role rule; **PATCH** = prose and docs.

## v0.3.1 — 2026-08-26

- `[process]` Release tooling: `bin/release.sh v<X>.<Y>.<Z>` (deterministic
  checks — clean tree, on main, changelog heading present, no duplicate tag —
  then annotated tag + push) and `skills/toolkit-release/` (drafts the
  changelog entry from git history since the last tag, classifies impact,
  proposes the version, runs the releaser after user approval).
- `[process]` `--update` on a pre-stamp project no longer requires the
  original init flags: it recovers them from the target's own scaffolded
  files, prints them for verification, and suggests `--refresh-stamp` to
  make them permanent.
- `[docs]` Fixed two wrong steps in "Updating a project scaffolded before
  v0.3.0" (README), found by actually running them against two real
  projects: a premature `/toolkit-update` reference before that command
  exists in the target, and a false "flag-free" claim on the file-adding
  re-run (it needs the same flags as the `--update` pass before it — only
  `--update` attempts recovery).

## v0.3.0 — 2026-08-26

- `[contract]` state file: acceptance-criteria ledger (lead-only, evidence
  required), *Test-fix loops* 0/2 and *Spec bounces* 0/1 counters,
  *Blocked since* field, `blocked:question`/`blocked:spec` split (bare
  `blocked` still validates as the legacy value).
  `verify-state.sh` enforces all budgets and refuses premature `done`.
  Migration: `migrations/01-delivery-contract.md`
- `[contract]` new `scripts/verify-spec.sh` — deterministic spec gate at
  approval (`feature.md` step 1); unfilled specs never reach the user.
- `[safety]` builder permission block: blanket `"git *": allow` removed →
  enumerated read-only git verbs; explicit denies kept (they are what
  holds under `--auto`). Verify live before trusting.
- `[process]` feature.md: Standing Duties block (ask-once, remove-blockers,
  only-long-lived-session, never-widen-mid-task); loop counters incremented
  at routing time; ledger closed at step 5; non-actionable findings routed
  to test instead of burning a review loop; blocked:* handling with
  planner-bounce path (max 1).
- `[process]` reviewer: pass N closes pass N−1 finding-by-finding;
  findings on unchanged code admissible later only at critical/high; must
  read the implementer's Decisions log.
- `[process]` tester: reads ACs first; fills an AC-coverage table; records
  "Tests authored by" (implementer-authored suites are weaker evidence).
- `[process]` planner: *Simplest version considered* + *Blast radius*
  fields; owns `draft` status; writes `none` instead of leaving tables
  blank.
- `[docs]` MIT LICENSE; README restructure; `REVIEW.md` / `REVIEW-2.md`;
  `docs/UPGRADING.md`; lessons-learned #10–#20.

## v0.2.0 — 2026-08-26

- `[safety]` `promote-findings.sh`: refuses absolute/`..` doc paths from
  agent-authored content; both structural scripts anchor to repo root.
- `[process]` feature.md preflight resolves the server port like oc.sh
  (`OC_SERVER` → `.agents/.oc-port` → 4096) instead of hardcoded 4096.
- `[contract]` Status enum gains `blocked` for a stopped implementer.
- `[process]` non-actionable-findings routing synced into all three flow
  copies; sync-set named in CLAUDE.md.
- `[docs]` `test/smoke.sh` + CI workflow; marker-based usage() in
  bin/init.sh / oc.sh / team.sh; SED_ARGS dedupe; `.gitignore`
  append-if-missing for `.agents/.oc-port`; machine-specific paths made
  generic.

## v0.1.0 — 2026-08-26

- Initial extraction: five roles (lead/planner/implementer/reviewer/
  tester), state-file handoff contract, `oc.sh` dispatch wrapper with
  session reuse + abort-on-timeout, `team.sh` tmux layout, `init.sh`
  scaffolder, delegate/status-board/karpathy-guidelines/self-improvement
  skills, dev-team-generator skill.
