# Keeping a scaffolded project up to date with this toolkit

> **Status: implemented.** Stages 1–5 below are live as of v0.3.0:
> `init.sh` writes the provenance stamp and defaults `--update` flags from
> it; `--update` is a triage tool (summary-first, `--diff`/`--only`,
> exit 0/1); `CHANGELOG.md` carries impact-tagged entries; the first real
> migration lives in `migrations/01-delivery-contract.md`; and
> `/toolkit-update` and `$toolkit-update` are rendered into scaffolded
> projects for Claude and Codex respectively. This file is now
> reference documentation for how it works and why.

`bin/init.sh --update` already does the mechanical half: render the
current templates, `diff -u` each one against the live file in the target,
write nothing. What is missing is everything *around* it — which is why
downstream projects drift and stay drifted.

## Adding the project dashboard

New scaffolds include `scripts/dashboard`. For an existing stamped project,
run these commands from its root after updating your toolkit checkout:

```bash
bash /path/to/agent-toolkit/bin/init.sh --update --target . --only scripts/dashboard
bash /path/to/agent-toolkit/bin/init.sh --target .
./scripts/dashboard
```

The first command previews only the dashboard and writes nothing: exit 1
means it is missing or differs. The second loads settings from the provenance
stamp and installs missing files without overwriting existing customizations.
It may add other missing upstream files too. Existing dashboard changes are
reconciled through `/toolkit-update`, not overwritten by re-running init.

The installed viewer is self-contained and requires only Python 3.8+ on
macOS/Linux. Use `./scripts/dashboard --once` for a text snapshot or
`--project /path/to/repo` to view another project. No Herdr or model calls are
needed. See [the team guide](TEAM.md#task-dashboard-no-launcher-required) for
controls and status limitations.

## Bootstrapping a newly supported lead

An update command cannot bootstrap itself into a project that does not have it
yet. After pulling the toolkit checkout, an existing stamped project can add
newly introduced template files without repeating its original flags:

For a runtime still under `.agents/`, apply
[migration 02](../migrations/02-pipeline-directory.md) between inspection and
bootstrap. Update triage reads the legacy stamp; a plain run refuses to create
new runtime state before migration is complete.

```bash
<toolkit-checkout>/bin/init.sh --update --target <project>  # inspect first
<toolkit-checkout>/bin/init.sh --target <project>           # missing files only
```

The plain run now loads values from `.pipeline/.toolkit-version` and retains
`render()`'s skip-if-exists guarantee. A Claude user whose older scaffold
already has `/toolkit-update` can let that command perform these steps. A
Codex-only user upgrading from before Codex support must run the shell bootstrap
once; afterward `$toolkit-update` is installed and handles future updates. A
pre-v0.3.0 scaffold has no stamp, so it still follows README's one-time flag
recovery procedure.

This is the plan to close that, in five stages. Stages 1–2 are the ones
worth doing first; each stage is useful on its own and none blocks the
next.

## What is broken today, precisely

Run `--update` against a project scaffolded three months ago and you hit
four problems in a row:

1. **You must remember the original flags.** Pass a different
   `--builder-model` than the original init and every substituted line in
   every file shows up as diff noise. Nothing recorded what was used.
2. **No baseline.** There is no record of *which version* of the toolkit
   the project was scaffolded from, so "what changed since I took this"
   is unanswerable — you get a diff against your local edits, which
   conflates upstream changes with your own customizations.
3. **No signal.** Twelve files of raw `diff -u` with no indication that
   one hunk is a permission-block change you must merge today and another
   is a typo fix in a comment. Every upstream change looks equally
   urgent, so none of them get merged.
4. **No migrations.** When the state-file contract gains a field or a
   section — as it has now, substantially (the acceptance-criteria ledger,
   three budget counters, a split blocked status) — existing
   `.pipeline/T-*.md` files in flight silently lack it, and nothing says so.
   Stage 4 below now carries the real migration note for that change.

Consequence: `--update` is technically correct and practically unused. A
project scaffolds once and never upgrades, which means every hardening
lesson this toolkit earns after the scaffold date stays upstream.

---

## Stage 1 — Stamp provenance at scaffold time

**The single highest-value change.** `init.sh` writes, on a real scaffold:

```
.pipeline/.toolkit-version
```

```
toolkit_sha:   79f0e14
toolkit_tag:   v0.2.0
scaffolded:    2026-08-26
project_name:  my-project
claude_model:  sonnet
builder_model: hcnsec/kimi-k2.7-code
reviewer_model: hcnsec/glm-5.2
reviewer_fallback_model: sonnet
tester_model:  hcnsec/deepseek-v4-flash
test_dir:      e2e
```

Then:

- **`--update` defaults every flag from this file.** `bin/init.sh --update
  --target .` becomes the whole command. Problem 1 disappears, and with it
  the diff noise that makes the output unreadable.
- **`--update` prints the baseline** — "scaffolded from `79f0e14`
  (2026-08-26); toolkit is now at `a1b2c3d` (14 commits ahead)". Problem 2
  disappears.
- A successful merge updates the stamp; `--update` alone never writes it.
- It is committed (unlike `.pipeline/.oc-port`) — it describes the project,
  not the laptop.

Follow the existing conventions: written only when `FRESH_SCAFFOLD` was
true before any `render()` ran, same ordering rule as
`.needs-customization`; never written by `--update`. Add one smoke case.

**Cost:** ~30 lines in `init.sh`, one smoke case.

## Stage 2 — Version the toolkit and classify every change

There are currently **zero git tags**. Downstream has nothing to pin to.

**Tag releases**, with the version number meaning something specific to
this toolkit rather than to code:

| Bump | Means | Downstream obligation |
| --- | --- | --- |
| **MAJOR** | The state-file contract, a role's authority, or a script's interface changed | Must merge deliberately; may need a migration (Stage 4) |
| **MINOR** | New template, script, flag, or role rule | Should merge at the next task boundary |
| **PATCH** | Prose, docs, comments, formatting | Merge whenever, or never |

**`CHANGELOG.md`, with an impact tag per entry** — this is what makes a
diff triage-able:

```markdown
## v0.3.0 — 2026-09-xx
- `[contract]`  state file: added *Reviewer for this task* / *Tester for
                this task*. Migration: 03-reviewer-tester-fields.md
- `[safety]`    builder: removed blanket `git *: allow`; enumerated
                read-only git verbs. Merge this one now.
- `[process]`   feature.md: ask before splitting a very large task
- `[docs]`      README: quick-start blocks merged
```

Four tags, in descending order of "drop what you are doing":
`contract` › `safety` › `process` › `docs`. A downstream operator (or
their AI lead) reads the changelog *first* and the diffs second — which
inverts today's experience, where the diff is all you get.

**Cost:** a file plus the discipline to append to it. It is the same
"write down why" discipline the toolkit already applies everywhere else.

## Stage 3 — Make `--update` a triage tool, not a diff dump

With Stages 1–2 in place, `--update` gets three cheap upgrades:

- **Summary first.** List changed files with their changelog impact tag
  before printing any hunks:

  ```
  init.sh: 3 of 12 files differ from toolkit v0.3.0 (you are on v0.2.0)
    [safety]   .opencode/agents/builder.md      — permission block
    [contract] .pipeline/TEMPLATE.md             — 2 new fields
    [docs]     scripts/team.sh                 — comment only
  run with --diff to see hunks, or --diff <path> for one file
  ```
- **`--only <path>`** to diff one file, so merging can be done one file at
  a time rather than all-or-nothing.
- **Meaningful exit codes:** `0` clean, `1` drift. That is all a
  downstream project needs to run `init.sh --update` in its own CI weekly
  (or in `/loop`) and open an issue when the toolkit moves — the
  difference between pull-when-you-remember and being told.

**Cost:** ~40 lines, all in the existing `render()` update branch.

## Stage 4 — Migrations for contract changes

Only `[contract]` changes need this, which is rare by design. Ship a note
per contract change under `migrations/`. **There is now a real one to
write** — the delivery-contract work applied from `REVIEW-2.md` changed the
state file more than anything since the toolkit was extracted:

```markdown
# 01 — Delivery contract (ledger, budgets, split blocked status)
Applies to: .pipeline/TEMPLATE.md, scripts/verify-state.sh, every role file,
            and any in-flight .pipeline/T-*.md

New header fields (add under **Implementer for this task:**):
  **Reviewer for this task:** / **Tester for this task:**
  **Test-fix loops:** 0 / 2      **Spec bounces:** 0 / 1
  **Blocked since:** —

New section, under Acceptance criteria:
  ### Acceptance criteria ledger — one row per AC, columns:
  | AC | Met? | Reviewer evidence | Test evidence |

Status enum: `blocked` split into `blocked:question` / `blocked:spec`.
  Bare `blocked` still validates — it is kept as the legacy value precisely
  so in-flight files don't break. Nothing to do for existing tasks.

New script: scripts/verify-spec.sh (run at the end of step 1).

Safe to skip for tasks already at Status `done`.
```

**Backward compatibility, deliberately:** the new `verify-state.sh` treats
every new field as optional — an absent budget counter is skipped rather
than failed, an absent ledger means the done-gate has nothing to check, and
bare `blocked` still validates. So a downstream project can take the new
script before it takes the new template, and its in-flight tasks keep
passing. What it does *not* get until it takes the template is the
guarantee: no ledger means nothing refuses a premature `done`. That is the
difference between the checks being installed and the checks being load-
bearing, and it is worth saying out loud in the changelog entry.

Short, literal, and hand-appliable. Do **not** build a migration runner —
these are two-line edits a few times a year, and a runner is exactly the
kind of machinery this toolkit is right to refuse. The value is the note
existing at all, so an in-flight task does not silently lack a field that
`verify-state.sh` will later check for.

## Stage 5 — A lead update command in the target project

The AI-assisted merge path the README already gestures at ("hand the diff
to your AI lead and ask it to reconcile"), made into a real, templated
command/skill rendered by `init.sh` alongside each lead's feature entry point:

1. Read `.pipeline/.toolkit-version` for the baseline.
2. Run `bin/init.sh --update` (flags come from the stamp).
3. Read the toolkit's `CHANGELOG.md` for entries after the baseline.
4. Work the diffs **in impact order** — `contract`, then `safety`, then
   `process`, then `docs`.
5. For each: show the user what changed upstream, what this project
   customized locally, and the proposed merge. **Never silently
   overwrite a local customization** — that is the whole reason
   `render()` is skip-if-exists.
6. **Hard stop on permission blocks.** Any hunk touching a `permission:`
   or `tools:` block is presented, never auto-applied, and carries the
   toolkit's standing rule: verify it live against the real server before
   trusting it.
   Treat a new or changed structural script (`verify-state.sh`,
   `verify-spec.sh`, `promote-findings.sh`) as `[safety]` too: these are
   what the pipeline's guarantees actually rest on, and a project running
   an old `verify-state.sh` against a new template silently loses the
   done-gate rather than failing loudly about it. This toolkit's own history is the argument — a
   blanket-deny that read correctly and did not enforce.
7. Update the stamp to the new SHA/tag when the merge is accepted.
8. Report merged / skipped / deferred, and record it in the project's
   Decisions log.

Run it **at a task boundary, never mid-task** — the state file contract is
live while a task is in flight, and changing the template under a running
task is exactly how an in-flight `T-<id>` ends up half on each contract.

---

## Upstream's own half of this

A downstream project can only merge what upstream shipped coherently. This
toolkit keeps several hand-synced copies of the same rules (three of the
lead's flow, two of the state-file contract), and hand-syncing failed twice
on consecutive commits before `test/invariants.sh` existed to check it —
including one rule that a review file recorded as applied and that was not
actually in the file.

That test is the upstream-side counterpart to everything above: it asserts
one grep per (rule, file) pair and runs in CI, so a release cannot ship a
rule that reached only two of its three homes. Add a rule to a flow copy and
you add one line to its table in the same commit. Without that, a downstream
project merging faithfully still inherits whichever copy happened to be
stale.

## Rejected: submodule or subtree

Considered and deliberately not recommended.

A git submodule or subtree would make updates trivial (`git pull`) — and
would break the property the whole design rests on: **every generated file
is meant to be edited locally.** Projects are expected to widen the
reviewer's permission block after verifying it live, fill role files with
their own project-specific pitfalls, and add steps to `feature.md`. A
submodule makes those edits either impossible or upstream-hostile.

Copy-with-provenance is the correct model for generated-then-customized
files. What is missing is not a different distribution mechanism — it is
the provenance stamp and the changelog that make merging a copy tractable.
Stages 1–2 supply exactly that.

---

## Recommended cadence for a downstream project

| When | Do |
| --- | --- |
| Weekly, in CI or a `/loop` | `bin/init.sh --update --target .` — exit 1 means the toolkit moved |
| On a `[safety]` entry | Merge at the next task boundary, verify permission changes live |
| On a `[contract]` entry | Merge before starting the next task; apply the migration to in-flight state files |
| On `[process]` / `[docs]` | Batch them; merge whenever convenient |
| Never | Mid-task |

## Suggested build order

Stage 1 → Stage 2 → Stage 3 → Stage 5 → Stage 4 as needed.

Stages 1 and 2 alone remove the two things that actually stop people from
upgrading (remembering the flags, and not knowing what matters). Stages 3
and 5 are convenience on top of a mechanism that already works. Stage 4 is
paperwork that only earns its keep when a contract change actually ships.
