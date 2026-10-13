# Cross-tool Claude review

Select `--reviewer-model claude/<id>` or `--reviewer-fallback-model claude/<id>`
to scaffold a pinned `.claude/agents/reviewer.md` or `reviewer_fallback.md`.
Claude, Codex, and OpenCode leads can use `.agent-pipeline/bin/claude-review.sh`:

```bash
.agent-pipeline/bin/claude-review.sh --model claude/sonnet \
  --prompt-file .agent-pipeline/prompts/T-001/reviewer-1.md \
  --raw-out .agent-pipeline/logs/T-001/reviewer-1.jsonl
```

Before dispatch, obtain task consent for the external Claude account/billing
and record `**Claude review approved:** on`. Audit existing project/user Claude
hooks/settings: tool restrictions do not disable hook commands. The model checker
reports Claude ids as unchecked; obtain and record explicit human confirmation
of the exact runtime/model assignment, not an invented catalog pass. Independent
model-maker review remains required: Claude-written work needs another family.

The wrapper enables only Read/Grep/Glob, denies shell/writes/agent/MCP tools,
and uses `dontAsk`, never bypass-permissions or standing broad execution rules.
Checks needing execution/network go to the tester. These are runtime guardrails,
not filesystem isolation; live enforcement remains to be tested. Claude CLI,
Python, and coreutils timeout/gtimeout are required. Default ceiling: 1200 seconds
(`CLAUDE_REVIEW_TIMEOUT` overrides it).

Each attempt uses an unused prompt/transcript pass. The wrapper returns full
final review text only with an exact leading VERDICT: PASS or
VERDICT: CHANGES_REQUESTED and a successful JSON result. CHANGES_REQUESTED is a
successful dispatch, not acceptance. Nonzero exit, malformed/error result, or
missing verdict blocks advancement. Transcript/session receipts remain available
for diagnosis; timeout does not prove remote inactivity. Inspect activity before
replacement; no automatic retries.

Record the receipt in `Claude reviewer session id`. Later passes may add
`--session <uuid>` only for this task and unchanged model, never the lead or
implementer session. Model changes start fresh. Paste returned findings and
dispositions unchanged under Review verdicts, set Latest handoff, and run
`verify-state.sh`. Use host background notifications when available; the
OpenCode-only `bg-dispatch.sh` does not support this wrapper.
