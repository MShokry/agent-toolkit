# System — read this first, whatever AI or tool you are

One file, meant to be handed to **any** AI coding tool (Claude, Codex,
Gemini, whatever you're running) with an instruction like "recreate this
system, with yourself as the lead." It gives you the *shape* of the whole
pipeline compactly, so you don't pay to read every file in `templates/` up
front — pull in a specific template's full text only once you actually need
that role's exact prose, using the paths cited below.

**Do not copy any template file byte-for-byte assuming it fits your tool.**
Claude Code, Codex, and OpenCode discover custom agent files per-repo, but their
formats and permission models differ in shape, not just detail (a per-command
allow/deny/ask map is not the same kind of thing as one coarse sandbox flag).
Codex project agents live under `.codex/agents/`, project skills under
`.agents/skills/`, and project instructions in `AGENTS.md`. Read
`docs/ADDING-A-TOOL.md` before
assuming a mechanism transfers — check your actual tool's real config and
capability surface first, the same way this toolkit's own worker-role
ports did, and recreate the *behavior*, adapted to what your tool can
actually enforce, rather than pasting a file in and hoping.

## The shape, compactly

**Runtime context is role-scoped.** Canonical contracts live in
`templates/pipeline/roles/`; the generated feature files are thin entrypoints.
Read only your role plus project guidance and required task sections; workers
never activate leader routing. Leaders load only selected backend adapters from
`.agent-pipeline/adapters/`, not every worker contract. Expand evidence/history
when unclear. This document explains the system, not an additional startup prompt.
The lead alone owns all loop counters. Quota retries require explicit approval
and scheduled retries require a real scheduler. No notification implies consent.
See docs/CONTEXT.md for loading boundaries and selective --leader/--extras profiles.
The major layout puts runtime scripts in `.agent-pipeline/bin/` and task records/
template in tasks/. One typed Role assignments table records Backend, Model,
resolved Family and Session / thread for each role; approvals/budgets stay separate.
The lead records immutable first-receipt bindings, and checks them before resume.
Legacy task headers remain readable, but never mix schemas in one task. Class
decided by remains pending until confirmed. Bulk migration requires a reviewed
plan/digest, inactive workers, collision checks and retained backups; native
discovery directories never move. This is one coordinated major upgrade.
Reviewer fallback `none` means disabled; obtain an approved independent assignment
instead of dispatching that sentinel.
Every profile also supplies `.agent-pipeline/README.md` as an opt-in portable
leader orientation. It embeds the canonical leader body plus team details;
workers do not load it and native leads need not read both copies. Sharing the
guide grants no project access, dispatch capability, or approval.
Team activation is opt-in: only an explicit user command or prompt selects the
leader workflow. Generated root AGENTS.md contains project guidance only, with
a CLAUDE.md link when needed; it never routes ordinary work into the pipeline.

**Herdr hosting is optional, not worker dispatch.** `.agent-pipeline/bin/herdr-team.sh`
can discover installed host actions/sessions and preserve the existing lead in
one tab while starting a dashboard and empty support shells in a separate tools
tab. Require explicit server/project/session targets for native read/focus/prompt
controls, never approval keystrokes or broad execution grants. Host idle/done is
not task acceptance; file-based handoffs and all pipeline gates remain unchanged.

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
`.agent-pipeline/tasks/T-<id>.md`, shape at `templates/agents-state/TEMPLATE.md.tmpl` —
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
run. Read-only reviewers return full findings for the lead to persist unchanged;
never weaken the reviewer permission boundary just to shorten its reply.

Keep native discovery directories separate from pipeline state. Gitignore
generated prompts, logs, credentials, and local sessions, not native skills.
Do not force-add ignored pipeline records or artifacts; an entirely local state
directory still supplies on-disk role handoffs.
Directory migrations require an approved move plan at a task boundary, never
during a task; preserve user data, refuse collisions, and reconcile references
and permissions before resuming dispatch.

**Artifact layout:** keep `.agent-pipeline/` root for task state (`T-<id>.md`), shared
guidance/configuration, and toolkit metadata; installed skills stay in their
own subdirectory. Create `.agent-pipeline/prompts/T-<id>/` and `.agent-pipeline/logs/T-<id>/`
before dispatch. Save prompts as `<role>-<pass>.md`, exported transcripts as
`<role>-<pass>.jsonl`, and patches as `<implementer>-<pass>.patch`. Every
`oc.sh` call uses matching `--prompt-file` / `--raw-out` task/role/pass paths.
Use a new unused positive pass number on every attempt, including retries;
this is separate from loop-budget counters. Never overwrite a prior pass
artifact; use no-clobber writes. Link all artifacts in the state file's
*Artifacts* table using state-relative Markdown links, identifying the current
patch for review. Findings and verdicts remain in the state file.
Never move an artifact while its associated run is active. Explicit legacy
migrations stage moves and link updates as one transaction, publish the state
file atomically, and rollback on failure. The dashboard shows task state/status
only, not individual prompt/transcript files; at most one optional Artifacts
link per task.

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

Have the reviewer emit a machine-readable verdict line — `VERDICT: PASS` /
`VERDICT: CHANGES_REQUESTED` as the first line of its reply — and **branch
on that line**, not on its findings prose or the raw event stream. Have the
structural check also fail when a task has reached review with no filled
verdict on record, so a missing or malformed verdict is caught from both
the reply and the file.

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

**Standing duties for you as lead, all run long:** ask every setup
question once, at spec approval; between gates your job is removing
blockers, not implementing; you are the only long-lived session (keep your
context flat — receipt-not-record); never widen scope, permissions, or
auto-approve mid-task; increment every re-engagement budget counter at the
moment you route work back, and treat an exceeded budget as an escalation,
never one more lap.

**Every task gets a class, proposed by the planner:** `routine`,
`standard`, or `sensitive`, judged by scope breadth and blast radius. You
confirm it at spec approval and ask the human only when genuinely torn.
Record **who decided** (`agent` | `human`) next to it — and record, don't
act: a class never changes session policy, permissions, or budgets
mid-task.

**Session scope is one task per role:** same task and same role → same session;
another role or new task → new session. Never share the implementer's
conversation with the reviewer or tester. Record separate role session ids;
each role reads the task record and current patch. Reuse within a role saves
reload cost on reruns. A reviewer model change starts a fresh reviewer session.
A session receipt is not success evidence. After a timeout or killed wrapper,
confirm server-side inactivity before reuse; unknown state is a blocker, not
permission to launch a competing turn. Migrate legacy shared sessions only at
an idle task boundary; never copy one id into all role fields.

**Verify configured worker model ids before planning.** Validate against the
authenticated runtime catalog, not just agreement between files. This toolkit's
`.agent-pipeline/bin/verify-models.sh` checks the stamped OpenCode worker ids with bounded
calls. Unreachable, invalid, or unchecked ids block dispatch; catalog presence
does not prove credentials, quota, or the served model. Reconcile flow/role-file
drift before validating one id and dispatching another.

**Long dispatches need durable completion evidence.** Prefer host background
execution with notifications, and do not poll those calls. Otherwise use
`.agent-pipeline/bin/bg-dispatch.sh start/wait` for OpenCode workers or an equivalent
adapter. Reserve each task/role/pass atomically and save its actual exit status;
a session receipt is not success evidence. Retain output, stderr, and completion
records under the task's logs and link them from Artifacts. Unknown/failed state
blocks replacement until server-side inactivity is confirmed; retries allocate
unused passes. No implicit retry or permission change. Wrapper success is not
task acceptance.

**Cross-tool Claude review is explicit and consent-gated.** Configured
`claude/<id>` reviewers use a read/search-only headless wrapper, not OpenCode.
Ask at spec approval and record task consent, account/billing implications, and
manual model/runtime verification when catalog checks report unchecked.
Audit project hooks/settings: tool restrictions do not disable hook commands.
Save immutable prompt/transcript passes and a separate Claude reviewer session id;
reuse only for this task/model, never a lead or implementer session. The lead
records full findings unchanged and verifies state. Errors or missing verdicts
are failed dispatches, not PASS. Model-maker independence still applies.
Only unchecked Claude reviewer assignments may proceed after explicit human
confirmation of the exact runtime/model; other unchecked or invalid ids block.

**Native workers require verified dispatch capability.** Optional Codex
implementer/reviewer/tester agents do not replace the default OpenCode workers.
Codex implementation is an explicit spec-gate choice; record its actual model
family. A native model alias is not an OpenCode provider id. Other leaders must
report an unavailable native dispatcher and obtain an approved alternative,
not silently substitute a model/tool or implement in the lead thread.
Native thread ids are recorded separately by role, never as OpenCode session ids.
Use file-based prompts with unused artifact passes; if transcript export is
unavailable, record it and the thread id rather than fabricating evidence.
A read-only native reviewer returns full findings for the lead to record unchanged;
a native tester's workspace-write scope is an instruction boundary, not narrow
filesystem enforcement. OpenCode auto-mode never grants native escalation.
Two OpenAI-family models are not independent review even in different harnesses;
use the approved different-family reviewer or stop if identity is unknown.

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

**Only the lead commits, and only once the user has approved the merge** —
every implementer's write scope hard-denies `git commit`/`git push` so this
stays the one git-mutating action in the whole pipeline, gated on a human
yes. When you do, stage the state file alongside the code (so the commit
carries the spec, decisions, findings, and test results together, not
scattered across an un-versioned file) and **tag the commit with the task
id** — `[T-<id>]` leading the subject line, or appended if the project's
own commit convention already owns that position. It has to be in the
one-line subject, not just the body, so `git log --oneline` / `git blame`
show it and a later `git log --grep` finds every commit for a task from
whatever incident sends someone looking.

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
   `.agent-pipeline/.needs-customization`), the role files still carry generic
   pitfalls/hard-rules text rather than this codebase's real ones — do that
   customization pass with the human before running anything, then delete
   the marker. It is written once; the neutral leader contract owns the check.
1. **A way to read and write `.agent-pipeline/tasks/T-<id>.md`** — any tool with file
   access can do this.
2. **A way to run each worker role** — separate role conversations, never
   feature implementation in the lead thread. Use a native child or a
   wrapper the way `templates/scripts/oc.sh.tmpl` does for OpenCode — a
   thin CLI wrapper that passes a role's instructions and a model choice to
   another agent process and gets its final text back, nothing more exotic
   than that.
3. **The discipline rules above**, actually followed — the short-reply
   convention, the loop cap, the stop-and-ask list.

For the exact orchestration *sequence* (preflight checks → dispatch planner
→ show the spec and wait for approval → implement → review loop → test →
report and ask before merging), read
`templates/pipeline/roles/leader.md.tmpl`. Its sequence and gates are neutral;
dispatch details live in backend adapters, loaded only when needed.

For a given worker role's exact prose (its hard rules, working rhythm,
report format), read the closest existing template as a **style
reference**, not a copy target:

- `templates/pipeline/roles/planner.md.tmpl` — planner
- `templates/pipeline/roles/implementer.md.tmpl` — implementer
- `templates/pipeline/roles/reviewer.md.tmpl` — reviewer
- `templates/pipeline/roles/tester.md.tmpl` — tester

Adapt each to what your own tool can actually enforce or actually do —
research your tool's real config and capability surface first (don't
assume it matches what's already here), then write the role's content
accordingly. `docs/ADDING-A-TOOL.md` is the full recipe for that step:
recreate the behavior, don't paste the file.

## If you're scaffolding into a fresh repo, not just orienting yourself

`bin/init.sh` renders Claude, Codex-lead, and OpenCode templates into a target
repo mechanically (see README's "Quick start"). The Codex adapter consists of
root `AGENTS.md`, a project-scoped planner, and `feature` / `toolkit-update`
skills; it executes the same canonical flow as Claude. For any other tool, this
file plus `docs/ADDING-A-TOOL.md` is the path — there's no flag for "generate my
tool's shim," so research its real discovery and permission surfaces first.
