# agent-toolkit — maintainer instructions

This file is for any AI tool (Codex, OpenCode, Claude Code) that is *changing the
toolkit's own code*. It is not the `AGENTS.md` that `bin/init.sh` generates into
target projects; that comes from `templates/codex/AGENTS.md.tmpl`.

The maintainer guide lives in **`CLAUDE.md`** at this repository root. Read it
in full before editing; it is the single source of truth, and is deliberately
not duplicated here so the two cannot drift. Its "Claude" wording refers to the
lead tool whose command files are the canonical flow; it does not require the
Claude CLI.

Minimum checks before claiming a change works:

```bash
bash test/smoke.sh
bash test/invariants.sh
bash test/codex.sh
python3 test/herdr.py
```

Runtime state for scaffolded projects is `.pipeline/`; skills stay in
`.agents/skills/`. Never move task records back under `.agents/`.
