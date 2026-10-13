# Lean context and installation

Role, harness, and model provider are separate. A new OpenCode provider/model
normally changes an assignment, not the workflow or role contracts.

## What each conversation reads

| Conversation | Toolkit instructions | Task/source inputs |
| --- | --- | --- |
| Leader | Small native entrypoint + roles/leader.md + selected backend adapters | Header/handoff between gates; approval/evidence at decisions |
| Planner | Native agent + roles/planner.md | Template, request, relevant planning/architecture/source |
| Implementer | Native agent + roles/implementer.md | Approved spec/scope, constraints, decisions, outstanding findings, source |
| Reviewer | Native agent + roles/reviewer.md | Spec, current patch, decisions, previous finding dispositions, security docs |
| Tester | Native agent + roles/tester.md | Criteria, required checks, routed findings, previous results, test authorship |

Every role also receives harness system/tool instructions and applicable global,
project, and nested guidance. Those costs are not controlled by this toolkit.
An explicit worker assignment must NOT activate generic feature/lead routing.
Workers do not load leader rules or backend dispatch manuals; leaders do not
load all worker contracts. Tool adapters retain their own actual permissions.

Task records remain authoritative and history is preserved. Read required
sections, expanding to full history when uncertain. Do not hide old evidence
behind a lossy summary or move active artifacts. Raw transcripts are for diagnosis,
not routine lead input. Read-only reviewer findings are the deliberate full-reply
exception; the lead records them unchanged.

The leader contract is about 1,040 words, down from the former 5,522-word feature
flow. Worker contracts are 260–360 words; backend adapters 190–290 words.
`test/context.py` enforces word budgets and loading boundaries, not tokenizer-
specific token totals. Actual initial prompts, discovery, inherited settings,
sandboxes, and fresh child context still require live verification per harness.

## Portable single-file leader guide

`.agent-pipeline/README.md` is installed by every profile. It embeds the complete
leader body from the same source as roles/leader.md, plus configured team/model
details and a capability/access checklist. Share it with an agent in any app to
orient it as leader without sharing every instruction file first. Worker dispatch
still requires project access, role contracts, selected backend instructions,
and verified tools; the file itself grants none of these or any approval.

This is an opt-in orientation, not extra automatic context: workers never load
it, and native leads still load the smaller role contract. Do not routinely read
both. It is a snapshot; actual local contracts/configuration may have changed.
Surface conflicts, never override project rules or claim capability from the guide.
Update preview composes it from the canonical toolkit leader source; plain init
preserves existing copies. Reconcile local role changes into the embedded body
too when deliberately updating a shareable guide, and review changed profile/model
details before sharing. Stamp refresh alone does not update the README.

## Install only what you need

```bash
bash /path/to/agent-toolkit/bin/init.sh --target . --project-name my-app \
  --leader opencode --extras none
# Or --leader claude / --leader codex; models remain separate flags.
```

Default worker assignments yield 25 files for OpenCode, 26 for Codex or Claude
(excluding provenance/customization metadata). All include neutral contracts,
validation, OpenCode worker dispatch, and the chosen lead. Native reviewer/tester
assignments add only their required adapters/agents; OpenCode implementation
remains the default. Installing a native agent is not permission or capability
to dispatch it from another harness.

Extras: `dashboard`, `herdr` (includes dashboard), `launcher` (tmux/completion,
dashboard, exact Codex lead capture/hooks), or a comma-separated combination.
Example: `--leader codex --extras herdr`. No global plugin/hook installation or
trust approval occurs. Normally launch your chosen lead directly; the optional
team launcher honors a single-leader profile instead of selecting another CLI.

`--leader all` defaults to `--extras all` for compatibility (43 default files);
use `--extras none` to omit host conveniences. Separating canonical contracts
adds shared files to all-tools installations; lean profiles reduce actual
installed files instead of disguising a giant prompt as one file.

## Existing projects

The major layout keeps the core in one folder: bin/ for runtime scripts,
tasks/ for task records/template, and existing roles/adapters/prompts/logs.
Native discovery directories remain outside the core by client requirement.
For old root tasks/scripts, run the reviewed bulk migration plan/apply FIRST;
plain init refuses the old layout rather than creating split state.

New tasks replace per-client session headers with one Role assignments table:
Role, Backend, Model, Family, Session / thread. Family is the resolved model-maker,
not a provider label. Class decided by remains pending until confirmed. Keep
external-review/auto approvals and loop budgets separately; these are authority,
not routing metadata. Legacy records remain readable without rewriting history.
After first receipts the lead creates immutable model/session bindings using
task-record.py bind; session lookup refuses missing bindings or model changes.

Preview with `--update --leader <tool> --extras <selection>`. Preview never
writes. Plain init only adds missing selected files; it never replaces or deletes
existing adapters/customizations. Profile/model overrides do not update a prior
stamp. After approved reconciliation, explicitly refresh with the same flags.
Then flag-free init/update uses the selected baseline. Legacy stamps without
profile fields retain all tools/extras. If removing old adapters is desired,
review an explicit idle-only removal plan; do not delete project-owned guidance.
See [migration 04](../migrations/04-team-upgrade.md).
