---
name: self-improvement
description: Optional, off by default. Captures corrections and confirmed lessons from a lead session into the project's own durable instructions (feature.md, a role file, or a doc via the existing Findings-for-docs path) so future runs don't need the same correction twice. Lead-only — never loaded by a dispatched role. See README's "Optional: the self-improvement skill" for how to enable it.
---

# Self-improvement (optional)

**Off by default.** Nothing in this toolkit loads this skill automatically
— not `feature.md`, not `init.sh`. You enable it deliberately, the same way
you'd add `delegate` or `karpathy-guidelines` to `feature.md`'s own
load-these-skills line. See README's "Optional: the self-improvement skill"
for the exact steps.

**Lead-only, always.** Never wire this into `senior-dev.md`, `builder.md`,
`reviewer.md`, or `tester.md`. A dispatched role editing its own rules — or
another role's — based on its own read of "what went wrong" is exactly the
failure mode this toolkit's other rules exist to prevent (no role but the
lead writes to `docs/`, and even the lead only does it mechanically via
`promote-findings.sh`). This skill is the one deliberate, narrow exception:
the **lead's own orchestration instructions**, edited by the **lead**, in
response to something a **human** said.

## What it watches for

Exactly the two signals a human gives naturally in conversation, during a
lead session:

1. **A correction.** The user says some version of "no, don't do that" /
   "that's not what I meant" / "stop doing X" about how you ran the
   pipeline itself — not about the code a role wrote, that's the
   reviewer's job.
2. **A confirmed judgment call.** The user accepts an unusual choice
   without pushback, or says some version of "yes, exactly, keep doing
   that" about a non-obvious approach you took.

Not every correction qualifies. Only write something down if it would
recur on a *future, different* task — a one-off preference about this
specific feature is not a standing rule.

## What to do about it

1. **Say where it belongs, out loud, before writing anything:**
   - About how the lead orchestrates (dispatch order, when to stop and
     ask, session policy) → `.claude/commands/feature.md`.
   - About how a specific role behaves → that role's own file.
   - About a durable fact about the project (a platform gotcha, a
     constraint, an incident) that isn't about *how the pipeline runs* →
     not this skill's job — that's exactly what *Findings for docs* +
     `scripts/promote-findings.sh` already exist for. Use that path,
     don't invent a second one.
2. **Make the smallest edit that captures it** — a sentence or a bullet,
   not a rewrite. State the *why*, the same way this toolkit's own
   Decisions log convention requires elsewhere: what happened, what the
   user said, why it generalizes.
3. **Say what you changed, in your normal report to the user** — don't
   bury it. A silent edit to your own instructions is the one thing this
   skill must never do; the user should see it the same turn it happens.

## Guardrails

- **Bias toward recording constraints, never toward loosening them.** If
  you notice a rule is inconvenient, that is not evidence the rule is
  wrong. This skill exists to make the lead more constrained by real
  feedback over time, not less.
- **Never touch acceptance criteria, source code, or a role's hard
  permission boundaries** (a `tools:` list, a `permission:` block) — those
  aren't yours to edit under this skill, full stop.
- **One edit per correction, not a cascade.** Don't use a single piece of
  feedback to justify rewriting an adjacent section "while you're in
  there" — that's scope creep with extra steps.
- **If you're unsure whether something generalizes, ask, don't guess.**
  Write it as a question to the user rather than silently deciding it's
  durable.
