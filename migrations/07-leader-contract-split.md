# Migration 07 — Leader core and by-case reference

Wording and file-layout change to the leader contract after migration 06. No
gate, budget, role authority, model assignment, permission, task schema, or
script interface changes.

## What changed

- `.agent-pipeline/roles/leader.md` is now the leader **core**: eight numbered
  steps, the approval and merge stops, the per-dispatch rules, and a table
  saying when to read the reference.
- `.agent-pipeline/roles/leader-reference.md` is new. It holds the rules for
  less common cases in seven sections: Models and independence; Backends and
  consent; Sessions and artifacts; Waiting and recovery; Findings, disputes,
  and bounces; Committing; Layout and hosts.
- `.agent-pipeline/README.md` embeds the core and points to the reference.
- Native entrypoints are unchanged: they still load `roles/leader.md`.

## Existing installation

1. At an inactive boundary, run `init.sh --update`. It reports
   `roles/leader-reference.md` as new and `roles/leader.md` and `README.md` as
   differing.
2. Run plain `init.sh` to add the reference; existing files are skipped.
3. Merge the new `roles/leader.md` by hand. If the project added its own leader
   rules, keep them: put a rule every task needs in the core, and a rule for a
   specific case in the matching reference section. Do not drop a local rule
   because the upstream file no longer has a paragraph to attach it to.
4. Regenerate or merge the embedded block in `.agent-pipeline/README.md`.
5. Start a fresh lead conversation; a running lead keeps the old text.
6. Accept provenance with `--refresh-stamp` after the reviewed merge.

Static tests check that each rule is still present and that gates stay in the
core. They do not show that a lead follows the shorter text; run one real task
and compare its record against the steps before relying on it.
