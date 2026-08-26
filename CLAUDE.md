# agent-toolkit

A reusable, project-agnostic version of the planner → implement → review →
test multi-agent pipeline. `bin/init.sh` scaffolds it into any target repo:
Claude subagents for planning/implementing, OpenCode (any vendor) for
cross-vendor implement/review/test, a state file (`.agents/T-<id>.md`) as the
one handoff surface between roles, and a `delegate` skill that keeps the
orchestrating lead's own context small across a long run.

It was distilled from real multi-agent pipeline runs and hardened there
over time, so the same setup — permissions, session-reuse policy,
cross-vendor independence rules, the state-file contract, the
context-discipline rules — doesn't get re-invented and re-debugged from
scratch in every new repo. Read
`README.md` first for the pitch, the file tree, and the documented design
tradeoffs; this file is for someone (human or agent) actively changing the
toolkit's own code.

## Commands

No build step, no dependencies, no LLM calls in the test path. Verify a
change with the automated smoke run:

```bash
bash test/smoke.sh        # scaffolder guarantees + the two structural scripts
bash test/invariants.sh   # every load-bearing rule present in every copy
```

`smoke.sh` scaffolds into a throwaway directory and asserts the core
guarantees: every placeholder substituted, no file clobbered on re-run,
the provenance stamp written once and never touched by `--update`,
`--update` triage (summary-first, exit 0 clean / 1 drift, hunks behind
`--diff`/`--only`, flags defaulted from the stamp), the findings-promotion
traversal guard, the loop-cap and budget checks fire, `verify-state.sh`
refuses `done` while an acceptance criterion is open, and `verify-spec.sh`
rejects an unfilled spec while accepting a filled one.

`invariants.sh` is the other half: it greps each load-bearing rule against
every hand-synced copy that must carry it. Run it after **any** change to
the pipeline's rules — it is what the "keep the copies in sync" convention
below finally has behind it. CI runs both plus shellcheck on every push
(`.github/workflows/ci.yml`). For an eyeball-level pass you can still do
the manual version:

```bash
mkdir -p /tmp/toolkit-smoke && bash bin/init.sh \
  --target /tmp/toolkit-smoke --project-name x \
  --builder-model a/b --reviewer-model a/c \
  --reviewer-fallback-model d/e --tester-model a/b
grep -rl '__[A-Z_]*__' /tmp/toolkit-smoke   # must print nothing — no unfilled placeholder
rm -rf /tmp/toolkit-smoke
```

Re-run `init.sh` a second time against the same target to confirm existing
files are skipped, not clobbered (`render()`'s core guarantee).

## Architecture

| Path | Role |
| --- | --- |
| `bin/init.sh` | The scaffolder. `render()` copies a `.tmpl` file to a destination with `sed` placeholder substitution, skipping any file that already exists |
| `test/smoke.sh` | The automated smoke run (see Commands). CI runs it plus shellcheck on every push |
| `test/invariants.sh` | Cross-file rule presence check: one grep per (rule, file) pair over the hand-synced copies. Add a rule = one line in its table |
| `.github/workflows/ci.yml` | Runs `test/smoke.sh` + shellcheck (`bin/init.sh`, the test, and every `templates/scripts/*.tmpl`) |
| `templates/claude/agents/` | `planner.md.tmpl`, `senior-dev.md.tmpl` — Claude subagent role definitions |
| `templates/claude/commands/` | `feature.md.tmpl` — the `/feature` pipeline command (the lead's own instructions); `toolkit-update.md.tmpl` — the `/toolkit-update` merge command for already-scaffolded projects |
| `templates/opencode/agent/` | `builder.md.tmpl`, `reviewer.md.tmpl`, `tester.md.tmpl` — OpenCode role definitions |
| `templates/agents-state/` | `TEMPLATE.md.tmpl` — the `T-<id>` state-file shape every role reads and appends to |
| `templates/scripts/` | `oc.sh.tmpl` (OpenCode CLI wrapper), `team.sh.tmpl` (+ `team-completion.bash.tmpl`; tmux layout), `verify-state.sh.tmpl` (state file) / `verify-spec.sh.tmpl` (spec, before the approval gate) / `promote-findings.sh.tmpl` — all deterministic, no-LLM-call structural checks |
| `skills/delegate/` | Context-discipline rules for the lead — usable independently of `init.sh` |
| `skills/toolkit-init/` | Thin skill wrapping `bin/init.sh`, for running the scaffold conversationally |
| `skills/dev-team-generator/` | Self-contained, interview-driven alternative to `toolkit-init`: generates the team + flow live for whatever tool(s) are actually available, instead of stamping out `templates/`. Its own `reference/lessons-learned.md` is a generalized, tool-agnostic distillation of this toolkit's hardening history — see the Conventions bullet below |
| `skills/status-board/` | Keeps a project-wide status board in sync with per-task state files — independent of `init.sh` |
| `skills/karpathy-guidelines/` | Behavioral defaults loaded by the lead via `feature.md`; inlined into senior-dev/builder rather than granted Skill access |
| `skills/self-improvement/` | Optional, off by default: lead-only capture of user corrections into its own instruction files. Never auto-loaded |
| `SYSTEM.md` | Tool-agnostic one-pager meant to be handed to any AI ("recreate this system with yourself as lead") |
| `CHANGELOG.md` | Impact-tagged per-release entries (`[contract]` › `[safety]` › `[process]` › `[docs]`). Append an entry in the same commit as any template/script change — this is what lets a downstream project triage an update without reading raw diffs |
| `migrations/` | Numbered, hand-appliable notes for `[contract]` changes only. No migration runner, by design. Write one in the same commit as the contract change it describes |
| `docs/UPGRADING.md` | The downstream-update plan (provenance stamp → tags/changelog → `--update` triage → migrations → `/toolkit-update`); stages 1–5 are implemented in `bin/init.sh` + `CHANGELOG.md` + `migrations/` |
| `REVIEW.md` / `REVIEW-2.md` | Point-in-time honest reviews; see each file's status section for applied vs open items |
| `REVIEW-2.md` | Third review pass — the delivery contract (acceptance criteria are never marked met by anyone), the status state machine, the missing team-charter layer. Does not repeat `REVIEW.md`; its Part D re-ranks and prunes that file's backlog |
| `docs/UPGRADING.md` | Staged plan for keeping an already-scaffolded downstream project current: provenance stamp, tagged releases + impact-classified changelog, `--update` triage, AI-assisted merge |

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
- **Keep `templates/` and any applied copy of this toolkit in sync** (any
  repo that has scaffolded it, with its own `.claude/` + `.opencode/` +
  `.agents/TEMPLATE.md`) when one side gets a
  structural fix — a new state-file field, a new script, a report-back
  change. They're meant to be the same mechanism, generic vs. applied.
  `test/invariants.sh` covers the state-file contract's two copies; the
  rest is still by hand — `diff` the two sides after any pipeline-mechanism
  change.
- **The lead's flow exists in three hand-synced copies — re-diff all
  three when the pipeline sequence changes:**
  `templates/claude/commands/feature.md.tmpl`, `SYSTEM.md`, and
  `skills/dev-team-generator/reference/flow-example.md`. They serve three
  audiences (generated project / any-AI-as-lead / generate-anything skill)
  but must carry the same sequence and stop-and-ask rules. These have
  diverged silently before — twice, on consecutive commits, *after* this
  bullet was written, which is why the rule alone was never enough.
  **`test/invariants.sh` now enforces it**: add the rule to its table in the
  same turn you add it to a flow copy, and CI fails when a copy is missing
  it. The table is presence-only (it cannot catch wording drift), so still
  read the sibling copies — but omission, the failure that actually keeps
  happening, is now caught for you. Check all three plus
  `lessons-learned.md` per the next bullet.
- **Mirror every new hardening lesson into
  `skills/dev-team-generator/reference/lessons-learned.md`, in the same
  turn.** This toolkit's real lessons — a live-verified gotcha, a
  reliability fix, an incident and what actually fixed it — mostly surface
  first as a change to one specific template (`oc.sh.tmpl` gaining
  session-abort-on-timeout, `senior-dev.md.tmpl`'s testing rhythm getting
  scoped, and so on) or in a project applying this toolkit. Whenever that
  happens, add or update the corresponding entry in
  `lessons-learned.md` too, written generalized — the mechanism and the
  reason, not the originating tool's specific flag/endpoint name (that
  file already explains why: it exists so a lesson earned once against
  OpenCode, say, doesn't have to be re-earned by a future project running
  some other tool entirely). This is a distinct sync step from the bullet
  above: that one keeps the Claude+OpenCode *mechanism* consistent across
  `templates/` and its applied copies; this one keeps the *generalized
  knowledge* available to `dev-team-generator`'s any-tool generation path,
  which doesn't read `templates/` at all. A change that's purely
  mechanical (a typo fix, a formatting change) doesn't need this; a change
  that exists *because* something failed, or because live verification
  proved or disproved an assumption, does.

## Gotchas

- `render()` prints `skip (exists)` and leaves the file alone when the
  destination already exists — if an edit to a `.tmpl` file doesn't show up
  after a re-run against an existing target, that's why, not a bug in
  `init.sh`. Use `init.sh --update` to see what changed instead.
- `.agents/.needs-customization` is written only when `FRESH_SCAFFOLD` was
  true *before* any `render()` call ran (checked via whether
  `.claude/commands/feature.md` already existed) — never on `--update`,
  and never again once deleted. The provenance stamp
  (`.agents/.toolkit-version`) follows the same ordering rule: written
  exactly once on a fresh scaffold, never by `--update` (that would erase
  the baseline it exists to record), rewritten only by an explicit
  `--refresh-stamp` after a merge is accepted. If you add a new
  marker-gated behavior, keep that "computed once, before any write"
  ordering or a later non-fresh `init.sh` run will re-trigger it.
- `templates/opencode/agent/reviewer.md.tmpl` defaults to blanket
  `edit: deny` / `write: deny`, unlike a project that has since widened its
  own copy (e.g. an applied copy's reviewer allows
  `.agents/**`). That gap is intentional — see README's "Design decisions"
  — not drift to fix by copying the widened version back over the
  template.
- A permission block that reads correctly in YAML is not proof it's
  enforced by the runtime. This toolkit's safe-default posture exists
  because that assumption failed once in a real pipeline. Any change to a
  permission block in a template should carry a note
  to verify it live (dispatch the agent, try the disallowed action,
  confirm it's refused) rather than just reading the config.

## Status

Actively developed; history in git. The scaffolder's core guarantees are
covered by `test/smoke.sh`, and cross-copy rule presence by
`test/invariants.sh` (CI: both + shellcheck). What's *not*
automated: a live end-to-end pipeline run against a real OpenCode server,
and live permission-enforcement verification — those stay manual per
README's "Design decisions". Treat README.md's "Known gaps" and
REVIEW.md's open items as the backlog.
