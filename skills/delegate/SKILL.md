---
name: delegate
description: Context-discipline rules for a lead/orchestrator agent running a multi-agent pipeline. Load this before dispatching planner/implementer/reviewer/tester subagents or shelling out to a cross-vendor CLI, so the lead's own context stays small across a long-running feature.
---

# Delegate

You are acting as the **lead** of a multi-agent pipeline (see
`.claude/commands/feature.md` if this project has one). This skill is not a
workflow — it is the discipline that keeps *your own* context small while
that workflow runs, since there is no way to invoke `/compact`
programmatically from inside the loop.

## The one rule

**Everything a delegate produces lands on disk, not in your context.** A
subagent's chat reply is a receipt, not the record. The record is the file
it wrote — a state file (`.agents/T-<id>.md`), a diff, a test report. Read
the file to verify placement and content; do not ask the delegate to repeat
itself into the conversation, and do not re-paste what is already on disk.

**Prefer a script to a delegate for anything the script can decide.** When a
role's output has been read into your context once, verifying that a *later*
role's output is structurally sound (right heading, no duplicate section, no
unfilled placeholder) is a job for a few lines of grep/awk, not for another
subagent. Adding an agent to check an agent costs a paid call on every run
and adds a component that can misjudge the same way the one it's checking
can — a script that only asserts structure cannot hallucinate a pass. Reach
for a script first; reach for a human (the user) when the question needs
judgment a script can't encode; reach for another delegate only when the
work itself — not the checking of it — genuinely needs a different role or
vendor.

**Read the one-line handoff, not the whole file, between steps.** If the
project's state-file template has a `Latest handoff` field, that's what each
role updates when it finishes and what you read to decide what's next. Open
the full file only when that line, a verification script, or a real decision
point says something needs a look.

## Before you delegate

- **Is this actually a delegation, or could you just do it?** A single
  grep, a one-file read, a `git status` — do it yourself. Spawning a
  subagent for something you could resolve in one tool call is the most
  common way context discipline gets undermined: the dispatch-and-wait
  overhead costs more than the work saved.
- **Does the delegate have everything it needs *in the request or on
  disk*?** If the answer depends on something you know from earlier in
  this conversation that isn't written down anywhere the delegate can
  read, write it down first — into the state file, a scratch file, or the
  prompt itself. A delegate that has to guess will guess wrong in a way
  that costs a full loop to discover.
- **Is the role's write scope actually scoped?** A read-only reviewer that
  can edit its own verdict file is fine; a reviewer with unrestricted
  write access to the repo is a second author, not a second eye. Prefer
  the narrowest permission that lets the role do its one job — and verify
  that permission is actually enforced by the runtime before trusting it
  as a guarantee, not just readable-correct in the config file.

## Simple + recurring → tool it, don't repeat it

The point of this skill is to keep your own context free for judgment,
not to make you do simple things yourself instead of delegating them. A
simple task has three different right homes depending on whether it
recurs:

- **Simple and one-off** — do it yourself in one tool call. Dispatching a
  subagent for a single grep costs more (a full dispatch-and-wait cycle)
  than it saves.
- **Simple and mechanical, and you've now done it more than once** — stop
  and write a script under `scripts/`. A structural check, a copy, a
  format conversion: none of that needs judgment, so it never needed an
  LLM call in the first place. `scripts/verify-state.sh`,
  `scripts/verify-spec.sh` and `scripts/promote-findings.sh` exist because
  the same "did this land in the right place", "is this spec actually
  finished" and "does this belong in a doc" questions were being re-answered
  by hand every task; now they're free and can't misjudge.
- **Needs judgment, but the same judgment every time** — write it up as a
  Skill instead of re-deriving the reasoning in every session. If you find
  yourself re-explaining the same rule to yourself or a delegate for the
  second time, that explanation belongs in a file, not in this
  conversation's context.
- **Genuinely one-off and needs real judgment or a different vendor** —
  that's what a delegate dispatch is actually for.

Recognizing which bucket you're in is itself part of managing sessions
cheaply: a lead that keeps re-solving the same simple thing inline is
spending context the same way a lead that over-delegates trivial work is
spending calls.

## Anti-patterns to catch, in yourself and in delegates

- **Circular delegation.** A dispatches B, B decides it needs A's judgment
  and reports back a question instead of an answer, A dispatches B again
  with the same question restated. Break the loop by answering from the
  record (spec, docs, prior decisions) or by escalating to the human —
  never by re-dispatching the same ambiguity hoping for a different guess.
- **Context loss across a handoff.** If a fact mattered enough to change
  what you did, it belongs in the state file's Decisions log, not just in
  this conversation. The next role — and the next you, after a
  compaction — only has the file.
- **Silent scope creep.** A delegate that touches a file outside its
  stated scope, or a permission that got widened to work around an
  enforcement failure instead of fixing the failure, is a finding, not a
  shrug. Log it, don't normalize it.
- **Retrying into a collision.** A slow or timed-out call is not evidence
  the work needs to be resent — the underlying job may still be running.
  Check before you resend into the same session/target; a second
  concurrent call racing the first is a more common cause of failure than
  the original slowness.

## What to actually read

- Read a delegate's **raw event stream** only to diagnose a stalled or
  misbehaving run — it inlines the full contents of every file the
  delegate touched and is the single biggest source of avoidable context
  growth. Prefer a `--text`/summary-only output for the normal path.
- Don't re-read a file already read this session unless it may have
  changed.
- Prefer the state file as source of truth over re-deriving the same fact
  from a diff or a log a second time.

## When you're the one who should stop and ask the human

- A delegate escalates an open question the record doesn't settle.
- Two delegates disagree and the written evidence doesn't resolve it —
  arbitrate on the evidence, don't cast a tiebreak vote from your own
  opinion.
- A permission, dependency, or irreversible action wasn't in the original
  scope.
