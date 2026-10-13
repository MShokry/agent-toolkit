#!/usr/bin/env bash
# shellcheck disable=SC2016 # Rule patterns deliberately match literal shell/Markdown text.
#
# Cross-file invariants: does every copy that must carry a load-bearing rule
# still carry it?
#
# This toolkit deliberately keeps several hand-synced surfaces — the lead's
# flow exists three times (the generated slash command, SYSTEM.md for an
# any-tool lead, and the generator skill's flow example), the state-file
# contract twice, and canonical roles with thin native adapters. AGENTS.md's Conventions
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

FEATURE="templates/pipeline/roles/leader.md.tmpl"
SYSTEM="SYSTEM.md"
FLOW="skills/dev-team-generator/reference/flow-example.md"
STATE="templates/agents-state/TEMPLATE.md.tmpl"
STATE_EX="skills/dev-team-generator/reference/state-file-example.md"
PLANNER="templates/pipeline/roles/planner.md.tmpl"
SENIOR="templates/pipeline/roles/implementer.md.tmpl"
BUILDER="$SENIOR"
REVIEWER="templates/pipeline/roles/reviewer.md.tmpl"
TESTER="templates/pipeline/roles/tester.md.tmpl"
OC_DISPATCH="templates/pipeline/adapters/opencode.md.tmpl"
CODEX_DISPATCH="templates/pipeline/adapters/codex.md.tmpl"
LESSONS="skills/dev-team-generator/reference/lessons-learned.md"
CODEX_AGENTS="templates/codex/AGENTS.md.tmpl"
CODEX_FEATURE="templates/codex/skills/feature/SKILL.md.tmpl"
CODEX_PLANNER="templates/codex/agents/planner.toml.tmpl"
CODEX_DEV="templates/codex/agents/codex-dev.toml.tmpl"
CODEX_REVIEWER="templates/codex/agents/reviewer.toml.tmpl"
CODEX_TESTER="templates/codex/agents/tester.toml.tmpl"
OC_LEADER="templates/opencode/agents/leader.md.tmpl"
OC_PLANNER="templates/opencode/agents/planner.md.tmpl"
OC_FEATURE="templates/opencode/commands/feature.md.tmpl"
OC_UPDATE="templates/opencode/commands/toolkit-update.md.tmpl"
HERDR_DOC="integrations/herdr/README.md"

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
rule "timeout guidance never widens permissions automatically" \
  'do not widen permissions or enable --auto automatically after a timeout' \
  "templates/scripts/oc.sh.tmpl"

rule "worker warnings retain unverified live enforcement" \
  'live enforcement is UNVERIFIED' \
  templates/opencode/agent/builder.md.tmpl templates/opencode/agent/reviewer.md.tmpl templates/opencode/agent/tester.md.tmpl

rule "maintainer entry points share one guide" \
  'AGENTS.md' "CLAUDE.md"

rule "pipeline state separate from native discovery" \
  'native discovery directories separate from pipeline' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "directory migrations need an approved move plan at a task boundary" \
  'directory migrations require an approved move plan at a task boundary' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "honor pipeline gitignore when staging" \
  'do not force-add ignored pipeline records or artifacts' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "update adapters preserve native skills during migration" \
  'preserve.*\.agents/skills/|never rename.*\.agents/skills/' \
  "templates/claude/commands/toolkit-update.md.tmpl" \
  "templates/codex/skills/toolkit-update/SKILL.md.tmpl" "$OC_UPDATE"

rule "standing duties: ask once, unblock, never widen mid-task" \
  'removing blockers, not implementing' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "task class proposed by model, tracked with decision source" \
  'class decided by|record \*\*who decided\*\*|who decided.*agent.*human' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "session scope is one task per role" \
  'session scope is one task per role' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "reviewer model changes start fresh" \
  'reviewer model change.*fresh reviewer session|reviewer model.*changes.*fresh reviewer session' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "session receipts are not success evidence" \
  'session receipt.*not.*success' "$FEATURE" "$SYSTEM" "$FLOW"

rule "worker session fields are separate" \
  'Role.*Backend.*Model.*Family.*Session / thread' "$STATE"

rule "native workers are capability gated" \
  'native workers require verified dispatch capability' "$FEATURE" "$SYSTEM" "$FLOW"

rule "Herdr layout never substitutes for dispatch" \
  'Herdr hosting is optional, not worker dispatch' "$FEATURE" "$SYSTEM" "$FLOW"

rule "Herdr team launcher does not install plugins" \
  'no tmux, automatic installation' templates/scripts/herdr-team.sh.tmpl

rule "cross-tool review requires consent" \
  'cross-tool Claude review is explicit and consent-gated' "$FEATURE" "$SYSTEM" "$FLOW"

rule "Claude review never bypasses permissions" \
  'permission-mode dontAsk' templates/scripts/claude-review.sh.tmpl

rule "Claude review tools are read search only" \
  'tools Read,Grep,Glob' templates/scripts/claude-review.sh.tmpl

rule "Codex lead uses exact resume" \
  'codex resume --no-daemon "\$ID"' templates/scripts/codex-lead.sh.tmpl

rule "Codex launch does not use latest session" \
  '.agent-pipeline/bin/codex-lead.sh \$SESSION' templates/scripts/team.sh.tmpl

rule "native threads are recorded separately" \
  'planner.*implementer.*reviewer.*tester' \
  "$STATE" "$STATE_EX"

rule "native implementation never becomes the default" \
  'builder.*remains the default implementer' "$CODEX_FEATURE"

rule "native review is read only" \
  'sandbox_mode = "read-only"' "$CODEX_REVIEWER"

rule "native implementation delegates to the implementer contract" \
  '\.agent-pipeline/roles/implementer\.md' "$CODEX_DEV"

rule "native tester scope is not filesystem isolation" \
  'workspace-write does not enforce.*narrow path scope' "$CODEX_TESTER"

rule "different harnesses do not mean independent weights" \
  'two OpenAI-family models are not independent review|two OpenAI-family models independent' \
  "$SYSTEM" "$FLOW" "$CODEX_DISPATCH"

rule "model resolution preflight runs before planning" \
  'verify configured worker model ids before planning' "$FEATURE" "$SYSTEM" "$FLOW"

rule "background fallback uses real exit status" \
  'actual (wrapper )?exit status' "$FEATURE" "$SYSTEM" "$FLOW"

rule "background fallback never implies task acceptance" \
  'not task acceptance|does not replace review/test evidence or task acceptance' \
  "$FEATURE" "$SYSTEM" "$FLOW"

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

rule "branch on the reviewer's machine-readable verdict line" \
  'branch on that line' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "only the lead commits, tagged with the task id" \
  'tag the commit with the task id' \
  "$FEATURE" "$SYSTEM" "$FLOW"

rule "check the spec with a script before approval" \
  'verify-spec|check the spec with a script|spec.{0,40}structural check' \
  "$FEATURE" "$SYSTEM" "$FLOW" "$PLANNER"

# --- Codex lead adapter -----------------------------------------------------
rule "task-scoped prompt and log directories" \
  '\.agent-pipeline/prompts/T-<id>.*\.agent-pipeline/logs/T-<id>' \
  "$FEATURE" "$SYSTEM" "$FLOW" "$OC_DISPATCH"
rule "prior pass artifacts survive retries" \
  'never overwrite a prior( >)? pass artifact' \
  "$FEATURE" "$SYSTEM" "$FLOW" "$STATE" "$STATE_EX" "$BUILDER" "$LESSONS"
rule "active artifacts cannot move" \
  'never move an artifact while its associated.*run is active' \
  "$FEATURE" "$SYSTEM" "$FLOW" "$STATE" "$STATE_EX"
rule "state file links artifacts and names current patch" \
  'current patch.*review' "$STATE" "$STATE_EX" "$REVIEWER"
rule "dashboard shows task state only" \
  'dashboard shows task state/status only' "$FEATURE" "$SYSTEM" "$FLOW"

rule "Codex feature skill delegates to the canonical lead flow" \
  '\.agent-pipeline/roles/leader\.md' \
  "$CODEX_FEATURE"

rule "Codex project instructions route feature work through the skill" \
  'invoke the `feature` skill' \
  "$CODEX_AGENTS"

rule "Codex planner discloses its non-enforced source-write boundary" \
  'cannot enforce a narrower path-only write scope.*never modify source' \
  "$CODEX_PLANNER"

rule "Codex planner delegates to the canonical planner contract" \
  '\.agent-pipeline/roles/planner\.md' \
  "$CODEX_PLANNER"

# --- the delivery contract --------------------------------------------------
rule "Herdr adoption does not prompt or relaunch an existing lead" \
  'sends \*\*no prompt\*\*.*launches \*\*no process\*\*' "$HERDR_DOC"
rule "Herdr lifecycle completion is not task acceptance" \
  'Herdr done/idle is not task acceptance' "$HERDR_DOC"
rule "Herdr bindings never guess the newest worker session" \
  'never.*choose the newest worker' "$HERDR_DOC"
rule "Herdr role briefing does not activate runtime permissions" \
  'not an OpenCode profile switch' "$HERDR_DOC"

# OpenCode-only adapters reference policy rather than becoming new flow copies.
rule "OpenCode leader and command reference the canonical flow" \
  '\.agent-pipeline/roles/leader\.md' "$OC_LEADER" "$OC_FEATURE"
rule "OpenCode planner references the canonical planner contract" \
  '\.agent-pipeline/roles/planner\.md' "$OC_PLANNER"
rule "OpenCode update references canonical reconciliation gates" \
  '\.agent-pipeline/update\.md' "$OC_LEADER" "$OC_UPDATE"
rule "OpenCode commands select the lead in the current session" \
  'agent: leader subagent: false' "$OC_FEATURE" "$OC_UPDATE"
rule "OpenCode adapters require live permission verification" \
  'verify.*permissions.*live' "$OC_LEADER" "$OC_PLANNER"
rule "OpenCode planner cannot record AC outcomes" \
  'never tick' "$OC_PLANNER"
rule "OpenCode leader does not implement source" \
  'never implement feature code' "$OC_LEADER"
rule "OpenCode lead resume never selects an arbitrary worker" \
  'never resume the lead with the newest worker session' "$OC_LEADER"

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
  'reviewer for this task|Role assignments' \
  "$STATE" "$STATE_EX"

rule "worker routing excludes the leader workflow" \
  'Explicit worker assignment takes precedence' "$CODEX_AGENTS"
rule "lead alone owns counters" \
  'lead.*owns.*(loop )?counters|lead alone owns.*counters' "$SENIOR" "$SYSTEM" "$FLOW"
rule "lead increments spec bounces at routing" \
  'lead increments Spec bounces when routing' "$FEATURE"
rule "entrypoints reference the compact leader contract" \
  '\.agent-pipeline/roles/leader\.md' templates/claude/commands/feature.md.tmpl "$CODEX_FEATURE" "$OC_FEATURE"
rule "native reviewers reference only the neutral review contract" \
  '\.agent-pipeline/roles/reviewer\.md' templates/claude/agents/reviewer.md.tmpl "$CODEX_REVIEWER"
rule "retry notification is not standing approval" \
  'retry.*explicit authorization|retries require explicit approval' "$FEATURE" "$SYSTEM" "$FLOW"
rule "portable guide does not become worker context" \
  'Keep this guide out of worker prompts' templates/pipeline/README.md.tmpl
rule "portable guide is not a capability grant" \
  'Sharing a file grants no repository access' templates/pipeline/README.md.tmpl
rule "portable guide embeds one canonical leader source" \
  '__LEADER_CONTRACT__' templates/pipeline/README.md.tmpl bin/init.sh
rule "major task paths live under tasks" \
  '\.agent-pipeline/tasks/T-<id>' "$FEATURE" "$PLANNER" "$CODEX_REVIEWER"
rule "tester cannot edit executable core" \
  '\.agent-pipeline/tasks/T-\*\.md' templates/opencode/agent/tester.md.tmpl
rule "new tasks do not invent class attribution" \
  'Class decided by:\*\* pending' "$STATE"
rule "disabled reviewer fallback is not dispatched" \
  'fallback.*none' templates/pipeline/roles/leader.md.tmpl SYSTEM.md skills/dev-team-generator/reference/flow-example.md
rule "upgrade stamp keeps project extensions" \
  'project extension' bin/init.sh migrations/04-team-upgrade.md
rule "migration plans expose retained artifacts" \
  'attention' bin/migrate-layout.py migrations/04-team-upgrade.md
rule "major upgrade is digest approved" \
  '\-\-approve.*\-\-workers-inactive|workers-inactive.*approve' bin/migrate-layout.py

if [ "$FAIL" -eq 0 ]; then
  printf 'invariants: all %s (rule, file) pairs present\n' "$CHECKS"
else
  printf '\ninvariants: FAILED — a rule is missing from a copy that must carry it.\nAdd it there, or if it genuinely does not apply, remove that file from the rule in %s.\n' "test/invariants.sh" >&2
fi
exit "$FAIL"
