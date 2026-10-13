#!/usr/bin/env bash
# shellcheck disable=SC2016 # Assertions match literal Markdown/command spellings.
#
# Automated version of the manual smoke run documented in CLAUDE.md's
# "Commands" section. Asserts the scaffolder's core guarantees end to end:
#
#   1. first scaffold writes every file, with no unsubstituted placeholder
#   2. the first-run customization marker is dropped exactly once
#   3. a flag-free second run loads its stamp, skips everything (never
#      clobbers), and does NOT re-drop the marker once deleted
#   3a. a flag-free plain run installs files added by a newer toolkit
#   3a. Codex lead instructions, skills, and planner are scaffolded; team.sh
#       falls back to Codex when Claude is unavailable
#   4. --update against an unchanged target reports every file up to date
#      and writes nothing
#   5. --update against a drifted file reports exactly that one diff
#   6. init.sh refuses to scaffold into its own checkout
#   7. verify-state.sh: valid state file passes; 'blocked' Status is known;
#      a third review pass (loop-cap breach) fails loudly; a blown budget
#      counter fails; 'done' is refused while an acceptance criterion is
#      unticked and unwaived, or while a ticked ledger row cites no
#      evidence; a task past review with no filled verdict fails
#   8. verify-spec.sh: the raw template fails (it is boilerplate), a filled
#      spec passes, and an unmeasurable acceptance criterion is caught
#   9. promote-findings.sh: copies findings into docs, is idempotent, and
#      refuses doc paths that escape the repo
#
# Zero dependencies beyond bash/sed/awk/diff — same stance as init.sh.
# Run directly: bash test/smoke.sh

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/toolkit-smoke.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASSED=0
ok() { PASSED=$((PASSED + 1)); printf 'smoke: ok — %s\n' "$1"; }
fail() { printf 'smoke: FAIL: %s\n' "$1" >&2; exit 1; }

INIT_ARGS=(--target "$TMP" --project-name smoke
  --builder-model a/b --reviewer-model a/c
  --reviewer-fallback-model d/e --tester-model a/b)

# --- 1. first scaffold -----------------------------------------------------
bash "$ROOT/bin/init.sh" "${INIT_ARGS[@]}" > "$TMP/run1.log" 2>&1 \
  || fail "first init.sh run failed"

leftovers="$(grep -rl '__[A-Z_]*__' "$TMP" || true)"
[ -z "$leftovers" ] || fail "unsubstituted placeholders remain in: $leftovers"
ok "no unsubstituted __PLACEHOLDER__ tokens"

wrote="$(grep -c '^init.sh: wrote ' "$TMP/run1.log" || true)"
# Exclude this log and the customization marker; the provenance stamp is
# counted separately since it is written once, not rendered per-template.
stamp_written=0; [ -f "$TMP/.agent-pipeline/.toolkit-version" ] && stamp_written=1
files="$(find "$TMP" -type f -not -name run1.log \
  -not -name .needs-customization -not -name .toolkit-version | wc -l | tr -d ' ')"
[ "$wrote" = "$((files + stamp_written))" ] || fail "claimed $wrote writes but $((files + stamp_written)) files exist"
ok "every reported write produced exactly one file ($files rendered + stamp)"

[ -x "$TMP/.agent-pipeline/bin/dashboard" ] || fail "project dashboard missing or not executable"
cmp -s "$ROOT/integrations/herdr/dashboard.py" "$TMP/.agent-pipeline/bin/dashboard" \
  || fail "project dashboard differs from the shared standalone source"
ok "self-contained executable dashboard was scaffolded"

for codex_file in \
  "$TMP/AGENTS.md" \
  "$TMP/.codex/agents/planner.toml" \
  "$TMP/.agents/skills/feature/SKILL.md" \
  "$TMP/.agents/skills/toolkit-update/SKILL.md"; do
  [ -f "$codex_file" ] || fail "Codex scaffold file missing: $codex_file"
done
grep -q '\.agent-pipeline/roles/leader.md' "$TMP/.agents/skills/feature/SKILL.md" \
  || fail "Codex feature skill does not point at the canonical lead flow"
grep -q 'If required project constraints are missing, ask' "$TMP/AGENTS.md" \
  || fail "generated AGENTS.md masks missing project-specific guidance"
if grep -qiE 'team|leader|feature|agent-pipeline|skills/' "$TMP/AGENTS.md"; then
  fail "generated startup guidance activates or mentions the team"
fi
grep -q 'Codex `planner` subagent' "$TMP/.agents/skills/feature/SKILL.md" \
  || fail "Codex feature skill does not select the Codex planner"
grep -q 'sandbox_mode = "workspace-write"' "$TMP/.codex/agents/planner.toml" \
  || fail "Codex planner lacks the sandbox needed to write its state file"
grep -q 'never modify source' "$TMP/.codex/agents/planner.toml" \
  || fail "Codex planner does not state its source-write boundary"
ok "Codex lead instructions, skills, and planner were scaffolded"

for oc_file in agents/leader.md agents/planner.md commands/feature.md commands/toolkit-update.md; do
  [ -f "$TMP/.opencode/$oc_file" ] || fail "OpenCode lead file missing: $oc_file"
done
grep -q '\.agent-pipeline/roles/planner.md' "$TMP/.opencode/agents/planner.md" \
  || fail "OpenCode planner does not reference its canonical contract"
grep -q '\.agent-pipeline/roles/leader.md' "$TMP/.opencode/agents/leader.md" \
  || fail "OpenCode leader does not reference the canonical flow"
grep -q '^permissions:' "$TMP/.opencode/agents/planner.md" \
  || fail "OpenCode planner does not use native V2 permissions"
grep -q 'resource: ".agent-pipeline/tasks/T-\*.md"' "$TMP/.opencode/agents/planner.md" \
  || fail "OpenCode planner lacks its state-file-only edit rule"
for oc_command in feature toolkit-update; do
  grep -q '^agent: leader$' "$TMP/.opencode/commands/$oc_command.md" \
    || fail "OpenCode $oc_command command does not select the leader"
  grep -q '^subagent: false$' "$TMP/.opencode/commands/$oc_command.md" \
    || fail "OpenCode $oc_command command does not preserve the lead session"
done
ok "OpenCode agents and commands reference canonical prompts with native V2 metadata"

[ -f "$TMP/.agent-pipeline/.needs-customization" ] || fail ".needs-customization marker missing on fresh scaffold"
ok "first-run customization marker dropped"

STAMP="$TMP/.agent-pipeline/.toolkit-version"
[ -f "$STAMP" ] || fail "provenance stamp missing on fresh scaffold"
grep -q '^toolkit_sha:' "$STAMP" || fail "stamp lacks toolkit_sha"
grep -q '^builder_model: a/b' "$STAMP" || fail "stamp does not record the init flags"
cp "$STAMP" "$TMP/stamp.bak"
ok "fresh scaffold wrote the provenance stamp with flags + toolkit SHA"

# --- 2. second run skips, never clobbers ------------------------------------
cp "$TMP/.claude/commands/feature.md" "$TMP/feature.sentinel"
printf 'LOCAL CUSTOMIZATION\n' >> "$TMP/.claude/commands/feature.md"
cp "$TMP/.opencode/agents/leader.md" "$TMP/leader.sentinel"
printf 'LOCAL OPENCODE CUSTOMIZATION\n' >> "$TMP/.opencode/agents/leader.md"
rm -f "$TMP/.agent-pipeline/.needs-customization"
bash "$ROOT/bin/init.sh" --target "$TMP" > "$TMP/run2.log" 2>&1 \
  || fail "second init.sh run failed"
skips="$(grep -c '^init.sh: skip (exists)' "$TMP/run2.log" || true)"
[ "$skips" = "$files" ] || fail "second run: $skips skips, expected $files"
! grep -q '^init.sh: wrote ' "$TMP/run2.log" || fail "second run wrote something"
grep -q 'LOCAL CUSTOMIZATION' "$TMP/.claude/commands/feature.md" \
  || fail "second run clobbered a customized file"
grep -q 'LOCAL OPENCODE CUSTOMIZATION' "$TMP/.opencode/agents/leader.md" \
  || fail "second run clobbered the OpenCode leader"
[ ! -f "$TMP/.agent-pipeline/.needs-customization" ] || fail "marker recreated on non-fresh run"
cmp -s "$TMP/stamp.bak" "$TMP/.agent-pipeline/.toolkit-version" 2>/dev/null \
  || fail "second run touched the provenance stamp"
ok "re-run skipped all $files files, preserved local edits, marker + stamp untouched"
# restore the pristine render so the --update checks below start clean
mv "$TMP/feature.sentinel" "$TMP/.claude/commands/feature.md"
mv "$TMP/leader.sentinel" "$TMP/.opencode/agents/leader.md"

# Simulate a stamped project that predates Codex support. A plain, flag-free
# run must recover the render values from the stamp and add only missing files.
rm -f "$TMP/AGENTS.md" \
  "$TMP/.codex/agents/planner.toml" \
  "$TMP/.agents/skills/feature/SKILL.md" \
  "$TMP/.agents/skills/toolkit-update/SKILL.md"
bash "$ROOT/bin/init.sh" --target "$TMP" > "$TMP/bootstrap.log" 2>&1 \
  || fail "flag-free missing-file bootstrap failed"
bootstrap_writes="$(grep -c '^init.sh: wrote ' "$TMP/bootstrap.log" || true)"
[ "$bootstrap_writes" = "4" ] \
  || fail "missing-file bootstrap wrote $bootstrap_writes files, expected 4"
grep -q '^builder_model: a/b' "$TMP/.agent-pipeline/.toolkit-version" \
  || fail "missing-file bootstrap changed the provenance values"
[ ! -f "$TMP/.agent-pipeline/.needs-customization" ] \
  || fail "missing-file bootstrap recreated the first-run marker"
ok "flag-free plain run installs newly added files from stamped values only"

# Simulate a stamped scaffold without OpenCode lead support. Triage reports
# all four files without writing them; plain bootstrap adds only those files.
rm -f "$TMP/.opencode/agents/leader.md" "$TMP/.opencode/agents/planner.md" \
  "$TMP/.opencode/commands/feature.md" "$TMP/.opencode/commands/toolkit-update.md"
rc=0
bash "$ROOT/bin/init.sh" --update --target "$TMP" > "$TMP/oc-triage.log" 2>&1 || rc=$?
[ "$rc" = "1" ] || fail "OpenCode missing-file triage did not report drift"
[ "$(grep -c '^  new ' "$TMP/oc-triage.log")" = "4" ] \
  || fail "OpenCode triage did not list exactly four new files"
[ ! -f "$TMP/.opencode/agents/leader.md" ] || fail "OpenCode triage wrote an adapter"
bash "$ROOT/bin/init.sh" --target "$TMP" > "$TMP/oc-bootstrap.log" 2>&1 \
  || fail "OpenCode flag-free bootstrap failed"
[ "$(grep -c '^init.sh: wrote ' "$TMP/oc-bootstrap.log")" = "4" ] \
  || fail "OpenCode bootstrap did not write exactly four files"
cmp -s "$TMP/stamp.bak" "$STAMP" || fail "OpenCode bootstrap changed the stamp"
[ ! -f "$TMP/.agent-pipeline/.needs-customization" ] || fail "OpenCode bootstrap recreated the marker"
ok "OpenCode lead bootstrap is additive; triage writes nothing and preserves provenance"

# Exercise lead auto-selection without requiring tmux/Codex on the test host.
# PATH contains a fake codex and tmux but no claude, and tmux records the pane
# command instead of creating a real session.
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/codex" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$FAKEBIN/tmux" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TEAM_LOG"
[ "$1" = "has-session" ] && [ "${TEAM_HAS_SESSION:-0}" = "1" ] && exit 0
[ "$1" = "has-session" ] && exit 1
exit 0
EOF
chmod +x "$FAKEBIN/codex" "$FAKEBIN/tmux"
TEAM_LOG="$TMP/team.log" PATH="$FAKEBIN:/usr/bin:/bin" \
  "$TMP/.agent-pipeline/bin/team.sh" --fresh codex-smoke >/dev/null 2>&1 \
  || fail "team.sh failed its Codex fallback launch"
grep -q 'send-keys .* .agent-pipeline/bin/codex-lead.sh codex-smoke --fresh C-m' "$TMP/team.log" \
  || fail "team.sh did not put Codex in the lead pane when Claude was unavailable"
ok "team.sh falls back to Codex when Claude is unavailable"

cat > "$FAKEBIN/opencode" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FAKEBIN/opencode"
TEAM_LOG="$TMP/team-oc.log" PATH="$FAKEBIN:/usr/bin:/bin" \
  "$TMP/.agent-pipeline/bin/team.sh" --lead opencode --port 4097 --fresh oc-smoke >/dev/null 2>&1 \
  || fail "team.sh failed its explicit OpenCode launch"
grep -q 'send-keys .*team.0 .*opencode --server http://localhost:4097 C-m' "$TMP/team-oc.log" \
  || fail "OpenCode lead did not connect to the selected server"
grep -q 'team.0 .*OPENCODE_PASSWORD=.*cat' "$TMP/team-oc.log" \
  || fail "OpenCode lead did not load server authentication at runtime"
! grep -q -- '--auto\|--continue\|--agent' "$TMP/team-oc.log" \
  || fail "OpenCode lead launch auto-approved, resumed an arbitrary worker, or used unsupported --agent"
ok "team.sh launches an authenticated OpenCode-only lead on the selected port"

rm -f "$FAKEBIN/codex"
TEAM_LOG="$TMP/team-oc-auto.log" PATH="$FAKEBIN:/usr/bin:/bin" \
  "$TMP/.agent-pipeline/bin/team.sh" --fresh oc-auto >/dev/null 2>&1 \
  || fail "team.sh failed OpenCode auto fallback"
grep -q 'team.0 .*opencode --server' "$TMP/team-oc-auto.log" \
  || fail "team.sh did not select OpenCode when Claude/Codex were absent"
ok "team.sh falls back to OpenCode without Claude or Codex"

TEAM_LOG="$TMP/team-oc-resume.log" TEAM_OPENCODE_SESSION=ses_AbC123 \
  PATH="$FAKEBIN:/usr/bin:/bin" "$TMP/.agent-pipeline/bin/team.sh" --lead opencode oc-resume \
  >/dev/null 2>&1 || fail "team.sh failed explicit OpenCode lead resume"
grep -q -- '--session ses_AbC123 C-m' "$TMP/team-oc-resume.log" \
  || fail "team.sh did not preserve the exact mixed-case lead session id"
TEAM_LOG="$TMP/team-oc-fresh.log" TEAM_OPENCODE_SESSION=ses_AbC123 \
  PATH="$FAKEBIN:/usr/bin:/bin" "$TMP/.agent-pipeline/bin/team.sh" --lead opencode --fresh oc-fresh \
  >/dev/null 2>&1 || fail "team.sh failed fresh OpenCode lead launch"
! grep -q -- '--session' "$TMP/team-oc-fresh.log" || fail "--fresh reused the lead session"
if TEAM_LOG="$TMP/team-oc-invalid.log" TEAM_OPENCODE_SESSION='ses_abc;bad' \
  PATH="$FAKEBIN:/usr/bin:/bin" "$TMP/.agent-pipeline/bin/team.sh" --lead opencode oc-invalid \
  >/dev/null 2>&1; then
  fail "team.sh accepted shell text in TEAM_OPENCODE_SESSION"
fi
! grep -q '^new-session ' "$TMP/team-oc-invalid.log" || fail "invalid session created panes"
ok "OpenCode resume uses only an explicit lead id; --fresh and input validation are enforced"

TEAM_LOG="$TMP/team-existing.log" TEAM_HAS_SESSION=1 TEAM_LEAD=invalid \
  PATH="$FAKEBIN:/usr/bin:/bin" "$TMP/.agent-pipeline/bin/team.sh" existing \
  >/dev/null 2>&1 || fail "team.sh refused to attach an existing session before lead selection"
grep -q '^attach -t existing$' "$TMP/team-existing.log" \
  || fail "team.sh did not attach the existing session"
ok "team.sh attaches an existing session without requiring a lead CLI"

# --- 3. provenance stamp ------------------------------------------------------

# --- 4. --update (triage mode): clean target, flags defaulted from stamp ------
rc=0
bash "$ROOT/bin/init.sh" --update --target "$TMP" > "$TMP/upd1.log" 2>&1 || rc=$?
[ "$rc" = "0" ] || { cat "$TMP/upd1.log"; fail "--update exited $rc on a clean target, expected 0"; }
grep -q "all $files checked files match" "$TMP/upd1.log" || fail "--update summary missing on a clean target"
ok "--update: flag-free run defaults from the stamp; clean target exits 0"

# --- 5. --update: drift is summarized, exit 1, hunks only behind --diff -------
printf '\n' >> "$TMP/.agent-pipeline/tasks/TEMPLATE.md"
rc=0
bash "$ROOT/bin/init.sh" --update --target "$TMP" > "$TMP/upd2.log" 2>&1 || rc=$?
[ "$rc" = "1" ] || fail "--update exited $rc on a drifted target, expected 1"
differ="$(grep -c '^  differs  ' "$TMP/upd2.log" || true)"
[ "$differ" = "1" ] || fail "--update summary listed $differ differing files after drifting one, expected 1"
grep -q 'differs  .*TEMPLATE.md' "$TMP/upd2.log" || fail "--update flagged the wrong file"
! grep -q '^--- \|^+++ \|^@@ ' "$TMP/upd2.log" || fail "--update leaked hunks without --diff"
cmp -s "$STAMP" "$TMP/stamp.bak" || fail "--update modified the provenance stamp"
rc=0
bash "$ROOT/bin/init.sh" --update --target "$TMP" --only TEMPLATE.md --diff > "$TMP/upd3.log" 2>&1 || rc=$?
[ "$rc" = "1" ] || fail "--only --diff exited $rc, expected 1"
grep -q '^@@ ' "$TMP/upd3.log" || fail "--diff mode printed no hunks"
grep -q "filtered by --only" "$TMP/upd3.log" || fail "--only filter not reported"
ok "--update: drift → exit 1, summary-only by default, hunks behind --diff/--only, stamp untouched"

# --- 5b. --refresh-stamp rewrites the baseline --------------------------------
printf '\n# touched\n' >> "$STAMP"
sed 's/^toolkit_sha:.*/toolkit_sha: stale-test-baseline/' "$STAMP" > "$TMP/stamp-stale"
mv "$TMP/stamp-stale" "$STAMP"
rc=0
bash "$ROOT/bin/init.sh" --refresh-stamp --target "$TMP" > /dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "--refresh-stamp failed"
! grep -q 'stale-test-baseline' "$STAMP" || fail "--refresh-stamp did not refresh its owned baseline"
grep -q '^# touched' "$STAMP" || fail "--refresh-stamp erased project notes"
grep -q '^toolkit_sha:' "$STAMP" || fail "rewritten stamp lost its fields"
ok "--refresh-stamp updates owned provenance fields and preserves project notes"

# --- 5c. --update without a stamp recovers init values from the target --------
mv "$STAMP" "$TMP/stamp.hold"
rc=0
bash "$ROOT/bin/init.sh" --update --target "$TMP" > "$TMP/upd5.log" 2>&1 || rc=$?
[ "$rc" = "1" ] || fail "stamp-less flag-free --update exited $rc, expected 1 (known drift)"
grep -q "no stamp — inferred" "$TMP/upd5.log" || fail "did not report inferring values from the target"
grep -q 'BUILDER_MODEL: a/b' "$TMP/upd5.log" || fail "inferred wrong builder_model"
grep -q 'scaffolded from' "$TMP/upd5.log" && fail "claimed a stamp baseline without a stamp"
mv "$TMP/stamp.hold" "$STAMP"
ok "--update without a stamp recovers the init values from the target's files"

# leave the deliberate TEMPLATE.md drift in place; later sections don't read it

# --- 5. self-target guard ---------------------------------------------------
if bash "$ROOT/bin/init.sh" --target "$ROOT" --project-name x \
     --builder-model a/b --reviewer-model a/c \
     --reviewer-fallback-model d/e --tester-model a/b >/dev/null 2>&1; then
  fail "init.sh allowed scaffolding into its own checkout"
fi
ok "init.sh refuses --target pointing at the toolkit itself"

# --- 6. verify-state.sh ------------------------------------------------------
VS="$TMP/.agent-pipeline/bin/verify-state.sh"
cat > "$TMP/.agent-pipeline/tasks/T-01.md" <<'EOF'
**Status:** blocked

## Review verdicts

### Pass 1 — 2026-08-26 — verdict: CHANGES_REQUESTED

1. [high] a.js:1 — finding
EOF
"$VS" T-01 > /dev/null 2>&1 || fail "verify-state rejected a valid blocked-state file"
ok "verify-state accepts valid state file incl. blocked Status"

cp "$TMP/.agent-pipeline/tasks/T-01.md" "$TMP/.agent-pipeline/tasks/T-08.md"
printf '**OpenCode session id:** ses_legacy\n' >> "$TMP/.agent-pipeline/tasks/T-08.md"
"$VS" T-08 > /dev/null 2>&1 || fail "legacy shared-session task became unreadable"
for role in builder reviewer tester; do
  printf '**OpenCode %s session id:** ses_%s\n' "$role" "$role" >> "$TMP/.agent-pipeline/tasks/T-08.md"
done
"$VS" T-08 > /dev/null 2>&1 || fail "distinct role sessions were refused"
sed 's/ses_tester/ses_builder/' "$TMP/.agent-pipeline/tasks/T-08.md" > "$TMP/shared.md"
cp "$TMP/shared.md" "$TMP/.agent-pipeline/tasks/T-08.md"
"$VS" T-08 > /dev/null 2>&1 && fail "shared builder/tester session was accepted"
grep -v 'OpenCode tester session id' "$TMP/shared.md" > "$TMP/.agent-pipeline/tasks/T-08.md"
"$VS" T-08 > /dev/null 2>&1 && fail "incomplete role session migration was accepted"
grep -v 'OpenCode .* session id' "$TMP/shared.md" > "$TMP/.agent-pipeline/tasks/T-08.md"
for role in builder reviewer tester; do
  printf '**OpenCode %s session id:** none yet — first call starts fresh\n' "$role" >> "$TMP/.agent-pipeline/tasks/T-08.md"
done
"$VS" T-08 > /dev/null 2>&1 || fail "empty role session fields were refused"
printf '**OpenCode builder session id:** ses_extra\n' >> "$TMP/.agent-pipeline/tasks/T-08.md"
"$VS" T-08 > /dev/null 2>&1 && fail "duplicate session field was accepted"
ok "role sessions stay separate; legacy tasks remain readable and partial migrations fail"

# 6a. Task class + decision source: absent = fine, junk = fails
cat > "$TMP/.agent-pipeline/tasks/T-01.md" <<'EOF'
**Status:** blocked
**Task class:** TBD
**Class decided by:** maybe
EOF
"$VS" T-01 > /dev/null 2>&1 && fail "verify-state accepted bogus Task class / decision source"
printf '**Status:** blocked\n**Task class:** sensitive\n**Class decided by:** human\n' > "$TMP/.agent-pipeline/tasks/T-01.md"
"$VS" T-01 > /dev/null 2>&1 || fail "verify-state rejected a valid class + decision source"
ok "verify-state validates Task class + Class decided by (absent ok, junk fails)"

printf '\n### Pass 3 — 2026-08-26 — verdict: PASS\n\nnone\n' >> "$TMP/.agent-pipeline/tasks/T-01.md"
if "$VS" T-01 > /dev/null 2>&1; then
  fail "verify-state accepted a Pass 3 (two-loop cap breached)"
fi
ok "verify-state fails loudly on a third review pass"

# --- 6b. verify-state.sh: budgets and definition-of-done --------------------
# The budget counters and the done-gate are the structural half of the
# anti-thrash and delivery-contract rules; if they are advisory only, they
# are not rules. Each is checked on a file that is otherwise valid, so a
# failure here names exactly one cause.
cat > "$TMP/.agent-pipeline/tasks/T-03.md" <<'EOF'
**Status:** in-review
**Review loop count:** 1 / 2
**Test-fix loops:** 5 / 2
**Spec bounces:** 0 / 1

## Review verdicts

### Pass 1 — 2026-08-26 — verdict: CHANGES_REQUESTED

1. [high] a.js:1 — finding
EOF
"$VS" T-03 2>&1 | grep -q 'test-fix loop budget exceeded'   || fail "verify-state did not catch a blown test-fix budget"
sed -i.bak 's|^\*\*Test-fix loops:\*\* 5 / 2|**Test-fix loops:** 1 / 2|' "$TMP/.agent-pipeline/tasks/T-03.md"
"$VS" T-03 > /dev/null 2>&1 || fail "verify-state rejected a file with in-budget counters"
ok "verify-state enforces the loop budgets and passes when they are in range"

cat > "$TMP/.agent-pipeline/tasks/T-04.md" <<'EOF'
**Status:** done
**Review loop count:** 1 / 2
**Test-fix loops:** 0 / 2
**Spec bounces:** 0 / 1

## Acceptance criteria

- [ ] AC1 — something checkable
- [ ] AC2 — something else checkable

### Acceptance criteria ledger

| AC | Met? | Reviewer evidence | Test evidence |
| --- | --- | --- | --- |
| AC1 | [x] | Pass 1 — a.js:42 | Run 1 — "parses null" |
| AC2 | [ ] | Pass 1 — unverifiable from diff | no covering test |

## Review verdicts

### Pass 1 — 2026-08-26 — verdict: PASS

none
EOF
if "$VS" T-04 > /dev/null 2>&1; then
  fail "verify-state accepted 'done' with an unticked, unwaived criterion"
fi
"$VS" T-04 2>&1 | grep -q "acceptance criteria are unticked"   || fail "verify-state's done-gate failed for the wrong reason"
python3 - "$TMP/.agent-pipeline/tasks/T-04.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('| AC2 | [ ] | Pass 1 — unverifiable from diff | no covering test |',
            '| AC2 | [ ] | waived by user 2026-08-26 | n/a |')
open(p,'w').write(s)
PY
"$VS" T-04 > /dev/null 2>&1 || fail "verify-state rejected 'done' with a properly waived criterion"
ok "verify-state refuses 'done' on an open criterion, accepts an explicit waiver"

# 6c. done-gate also rejects a ticked ledger row with an empty evidence cell —
# a tick TEMPLATE.md already forbids, now enforced instead of self-policed.
cat > "$TMP/.agent-pipeline/tasks/T-06.md" <<'EOF'
**Status:** done
**Review loop count:** 1 / 2
**Test-fix loops:** 0 / 2
**Spec bounces:** 0 / 1

## Acceptance criteria

- [ ] AC1 — something checkable

### Acceptance criteria ledger

| AC | Met? | Reviewer evidence | Test evidence |
| --- | --- | --- | --- |
| AC1 | [x] | Pass 1 — a.js:42 | |

## Review verdicts

### Pass 1 — 2026-09-10 — verdict: PASS

none
EOF
"$VS" T-06 > /dev/null 2>&1 && fail "verify-state accepted 'done' with a ticked ledger row citing no test evidence"
"$VS" T-06 2>&1 | grep -q 'cite no evidence' || fail "done-gate ledger-evidence check failed for the wrong reason"
python3 - "$TMP/.agent-pipeline/tasks/T-06.md" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace('| AC1 | [x] | Pass 1 — a.js:42 | |',
              '| AC1 | [x] | Pass 1 — a.js:42 | Run 1 — "parses null" |')
open(p, 'w').write(s)
PY
"$VS" T-06 > /dev/null 2>&1 || fail "verify-state rejected a 'done' file whose ticked row cites both kinds of evidence"
ok "verify-state's done-gate rejects a ticked ledger row with a blank evidence cell"

# 6d. once review has run, a missing/placeholder verdict fails from the file
# side too — the mirror of the unfilled-placeholder check.
cat > "$TMP/.agent-pipeline/tasks/T-07.md" <<'EOF'
**Status:** testing
**Review loop count:** 1 / 2
**Test-fix loops:** 0 / 2
**Spec bounces:** 0 / 1

## Review verdicts

### Pass 1 — 2026-09-10 — verdict: TBD
EOF
"$VS" T-07 > /dev/null 2>&1 && fail "verify-state accepted Status 'testing' with no filled review verdict"
"$VS" T-07 2>&1 | grep -q 'no Review verdicts pass records a filled' || fail "missing-verdict check failed for the wrong reason"
sed -i.bak 's/verdict: TBD/verdict: PASS/' "$TMP/.agent-pipeline/tasks/T-07.md"
"$VS" T-07 > /dev/null 2>&1 || fail "verify-state rejected 'testing' once a filled PASS verdict was present"
ok "verify-state requires a filled review verdict once a task has reached review"

# --- 7. verify-spec.sh -------------------------------------------------------
# The spec-side equivalent: structure only, run before the human sees a spec.
VSPEC="$TMP/.agent-pipeline/bin/verify-spec.sh"
cp "$TMP/.agent-pipeline/tasks/TEMPLATE.md" "$TMP/.agent-pipeline/tasks/T-05.md"
if "$VSPEC" T-05 > /dev/null 2>&1; then
  fail "verify-spec passed the raw template, which is entirely boilerplate"
fi
"$VSPEC" T-05 2>&1 | grep -q 'still the template placeholder'   || fail "verify-spec did not identify template boilerplate"
ok "verify-spec rejects an unfilled spec"

python3 - "$TMP/.agent-pipeline/tasks/T-05.md" <<'PY'
import sys
NL = chr(10)
p = sys.argv[1]
out, skip = [], False
for line in open(p).read().split(NL):
    if skip:
        # placeholder fields wrap over several lines; drop until the blank one
        if line.strip() == "":
            skip = False
            out.append(line)
        continue
    if line.startswith("**Simplest version considered:**"):
        out.append("**Simplest version considered:** strip at the call site; rejected, three callers need it.")
        skip = True
    elif line.startswith("**Blast radius:**"):
        out.append("**Blast radius:** every importer path; a wrong rule silently rewrites user URLs.")
        skip = True
    elif line.startswith("<One paragraph."):
        out.append("Trailing slashes in imported URLs 404 instead of resolving.")
        skip = True
    elif line.startswith("- [ ] AC1 "):
        out.append('- [ ] AC1 — importing "https://x.test/a/" resolves identically to "https://x.test/a"')
    elif line.startswith("- [ ] AC2 "):
        out.append('- [ ] AC2 — importing "https://x.test/" returns the root document, not a 404')
    elif line.startswith("- [ ] AC3 "):
        out.append("- [ ] AC3 — a URL without a trailing slash is byte-identical after normalisation")
    elif line == "| | |":
        out.append("| filled | filled |")
    else:
        out.append(line)
open(p, "w").write(NL.join(out))
PY
"$VSPEC" T-05 > /dev/null 2>&1 || { "$VSPEC" T-05; fail "verify-spec rejected a properly filled spec"; }
ok "verify-spec accepts a filled spec"

python3 - "$TMP/.agent-pipeline/tasks/T-05.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('resolves identically to "https://x.test/a"','works well')
open(p,'w').write(s)
PY
if "$VSPEC" T-05 > /dev/null 2>&1; then
  fail "verify-spec accepted an acceptance criterion that names a quality, not an observable"
fi
ok "verify-spec catches an unmeasurable acceptance criterion"

# --- 8. promote-findings.sh --------------------------------------------------
PF="$TMP/.agent-pipeline/bin/promote-findings.sh"
mkdir -p "$TMP/docs"
cat > "$TMP/.agent-pipeline/tasks/T-02.md" <<'EOF'
## Findings for docs

- [docs/GOTCHAS.md] real finding worth keeping
- [../../escaped.md] traversal attempt
- [/abs/escaped.md] absolute-path attempt
EOF
out="$("$PF" T-02 2>&1)"
grep -q 'appended to docs/GOTCHAS.md' <<< "$out" || fail "legit finding not promoted"
grep -q 'escaping the repo root' <<< "$out" || fail "../.. path was not refused"
grep -q 'unsafe/invalid doc path' <<< "$out" || fail "absolute path was not refused"
[ -f "$TMP/docs/GOTCHAS.md" ] || fail "docs/GOTCHAS.md not created"
if [ -e "$TMP/../escaped.md" ] || [ -f "/tmp/escaped.md" ]; then
  fail "a traversal write landed somewhere"
fi
[ ! -f "$(cd "$TMP/.." && pwd)/escaped.md" ] || fail "traversal escaped above target"
out="$("$PF" T-02 2>&1)"
grep -q 'already present, skipped' <<< "$out" || fail "promotion not idempotent"
ok "promote-findings copies legit findings, refuses escaping paths, is idempotent"

# --- 9. artifact dispatch contract (fake CLI; no agents or LLM calls) ---------
MOCK_OC="$TMP/mock-oc"
mkdir -p "$MOCK_OC" "$TMP/.agent-pipeline/prompts/T-artifacts" "$TMP/.agent-pipeline/logs/T-other"
cat > "$MOCK_OC/timeout" <<'EOF'
#!/usr/bin/env bash
shift
exec "$@"
EOF
cat > "$MOCK_OC/opencode" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  api) printf '{"data":[]}\n' ;;
  run)
    printf 'run\n' >> "$OC_TEST_CALLS"
    cat >/dev/null
    sleep 0.05
    printf '{"type":"text","sessionID":"ses_mock","part":{"text":"receipt"}}\n'
    exit "${MOCK_OC_STATUS:-0}"
    ;;
  *) exit 99 ;;
esac
EOF
chmod +x "$MOCK_OC/timeout" "$MOCK_OC/opencode"
mock_oc() {
  (cd "$TMP" && PATH="$MOCK_OC:$PATH" OC_POLL=0.01 OC_TEST_CALLS="$TMP/mock-calls" \
    .agent-pipeline/bin/oc.sh --agent builder --model fake/model --session ses_mock "$@")
}
for attempt in 1 2 3 4; do
  printf 'Implement the test task.\n' > "$TMP/.agent-pipeline/prompts/T-artifacts/builder-$attempt.md"
done
if mock_oc --prompt "inline" > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh accepted an inline prompt"
fi
if mock_oc --prompt-file .agent-pipeline/prompts/T-artifacts/builder-1.md > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh accepted a missing transcript"
fi
if mock_oc --raw-out .agent-pipeline/logs/T-artifacts/builder-1.jsonl < /dev/null > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh accepted a missing prompt file"
fi
if mock_oc --prompt-file .agent-pipeline/prompts/T-artifacts/builder-1.md \
    --raw-out .agent-pipeline/logs/T-other/builder-1.jsonl > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh accepted a different transcript task"
fi
if mock_oc --prompt-file .agent-pipeline/prompts/T-artifacts/builder-1.md \
    --raw-out .agent-pipeline/logs/T-artifacts/builder-2.jsonl > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh accepted a mismatched pass"
fi
printf 'wrong role\n' > "$TMP/.agent-pipeline/prompts/T-artifacts/reviewer-1.md"
if mock_oc --prompt-file .agent-pipeline/prompts/T-artifacts/reviewer-1.md \
    --raw-out .agent-pipeline/logs/T-artifacts/reviewer-1.jsonl > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh accepted a mismatched role"
fi
[ ! -e "$TMP/mock-calls" ] || fail "invalid dispatch reached the fake worker"
printf 'invalid pass\n' > "$TMP/.agent-pipeline/prompts/T-artifacts/builder-0.md"
if mock_oc --prompt-file .agent-pipeline/prompts/T-artifacts/builder-0.md \
    --raw-out .agent-pipeline/logs/T-artifacts/builder-0.jsonl > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh accepted pass zero"
fi
printf 'legacy prompt\n' > "$TMP/.agent-pipeline/T-artifacts.request.md"
if mock_oc --prompt-file .agent-pipeline/T-artifacts.request.md \
    --raw-out .agent-pipeline/logs/T-artifacts/builder-1.jsonl > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh accepted a legacy root-level prompt"
fi
ln -s "$TMP/missing-transcript" "$TMP/.agent-pipeline/logs/T-artifacts/builder-1.jsonl"
if mock_oc --prompt-file .agent-pipeline/prompts/T-artifacts/builder-1.md \
    --raw-out .agent-pipeline/logs/T-artifacts/builder-1.jsonl > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh followed a dangling transcript symlink"
fi
[ ! -e "$TMP/missing-transcript" ] || fail "transcript symlink target was created"
rm "$TMP/.agent-pipeline/logs/T-artifacts/builder-1.jsonl"
ok "oc.sh rejects missing/inline prompts and mismatched artifact task/role/pass before dispatch"

mock_oc --prompt-file .agent-pipeline/prompts/T-artifacts/builder-1.md \
  --raw-out .agent-pipeline/logs/T-artifacts/builder-1.jsonl > "$TMP/oc-check.log" 2>&1 \
  || { cat "$TMP/oc-check.log"; fail "valid artifact dispatch failed"; }
grep -q 'receipt' "$TMP/.agent-pipeline/logs/T-artifacts/builder-1.jsonl" || fail "transcript not saved"
[ -s "$TMP/.agent-pipeline/logs/T-artifacts/pipeline.jsonl" ] || fail "task telemetry not saved"
[ ! -e "$TMP/.agent-pipeline/logs/pipeline.jsonl" ] || fail "telemetry was saved outside its task"
cp "$TMP/.agent-pipeline/logs/T-artifacts/builder-1.jsonl" "$TMP/transcript-before"
if mock_oc --prompt-file .agent-pipeline/prompts/T-artifacts/builder-1.md \
    --raw-out .agent-pipeline/logs/T-artifacts/builder-1.jsonl > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh overwrote a previous pass"
fi
cmp -s "$TMP/transcript-before" "$TMP/.agent-pipeline/logs/T-artifacts/builder-1.jsonl" \
  || fail "previous transcript changed"
[ "$(wc -l < "$TMP/mock-calls" | tr -d ' ')" = 1 ] || fail "duplicate dispatch reached worker"
ok "oc.sh saves task transcript and refuses duplicate passes without changing evidence"

# Absolute paths work even when the caller is in a nested project directory.
(cd "$TMP/docs" && PATH="$MOCK_OC:$PATH" OC_POLL=0.01 OC_TEST_CALLS="$TMP/mock-calls" \
  "$TMP/.agent-pipeline/bin/oc.sh" --agent builder --model fake/model --session ses_mock \
  --prompt-file "$TMP/.agent-pipeline/prompts/T-artifacts/builder-2.md" \
  --raw-out "$TMP/.agent-pipeline/logs/T-artifacts/builder-2.jsonl") > "$TMP/oc-check.log" 2>&1 \
  || fail "nested caller with absolute artifact paths failed"
if MOCK_OC_STATUS=7 mock_oc --prompt-file .agent-pipeline/prompts/T-artifacts/builder-3.md \
    --raw-out .agent-pipeline/logs/T-artifacts/builder-3.jsonl > "$TMP/oc-check.log" 2>&1; then
  fail "oc.sh lost the worker failure status"
else
  [ "$?" -eq 7 ] || fail "oc.sh changed the worker failure status"
fi
grep -q 'receipt' "$TMP/.agent-pipeline/logs/T-artifacts/builder-3.jsonl" || fail "failed-run transcript lost"
ok "new passes preserve earlier artifacts, work from nested cwd, and retain failed-run evidence"

# Two callers race for one pass: exactly one may reserve and launch it.
for caller in 1 2; do
  (
    if mock_oc --prompt-file .agent-pipeline/prompts/T-artifacts/builder-4.md \
        --raw-out .agent-pipeline/logs/T-artifacts/builder-4.jsonl > "$TMP/race-$caller.log" 2>&1; then
      printf '0\n' > "$TMP/race-$caller.status"
    else
      printf '%s\n' "$?" > "$TMP/race-$caller.status"
    fi
  ) &
done
wait
successes="$(grep -l '^0$' "$TMP/race-1.status" "$TMP/race-2.status" | wc -l | tr -d ' ')"
[ "$successes" = 1 ] || fail "concurrent callers did not reserve one exclusive pass"
[ "$(wc -l < "$TMP/mock-calls" | tr -d ' ')" = 4 ] || fail "concurrent duplicate reached worker"
grep -q 'receipt' "$TMP/.agent-pipeline/logs/T-artifacts/builder-4.jsonl" || fail "raced transcript lost"
ok "oc.sh atomically reserves transcripts against concurrent duplicate dispatch"

# --- directory separation, ignore rules, and legacy update safety ---------
IGNORE_PROJECT="$TMP/ignore-project"
mkdir -p "$IGNORE_PROJECT"
git init -q "$IGNORE_PROJECT"
bash "$ROOT/bin/init.sh" --target "$IGNORE_PROJECT" --project-name ignore > "$TMP/ignore.log" 2>&1 \
  || fail "gitignore fixture scaffold failed"
for ignored in logs/T-001/builder-1.jsonl prompts/T-001/builder-1.md .oc-port .oc-password .claude-session-id.test; do
  git -C "$IGNORE_PROJECT" check-ignore -q ".agent-pipeline/$ignored" \
    || fail "runtime artifact is not ignored: $ignored"
done
for tracked in .agent-pipeline/tasks/T-001.md .agent-pipeline/tasks/TEMPLATE.md .agent-pipeline/.toolkit-version .agents/skills/feature/SKILL.md; do
  if git -C "$IGNORE_PROJECT" check-ignore -q "$tracked"; then
    fail "shared state/native skill unexpectedly ignored: $tracked"
  fi
done
cp "$IGNORE_PROJECT/.gitignore" "$TMP/ignore-before"
bash "$ROOT/bin/init.sh" --target "$IGNORE_PROJECT" > "$TMP/ignore.log" 2>&1 \
  || fail "gitignore fixture rerun failed"
cmp -s "$IGNORE_PROJECT/.gitignore" "$TMP/ignore-before" || fail "ignore rules duplicated on rerun"
ok "pipeline artifacts/secrets are ignored, shared state and native skills stay trackable"

# A gitdir file (as used by worktrees) gets the same additive rules.
mv "$IGNORE_PROJECT/.git" "$TMP/ignore-gitdir"
printf 'gitdir: %s\n' "$TMP/ignore-gitdir" > "$IGNORE_PROJECT/.git"
printf '# local rule\ncustom-output/\n' > "$IGNORE_PROJECT/.gitignore"
bash "$ROOT/bin/init.sh" --target "$IGNORE_PROJECT" > "$TMP/ignore.log" 2>&1 \
  || fail "gitdir-file fixture rerun failed"
git -C "$IGNORE_PROJECT" check-ignore -q .agent-pipeline/.oc-password \
  || fail "gitdir-file checkout did not receive secret ignore rule"
grep -qxF 'custom-output/' "$IGNORE_PROJECT/.gitignore" || fail "custom ignore rule lost"
ok "gitdir-file checkouts receive additive ignore rules"

printf '\n/.agent-pipeline/\n' >> "$IGNORE_PROJECT/.gitignore"
git -C "$IGNORE_PROJECT" check-ignore -q .agent-pipeline/tasks/T-001.md \
  || fail "whole-pipeline ignore policy did not cover task records"
if git -C "$IGNORE_PROJECT" check-ignore -q .agents/skills/feature/SKILL.md; then
  fail "whole-pipeline ignore policy hid native skills"
fi
bash "$ROOT/bin/init.sh" --target "$IGNORE_PROJECT" > "$TMP/ignore.log" 2>&1 \
  || fail "whole-pipeline ignore prevented local bootstrap"
grep -qxF '/.agent-pipeline/' "$IGNORE_PROJECT/.gitignore" || fail "whole-pipeline ignore policy was removed"
ok "projects can ignore the entire pipeline without hiding native skills"

LEGACY_PROJECT="$TMP/legacy-project"
mkdir -p "$LEGACY_PROJECT"
bash "$ROOT/bin/init.sh" --target "$LEGACY_PROJECT" --project-name legacy \
  --builder-model a/b --reviewer-model a/c --reviewer-fallback-model d/e \
  --tester-model a/b > "$TMP/legacy.log" 2>&1 || fail "legacy fixture scaffold failed"
python3 - "$LEGACY_PROJECT" <<'PY'
import pathlib, shutil, sys
root = pathlib.Path(sys.argv[1])
# Recreate an actual old release, not a split old/new tasks layout.
(root / '.agent-pipeline/tasks/TEMPLATE.md').unlink()
(root / '.agent-pipeline/tasks').rmdir()
(root / 'scripts').mkdir()
for script in (root / '.agent-pipeline/bin').iterdir():
    if script.name in ('task-record.py', 'migrate-layout.py'):
        script.unlink()  # These did not exist in the old release fixture.
    else:
        shutil.move(str(script), str(root / 'scripts' / script.name))
(root / '.agent-pipeline/bin').rmdir()
for entry in (root / '.agent-pipeline').iterdir():
    shutil.move(str(entry), str(root / '.agents' / entry.name))
(root / '.agent-pipeline').rmdir()
(root / '.agents/TEMPLATE.md').write_text('LOCAL TEMPLATE CUSTOMIZATION\n')
(root / '.agents/.oc-password').write_text('fixture-secret')
(root / '.agents/.oc-password').chmod(0o600)
(root / '.agents/T-001.md').write_text('**Status:** done\n')
PY
snapshot_project() {
  python3 - "$1" <<'PY'
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
for path in sorted(root.rglob('*')):
    if path.is_file():
        print(path.relative_to(root), oct(path.stat().st_mode), hashlib.sha256(path.read_bytes()).hexdigest())
PY
}
snapshot_project "$LEGACY_PROJECT" > "$TMP/legacy-before"
rc=0
bash "$ROOT/bin/init.sh" --update --target "$LEGACY_PROJECT" > "$TMP/legacy.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "legacy layout did not report migration drift"
grep -q 'directory migration required' "$TMP/legacy.log" || fail "legacy migration not surfaced"
grep -q 'this project scaffolded from' "$TMP/legacy.log" || fail "legacy stamp not read"
grep -q 'differs .*\.agent-pipeline/tasks/TEMPLATE.md' "$TMP/legacy.log" || fail "legacy template customization not compared"
if grep -q 'new .*\.agent-pipeline/tasks/TEMPLATE.md' "$TMP/legacy.log"; then
  fail "legacy template reported as missing instead of compared"
fi
rc=0
bash "$ROOT/bin/init.sh" --update --target "$LEGACY_PROJECT" --only .agent-pipeline/bin/dashboard > "$TMP/legacy.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "filtered update hid required directory migration"
for mode in scaffold refresh; do
  rc=0
  if [ "$mode" = refresh ]; then
    bash "$ROOT/bin/init.sh" --refresh-stamp --target "$LEGACY_PROJECT" > "$TMP/legacy.log" 2>&1 || rc=$?
  else
    bash "$ROOT/bin/init.sh" --target "$LEGACY_PROJECT" > "$TMP/legacy.log" 2>&1 || rc=$?
  fi
  [ "$rc" = 1 ] || fail "legacy $mode was not refused"
done
snapshot_project "$LEGACY_PROJECT" > "$TMP/legacy-after"
cmp -s "$TMP/legacy-before" "$TMP/legacy-after" || fail "legacy preview/refusal wrote project files"
ok "legacy update reads old provenance/template without writes; scaffold and refresh refuse split state"

cp "$LEGACY_PROJECT/.agents/.toolkit-version" "$TMP/legacy-stamp"
rm "$LEGACY_PROJECT/.agents/.toolkit-version"
rc=0
bash "$ROOT/bin/init.sh" --update --target "$LEGACY_PROJECT" > "$TMP/legacy.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "unstamped legacy layout did not report migration drift"
grep -q 'inferred init values' "$TMP/legacy.log" || fail "unstamped legacy flags not recovered"
grep -q 'REVIEWER_FALLBACK_MODEL: d/e' "$TMP/legacy.log" || fail "legacy reviewer fallback replaced by a default"
cp "$TMP/legacy-stamp" "$LEGACY_PROJECT/.agents/.toolkit-version"
mkdir "$LEGACY_PROJECT/.agent-pipeline"
cp "$TMP/legacy-stamp" "$LEGACY_PROJECT/.agent-pipeline/.toolkit-version"
rc=0
bash "$ROOT/bin/init.sh" --update --target "$LEGACY_PROJECT" > "$TMP/legacy.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "duplicate provenance collision was not refused"
grep -q 'both pipeline provenance stamps exist' "$TMP/legacy.log" || fail "collision reason missing"
cmp -s "$TMP/legacy-stamp" "$LEGACY_PROJECT/.agents/.toolkit-version" || fail "legacy collision changed baseline"
cmp -s "$TMP/legacy-stamp" "$LEGACY_PROJECT/.agent-pipeline/.toolkit-version" || fail "new collision changed baseline"
rm "$LEGACY_PROJECT/.agent-pipeline/.toolkit-version"
rmdir "$LEGACY_PROJECT/.agent-pipeline"
ok "unstamped legacy recovery works and duplicate provenance is refused without clobbering"

# Simulate the approved relocation; never move the native skill directory.
python3 - "$LEGACY_PROJECT" <<'PY'
import pathlib, shutil, sys
root = pathlib.Path(sys.argv[1])
(root / '.agent-pipeline').mkdir()
for entry in (root / '.agents').iterdir():
    if entry.name != 'skills':
        shutil.move(str(entry), str(root / '.agent-pipeline' / entry.name))
PY
python3 - "$ROOT" "$LEGACY_PROJECT" <<'PY'
import json, subprocess, sys
command = [sys.executable, sys.argv[1] + '/bin/migrate-layout.py']
plan = json.loads(subprocess.check_output(command + ['plan', '--project', sys.argv[2]], text=True))
subprocess.run(command + ['apply', '--project', sys.argv[2], '--approve', plan['approval'], '--workers-inactive'], check=True, stdout=subprocess.DEVNULL)
PY
bash "$ROOT/bin/init.sh" --target "$LEGACY_PROJECT" > "$TMP/legacy.log" 2>&1 || fail "bootstrap refused migrated layout"
grep -q 'LOCAL TEMPLATE CUSTOMIZATION' "$LEGACY_PROJECT/.agent-pipeline/tasks/TEMPLATE.md" || fail "migration bootstrap clobbered template"
[ -f "$LEGACY_PROJECT/.agents/skills/feature/SKILL.md" ] || fail "migration moved native skills"
cmp -s "$TMP/legacy-stamp" "$LEGACY_PROJECT/.agent-pipeline/.toolkit-version" || fail "migration bootstrap replaced baseline"
python3 - "$LEGACY_PROJECT/.agent-pipeline/.oc-password" <<'PY'
import pathlib, stat, sys
path = pathlib.Path(sys.argv[1])
assert path.read_text() == 'fixture-secret'
assert stat.S_IMODE(path.stat().st_mode) == 0o600
PY
rc=0
bash "$ROOT/bin/init.sh" --update --target "$LEGACY_PROJECT" --only .agent-pipeline/bin/dashboard > "$TMP/legacy.log" 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "migrated layout still reported directory drift"
ok "post-migration bootstrap preserves customization, credential modes, baseline, and native skills"

printf '\nsmoke: all checks passed (%s)\n' "$PASSED"
