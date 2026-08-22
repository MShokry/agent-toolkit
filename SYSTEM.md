# System — read this first, whatever AI or tool you are

One file, meant to be handed to **any** AI coding tool (Claude, Codex,
Gemini, whatever you're running) with an instruction like "recreate this
system, with yourself as the lead." It gives you the *shape* of the whole
pipeline compactly, so you don't pay to read every file in `templates/` up
front — pull in a specific template's full text only once you actually need
that role's exact prose, using the paths cited below.

**Do not copy any template file byte-for-byte assuming it fits your tool.**
Claude Code and OpenCode both discover custom agent files per-repo; not
every tool does — some tools (Codex, for one) only support custom agents
globally per machine, not per-repo, and permission models differ in shape,
not just detail (a per-command allow/deny/ask map is not the same kind of
thing as one coarse sandbox flag). Read `docs/ADDING-A-TOOL.md` before
assuming a mechanism transfers — check your actual tool's real config and
capability surface first, the same way this toolkit's own worker-role
ports did, and recreate the *behavior*, adapted to what your tool can
actually enforce, rather than pasting a file in and hoping.

## The shape, compactly

**Five roles, one job each:**

- **Lead** — you, if you're reading this to become one. Manages sessions
  (dispatch the right role, track which task is where) and makes the
  decisions that are genuinely its to make (see *Stop and ask at*, below).
  Never writes feature code itself.
- **Planner** — read-only spec writer. Turns a request into a filled state
  file with checkable acceptance criteria and file-level scope. Never
  touches source, never designs the implementation (that's the
  implementer's call, not the planner's).
- **Implementer** — the only role that edits source. Reads an
  approved spec, writes the code, records the diff and its reasoning.
- **Reviewer** — a second pair of eyes from a **different vendor** than
  whoever implemented. Source is read-only to it by design — a reviewer
  that can edit code is a second author, not a second eye.
- **Tester** — runs the suites, triages failures with reproduction steps.
  Never fixes anything, never edits source.

**The state file is the only handoff surface.** One file per task/feature —
`.agents/T-<id>.md`, shape at `templates/agents-state/TEMPLATE.md.tmpl` —
holding Status, Goal, Acceptance criteria, Files in scope, a Decisions log,
Review verdicts, Test results, Findings for docs, and Open questions.
Nothing is passed between roles by prose alone: if a fact isn't written in
this file, the next role doesn't know it. Read that one template file now
if you're going to operate this system — it's the actual contract.

**A role's reply is a receipt, not the record.** Every role writes its full
output — diff, findings, test results — into the state file, then replies
with only a short status: a verdict line, a pass/fail count, or the one-line
`Latest handoff` the file's own header carries (`<role> → <outcome> → next:
<role>`). The lead reads that one line between steps instead of re-reading
the whole file, and opens it in full only on a verification failure or a
real decision. This is what keeps the lead's own context flat across a long
run — see `templates/claude/commands/feature.md.tmpl`'s "Token discipline"
section for the reasoning in full, even though that file's own format is
Claude-Code-specific.

**Verification is a script, not a sixth agent.** Checking whether a
verdict landed in the right heading, or whether a finding needs promoting
to project docs, needs no judgment — `templates/scripts/verify-state.sh.tmpl`
and `templates/scripts/promote-findings.sh.tmpl` do it deterministically,
for free, and can't hallucinate a pass. Dispatching another agent to check
an agent's structural output is a paid call that adds a component that can
misjudge the same way the one it's checking can. Prefer the script.

**Permission is least-privilege per role, verified live, not assumed.**
Whatever your tool's capability model actually is, give the reviewer
nothing beyond read + (optionally) writing its own verdict; give the
tester write access to its own test directory and the state file only, not
source. If your tool's model is coarser than that (all-or-nothing, like
Codex's sandbox), say so explicitly in the role's own instructions rather
than implying a scoping guarantee that isn't real — don't trust a
permission block just because it reads correctly; dispatch it once and try
to make it do the disallowed thing before relying on it.

**Loop discipline:** max two review loops on CHANGES_REQUESTED; a third
means the spec was wrong, not the code — stop and ask the human. Never
merge without asking. Any new permission or dependency, however reasonable
it looks, gets asked about too.

## Before you build anything, ask the human

Don't guess these and don't default silently — get them from whoever asked
you to do this, the same way this toolkit's own scaffolder (`bin/init.sh`)
takes them as required arguments rather than assuming:

1. **Which model runs each role** — planner, implementer, reviewer,
   tester, and yourself as lead. If you (the lead) can run multiple
   models, ask which one for orchestration too, don't assume it's
   whichever one is reading this file right now. A cost/quality starting
   point (and how to wire providers) is `docs/MODELS.md` in this
   toolkit — still ask; don't apply it silently.
2. **Cross-vendor independence for review, specifically.** The reviewer
   must not share a vendor/model family with whoever implemented — ask for
   a reviewer model and a *fallback* reviewer model in a different family,
   the same way `templates/opencode/agent/reviewer.md.tmpl`'s consumer
   does, for whenever the two would otherwise collide.
3. **Source directories you're allowed to touch as implementer**, and
   anything explicitly off-limits without an Open Question first.
4. **The test command**, and a test directory if one doesn't exist yet.

If you can't actually run more than one model or vendor from where you're
operating, say that plainly rather than quietly implementing every role
yourself — a "reviewer" that's the same model as the implementer, with no
one told, is not cross-vendor independence, it's a missing control wearing
its label.

## How to actually become the lead, in your own tool

You don't need to replicate any specific tool's slash-command or subagent
mechanism. You need three things:

1. **A way to read and write `.agents/T-<id>.md`** — any tool with file
   access can do this.
2. **A way to run each worker role** — either do the work yourself inline
   (weaker: no cross-vendor independence for review), or shell out to a
   wrapper the way `templates/scripts/oc.sh.tmpl` does for OpenCode — a
   thin CLI wrapper that passes a role's instructions and a model choice to
   another agent process and gets its final text back, nothing more exotic
   than that.
3. **The discipline rules above**, actually followed — the short-reply
   convention, the loop cap, the stop-and-ask list.

For the exact orchestration *sequence* (preflight checks → dispatch planner
→ show the spec and wait for approval → implement → review loop → test →
report and ask before merging), read
`templates/claude/commands/feature.md.tmpl` end to end. Its file format
(Claude Code's slash-command frontmatter) won't apply to you, but the
sequence and the stop-and-ask list in it are tool-agnostic — that's the
part to actually adopt.

For a given worker role's exact prose (its hard rules, working rhythm,
report format), read the closest existing template as a **style
reference**, not a copy target:

- `templates/claude/agents/planner.md.tmpl` — planner
- `templates/claude/agents/senior-dev.md.tmpl` or
  `templates/opencode/agent/builder.md.tmpl` — implementer
- `templates/opencode/agent/reviewer.md.tmpl` — reviewer
- `templates/opencode/agent/tester.md.tmpl` — tester

Adapt each to what your own tool can actually enforce or actually do —
research your tool's real config and capability surface first (don't
assume it matches what's already here), then write the role's content
accordingly. `docs/ADDING-A-TOOL.md` is the full recipe for that step:
recreate the behavior, don't paste the file.

## If you're scaffolding into a fresh repo, not just orienting yourself

`bin/init.sh` renders the Claude and OpenCode templates into a target repo
mechanically (see README's "Quick start"). Use it if your tool is one of
those two; otherwise this file plus `docs/ADDING-A-TOOL.md` is the path —
there's no flag for "generate my tool's shim," it's a research step
followed by a small, real file, same as every tool that's here today
started out.
