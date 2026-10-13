# OpenCode dispatch watchdog

`.agent-pipeline/bin/oc.sh` bounds dispatches with an idle detector and an absolute ceiling.
It uses `opencode run --server` and authenticated `opencode api` calls. It does
not infer progress from transcript-file growth, which may be buffered.

## Current contract

| Variable | Default | Meaning |
| --- | --- | --- |
| `OC_TIMEOUT` | `2400` | Absolute ceiling in seconds; raise explicitly for longer work |
| `OC_IDLE_TIMEOUT` | `600` | Unchanged newest message while a turn is incomplete |
| `OC_POLL` | `20` | Poll interval in seconds |

The wrapper fingerprints the newest message from
`GET /api/session/<id>/message`, selecting by creation time rather than assuming
response order or server-side limits. A changing fingerprint resets the idle
timer. An incomplete, unchanged message can trigger an idle abort; reaching the
ceiling while polling can trigger a ceiling abort. An outer timeout at
`OC_TIMEOUT + 300` is a final backstop.

If a fresh session cannot be identified, polling stops and the outer timeout
remains. Message-read failures do not establish progress or completion; inspect
the API/runtime before diagnosing a permission stall. Do not assume every
ceiling hit proves productive work.

On timeout the wrapper attempts `POST /api/session/<id>/interrupt` when an ID is
known and exits 124. The interrupt is best-effort: confirm the server-side turn
has stopped before retrying. A killed client is not proof of a cancelled turn.
Manual interruption or the lead's own tool timeout may bypass wrapper cleanup.

## Live verification (disposable project)

Start an authenticated server with `.agent-pipeline/bin/team.sh`, or export
`OPENCODE_PASSWORD` when launching it manually. Set `OC_SERVER` when needed.
Choose available model IDs with `opencode models`.

Create task directories and write each prompt before dispatch:

```bash
mkdir -p .agent-pipeline/prompts/T-watchdog .agent-pipeline/logs/T-watchdog
.agent-pipeline/bin/oc.sh --agent tester --model <available-model> --text \
  --prompt-file .agent-pipeline/prompts/T-watchdog/tester-1.md \
  --raw-out .agent-pipeline/logs/T-watchdog/tester-1.jsonl
```

Use a new positive pass number on every attempt, including failures. Check:

1. A short prompt returns its expected output, exit 0, and a session receipt.
2. A long active read-only task survives idle intervals below the ceiling.
3. A safe reproducible stall in a disposable environment triggers idle abort
   with a deliberately small idle window; a permission prompt is not the only
   possible cause. Never enable `--auto` or widen permissions as an automatic fix.
4. A task longer than an explicitly shortened ceiling exits 124.
5. After any abort, inspect the session's newest message/turn through
   `opencode api GET /api/session/<id>/message --server <url>` and verify that
   work actually stopped before session reuse.

These are manual runtime checks, not deterministic CI tests. Reverify the
message signal, response shape, authentication, and cancellation behavior after
runtime upgrades. See [PERMISSIONS.md](PERMISSIONS.md) for permission checks.
