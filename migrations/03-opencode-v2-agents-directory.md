# Migration 03 — OpenCode V2 agents directory

Apply at a task boundary. OpenCode V2's canonical project role directory is
`.opencode/agents/`; older toolkit scaffolds wrote `.opencode/agent/`. Do not
bootstrap the new directory beside the old one: duplicate role ids make it
unclear which permission block the runtime loaded.

1. Confirm no task state file is in flight.
2. Stop the OpenCode server.
3. Move the customized role files without rewriting their frontmatter:

   ```bash
   mv .opencode/agent .opencode/agents
   ```

4. Update current instructions and scripts that reference
   `.opencode/agent/` to `.opencode/agents/`. Historical task records may keep
   their original paths.
5. Restart OpenCode from the project root.
6. Query the authenticated live agent endpoint and confirm `builder`,
   `reviewer`, and `tester` are present. Inspect the ordered permission rules;
   the last matching edit rule must preserve each role's intended write scope.
7. Run `scripts/verify-models.sh`, then the project preflight.

The migration deliberately does not convert legacy `permission:` frontmatter
to another schema. Directory discovery and permission-schema conversion are
separate changes; combining them makes a missing role indistinguishable from a
silently dropped ruleset.
