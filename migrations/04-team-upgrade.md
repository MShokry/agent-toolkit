# Migration 04 — One coordinated major team upgrade

Breaking contract/process change introduced in v1.0.0. This is the single
coordinated migration after v0.10.2; published migrations 01–03 remain unchanged
and apply first when required. No release/tag is created by this guide.

## Final layout

```text
.agent-pipeline/
  README.md                 # portable leader guide; opt-in context
  bin/                      # all toolkit runtime scripts, including validators
  tasks/TEMPLATE.md
  tasks/T-<id>.md            # authoritative task records
  roles/                    # compact role contracts
  adapters/                 # selected backend dispatch instructions
  prompts/T-<id>/
  logs/T-<id>/               # transcripts, patches, immutable session bindings
  .toolkit-version          # approved provenance/config; layout_schema: 2
```

Native discovery files stay in .claude/, .codex/, .opencode/, .agents/skills/;
project-owned root AGENTS.md/CLAUDE.md stay in place. Never globally rename these.
User-owned scripts stay in scripts/. Only known toolkit script names relocate.

## 1. Pause and review the complete upgrade

Finish or explicitly park work with a recorded handoff. Confirm ALL lead/worker
turns inactive, including interrupted remote work; a local wrapper receipt is
not proof. Unknown background dispatches and lead locks block the mover. Back up
local guidance/config and preserve the baseline/models. Never change a live task
contract. Choose leader/extras/model changes explicitly; otherwise preserve them.

From the target project:

```bash
TOOLKIT=/path/to/agent-toolkit
bash "$TOOLKIT/bin/init.sh" --update --target .
python3 "$TOOLKIT/bin/migrate-layout.py" plan --project .
```

Both are read-only. Preview compares old files to final destinations rather
than treating customized scripts/template as missing. Inspect the plan's exact
source/target paths and diffs, including hook and scoped permission path changes.
Permission VALUE changes still require separate approval/live verification.
Review the plan's `attention` entries as well: retained legacy artifacts/custom
scripts and unsupported bare/reference-style artifact links require explicit
mapping or caller review, not guessed automatic cleanup. Only moved task records
get task-relative artifact link adjustments; guidance remaining at the root keeps
its original relative links.
The tester's former whole-core write grant narrows to tasks/T-*.md, and the
leader's automatic edits narrow to tasks/prompts/logs. This prevents moving bin/
under a state grant from implicitly granting edits to executable tooling. Review
these permission-resource changes explicitly and verify them live; shell remains
a separate guardrail, not filesystem isolation. Other action/effect values stay.

## 2. Apply the approved bulk layout move once

After human review/approval and actual inactivity confirmation:

```bash
python3 "$TOOLKIT/bin/migrate-layout.py" apply --project . \
  --approve <approval-digest-from-reviewed-plan> --workers-inactive
```

The CLI recomputes the plan; changed inputs invalidate approval. It refuses
collisions/symlinks and published pre-.agent-pipeline layouts. Move task files/
template into tasks/ and known scripts into bin/; rewrite known toolkit callers,
root calculations, hook paths, and relative Markdown artifact links. Artifacts,
credentials, provenance, sessions, custom rules and native directories are NOT
discarded or silently reconfigured. Unknown custom callers outside its documented
scope need reviewed manual updates; the script does not claim to discover them all.

Private backups and the exact plan remain in `.agent-pipeline/.layout-backup-*/`.
The lock prevents competing migration runs. Failure rolls back only known owned
bytes; concurrent user edits are preserved and may require manual recovery from
backup. Never blindly remove stale locks or overwrite collision destinations.
Plain init/stamp refresh refuse an old root-task layout, preventing split state.

## 3. Bootstrap missing dependencies and merge existing files together

```bash
PROFILE=(--leader codex --extras herdr) # choose your desired team, or omit overrides
bash "$TOOLKIT/bin/init.sh" --target . "${PROFILE[@]}"
bash "$TOOLKIT/bin/init.sh" --update --target . "${PROFILE[@]}" --diff
```

Use the SAME approved profile/model flags for bootstrap, per-file previews and
stamp refresh. Legacy stamps without profile fields mean all tools/extras.
If the project deliberately disabled reviewer fallback, preserve that selection
with `--reviewer-fallback-model none` in every command; never accept a default
provider merely because the old stamp omitted the field. The sentinel is not
dispatchable. Missing fallback in an old stamp defaults to disabled, never a new
provider; ambiguous unstamped recovery asks for an explicit fallback flag.
Stamp refresh preserves project extension fields (including planner and builder
fallback assignments) and notes; it updates only generator-owned fields.
Plain init ADDS missing files only; it does NOT overwrite existing moved scripts,
adapters or customizations. Do not dispatch during partial reconciliation.

Merge final role contracts, selected adapters, entrypoints, hooks, task template,
and structural/runtime scripts as one reviewed upgrade. Transfer local behavior
to its neutral role/project guidance; retain native model/permission/sandbox
metadata. Workers must not activate leader/feature routing. The shareable README
embeds the canonical leader body; keep accepted local rules/snapshot consistent.
Smaller profiles never delete old discovery files; retirement needs explicit
file-by-file approval. No automatic retry, execution allowlist, or approval bypass.

## 4. Adopt the compact task metadata safely

New tasks use one table under `## Role assignments`:
Keep the generated `<!-- task-schema: 2 -->` marker; it prevents a missing table
from being mistaken for a historical legacy record.

| Role | Backend | Model | Family | Session / thread |
| --- | --- | --- | --- | --- |
| planner | pending | pending | pending | pending |
| implementer | pending | pending | pending | pending |
| reviewer | pending | pending | pending | pending |
| tester | pending | pending | pending | pending |

Backend is opencode/codex/claude; Model is the full configured/resolved assignment;
Family is the actual model-maker, not a provider/harness label. Class decided by
stays pending until confirmed. Consent fields and 2/2/1 budgets remain separate;
the LEAD alone increments every counter and fills acceptance outcomes.

Historical completed tasks need no metadata rewrite: legacy headers remain
readable at their new path. Never mix legacy session headers with the new table.
For a parked task, preserve prior IDs/assignments as history in Decisions and
start fresh per-role conversations after confirmed inactivity. A shared old id
is never copied into every row. Reviewer model/backend changes need a fresh id.
Every dispatch uses unused immutable artifact paths and an explicit current patch.

After recording first receipts, use task-record.py bind to retain immutable
role/backend/model/session evidence; use its session operation before resume.
Missing/mismatched binding blocks reuse. Record unavailable transcript exports
honestly. Independent reviewer families are mandatory; unknown identity blocks
claims of independence. Read-only findings are persisted unchanged by the lead.

## 5. Selected optional capabilities

- Native Codex workers require verified discovery/model/sandbox/resume, not just
  valid files/catalogs. Native aliases never reach oc.sh. Read-only reviewers
  return full findings; native testers never fix tests/source. Workspace-write
  does not enforce narrower scope. OpenAI authors need a different-family reviewer.
- Exact Codex lead capture uses normally trusted, additively merged hooks. Existing
  leads may need their exact /status id pinned manually per team name. Never use
  latest-session lookup or fallback on failed resume; --fresh is explicit.
- External Claude review needs task consent, hook/settings audit, and manual
  confirmation for unchecked model/runtime assignments. Read/search restrictions
  do not disable hooks or provide OS isolation. Separate reviewer UUID/bindings.
- Herdr plugin update/relink stays explicit. Its tools tab preserves the lead;
  empty support shells launch no duplicate agent/server. Host idle/done is not
  verification. No permission-alias adjustment is included.

## 6. Validate, then accept provenance

Run `.agent-pipeline/bin/verify-state.sh <task-id>` on representative legacy/new
records and verify-spec on complete specs. Inspect dashboard --once if installed.
Check fresh role loading, permissions, identity and resume live before trusting
them; catalogs/static tests do not establish enforcement. See docs/PERMISSIONS.md,
docs/CONTEXT.md and docs/BACKLOG.md. Test in a disposable project copy first.

After approved merges/validation:

```bash
bash "$TOOLKIT/bin/init.sh" --refresh-stamp --target . "${PROFILE[@]}"
bash "$TOOLKIT/bin/init.sh" --update --target .
.agent-pipeline/bin/verify-models.sh
```

Final preview should show only intentionally retained local differences. Stamp
refresh is not proof of merges. Record merged/kept-local/deferred items. Start a
fresh lead from recorded state at the approved boundary, avoiding old loaded
instructions. Commit/release only when separately authorized.
