# Changelog

Impact tags, in descending order of "drop what you are doing":
`[contract]` › `[safety]` › `[process]` › `[docs]`.

A downstream project (or its AI lead — run `/toolkit-update` in Claude or
`$toolkit-update` in Codex) reads this file *first* and the diffs second. See
`docs/UPGRADING.md` for the full
update workflow. Version bumps mean: **MAJOR** = state-file contract /
role authority / script interface changed; **MINOR** = new template,
script, flag, or role rule; **PATCH** = prose and docs.

## v1.0.2 — 2026-10-14

- `[contract]` Make team activation explicitly opt-in. Fresh root AGENTS.md only
  links to project guidance/CLAUDE.md; it does not mention the team or load leader
  rules. Feature skill discovery requires an explicit command or team request.
  Document manual commands and a copyable prompt; preserve existing startup files
  and project constraints through migration 05. No permission/model changes.
- `[docs]` Remove named downstream-project examples from toolkit documentation;
  keep verification fixtures and instructions project-neutral.

## v1.0.1 — 2026-10-13

- `[safety]` Fix CI ShellCheck compatibility for the manifest's indirect callbacks
  and express the traversal-test assertion explicitly. No runtime behavior,
  permissions, models, or task contract changes.
  Rewrite equivalent template guards as explicit `if` checks for older analyzers.

## v1.0.0 — 2026-10-13

- `[safety]` Planner adapters no longer load historical lead handoffs; relevant
  verified facts belong in the scoped brief, not additional worker context.
  Live context loading remains unverified. Limit CI ShellCheck to shell templates.
  Fix completion-array splitting and express the Herdr scaffold gate explicitly;
  document literal-text and indirect-callback lint exceptions.

- `[safety]` Upgrade provenance refresh preserves custom fields/notes, including
  planner and builder fallback assignments. Missing legacy reviewer fallback
  stays disabled; ambiguous unstamped recovery requires an explicit choice.
- `[process]` Layout plans report retained legacy artifacts/custom scripts and
  unsupported relative link syntax for review. Only actually moved task records
  gain task-relative links; unmoved root guidance keeps its relative paths.
  Preserve explicit legacy-discovery paths instead of rewriting detection gates.

- `[process]` Dashboard `s` toggles the existing priority order (default) and
  ascending numeric task order; active sort appears in the footer, with no state writes.

- `[process]` Herdr adoption reports an actionable shell-pane error before
  calling agent-get; it still never guesses a lead or launches a replacement.

- `[process]` Add `test/project.py --project <path>` for installed all-tools
  contracts, structural-script parity and mocked installed runtime/schema/mover
  regressions; local findings hardening is checked in a disposable fixture.

- `[safety]` Model preflight accepts explicit `reviewer_fallback_model: none`;
  disabled fallbacks must not become unapproved provider assignments on upgrade.

- `[safety]` Preserve native skill-directory symlink aliases without traversing
  them during layout planning; migration inputs and destinations still refuse
  symlinks. This keeps existing cross-client discovery aliases intact.
  Exclude installed dependencies and cache/VCS directories from config rewrites.

- `[contract]` **Major/breaking layout change:** consolidate toolkit runtime in
  `.agent-pipeline/bin/` and task records/template in `.agent-pipeline/tasks/`;
  native discovery directories remain in place. New tasks use one typed role
  table (backend, model, resolved family, session/thread), pending attribution,
  and immutable resume bindings. Legacy headers remain readable; mixed schemas,
  wrong-backend/shared ids, unresolved review families and missing consent fail.
- `[process]` Add reviewed-digest bulk layout plan/apply with collision/symlink/
  unknown-dispatch checks, private backups and owned-change rollback. Update
  callers/hooks/host readers/tests together in migration 04; old-layout bootstrap
  and stamp refresh refuse split state. Major release publication remains explicit.
- `[safety]` Narrow tester core writes to task records and lead automatic edits
  to tasks/prompts/logs, so relocated executable bin/ files do not inherit state
  write grants. Other action/effect values and reviewer denies remain unchanged;
  permission-resource changes need explicit upgrade review and live verification.

- `[process]` Scaffold a shareable `.agent-pipeline/README.md` in every profile:
  configured team details and role boundaries, capability checks for any lead app,
  and the full leader rules composed from the canonical source. Normal worker/
  native-lead loading stays lean; preview uses the same composition and existing
  customized guides are never overwritten. Default lean profiles now install
   25–26 files (including this opt-in guide and centralized helpers).

- `[docs]` Consolidate unreleased migration drafts 04–07 into one
  `migrations/04-team-upgrade.md` with the final upgrade order. Published migrations
  01–03 are unchanged. Clarify additive bootstrap versus reviewed existing-file
  merges, consistent profile/model flags, provenance acceptance, and fresh context.
- `[process]` Update reconciliation instructions to preserve the approved
  profile/model selection, bootstrap shared dependencies before switching
  entrypoints, and block dispatch during partial upgrades. Profile retirement
  and native-file removal remain separately approved, never automatic.

- `[contract]` Extract compact, provider-neutral leader/planner/implementer/
  reviewer/tester contracts; feature entrypoints and native agents load only
  their role. Backend dispatch instructions are selected lazily. Root guidance
  excludes assigned workers from leader routing; task templates retain field
  compatibility without repeated instructional prose. The lead alone owns all
  counters; quota retries require explicit authorization. See migration 04.
- `[process]` Add stamped `--leader` and `--extras` scaffold profiles and one
   shared manifest for count/render/preview. Lean profiles install 25–26 default
  files; legacy/all-tool baselines remain supported. Smaller selections never
  delete existing files or overwrite local customizations. Add context/profile
  regressions and permission-preservation fingerprints; live loading remains pending.

- `[process]` Scaffold `.agent-pipeline/bin/herdr-team.sh` and add optional Herdr two-tab
  setup/focus actions: preserve the existing lead, start the live dashboard in a
  separate tools tab, and add reusable empty support shells. Discover installed
  actions and workspace sessions without changing worker dispatch or permissions.
  Save partial layout progress and reject mismatched caller projects; plugin
  installation remains explicit. Live host verification is pending.

- `[contract]` Pin Codex team leads to hook-captured exact ids with additive
  trusted hooks, launch locks, and no latest-session/failed-resume fallback.
  Add configured, consent-gated headless Claude reviewer/fallback dispatch for
  all three leaders, immutable transcripts, strict verdict checks, and separate
  reviewer state. No OpenCode permissions or broad execution rules change;
  live enforcement is pending. See migration 04.

- `[contract]` Add optional native Codex implementation, read-only review
  (including configured fallback), and test workers, with distinct role thread
  fields and capability-gated dispatch. OpenCode remains the default worker
  runtime for all three leaders. Check explicit Codex ids against a bounded
  runtime catalog; preserve model-family independence, per-task consent, and
  existing sandbox/merge gates. See migration 04. No execution allowlists or
  hooks are installed by this change.

- `[process]` Add authenticated, bounded worker-model catalog preflight and a
  detached OpenCode dispatch fallback usable by Claude, Codex, and OpenCode
  leads. Reserve immutable attempts atomically and record actual exit status;
  session receipts no longer stand in for completion. No automatic retry,
  outside-sandbox allowlist, or permission widening is introduced.

- `[contract]` Isolate worker sessions by task and role instead of sharing the
  implementer's conversation with review/test. Add separate session fields,
  reject duplicate role ids, and keep legacy task files readable. All three
  leaders use the same policy; see migration 04. Adapted from the abdoharb fork,
  without standing auto-approval or permission changes.

- `[safety]` Timeout guidance no longer recommends widening permissions or
  enabling auto-approval mid-task, or claims that best-effort interruption proves
  a turn stopped. Existing dispatch logic and permission rules are unchanged.
- `[docs]` Replace obsolete upgrade proposals, model tables, and repeated
  permission incident narratives with current guides. Consolidate maintainer
  guidance in AGENTS.md, retaining CLAUDE.md as its native entry point. Claude,
  Codex, and OpenCode remain supported leaders. Extract open review work into
  docs/BACKLOG.md and remove the resolved historical review files; preserve
  changelog history, migrations, active templates, and compatibility handling.

## v0.10.2 — 2026-10-11

- `[contract]` Pipeline state/artifacts move from `.agents/` to
  `.agent-pipeline/`, separate from native `.agents/skills/` discovery. Scripts,
  roles, dashboard, integrations, and task links use the new directory. Update
  triage reads the legacy stamp without writing; scaffold/stamp refresh refuse
  old layouts to prevent split state. See migration 03 for approved lead-assisted
  moves, collision checks, backups/rollback, and permission-path reconciliation.
- `[safety]` Init ignores generated prompts as well as logs, credentials, and
  local session state; Git worktrees receive ignore rules too. Task records,
  shared guidance, and provenance remain trackable by default. Native skills
  stay outside the pipeline ignore scope.

## v0.10.1 — 2026-10-09

- `[contract]` Task state remains at `.agents/T-<id>.md`; prompts and transcripts
  now use `prompts/T-<id>/<role>-<pass>.md` and
  `logs/T-<id>/<role>-<pass>.jsonl`, with numbered implementation patches and
  an Artifacts table linking evidence/current patch. `oc.sh` requires matching
  prompt/transcript paths, rejects inline/stdin prompts, and reserves transcripts
  without clobbering earlier attempts. Retries allocate fresh pass numbers;
  telemetry is append-only under each task's logs directory. Existing projects
  reconcile callers/role instructions together; see migration 02. No automatic
  artifact moves, especially during active runs.
- `[process]` Dashboard discovery excludes legacy dotted artifact filenames as
  well as nested prompts/logs, displaying task records only. Added mocked
  dispatch safety tests and cross-copy artifact-policy invariants.
- `[process]` Dashboard task cards now show latest recorded review/test evidence,
  blocker timing, and highlighted loop budgets. Attention-first ordering,
  project acceptance totals, and distinct status colors improve scanning
  without adding controls, artifact clutter, dependencies, or model calls.

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
