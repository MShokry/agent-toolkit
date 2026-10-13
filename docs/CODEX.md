# Native Codex workers

Claude, Codex, and OpenCode remain first-class leaders. Worker runtime is a
separate choice. OpenCode workers remain the defaults; a Codex lead can opt into
native workers without silently changing approvals or review independence.

## Available agents

| Agent | Selection | Sandbox / record |
| --- | --- | --- |
| `planner` | Codex-led planning | workspace-write; spec only |
| `codex-dev` | user explicitly chooses Codex at spec approval | workspace-write; approved files + patch + task |
| `reviewer` | `--reviewer-model codex/<id>` | read-only; lead records full findings |
| `reviewer_fallback` | `--reviewer-fallback-model codex/<id>` | read-only; lead records full findings |
| `tester` | `--tester-model codex/<id>` | workspace-write; test results, no source/test fixes |

Definitions live in `.codex/agents/`; skill discovery stays in `.agents/skills/`.
No project config or execution rules are installed. Additive session-capture
hooks are scaffolded for the team launcher; existing hooks are never overwritten
and must be hand-merged and trusted with `/hooks`.
Existing agent files are preserved on re-scaffold; update preview exposes drift.
When a reviewer/tester is native, its retained OpenCode role file is a shared
instruction source with no native alias in its OpenCode model metadata.
See [migration 04](../migrations/04-team-upgrade.md) for the unified upgrade of existing projects.

For a fresh project, pass whichever native assignments you need:

```bash
bash /path/to/agent-toolkit/bin/init.sh --target . --project-name example \
  --reviewer-model codex/<available-id> --tester-model codex/<available-id>
```

Model ids must be actual Codex catalog slugs, not family nicknames. Native
implementer model/reasoning inherit from the lead unless the project customizes
its agent. Record the actual settings before claiming independence; model-only
overrides can inherit an incompatible reasoning effort, so verify both.

## Capability and scope checks

- Confirm the Codex runtime discovers and can spawn the required custom agents
  with their configured model/sandbox. Valid TOML and files are not proof of that.
- Run `.agent-pipeline/bin/verify-models.sh` before planning. Explicit `codex/*` worker ids
  use a bounded `codex debug models` query; missing/unsupported/unreachable catalogs
  are unchecked, not passed. Catalog presence is not proof of account access or
  served-model identity. The CLI surface may differ across versions.
- Workspace-write does not limit a worker to its instructed task paths. The
  reviewer/lead checks scope and test/source changes. Verify real sandbox
  enforcement, including protected paths, in the actual runtime.
- Native workers never ask to widen permissions. A blocked command is recorded
  and escalated through the lead. OpenCode auto-mode consent does not authorize
  Codex escalation. Only the lead commits after user merge approval.

## Threads and evidence

Record each role's native thread id in its typed Role assignments row with backend,
model and family. Bind the first receipt before reuse. Reuse only for the same task/role and confirmed inactive
thread; model changes start a fresh reviewer. Start review with a file-based brief,
not inherited implementer conversation. If resume is unavailable, record the lost
thread and replace it from written state only after confirming inactivity.

Each dispatch gets an unused prompt pass and an Artifacts link. Export a transcript
only when the runtime supports it; otherwise record unavailable and the thread id.
The read-only reviewer's full reply is the record exception: paste its verdict,
findings, and dispositions unchanged into the task, set Latest handoff, and run
`verify-state.sh`. Tester replies remain short receipts of the on-disk results.

Two OpenAI-family models are not independent review, even in different harnesses.
Use the approved different-family reviewer or stop if identity is unknown. Other
leaders cannot pretend to spawn native Codex agents: obtain an approved dispatch
mechanism or a human-approved assignment change, never silently substitute.

References: [Codex custom agents](https://developers.openai.com/codex/agent-configuration/subagents)
and [configuration](https://developers.openai.com/codex/config-file/config-reference).
