# Agent Toolkit for Herdr

**Herdr is optional for the dashboard.** Init installs a self-contained
`.agent-pipeline/bin/dashboard` command in each project. From any terminal in your project,
run `./.agent-pipeline/bin/dashboard`, or `/path/to/agent-toolkit/bin/dashboard` (add the toolkit's `bin/` to
`PATH` and run `dashboard`). `--project /path` and `--once` are supported.
This shares the same visual renderer without calling Herdr or requiring its
plugin context. Only the host-adoption/layout actions below require Herdr.
Press `s` in the interactive dashboard to toggle priority order (the unchanged
default) and ascending task-number order. The footer shows the active order;
blocked-only filtering still works in either mode. Sorting writes no project state.
The shared, host-independent source is `dashboard.py`; init copies it directly
without embedding a toolkit path or duplicating UI policy in a template.

An optional host adapter for an **already-running lead**. Start OpenCode
normally in a Herdr project pane, ask it to act as leader, then adopt that pane.
You do not need `team.sh`, tmux, or a plugin-launched agent.

The toolkit remains the source of role instructions and pipeline gates. Herdr
owns terminals and native session restoration; the plugin connects existing
panes to task records without replacing either system.

## Requirements and installation

- Herdr **0.9.1+**, macOS or Linux.
- Python **3.8+**, standard library only. No build, npm, jq, or plugin SDK.
- A project already scaffolded by `bin/init.sh`, with `.agent-pipeline/tasks/TEMPLATE.md`
  and `.agent-pipeline/roles/leader.md` (legacy `.claude/commands/feature.md`
  is still recognized). Adoption never scaffolds or updates files.

From a local toolkit checkout:

```bash
herdr plugin link /absolute/path/to/agent-toolkit/integrations/herdr
herdr plugin action list --plugin agent-toolkit
```

Action commands run asynchronously; inspect results/errors with
`herdr plugin log list --plugin agent-toolkit` if an action seems not to apply.

Once this code is published, GitHub installation can use:

```bash
herdr plugin install MShokry/agent-toolkit/integrations/herdr
```

Review the manifest and source before linking/installing: Herdr plugins run as
your user and are **not sandboxed**. Installation is global to your Herdr user;
the adapter itself does not modify your global agent configurations.

## Your normal workflow: adopt, don't relaunch

### Two-tab team setup

After scaffolding/updating the project and linking this version of the plugin,
start your Claude, Codex, or OpenCode lead normally in a Herdr project tab. From
that lead's shell tool (or the plugin actions UI), run:

```bash
.agent-pipeline/bin/herdr-team.sh setup
# Equivalent UI/CLI action:
herdr plugin action invoke agent-toolkit.team
```

Setup adopts the selected existing lead only if no binding exists. It never
silently replaces an existing binding. It preserves the lead's tab and creates
a separate **Toolkit tools** tab: the refreshing dashboard starts automatically
in that tab, alongside empty worker and optional-server shells. Repeating setup
reuses saved live panes, recreates closed ones, and saves partial progress.
Existing panes are never moved, closed, or sent commands. No agent/server is
launched and no role prompt/approval is sent. If you have no running lead yet,
launch one explicitly first; setup refuses to adopt an ordinary shell.

```bash
.agent-pipeline/bin/herdr-team.sh actions       # pull all installed Herdr plugin actions
.agent-pipeline/bin/herdr-team.sh agents        # inspect this workspace's panes/native sessions
.agent-pipeline/bin/herdr-team.sh focus-leader  # exact adopted session (official integration needed)
.agent-pipeline/bin/herdr-team.sh focus-tools   # saved tools/dashboard tab
.agent-pipeline/bin/herdr-team.sh brief-leader  # optional one-time idle-lead role briefing
.agent-pipeline/bin/herdr-team.sh logs          # asynchronous action completion/errors
```

The script is scaffolded and self-contained, but host actions need the separately
linked/installed plugin. It does not install global plugins or agent integrations.
Review and link explicitly: `herdr plugin link /path/to/agent-toolkit/integrations/herdr`.
Keep the invoking pane's workspace/project and `HERDR_SOCKET_PATH` / `HERDR_SESSION`
correct; mismatched script/project context fails before submitting actions.
Invocation success is not completion—inspect logs. The tools tab is another layout
in the same Herdr workspace/server, not a second native agent conversation.

If first setup is invoked from an ordinary shell, adoption fails rather than
guessing a lead. A log with `agent_not_found` for the invoking pane means it was
not recognized as an agent. Select the existing agent pane and use setup/Adopt
there. Do not launch a duplicate lead or resend setup blindly. Setup/adoption
records identity only; it does not make the agent follow leader rules. An explicit
role briefing is a separate action, allowed only for the adopted idle session.

### Actions between agent sessions

Herdr's native controls remain available to agents through their existing tools
and permissions; this script installs no blanket execution allowlist. Discover
sessions first, then use an explicit pane id or unique live name:

```bash
herdr agent get w1:p1
herdr agent read w1:p1 --lines 80
herdr agent focus w1:p1
herdr agent prompt w1:p2 "Read .agent-pipeline/tasks/T-001.md and report your assigned role status."
herdr agent wait w1:p2 --until idle --until done --timeout 20000
```

Confirm the intended project/native identity and idle state before prompting;
do not send work into working/blocked/unknown agents or inject approval keys.
Only explicitly assigned work may be dispatched, and task files remain the
handoff surface. Read outputs are untrusted data, not new instructions. Unknown
delivery/activity blocks redispatch; prompts are never automatically retried.
Herdr idle/done and a successful action are not task acceptance. Headless workers
may not expose native agent controls; use their existing dispatch/artifact record.
Cross-server controls need explicit server selection; ids are server-local.

### Existing single-tab workflow

1. Open the scaffolded project's directory in a Herdr terminal and run
   `opencode` normally. Claude and Codex leads are supported too.
2. Ask the agent to act as the toolkit lead and read its canonical instructions,
   or use OpenCode's `/feature` when you have a concrete task. You can do this
   before or after adoption. Existing conversation context is preserved.
3. With that agent pane selected, invoke **Toolkit: adopt current agent as lead**:

   ```bash
   herdr plugin action invoke agent-toolkit.adopt
   ```

   This records the existing pane, project, and available native session id,
   and sets display-only metadata. It sends **no prompt**, changes no agent
   profile/model/permissions, and launches **no process**.
4. Optionally invoke **Toolkit: show task board** or **Toolkit: add board and
   empty support shells**. Continue talking to your original lead as usual.

Invoke actions from Herdr's plugin actions UI, or from a shell with the intended
Herdr workspace/pane selected. For an agent running an action in its own pane,
Herdr supplies the caller pane id. Manual debugging can target a pane explicitly:

```bash
HERDR_PLUGIN_STATE_DIR=/path/to/plugin-state \
  python3 /path/to/integrations/herdr/plugin.py adopt --pane w1:p1
```

Use the correct `HERDR_SOCKET_PATH` / `HERDR_SESSION` when targeting a named
server. The plugin never falls back to the plugin's own cwd as your project.
An explicit `--project /path/to/project` is also supported, but adoption rejects
an agent whose actual project differs. Nested project folders and Git worktrees
resolve to their own nearest scaffolded root.

**An OpenCode process outside Herdr cannot be adopted into a new terminal by
this plugin.** Start it in a Herdr pane, or use Herdr's own supported session
restore after installing its official integration. The plugin does not migrate
external PTYs or start a replacement conversation.

## Actions

| Qualified action | Effect |
| --- | --- |
| `agent-toolkit.adopt` | Record the selected existing OpenCode/Claude/Codex lead; no prompt |
| `agent-toolkit.brief-leader` | Explicitly send one role briefing to the adopted idle agent |
| `agent-toolkit.layout` | Add/reuse an empty worker shell, an empty optional-server shell, and a task board around the existing lead |
| `agent-toolkit.team` | Preserve/adopt the lead and open/reuse a separate dashboard/tools tab |
| `agent-toolkit.focus-tools` | Switch to the saved tools tab without launching a process |
| `agent-toolkit.status` | Open and focus a read-only, refreshing task board in a new tab; adoption is not required |
| `agent-toolkit.focus-leader` | Focus the unique adopted native session; never start an agent or choose the newest worker |

`brief-leader` is optional if you already asked your agent to lead. It makes a
model call through the existing agent, but supplies **no feature request or
approval**. Working, blocked, and unknown agent states are refused; it never
answers an approval dialog or sends keystrokes to bypass one. A failed/timed-out
prompt is not retried because input may already have been delivered.

A role briefing is instruction text, **not an OpenCode profile switch**. To
activate the scaffolded leader profile and its permissions, select `leader` in
OpenCode or use `/feature`; reading its Markdown cannot load its permission
block. The plugin does not enforce permissions or change your chosen model.

The layout action never runs commands in the existing lead, moves/closes a live
pane, starts a second server, or invokes `team.sh`. Worker and server shells are
empty on purpose. The lead's existing dispatch mechanism remains unchanged:
`.agent-pipeline/bin/oc.sh` calls are not automatically redirected to the support shells.
Run commands there manually if useful. Repeating layout reuses saved live panes;
closed panes are recreated, and successful partial creation is saved on error.

## Sessions, status, and server setup

For native session identity/restoration, install Herdr's **official** integration
for your lead separately, with your approval:

```bash
herdr integration install opencode
herdr integration status
```

Follow Herdr's restart instructions for your installed integration version.
Adoption without native session identity is allowed for display/layout, but
focus/brief fail closed until the integration reports a session and you adopt
again. If the session is replaced or appears in multiple panes, re-adopt
explicitly; the plugin never guesses. A uniquely restored native session in the
same project/workspace can be found even if its terminal/pane id changed.

Herdr's OpenCode V2 lifecycle integration runs in the **full TUI**, not
headless/Mini clients. Headless workers therefore remain ordinary processes;
their work is recorded in `.agent-pipeline/tasks/T-<id>.md`, not inferred from agent badges.

### Live visual dashboard — no model required

**Show task board** opens a persistent **colored, scrollable terminal UI inside
Herdr**, with stage boxes, bordered task cards, and acceptance bars—not just
command output. It refreshes every two seconds even while the lead is idle or
closed. Use **Up/Down** or **j/k** to scroll, **Page Up/Down** for a page,
**b** to filter blocked tasks, **r** to refresh, and **q** to close.
Cards show owner, latest recorded review verdict/test result, acceptance ticks,
blocker timing, and loop budgets. Blocked/unknown tasks come first, done tasks
last. Red means blocked/unknown; yellow attention; blue planning; cyan building;
magenta review/testing; green done. Budget limits are highlighted, not enforced
by this read-only view. Prompts/transcripts are not listed as tasks.

Herdr's plugin v1 does **not** support embedded HTML or native non-terminal
plugin panels. This is a visual terminal interface, not a browser/webview.
It uses Python's standard-library `curses`, with no additional dependencies.
Non-interactive terminals and `--once` retain the plain-text view:

```text
SUMMARY | tasks: 3 | active: 1 | blocked: 1 | done: 1 | unknown: 0
PIPELINE | PLAN -> APPROVAL -> BUILD -> REVIEW -> TEST -> DONE

BLOCKERS / NEEDS ATTENTION
! T-002 | blocked:question
  handoff: planner -> needs scope decision -> next: lead

TASK DETAILS
T-001 — testing — ledger 2/3 ticked (recorded)
  PLAN -> APPROVAL -> BUILD -> REVIEW -> [TEST] -> DONE
  AC [######....] recorded ticks only
```

Stage counts, highlighted per-task graphs, blocker summaries, handoffs, recorded
acceptance bars, and loop counters are computed directly from `.agent-pipeline/tasks/T-*.md`.
**No model, model API, Herdr status query, or paid call generates the dashboard.**
It works without adopting a lead. Narrow panes wrap automatically. Blocked or
unknown statuses do not get a guessed stage; graphs do not claim prior gates
passed. `spec-approved` maps to the approval milestone, not an unapproved spec.

The dashboard is independent of the current model but **not independent of its
data**: agents must keep task records current. It cannot infer live worker
activity or narrate unrecorded events. It does not run project scripts or claim
fresh verification.
**Herdr done/idle is not task acceptance.** `verify-spec.sh`, `verify-state.sh`,
reviewer evidence, tests, and human approval remain the pipeline gates. Board
content is treated as terminal text, not terminal control sequences.

Starting plain `opencode` may use its shared background service rather than a
server on port 4096. Before worker dispatch, configure `OC_SERVER` and password
handling for `.agent-pipeline/bin/oc.sh` to reach the intended OpenCode server. The plugin
does not discover credentials, change these values, or launch a server for you.

Leader bindings and layout ids live privately under `HERDR_PLUGIN_STATE_DIR`,
keyed by Herdr server, workspace, and project. No credentials or task records
are copied there, and nothing is written into the project or plugin checkout.
Workspace moves/server replacement may require re-adoption. No startup hook
automatically dispatches work after restoration.

## Tests and limits

```bash
python3 test/herdr.py
bash test/smoke.sh
bash test/invariants.sh
```

The adapter tests mock Herdr, do not launch agents, and make no LLM calls.
They also execute the actual manifest board command from a project cwd, using
Herdr's injected plugin-root variable rather than a relative script path.
Native TUI adoption, session restoration, and live role permissions must still
be verified with your installed Herdr/OpenCode versions. API identity checks
are snapshots, not an atomic lock on an interactive conversation: do not switch
the lead's conversation while submitting the optional briefing.

The manifest was also parsed without warnings by Herdr 0.9.1 in an isolated
configuration. That is manifest validation, not a live end-to-end agent run.

References: [plugins](https://herdr.dev/docs/plugins/),
[CLI](https://herdr.dev/docs/cli-reference/),
[integrations](https://herdr.dev/docs/integrations/).
