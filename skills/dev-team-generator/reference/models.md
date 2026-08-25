# Models and vendor independence

Advisory, not a default to apply silently — `SKILL.md` step 1 still means
actually asking the user, every time.

## The one rule that isn't negotiable

Independence for the reviewer is about **model family / lab weights**, not
which company's endpoint or aggregator happens to serve the request. Two
models from the same lab on the same aggregator are still the same family.
An "auto"/router model id is not a family at all — never use it for the
reviewer, since it can silently resolve to whatever the implementer used.

If the implementer and the reviewer would end up in the same family,
switch the reviewer to the fallback family gathered at setup, and log the
substitution in the state file.

## What actually costs money, roughly

Not five equal-cost calls:

| Role | Typical volume | Optimize for |
| --- | --- | --- |
| Lead | Long session, small if it only reads the handoff line | Instruction-following, not raw power |
| Planner | One or two shots, read-heavy, short write | Spec quality; cost is small either way |
| Implementer | The hog — many tool calls | Quality *and* cost; this is where a frontier model empties a budget fastest |
| Reviewer | One or two shots, large context (spec + diff) | Skepticism, a different family; per-call price is usually fine |
| Tester | One shot plus a smoke command | Faithful reporting; the cheapest capable model is fine here |

Spend mid-tier budget on the implementer loop. Spend a different family's
judgment on review. Don't spend frontier-tier budget on the tester.

## A cost/quality starting point, not a rule

Pin exact model ids from whatever the tool's own model-listing command
shows — family names here are not guaranteed ids, and the relative-cost
ordering drifts over time; re-check it periodically rather than trusting a
snapshot.

A reasonable default shape for a general-purpose project (adjust for
whatever's actually available):

- **Lead / planner:** whichever capable model is already running the
  session doing the orchestrating — no benefit to a bigger model here.
- **Implementer:** a solid mid-tier coding model. Not the most expensive
  available model as a default loop; reserve that for a task that's
  actually proven hard, not every task.
- **Reviewer:** a different family than the implementer, strong enough for
  a careful single/double pass — per-call cost matters less here since the
  volume is low.
- **Reviewer fallback:** a **third** family (and ideally a second
  gateway/provider entirely, so one vendor's outage or a silent
  model-substitution bug can't take out both implementation and review at
  once).
- **Tester:** the cheapest model actually capable of following the
  triage-and-report instructions faithfully — this role doesn't need
  coding strength, it needs faithful reporting.

## One aggregator for workers is fine; one tool per model family is not

Two different things are easy to conflate:

- A **tool** is a harness with its own agent files and permission model.
  Adding one is real work — see `tool-onboarding.md`.
- A **model family** (which lab, which weights) is a model-selection
  argument on an *existing* role under an *existing* tool, not a reason to
  add a new templated tool. Don't add a new `templates/<lab>/`-equivalent
  just to get a specific lab's weights if the tool already dispatched can
  reach them through one multi-model provider — that turns one behavioral
  fix into N file edits for no independence gain, which is exactly the
  failure `tool-onboarding.md`'s "only extract once duplicated twice" rule
  exists to avoid triggering early.

Prefer: one dispatched CLI tool, configured against one provider that
already lists multiple independent families, over one CLI-tool-shaped
adapter per model family.
