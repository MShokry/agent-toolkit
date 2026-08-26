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
#      a third review pass (loop-cap breach) fails loudly; a blown budget
#      counter fails; 'done' is refused while an acceptance criterion is
#      unticked and unwaived
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
stamp_written=0; [ -f "$TMP/.agents/.toolkit-version" ] && stamp_written=1
files="$(find "$TMP" -type f -not -name run1.log \
  -not -name .needs-customization -not -name .toolkit-version | wc -l | tr -d ' ')"
[ "$wrote" = "$((files + stamp_written))" ] || fail "claimed $wrote writes but $((files + stamp_written)) files exist"
ok "every reported write produced exactly one file ($files rendered + stamp)"

[ -f "$TMP/.agents/.needs-customization" ] || fail ".needs-customization marker missing on fresh scaffold"
ok "first-run customization marker dropped"

STAMP="$TMP/.agents/.toolkit-version"
[ -f "$STAMP" ] || fail "provenance stamp missing on fresh scaffold"
grep -q '^toolkit_sha:' "$STAMP" || fail "stamp lacks toolkit_sha"
grep -q '^builder_model: a/b' "$STAMP" || fail "stamp does not record the init flags"
cp "$STAMP" "$TMP/stamp.bak"
ok "fresh scaffold wrote the provenance stamp with flags + toolkit SHA"

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
cmp -s "$TMP/stamp.bak" "$TMP/.agents/.toolkit-version" 2>/dev/null \
  || fail "second run touched the provenance stamp"
ok "re-run skipped all $files files, preserved local edits, marker + stamp untouched"
# restore the pristine render so the --update checks below start clean
mv "$TMP/feature.sentinel" "$TMP/.claude/commands/feature.md"

# --- 3. provenance stamp ------------------------------------------------------

# --- 4. --update (triage mode): clean target, flags defaulted from stamp ------
rc=0
bash "$ROOT/bin/init.sh" --update --target "$TMP" > "$TMP/upd1.log" 2>&1 || rc=$?
[ "$rc" = "0" ] || { cat "$TMP/upd1.log"; fail "--update exited $rc on a clean target, expected 0"; }
grep -q "all $files checked files match" "$TMP/upd1.log" || fail "--update summary missing on a clean target"
ok "--update: flag-free run defaults from the stamp; clean target exits 0"

# --- 5. --update: drift is summarized, exit 1, hunks only behind --diff -------
printf '\n' >> "$TMP/.agents/TEMPLATE.md"
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
rc=0
bash "$ROOT/bin/init.sh" --refresh-stamp --target "$TMP" > /dev/null 2>&1 || rc=$?
[ "$rc" = "0" ] || fail "--refresh-stamp failed"
! grep -q '^# touched' "$STAMP" || fail "--refresh-stamp did not rewrite the stamp"
grep -q '^toolkit_sha:' "$STAMP" || fail "rewritten stamp lost its fields"
ok "--refresh-stamp rewrites the provenance stamp (the only post-scaffold writer)"

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
VS="$TMP/scripts/verify-state.sh"
cat > "$TMP/.agents/T-01.md" <<'EOF'
**Status:** blocked

## Review verdicts

### Pass 1 — 2026-08-26 — verdict: CHANGES_REQUESTED

1. [high] a.js:1 — finding
EOF
"$VS" T-01 > /dev/null 2>&1 || fail "verify-state rejected a valid blocked-state file"
ok "verify-state accepts valid state file incl. blocked Status"

# 6a. Task class + decision source: absent = fine, junk = fails
cat > "$TMP/.agents/T-01.md" <<'EOF'
**Status:** blocked
**Task class:** TBD
**Class decided by:** maybe
EOF
"$VS" T-01 > /dev/null 2>&1 && fail "verify-state accepted bogus Task class / decision source"
printf '**Status:** blocked\n**Task class:** sensitive\n**Class decided by:** human\n' > "$TMP/.agents/T-01.md"
"$VS" T-01 > /dev/null 2>&1 || fail "verify-state rejected a valid class + decision source"
ok "verify-state validates Task class + Class decided by (absent ok, junk fails)"

printf '\n### Pass 3 — 2026-08-26 — verdict: PASS\n\nnone\n' >> "$TMP/.agents/T-01.md"
if "$VS" T-01 > /dev/null 2>&1; then
  fail "verify-state accepted a Pass 3 (two-loop cap breached)"
fi
ok "verify-state fails loudly on a third review pass"

# --- 6b. verify-state.sh: budgets and definition-of-done --------------------
# The budget counters and the done-gate are the structural half of the
# anti-thrash and delivery-contract rules; if they are advisory only, they
# are not rules. Each is checked on a file that is otherwise valid, so a
# failure here names exactly one cause.
cat > "$TMP/.agents/T-03.md" <<'EOF'
**Status:** in-review
**Review loop count:** 1 / 2
**Test-fix loops:** 5 / 2
**Spec bounces:** 0 / 1

## Review verdicts

### Pass 1 — 2026-08-26 — verdict: CHANGES_REQUESTED

1. [high] a.js:1 — finding
EOF
"$VS" T-03 2>&1 | grep -q 'test-fix loop budget exceeded'   || fail "verify-state did not catch a blown test-fix budget"
sed -i.bak 's|^\*\*Test-fix loops:\*\* 5 / 2|**Test-fix loops:** 1 / 2|' "$TMP/.agents/T-03.md"
"$VS" T-03 > /dev/null 2>&1 || fail "verify-state rejected a file with in-budget counters"
ok "verify-state enforces the loop budgets and passes when they are in range"

cat > "$TMP/.agents/T-04.md" <<'EOF'
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
python3 - "$TMP/.agents/T-04.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace('| AC2 | [ ] | Pass 1 — unverifiable from diff | no covering test |',
            '| AC2 | [ ] | waived by user 2026-08-26 | n/a |')
open(p,'w').write(s)
PY
"$VS" T-04 > /dev/null 2>&1 || fail "verify-state rejected 'done' with a properly waived criterion"
ok "verify-state refuses 'done' on an open criterion, accepts an explicit waiver"

# --- 7. verify-spec.sh -------------------------------------------------------
# The spec-side equivalent: structure only, run before the human sees a spec.
VSPEC="$TMP/scripts/verify-spec.sh"
cp "$TMP/.agents/TEMPLATE.md" "$TMP/.agents/T-05.md"
if "$VSPEC" T-05 > /dev/null 2>&1; then
  fail "verify-spec passed the raw template, which is entirely boilerplate"
fi
"$VSPEC" T-05 2>&1 | grep -q 'still the template placeholder'   || fail "verify-spec did not identify template boilerplate"
ok "verify-spec rejects an unfilled spec"

python3 - "$TMP/.agents/T-05.md" <<'PY'
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

python3 - "$TMP/.agents/T-05.md" <<'PY'
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
