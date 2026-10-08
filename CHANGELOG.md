# Changelog

Impact tags, in descending order of "drop what you are doing":
`[contract]` › `[safety]` › `[process]` › `[docs]`.

A downstream project (or its AI lead — run `/toolkit-update` in Claude or
`$toolkit-update` in Codex) reads this file *first* and the diffs second. See
`docs/UPGRADING.md` for the full
update workflow. Version bumps mean: **MAJOR** = state-file contract /
role authority / script interface changed; **MINOR** = new template,
script, flag, or role rule; **PATCH** = prose and docs.

## Unreleased

- `[process]` Codex-lead parity with the Claude lead. New
  `scripts/bg-dispatch.sh` (`start`/`wait`) is the detached-dispatch watch for
  any lead — a Codex lead has no Monitor, so it loops on `wait` instead of
  losing dispatches to its own exec timeout. New `scripts/claude-review.sh`
  runs the project's Claude `reviewer` agent headlessly (read-only tool list,
  Edit/Write refused) so a non-Claude lead can dispatch a `claude/*` reviewer.
  `scripts/oc.sh` gains `--status` (v2 `/api/session/active`) and
  `--interrupt` (v2 `/api/session/<id>/interrupt`); the feature flow now uses
  them instead of raw `opencode api` calls. `codex-preflight.sh` checks the new
  wrappers and, for a `claude/*` reviewer, the Claude CLI and agent file.
- `[process]` Canonical feature flow: a *Where the team stopped* status check
  (board + handoffs + `gh pr list` reconciliation + stale-`main` check); the
  merge record after a merge; the mid-task model/implementer switch procedure
  (interrupt, ask keep-vs-discard, update manifest and role file,
  `verify-models.sh`, fresh session); verifying a role's "concurrent writer"
  claim before acting on it; the exact `### Pass N — <date> — verdict: <V>`
  heading `verify-state.sh` keys off; what to do when the lead cannot spawn
  the configured tester. The Codex feature skill gains the matching
  adaptations (no Monitor, no structured question tool, headless Claude
  review, per-task branches, sandboxed `oc.sh`).
- `[safety]` `promote-findings.sh` skips a *Findings for docs* tag that names
  a directory instead of aborting the run and silently dropping every later
  finding.
- `[process]` `init.sh` ignores `.pipeline/T-*.{out,err,pid,brief}` dispatch
  traces in a git target.
- `[process]` A `codex/<model>` tester is now a supported role:
  `--tester-model codex/<model>` scaffolds `.codex/agents/tester.toml`
  (report-only tester, model id without the vendor prefix);
  `verify-models.sh` skips `codex/*` like `claude/*`; `codex-preflight.sh`
  requires the tester agent when the manifest names one.
- `[process]` The OpenCode lead dispatches a `claude/*` reviewer through
  `scripts/claude-review.sh`, waits through `bg-dispatch.sh`, and stops roles
  with `oc.sh --interrupt`. Generated `AGENTS.md` asks the project to record
  whether sending review material to Anthropic is authorized.

- `[contract]` Merged upstream v0.10.0 (OpenCode lead, standalone dashboard,
  Herdr plugin) onto this line without changing the Codex/`.pipeline/`
  contract: the new OpenCode `leader`/`planner`/commands, `scripts/dashboard`,
  and the Herdr plugin read and write `.pipeline/` (task records) while
  skills stay in `.agents/skills/`. Upstream's `.opencode/agent/` worker
  directory stays retired in favor of `.opencode/agents/`. See below for
  upstream's own v0.10.0 notes, which still say `.agents/` where they
  describe the unmodified upstream.
- `[contract]` OpenCode role templates move from the legacy singular
  `.opencode/agent/` directory to V2's canonical `.opencode/agents/` path.
  Plain bootstrap refuses to create a second role tree beside an unmigrated
  one, while stamp-less update recovery can still read either layout.
  Migration: `migrations/03-opencode-v2-agents-directory.md`.
- `[safety]` Fresh scaffolds now include `scripts/verify-models.sh`; feature
  preflight resolves every OpenCode-dispatched model against the authenticated
  live server, and instructs the lead to verify (against `/api/agent`) that
  required roles and their ordered permission rules loaded after restarts,
  upgrades, migrations, or permission edits — the script checks models, the
  role check is a lead-run step. Disk configuration alone is no longer treated
  as readiness evidence.
- `[contract]` Writable task records, outputs, server credentials, session pins,
  and logs move from `.agents/` to `.pipeline/` for both leads. Codex protects
  `.agents/` under its default workspace policy; skills remain at
  `.agents/skills/`. Migration: `migrations/02-pipeline-directory.md`.
  Read-only update triage accepts legacy provenance stamps; a plain bootstrap
  refuses an unmigrated runtime rather than silently creating another one.
- `[process]` Codex leads capture exact session IDs through reviewed lifecycle
  hooks, pin them per team name, and resume through `codex-lead.sh`. Failed
  resumes, missing capture, and concurrent launches stop explicitly. The task
  template gains an optional Codex planner thread ID for corrections/recovery.
- `[process]` Added Codex lead/planner model and reasoning flags, defaulting to
  inheritance and preserved through the provenance stamp. Supporting delegate,
  status-board, and karpathy-guidelines skills are now installed deterministically.
- `[safety]` Codex preflight probes writable state and authenticated OpenCode
  access from the active sandbox. The adapter distinguishes workflow consent
  from runtime permission approval and preserves task/thread state on failure.
  Update consent explicitly covers Codex permissions, execution rules, and hooks.
- `[process]` Added no-model behavioral tests for launcher/hook/preflight and
  migration failures, plus an opt-in real Codex sandbox test. CI runs the
  behavioral suite. Live model workflow verification remains a documented
  manual check; these tests do not claim to establish model-level parity.
- `[docs]` Added `docs/CODEX.md`, migration/recovery guidance, and generalized
  lessons about protected instruction directories, exact-session identity,
  lifecycle trust, and separate workflow/runtime approvals.

## v0.10.0 — 2026-10-06

- `[safety]` Corrected earlier permission-verification conclusions in worker
  templates and `oc.sh`: v2 enforcement remains unverified against the exact
  generated artifacts. Stale server configuration and altered scratch copies
  can mislead checks; verify resolved rules and refused actions in a fresh
  runtime. Permission blocks remain guardrails, not filesystem isolation.

- `[process]` Init now installs self-contained `scripts/dashboard` into target
  repos, and `--update` / `/toolkit-update` include it in new-file and drift
  triage. Existing stamped projects add it with a plain flag-free init re-run;
  existing dashboard customizations and provenance are preserved. The shared
  dashboard module is host-independent and needs no toolkit checkout to run.
- `[process]` Added standalone `bin/dashboard`: opens the same visual task
  dashboard from any macOS/Linux terminal without Herdr or model calls. Finds
  the nearest `.agents/` directory from cwd, supports `--project` and `--once`,
  and shares the existing renderer rather than duplicating UI logic.
- `[process]` The in-Herdr board now uses a colored, scrollable visual terminal
  UI with pipeline boxes, task cards, acceptance bars, and a blocked-task filter.
  It uses standard-library curses, not an unsupported embedded webview; plain
  text remains available for non-interactive output and `--once`.
- `[safety]` Fixed Herdr dashboard tab creation: target-pane arguments are now
  supplied only for splits, avoiding Herdr's `invalid_params` rejection for tabs.
- `[process]` Herdr's task board is now a model-independent live dashboard:
  pipeline graphs, stage/task counts, blocker and handoff summaries, and recorded
  acceptance bars refresh from local task files without model calls. Unknown or
  blocked stages are not guessed; narrow terminal panes wrap the display.
- `[process]` Added an optional Herdr plugin under `integrations/herdr/` for
  the normal "start OpenCode and ask it to lead" workflow. Adoption binds the
  existing pane/session without prompting or relaunching it. Explicit actions
  can brief an idle lead, show task records, focus the exact native session, or
  add reusable empty worker/server shells and a board; `team.sh` is not required.
- `[safety]` Herdr bindings are scoped by server/workspace/project, stored
  outside project files, and never select the latest worker session. The plugin
  does not change permissions, send approval keystrokes, launch workers/servers,
  run verification scripts implicitly, or equate Herdr's done badge with task
  acceptance. Mocked adapter tests make no LLM calls; live integrations and
  permissions still require manual verification.
- `[process]` OpenCode can lead the scaffolded pipeline without a Claude or
  Codex CLI: new native V2 `leader`/`planner` adapters and `/feature` /
  `/toolkit-update` commands reference the canonical Claude instruction files
  instead of duplicating role policy. Existing worker files and session policy
  remain unchanged. The optional project handoff is historical context, not an
  implicit override of the pipeline.
- `[process]` `team.sh --lead opencode` launches the interactive OpenCode lead
  against the same authenticated server as its workers. Auto selection now
  falls back to OpenCode after Claude and Codex. OpenCode starts a fresh lead
  chat unless `TEAM_OPENCODE_SESSION` supplies an explicit lead id; `--fresh`
  ignores that id. It never uses `--continue` to accidentally resume a worker.
- `[safety]` The new planner denies shell/child dispatch and permits editing
  task state files only; the leader requests approval for shell actions and
  edits outside `.agents/**`. These are configuration defaults, not proven
  runtime isolation: verify resolved permissions and refused actions live.
- `[docs]` Generalized downstream handoff lessons: distinguish dated context
  from policy, preserve dispatch evidence, verify served models, and do not
  confuse the lead's session with worker sessions. No project-specific handoff
  content or model overrides are imported into the toolkit.
- `[docs]` Documented `./scripts/dashboard`, `--project`, `--once`, navigation,
  and additive installation for existing projects in README, the team guide,
  and the upgrade guide. No Herdr, agent runtime, or model calls are required
  to view recorded progress.

## v0.9.0 — 2026-09-27

- `[safety]` Synced this toolkit's own opencode v2 migration into the
  scaffolded pipeline templates: the shell permission key renamed `bash:` →
  `shell:` in `builder.md.tmpl`/`reviewer.md.tmpl`/`tester.md.tmpl` (under
  the old key, none of a template's shell `deny`/`ask` rules matched
  anything under opencode v2, so `rm -rf /*`, `sudo *`, `curl *`, etc. were
  silently unenforced); `oc.sh.tmpl` now authenticates with
  `OPENCODE_PASSWORD` (v2's `serve` is always password-gated, v1 had none),
  polls via `opencode api` against v2's `/api/*` routes, aborts via the
  renamed `/api/session/<id>/interrupt` endpoint, and picks the *newest*
  message for watchdog progress instead of the oldest (v2 returns messages
  newest-first; the old indexing could silently track the wrong message and
  let a wedged run look like it was still progressing).
- `[docs]` Corrected an earlier `oc.sh.tmpl`/agent-template comment claiming
  `--auto` lets a deny-listed shell command run anyway on opencode v2 —
  re-verified live via `GET /api/agent/<name>` and could not be reproduced;
  left the correction in place rather than deleting the original claim
  outright.
- `[process]` `bin/init.sh` now checks `opencode --version` on every
  scaffold or `--update` run and warns (non-fatally) when it's missing, v1,
  or newer than the v2 these templates assume, explaining specifically what
  breaks on v1 (password auth, the permission-key rename, the `opencode
  api` subcommand, `--server` replacing the removed `--attach`/`--dir`).
  `toolkit-update.md.tmpl` now tells the lead to surface this warning to
  the user rather than let it scroll past.
- `[process]` `bin/init.sh`'s `--builder-model`, `--reviewer-model`,
  `--reviewer-fallback-model`, and `--tester-model` are no longer required —
  `apply_defaults()` now fills them with `opencode-go/glm-5.3-flash` /
  `opencode-go/minimax-m2.7` / `opencode-go/deepseek-v4-flash` /
  `hcnsec/auto` when omitted, the same lineup two independently scaffolded
  projects (resto-agent, relationship) landed on. `--project-name` remains
  the only required flag; every flag can still be passed explicitly to
  override the defaults. Backward compatible — a call that already passed
  all four flags behaves identically.
- `[safety]` `init.sh` now also adds `.agents/.oc-password` (the local
  opencode v2 server password `scripts/team.sh` generates) to a scaffolded
  project's `.gitignore`, alongside the existing `.oc-port` and Claude
  session-id entries.
- `[docs]` README's quickstart and `docs/MODELS.md`'s recommended lineup
  updated to show this lineup as the documented default instead of the
  older Kimi/GLM-5.2/Sonnet-fallback/DeepSeek-Flash recommendation.

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
