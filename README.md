# agent-toolkit

A reusable version of the planner → implement → review → test multi-agent
pipeline: Claude, Codex, or OpenCode as the lead, matching-tool planning,
OpenCode (any vendor) for cross-vendor implement/review/test, a state file
(`.agent-pipeline/tasks/T-<id>.md`) as the single handoff surface between roles, and a
`delegate` skill so the lead's own context stays small across a long run. 

It was distilled from real multi-agent pipeline runs and hardened there
over time, so the same setup — permissions, session-reuse policy,
cross-vendor independence rules, the state-file contract — doesn't get
re-invented and re-debugged from scratch in every new repo.

OpenCode is also a supported direct lead: `/feature` and `/toolkit-update`
select a `leader` adapter, and its `planner` references the canonical role
instructions. No Claude or Codex CLI is required. Native
entrypoints reference neutral `.agent-pipeline/roles/` contracts; Claude files
are not dependencies of an OpenCode-only scaffold.

Codex is a supported lead: the scaffold includes project instructions,
a `feature` skill, a `toolkit-update` skill, a Codex planner, and an optional
`codex-dev` implementer. `--reviewer-model codex/<id>`, a Codex reviewer fallback,
or `--tester-model codex/<id>` adds the matching native worker. OpenCode workers
remain the defaults; native workers require verified Codex dispatch capability.
See [docs/CODEX.md](docs/CODEX.md). Configured `claude/<id>` primary/fallback
reviewers also have a consent-gated headless adapter for all leaders; see
[docs/CLAUDE-REVIEW.md](docs/CLAUDE-REVIEW.md). For any other
lead tool, read [`SYSTEM.md`](SYSTEM.md) — one tool-agnostic page meant to be
handed to an AI ("recreate this system, with yourself as the lead").

## How it flows

### Lean team profiles and context

**v1.0.0 major layout:** the toolkit-owned core lives in one `.agent-pipeline/`
folder. Runtime scripts move to bin/, task records/template to tasks/, and each
task uses one typed Role assignments table. Client-required discovery files stay
native. Existing projects apply one reviewed bulk migration before bootstrap;
see [migration 04](migrations/04-team-upgrade.md).

```bash
bash /path/to/agent-toolkit/bin/init.sh --target . --project-name my-app \
  --leader opencode --extras none
# --leader claude or codex uses the same neutral role contracts.
# Add --extras herdr to get the two-tab host helper and dashboard.
```

The leader loads its compact contract and only selected backend adapters.
Workers load their own role, project constraints, and required task evidence—
not the leader workflow. Default selected profiles install **25–26 files**;
`--leader all` retains all-tool compatibility. Existing files are never deleted
or overwritten. See [context/loading and profiles](docs/CONTEXT.md) and
[migration 04](migrations/04-team-upgrade.md).

### One file to introduce the team to any app

Every profile installs **`.agent-pipeline/README.md`**: configured team/model
details, role boundaries, task handoffs, and the complete leader rules. Share it
and ask: “Act as this project's team leader using this guide; confirm access and
worker capabilities first.” It is generated from the same leader contract, not
another hand-maintained policy copy. Workers do not load it; normal native leads
still use their small entrypoint and role contract. A shared file grants no tools,
credentials, or approval; an app without project/dispatch access must report that.

### Herdr two-tab team (optional)

Link the reviewed host plugin with
`herdr plugin link /path/to/agent-toolkit/integrations/herdr`, start your lead
normally in a Herdr project tab, then run `.agent-pipeline/bin/herdr-team.sh setup` from its
shell tool or invoke `agent-toolkit.team` in Herdr's actions UI. Your lead stays
in its tab; a second **Toolkit tools** tab starts the live dashboard alongside
empty worker/server shells. `actions`, `agents`, `focus-leader`, `focus-tools`,
and `logs` expose host discovery/navigation. No duplicate agent/server or approval
is launched. See [the Herdr guide](integrations/herdr/README.md).

### Standalone visual dashboard

From any project with `.agent-pipeline/` task records, run:

```bash
./.agent-pipeline/bin/dashboard
```

The dashboard extra installs this self-contained command in the project
(all-tools defaults include it). It does not need the
toolkit checkout to remain on disk. You can still use
`/path/to/agent-toolkit/bin/dashboard` for projects without the installed copy.

It discovers the project from your current directory (including nested folders),
shows live pipeline boxes/task cards, and refreshes every two seconds. No Herdr,
agent CLI, server, or model calls required. Python 3.8+ on macOS/Linux is enough.
Use arrows or `j/k` to scroll, `b` for blocked tasks, `s` to toggle sorting between
the current priority order (default) and task number, and `q` to close.
Task cards show the latest recorded review verdict and test result, owner,
acceptance progress, and loop budgets. Blocked/unknown tasks appear first;
completed tasks last. Status colors distinguish blockers (red), attention
(yellow), planning (blue), building (cyan), review/test (magenta), and done
(green). Labels remain readable without color; no new controls or model calls.

For another project or a plain-text snapshot:

```bash
./.agent-pipeline/bin/dashboard --project /path/to/project
./.agent-pipeline/bin/dashboard --once
```

Optionally add the toolkit's `bin/` directory to your shell's `PATH` to run
`dashboard` from any project. No project files are installed or changed. The
standalone command shares the optional Herdr adapter's renderer; it does not
call Herdr. Displayed progress is recorded data, not independent verification.

For an existing stamped scaffold, preview the addition and then install it:

If task records still live in `.agents/`, first apply
[migration 03](migrations/03-pipeline-directory.md); plain init refuses that
legacy layout until the lead completes the approved relocation.

```bash
bash /path/to/agent-toolkit/bin/init.sh --update --target . --only .agent-pipeline/bin/dashboard
bash /path/to/agent-toolkit/bin/init.sh --target .
```

The preview writes nothing (exit 1 means new/differing files). The plain run
adds missing files only, loading the original settings from the provenance
stamp. Future dashboard changes appear in `/toolkit-update` triage like other
generated files; local customizations are never overwritten by a re-run.

```mermaid
flowchart TD
    Req([Feature request]) --> Lead
    Lead -->|dispatch| Planner
    Planner -->|T-id.md - Goal, ACs, ledger rows, scope| Spec[/verify-spec.sh<br/>structural check, no LLM call/]
    Spec -- fails --> Planner
    Spec -- passes --> Approve{User approves?}
    Approve -- no or open questions --> Req
    Approve -- yes --> Impl[Implementer<br/>builder / senior-dev / codex-dev]
    Impl -- spec unbuildable, max 1 bounce --> Planner
    Impl -->|code, per-pass patch, Decisions log| Review[Reviewer]
    Review -- CHANGES_REQUESTED, max 2 loops --> Impl
    Review -- PASS --> Test[Tester]
    Test -- failures, max 2 loops --> Impl
    Test -->|AC coverage, test authorship| Ledger[Lead closes the AC ledger<br/>a tick needs reviewer AND test evidence]
    Ledger --> Report[Lead reports: ACs met, unverified, loops used]
    Report --> Merge{Merge?}
```



Every arrow into or out of a role is really a write to, or a read from,
`.agent-pipeline/tasks/T-<id>.md` — see below.

### Task files stay visible; artifacts stay grouped

```text
.agent-pipeline/
├── README.md                   # shareable team/leader guide; not worker context
├── bin/                        # runtime scripts; no project-level scripts pollution
├── tasks/
│   ├── TEMPLATE.md             # task shape
│   └── T-023.md                # task state, decisions, findings, results
├── roles/                      # compact role contracts
├── adapters/                   # selected backend dispatch instructions
├── prompts/T-023/
│   ├── builder-1.md
│   ├── reviewer-1.md
│   └── tester-1.md
└── logs/T-023/
    ├── builder-1.jsonl
    ├── builder-1.patch
    ├── reviewer-1.jsonl
    ├── tester-1.jsonl
    └── pipeline.jsonl           # append-only task telemetry
```

Every `oc.sh` dispatch requires matching `--prompt-file` and `--raw-out`
task/role/pass paths. Create directories and write the prompt before dispatch;
use a new positive pass number for every attempt, including retries. Prior
prompts, transcripts, and patches are never overwritten. State files link to
them in an **Artifacts** table and identify the current patch for review;
review findings and test results remain in the state file itself.

Run `.agent-pipeline/bin/verify-models.sh` before planning to catch unavailable/mistyped worker
ids against the authenticated catalog. This verifies resolution, not quota or
served-model identity. For hosts without durable background calls,
`.agent-pipeline/bin/bg-dispatch.sh start/wait` keeps OpenCode workers detached and stores
the actual exit status under `logs/T-<id>/<role>-<pass>.dispatch/`. It never
overwrites attempts or automatically retries; a session receipt alone is not
completion evidence. All three leaders follow these same rules.

The dashboard lists task state/status only, not individual artifacts. Existing
files are not moved automatically, and active-run artifacts must never move.
See [migration 02](migrations/02-artifact-layout.md) before upgrading a project
with root-level prompts/logs or old `oc.sh` callers.

`.agent-pipeline/` is toolkit-owned state, separate from native agent/skill
discovery. Codex skills still live in `.agents/skills/`; OpenCode definitions
stay in `.opencode/`. Init gitignores pipeline `prompts/`, `logs/`, local server
credentials, and session IDs, while task records, shared guidance, and the
provenance stamp remain trackable. A project may ignore the entire
`/.agent-pipeline/` if it wants all pipeline state local; this also excludes
shared guidance and the update baseline, so keep local backups.

Existing `.agents/` pipeline layouts require
[migration 03](migrations/03-pipeline-directory.md). `--update` reads the legacy
stamp without writing anything; plain init and stamp refresh refuse the old
layout to prevent split state. The updating lead can carry out the approved
rename, keeping native skills in place and reconciling links and permissions.

### Context stays small, by construction

```mermaid
sequenceDiagram
    participant Lead
    participant Role as Role (any)
    participant File as .agent-pipeline/tasks/T-id.md

    Lead->>Role: dispatch (task id, short prompt)
    Role->>File: full detail - diff, Decisions log,<br/>verdict, test results
    Role->>File: Latest handoff (one line)
    Role-->>Lead: short reply - verdict or pass count only
    Note over Lead: reads Latest handoff,<br/>not the whole file
    Lead->>File: opens the full file only on a<br/>verify-state.sh failure or a real decision
```



A role's chat reply is a receipt, not the record — the record is always the
file. That's what keeps the lead's own context flat whether the run has one
task or twenty: it never accumulates a second copy of every diff, verdict,
and test log it dispatched.

### Role permissions at a glance


| Role                                   | Reads                  | Writes                                      | Notes                                                   |
| -------------------------------------- | ---------------------- | ------------------------------------------- | ------------------------------------------------------- |
| Lead                                   | state file             | the acceptance-criteria ledger, Status      | the only role that records whether a criterion was met  |
| Planner                                | whole repo             | `.agent-pipeline/tasks/T-<id>.md` only                    | never touches source; owns criteria *text*, not outcome |
| Implementer (`senior-dev` / `builder` / `codex-dev`) | whole repo             | source + `.agent-pipeline/logs/T-<id>/<implementer>-<pass>.patch` + state file | the only roles that edit source                         |
| Reviewer                               | whole repo (read-only) | state file only, or nothing — see below     | blanket `edit`/`write: deny` by default in this toolkit |
| Tester                                 | whole repo (read-only) | `<test-dir>/**` + state file only           | never fixes, only reports                               |


The reviewer template ships **safer than it has to be** — blanket deny, not
scoped-allow on `.agent-pipeline/**` — because a permission block that reads
correctly in YAML isn't proof it's enforced by the runtime. Loosen it only
after verifying that live against your own OpenCode server (see "Design
decisions" below).

Codex's planner uses a `workspace-write` sandbox because it must create the
state file. Codex cannot scope that sandbox to `.agent-pipeline/**` alone, so its
source-read-only boundary is explicit role instruction rather than filesystem
enforcement. This limitation is stated in the generated planner file rather
than hidden.

Optional Codex implementer/tester agents likewise disclose their workspace-write
scope limits. Native Codex reviewers are read-only and return full findings for
the lead to record unchanged. Native dispatch requires live discovery and
resolved model/sandbox checks; valid files alone are not proof of those controls.

## What's in it

```
bin/init.sh           the scaffolder — copies templates/ into a target repo
                        (--update: diffs current templates against a target
                        that's already scaffolded, writes nothing)
bin/release.sh        the releaser — checks clean tree/main/changelog heading,
                        then annotated tag + push (drafting the entry is the
                        toolkit-release skill's job)
test/smoke.sh         automated smoke test for the guarantees above (run by CI)
test/invariants.sh    asserts every load-bearing rule is present in each of the
                        hand-synced copies that must carry it (run by CI) —
                        catches the omission that hand-syncing keeps producing
test/runtime.py       mocked worker completion/ownership and model-catalog checks
CHANGELOG.md          impact-tagged per-release changes ([contract] › [safety]
                      › [process] › [docs]) — read this before merging an update
migrations/           hand-appliable notes for [contract] changes only
integrations/herdr/   optional plugin: adopt an existing lead, show task records,
                       and add support panes without requiring team.sh
templates/             every generated file, with __PLACEHOLDER__ tokens
  pipeline/roles/       leader, planner, implementer, reviewer, tester contracts
  pipeline/adapters/    opencode, codex, claude dispatch instructions (load selectively)
  claude/agents/        planner.md.tmpl, senior-dev.md.tmpl
  claude/commands/      feature.md.tmpl — the /feature pipeline command;
                          toolkit-update.md.tmpl — the /toolkit-update merge command
   codex/                AGENTS.md.tmpl, project-scoped planner/codex-dev agents,
                           optional pinned reviewer/tester agents, and
                          feature/toolkit-update skills for a Codex lead
  opencode/agent/        builder.md.tmpl, reviewer.md.tmpl, tester.md.tmpl
  opencode/agents/       leader.md.tmpl, planner.md.tmpl — native V2 adapters
  opencode/commands/     feature.md.tmpl, toolkit-update.md.tmpl — direct lead commands
  agents-state/          TEMPLATE.md.tmpl — the T-<id> state file shape
   scripts/                oc.sh.tmpl (OpenCode CLI wrapper), bg-dispatch.sh.tmpl
                           (durable detached start/wait), verify-models.sh.tmpl
                           (bounded authenticated catalog preflight), team.sh.tmpl (tmux
                          layout — resumes the lead by default, --port for
                          running a second project at once, see docs/TEAM.md),
                          team-completion.bash.tmpl (optional shell completion
                          for team.sh), verify-state.sh.tmpl (structural check on
                          a task's state file — no LLM call), verify-spec.sh.tmpl
                          (the same, on a spec, before the human approves it),
                          promote-findings.sh.tmpl
                          (copies tagged findings into project docs — no LLM
                          call, no agent write access to docs/)
skills/
  delegate/SKILL.md      context discipline for the lead — load this in
                          any project's lead session, independent of init.sh
  toolkit-init/SKILL.md  a thin skill wrapping bin/init.sh, so a lead can
                          run this conversationally in a target repo
  toolkit-release/        cut a release conversationally: drafts the
    SKILL.md              impact-tagged changelog entry from git history
                          since the last tag, proposes the version, runs
                          bin/release.sh after user approval
  dev-team-generator/     self-contained alternative to toolkit-init: asks
    SKILL.md              first, then generates the team + flow live for
                          whatever tool(s) are actually available, instead
                          of stamping out templates/. Reach for this when a
                          role needs a tool init.sh doesn't already
                          template, or outside a checkout of this repo
                          entirely — everything it needs travels in its own
                          reference/ folder
  status-board/SKILL.md  keeps a top-level status board in sync with the
                          per-task state files — independent of init.sh
  karpathy-guidelines/    behavioral defaults (surface assumptions, minimum
    SKILL.md              code, surgical changes, verifiable success
                          criteria) — loaded by the lead via feature.md,
                          same as delegate. Not given to senior-dev/builder:
                          they'd need Skill-tool access to load it (a bigger
                          grant than either role needs), so the same content
                          is inlined directly into each of their own files
                          instead
  self-improvement/       optional, off by default — not loaded by
    SKILL.md               feature.md.tmpl like the others; see "Optional:
                          the self-improvement skill" for how to enable it
```



## Quick start

```bash
git clone https://github.com/MShokry/agent-toolkit ~/tools/agent-toolkit

cd /path/to/some/other/project
opencode models          # see what's actually configured before picking models

~/tools/agent-toolkit/bin/init.sh \
  --target . \
  --project-name "my-project" \
  --test-dir e2e
```

`--project-name` is the only required flag. `--claude-model`,
`--builder-model`, `--reviewer-model`, `--reviewer-fallback-model`, and
`--tester-model` all default to the lineup two independent real projects
converged on: Claude Sonnet lead/planner, `opencode-go/glm-5.3-flash`
builder, `opencode-go/minimax-m2.7` reviewer,
`opencode-go/deepseek-v4-flash` reviewer fallback, `hcnsec/auto` tester.
Override any of them per project once `opencode models` shows your server's
actual list differs — these are a starting point, not a guarantee those
exact ids still exist for you:

```bash
~/tools/agent-toolkit/bin/init.sh \
  --target . \
  --project-name "my-project" \
  --builder-model "<vendor/model>" \
  --reviewer-model "<vendor/model, different family than builder>" \
  --reviewer-fallback-model "<vendor/model, different family again>" \
  --tester-model "<vendor/model>"
```

`--reviewer-model` and `--reviewer-fallback-model` should be **different
model families** — the fallback is what the pipeline switches to when
`builder` implements and would otherwise share a vendor with the default
reviewer, which would defeat cross-vendor independence. Do not use `auto`
for the reviewer.

Current scaffold defaults, model-family independence, and provider choices: see
[`docs/MODELS.md`](docs/MODELS.md).

`init.sh` never overwrites a file that already exists in the target — it
prints `skip (exists)` and leaves it alone, so re-running is safe and an
existing project's customizations survive. Once a project has a provenance
stamp, a plain `bin/init.sh --target .` re-run is flag-free too: it loads the
original values from the stamp and writes only files a newer toolkit added.

`init.sh --update` never writes anything either — it renders the current
templates into a temp file and compares each one against what's already in
`--target`, printing a drift **summary** first (`exit 0` = clean, `exit 1`
= something to merge; full hunks behind `--diff`, one file via
`--only <path>`). On any scaffold after v0.3.0, flags default from
`.agent-pipeline/.toolkit-version` — the provenance stamp written at init — so
usually just `--update --target .` is needed. Merge deliberately (or run
the generated `/toolkit-update` command and let your lead reconcile,
triaging against the impact-tagged `CHANGELOG.md`), then refresh the
baseline: `bin/init.sh --refresh-stamp --target .`. Full workflow:
[`docs/UPGRADING.md`](docs/UPGRADING.md).

### OpenCode-only lead

After scaffolding a target project, start OpenCode normally:

```bash
opencode
# or
.agent-pipeline/bin/team.sh --lead opencode
```

Ask it to act as the toolkit leader and read `.opencode/agents/leader.md`, or
choose your model and run `/feature <request>` or
`/toolkit-update`. These commands select `leader` in the current session; the
planner runs as an OpenCode child agent, and builder/reviewer/tester still use
`.agent-pipeline/bin/oc.sh`. No Claude or Codex CLI is required. Neutral role contracts are
the shared policy; a lean OpenCode profile does not install Claude entrypoints.

`.agent-pipeline/bin/team.sh --lead opencode` is an optional tmux launcher, not a prerequisite
for acting as leader. For Herdr, the optional
[`integrations/herdr/`](integrations/herdr/README.md) plugin adopts your existing
agent without relaunching it. It offers an optional briefing, task board, and
support-pane layout; no launcher script is required.

Without tmux, start `opencode serve` with a configured password, export that
password as `OPENCODE_PASSWORD`, and connect using `opencode --server <url>`.
Set `OC_SERVER` to that same URL for worker calls (or use the port/password files
written by `team.sh`). Do not start the lead with `--auto`.

OpenCode starts a fresh lead chat by default; `--continue` might resume a worker
instead. To resume a known lead explicitly, set `TEAM_OPENCODE_SESSION=ses_...`
when launching `team.sh`. `--fresh` ignores it. This does not change the
canonical one-task-per-role worker-session policy. Verify live agent discovery and denied actions before trusting
permission controls; the smoke suite does not make that guarantee.

For an already-stamped project, a plain `bin/init.sh --target <project>` adds
the four missing OpenCode files without overwriting existing files. Use
`--update` first to triage related changes to the root instructions and launcher.

### Updating a project scaffolded before v0.3.0

Older scaffolds have no provenance stamp and use `.agents/` for pipeline state.
Apply [migration 03](migrations/03-pipeline-directory.md) after the read-only
preview and before the plain bootstrap in step 3; the paths below describe the
resulting `.agent-pipeline/` layout. One-time
migration — in the *target* project:

`/toolkit-update` doesn't exist in the target yet at this point (step 3
below is what adds it) — so this first pass has to be done by hand,
against the *toolkit checkout*, not the target's own commands:

1. **Get the latest toolkit on disk** (this is what you update against):
   `git -C <toolkit-checkout> pull`, or
   `git clone https://github.com/MShokry/agent-toolkit` if it isn't
   cloned yet.
2. From the toolkit checkout, run
   `bin/init.sh --update --target <path-to-project>`. With no stamp it
   recovers the original init values from the target's own scaffolded
   files and prints them for you to verify — pass a flag explicitly only
   if one couldn't be recovered (a project that customized its reviewer
   selection past the standard single-model-plus-fallback shape will need
   `--reviewer-fallback-model` by hand). This prints the drift summary and
   **doesn't write anything yet**. Before merging, check
   `.agent-pipeline/tasks/T-*.md` for any `Status:` that isn't `done` — merge at a task
   boundary, not mid-flight.
3. Run the **same command again with the same flags, minus `--update`**
   (i.e. plain `bin/init.sh --target <path> --project-name ... [...]`) —
   skip-if-exists makes this safe. This is what actually adds the files
   your scaffold predates (`.claude/commands/toolkit-update.md`,
   `.agent-pipeline/bin/verify-spec.sh`); it is **not** flag-free the way a re-run
   against an already-current project is — you still need the values from
   step 2, because this run doesn't attempt recovery itself.
4. Merge in `CHANGELOG.md` impact order. Coming from ≤ v0.2.x also apply
   `migrations/01-delivery-contract.md` to `.agent-pipeline/TEMPLATE.md` and any
   in-flight `.agent-pipeline/T-*.md` (bare `blocked` still validates; nothing
   breaks if you skip it — you just don't get the new guarantees).
5. Create the baseline: `bin/init.sh --refresh-stamp --target <path>`
   (same flags again).

Every later update is then just: pull the toolkit → open the target repo →
`/toolkit-update` (Claude) or `$toolkit-update` (Codex) → done.

### Adding Codex support to an existing scaffold

If the project already has `/toolkit-update`, its Claude lead can run that
command after pulling the toolkit checkout. The command reports the new Codex
files, and its plain `bin/init.sh --target .` step adds them without overwriting
existing files.

A Codex-only user on an older scaffold does not have `$toolkit-update` yet, so
that skill cannot bootstrap itself. After pulling the toolkit checkout, run:

```bash
<toolkit-checkout>/bin/init.sh --update --target <project>  # preview only
<toolkit-checkout>/bin/init.sh --target <project>           # add missing files only
```

For a stamped project the second command loads all original values from
`.agent-pipeline/.toolkit-version`. It installs the Codex skill and planner without
touching customized files; then open Codex and run `$toolkit-update` to
reconcile any reported changes to files that already existed. For a pre-v0.3.0
project with no stamp, follow the flag-recovery procedure above and pass those
values to the plain init command once.

## Using it

The pipeline is a slash command, not a separate program. Once scaffolded,
open Claude Code in the target repo and run:

```
/feature <describe the feature or bug you want fixed>
```

That runs the generated `.claude/commands/feature.md` — the lead reads it,
dispatches `planner` first, and walks the flow in "How it flows" above.

If Claude Code is not installed, open Codex in the target repo and invoke:

```
$feature <describe the feature or bug you want fixed>
```

Codex discovers the generated root `AGENTS.md`, the repository-scoped skill at
`.agents/skills/feature/SKILL.md`, and the planner at
`.codex/agents/planner.toml`. The skill reads the same canonical feature flow,
but uses the Codex planner and OpenCode builder instead of Claude roles.
When the launcher extra is installed, `.agent-pipeline/bin/team.sh` honors a single-leader
profile; all-tools profiles select Claude, then Codex, then OpenCode by availability.
Two things need to be true first:

- `opencode serve` must be reachable — `.agent-pipeline/bin/team.sh` starts it in a
tmux layout (and resumes the lead's own conversation by default — see
[`docs/TEAM.md`](docs/TEAM.md) for that and for running a second project
at the same time), or run `opencode serve` yourself. The neutral leader's
preflight runs authenticated `.agent-pipeline/bin/verify-models.sh`; an unavailable server
is a reported blocker, not permission to silently launch a duplicate.
- The target project needs its own project-specific guidance in `CLAUDE.md` or
  `AGENTS.md`. The generated `AGENTS.md` is an integration entry point with an
  explicitly unpopulated project-guidance section; it does not satisfy this
  requirement until customized. Every generated role file defers
  project-specific constraints to it (see
"Design decisions" below) — without one, a role has nothing binding it
beyond this toolkit's generic rules.

Read `skills/toolkit-init/SKILL.md`'s "After it runs" checklist before
trusting the loop unattended, in particular the reviewer's permission
block — verify it's actually enforced against your real OpenCode server,
not just correct-looking YAML.

The first `/feature` run on a freshly-scaffolded project also asks, once,
whether to fill project guidance with real constraints from your codebase —
gated by a `.agent-pipeline/.needs-customization` marker that `init.sh` drops only
on a genuinely fresh scaffold, deleted the moment it's asked either way.
See `templates/pipeline/roles/leader.md.tmpl`'s preflight; every lead executes the
same check.

## Design decisions, and why

- **Zero dependency, bash + sed only — for the scaffolder itself.**
  `bin/init.sh` needs nothing beyond bash, sed, and diff: scaffolding has
  nothing to install or go stale. The *generated runtime scripts* have a
  small, standard footprint each one documents in its own header:
  `python3` and `curl` everywhere (`oc.sh`), GNU/coreutils `timeout` on
  macOS via `brew install coreutils` (`oc.sh`), and `tmux` if you use
  `.agent-pipeline/bin/team.sh`.
- **Project-specific constraints are never duplicated into the templates.**
Every generated agent file says "read this project's own `CLAUDE.md` /
`AGENTS.md` first" rather than trying to guess or hardcode what a given
project cares about (security posture, banned patterns, style). The
toolkit owns the *process*; each project's own guidance file owns the
*content*.
- **The reviewer defaults to blanket-deny on edit/write.** A prior real run
found that a blanket "deny" configuration still let a reviewer write to a
file outside its intended scope — the enforcement didn't match the
config. `reviewer.md.tmpl` keeps the safe default and documents, inline,
exactly how to verify before loosening it (dispatch the agent, try to
make it edit a source file, confirm it's refused). Do not trust "the
reviewer can't touch source" without having run that check once against
your actual OpenCode server.
- **Sessions are isolated by task and role.** Builder, reviewer, and tester
start separate conversations; retries reuse only the matching role's session.
The reviewer reads the recorded decisions and patch, not the builder's private
trace. Model-family independence is still required. See
[migration 04](migrations/04-team-upgrade.md) for the unified unreleased upgrade.
- **One concise contract per role, thin native adapters.** With three supported
leaders and several native worker backends, duplicated behavioral prose now costs
more than one explicit contract read. Permissions/models/sandboxes stay native;
role behavior lives in `.agent-pipeline/roles/`. Workers never read the leader
workflow. Leaders load backend instructions only when needed, not every provider's
manual. `test/context.py` checks links, word budgets, selective installation, and
unchanged OpenCode permission values; live prompt loading remains a separate check.
- **Profiles reduce installation, not safety.** Select a leader and optional
extras; an explicit all-tools option retains compatibility. Re-scaffolding never
removes older files or overwrites local customization. See docs/CONTEXT.md.



## The `delegate` skill

Independent of `init.sh` — it's about the **lead's** own context, not the
pipeline's shape. Load it (`/delegate` or however skills are invoked in
your setup) at the start of any session that's going to dispatch several
subagents or shell out to `.agent-pipeline/bin/oc.sh` repeatedly. It covers: when a
dispatch is worth its overhead, why raw event streams are the biggest
avoidable context cost, named anti-patterns (circular delegation, context
loss across a handoff, silent scope creep, retrying into a collision)
drawn from real pipeline incidents, and a
four-way rule for simple tasks — one-off simple work you just do yourself,
simple work that recurs becomes a script, judgment that recurs becomes a
Skill, and only genuinely one-off judgment or cross-vendor work becomes a
delegate dispatch. `verify-state.sh` and `promote-findings.sh` exist
because that rule was applied to this toolkit's own pipeline.

```mermaid
flowchart TD
    Task[A task shows up] --> Q1{Recurring?}
    Q1 -- no --> Q2{Needs judgment?}
    Q2 -- no --> Self[Do it yourself - one tool call]
    Q2 -- yes --> Deleg[Dispatch a delegate]
    Q1 -- yes --> Q3{Needs judgment?}
    Q3 -- no --> Script[Write a script under scripts/]
    Q3 -- yes --> Skill[Write it up as a Skill]
```

## The `status-board` skill

Also independent of `init.sh`. A per-task state file stays current on its
own — each role updates it as it works — but nothing rolls that up into a
project-wide "what's the state of everything" view unless something forces
it to happen every time, not just when a task finishes. This skill is that
rule: update the top-level status board (one row per active task: id,
title, live `Status:`, which longer-term checklist item it maps to) at the
end of every pipeline step, and only check off a longer-term checklist box
once a task's `Status:` actually reaches its terminal "done" value, not
when review merely passes or implementation merely finishes. `feature.md`'s
step 5 points at it; load it explicitly for it to apply to every step, not
only the last one.

## Optional: the `self-improvement` skill (off by default)

Not loaded by anything in this toolkit automatically — `feature.md.tmpl`
does not reference it the way it does `delegate` and `karpathy-guidelines`.
That's deliberate: it edits the **lead's own instructions** in response to
something you say mid-session, and self-modifying prompts are a real risk
category worth an explicit opt-in, not a default.

What it does: watches for you correcting the lead's *orchestration* (not a
role's code — that's the reviewer's job) or confirming an unusual approach
worked, and writes the durable version of that lesson into `feature.md` or
the relevant role file — a sentence, not a rewrite — so a future run
doesn't need the same correction twice. It reuses *Findings for docs* +
`promote-findings.sh` for anything that's a project fact rather than a
pipeline-orchestration rule, instead of inventing a second memory
mechanism. Full behavior and guardrails: `skills/self-improvement/ SKILL.md`.

**To enable it in a project:**

1. Copy the file in:
  `cp /path/to/agent-toolkit/skills/self-improvement/SKILL.md .claude/skills/self-improvement/SKILL.md`
   (or wherever your tool discovers skills from — same as `delegate` and
   `karpathy-guidelines`, this toolkit's skills aren't rendered by
   `init.sh`, they're copied in on request).
2. Add one line to that project's own `.claude/commands/feature.md`, next
  to the existing `delegate`/`karpathy-guidelines` line: `If the  "self-improvement" skill is available, load it now.`
3. Read the guardrails in the skill file once before relying on it — it's
  scoped to be conservative (records constraints, never loosens them;
   asks rather than guesses; reports every edit it makes in the same
   turn), but it does write to your pipeline's own instruction files,
   which is a different risk than anything else in this toolkit.



## Adding a new tool, or moving a role to one

Not something `init.sh` does on its own for an untemplated tool — it's a
recipe, not a flag; `skills/toolkit-init/SKILL.md` branches to it when
asked for a tool with no `templates/<tool>/` directory yet. See
`[docs/ADDING-A-TOOL.md](docs/ADDING-A-TOOL.md)`: how to bring a role like
`tester` to a tool it doesn't run under yet, and — only once a role is
actually duplicated across 2+ tools, not before — how to collapse the
duplicated prose into one shared file so a future fix is one edit instead
of N. You can hand that file to an AI directly ("follow
docs/ADDING-A-TOOL.md to add `<tool>` support for `<role>`") and it has
enough to act on without re-deriving the pattern from scratch.

That recipe is for porting a *worker* role to a new tool. Claude, Codex, and
OpenCode lead entry points are generated by `init.sh`; for any other lead AI, use
[`SYSTEM.md`](SYSTEM.md), the tool-agnostic file meant to be handed directly to
that AI.

If most or all of the roles need a tool `init.sh` doesn't template — not
just one role under an otherwise Claude+OpenCode setup —
`skills/dev-team-generator/SKILL.md` runs this same research-then-write recipe as its default path
instead of an escape hatch, and does it self-contained (no dependency on
this repo's own `docs/`/`templates/`), so it also works handed to another
project on its own.

## Known gaps

- `test/smoke.sh` covers the scaffolder's core guarantees (placeholder
  substitution, never-clobber on re-run, `--update` diffing, the
  findings-path traversal guard, the loop-cap and budget checks, the
  refusal to mark a task `done` on an open acceptance criterion or on a
  ticked ledger row that cites no evidence, the refusal to pass a task
  past review with no filled verdict, and `verify-spec.sh`'s three
  cases), and `test/invariants.sh` covers rule presence across the
  hand-synced copies — but nothing yet runs a *live* pipeline end to end
  against a real OpenCode server. **Permission
  enforcement in particular still needs the manual verification described
  under "Design decisions", and remains the single biggest unverified
  assumption in this toolkit.**
- The checks are structural by design. They can tell you a spec is
  unfinished, a budget is blown, or a criterion was closed without
  evidence; they cannot tell you the spec is *wrong* or the evidence is
  *good*. That judgement is still the reviewer's, the tester's, and yours
  at the approval and merge gates.
- Nothing here validates that a given OpenCode `vendor/model` string is
  real — `opencode models` is the source of truth and isn't queried by
  `init.sh` automatically.

## Reviews and upgrading

- [`docs/UPGRADING.md`](docs/UPGRADING.md) — how an already-scaffolded
  project stays current with this toolkit: the provenance stamp, the
  impact-tagged `CHANGELOG.md`, `--update`'s triage mode, `migrations/`,
  and `/toolkit-update`. See "Updating a project" above for the commands;
  this file is the reasoning behind them.
- [`docs/BACKLOG.md`](docs/BACKLOG.md) — current open verification work, policy
  decisions, and accepted tradeoffs. Historical reviews remain in Git history.
- [`docs/PERMISSIONS.md`](docs/PERMISSIONS.md) — live permission verification;
  configured rules are not proof of enforcement or filesystem isolation.
