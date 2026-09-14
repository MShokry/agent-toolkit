# Changelog

Impact tags, in descending order of "drop what you are doing":
`[contract]` › `[safety]` › `[process]` › `[docs]`.

A downstream project (or its AI lead — run `/toolkit-update` in Claude or
`$toolkit-update` in Codex) reads this file *first* and the diffs second. See
`docs/UPGRADING.md` for the full
update workflow. Version bumps mean: **MAJOR** = state-file contract /
role authority / script interface changed; **MINOR** = new template,
script, flag, or role rule; **PATCH** = prose and docs.

## v0.8.0 — 2026-09-13

- `[process]` Fresh scaffolds now support Codex as the project lead when Claude
  Code is unavailable. `init.sh` adds a root `AGENTS.md`, repository-scoped
  `feature` and `toolkit-update` skills, and a source-read-only-by-instruction
  Codex planner under `.codex/agents/`. Codex's sandbox cannot restrict writes
  to `.agents/**` alone, so this limitation is explicit. The Codex feature
  skill is a thin adapter over the
  canonical Claude feature flow, so lead policy remains one maintained copy.
- `[process]` `scripts/team.sh` now selects the lead with
  `--lead auto|claude|codex` (`auto` prefers Claude, then Codex) and resumes the
  latest repository-scoped Codex session when using the fallback. Existing
  Claude UUID pinning is unchanged.
- `[safety]` Plain `bin/init.sh --target .` re-runs now load render values from
  an existing provenance stamp. This makes the documented missing-file step
  genuinely flag-free, allowing older scaffolds to install the new Codex files
  without reconstructing their original model flags or overwriting local
  customizations. Smoke coverage removes and bootstraps the four Codex files.
- `[docs]` Corrected the obsolete statement that Codex custom agents are
  machine-global only; current Codex supports project agents under
  `.codex/agents/` and project skills under `.agents/skills/`.

## v0.7.0 — 2026-09-11

- `[process]` The lead's commit, once the user approves the merge, now has
  concrete mechanics instead of stopping at "propose the merge": stage the
  state file alongside the code (so `git show` on the commit carries the
  spec, decisions, findings, and test results together) and **tag the
  commit subject with the task id**, `[T-<id>]` — leading it, or appended
  if the project's own commit convention already owns that position.
  Lands in the one-line subject (not just the body) so `git log --oneline`,
  `git blame`, and `git log --grep '\[T-<id>\]'` all find their way back
  to `.agents/T-<id>.md`'s full record from an incident later. This was
  already implicit ("only the lead commits" lived in `senior-dev.md`) but
  had no explicit instruction anywhere in the lead's own flow. Synced
  across all three flow copies; `test/invariants.sh` enforces the rule's
  presence.

## v0.6.0 — 2026-09-10

Closes three role-boundary seams surfaced by a session that drove the
pipeline end to end. All three are "a script that can't misjudge" fixes,
not new agents.

- `[safety]` `scripts/verify-state.sh` gains two checks, each enforcing a
  rule `TEMPLATE.md` already stated but nothing verified:
  - **Ledger evidence.** `done` is now refused when a *ticked* Acceptance
    criteria ledger row has an empty *Reviewer evidence* or *Test
    evidence* cell. The template already says a box may be ticked "only
    when both evidence cells are non-empty"; a tick resting on
    recollection now fails loudly instead of relying on the lead to
    self-police. A row carrying `waived …` is unaffected.
  - **Verdict present.** Once Status is `in-review` or later, at least one
    `### Pass N` heading must carry a filled `PASS`/`CHANGES_REQUESTED` —
    the mirror of the existing unfilled-placeholder check, closing the gap
    where the placeholder was deleted but no verdict written.
- `[process]` The lead branches the review step on the reviewer's
  machine-readable `VERDICT: PASS` / `VERDICT: CHANGES_REQUESTED` reply
  line (already emitted by `reviewer.md`), not on the raw event stream or
  a scan of findings prose. Synced across all three flow copies
  (`feature.md`, `SYSTEM.md`, `flow-example.md`); `test/invariants.sh`
  enforces the rule's presence.
- `[process]` `scripts/oc.sh` appends one JSON line per call to
  `.agents/logs/pipeline.jsonl` — `ts`, `agent`, `model`, `session`,
  `wall_s`, `status`, `kill_reason`, and best-effort `cost` / `tokens`
  from `GET /session/<id>`. Makes the pipeline's own $/min per role
  answerable after the fact, not only when a timeout forces a look.
  Best-effort: never fails the run. `bin/init.sh` adds `.agents/logs/` to a
  target repo's `.gitignore` (machine state, like `.agents/.oc-port`).

## v0.5.0 — 2026-09-10

- `[process]` `scripts/oc.sh` replaces its flat wall-clock `timeout` with a
  keep-alive watchdog. It backgrounds `opencode run` and polls the server's
  own session-state API (`GET /session/<id>/message?limit=1`,
  byte-fingerprint + `completed` flag) for forward progress; a run is
  aborted only when that fingerprint is frozen for `OC_IDLE_TIMEOUT`
  seconds while still not completed (a real wedge), or the absolute
  `OC_TIMEOUT` ceiling is hit. A run that keeps making progress is never
  killed for merely taking a while — which the flat timeout did constantly
  to real 20–60 min builder/reviewer turns.
  - **Env change:** `OC_TIMEOUT` is now the *ceiling*, default raised
    `600` → `2400`. New: `OC_IDLE_TIMEOUT` (default `600`), `OC_POLL`
    (default `20`). Exit `124` still means aborted; the stderr message now
    says whether it was idle or the ceiling.
  - Fresh (`--session`-less) runs now get their session id resolved by the
    watchdog, so abort-on-timeout always has a target — closes the old
    "no session id known to abort" gap.
  - Falls back to ceiling-only (old behaviour, no regression) if the
    session id can't be resolved or the message endpoint isn't JSON.
  - Signal is opencode-version-specific (verified 1.18.25). Full rationale,
    the signals that *don't* work, and a test procedure:
    `docs/OC-TIMEOUT-WATCHDOG.md`. Supersedes
    `skills/dev-team-generator/reference/lessons-learned.md` §3's
    "flat timeout is the current design" (see the update note there).

## v0.4.0 — 2026-08-26

- `[contract]` State file gains two header fields: **Task class**
  (`routine` | `standard` | `sensitive`) and **Class decided by**
  (`agent` | `human`). The planner proposes the class with a one-line why;
  the lead confirms at spec approval and asks the human only when torn.
  The class is recorded, never acted on — it does not change session
  policy, permissions, or budgets. `verify-state.sh` validates both fields
  when present; files without them (pre-existing tasks) stay valid, no
  migration needed.
- `[process]` Session policy made explicit: same task → same session,
  new task → new session, for all sub-agents (implement/review/test share
  the task's single OpenCode session; nothing carries across tasks).
- `[process]` `scripts/team.sh`: pane 0 no longer resumes via
  `claude --continue` ("the most recent conversation in this directory,"
  with no notion of which tmux session started it — a second team.sh
  session name, or an unrelated `claude` run, in the same repo could steal
  the next resume). Each tmux session name now pins to its own
  conversation via a stored UUID
  (`.agents/.claude-session-id.<session-name>`, resumed with
  `claude --resume`), removing that ambiguity.

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
