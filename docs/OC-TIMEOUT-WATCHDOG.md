# oc.sh — the keep-alive watchdog (why a run is bounded, but not on a flat clock)

_Added 2026-09-10. Supersedes the "flat timeout is the current design"
conclusion in `skills/dev-team-generator/reference/lessons-learned.md` §3 —
see the update note there._

## The problem

`scripts/oc.sh` used a flat wall-clock kill: `timeout $OC_TIMEOUT opencode
run …`, default 600 s. That is wrong for the models the pipeline actually
runs:

- `opencode-go/glm-5.3-flash` (builder) and `opencode-go/kimi-k2.7-code`
  (reviewer) routinely do **20–60 minutes** of genuinely active work on a
  non-trivial task — one implementation, one two-pass review of a
  1000-line diff.
- A flat 600 s (or even 2400 s) `timeout` SIGTERMs those mid-tool-call. In
  one real session (resto-agent T-10) **every** dispatch needed
  `OC_TIMEOUT` raised by hand, and two still died mid-run.
- Bumping the flat number just trades false kills for the opposite failure:
  a genuinely wedged run (unanswered permission prompt, black-holed
  provider call) sits undetected for the whole inflated window.

## Why the obvious fixes don't work (verified against opencode 1.18.25)

| Signal | Result |
| --- | --- |
| `opencode run --format json` stdout / the `--raw-out` file growing | **Dead.** Buffers to end-of-turn. Observed: 0 bytes → one 304-byte early chunk → frozen through 80 s of real multi-file work → the entire 9 KB turn flushed at once on completion. This is lessons-learned §3's finding, re-confirmed. |
| `GET /event` or `GET /session/<id>/event` (SSE) | **Dead.** Emits only `server.connected` / `server.heartbeat`. No per-message / step / tool events ever reach these streams for an attached `opencode run` turn. |
| `GET /session/<id>` state — `time.updated`, `tokens`, `cost` | **Too coarse.** Advances only at some step boundaries; sat frozen through 80 s of active file-reading in testing. |
| `GET /session/<id>/message?limit=1` — the last message's body | **Works.** Its byte-fingerprint changes as parts are appended and streamed text grows (observed changing every ~10–50 s in a 96 s run), and it carries the `completed` timestamp. This is the signal the watchdog uses. It is also the same session-state API lessons-learned §2 already trusts for abort verification. |

## What the watchdog does

`oc.sh` backgrounds `opencode run` and, every `OC_POLL` seconds (default
20), fetches `GET $OC_SERVER/session/<id>/message?limit=1` and fingerprints
it as `<byte-size>:<md5>`. Any change resets an idle timer. The run is
aborted only when **either**:

1. the fingerprint has not changed for `OC_IDLE_TIMEOUT` seconds (default
   **600**) **and** the message has no `completed` timestamp — a real
   wedge; or
2. the absolute `OC_TIMEOUT` ceiling (default **2400**) is reached while
   the turn is still running.

On abort it `POST`s `/api/session/<id>/interrupt` (opencode v1 called this `/session/<id>/abort`; verified live on v1: 200,
idempotent) and exits **124**, with a stderr message that says which of the
two fired. A run that keeps making progress is never touched, however long
it takes.

Safety rails:

- The session id is resolved even for a fresh `--session`-less run
  (snapshot session ids before launch, diff after) — so the abort always
  has a target. This also closes the old "no session id known to abort"
  gap.
- If the session id can't be resolved within 60 s, or the message endpoint
  keeps returning non-JSON, the watchdog **disables itself** and the only
  bound is the `OC_TIMEOUT` ceiling — never worse than the old flat
  timeout.
- An outer `timeout $((OC_TIMEOUT + 300))` wraps the whole thing as an
  ultimate backstop against a wedged watchdog loop.

## Env

| Var | Default | Meaning |
| --- | --- | --- |
| `OC_TIMEOUT` | `2400` | Absolute ceiling, seconds. A still-progressing run is killed here; raise it for a job legitimately longer than 40 min. |
| `OC_IDLE_TIMEOUT` | `600` | Seconds the last message may stay byte-identical, while not completed, before the run is treated as wedged. 10× the worst active-gap observed in testing. |
| `OC_POLL` | `20` | Fingerprint poll interval, seconds. |

## How to test / verify

Prereq: `opencode serve` up (`scripts/team.sh`, or `opencode serve --port 4096`).

1. **Fast turn still works**
   ```
   printf 'reply with exactly: pong' | scripts/oc.sh --agent tester --model hcnsec/auto --text
   ```
   → prints `pong`, exit 0, one `oc.sh: session=ses_…` line.

2. **A long active run is NOT killed** (the regression this fixes)
   ```
   time ( printf 'Read every file under scripts/ and CLAUDE.md one at a time; for each write a detailed 6-bullet analysis. Be exhaustive, do not rush.' \
     | scripts/oc.sh --agent reviewer --model opencode-go/kimi-k2.7-code --text --raw-out /tmp/t.jsonl )
   ```
   → runs for minutes, exit 0, real output. **Not** `ABORTED — … did not change for 600s`. (resto-agent verified a 2-minute run here.)

3. **The watchdog still catches a wedge** — force a tiny idle window against a run that stalls
   ```
   OC_IDLE_TIMEOUT=30 OC_POLL=10 scripts/oc.sh --agent builder --model opencode-go/glm-5.3-flash \
     --prompt 'Run this and report its output: <a command that hangs, or point at a black-holed endpoint>'
   ```
   → exit 124 within ~40 s; stderr `oc.sh: ABORTED — the session's last message did not change for 30s …` + `Aborted server-side session ses_…`. Then confirm the turn actually stopped:
   ```
   curl -s $OC_SERVER/session/<id>/message?limit=1 | python3 -c 'import json,sys;print(json.load(sys.stdin)[-1]["info"]["time"])'
   ```
   → a `completed` timestamp is present (not an open turn).

4. **The ceiling still bounds a runaway**
   ```
   OC_TIMEOUT=60 scripts/oc.sh --agent reviewer --model opencode-go/kimi-k2.7-code --prompt '<a task that needs >60s>'
   ```
   → exit 124, stderr `ABORTED — the run hit the absolute 60s ceiling`.

5. **Portability**: `bash -n scripts/oc.sh` clean. Needs `python3`, `curl`,
   `md5`/`md5sum`, GNU `timeout`/`gtimeout` (already required).

Tests 1, 2, 4 are deterministic. Test 3 needs a reproducible stall; if you
can't induce one, the loop logic is short enough to read — `KILL_REASON=idle`
is set only when `message_fp` is byte-identical for `OC_IDLE_TIMEOUT` **and**
`turn_completed` returns false.

## If a future opencode changes this

The message-body signal is **tool-and-version specific** (opencode 1.18.25,
Sep 2026). Re-run tests 2 and 3 against any new opencode before trusting it.
If `GET /session/<id>/message?limit=1` ever stops tracking sub-turn
progress, fall back to a higher flat `OC_TIMEOUT` and say so plainly —
per lessons-learned §3, a bounded flat timeout with no false-positive risk
beats a fancier mechanism built on a broken assumption.
