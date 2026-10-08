# Migration 05 — Codex native implementer and reviewer

Apply at a task boundary. Only needed for a project that runs a Codex lead,
or wants a `codex/*` reviewer. Additive: no existing field changes meaning,
and historical `T-*.md` files stay as they are.

1. In `.pipeline/TEMPLATE.md`, add `codex-dev` to *Owner right now* and
   *Implementer for this task*, and add the *Codex implementer thread id* and
   *Codex reviewer thread id* lines from
   `templates/agents-state/TEMPLATE.md.tmpl` after *Codex tester thread id*.
2. Run `bin/init.sh --target .` (no flags) to add the new files:
   `.codex/agents/codex-dev.toml` and `.codex/rules/pipeline.rules`. A
   `--reviewer-model codex/<model>` project also gets
   `.codex/agents/reviewer.toml`; add `reviewer_model: codex/<model>` to the
   stamp first, or pass the flag.
3. **Review `.codex/rules/pipeline.rules` before trusting it.** It is a
   permission change: it lets the four dispatch wrappers run outside the
   sandbox without a prompt per call. Confirm live that
   `scripts/oc.sh --status` runs unprompted and `git push` still prompts. If
   you already allow these in `~/.codex/rules/default.rules`, the project file
   is what makes it reviewable and shared; keep or drop the personal rules.
4. Merge into `.claude/commands/feature.md`: the `codex-dev` implementer
   option, the vendor-family independence paragraph, the Codex reviewer
   paragraph, the usage-limit `--retry-on-limit` sentence, and the generalized
   "native subagent this lead cannot spawn" paragraph. Merge the matching
   bullets into `.agents/skills/feature/SKILL.md`.
5. Merge `scripts/bg-dispatch.sh` (`--retry-on-limit`),
   `scripts/codex-preflight.sh` (exit 3, reviewer check), and
   `scripts/codex-session.py` (silent per-prompt capture, unfinished-task
   summary at session start). The hook change needs renewed `/hooks` trust.
6. Run `bash scripts/codex-preflight.sh` from the lead's sandbox. Exit 3 means
   run `scripts/oc.sh --status` next; exit 0 there completes preflight.
