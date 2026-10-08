#!/usr/bin/env bash
# Opt-in real Codex sandbox check. No model calls. Run outside another sandbox
# if the OS refuses nesting. Requires the unified `codex sandbox` CLI (0.160).
set -eu
TMP="$(mktemp -d "${TMPDIR:-/tmp}/toolkit-sandbox.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.pipeline" "$TMP/.agents/skills" "$TMP/.codex" "$TMP/.git"
# shellcheck disable=SC2016 # literal backticks/quotes are intentional
codex sandbox --permission-profile :workspace -C "$TMP" -- /bin/bash -c '
  set -eu
  printf probe > .pipeline/probe
  for path in .agents/skills/probe .codex/probe .git/probe; do
    if (printf probe > "$path") 2>/dev/null; then
      printf "FAIL: protected path was writable: %s\n" "$path" >&2
      exit 1
    fi
  done
  printf "codex-sandbox: writable runtime and protected instructions/Git verified\n"
'
[ -f "$TMP/.pipeline/probe" ]

# The generated execution rules: the dispatch wrappers are allowed outside the
# sandbox; anything else (Git writes, the sandbox-testing preflight, an indirect
# `bash scripts/…` invocation, a look-alike name) gets no allow decision.
RULES="$(cd "$(dirname "$0")/.." && pwd)/templates/codex/rules/pipeline.rules.tmpl"
decision() { codex execpolicy check --rules "$RULES" -- "$@" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("decision","none"))'; }
for allowed in "scripts/oc.sh --status" "scripts/bg-dispatch.sh wait T-1 builder 540" \
  "scripts/claude-review.sh T-1 1" "scripts/verify-models.sh"; do
  # shellcheck disable=SC2086 # word splitting into argv is the point
  [ "$(decision $allowed)" = allow ] || { printf 'FAIL: rules do not allow: %s\n' "$allowed" >&2; exit 1; }
done
for denied in "git push" "git commit -m x" "scripts/codex-preflight.sh" "bash scripts/oc.sh --status" "scripts/oc.sh.evil"; do
  # shellcheck disable=SC2086
  [ "$(decision $denied)" != allow ] || { printf 'FAIL: rules allow: %s\n' "$denied" >&2; exit 1; }
done
printf 'codex-sandbox: execution rules allow only the dispatch wrappers\n'
