# Maintainer backlog

Current open work, carried forward from the historical reviews. Resolved
findings and incident timelines remain available in Git history.

## Verification

- Luna follow-up audited installed contracts and 18 synthetic leader gate cases;
  written rules provide safe routes, not live enforcement proof. OpenCode planner
  model dispatch wiring still needs a fresh approved runtime check against the
  stamped assignment. Herdr setup from a shell failed adoption; submission/hosting
    is not a role briefing.

- Major layout: verify moved permission resources against the exact generated
  artifacts live. Tester writes must reach task records but not bin/ or roles/;
  lead automatic edits must not include executable tooling. Confirm per-role
  model bindings and actual reviewer identity in fresh native/runtime sessions.
- Triage existing validator warnings without deleting historical evidence or
  inferring acceptance just to make migration checks green. Keep migration tests
  project-neutral and confined to disposable fixtures.

- Verify lean starting context live in all three harnesses: native role discovery,
  actual first-turn instructions, global/project/nested guidance inheritance,
  no worker-to-leader routing, fresh reviewer isolation, and lazy adapter loads.
  Static word budgets and linked contracts do not prove the full served prompt.

- Verify optional Herdr two-tab setup live: action discovery/caller context,
  same-server/project scoping, lead preservation, dashboard startup in tools tab,
  reuse/partial failure/recreated panes, exact focus actions, and official native
  session controls. No script installs agent integrations or changes permissions.

- Run the full pipeline against a real OpenCode server. Automated tests use
  mocks and structural checks; they do not establish runtime enforcement.
- Verify each generated role's resolved permissions and refused actions in a
  fresh runtime, using the exact generated files. Check auto-approval separately.
- Verify distinct role session ids and same-role reruns in a real pipeline;
  mocked lifecycle tests do not establish live runtime capability selection.
- Recheck legacy `write`/`patch` alias ordering against resolved edit rules.
  The fork reports that trailing aliases can override scoped edit grants;
  any resulting permission change needs separate approval and refused-action tests.
- Run ShellCheck locally as well as in CI; do not mistake a skipped check for
  a successful lint run.

## Policy decisions (require user approval)

- Define project-specific sensitive paths and whether sensitive tasks need
  a stronger reviewer or additional negative tests. Role sessions are isolated
  for all task classes.
  Task-class fields already exist; class-dependent staffing is not automatic.
- Decide whether to introduce a project team charter covering definition of
  done, merge authority, unavailable approvers, test ownership, WIP limits, and
  escalation budgets. Do not invent these answers or loosen existing gates.

## Selective fork integration followups

- Native Codex worker definitions are integrated, but live discovery, thread
  resume, sandbox enforcement, and independent cross-family review remain manual
  verification. Exact Codex lead pinning and headless cross-tool Claude review
  are integrated; test capture/trust, resume, account/model discovery, hook side
  effects, read-only enforcement, and error/timeout handling live before release.
- Detached dispatch deliberately does not replay failed commands automatically.
  Retry orchestration must allocate immutable new passes and verify inactivity;
  copying the fork's retry loop unchanged would destroy those guarantees.

## Accepted tradeoffs

- Structural checks validate evidence placement, not evidence quality. Human
  approval and independent review/test judgment remain necessary.
- The lead is a single point of orchestration judgment; budgets and approval
  gates constrain it but do not eliminate that risk.
- Keep Python for the optional dashboard and runtime JSON handling. A
  Python-free text extractor is not a current priority.
- Keep optional shell completion: it is an active scaffolded feature, not a
  disposable leftover.

See [UPGRADING.md](UPGRADING.md) for downstream reconciliation and
[PERMISSIONS.md](PERMISSIONS.md) for the live-verification procedure.
