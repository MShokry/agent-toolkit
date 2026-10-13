# Verify permissions before trusting them

Generated permission rules are guardrails, not filesystem isolation. This
toolkit has not established live enforcement for every generated role on the
installed OpenCode version, with or without `--auto`.

## Live verification

1. Use a disposable project, non-production credentials, and the exact generated
   agent files. Do not normalize or hand-copy a suspect file while testing it.
2. Restart/reload the runtime after configuration changes so cached agent rules
   cannot produce a false-clear result. Inspect the resolved rules:

   ```bash
   opencode api GET /api/agent --server <url> --param directory=<repo-root>
   ```

   Authenticate through the same OpenCode context as the worker. Do not print
   passwords or tokens. Check the actual role and expected allow/ask/deny rules.
3. Dispatch the role and try a safe allowed action and a safe disallowed action
   in the disposable project. Verify refusal, not merely the YAML or API listing.
   For a reviewer, confirm source edits are refused. Before allowing state-file
   edits, also confirm the narrowly allowed scratch-state edit succeeds.
4. Repeat separately with `--auto` only after user approval. Record tool version,
   exact artifact, resolved rules, attempted actions, and results. Passing a
   different version or role is not evidence for this one.

`--auto` remains off unless explicitly approved for that task. Never widen
permissions or enable it automatically after a timeout. Shell-based writes can
bypass an edit-tool boundary; real isolation belongs to the environment.

## Structural checks are not enforcement

Duplicate-key checks must operate per mapping: the same pattern in independent
edit/write maps is not a duplicate. Earlier investigations produced conflicting
explanations involving format mixing, duplicate keys, stale configuration, and
modified scratch copies. Those explanations are not confirmed against every
current template; do not present them as resolved diagnoses.

Historical upstream reports #42436 and #35238 are investigative references,
not current-status guarantees. Recheck the installed runtime and official
documentation rather than assuming a report remains open or is fixed.

Role templates retain short verification warnings so scaffolded projects do
not need this checkout merely to understand the safety boundary.
