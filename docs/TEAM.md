# `scripts/team.sh`

A tmux layout for running the pipeline: pane 0 is the lead (`claude`), pane
1 is `opencode serve` (what `scripts/oc.sh` attaches to), pane 2 tails
`.agents/` for activity, pane 3 is free.

## Usage

```
scripts/team.sh [session-name]     start, or attach if it's already running
scripts/team.sh --fresh            start a NEW lead conversation, not a resume
scripts/team.sh --port <N>         opencode server port (default 4096)
scripts/team.sh --kill [session-name]
```

Flags can combine with a session name in any order:
`scripts/team.sh --port 4097 my-second-project`.

## Resuming is the default

Pane 0 runs `claude --continue`, which picks up the most recent
conversation in this project's directory — not a fresh one. This exists
because killing the tmux session (the usual way to free up a port, or just
closing the terminal) used to also throw away the lead's context, with no
way back into the same conversation. Now: kill it, come back later, run
`scripts/team.sh` again, the lead is where you left it.

Pass `--fresh` on the rare run where you actually want a clean slate
instead.

## Running two projects at once

`opencode serve` binds one port per process. Two projects both defaulting
to port 4096 collide — the second one's server fails to bind, and until
now the only fix was killing the first project's session. Instead, give
the second project its own port:

```
scripts/team.sh --port 4097
```

That port gets written to `.agents/.oc-port` in this repo. `scripts/oc.sh`
reads it automatically (when `OC_SERVER` isn't already set), so every
`oc.sh` call in this project just uses the right port — you don't export
`OC_SERVER` by hand for every call.

**Add `.agents/.oc-port` to this project's `.gitignore`.** It's local
machine state — which port happened to be free on your laptop today — not
something to commit.

## Shell completion (optional)

`scripts/team-completion.bash` completes `--fresh`, `--port`, `--kill`,
and `-h`/`--help`. It's not installed automatically — source it from your
shell rc file if you want it:

```bash
# ~/.bashrc or ~/.zshrc (zsh needs `autoload -U +X bashcompinit && bashcompinit` first)
source /path/to/this/repo/scripts/team-completion.bash
```
