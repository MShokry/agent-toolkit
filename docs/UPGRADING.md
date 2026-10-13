# Updating a scaffolded project

Generated files are project-owned copies, not a package to overwrite. Update
at a task boundary and preserve local customizations.

## v1.0.2 opt-in activation update

[Migration 05](../migrations/05-manual-team-activation.md) removes automatic team
routing from generated startup guidance. Fresh AGENTS.md is only a project-guidance
bridge to CLAUDE.md; commands and a copyable prompt are documented in README.md.
Existing guidance is never overwritten. Merge out old routing paragraphs explicitly,
preserve project constraints, and start a fresh conversation to drop loaded rules.

## v1.0.0 upgrade: one migration

Projects on **v0.10.2** use [migration 04](../migrations/04-team-upgrade.md)
once. It combines the formerly separate unreleased drafts 04–07: role sessions,
optional native workers/review, exact lead resume, and lean contracts/profiles.
The final major layout uses bin/ for runtime and tasks/ for task records, plus
one typed role table. There are no intermediate releases to install. Published migrations 01–03 stay
separate and apply first only when the project's baseline/layout requires them.

The upgrade is **preview → approved bulk layout move → add missing dependencies → reviewed merge → validate
→ refresh provenance → fresh lead**. It is not automatic replacement:

- `--update` writes nothing; exit 1 reports drift/new files or required migration.
- Before bootstrap, review `python3 "$TOOLKIT/bin/migrate-layout.py" plan --project .`.
  Apply only with its reviewed approval digest and confirmed inactive workers.
  It refuses collisions/symlinks and retains private backups; native paths stay put.
- Plain init adds missing selected files and skips EVERY existing file. It does
  not shrink an old feature prompt or convert an old agent definition by itself.
  This also bootstraps the shareable `.agent-pipeline/README.md`; existing guides
  need reviewed merges, and stamp refresh alone never updates their contents.
- The lead reviews/merges existing entrypoints, role adapters, task template,
  and scripts together. Local constraints move into the proper neutral contract
  or project guidance; native permissions remain unchanged unless separately approved.
- A smaller profile does not delete old files. Any retirement/removal needs an
  explicit reviewed plan; extra discovery files may otherwise remain visible.
- Stamp refresh records the accepted inputs/version, not proof of a successful
  merge. Start a fresh lead after the boundary to avoid old loaded instructions.

For example, from a target project choosing Codex + Herdr:

```bash
TOOLKIT=/path/to/agent-toolkit
PROFILE=(--leader codex --extras herdr)
bash "$TOOLKIT/bin/init.sh" --update --target . "${PROFILE[@]}"
python3 "$TOOLKIT/bin/migrate-layout.py" plan --project .
# Review the plan and confirm inactivity, then:
python3 "$TOOLKIT/bin/migrate-layout.py" apply --project . \
  --approve <reviewed-approval-digest> --workers-inactive
bash "$TOOLKIT/bin/init.sh" --target . "${PROFILE[@]}"
# Stop here: review and merge existing files per migration 04. Do not dispatch.
# After approval and validation:
bash "$TOOLKIT/bin/init.sh" --refresh-stamp --target . "${PROFILE[@]}"
bash "$TOOLKIT/bin/init.sh" --update --target .
```

For an all-tools installation, an additional read-only/project-copy check is:
`python3 "$TOOLKIT/test/project.py" --project .`. It checks installed contracts
and runs installed runtime scripts with mocked CLIs in disposable fixtures,
including findings promotion in a disposable fixture. It is not a live permission,
model-identity, native-discovery, or application/device test.

Choose claude/opencode/all instead if desired. Keep existing model assignments
unless explicitly changing them; add the same model flags to every command when
you do. Retain all-tools by omitting profile flags on a legacy stamp. Run model
preflight against the accepted stamp before new work; verify discovery/permissions
live. Herdr plugin update/relink and hook trust review remain explicit opt-ins.

An old `/toolkit-update` still leads the reconciliation, but must read the current
migration before bootstrap: its old instructions may not know the new profile or
neutral paths. New update entrypoints load `.agent-pipeline/update.md` for future
upgrades. This section documents the coordinated v1.0.0 upgrade.

## Standard workflow

1. Update your toolkit checkout and record its SHA/tag.
2. Read `.agent-pipeline/.toolkit-version` in the target for the baseline and
   original scaffold inputs. Before directory migration, read the legacy
   `.agents/.toolkit-version` instead.
3. Preview from the target project:

   ```bash
   /path/to/agent-toolkit/bin/init.sh --update --target .
   ```

   Exit 0 means the checked templates match; exit 1 means drift or a required
   directory migration. Preview writes nothing. Summary paths identify new or
   differing files; impact classifications come from the changelog, not from
   automatic classification of each diff.
4. Read changelog entries after the baseline in impact order:
   `[contract]` → `[safety]` → `[process]` → `[docs]`. Apply numbered migration
   notes first. Show permission changes separately, obtain explicit approval,
   and verify enforcement live afterward.
5. Inspect each change:

   ```bash
   /path/to/agent-toolkit/bin/init.sh --update --target . --only .agent-pipeline/bin/oc.sh --diff
   ```

   Choose upstream, keep local, or hand-merge. Never silently overwrite a local
   customization. Add genuinely missing files with a plain run only after any
   directory migration is complete:

   ```bash
   /path/to/agent-toolkit/bin/init.sh --target .
   ```

   This loads stamped inputs and skips existing files. It also adds missing
   runtime ignore rules in Git checkouts. If preview used profile/model override
   flags, repeat them in bootstrap, per-file previews, and stamp refresh too.
6. Validate the latest task with `.agent-pipeline/bin/verify-state.sh <id>` and, if installed,
   inspect `.agent-pipeline/bin/dashboard --once`. Refresh provenance only after accepting the
   merge:

   ```bash
   /path/to/agent-toolkit/bin/init.sh --refresh-stamp --target .
   /path/to/agent-toolkit/bin/init.sh --update --target .
   ```

   Refreshing provenance does not remove intentional local differences.
   Report merged, kept-local, and deferred items and record the new baseline.

Claude/OpenCode `/toolkit-update` and Codex `$toolkit-update` guide this same
reconciliation. If an older installed command conflicts with a current
migration, follow the current migration before its bootstrap step.

## Legacy layouts and unstamped projects

- [Migration 04](../migrations/04-team-upgrade.md) covers role isolation, compact
  contracts/profile selection, and optional Codex workers/lead capture/Claude
  review together. Preserve completed task records; never copy a legacy shared
  id into every role field. Keep OpenCode defaults unless native roles are chosen;
  hand-merge hooks, use normal trust review, and verify live capability/independence.
- For optional two-tab Herdr hosting, bootstrap `.agent-pipeline/bin/herdr-team.sh` with
  plain init and explicitly update/relink the reviewed host plugin; setup preserves
  the existing lead and starts the dashboard in a separate tools tab. No task
  migration or agent permission change is required.

- Pipeline records under `.agents/` require
  [migration 03](../migrations/03-pipeline-directory.md). The lead may execute
  an approved move plan with paused readers/workers, backups, collision checks,
  coordinated reference changes, and rollback. Keep `.agents/skills/` in place.
- Plain init and stamp refresh refuse detected legacy layouts to prevent two
  competing task-record directories. Read-only preview can still read the old
  stamp and compare the old state template.
- An unstamped project's preview infers original inputs from generated files.
  Verify the recovered values; supply missing inputs explicitly. Use the same
  values for the plain bootstrap and initial stamp refresh. See README's
  pre-v0.3.0 procedure and migrations 01/02 for earlier contract changes.

## Adding the project dashboard

After required migrations, preview and install the self-contained viewer. If the
profile does not already include it, select a new extras list that retains any
other desired extras (example below adds dashboard only):

```bash
/path/to/agent-toolkit/bin/init.sh --update --target . --extras dashboard --only .agent-pipeline/bin/dashboard
/path/to/agent-toolkit/bin/init.sh --target . --extras dashboard
./.agent-pipeline/bin/dashboard --once
```

The viewer requires Python 3.8+, not Herdr, a server, or the toolkit checkout.
Existing customized viewers are reconciled, not overwritten by plain init.
Refresh the stamp with the accepted extras selection afterward; extras flags
replace the selection, not append to it. Herdr/launcher already include dashboard.

## Bootstrapping a newly supported lead

A new command cannot install itself. Use read-only preview followed by plain
init after migration; then use the installed lead's update command/skill for
future reconciliation. No original flags are needed when a valid stamp exists.

## Maintenance cadence

Preview periodically. Merge safety/contract changes before the next task and
batch process/docs changes when convenient. Never change a live task contract.
Upstream must keep template/flow copies synchronized and run
`test/invariants.sh`; downstream merging cannot repair an incoherent release.

Copy-with-provenance preserves project customizations. A submodule is not a
substitute for deliberate reconciliation of locally edited generated files.
