---
name: toolkit-init
description: Scaffold the multi-agent pipeline (planner/implementer/reviewer/tester, cross-vendor via OpenCode, state-file handoff) into the current project. Use when the user asks to set up the agent pipeline, multi-agent review, or cross-vendor code review in a new repo.
---

# Toolkit init

Bootstraps the current project with the same planner → implement → review →
test pipeline used elsewhere, backed by `bin/init.sh` in the toolkit repo
(wherever it's cloned — ask the user for the path if you can't find a
checkout; nothing in this skill assumes a fixed location).

## What you need from the user before running it

Ask these up front rather than guessing — they shape every generated file:

1. **Project name** — used in a few descriptions and the tmux session name.
2. **Claude model** for planner/senior-dev (default `sonnet`).
3. **Cross-vendor provider and models.** Run `opencode models` in the
   target project and show the user the list rather than assuming what's
   configured. You need three: builder, reviewer, and a reviewer-fallback
   in a *different* model family (used when builder implements, so review
   stays independent of the implementer). If they have not chosen yet,
   offer `docs/MODELS.md` as a starting recommendation (Kimi builder,
   GLM reviewer, DeepSeek Flash tester, Sonnet fallback; one OpenCode
   aggregator plus Claude — not a new toolkit tool per lab) and let them
   confirm or override. Never accept `auto` for the reviewer.
4. **Source directories** the implementer is allowed to touch, and any
   this project considers off-limits without an Open Question first.
5. **Test command** and, if applicable, a test directory (default `e2e`).

## Run it

```bash
/path/to/agent-toolkit/bin/init.sh \
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

When the toolkit itself has moved on since this project was scaffolded, add
`--update` to the same command (same flags) instead of re-running it plain.
It writes nothing — it renders the current templates and prints a `diff -u`
against each live file that changed, for the user (or you) to merge by
hand.

## If the user wants a worker role under a tool this doesn't already template

`bin/init.sh` only knows Claude and OpenCode today. If the user asks for a
*worker* role (planner/implementer/reviewer/tester) under a different tool:

1. **Don't force it into `bin/init.sh`'s shape by guessing.** Different
   tools genuinely differ in how they read project config, discover custom
   agents, and scope permissions — check the target tool's real surface
   before assuming it works like OpenCode.
2. **Research the tool's real config/discovery surface before writing
   anything** — see `docs/ADDING-A-TOOL.md`'s Case 1, step 1.
3. **Ask the model to use for the new role**, the same way step 3 above
   already asks for builder/reviewer/tester models — this doesn't change
   just because the tool is new.
4. **Follow the Case 1 recipe live**: write the role's real content (using
   an existing role file as a style reference, not a copy-paste target),
   pick the right mechanism for that tool, and say plainly what guarantees
   that tool's permission model can and can't give — don't imply a scoping
   guarantee the tool can't actually enforce.
5. Offer to add a real `templates/<tool>/` entry to the toolkit itself
   afterward, so the next project doesn't repeat the research — but do the
   research-then-build step live for this project regardless of whether
   that offer is taken.

If instead the user wants a *different AI to be the lead itself* — not a
worker role dispatched by an existing lead — that's not this skill. Point
them at `SYSTEM.md` at the toolkit root instead.

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
