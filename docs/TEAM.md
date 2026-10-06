# `scripts/team.sh`

A tmux layout for running the pipeline: pane 0 is the lead (`claude` when
installed, otherwise `codex`, then `opencode`), pane
1 is `opencode serve` (what `scripts/oc.sh` attaches to), pane 2 tails
`.pipeline/` for activity, pane 3 is free.

## Usage

```
scripts/team.sh [session-name]     start, or attach if it's already running
scripts/team.sh --fresh            start a NEW lead conversation, not a resume
scripts/team.sh --lead <name>      auto (default), claude, codex, or opencode
scripts/team.sh --port <N>         opencode server port (default 4096)
scripts/team.sh --kill [session-name]
```

Flags can combine with a session name in any order:
`scripts/team.sh --port 4097 my-second-project`.

## Lead selection

`--lead auto` prefers Claude when `claude` is installed and falls back to Codex
when it is not, then OpenCode if neither is installed. Use `--lead claude`,
`--lead codex`, or `--lead opencode` to override that choice;
`TEAM_LEAD` provides the same default as an environment variable. When creating
a session, the script fails before creating panes if the selected CLI is
unavailable; attaching an already-running session does not require the CLI to
remain discoverable.

In a Codex pane, invoke `$feature <request>`. The generated repository skill
drives the same pipeline as Claude's `/feature` command.

In an OpenCode pane, choose the lead model and run `/feature <request>` or
`/toolkit-update`. The command selects the OpenCode `leader` adapter in that
session. Its native `planner` child and CLI-dispatched workers use the same
canonical prompt files as the other leads; no Claude or Codex executable is
needed. Both the lead and workers authenticate against pane 1's server using
the password file, without putting its contents in the pane command.

## Resuming is the default

Pane 0 resumes the lead's own conversation — not a fresh one — but it does
so by pinning to a stored UUID (`.pipeline/.claude-session-id.<session-name>`,
written the first time that session name runs) rather than
`claude --continue`. `--continue` only means "the most recent conversation
in this directory," with no notion of *which* tmux session started it, so
running a second `scripts/team.sh` session name against the same repo (or
just running a one-off `claude` there for something unrelated) could make
the next `--continue` resume the wrong thread entirely. The pinned id
removes that ambiguity: each session name always resumes its own
conversation via `claude --resume <uuid>`, however many other Claude
conversations have happened in the same directory since.

This exists because killing the tmux session (the usual way to free up a
port, or just closing the terminal) used to also throw away the lead's
context, with no way back into the same conversation. Now: kill it, come
back later, run `scripts/team.sh` again, the lead is where you left it.

Pass `--fresh` on the rare run where you actually want a clean slate
instead — this mints a new pinned id, so later resumes follow the new
conversation, not the old one.

Codex captures its actual session ID using reviewed SessionStart and
UserPromptSubmit hooks. `scripts/codex-lead.sh` stores it per team name under
`.pipeline/.codex-session-id.<session-name>` and resumes that exact conversation.
It never uses `--last` or starts a fresh conversation after a failed resume.
Review/trust the generated hooks with `/hooks`; existing hooks need a hand-merge.
Use `--fresh` to deliberately reset a conversation. Missing capture or a stale
process lock requires explicit recovery; see [Codex lead operation](CODEX.md).

OpenCode deliberately does **not** use `--continue`: the latest session may be
a worker, not the lead. It starts a fresh lead chat unless you supply a known
lead session id via `TEAM_OPENCODE_SESSION=ses_... scripts/team.sh --lead opencode`.
`--fresh` ignores this variable. Obtain the exact id from OpenCode; never
invent it or strip uppercase characters. This is not automatic pinned resume.

## Running two projects at once

`opencode serve` binds one port per process. Two projects both defaulting
to port 4096 collide — the second one's server fails to bind, and until
now the only fix was killing the first project's session. Instead, give
the second project its own port:

```
scripts/team.sh --port 4097
```

That port gets written to `.pipeline/.oc-port` in this repo. `scripts/oc.sh`
reads it automatically (when `OC_SERVER` isn't already set), so every
`oc.sh` call in this project just uses the right port — you don't export
`OC_SERVER` by hand for every call.

**`.pipeline/.oc-port` is gitignored automatically by `bin/init.sh`** when
the target is a git repo — it's local machine state (which port happened
to be free on your laptop today), not something to commit. If your project
predates that, or ignores it differently, add it by hand.

## Task dashboard (no launcher required)

From the project root, open the read-only visual dashboard:

```bash
./scripts/dashboard
```

It refreshes `.pipeline/T-*.md` every two seconds, showing stage graphs, task
cards, acceptance ticks, blockers, and latest handoffs. Use arrows or `j/k` to
scroll, `b` to filter blocked tasks, `r` to refresh, and `q` to close.

```bash
./scripts/dashboard --once                  # plain-text snapshot
./scripts/dashboard --project /path/to/repo # another project
```

Requires Python 3.8+ on macOS/Linux; no Herdr, tmux, running agent, toolkit
checkout, or model calls. It displays recorded state, not live verification.
Init installs the command automatically. For older scaffolds, see
[adding the dashboard during upgrade](UPGRADING.md#adding-the-project-dashboard).

## Shell completion (optional)

`scripts/team-completion.bash` completes `--fresh`, `--lead`, `--port`, `--kill`,
and `-h`/`--help`. It's not installed automatically — source it from your
shell rc file if you want it:

```bash
# ~/.bashrc or ~/.zshrc (zsh needs `autoload -U +X bashcompinit && bashcompinit` first)
source /path/to/this/repo/scripts/team-completion.bash
```
