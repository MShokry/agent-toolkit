# agent-toolkit

A reusable, project-agnostic version of the planner → implement → review →
test multi-agent pipeline. `bin/init.sh` scaffolds it into any target repo:
Claude subagents for planning/implementing, OpenCode (any vendor) for
cross-vendor implement/review/test, a state file (`.agents/T-<id>.md`) as the
one handoff surface between roles, and a `delegate` skill that keeps the
orchestrating lead's own context small across a long run.

It was extracted from a real project (a browser extension) so the same
setup — permissions, session-reuse policy, cross-vendor independence rules,
the state-file contract, the context-discipline rules — doesn't get
re-invented and re-debugged from scratch in every new repo. Read
`README.md` first for the pitch, the file tree, and the documented design
tradeoffs; this file is for someone (human or agent) actively changing the
toolkit's own code.

## Commands

No build step, no dependencies, no test runner yet (see README's "Known
gaps"). Verify a change with a manual smoke run into a scratch directory:

```bash
mkdir -p /tmp/toolkit-smoke && bash bin/init.sh \
  --target /tmp/toolkit-smoke --project-name x \
  --builder-model a/b --reviewer-model a/c \
  --reviewer-fallback-model d/e --tester-model a/b
grep -rl '__[A-Z_]*__' /tmp/toolkit-smoke   # must print nothing — no unfilled placeholder
find /tmp/toolkit-smoke -type f | wc -l     # should match the file count bin/init.sh reports
rm -rf /tmp/toolkit-smoke
```

Re-run `init.sh` a second time against the same target to confirm existing
files are skipped, not clobbered (`render()`'s core guarantee).

## Architecture

| Path | Role |
| --- | --- |
| `bin/init.sh` | The scaffolder. `render()` copies a `.tmpl` file to a destination with `sed` placeholder substitution, skipping any file that already exists |
| `templates/claude/agents/` | `planner.md.tmpl`, `senior-dev.md.tmpl` — Claude subagent role definitions |
| `templates/claude/commands/` | `feature.md.tmpl` — the `/feature` pipeline command (the lead's own instructions) |
| `templates/opencode/agent/` | `builder.md.tmpl`, `reviewer.md.tmpl`, `tester.md.tmpl` — OpenCode role definitions |
| `templates/agents-state/` | `TEMPLATE.md.tmpl` — the `T-<id>` state-file shape every role reads and appends to |
| `templates/scripts/` | `oc.sh.tmpl` (OpenCode CLI wrapper), `team.sh.tmpl` (tmux layout), `verify-state.sh.tmpl` / `promote-findings.sh.tmpl` (deterministic, no-LLM-call structural checks) |
| `skills/delegate/` | Context-discipline rules for the lead — usable independently of `init.sh` |
| `skills/toolkit-init/` | Thin skill wrapping `bin/init.sh`, for running the scaffold conversationally |

## Conventions

- **Zero dependencies, bash + sed only.** Do not add Node/npm tooling to the
  scaffolder itself, even for something `bin/init.sh` would find easier
  with them.
- **`render()` never overwrites an existing file in the target.** That's
  what makes re-running `init.sh` safe and lets a project's own
  customizations survive a re-scaffold. Don't change that default.
- **Templates never hardcode project-specific constraints.** Every
  generated role file says "read this project's own `CLAUDE.md` /
  `AGENTS.md` first" rather than guessing at a target project's security
  posture, banned patterns, or style. The toolkit owns the *process*; the
  target project's own guidance file owns the *content*. If you're tempted
  to bake in a specific rule (e.g. "never use `innerHTML`"), it belongs in
  an example project's own `CLAUDE.md`, not here.
- **Every generated role's reply to the lead is short by design** — a
  verdict line, a pass/fail count, the Latest-handoff line — never a copy
  of the diff, findings, or test output it already wrote to the state
  file. This is deliberate: it's what keeps the orchestrating lead's
  context small across a long pipeline run. When editing a role template's
  "Report"/"Output" section, preserve that shape rather than reverting to
  "report your findings/output to the lead."
- **Keep `templates/` and any applied copy (e.g. `vivaldi-extension`'s own
  `.claude/` + `.opencode/` + `.agents/TEMPLATE.md`) in sync** when one
  side gets a structural fix — a new state-file field, a new script, a
  report-back change. They're meant to be the same mechanism, generic vs.
  applied. There is no automated check for this yet; do it by hand and
  `diff` the two sides after any pipeline-mechanism change.

## Gotchas

- `render()` prints `skip (exists)` and leaves the file alone when the
  destination already exists — if an edit to a `.tmpl` file doesn't show up
  after a re-run against an existing target, that's why, not a bug in
  `init.sh`.
- `templates/opencode/agent/reviewer.md.tmpl` defaults to blanket
  `edit: deny` / `write: deny`, unlike a project that has since widened its
  own copy (e.g. `vivaldi-extension`'s `.opencode/agent/reviewer.md` allows
  `.agents/**`). That gap is intentional — see README's "Design decisions"
  — not drift to fix by copying the widened version back over the
  template.
- A permission block that reads correctly in YAML is not proof it's
  enforced by the runtime. This toolkit's safe-default posture exists
  because that assumption failed once in the project it was extracted
  from. Any change to a permission block in a template should carry a note
  to verify it live (dispatch the agent, try the disallowed action,
  confirm it's refused) rather than just reading the config.

## Status

No commits yet as of writing — everything here is uncommitted working
state. No CI, no automated test for `init.sh` beyond the manual smoke run
above. Treat README.md's "Known gaps" section as the actual backlog.
