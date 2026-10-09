# 02 — Task-scoped artifact layout

Applies to `.agents/TEMPLATE.md`, active task records, lead/implementer/reviewer
instructions, `scripts/oc.sh`, and any custom callers. Introduced in v0.10.1.

Task state files remain `.agents/T-<id>.md`. Shared guidance, hidden toolkit
metadata, and installed skills keep their existing locations. Only generated
artifacts change layout:

- Prompts: `.agents/prompts/T-<id>/<role>-<pass>.md`
- Transcripts: `.agents/logs/T-<id>/<role>-<pass>.jsonl`
- Patches: `.agents/logs/T-<id>/<implementer>-<pass>.patch`
- Append-only telemetry: `.agents/logs/T-<id>/pipeline.jsonl`

## Upgrade callers and state together

1. Wait for all affected runs to finish, including any still running on the
   server after a disconnected CLI. Pause dispatch and dashboard refresh/readers
   for the migration. Never move an artifact while its associated run is active.
2. Reconcile the lead, implementer, reviewer, template, and wrapper updates
   together; plain init will not overwrite customized files. Old inline/stdin
   prompts and root-level transcript paths are now rejected by `oc.sh`.
3. Add `## Artifacts` to each task being continued, with columns for role/attempt,
   prompt, transcript, and patch/current-for-review. Use Markdown links relative
   to `.agents/T-<id>.md`, e.g. `[prompt](prompts/T-023/builder-1.md)` and
   `[current patch](logs/T-023/builder-1.patch)`. Keep findings/verdicts in state.
4. Create both task directories before dispatch. Choose a positive number unused
   by that role's prompt, transcript, or patch; every retry gets a fresh number.
   These attempt numbers do not change review/test-fix budgets. Write prompts and
   patches with no-clobber protection, pass the assigned patch path to the
   implementer, and give `oc.sh` matching `--prompt-file` / `--raw-out` paths.

## Legacy artifacts (optional, never automatic)

Completed tasks may retain their existing links and files. For tasks you choose
to reorganize, explicitly map each old artifact to its task/role/attempt; do not
guess ownership or chronology from filenames alone. Do not merge unrelated
task telemetry or fabricate transcripts that were never saved.

While dispatch/readers remain paused, stage copies at unused destinations and
verify their bytes match the originals. Stage all updated state links in a
temporary file beside the state file, and publish it with a same-filesystem
atomic rename only after all copies succeed. Retain originals until publication
is confirmed, then remove only the explicitly mapped originals. If staging or
publication fails, retain the original state/artifacts and roll back only the
new files created by this migration. This maintenance window plus atomic state
publication prevents readers from observing half-updated links; multiple file
moves are not themselves a filesystem-wide atomic operation.

Confirm every link resolves and the dashboard lists only task records before
resuming dispatch. `review-1` examples should use the actual role name
`reviewer-1` for `--agent reviewer`.
