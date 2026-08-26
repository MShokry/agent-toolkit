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

**Nobody may declare their own work done — and someone must declare it.**
The acceptance criteria are the contract; a criterion nobody records an
outcome for means the pipeline stopped one step short of saying what it
delivered. Keep a **ledger** in the state file: one row per criterion, with
the reviewer's citation (`file:line`) and the tester's (which test) in
separate columns. Rules that make it worth having:

- Only the **lead** fills it, at the report step. The planner owns the
  criteria's *text* and may not record outcomes; the implementer may never
  mark its own work met; the reviewer and tester supply evidence, not
  verdicts on the contract.
- A criterion is met **only when both evidence cells are filled.** No
  evidence, no tick — "unverified" is a true and useful answer, and hiding
  it behind a tick is exactly what this prevents.
- A structural check should refuse a `done` status while any criterion is
  unticked and unwaived. That is the difference between a pipeline that
  produces work and one that can tell you what it produced.

**Every status has exactly one owner.** Write down which role sets each
value of your status field and on what event, or the field silently rots:
this toolkit shipped eight statuses of which only three were ever set by
anyone — including `done`, which nothing set, while the status-board rule
keyed off exactly that value. A status nobody owns is a status that lies,
and everything downstream that reads it inherits the lie.

**Verification is a script, not a sixth agent.** Checking whether a
verdict landed in the right heading, or whether a finding needs promoting
to project docs, needs no judgment — `templates/scripts/verify-state.sh.tmpl`
and `templates/scripts/promote-findings.sh.tmpl` do it deterministically,
for free, and can't hallucinate a pass. The same applies *before*
implementation: most spec defects are structural (an empty scope table, a
criterion that names a quality instead of an observable, boilerplate left
in), so check the spec with a script too — see
`templates/scripts/verify-spec.sh.tmpl`. Code gets two review passes; the
spec every role treats as the contract should not get zero.

Dispatching another agent to check an agent's structural output is a paid
call that adds a component that can misjudge the same way the one it's
checking can. Prefer the script.

**Permission is least-privilege per role, verified live, not assumed.**
Whatever your tool's capability model actually is, give the reviewer
nothing beyond read + (optionally) writing its own verdict; give the
tester write access to its own test directory and the state file only, not
source. If your tool's model is coarser than that (all-or-nothing, like
Codex's sandbox), say so explicitly in the role's own instructions rather
than implying a scoping guarantee that isn't real — don't trust a
permission block just because it reads correctly; dispatch it once and try
to make it do the disallowed thing before relying on it.

**Ask before running a very large task as one task.** Many files or
subsystems touched, several unrelated acceptance criteria → ask the human
whether to split it into smaller tasks run through this pipeline one at a
time, or proceed as one. Judge by scope breadth, not effort. The human
decides; you size it. A large task run unsplit compounds two risks at once —
a wide, hard-to-review diff, and (if any implementer has a wide
auto-approve flag) unattended permission approval across all of it.

**Loop discipline:** max two review loops on CHANGES_REQUESTED; a third
means the spec was wrong, not the code — stop and ask the human. **Every
other way the implementer gets re-engaged is budgeted too** — test-fix loops
(cap 2) and spec bounces (cap 1) — and all three counters live in the state
file where a script can check them. A budget with no counter is not a
budget: before this toolkit added the test-fix counter, a flaky suite plus
an eager implementer could cycle fix→test forever, because the only budget
in the file counted review passes.

**A second review pass closes the first, it does not restart it:** every
earlier finding marked fixed, withdrawn, disputed (answering the author's
written reason) or routed to test, and a finding about code the diff did
not change is admissible on a later pass only at the top two severities.
Without that, a loop cap stops being a convergence guarantee and becomes an
arbitrary cutoff. For the same reason the reviewer must read the author's
decisions/reasoning log, not only the diff — otherwise written disagreement
has no reader and the record of it is theatre.

**Independence of *evidence*, not only of opinion.** Switching the
reviewer's model family buys you an independent opinion. It buys nothing
about the tests: if the implementer wrote them, a green run confirms the
code matches its author's own idea of correct. Require the tester to read
the acceptance criteria, to record its acceptance-criteria coverage (each
criterion and the covering test), to name every criterion **no** test
covers, and to record who authored the tests it ran. A suite that exercises none of the criteria is not evidence,
and a reader cannot tell unless the file says so.

A
CHANGES_REQUESTED whose findings name no concrete code defect is not a
loop at all: route it to the test/verification step as an explicit thing
to check, logged in the state file so the human can see and disagree —
never silently downgraded. Never merge without asking. Any new permission
or dependency, however reasonable it looks, gets asked about too.

**Keep the project's main tracking doc current, always, not only at
completion.** A status board / task list / equivalent, updated at the end
of every step for every task whose status changed, not only when one
finishes — otherwise it drifts out of sync with in-review/testing work for
however long that takes, which defeats the point of having it. This is a
standing rule for you as lead, not something conditional on a specific
skill or file existing — if the project has no tracking doc yet, that's a
gap to raise with the human, not a reason to skip this.

**Assess whether a task needs the planner — completeness of an existing
spec is the test, not size.** Not yet planned or genuinely ambiguous about
scope → dispatch the planner. Already fully documented somewhere (a prior
state file, an existing plan, or a request specific enough to state
Goal/acceptance-criteria/files-in-scope yourself with no invention) → skip
the planner and go straight to implementation, however large the task is.
Not sure which → ask the human rather than guessing either way.

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

0. **First, check whether this project was just scaffolded.** If a
   first-run customization marker exists (this toolkit writes
   `.agents/.needs-customization`), the role files still carry generic
   pitfalls/hard-rules text rather than this codebase's real ones — do that
   customization pass with the human before running anything, then delete
   the marker. It is written once, on a fresh scaffold only, and the check
   otherwise lives in a Claude-Code-specific command file that you, as a
   different lead, will never execute.
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
