# Review of agent-toolkit

Two reviews live in this file:

- **Part 1** — code/tooling review (first pass), with `[DONE]` marks on
  everything applied in the fix pass and `[OPEN]` on what deliberately
  remains.
- **Part 2** — second pass from an organizational lens (agent-generator
  expert + tech-team-manager view of the five-role team as a team): role
  harmony, authority boundaries, feedback loops, failure budgets. Marked
  `[REC]` until you decide.

A **third pass** — delivery guarantees, the acceptance-criteria contract,
the status state machine, and the missing team-charter layer — lives in
[`REVIEW-2.md`](REVIEW-2.md). It does not repeat anything here; where it
touches a finding below it re-ranks it by id and says so, and its Part D
is direct feedback on this file (what to act on, what to neglect).

Legend, marked at the start of every heading so a human can scan status
without reading prose:

| Mark | Meaning |
| --- | --- |
| ✅ | `[DONE]` — applied and smoke-covered |
| ✅⬜ | applied, with one step still owed |
| ⬜ | `[OPEN]` — remains, by design or by choice |
| 🔶 | `[REC]` — recommendation awaiting your call |

**Where this file stands:** 15 ✅ done · 1 ✅⬜ done-with-a-step-owed ·
4 ⬜ open by choice · 5 🔶 awaiting your decision. Everything in Part 1
except §3.3 and the two editorial calls in §4 is closed; the live backlog
is Part 2's O1–O4, O7 and the owed live verification in §1.3.

---

# Part 1 — code & tooling review

Reviewed: full read of every file (`bin/init.sh`, all 12 templates, all 7
skills, `SYSTEM.md`, all 4 docs), plus live verification: smoke run into
a throwaway dir (zero leftover `__PLACEHOLDER__` tokens), second-run skip
behavior, `verify-state.sh` regex behavior, and a path-traversal probe
against `promote-findings.sh` logic.

## Verdict

This is a genuinely good toolkit with unusually honest documentation. The
core ideas are sound and earned, not invented: receipt-not-record, the
state file as single handoff surface, verification-as-script-not-agent,
skip-if-exists scaffolding, `--update` diff mode, blanket-deny reviewer
with an inline live-verification recipe, and the discipline of writing
down *why* every hardening rule exists (lessons-learned, design-decisions
sections). The smoke run passes exactly as documented. Most repos claim
these virtues; this one has them.

The problems were never conceptual. They were: one real injection bug,
one self-inflicted config inconsistency, sync debt that had already
produced its first divergence, and hygiene gaps (license, tests, stale
docs, machine-specific paths) — all fixed below.

## 1. Fix first (real bugs / risks)

### ✅ 1.1 [DONE] `promote-findings.sh`: agent-authored content escaped the repo

The doc path extracted from state-file lines written by *an agent* was
used unchecked (`- [../../escaped.md] …` wrote outside the repo). Fixed:
absolute paths and any `..` segment refused with a loud skip; script now
anchors itself to the repo root like its siblings. Smoke-tested.

### ✅ 1.2 [DONE] Preflight contradicted the port mechanism it ships

`feature.md.tmpl` hardcoded `curl localhost:4096` while `team.sh --port
4097` + `.agents/.oc-port` was a supported setup — preflight reported
"server down" on a running server. Fixed: resolves `OC_SERVER` →
`.agents/.oc-port` → 4096, same order as `oc.sh`.

### ✅⬜ 1.3 [DONE, one step owed] builder blanket `"git *": allow`

Removed; replaced with enumerated read-only allows (`status/diff/log/
show`); explicit denies kept because `--auto` bypasses `ask` but honors
`deny`. Also fixed the rhythm step that told builder to "implement in
commits" while its own hard rule forbade committing. The owed step,
per this toolkit's own rules: **[OPEN]** dispatch builder against a real
OpenCode server once, make it try `git commit`, confirm refusal names the
deny rule, annotate the block with the result.

### ✅ 1.4 [DONE] "Zero dependencies" overclaim

README now scopes bash+sed-only to the scaffolder and lists what the
generated runtime scripts actually need (python3, curl, coreutils
timeout, tmux). A python3-free replacement for `oc.sh --text` remains
possible but is not worth fragility — **[OPEN]** by choice.

## 2. Sync debt

### ✅ 2.1 [DONE] Lesson #5 lived in 2 of 3 flow copies

Non-actionable-findings routing existed in `flow-example.md` +
`lessons-learned.md` but not in the canonical `feature.md.tmpl` nor
`SYSTEM.md`. Ported to both. CLAUDE.md Conventions now names the three
hand-synced files explicitly so the next divergence gets caught.

### ✅ 2.2 [DONE] Stale CLAUDE.md

Skills list completed (all six), status section rewritten, origin-project
references generalized.

### ✅ 2.3 [DONE] Machine-specific paths

`~/PWS/agent-toolkit` → `/path/to/agent-toolkit` everywhere user-facing.

### ✅ 2.4 [DONE] Stray README links

mcpmarket link and unexplained "Other Skills" section removed.

## 3. Hygiene gaps

### ✅ 3.1 [DONE] LICENSE added (MIT)

Matches karpathy-guidelines' existing `license: MIT` claim.

### ✅ 3.2 [DONE] Automated smoke run + CI

`test/smoke.sh`: 10 checks — placeholder substitution, write/skip pairing,
marker lifecycle, never-clobber with local edits preserved, `--update`
clean + single-drift behavior, self-target guard, `blocked` Status
acceptance, Pass-3 loop-cap failure, findings promotion + traversal
refusal + idempotence. CI runs it plus shellcheck on every push.

### ⬜ 3.3 [OPEN] Shellcheck locally

Wired into CI; not installed on the dev machine — run it before relying
on the CI verdicts.

## 4. Trim/remove decisions

| Item | Status |
| --- | --- |
| ⬜ MODELS.md dated credit/request tables | **[OPEN]** — your call; principles age well, numbers rot |
| ⬜ `team-completion.bash` | **[OPEN]** — kept; weakest artifact, safe to drop |
| ✅ Duplicate Quick-start blocks | **[DONE]** merged into one example |
| ✅ README stray links | **[DONE]** removed |
| ✅ `~/PWS/…` paths | **[DONE]** genericized |

Kept deliberately: SYSTEM.md overlap, duplicated senior-dev/builder prose,
the three mermaid diagrams, reviewer blanket-deny default.

## ✅ 5. Smaller notes — all [DONE]

SED_ARGS dedupe in `render()` · self-target guard · `blocked` Status
(replacing implementer-set `changes-requested`) · repo-root anchoring in
verify-state/promote-findings · marker-based `usage()` in init/oc/team ·
tester npm-install rationale comment · Pass-3 structural check ·
`.gitignore` append-if-missing · lessons-learned #10 (permission-map
precedence) and #11 (untrusted paths from agent-authored content).

---

# Part 2 — second review: the team as an organization

Lens: not code — does this five-role team *work* as a team? Authority,
harmony, incentives, failure handling, memory. Read as an engineering
manager reviewing their own org chart.

## What already works (genuine harmony assets)

- **One ledger.** Every dispute adjudicates on written evidence in the
  state file, so roles can't talk past each other and the lead doesn't
  arbitrate from memory.
- **Disjoint authority map.** Planner owns acceptance criteria, implementer
  owns code decisions, reviewer owns verdicts, tester owns test truth,
  lead owns process + human liaison, user owns approvals and merge. Write
  scopes are disjoint too — role conflict is structurally rare.
- **Anti-thrash policy.** The two-loop cap and stop-and-ask list prevent
  the classic multi-agent death spiral (fix → review → fix → review).
- **Escalation ladder is defined** before the first incident, not during
  one: open questions, disagreements, new permissions, merge — all named
  human-decision points up front.

## Findings

### 🔶 O1 — Independence is asserted more than engineered `[REC]`

Review and test continue the implementer's OpenCode session, so both
inherit its reasoning trace and file-reading history. Family-switching
fixes model bias, not context anchoring — a reviewer that watched the code
get written anchors on the author's framing ("they clearly considered the
error path") instead of the diff alone. The docs treat this as a token-
cost tradeoff and say "measure it," but nothing makes measuring happen.

**Recommendation:** invert the default for high-stakes tasks — forked
session for review/test whenever the diff touches permission blocks,
`render()`, the state-file contract, or anything the project flags as
sensitive; session reuse stays the default for routine diffs. One sentence
in `feature.md` step 3 plus a Decisions-log note when deviating.

### 🔶 O2 — Organizational memory needs two opt-ins to fire `[REC]`

Project facts need the lead to remember `promote-findings.sh`;
orchestration lessons need self-improvement, which is off by default;
delegate/status-board/karpathy need manual loads. A fresh project can
re-run its early mistakes indefinitely.

**Recommendation:** one unconditional end-of-task line in step 5: after
the promote-findings run, ask the user exactly once whether anything about
*how the pipeline ran* should be recorded — and if yes, add a sentence to
`feature.md` themselves (the manual, consented version of self-improvement,
without giving a skill standing edit rights).

### 🔶 O3 — Reviewer workload vs. reviewer model mismatch `[REC]`

The reviewer carries the heaviest cognitive job (two mandatory passes,
severity taxonomy, zero-praise discipline) yet sits on a cost-tiered slot
picked for "one or two calls." On a large diff, systematic under-reviewing
is the predictable result.

**Recommendation:** a size-based bump rule in `feature.md` step 3 — e.g.
diff above ~400 changed lines (or >7 files) dispatches the fallback/
stronger reviewer instead of the default, recorded like the vendor-
substitution note. Cheap, mechanical, closes the gap where it actually
opens.

### 🔶 O4 — Test-failure loops have no budget `[REC]` *(the one real org bug)*

Review loops are capped at two, structurally enforced by `verify-state.sh`
(Pass 3 fails loudly). Test failures route "back to the implementer as a
new loop" — with **no cap, no counter field, and no structural check**.
A flaky suite plus an eager implementer can cycle fix→test indefinitely
and nothing in the system notices, because the only budget in the state
file counts review passes.

**Recommendation:** rename/redefine the field as a shared implementer
re-engagement budget (e.g. `Implementer re-engagements: 0 / 4` counting
review-driven and test-driven returns together, or two separate counters)
and teach `verify-state.sh` the same fail-loudly trick it already does
for Pass 3. Tiny change; restores the anti-thrash guarantee the review
cap already provides.

### ⬜ O5 — Lead is a single point of judgment failure `[OPEN]` (accepted)

Everything escalates to lead + user; there is no peer mechanism. For a
solo-dev toolkit this is correct scope — but say the scaling boundary out
loud somewhere: one task at a time per lead/session, parallel work means
parallel projects (port-per-project already supported), not parallel tasks
inside one pipeline.

### ⬜ O6 — Team onboarding fires once, Claude-only `[OPEN]` (minor)

`.needs-customization` gives the team its project-specific induction
exactly once, via `feature.md` — which only a Claude Code lead executes.
Non-Claude leads get prose in `init.sh` output telling them to do it by
hand. Easy to skip. A line in SYSTEM.md's "become the lead" checklist
("if `.agents/.needs-customization` exists, do the customization pass
first") would close it for free.

### 🔶 O7 — No health metrics anywhere `[REC]` (low priority)

Loops used, wall-clock per phase, retries hit — none of it is rolled up.
You can't manage (or tune model picks for) a team whose only observable
is the final report. Cheapest version: have step 5's report include
"loops used R/T" read from the state file; O4's counter gives it a home.

## Priority for Part 2

1. **O4** — real bug in the org design; small template + verify-state change
2. **O1, O2, O3** — one-to-three-sentence edits to `feature.md`, pending your decision
3. **O6** — one line in SYSTEM.md
4. **O5, O7** — note / optional metric line

---

# Remaining work (both parts)

1. 🔶 `[REC]` Decide O4 (loop budget) — say go and it's a ~20-line change incl. smoke coverage
2. ⬜ `[OPEN]` Live permission verification on a real server (builder denies under `--auto`; reviewer blanket-deny) — manual by design
3. 🔶 `[REC]` O1/O2/O3/O6 wording changes pending approval
4. ⬜ `[OPEN]` MODELS.md trim, team-completion.bash removal — editorial calls

## Then the third pass

`REVIEW-2.md`'s priority list continues this one — its D1/D3 (close the
acceptance-criteria contract), D2 (the status state machine has 8 values
and 3 of them are ever set), and S1 (two live sync divergences, both from
the last two commits) rank **above** O4 in that file's ordering. It also
recommends folding O1 and O3 into a single task-class mechanism, and
neglecting §3.3, §4, O5 and most of O7 outright.
