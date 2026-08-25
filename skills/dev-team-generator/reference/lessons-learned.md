# Lessons learned

Each entry below cost something to learn — a live verification, a near-miss,
or an actual incident — before it became a rule. They're written generalized
(not OpenCode-specific) so they apply to whatever tool ends up dispatched.
When you port one of these into a generated file, port the *mechanism and
the reason*, not any tool-specific flag name that happens to appear here as
the worked example.

## 1. A "wide auto-approve" flag is opt-in per task, never a standing default

Many non-interactive CLI tools have some flag that auto-approves anything
not explicitly denied, instead of hanging forever on a permission prompt
nothing can answer (OpenCode's `--auto` is the worked example this toolkit
verified live). That flag is genuinely useful — it's what ends the
"dispatch hangs on an un-allowlisted command, someone notices, widens the
allowlist, retries" cycle — but it is also, by the tool's own admission
usually, "dangerous."

- Default is off.
- Turning it on for a task is the **user's** call, asked explicitly, bundled
  into whatever approval gate already exists (don't invent a second
  interruption point for it) — never the lead's or implementer's own
  judgement call, not even after a timeout.
- **Verify live, before trusting it, that the tool's own explicit deny-list
  still blocks even with the flag on.** Don't take the tool's docs' word for
  it. The verification this toolkit did: dispatch a throwaway agent with a
  deny-listed command, turn the auto-approve flag on, confirm the call is
  still refused and the refusal names the specific deny rule. If a tool's
  auto-approve flag turns out to bypass its own deny-list too, that's a
  materially different (and worse) risk profile than what's described
  above — find out before recommending it, not after.
- Record which tasks had it on, and why, in the state file — not just in
  the dispatch command.

## 2. A killed dispatch may not be a finished dispatch — check before reusing its session

If the dispatched tool has any concept of a server-side session/turn that
outlives the CLI client process (OpenCode's `--attach` sessions are the
worked example), then killing the *client* does not necessarily cancel the
*turn*. A killed-but-not-cancelled turn can leave an orphaned
in-progress message with no completion marker — and reusing that session
for the next call risks two calls racing on it, which is a real, previously
observed failure mode (two writes racing on the same session produced a
collision that looked like an unrelated server error).

- Bound every dispatch with a hard wall-clock timeout.
- On a timeout **your own wrapper caused**, actively cancel the server-side
  turn if the tool exposes a way to (an abort/cancel endpoint or command),
  using whatever session id the wrapper can determine — verify this live:
  confirm the cancelled turn actually shows as completed/aborted afterward,
  don't just assume the cancel call succeeding means the turn stopped.
  Once verified, retrying the same session immediately is safe.
- On a dispatch that was killed **some other way** — interrupted by hand,
  the host process manager stopped it, the machine slept — the same
  orphaned-turn risk applies but your wrapper's own auto-cancel-on-timeout
  logic never ran. Check the session's actual state (or just cancel it
  unconditionally, if that's cheap and idempotent) before reusing it. Don't
  assume "it's not running anymore because nothing is polling it" —
  verify, the way this toolkit verified via the tool's own session-state
  API: fetch the last message, confirm it either completed normally or
  show it explicitly aborted, before sending the next one into that
  session.

## 3. Don't assume a CLI streams its own output incrementally — verify before building anything that depends on it

An idle/no-output watchdog (kill a dispatch if its output file hasn't grown
in N seconds, on the theory that "no output" means "stuck") is an
attractive-looking hardening pattern. It is **only safe if the underlying
tool actually flushes output incrementally as it works.** This toolkit
built one, tested it against a synthetic harness (passed), then tested it
against the *real* installed tool doing genuinely long, successfully
progressing work — and found the tool's own CLI batches all output until
the entire turn completes, even with an explicit line-buffered format flag
and OS-level `stdbuf` forcing. The output file sat at zero bytes through
over a dozen seconds of real, correct work. Deploying the watchdog as
designed would have killed every long-but-successful run, which is strictly
worse than the flat timeout it was meant to improve on.

- If you're about to build anything whose correctness depends on "this
  tool streams output as it goes," check that assumption against the
  actual installed version of that tool, with genuinely long real work, not
  a quick synthetic test — synthetic tests can pass on the logic while the
  underlying I/O assumption is still wrong.
- If it turns out not to stream incrementally, a flat timeout (bounded,
  simple, no false-positive risk) is the better and current design — say so
  plainly rather than shipping the fancier mechanism anyway.
- If you do find a tool that streams incrementally and want to build an
  idle-watchdog for it, re-verify against that tool's actual version before
  reusing this note as precedent — the finding above is tool-and-version
  specific, not a general property of CLI tools.

## 4. Implementer testing: scoped to fast/deterministic, not banned, not unlimited

Don't swing to either extreme:

- **Not a full ban.** A deterministic local check (a type check, a linter,
  a test suite that runs in seconds) is cheap — CPU-seconds, not a paid
  LLM call — and catching an obvious break before it ever reaches the
  reviewer/tester saves a whole loop. Banning it outright optimizes for the
  wrong cost.
- **Not unlimited either.** Slow, environment-heavy suites (full e2e,
  integration against real external services) are the dedicated tester
  role's job, run once, independently, as the record the state file
  trusts. The implementer's own local run is informational — it does not
  replace the tester's run, and should say so explicitly in its own report
  rather than implying its self-check is the verified result.
- The actual distinction driving this: avoiding a second *paid agent
  call* re-verifying what the first one already claimed is the thing worth
  being economical about (per this skill's "verification is a script, not
  a sixth agent" principle) — a second **script run** is not that, and
  reasoning about the two as if they were the same cost is how this rule
  gets over-tightened into a full ban that then has to be walked back.

## 5. Not every reviewer finding is worth a full implementer loop

`CHANGES_REQUESTED` is the default routing back to the implementer — but a
finding that names no concrete code defect (e.g. "I can't confirm this
platform API is supported on the actual target from the docs I checked,
verify before shipping") isn't something a code change can address. Sending
it back anyway burns a review-loop slot on a call the implementer has no
action for.

- If a finding is genuinely non-actionable as a code change, route it to
  wherever it *can* be resolved instead (usually: the test/verification
  step, as an explicit thing to check against the real target) — but do
  this transparently, logged in the state file with the reasoning, not by
  silently downgrading the verdict. The user should be able to see and
  disagree with the call.
- This is a judgment call the lead makes on the evidence in hand, not a
  license to wave away a finding that's inconvenient — the bar is "no code
  change could address this," not "this seems minor."

## 6. Check for a real test harness before assuming only manual verification is possible

"No browser/runtime on `PATH`" is not the same as "no way to drive a real
instance of the target." A project may already have a managed/bundled
runtime (a test framework's own downloaded browser binaries, a container
image, a local emulator) that a plain `which <tool>` check won't find,
because it isn't meant to be found that way — and the project may already
have a *working* automated-testing convention for exactly this (an existing
`e2e/` directory, a CI config, a documented manual-checklist policy) that a
fresh dispatch, working from a narrower prompt, won't discover on its own.
Before concluding "this needs the user's own hands," check: does this
project already have automated infrastructure for driving the real target,
and does the current task's verification need actually fit what that
infrastructure can reach? If yes, use it — a real automated check against
the actual artifact is stronger evidence than asking a human to click
through the same thing by hand, and is worth the extra effort to wire up
correctly (get the exact selectors/shape right by reading the actual
generated UI/output, not by guessing).

## 7. Non-destructive scaffolding, with a path to reconcile later

Never silently overwrite a file the user or a prior run may have
customized. Skip-if-exists is the safe default for first generation; for a
later re-run against a project that's drifted from what this pipeline would
now generate, offer a diff-only mode — render the current version to a
temp location, `diff -u` against the live file, write nothing — so the
human (or an agent working with the human) can merge deliberately instead
of either blindly overwriting or blindly staying stale forever.

## 8. First-run, project-specific customization: ask once, then never again

A freshly generated pipeline's role/flow files start out generic — they
don't yet know this project's own sharp edges (a hard rule that isn't in
the root guidance file yet, a permission boundary worth calling out
explicitly). Rather than leaving that gap open indefinitely or re-asking
every run, gate a single customization prompt behind a marker written only
on first generation (never on a later re-run/update) and cleared only once
the human answers it. This keeps the ask-once property without needing
anything heavier than a marker file.

## 9. "Receipt not record" applies role-to-role — and is worth extending to the lead's own report, deliberately, not by default

Every worker role's reply to the lead should be short: a verdict line, a
pass/fail count, the one-line handoff field — never a second copy of what
it already wrote to the state file. This is settled and load-bearing (see
`reference/flow-example.md`).

Whether the **lead's own report to the human** should get the same
compression is a live, unresolved question this toolkit has raised but not
settled — the human is not re-reading a state file the way the next role
is, so some of the state file's content genuinely needs to reach them
somewhere, and over-compressing that report risks hiding the "blocked,
unverified, or needs a decision" signal the human actually needs to act on.
If you're generating a lead flow and asked to tighten its human-facing
report, treat this as a real design decision to make with the user, not an
obvious extension of the role-to-role rule — get their answer on what to
keep versus compress before changing it.
