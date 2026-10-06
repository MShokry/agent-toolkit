#!/usr/bin/env bash
# Behavioral tests of the launcher/hooks/preflight. No model calls, daemon,
# authentication, or running OpenCode server; external CLIs are test doubles.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/toolkit-codex.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
fail() { printf 'codex: FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'codex: ok — %s\n' "$*"; }
bash "$ROOT/bin/init.sh" --target "$TMP" --project-name codex-test \
  --codex-model test-lead --codex-reasoning high \
  --codex-planner-model test-planner --codex-planner-reasoning medium > "$TMP/init.log" 2>&1
python3 - "$TMP" <<'PY'
import json, pathlib, sys, tomllib
root = pathlib.Path(sys.argv[1])
agent = tomllib.loads((root / '.codex/agents/planner.toml').read_text())
assert agent['model'] == 'test-planner'
assert agent['model_reasoning_effort'] == 'medium'
assert agent['sandbox_mode'] == 'workspace-write'
hooks = json.loads((root / '.codex/hooks.json').read_text())
assert set(hooks['hooks']) == {'SessionStart', 'UserPromptSubmit'}
assert '.pipeline/T-' in agent['developer_instructions']
assert 'codex_planner_model: test-planner' in (root / '.pipeline/.toolkit-version').read_text()
PY
bash "$ROOT/bin/init.sh" --update --target "$TMP" > "$TMP/update.log" 2>&1 \
  || fail "Codex settings did not round-trip through the stamp"
ok "valid TOML/hooks and independent lead/planner settings round-trip"

FAKEBIN="$TMP/fakebin"
mkdir "$FAKEBIN"
cat > "$FAKEBIN/codex" <<'SH'
#!/usr/bin/env bash
set -eu
if [ "${1:-}" = --version ]; then echo 'codex-cli 0.160.0'; exit 0; fi
if [ "${1:-}" = features ]; then
  printf 'hooks stable %s\nmulti_agent stable true\n' "${FAKE_HOOKS:-true}"; exit 0
fi
if [ "${1:-}" = resume ] && [ "${2:-}" = --help ]; then echo '--no-daemon'; exit 0; fi
printf '%s\n' "$@" > "$FAKE_ARGS"
if [ "${1:-}" = resume ]; then
  [ "${FAKE_RESUME_FAIL:-0}" = 0 ] || exit 9
  export FAKE_SESSION_ID="${!#}"
fi
[ "${FAKE_NO_HOOK:-0}" = 0 ] || exit 0
HOOK="$(python3 -c 'import json; print(json.load(open(".codex/hooks.json"))["hooks"]["SessionStart"][0]["hooks"][0]["command"])')"
python3 -c 'import json,os; print(json.dumps({"session_id":os.environ["FAKE_SESSION_ID"], "cwd":os.getcwd(), "hook_event_name":"SessionStart"}))' \
  | bash -c "$HOOK"
SH
cat > "$FAKEBIN/opencode" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_OC_ARGS"
exit "${FAKE_API_FAIL:-0}"
SH
cat > "$FAKEBIN/timeout" <<'SH'
#!/usr/bin/env bash
shift
exec "$@"
SH
chmod +x "$FAKEBIN/"*
export PATH="$FAKEBIN:$PATH" FAKE_ARGS="$TMP/args" FAKE_OC_ARGS="$TMP/oc-args"
export FAKE_SESSION_ID=thread-one
LEAD="$TMP/scripts/codex-lead.sh"
bash "$LEAD" first > "$TMP/lead.log" 2>&1 || fail "fresh lead did not capture its id"
[ "$(cat "$TMP/.pipeline/.codex-session-id.first")" = thread-one ] || fail "wrong captured id"
grep -qx test-lead "$FAKE_ARGS" || fail "lead model not passed"
grep -qx 'model_reasoning_effort="high"' "$FAKE_ARGS" || fail "reasoning not passed"
grep -qx -- --no-daemon "$FAKE_ARGS" || fail "hooks could inherit a different daemon environment"
export FAKE_SESSION_ID=unrelated-latest
bash "$LEAD" first > "$TMP/lead.log" 2>&1 || fail "pinned resume failed"
grep -qx resume "$FAKE_ARGS" || fail "did not resume the pinned thread"
grep -qx thread-one "$FAKE_ARGS" || fail "did not resume the pinned thread"
! grep -qx -- --last "$FAKE_ARGS" || fail "launcher used latest-thread lookup"
ok "resume pins the exact thread despite unrelated repository conversations"

export FAKE_SESSION_ID=thread-two
bash "$LEAD" second > "$TMP/lead.log" 2>&1 || fail "second team launch failed"
[ "$(cat "$TMP/.pipeline/.codex-session-id.second")" = thread-two ] || fail "teams share a pin"
bash "$LEAD" first --fresh > "$TMP/lead.log" 2>&1 || fail "explicit fresh failed"
[ "$(cat "$TMP/.pipeline/.codex-session-id.first")" = thread-two ] || fail "fresh did not replace its own pin"
ok "team names are isolated and explicit fresh replaces only the selected pin"

if FAKE_RESUME_FAIL=1 bash "$LEAD" first > "$TMP/lead.log" 2>&1; then fail "failed resume silently started a fresh conversation"; fi
[ "$(cat "$TMP/.pipeline/.codex-session-id.first")" = thread-two ] || fail "failed resume destroyed its pin"
[ ! -d "$TMP/.pipeline/.codex-lead-lock.first" ] || fail "failed resume leaked its lock"
if FAKE_NO_HOOK=1 bash "$LEAD" unpinned > "$TMP/lead.log" 2>&1; then fail "missing hook capture was accepted"; fi
rm -f "$FAKE_ARGS"
if bash "$LEAD" unpinned > "$TMP/lead.log" 2>&1; then fail "unpinned restart accepted"; fi
[ ! -f "$FAKE_ARGS" ] || fail "unpinned restart reached Codex instead of requiring recovery"
mkdir "$TMP/.pipeline/.codex-lead-lock.locked"
if bash "$LEAD" locked > "$TMP/lead.log" 2>&1; then fail "concurrent writer accepted"; fi
if bash "$LEAD" '../escape' > "$TMP/lead.log" 2>&1; then fail "unsafe team name accepted"; fi
ok "failed resume, absent hooks, concurrent leads, and unsafe names fail closed"

python3 - "$TMP" <<'PY'
import json, os, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
def hook(event, team='hook-test'):
    return subprocess.run([sys.executable, str(root/'scripts/codex-session.py')],
        input=json.dumps(event), text=True, capture_output=True,
        env={**os.environ, 'TEAM_CODEX_SESSION':team})
event = {'session_id':'hook-one', 'cwd':str(root), 'hook_event_name':'UserPromptSubmit'}
assert hook(event).returncode == 0
assert hook(event).returncode == 0  # idempotent across turns/compactions
assert hook({**event, 'session_id':'hook-two'}).returncode != 0
assert hook({**event, 'cwd':'/'}).returncode != 0
assert hook({**event, 'session_id':'../escape'}).returncode != 0
assert hook(event, '').returncode == 0
assert (root/'.pipeline/.codex-session-id.hook-test').read_text().strip() == 'hook-one'
PY
ok "real hook handler validates event data, refuses replacement, and ignores ordinary chats"

PREFLIGHT="$TMP/scripts/codex-preflight.sh"
OC_SERVER=http://localhost:4999 bash "$PREFLIGHT" > "$TMP/preflight.log" 2>&1 || fail "valid preflight failed"
grep -qx http://localhost:4999 "$FAKE_OC_ARGS" || fail "preflight ignored OC_SERVER"
if FAKE_API_FAIL=1 bash "$PREFLIGHT" > "$TMP/preflight.log" 2>&1; then fail "preflight ignored inaccessible API"; fi
grep -q 'authentication, or sandbox network policy' "$TMP/preflight.log" || fail "preflight obscured the blocked operation"
if FAKE_HOOKS=false bash "$PREFLIGHT" > "$TMP/preflight.log" 2>&1; then fail "preflight ignored disabled hooks"; fi
grep -q 'hooks capability is unavailable or disabled' "$TMP/preflight.log" || fail "disabled capability not identified"
cat > "$FAKEBIN/mktemp" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$FAKEBIN/mktemp"
if bash "$PREFLIGHT" > "$TMP/preflight.log" 2>&1; then fail "preflight accepted blocked state writes"; fi
grep -q 'cannot write .pipeline' "$TMP/preflight.log" || fail "write failure did not name its path"
rm "$FAKEBIN/mktemp"
ok "preflight checks actual writes and authenticated API access, including failures"

# A legacy stamp remains readable for triage; init must not split the runtime.
mkdir -p "$TMP/.agents"
mv "$TMP/.pipeline/TEMPLATE.md" "$TMP/.agents/TEMPLATE.md"
mv "$TMP/.pipeline/.toolkit-version" "$TMP/.agents/.toolkit-version"
cp "$TMP/.agents/.toolkit-version" "$TMP/legacy-stamp"
if bash "$ROOT/bin/init.sh" --target "$TMP" > "$TMP/legacy.log" 2>&1; then fail "bootstrap accepted unmigrated runtime"; fi
grep -q '02-pipeline-directory' "$TMP/legacy.log" || fail "migration not identified"
rc=0
bash "$ROOT/bin/init.sh" --update --target "$TMP" > "$TMP/legacy.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "legacy read-only triage did not report drift"
cmp -s "$TMP/legacy-stamp" "$TMP/.agents/.toolkit-version" || fail "triage changed the legacy baseline"
[ ! -f "$TMP/.pipeline/TEMPLATE.md" ] || fail "triage wrote a second runtime"
ok "legacy baseline is readable, triage is read-only, and unmigrated bootstrap is refused"

# The OpenCode V2 role path migration must not create duplicate role trees.
LEGACY_AGENT="$TMP/legacy-agent"
mkdir "$LEGACY_AGENT"
bash "$ROOT/bin/init.sh" --target "$LEGACY_AGENT" --project-name legacy-agent > "$TMP/legacy-agent.log" 2>&1
mv "$LEGACY_AGENT/.opencode/agents" "$LEGACY_AGENT/.opencode/agent"
if bash "$ROOT/bin/init.sh" --target "$LEGACY_AGENT" > "$TMP/legacy-agent.log" 2>&1; then fail "bootstrap accepted the legacy singular OpenCode role layout"; fi
grep -q '03-opencode-v2-agents-directory' "$TMP/legacy-agent.log" || fail "OpenCode role-path migration not identified"
mv "$LEGACY_AGENT/.pipeline/.toolkit-version" "$LEGACY_AGENT/stamp.hold"
rc=0
bash "$ROOT/bin/init.sh" --update --target "$LEGACY_AGENT" > "$TMP/legacy-agent.log" 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "legacy OpenCode role layout triage did not report drift"
grep -q 'BUILDER_MODEL: opencode-go/glm-5.3-flash' "$TMP/legacy-agent.log" || fail "stamp-less recovery did not read the legacy OpenCode role path"
[ ! -d "$LEGACY_AGENT/.opencode/agents" ] || fail "read-only triage created a second OpenCode role tree"
ok "legacy OpenCode role layout is readable for triage and refused for bootstrap"

# Defaults preserve local model choices; existing instructions/hooks/skills survive.
DEFAULT="$TMP/default"
mkdir "$DEFAULT"
bash "$ROOT/bin/init.sh" --target "$DEFAULT" --project-name defaults > "$TMP/default.log" 2>&1
! grep -q '^model = ' "$DEFAULT/.codex/agents/planner.toml" || fail "default planner pins a model"
! grep -q '^model_reasoning_effort = ' "$DEFAULT/.codex/agents/planner.toml" || fail "default planner pins reasoning"
export FAKE_SESSION_ID=default-thread
bash "$DEFAULT/scripts/codex-lead.sh" defaults > "$TMP/default.log" 2>&1 || fail "inherited-settings launch failed"
! grep -qx -- --model "$FAKE_ARGS" || fail "default launcher overrides the configured model"
! grep -qx -- -c "$FAKE_ARGS" || fail "default launcher overrides configured reasoning"
printf '\nLOCAL RULE\n' >> "$DEFAULT/AGENTS.md"
printf '\n' >> "$DEFAULT/.codex/hooks.json"
printf '\nLOCAL SKILL RULE\n' >> "$DEFAULT/.agents/skills/delegate/SKILL.md"
cp "$DEFAULT/.codex/hooks.json" "$TMP/hooks-before"
bash "$ROOT/bin/init.sh" --target "$DEFAULT" > "$TMP/default.log" 2>&1
grep -q 'LOCAL RULE' "$DEFAULT/AGENTS.md" || fail "existing project instructions were overwritten"
grep -q 'LOCAL SKILL RULE' "$DEFAULT/.agents/skills/delegate/SKILL.md" || fail "supporting skill customization was overwritten"
cmp -s "$TMP/hooks-before" "$DEFAULT/.codex/hooks.json" || fail "existing hooks were overwritten"
if bash "$ROOT/bin/init.sh" --target "$DEFAULT" --codex-planner-reasoning invalid > "$TMP/default.log" 2>&1; then fail "invalid reasoning accepted"; fi
ok "inheritance is preserved, invalid settings are rejected, and existing instructions/hooks/skills survive"

printf '\ncodex: all behavioral checks passed\n'
