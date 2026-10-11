# 03 — Separate pipeline state from native agent discovery

Impact: `[contract]`. Applies to scaffolds that keep toolkit task records in
`.agents/`. New scaffolds use `.agent-pipeline/`. Codex still discovers skills
in `.agents/skills/`; OpenCode definitions remain in `.opencode/`.

This is a lead-assisted migration, not an automatic move by `init.sh`.
`--update` reads the old provenance stamp and compares the old state template
without writing anything. Plain init and `--refresh-stamp` refuse a detected
legacy layout so they cannot create parallel state or erase the old baseline.
An older installed update command may not know this rule: read this note from
the current toolkit before running its missing-file bootstrap step.

## Move plan (show it to the user; execute after approval)

1. Check task records in **both** `.agents/` and `.agent-pipeline/`. Finish
   in-flight tasks first (unknown/unparseable status is not evidence of `done`).
   Stop workers, dashboard readers/watchers, and launchers. Do not relocate
   active artifacts or reuse an old worker session across this update.
2. Inventory tracked, untracked, and ignored files, including dotfiles. Record
   the existing Git status; back up pipeline data and every file to be edited
   in a private location outside the repo. Preserve modes, especially credential
   files, and do not print secrets. Git alone does not back up ignored logs.
3. Propose moves for toolkit-owned state: `T-*.md`, `TEMPLATE.md`, shared
   guidance (`TEAM.md`, handoffs, etc.), `prompts/`, `logs/`, provenance and
   customization markers, local server port/password, and session-ID files.
   Inspect other entries and ask which belong to the pipeline; do not silently
   move unrelated user files. **Keep `.agents/skills/` in place.** Never rename
   `.agents/` wholesale or change `.opencode/` / `.codex/` discovery paths.
4. Refuse any destination collision, including symlinks; do not overwrite,
   nest directories accidentally, or pick one provenance stamp arbitrarily.
   Stage verified copies and edited references before publishing. Use `git mv`
   for tracked entries and no-clobber filesystem moves for untracked/ignored
   entries; preserve bytes and permissions. Keep a move manifest for rollback.
   Remove an old directory only if it is empty; keep it if skills or unrelated
   files remain. Preserve the original stamp bytes until the final refresh.
5. Reconcile scripts, roles, project guidance, launchers, integrations, and
   task links to `.agent-pipeline/` in the same paused transaction. Relative
   links within moved records normally stay valid, but verify every artifact
   link and current-patch path. Preserve original transcripts/prompts/patches
   as historical evidence rather than rewriting their contents; record the
   relocation in task artifacts/decisions when needed. Do not globally replace
   `.agents`: references to native skills must stay unchanged.
6. Show permission-path changes separately and get explicit approval; verify
   enforcement live after restarting/reloading the actual runtime. Old cached
   agents must not continue with stale paths. Directory renames do not waive
   the usual permission or local-customization approval gates.
7. Reconcile `.gitignore`. Add `.agent-pipeline/logs/`,
   `.agent-pipeline/prompts/`, `.agent-pipeline/.oc-port`,
   `.agent-pipeline/.oc-password`, and `.agent-pipeline/.claude-session-id.*`.
   Keep legacy secret-ignore rules until the old paths are empty. Task records,
   shared guidance, and `.toolkit-version` remain trackable by default. A user
   may instead choose `/.agent-pipeline/` for entirely local pipeline state;
   explain that this also excludes shared guidance and the baseline. Do not
   ignore `.agents/skills/`. Gitignore does not untrack already committed files:
   propose explicit, scoped index changes when needed, never silently remove
   tracked files. Rotate a credential if it was previously committed.
8. Validate moved files against the manifest/backups, check links, run
   `scripts/verify-state.sh <id>` on the latest task, and check
   `scripts/dashboard --once`. Confirm Codex skills remain discoverable. If a
   check fails, stop and restore only this migration's changes using the move
   manifest/backups; preserve all pre-existing user edits. Do not reset Git.
9. Only after verification, run plain `bin/init.sh --target .` to add any
   genuinely missing files (also adds ignore rules), then reconcile remaining
   template drift and refresh the stamp. Re-run `--update`; report intentional
   local differences rather than claiming that refresh erased them. Resume
   dispatch/readers only on the consistent new layout.

Historical changelog entries and migrations 01/02 retain their original paths;
when applying them after this migration, use `.agent-pipeline/` for pipeline
state, not for native skills.
