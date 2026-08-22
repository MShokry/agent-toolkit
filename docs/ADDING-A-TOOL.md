# Adding or moving an agent to a new tool

This is a recipe, meant to be followed on request — by an AI asked to "add
Cursor support" or "move the tester to tool X", or by a human doing it by
hand. It is not standing architecture: this toolkit keeps each role's file
self-contained per tool by default (see README's "Design decisions" for
why a shared-file version of this was tried and reverted). Reach for the
extraction step at the bottom only once a role is actually needed by a
second or third tool — not before.

## Case 1 — a role this toolkit already has, running under a tool it
doesn't support yet

Example: `tester` exists only for OpenCode (`.opencode/agent/tester.md`);
you want it to also run under some other tool.

1. **Learn the new tool's own agent/rule format first** — don't guess it.
   Find: where it looks for custom agent/rule definitions (a directory
   convention, like `.claude/agents/` or `.opencode/agent/`), what
   frontmatter or config keys it reads (model selection, a permission or
   capability model, a system-prompt field), and how — or whether — it can
   be dispatched non-interactively from a script (OpenCode has `opencode
   run --attach`; Claude Code subagents are dispatched via the `Agent`/Task
   tool from a lead session; a given third tool might only support an
   interactive UI, in which case it cannot be a `scripts/oc.sh`-style
   pipeline participant at all — say so rather than forcing the fit).
2. **Copy the existing single-tool file's actual prose**, not its
   frontmatter — job description, hard rules, working rhythm, report
   format. Adapt only what's genuinely tool-specific: the non-interactive
   framing (why there's no human to ask mid-run, if that's even true for
   this tool), the permission/capability syntax, any tool-specific
   quirk worth a line (e.g. OpenCode's `question: deny` needing an explicit
   note that it means literally no channel to ask through).
3. **Write the new tool's frontmatter for real**, in its own required
   shape — don't invent a plausible-looking schema. If the tool has a
   narrower or wider permission model than the ones already here, that
   difference is real and should show up as a real difference in what this
   role is trusted to do under that tool, not be smoothed over.
4. **Add it to the scaffolder**: put the new file under
   `templates/<tool>/...` with `__PLACEHOLDER__` tokens matching the
   existing convention (`__PROJECT_NAME__`, `__CLAUDE_MODEL__`, etc. — add
   a new one to `bin/init.sh`'s `render()` substitution list if this tool
   needs a model flag `init.sh` doesn't already take), then add a `render`
   line for it in `bin/init.sh`.
5. **If the new tool needs its own dispatch mechanism** (the way OpenCode
   needs `scripts/oc.sh`), write and template it the same way — see
   `templates/scripts/oc.sh.tmpl` for the shape (session reuse, `--text`
   to avoid inlining raw event streams, exit-code handling for usage-cap
   errors). `feature.md.tmpl`'s pipeline steps call whichever dispatch
   mechanism a given role's tool needs; add the new one there too,
   following the existing `builder`/`senior-dev` two-option pattern in
   step 2.
6. **Update README**: the file tree, the role-permissions table, and the
   "How it flows" diagrams if a genuinely new path through the pipeline
   was added (not just a new implementer vendor, which the existing
   diagram already generalizes over).
7. **Smoke-test**: re-run `bin/init.sh` into a scratch directory and
   confirm the new file renders with no leftover `__PLACEHOLDER__` tokens.

## Case 2 — a role that's now genuinely duplicated across 2+ tools

Only once Case 1 has actually happened twice for the same role (not in
anticipation of it): consider collapsing the now-duplicated prose into one
shared file, so a future behavioral fix is one edit instead of N.

1. Extract the actual instructions — not the frontmatter — into
   `.agents/roles/<role>.md` (rendered from a new
   `templates/agents-state/roles/<role>.md.tmpl`), written generically: no
   tool name in the prose itself, since two or more tools now read it.
2. Shrink every existing tool-specific file for that role down to: its own
   real frontmatter/permission block (this can never be shared — it's the
   one thing that's genuinely different per tool), a short paragraph on
   what's tool-specific about running this role under this tool, and one
   line: "Read `.agents/roles/<role>.md` now, in full, before doing
   anything else."
3. Add the new canonical file's `render` line to `bin/init.sh`.
4. Update README to note the exception — this toolkit's default is one
   self-contained file per tool; a role that hits this step is the
   exception, and the exception should be visible, not silent.

## Note: adding an AI tool as the *lead*, not a worker role

Everything above is about porting a worker role (planner/implementer/
reviewer/tester) to a new tool, dispatched by an existing lead. If you want
a *different* AI to be the lead itself — the orchestrator, not a dispatched
role — that's not this recipe. See [`SYSTEM.md`](../SYSTEM.md) at the repo
root: a single tool-agnostic file meant to be handed directly to that AI
("recreate this system, with yourself as the lead"), rather than something
this toolkit generates for it the way `bin/init.sh` generates worker-role
shims.

**The tradeoff, stated plainly, so it's a real decision and not a reflex:**
an extra file read before the role can do anything, and content that's
genuinely tool-specific (not all of it) has to be judgment-called into
either the shim or the shared file — get that split wrong and you end up
re-litigating "why doesn't this line apply to me" the way this toolkit's
own `senior-dev`/`builder` split briefly did over skill access. If a role
only ever ends up needing one tool, this step was never worth taking for
it — that's normal, not a gap to preemptively fix.
