---
name: dev-team-generator
description: Interview the user, then generate a multi-agent pipeline (lead + planner/implementer/reviewer/tester, state-file handoff) for a project, under whatever AI tool(s) are actually available — not limited to Claude Code + OpenCode. Use when the user wants a multi-agent dev pipeline, cross-vendor review, or "a team like agent-toolkit" but the tools involved aren't a fixed Claude+OpenCode pair, or when no existing template already covers the target tool.
---

# Dev Team Generator

Generates a working multi-agent pipeline **live**, by interviewing the user
and then writing every file fresh — adapted to this project and to whatever
tool actually runs each role — rather than substituting placeholders into
static template files. That trade (a generation step instead of a stamping
step) is what makes "any tool" a real day-one capability instead of a
per-tool template someone has to add in advance.

**This skill is fully self-contained** — everything it needs to reason
from travels with it, in `reference/`. Nothing in it reads or requires any
file outside this folder; copy `dev-team-generator/` on its own into any
project, under any AI tool, and it works the same way.

**If a sibling `toolkit-init` skill also happens to be available** (it
ships alongside this one in the `agent-toolkit` project this skill was
originally distilled from, and might be installed next to this one
elsewhere too): that one is the faster, more predictable path specifically
when the target is Claude Code as lead + OpenCode as workers, since it
fills in an existing template tree instead of generating fresh. Prefer it
for exactly that pair. Reach for **this** skill instead whenever a role
needs a tool that isn't that exact pair, the interview-and-adapt flow is
preferred over fixed templates, or `toolkit-init` isn't available at all —
which is the common case for this folder used on its own.

## The five roles, unchanged

Whatever tool ends up running each one, the shape is fixed — this is the
part that isn't up for reinterpretation per project:

- **Lead** — manages sessions (dispatch the right role, track which task is
  where) and makes the decisions that are genuinely its to make (see *Stop
  and ask at*, in the generated flow file). Never writes feature code
  itself. Whichever AI/tool is running *this skill* is the lead by default.
- **Planner** — read-only spec writer. Turns a request into a state file
  with checkable acceptance criteria and file-level scope. Never designs
  the implementation.
- **Implementer** — the only role that edits source. Reads an approved
  spec, writes the code, records the diff and its reasoning in the state
  file.
- **Reviewer** — a second pair of eyes from a **different vendor/model
  family** than whoever implemented. Source is read-only to it by design.
- **Tester** — runs the suites, triages failures with reproduction steps.
  Never fixes anything.

A small project may not need all four workers under separate tools — see
*Step 1*, question 3.

## Step 1 — Ask first

Don't guess any of this. Ask the user (conversationally or via a structured
question tool if one is available) before writing anything:

1. **Project name**, and confirm it has a root guidance file (`CLAUDE.md` /
   `AGENTS.md` / equivalent). If it doesn't, say plainly that every
   generated role reads that file for constraints and ask whether to write
   a minimal one first (see `reference/state-file-example.md`'s header for
   the kind of thing it needs to state) — don't generate the pipeline into
   a project with nothing for it to read.
2. **Which roles are actually needed.** Full team (planner + implementer +
   reviewer + tester), or a subset — e.g. a solo user might not want a
   separate planner for every task (the generated lead's own flow should
   still carry the "skip the planner when the spec is already complete"
   judgment call from `reference/flow-example.md`, not lose it just
   because a role is being skipped by default here).
3. **Per role, which tool runs it.** Two shapes, and a role can be either:
   - **Inline** — the lead's own tool does the work directly (e.g. a
     Claude Code subagent via the `Agent`/Task mechanism). No dispatch
     wrapper needed; weaker cross-vendor independence for review if the
     lead's tool is also the implementer's tool.
   - **Dispatched** — a separate CLI tool, invoked non-interactively with
     a role + model argument (OpenCode's `opencode run --attach` is the
     worked example this toolkit already has; there is no reason a second
     or third CLI tool can't sit alongside it). Needs a dispatch wrapper —
     see Step 3.
   For any tool that isn't already a worked example in this folder's
   `reference/role-examples.md` **and** isn't already scaffolded in this
   target project (check `.claude/agents/`, `.opencode/agent/`, or
   whatever that tool's own convention is), go to **Step 2** before
   promising it works.
4. **Cross-vendor independence for review, specifically.** The reviewer
   must not share a vendor/model family with whoever implemented (two
   models on the same aggregator still count as the same family if they're
   the same weights). Ask for a reviewer model **and** a fallback reviewer
   model in a third family, for whenever the two would otherwise collide.
   Never accept an "auto"/router model id for the reviewer — see
   `reference/models.md`.
5. **Source directories** the implementer may touch, and anything
   explicitly off-limits without an Open Question first.
6. **Test command**, and a test directory (create one if none exists yet,
   matching whatever test framework the project already uses).
7. **Whether any dispatched tool's own "wide auto-approve" flag should ever
   be available**, if it has one (OpenCode's `--auto` is the worked
   example — see `reference/lessons-learned.md`'s first entry). Default
   answer is no; if yes, it must be **off by default, per-task opt-in,
   confirmed by the user at spec approval time**, never a standing
   default written into the generated implementer's dispatch — say this
   plainly rather than letting "yes" become "always."

If the user's answers reveal the request is already fully specified
somewhere (an existing plan doc, ticket, or prior spec) — skip straight to
generating the pipeline around that, the same judgment call
`reference/flow-example.md` describes for skipping the planner on a
per-task basis, just applied here at setup time.

## Step 2 — Onboard any tool this folder doesn't already cover

Read `reference/tool-onboarding.md` and follow it **before** writing a
single role file for that tool. Do not adapt an OpenCode-shaped or
Claude-Code-shaped file by guessing at the new tool's config format,
permission model, or dispatch mechanism — research it live first. A tool
that turns out to only support an interactive UI, or only a global
(not per-repo) custom-agent config, is a real constraint to say out loud,
not something to paper over by pretending the fit is closer than it is.

## Step 3 — Generate, starting from the leader

Write files in this order — later ones depend on decisions the earlier
ones make:

1. **The lead's own flow/orchestration file first.** This is what defines
   the state-file contract, the pipeline sequence, the loop cap, and the
   stop-and-ask list for this specific project. Adapt
   `reference/flow-example.md` to whatever mechanism the lead's own tool
   supports for a repeatable instruction set (a slash command if it's
   Claude Code; otherwise whatever that tool's own equivalent is — ask
   rather than assume one exists). This file is the one every worker role
   implicitly serves; writing it first is what makes "starting from the
   leader" true in practice, not just in the write order.
2. **Each worker role**, in whichever location and frontmatter/config
   shape its tool actually expects (per Step 1's answers and Step 2's
   research, if it was new). Use `reference/role-examples.md` as a style
   reference for each role's job description, hard rules, working rhythm,
   and report format — adapt the prose, don't paste it; the actual hard
   constraint (never designs the implementation / only role that edits
   source / read-only and a different vendor / never fixes anything) stays
   fixed per role regardless of tool.
3. **A dispatch wrapper for each tool that's dispatched (not inline).**
   `reference/lessons-learned.md` has the proven shape (session reuse,
   summary-only output extraction, hard timeout, abort-on-timeout,
   opt-in-only wide-auto-approve) — port the mechanism, not the OpenCode
   specifics, to whatever the new tool's own CLI actually supports for
   each of those. If the new tool has no non-interactive dispatch surface
   at all, say so — it cannot be a scripted pipeline participant, full
   stop, and the user needs to know that before relying on it as one.
4. **The state-file template** (`reference/state-file-example.md`) — the
   one handoff surface every role reads and writes. Nothing is passed
   between roles by prose alone.
5. **A structural verification script and a findings-promotion script**,
   if this project doesn't already have equivalents — see
   `reference/lessons-learned.md`'s "verification is a script, not a sixth
   agent" entry for why these are worth generating even for a small
   project: a few lines of grep/awk that can't hallucinate a pass, instead
   of a paid dispatch to check another dispatch's output.

**Never overwrite an existing file.** If a target path already has
content, skip it and say so in the final summary — do not silently
clobber something the user or a prior run already customized. If this is a
re-run against a project this skill already set up, offer the same
diff-and-report path `bin/init.sh --update` uses (render to a temp
location, `diff -u` against the live file, write nothing) rather than
overwriting.

## Step 4 — After generation

1. **Verify permission scoping live, not from the config alone.** Dispatch
   the reviewer once and have it try to edit a source file (must be
   refused) and write to the state-file directory if that's its intended
   scope (must succeed). A permission block that reads correctly is not
   the same as one the runtime actually enforces — this has bitten a real
   project before (a blanket-deny config that still let a reviewer write
   outside its intended scope).
2. **Confirm the root guidance file exists and is current** — every
   generated role reads it for constraints; if Step 1 flagged it as
   missing, this is where that gets resolved, not skipped.
3. Tell the user the pipeline is ready and name the first thing to run
   through it — a small, real task, not a synthetic one — so the loop gets
   exercised end to end (spec → approval → implement → review → test →
   report) before anything larger goes through it.
4. If this run is happening inside the `agent-toolkit` checkout itself,
   mention that the generated project can also use the `delegate` and
   `karpathy-guidelines` skills from `../..`'s `skills/` directory if it's
   running under Claude Code — this skill's own `reference/` material
   already carries the load-bearing parts of that discipline inline (see
   `reference/lessons-learned.md`), so it isn't a hard dependency, just a
   convenience if that specific toolkit is already at hand.

## What lives in this folder, and why

Everything under `reference/` is written to travel with this skill folder
on its own — copy `dev-team-generator/` somewhere else and it still has what it
needs. That's a deliberate duplication against `agent-toolkit`'s own
`docs/` and `templates/` (which this skill was distilled from): those stay
the source of truth for the Claude+OpenCode fast path (`toolkit-init`),
this folder is the source of truth for the generate-anything path.

- `reference/lessons-learned.md` — hardening rules earned the hard way
  (a real incident or a live verification each), generalized beyond any
  one tool.
- `reference/tool-onboarding.md` — how to research a new tool's real
  config/permission/dispatch surface before writing anything for it.
- `reference/flow-example.md` — a full worked lead/orchestration sequence
  to adapt.
- `reference/role-examples.md` — condensed, tool-agnostic-flavored
  exemplars for each of the four worker roles.
- `reference/state-file-example.md` — the handoff-file shape.
- `reference/models.md` — vendor-independence rules and a cost/quality
  starting point for model choice; advisory, always still asked about per
  Step 1.
