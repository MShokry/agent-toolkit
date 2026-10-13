# Migration 05 — Explicit team activation

v1.0.2 entrypoint/context change after v1.0.1. Installation no longer routes
ordinary feature/bug-fix requests into the team workflow. No task schema, role
authority, model assignment, permission, or native discovery path changes.

## Fresh installation

Generated root `AGENTS.md` is a neutral project-guidance file. It links to
`CLAUDE.md` when present and does not mention the team, skills, or leader contract.
Init does not inject routing into `CLAUDE.md` or another automatically loaded file.
Native feature commands and the opt-in feature skill remain installed as selected.

Use `/feature <request>` in Claude/OpenCode, explicitly invoke `$feature` in Codex,
or use the [copyable prompt](../README.md#start-the-team-explicitly-command-or-prompt).
Installing files, starting an agent, or adopting a Herdr pane does not activate
the workflow or approve any work. Explicit workers keep their role boundaries.

## Existing installation

1. At an inactive boundary, preview upstream changes with `init.sh --update`.
2. Review root AGENTS.md/CLAUDE.md and any other auto-loaded project guidance.
   Remove toolkit-owned automatic-routing paragraphs only after approval; retain
   ordinary project constraints, style/testing rules, and user customizations.
   Keep only the project-guidance link in a neutral AGENTS.md if desired. Store
   team-only notes in manually selected role/guide files, not startup guidance.
3. Merge the feature skill's explicitly opt-in description and leader/portable
   guide activation wording. Commands must still load the canonical role rules
   when explicitly invoked. Never turn a worker assignment into a leader request.
4. Validate in a disposable scaffold: startup guidance has no team references;
   explicitly invoked entrypoints still point to roles/leader.md; existing files
   survive re-scaffolding. Static tests do not prove the host's skill selection.
5. Accept provenance after the reviewed merge. Start a fresh conversation; loaded
   instructions cannot be removed from an existing agent's context by editing disk.

Plain init skips existing files. This migration is not authorization to overwrite
project guidance, move active artifacts, auto-dispatch workers, or change permissions.
