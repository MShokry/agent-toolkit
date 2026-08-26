#!/usr/bin/env bash
#
# Cross-file invariants: does every copy that must carry a load-bearing rule
# still carry it?
#
# This toolkit deliberately keeps several hand-synced surfaces — the lead's
# flow exists three times (the generated slash command, SYSTEM.md for an
# any-tool lead, and the generator skill's flow example), the state-file
# contract twice, and the role prose once per tool. CLAUDE.md's Conventions
# say to re-diff them by hand after any pipeline change. That instruction is
# correct and it does not work: it depends on the author remembering a
# five-bullet rule at exactly the moment they are focused on something else.
# Two rules went missing on two consecutive commits before this test existed
# (a "split a very large task" rule that reached only 2 of 3 flow copies, and
# state-file fields that reached only 1 of 2 template copies).
#
# So this checks *presence*, not text equality. It cannot catch wording
# drift, and does not try to — the failure mode that actually happens is
# omission: a rule added to one copy and forgotten in the others. One grep
# per (rule, file) pair, no LLM call, and adding a rule costs one line in
# the table below.
#
# Usage: bash test/invariants.sh
# Exit 0 = every rule present everywhere it must be.
# Exit 1 = the missing (rule, file) pairs, one per line.

set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FEATURE="templates/claude/commands/feature.md.tmpl"
SYSTEM="SYSTEM.md"
FLOW="skills/dev-team-generator/reference/flow-example.md"
STATE="templates/agents-state/TEMPLATE.md.tmpl"
STATE_EX="skills/dev-team-generator/reference/state-file-example.md"
PLANNER="templates/claude/agents/planner.md.tmpl"
SENIOR="templates/claude/agents/senior-dev.md.tmpl"
BUILDER="templates/opencode/agent/builder.md.tmpl"
REVIEWER="templates/opencode/agent/reviewer.md.tmpl"
TESTER="templates/opencode/agent/tester.md.tmpl"
LESSONS="skills/dev-team-generator/reference/lessons-learned.md"

FAIL=0
CHECKS=0

# rule <id> <extended-regex> <file>...
rule() {
  id="$1"; pattern="$2"; shift 2
  for f in "$@"; do
    CHECKS=$((CHECKS + 1))
    if [ ! -f "$f" ]; then
      printf 'invariants: MISSING FILE %s (rule: %s)\n' "$f" "$id" >&2
      FAIL=1
    # Match against the file with newlines flattened: these rules are prose
    # that wraps, so a phrase can legitimately span a line break. Presence in
    # the document is the question, not presence on one line.
    elif ! tr '\n' ' ' < "$f" | tr -s ' ' | grep -qiE "$pattern"; then
      printf 'invariants: %s does not carry rule "%s"\n' "$f" "$id" >&2
      FAIL=1
    fi
  done
}

# --- the three hand-synced copies of the lead's flow ------------------------
rule "ask before splitting a very large task" \
  'split it into smaller tasks|split into smaller tasks' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "two-loop review cap" \
  'maximum two loops|two failed loops|max two review loops|two review loops' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "never merge without asking" \
  'never merge' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "non-actionable findings are routed, not looped" \
  'no concrete code defect|names no actionable code change|no code change could address' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "check the spec with a script before approval" \
  'verify-spec|check the spec with a script|spec.{0,40}structural check' \
  "$FEATURE" "$SYSTEM" "$FLOW" "$PLANNER"

# --- the delivery contract --------------------------------------------------
rule "acceptance-criteria ledger closes the contract" \
  'ledger' \
  "$FEATURE" "$SYSTEM" "$FLOW" "$STATE" "$STATE_EX" "$PLANNER" "$SENIOR" "$BUILDER" "$LESSONS"

rule "only the lead records an AC outcome" \
  'never tick|only the lead|lead owns the outcome|lead fills' \
  "$FEATURE" "$STATE" "$STATE_EX" "$PLANNER" "$SENIOR" "$BUILDER"

rule "every status has one owner" \
  'who sets each status|exactly one owner|one setter' \
  "$SYSTEM" "$STATE" "$STATE_EX"

# --- budgets ----------------------------------------------------------------
rule "test-fix loops are budgeted" \
  'test-fix loop' \
  "$FEATURE" "$SYSTEM" "$FLOW" "$STATE" "$STATE_EX" "$SENIOR" "$BUILDER"

rule "spec bounce, capped at one" \
  'spec bounce|blocked:spec|bounced to the planner|bounce' \
  "$FEATURE" "$SYSTEM" "$FLOW" "$STATE" "$STATE_EX" "$SENIOR" "$BUILDER" "$PLANNER"

rule "a blocked task records what it waits on and since when" \
  'blocked since|since when|what it is parked on|parked on' \
  "$FEATURE" "$FLOW" "$STATE" "$STATE_EX" "$SENIOR" "$BUILDER"

# --- review convergence -----------------------------------------------------
rule "a later review pass closes the earlier one by number" \
  'close every|closes the first|closes the earlier|by number' \
  "$SYSTEM" "$FLOW" "$STATE" "$REVIEWER" "$SENIOR" "$BUILDER"

rule "reviewer reads the implementer's stated reasoning" \
  'decisions log|decisions/reasoning log|reasoning log' \
  "$REVIEWER" "$SYSTEM" "$FLOW"

# --- independence of evidence ------------------------------------------------
rule "tester maps criteria to covering tests" \
  'coverage|covering test' \
  "$TESTER" "$SYSTEM" "$FLOW" "$STATE" "$STATE_EX"

rule "test authorship is recorded" \
  'tests authored by|who authored the tests|authorship' \
  "$TESTER" "$SYSTEM" "$FLOW" "$STATE" "$STATE_EX"

# --- state-file fields present in both copies of the contract ---------------
rule "reviewer/tester recorded per task" \
  'reviewer for this task' \
  "$STATE" "$STATE_EX"

if [ "$FAIL" -eq 0 ]; then
  printf 'invariants: all %s (rule, file) pairs present\n' "$CHECKS"
else
  printf '\ninvariants: FAILED — a rule is missing from a copy that must carry it.\nAdd it there, or if it genuinely does not apply, remove that file from the rule in %s.\n' "test/invariants.sh" >&2
fi
exit "$FAIL"
