# Models and providers (cost vs quality)

A starting recommendation for which model runs each pipeline role, and how
to wire the providers. It is not a silent default: `bin/init.sh` still
requires the flags, and `SYSTEM.md` still says to ask a human. Run
`opencode models` and pin the exact `vendor/model` strings your server
actually lists — this file names **families**, not guaranteed IDs.

Independence is about **model family / lab weights**, not who prints the
invoice. Two GLM snapshots on one aggregator are still the same family.
`auto` is not a family; never use it for the reviewer.

Dated August 2026. Credit ratios drift; re-check the provider's own table
when a window starts emptying sooner than you expect.

## What burns credits

A `/feature` run is not five equal calls:

| Role | Typical volume | What to optimize |
| --- | --- | --- |
| Lead | Long session, few tokens per step if it only reads `Latest handoff` | Instruction-following, not coding power |
| Planner | One (maybe two) shots, read-heavy, short state-file write | Spec quality; cost is small |
| Implementer | The hog — many tool calls | Quality **and** cost; this is where Opus/K3 empty a window |
| Reviewer | One or two shots, large context (spec + diff) | Skepticism, different family; per-call price is fine |
| Tester | One shot + a smoke command | Faithful reporting; cheapest capable model |

Spend mid-tier credits on the implementer loop. Spend a *different family's*
judgment on review. Do not spend frontier credits on tester.

## Relative cost (credit-style meters)

OpenCode Go–class billing is dollar-equivalent credits (`$12` / 5h,
`$60` / month is the shape; your aggregator may differ). Approximate
request volume per 5h window, expensive → cheap:

| Family | Relative burn | Notes |
| --- | --- | --- |
| Claude Opus | Highest (usually a **different** pool than Go) | Do not put on a tool loop |
| Claude Sonnet | High, other pool | Lead + planner; reviewer fallback |
| Kimi K3 | Very high on Go (~110 req / 5h) | Rare “actually hard” implementer, not default |
| GLM-5.3 | High (~220 req / 5h, tighter cap than 5.2) | Best GLM for **one-shot** review |
| GLM-5.1 / 5.2 | Mid–high (~880 req / 5h) | Review, or planner if Claude credits are tight |
| Kimi K2.6 / K2.7 Code | Mid (~1k–1.3k req / 5h) | Default implementer — agentic loops |
| DeepSeek V4 Pro | Low | Implementer when the window is tight |
| DeepSeek V4 Flash | Lowest (~30k req / 5h) | Tester only |

These counts are provider estimates, not a promise. GLM-5.3 is usually
the same *job* as 5.2 at a worse credit rate — prefer 5.2 unless 5.3 is
clearly better on your list.

## Recommended lineup

For this toolkit's own work (bash + sed, markdown templates, process
rules, no app runtime):

| Role | Model | Why |
| --- | --- | --- |
| **Lead** | Claude Sonnet | Already the Claude Code session. Opus does not improve dispatch. |
| **Planner** | Claude Sonnet | One shot. A cheaper model writes mushy ACs or starts designing the implementation. Drop to GLM-5.2 only if the Claude pool is the bottleneck. |
| **Implementer** (`builder` / `senior-dev`) | **Kimi K2.7 Code** (or K2.6) | Cost/quality for surgical template + `init.sh` work. GLM-5.2 only if Kimi is missing. Not GLM-5.3, not K3, not Opus as the default loop. |
| **Reviewer** | **GLM-5.3** or **5.2** | Different family than Kimi. One/two calls, so GLM's per-call cost is acceptable. Catches process bugs (leftover placeholders, `render()` skip-if-exists, permission YAML ≠ enforcement) better than Flash. |
| **Reviewer fallback** | Claude Sonnet (or DeepSeek Pro) | A **third** family, and preferably a **second gateway** (see below). Used when builder would share a family with the default reviewer. |
| **Tester** | DeepSeek V4 Flash | Smoke `init.sh` into `/tmp`, assert no `__[A-Z_]*__`, second run does not clobber. Flash is enough. |

`init.sh` shape (replace with strings from `opencode models`):

```bash
--claude-model sonnet \
--builder-model "<aggregator>/kimi-k2.7-code" \
--reviewer-model "<aggregator>/glm-5.2" \
--reviewer-fallback-model sonnet \
--tester-model "<aggregator>/deepseek-v4-flash"
```

If you implement with GLM, reviewer must **not** be GLM (5.2 vs 5.3
does not count). Switch reviewer to Kimi or DeepSeek Pro.

Tight credits: DeepSeek Pro implementer, GLM-5.2 reviewer, Flash tester.
High-stakes (`render()`, permission blocks, state-file contract): keep
Kimi on implementer; optionally fire the Sonnet fallback as a second
review pass — still cheaper than implementing on Opus.

Do not: Claude on builder **and** reviewer; K3/Opus as default
implementer; Flash as reviewer; `auto` anywhere independence matters.

## Provider: one aggregator for workers, not one tool per lab

This toolkit has two different words that are easy to smash together:

- A **tool** is a harness with its own agent files and permission model
  (Claude Code, OpenCode, …). Adding one is `docs/ADDING-A-TOOL.md`.
- A **model family** is Kimi / GLM / DeepSeek / Claude. That is an
  `init.sh` flag on an existing role, not a new `templates/<lab>/`.

**Do not add Moonshot, Zhipu, DeepSeek, or Anthropic as extra toolkit
tools** just to get those weights. You would copy `builder.md` /
`reviewer.md` N times for no permission-model reason, and every
behavioral fix would become N edits — the failure mode
`ADDING-A-TOOL.md` tells you not to invent.

**Do use one multi-model provider in OpenCode for the worker roles**
(implementer, reviewer, tester). One `opencode serve`, one `opencode
models` list, one credit meter, three families. That is the cost/quality
mix above without extra keys.

Concrete options, in order:

1. **Whatever aggregator you already have wired into OpenCode** (the
   README's `hcnsec/…` example is this). Stay on it if `opencode models`
   already lists Kimi, GLM, and DeepSeek. Adding native lab keys on top
   is extra ops for no independence gain.
2. **OpenCode Go** (or the current OpenCode credit pass for open
   models) if you are starting from nothing and want Kimi / GLM /
   DeepSeek on one bill. Pin named models; do not use a router `auto`.
3. **Native lab APIs** (Moonshot + Zhipu + DeepSeek as separate OpenCode
   providers) only when you need something the aggregator cannot give:
   a missing family, data-residency, or surviving that aggregator going
   down. Three dashboards, three rate limits, three keys — real cost.

**Keep Claude as its own provider** for lead / planner (Claude Code) and
as reviewer fallback. That is already how the pipeline is split, and it
is the one extra connection worth having: a second *gateway*, so an
aggregator outage or a silent model substitution cannot take out both
implementation and review.

That hybrid is the recommendation:

```
Claude Code  ── lead, planner, (optional senior-dev), reviewer fallback
OpenCode     ── builder, reviewer, tester
                 └── one aggregator: Kimi + GLM + DeepSeek
```

### What an aggregator does not buy you

- Same HTTP front door ≠ same weights. Kimi vs GLM on one gateway still
  satisfies the family rule. Two GLM ids do not.
- Shared wrappers can correlate tool-call bugs. The fallback reviewer
  on Claude is the cheap hedge; a second aggregator is not worth it
  until the first one has actually lied about which model ran.
- One credit window: the implementer runs first and can starve review.
  If the 5h cap is tight, implement on DeepSeek Pro, or stop and wait —
  do not skip review or swap the reviewer to Flash.
- `auto` / router ids defeat the family rule. Pin `…/kimi-k2.7-code`
  and `…/glm-5.2` (or whatever the list actually prints).

### When native-per-lab *is* better

- The aggregator does not offer a family you need.
- Policy requires traffic to go to the lab, not a middleman.
- You are debugging a provider-specific refusal (permissions, tool
  schema) and need to know there is no extra wrapper.

Even then, you still have **one OpenCode tool** with multiple providers
in its config — not new files under `templates/`.
