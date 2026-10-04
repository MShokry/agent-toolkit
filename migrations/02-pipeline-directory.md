# Writable pipeline records and Codex lead recovery

Apply at a task boundary. This changes the handoff location for **both** leads,
from `.agents/` to `.pipeline/`; `.agents/skills/` remains the skill-discovery
directory. Codex protects `.agents/`, `.codex/`, and `.git` under its standard
workspace sandbox. The previous planner configuration did not make task
records under `.agents/` writable.

1. Finish or explicitly park all tasks. Stop workers and the tmux team before
   moving runtime files; do not change a live writer's paths.
2. Read the old `.agents/.toolkit-version` as the update baseline. Run the
   toolkit's `bin/init.sh --update --target <project>` to review changes. It
   reads legacy stamps without modifying them; a plain bootstrap refuses an
   unmigrated `.agents/TEMPLATE.md`.
3. Create `.pipeline/` and move only runtime files, without overwriting any
   existing destination. Review collisions instead of merging automatically:
   `TEMPLATE.md`, `T-*.md`, task diffs/JSONL outputs, `.toolkit-version`,
   `.needs-customization`, `.oc-port`, `.oc-password`, `.claude-session-id.*`,
   and `logs/`. Preserve permissions on the password. **Leave `.agents/skills/`
   in place.** No automatic migration runner is supplied.
4. Reconcile every active reference to the old runtime path in role files,
   commands, project instructions, task links, tracking docs, scripts, and
   locally customized permission scopes. Take the new structural scripts
   together with the new task template. Keep historical changelog entries as
   historical records. Never widen permissions silently.
5. Run `bin/init.sh --target <project>` to add missing files. Existing files,
   including `AGENTS.md` and `.codex/hooks.json`, are preserved. Hand-merge the
   Codex routing block into existing instructions and the SessionStart plus
   UserPromptSubmit capture handlers into existing hooks. Runtime approval may
   be needed for protected configuration writes; user acceptance of the update
   is a separate decision. The three supporting skills are now installed under
   `.agents/skills/`; Claude can read these files directly too.
6. Add `.pipeline/.oc-port`, `.pipeline/.oc-password`,
   `.pipeline/.claude-session-id.*`, `.pipeline/.codex-session-id.*`,
   `.pipeline/.codex-started.*`, `.pipeline/.codex-lead-lock.*`, and
   `.pipeline/logs/` to the project's ignore rules. A plain bootstrap adds
   these rules in Git repos. Old ignore entries may remain harmlessly.
7. In Codex review/trust the new or changed hooks with `/hooks`. The launcher
   captures the actual session ID, never the newest repository conversation.
   Recover an existing Codex lead's ID from `/status` and save it to
   `.pipeline/.codex-session-id.<team-name>` before resuming, or deliberately
   use `scripts/team.sh --lead codex --fresh <team-name>`. Missing pins and
   failed resumes stop; they do not silently create another conversation.
8. Run `scripts/codex-preflight.sh` from the lead's actual sandbox, verify
   discovery of `planner` and the supporting skills, and run the structural
   scripts against a completed migrated task. Optional Codex model/reasoning
   flags default to `inherit`. Add the optional **Codex planner thread id**
   field to existing tasks only when a Codex planner is dispatched; older
   task files remain valid without it.
9. Refresh the provenance stamp after accepting the changes. An update may
   still report deliberate local customizations: review and record them rather
   than forcing template equality. Verify the changed permission scopes live.

See [Codex lead operation](../docs/CODEX.md) for the runtime checks and recovery
scenarios. The toolkit's tests never run paid model calls automatically.
