---
name: toolkit-init
description: Scaffold the multi-agent pipeline (planner/implementer/reviewer/tester, cross-vendor via OpenCode, state-file handoff) into the current project. Use when the user asks to set up the agent pipeline, multi-agent review, or cross-vendor code review in a new repo.
---

# Toolkit init

Bootstraps the current project with the same planner → implement → review →
test pipeline used elsewhere, backed by `bin/init.sh` in the toolkit repo
(default location: `~/PWS/agent-toolkit` — ask the user if it isn't there).

## What you need from the user before running it

Ask these up front rather than guessing — they shape every generated file:

1. **Project name** — used in a few descriptions and the tmux session name.
2. **Claude model** for planner/senior-dev (default `sonnet`).
3. **Cross-vendor provider and models.** Run `opencode models` in the
   target project and show the user the list rather than assuming what's
   configured. You need three: builder, reviewer, and a reviewer-fallback
   in a *different* model family (used when builder implements, so review
   stays independent of the implementer).
4. **Source directories** the implementer is allowed to touch, and any
   this project considers off-limits without an Open Question first.
5. **Test command** and, if applicable, a test directory (default `e2e`).

## Run it

```bash
~/PWS/agent-toolkit/bin/init.sh \
  --target . \
  --project-name "<name>" \
  --claude-model sonnet \
  --builder-model "<vendor/model>" \
  --reviewer-model "<vendor/model, different family than builder>" \
  --reviewer-fallback-model "<vendor/model, different family again>" \
  --tester-model "<vendor/model>" \
  --test-dir "<e2e or similar>"
```

It writes `.claude/agents/`, `.opencode/agent/`, `.claude/commands/feature.md`,
`.agents/TEMPLATE.md`, and `scripts/{oc.sh,team.sh,verify-state.sh,
promote-findings.sh}` into the target. It does **not** overwrite a file that
already exists — it prints what it skipped so you can diff and merge by
hand.

## After it runs

1. Read every generated file with the user before treating the pipeline as
   live — the reviewer's permission block in particular changes what "the
   reviewer cannot touch source" actually guarantees. That guarantee should
   be verified against the real OpenCode server (dispatch it once, try to
   get it to edit a source file, confirm it's refused) rather than assumed
   from the YAML. This has bitten a real project before: a blanket-deny
   config still let a reviewer write outside its intended scope.
2. Confirm `opencode serve` is reachable, per the printed next step.
3. Tell the user to load the `delegate` skill at the start of the lead's
   own session — it's the context-discipline half of this, not the
   workflow half.
4. The generated `.claude/commands/feature.md` and agent files reference
   "this project's own guidance file" for constraints — make sure the
   project actually has a `CLAUDE.md`/`AGENTS.md` before relying on that,
   or the delegates have nothing to read.
