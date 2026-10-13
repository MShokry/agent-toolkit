# Models and providers

`bin/init.sh` supplies model defaults; override them per project after checking
`opencode models`. Availability, prices, and provider quotas change. These IDs
are starting choices, not promises or an instruction to install extra providers.

After starting the server, run `.agent-pipeline/bin/verify-models.sh` before planning. It
checks the four stamped OpenCode worker ids (including reviewer fallback),
enabled state, and any `#variant`, using bounded authenticated catalog calls.
Native `codex/*` ids are checked against a bounded `codex debug models` catalog
query; unavailable catalogs return unchecked, not a pass. `claude/*` ids remain
explicitly unchecked. Only configured Claude reviewers can proceed after the
explicit human confirmation/consent gate in [CLAUDE-REVIEW.md](CLAUDE-REVIEW.md);
this does not convert an unchecked catalog to a pass. Keep actual flow/role
assignments in sync with the stamp; this check is
not proof of credentials, quota, or served-model identity.

## Scaffold defaults

| Role | Default |
| --- | --- |
| Claude planner/senior-dev | `sonnet` |
| OpenCode builder | `opencode-go/glm-5.3-flash` |
| OpenCode reviewer | `opencode-go/minimax-m2.7` |
| OpenCode reviewer fallback | `opencode-go/deepseek-v4-flash` |
| OpenCode tester | `hcnsec/auto` |

Claude, Codex, and OpenCode leads use their selected session model. The Claude
model flag does not select the Codex/OpenCode lead model.

The reviewer must use a different model family/lab than the implementer. Two
snapshots of one family are not independent. Keep a third-family fallback and
log substitutions in the task record. Never use an `auto` router for review;
it may silently select the implementer's family. Routing is acceptable for the
tester when faithful triage/reporting is verified.

`codex/<id>` selects a native Codex reviewer/tester, not an OpenCode provider.
The `codex-dev` implementer inherits the Codex lead's settings unless customized;
record the actual model/family before dispatch. A second OpenAI model is not
independent review of OpenAI-authored work; use an approved different-family
OpenCode reviewer or stop. See [CODEX.md](CODEX.md) for native discovery and scope.

## Choosing models

- Lead/planner: prioritize instruction-following and checkable specifications.
- Implementer: balance coding quality with the cost of repeated tool calls.
- Reviewer: prioritize skepticism and independent weights; assess capability
  on the project's actual diffs rather than choosing by price label alone.
- Tester: use a model capable of executing and reporting tests reliably.

Raise review depth or model capability only as an explicit project/task choice.
Do not skip review to fit a quota. Recheck provider pricing instead of relying
on historical request-count tables.

## Providers are not tools

OpenCode can dispatch multiple model families through one provider or several
native APIs. Prefer an already configured multi-model provider when it meets
availability and policy needs. Use another gateway/native API when needed for
residency, outage independence, missing models, or provider debugging.

Adding a lab's model is a role model/provider choice, not a reason to duplicate
toolkit role files. Adding another agent harness is a different task; see
[ADDING-A-TOOL.md](ADDING-A-TOOL.md). A shared gateway does not imply shared
weights, but it can correlate outages or model substitution failures.
