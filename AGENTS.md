# agent-toolkit — maintainer guidance

Read `README.md` first. This toolkit scaffolds a planner → implement → review →
test pipeline with Claude, Codex, or OpenCode as lead and `.agent-pipeline/` as
the task-record surface. Project guidance owns code constraints; the toolkit
owns process. `CLAUDE.md` points here so maintainer rules have one source.

## Verification

```bash
bash test/smoke.sh
bash test/invariants.sh
python3 test/runtime.py
python3 test/herdr.py
python3 test/context.py
python3 test/layout.py
```

No LLM calls are required for these tests. CI also runs ShellCheck on shell
scripts/templates. Runtime tests need Python 3.11+ for the standard TOML parser.
Live pipeline and permission-enforcement checks remain
manual; see `docs/PERMISSIONS.md` and `docs/BACKLOG.md`.

## Structure

| Path | Purpose |
| --- | --- |
| `bin/init.sh` | Scaffold, preview updates, refresh provenance; never overwrite existing generated files |
| `bin/migrate-layout.py` | Read-only plan / approved transactional layout move with private backups |
| `bin/release.sh`, `skills/toolkit-release/` | Checked tag/push and conversational release approval |
| `templates/pipeline/` | Compact neutral role contracts and lazily loaded dispatch adapters |
| `templates/claude/` | Thin native feature/worker adapters and the reconciliation source |
| `templates/codex/` | Codex lead instructions/skills, planner, and optional native worker adapters |
| `templates/opencode/agent/` | Active builder/reviewer/tester definitions in supported legacy syntax |
| `templates/opencode/agents/`, `templates/opencode/commands/` | Native OpenCode lead/planner adapters and commands |
| `templates/agents-state/`, `templates/scripts/` | Task contract and deterministic runtime/check scripts |
| `integrations/herdr/`, `bin/dashboard` | Optional host integration and standalone read-only viewer |
| `skills/` | Reusable skills; the generator's references are self-contained |
| `test/`, `.github/workflows/ci.yml` | Scaffold, cross-copy, and host-adapter tests |
| `CHANGELOG.md`, `migrations/`, `docs/UPGRADING.md` | Impact-tagged releases and downstream reconciliation |
| `SYSTEM.md`, `docs/BACKLOG.md` | Tool-independent flow and current open work |

## Load-bearing conventions

- Keep the scaffolder dependency-free: bash and standard shell utilities, not
  Node/npm tooling. Python is only needed by optional UI/runtime features.
- `render()` never overwrites an existing target file. Update preview writes
  nothing; local customizations survive re-scaffolding.
- Templates read the target project's `CLAUDE.md` / `AGENTS.md`; do not bake in
  project-specific security or style constraints.
- Role replies are short receipts: verdict/count and Latest handoff, not a
  second copy of the diff, findings, or test output already in the task record.
- Keep generated/applied copies in sync when the task contract, scripts, or
  report-back shape changes. Do not copy widened downstream permissions back
  into the safer upstream reviewer template without explicit approval.
- Reconcile the canonical flow and its explanatory copies when rules change:
  `templates/pipeline/roles/leader.md.tmpl`, `SYSTEM.md`, and
  `skills/dev-team-generator/reference/flow-example.md`. Add load-bearing rules
  to `test/invariants.sh` in the same change. Presence checks do not replace
  reading sibling copies for wording drift.
- Keep feature entrypoints thin and explicit workers out of lead routing.
  Test contract links/word budgets/profile selection in `test/context.py`.
  Changing model provider assignments must not add another behavioral flow.
- Mirror reliability lessons into
  `skills/dev-team-generator/reference/lessons-learned.md` in the same change,
  generalized to the mechanism and reason rather than tool-specific flags.
- Add a `CHANGELOG.md` entry with template/script changes. Contract changes also
  need a numbered migration note. Preserve historical entries and migrations.
- Keep native `.agents/skills/` separate from `.agent-pipeline/`; never globally
  replace or rename tool-discovery paths during state migration.

## Gotchas

- Compute `FRESH_SCAFFOLD` before any render call. The customization marker and
  provenance stamp are written only on a genuine fresh scaffold; `--update`
  never writes them. Only explicit `--refresh-stamp` updates the baseline.
- Existing files are skipped, not refreshed. Use `--update` to inspect drift.
- The reviewer intentionally denies all edits/writes by default. Permissions
  are guardrails, not filesystem isolation; verify enforcement live using the
  exact generated artifact in a fresh runtime before trusting any change.
- Do not delete compatibility handling merely because it mentions an old
  version. Downstream upgrades still depend on legacy stamp/state discovery.
