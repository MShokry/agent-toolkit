# Migration 04 — One OpenCode session per role

Apply at a task boundary. Earlier scaffolds shared one OpenCode session across
implement, review and test for a task, recorded in a single *OpenCode session
id* field. On opencode v2 a session pins the tool set of the agent that opened
it, so a tester dispatched into the builder's session could not write its
results, and a shared session fed the reviewer the builder's reasoning instead
of just the diff. Each role now gets its own session and its own field.

1. Confirm no task is between implement and test. A task already in review or
   testing can finish on the old policy; record that in its Decisions log.
2. In `.pipeline/TEMPLATE.md`, replace the `**OpenCode session id:**` line with
   the three per-role lines from `templates/agents-state/TEMPLATE.md.tmpl`
   (*OpenCode builder session id*, *OpenCode reviewer session id*, *OpenCode
   tester session id*), and add *Codex tester thread id* if the project uses a
   `codex/*` tester. Leave historical `T-*.md` files as they are.
3. Merge the new session-policy section, the review and test commands (no
   `--session` on a role's first call), and the per-task branch paragraph from
   `templates/claude/commands/feature.md.tmpl` into
   `.claude/commands/feature.md`. Keep any project-specific branch prefix.
4. Decide the project's standing answer to builder `--auto`: add
   `builder_auto:  ask` (ask per task, the old behavior) or `builder_auto:  on`
   (a standing user decision) to `.pipeline/.toolkit-version`. Only the user
   can choose `on`; record when and who in the status board or a decision note.
5. Merge the session lines in `scripts/oc.sh`'s header and the OpenCode
   `leader` agent's worker-session bullet.
6. Run `bash scripts/verify-state.sh` on any open task and the project
   preflight.

The first builder, reviewer and tester call on the next task each omit
`--session`; only a retry by the same role reuses its own recorded id.
