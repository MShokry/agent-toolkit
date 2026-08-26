#!/usr/bin/env bash
#
# Automated version of the manual smoke run documented in CLAUDE.md's
# "Commands" section. Asserts the scaffolder's core guarantees end to end:
#
#   1. first scaffold writes every file, with no unsubstituted placeholder
#   2. the first-run customization marker is dropped exactly once
#   3. a second run skips everything (never clobbers) and does NOT re-drop
#      the marker once deleted
#   4. --update against an unchanged target reports every file up to date
#      and writes nothing
#   5. --update against a drifted file reports exactly that one diff
#   6. init.sh refuses to scaffold into its own checkout
#   7. verify-state.sh: valid state file passes; 'blocked' Status is known;
#      a third review pass (loop-cap breach) fails loudly
#   8. promote-findings.sh: copies findings into docs, is idempotent, and
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
# Exclude this log and the customization marker — only rendered files should
# pair 1:1 with "wrote" lines.
files="$(find "$TMP" -type f -not -name run1.log \
  -not -name .needs-customization | wc -l | tr -d ' ')"
[ "$wrote" = "$files" ] || fail "claimed $wrote writes but $files files exist"
ok "every reported write produced exactly one file ($files files)"

[ -f "$TMP/.agents/.needs-customization" ] || fail ".needs-customization marker missing on fresh scaffold"
ok "first-run customization marker dropped"

# --- 2. second run skips, never clobbers ------------------------------------
cp "$TMP/.claude/commands/feature.md" "$TMP/feature.sentinel"
printf 'LOCAL CUSTOMIZATION\n' >> "$TMP/.claude/commands/feature.md"
rm -f "$TMP/.agents/.needs-customization"
bash "$ROOT/bin/init.sh" "${INIT_ARGS[@]}" > "$TMP/run2.log" 2>&1 \
  || fail "second init.sh run failed"
skips="$(grep -c '^init.sh: skip (exists)' "$TMP/run2.log" || true)"
[ "$skips" = "$files" ] || fail "second run: $skips skips, expected $files"
! grep -q '^init.sh: wrote ' "$TMP/run2.log" || fail "second run wrote something"
grep -q 'LOCAL CUSTOMIZATION' "$TMP/.claude/commands/feature.md" \
  || fail "second run clobbered a customized file"
[ ! -f "$TMP/.agents/.needs-customization" ] || fail "marker recreated on non-fresh run"
ok "re-run skipped all $files files, preserved local edits, marker stayed deleted"
# restore the pristine render so the --update checks below start clean
mv "$TMP/feature.sentinel" "$TMP/.claude/commands/feature.md"

# --- 3. --update: clean target is all up-to-date ----------------------------
upd="$(bash "$ROOT/bin/init.sh" --update "${INIT_ARGS[@]}" 2>&1)"
n_up2date="$(printf '%s\n' "$upd" | grep -c '^init.sh: up to date — ' || true)"
[ "$n_up2date" = "$files" ] || fail "--update: $n_up2date up-to-date, expected $files"
printf '%s\n' "$upd" | grep -q '^init.sh: upstream changes' && fail "--update reported changes on a clean target"
printf '%s\n' "$upd" | grep -q 'does not exist yet' && fail "--update thinks a live file is missing"
ok "--update: all $files files report up to date, nothing written"

# --- 4. --update: drifted file produces exactly one diff ---------------------
printf '\n' >> "$TMP/.agents/TEMPLATE.md"
upd="$(bash "$ROOT/bin/init.sh" --update "${INIT_ARGS[@]}" 2>&1)"
changes="$(printf '%s\n' "$upd" | grep -c '^init.sh: upstream changes for ' || true)"
[ "$changes" = "1" ] || fail "--update: $changes diffs after drifting one file, expected 1"
printf '%s\n' "$upd" | grep -q '^init.sh: upstream changes for .*TEMPLATE.md$' \
  || fail "--update flagged the wrong file"
ok "--update: drifted file reported as exactly one upstream diff"

# --- 5. self-target guard ---------------------------------------------------
if bash "$ROOT/bin/init.sh" --target "$ROOT" --project-name x \
     --builder-model a/b --reviewer-model a/c \
     --reviewer-fallback-model d/e --tester-model a/b >/dev/null 2>&1; then
  fail "init.sh allowed scaffolding into its own checkout"
fi
ok "init.sh refuses --target pointing at the toolkit itself"

# --- 6. verify-state.sh ------------------------------------------------------
VS="$TMP/scripts/verify-state.sh"
cat > "$TMP/.agents/T-01.md" <<'EOF'
**Status:** blocked

## Review verdicts

### Pass 1 — 2026-08-26 — verdict: CHANGES_REQUESTED

1. [high] a.js:1 — finding
EOF
"$VS" T-01 > /dev/null 2>&1 || fail "verify-state rejected a valid blocked-state file"
ok "verify-state accepts valid state file incl. blocked Status"

printf '\n### Pass 3 — 2026-08-26 — verdict: PASS\n\nnone\n' >> "$TMP/.agents/T-01.md"
if "$VS" T-01 > /dev/null 2>&1; then
  fail "verify-state accepted a Pass 3 (two-loop cap breached)"
fi
ok "verify-state fails loudly on a third review pass"

# --- 7. promote-findings.sh --------------------------------------------------
PF="$TMP/scripts/promote-findings.sh"
mkdir -p "$TMP/docs"
cat > "$TMP/.agents/T-02.md" <<'EOF'
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
[ ! -e "$TMP/../escaped.md" ] && [ ! -f "/tmp/escaped.md" ] || fail "a traversal write landed somewhere"
[ ! -f "$(cd "$TMP/.." && pwd)/escaped.md" ] || fail "traversal escaped above target"
out="$("$PF" T-02 2>&1)"
grep -q 'already present, skipped' <<< "$out" || fail "promotion not idempotent"
ok "promote-findings copies legit findings, refuses escaping paths, is idempotent"

printf '\nsmoke: all checks passed (%s)\n' "$PASSED"
