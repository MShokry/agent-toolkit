#!/usr/bin/env bash
# Opt-in real Codex sandbox check. No model calls. Run outside another sandbox
# if the OS refuses nesting. Requires the unified `codex sandbox` CLI (0.160).
set -eu
TMP="$(mktemp -d "${TMPDIR:-/tmp}/toolkit-sandbox.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.pipeline" "$TMP/.agents/skills" "$TMP/.codex" "$TMP/.git"
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
