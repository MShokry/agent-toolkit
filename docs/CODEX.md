# Codex lead operation

Codex and Claude use the same canonical feature and update workflow files.
Codex's adapters supply its dispatch, permissions, and recovery behavior;
OpenCode remains the implementer/reviewer/tester runtime. Both leads use
`.pipeline/` for writable task records, outputs, local server state, and logs.
Skills stay in `.agents/skills/` and agent/hook definitions in `.codex/`.

The CLI integration was checked against Codex 0.160.0. The OS sandbox and
project/skill/agent discovery must also be checked in the runtime actually
used. File presence and valid TOML are not proof of agent discovery.

## Setup

Scaffold normally, optionally choosing independent settings:

```bash
bash /path/to/agent-toolkit/bin/init.sh --target . --project-name example \
  --codex-model <available-model> --codex-reasoning high \
  --codex-planner-model <available-model> --codex-planner-reasoning medium
```

All four Codex options default to `inherit`. Omitted planner settings inherit
from the lead; the launcher preserves the user's configured lead settings.
Explicit choices are recorded in the provenance stamp. Use an available model
and a reasoning effort it supports; the scaffolder does not query accounts.

Ensure project guidance is populated. Existing `AGENTS.md` is preserved:
review/merge the generated routing instructions if that file already existed.
Existing hooks are preserved too: merge the two capture handlers, rather than
replacing unrelated hooks. Review and trust them with `/hooks` in a trusted
project. Hook changes require trust review again. The toolkit never bypasses
hook trust.

```bash
scripts/team.sh --lead codex example
```

Alternatively run `bash scripts/codex-lead.sh example` from any directory.
The wrapper starts Codex without the shared daemon so the hook inherits this
launcher's team key. SessionStart captures the exact lead ID; UserPromptSubmit
also captures it after initial hook trust. Ordinary Codex chats have no team
key and do not replace pins. Each team name has its own pin and process lock.
The launcher supplies the repository root to the hook command explicitly, so
capture also works in a nested checkout or a project without a Git root.

## Roles a Codex lead can spawn

| Role | Codex agent | When |
| --- | --- | --- |
| planner | `.codex/agents/planner.toml` | always; follows `.claude/agents/planner.md` |
| implementer | `.codex/agents/codex-dev.toml` | when the user asks for Codex to implement (default stays OpenCode `builder`); follows `.claude/agents/senior-dev.md` |
| reviewer | `.codex/agents/reviewer.toml` | only for `--reviewer-model codex/<model>`; `sandbox_mode = "read-only"`, follows `.opencode/agents/reviewer.md` |
| tester | `.codex/agents/tester.toml` | only for `--tester-model codex/<model>` |

Each records its own thread id in the task file, and only that role's retry
reuses it. `codex-dev` and the planner inherit the lead's model unless the
project pins one in the TOML. After `codex-dev` implements, an OpenAI-family
reviewer is not independent; the canonical flow switches to the fallback.

The Codex reviewer is the only role here whose boundary the runtime enforces:
a read-only sandbox, not a permission block that reads correctly. It cannot
write the state file, so its reply carries the full findings and the lead
pastes them. `codex-dev` and the planner run `workspace-write`, which keeps
`.git`, `.codex/` and `.agents/` read-only but does not restrict them to their
own source paths.

## Permissions and preflight

Before `$feature`, the lead runs `scripts/codex-preflight.sh` in its **current
sandbox**. It checks runtime-file writes, required files/tools, and authenticated
OpenCode API connectivity using the same server/password precedence as `oc.sh`.
It checks enabled hook/multi-agent capabilities and the launcher CLI option,
and prints the installed Codex version; verify custom planner and skill discovery
in Codex before dispatch. Running it from an unrestricted terminal alone does
not establish the lead's sandbox access.

`.codex/rules/pipeline.rules` is a project execution-rules file that lets
exactly `scripts/oc.sh`, `scripts/bg-dispatch.sh`, `scripts/claude-review.sh`
and `scripts/verify-models.sh` run outside the sandbox without a prompt per
call. Before it, a long run asked for approval at every dispatch, status check
and wait, and users ended up adding the same allow rules to their personal
`~/.codex/rules/default.rules`. Codex loads project rules only in a trusted
project. Invoke the wrappers by their repo-relative path; `bash scripts/oc.sh`
or an absolute path does not match. Git writes, `codex-preflight.sh` (which
must test the sandbox it runs in) and everything else still prompt. Review the
file like a hook, and confirm live that a wrapper runs without a prompt while
`git push` still prompts; `bash test/codex-sandbox.sh` checks the decisions
offline with `codex execpolicy check`.

With the rules present, preflight exits 3 when every check passed except the
OpenCode API probe from inside the sandbox. The lead then runs
`scripts/oc.sh --status`, which the rules run outside the sandbox. Exit 0 there
proves the server and credential.

If policy blocks a command, request runtime approval for that exact operation.
Local OpenCode access may need network approval; the user-approved commit may
need approval to write `.git`; toolkit updates may need approval to write
protected `.codex/` or `.agents/skills/` files. Never disable the sandbox or
approval controls to get parity. OpenCode `--auto` applies only to OpenCode.
Spec approval and merge consent are separate workflow gates.

The planner still has workspace-write access to ordinary source paths. Its
source-read-only rule is a disclosed role instruction, not path isolation. It
tests a temporary write under `.pipeline/` before planning and reports a blocked
operation to the lead. Changing the runtime directory does not make that
source-write boundary enforced.

## Lead parity with Claude

The Codex lead runs the same canonical flow as the Claude lead; what differs is
mechanics the Claude harness supplies and Codex does not:

- **No Monitor.** Long dispatches go through `scripts/bg-dispatch.sh start`,
  and the lead calls `scripts/bg-dispatch.sh wait … <seconds>` until it
  reports `finished:` or `wrapper-exited:`. Codex's unified exec yields after
  `yield_time_ms` and keeps the command running, so the lead polls that exec
  session instead of starting a second `wait`.
- **No scheduler for usage-limit retries.** After telling the user about a
  limit once, the lead relaunches the same dispatch with
  `bg-dispatch.sh start … --retry-on-limit 1800 -- …`. That detached loop
  reruns it every 30 minutes only while the failure is a usage limit (never a
  timeout), gives up after `BG_RETRY_MAX` attempts, and `wait` shows its latest
  retry note. A limit hit by a Codex subagent has no such loop and is reported
  with a resumable handoff.
- **No Claude subagents.** A `claude/*` reviewer runs headlessly through
  `scripts/claude-review.sh`, which needs the `claude` CLI, the project's
  `.claude/agents/reviewer.md`, and runtime approval to reach Anthropic.
- **No structured question tool.** A stop-and-ask is one plain message with
  numbered options, the recommended one first. (`request_user_input` is
  still an under-development Codex feature, off by default, as of 0.160.)
- **Stopping a role** is `scripts/oc.sh --interrupt <id>`, never a raw API call.

The reverse gap exists too: a Claude lead cannot spawn a Codex `tester`
subagent. The canonical flow says to ask the user rather than substitute — for
example, park the task at `testing` for a Codex-led session.

## Recovery

Resuming uses `.pipeline/.codex-session-id.<team-name>`, never `--last`. A failed
resume keeps the pin and stops. Missing capture after a prior launch also stops:
trust the hooks and submit a prompt, or recover the exact conversation ID from
`/status` and save it to the pin. Use `--fresh` only to deliberately reset that
team's lead conversation. After a crash, check that the process is stopped before
removing its stale `.pipeline/.codex-lead-lock.<team-name>` directory.

At session start (startup, resume, or after compaction), the capture hook also
prints one line per unfinished task: id, Status, Latest handoff, and Blocked
since. It is a pointer for the resumed lead, not a substitute for reading the
state files or checking worker activity. Per-prompt capture prints nothing.

The lead records its planner thread ID in the task file. Corrections and the
single spec bounce reuse that thread. After interruption, check worker status
and the task record before dispatching; never start a competing writer. If the
planner thread has disappeared, record why a replacement was necessary and
reconstruct it from the task file. After compaction/restart, recover status,
counters, approval decisions, and worker activity from disk.

If a quota failure occurs, preserve the task and thread IDs. Use a scheduled
wakeup only when the runtime actually offers one; otherwise leave a resumable
handoff and report that automatic retry is unavailable.

## Verification

`bash test/codex.sh` exercises real generated launcher/hook/preflight code using
CLI doubles: exact resume, isolated teams, explicit reset, failed resume, missing
capture, concurrent writers, unsafe event data, blocked writes/network access,
model-setting round trips, and legacy migration triage. CI runs it without any
model calls. Python 3.11+ is required for the test's TOML parser; runtime hooks
use only the Python standard library and do not require TOML parsing.

`bash test/codex-sandbox.sh` is an opt-in real local Codex sandbox check, also
without model calls. It verifies writable runtime state and refusal to write
instruction/configuration/Git paths. Run outside another sandbox when the OS
disallows nested sandbox creation.

Live workflow checks are manual, using a disposable repository and a real
OpenCode server. Verify each scenario before claiming model-level parity:

1. Invoke `$feature` on a small change. Confirm the custom planner is discovered,
   writes a spec passing `verify-spec.sh`, and stops for spec approval.
2. Request a spec correction; confirm reuse of the recorded planner thread.
3. Approve implementation. Exercise a review rejection and a failed test, then
   confirm counters, evidence, status-board updates, and independent review.
4. Interrupt planning/implementation, restart the same team after an unrelated
   Codex conversation, and confirm exact lead/thread recovery with no duplicate
   writer and no repeated recorded approval.
5. Confirm the lead reports results and stops before an unapproved merge. After
   approval, confirm it stages the task record with the code and tags the commit.
6. Change a sandbox or hook setting in a scratch update; confirm it is surfaced
   for explicit permission-change consent and renewed hook trust.
7. In a trusted project, confirm `scripts/oc.sh --status` and a
   `bg-dispatch.sh wait` run without a prompt while `git push` still prompts.
   Then ask for Codex to implement a small task: confirm `codex-dev` is
   discovered, records its thread id, cannot commit, and that the review step
   picks an independent (non-OpenAI) reviewer.

Do not label the no-model tests as a completed live multi-agent run.

Sources: [protected paths and approvals](https://learn.chatgpt.com/docs/agent-approvals-security),
[exact-session resume](https://learn.chatgpt.com/docs/developer-commands#codex-resume),
[lifecycle hooks and trust](https://learn.chatgpt.com/docs/hooks), and
[custom agents](https://learn.chatgpt.com/docs/agent-configuration/subagents).
