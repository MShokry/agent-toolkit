# Onboarding a tool this folder doesn't already cover

Follow this before writing a role file or dispatch wrapper for any tool
that isn't already a worked example in `role-examples.md`, or already
scaffolded in the target project. This is the primary path for this skill
— "any tool" means doing this research live, every time it's genuinely
needed, not maintaining an ever-growing library of pre-built adapters.

## For a worker role (planner / implementer / reviewer / tester) under a new tool

1. **Learn the tool's real agent/rule format first — don't guess it.**
   Find, from the tool's own documentation or by experimenting with it
   directly:
   - Where it looks for custom agent/rule definitions — a per-repo
     directory convention (like `.claude/agents/` or `.opencode/agent/`),
     a global (per-machine) config location, or no custom-agent concept
     at all.
   - What frontmatter or config keys it actually reads: model selection, a
     permission/capability model, a system-prompt field, temperature or
     similar generation controls.
   - **How — or whether — it can be dispatched non-interactively from a
     script.** OpenCode has `opencode run --attach`; a Claude Code
     subagent is dispatched via that session's own Agent/Task mechanism,
     not a separate CLI at all. A given tool might only support an
     interactive UI, in which case it **cannot** be a scripted pipeline
     participant — say that plainly instead of forcing the fit. This is
     the single most important thing to get right before writing anything
     else, since everything downstream (the dispatch wrapper, the lead's
     dispatch commands) depends on it existing.
   - Its actual permission/capability model's real shape: a per-command
     allow/deny/ask map is not the same *kind* of thing as one coarse
     sandbox flag with no per-command granularity. If the tool's model is
     coarser than what a role needs (e.g. it can't scope a reviewer to
     read-only), say so explicitly in that role's own generated
     instructions rather than implying a scoping guarantee the tool can't
     actually enforce.

2. **Write the role's actual content adapted from `role-examples.md`, not
   copied.** Keep: the job description, the hard rule that's fixed for that
   role regardless of tool (never designs the implementation / only role
   that edits source / read-only and a different vendor / never fixes
   anything), the working rhythm, the report format (short reply, full
   record in the state file). Adapt: the non-interactive framing (does this
   tool even have a human to ask mid-run? if not, say what happens on an
   unanswerable question instead — usually: record it and move on, never
   block), the permission/capability syntax in whatever shape this tool
   actually uses, any tool-specific quirk worth one line (the kind of thing
   OpenCode's `question: deny` needing an explicit "there is no channel to
   ask through" note is an example of).

3. **Write the frontmatter/config for real, in the tool's own required
   shape.** Don't invent a plausible-looking schema by analogy to
   OpenCode's or Claude Code's. If you can't find documentation for the
   exact shape, generate a minimal test file and confirm the tool actually
   reads and applies it (a made-up permission key that's silently ignored
   is worse than no permission block at all, since it looks like a
   guarantee that isn't one).

4. **If this role needs a dispatch wrapper** (the tool is a separate CLI,
   not inline in the lead's own session), write it following the shape in
   `lessons-learned.md` entries 1–3 (opt-in-only wide-auto-approve if the
   tool has one, hard timeout, abort-on-timeout using whatever session
   concept this tool exposes, verified live) — port the *mechanism*, not
   any OpenCode-specific flag or endpoint name.

5. **Smoke-test before relying on it.** Dispatch the new role once with a
   throwaway prompt and confirm: it actually runs non-interactively and
   returns, its permission scoping does what the config claims (try to get
   it to do the disallowed thing), and its output can actually be captured
   in the form the wrapper expects (some CLIs batch their entire output
   until the turn completes rather than streaming it — see
   `lessons-learned.md` entry 3 for why this matters and how it was
   caught).

## For an AI tool as the *lead itself*, not a dispatched worker role

That's a different, smaller job than the above — the lead doesn't need a
dispatch wrapper (it's not being dispatched by anything), a permission
block (nothing above it is scoping it down), or a frontmatter schema
(most tools don't need one for "the thing the human is talking to
directly"). It needs:

1. A way to read and write the state file — any tool with file access can
   do this.
2. A way to run each worker role — either inline (do the work itself,
   which is weaker for cross-vendor review independence if the lead's own
   tool is also the implementer's), or by shelling out to a dispatch
   wrapper the way described above.
3. The discipline in `flow-example.md` and `lessons-learned.md`, actually
   followed — the short-reply convention, the loop cap, the stop-and-ask
   list.

Don't assume any specific slash-command or subagent mechanism transfers —
adapt the *sequence* in `flow-example.md`, not its file format.

## Once a role has genuinely run under two or more tools

Only after this has actually happened twice for the same role (not in
anticipation of it), consider extracting that role's shared prose into one
canonical file each tool-specific shim points to, so a future behavioral
fix is one edit instead of N. Doing this before it's actually needed twice
adds an extra file every role has to read before doing anything, for a
duplication problem that doesn't exist yet — don't take this step early.
