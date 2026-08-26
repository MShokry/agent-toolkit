---
name: toolkit-release
description: Cut a new toolkit release — draft the CHANGELOG entry from git history since the last tag, pick the version, tag and push via bin/release.sh. Use when the user says "release", "cut a release", "publish vX.Y.Z", or asks to ship pending changes.
---

# Releasing the toolkit

You automate what used to be manual: read what changed since the last tag,
write the impact-tagged changelog entry, choose the version, run the
deterministic releaser. `bin/release.sh` owns every hard check (clean tree,
on main, changelog heading present, no duplicate tag); you own everything
requiring judgment. Never bypass it with a raw `git tag` + push.

## Steps

1. Find the baseline: `git describe --tags --abbrev=0`, then
   `git log --oneline <last-tag>..HEAD`. If empty, tell the user there is
   nothing to release and stop.
2. For each commit, read its diff (`git show <sha> --stat` first, full diff
   where needed) and classify by impact, exactly per the definitions at the
   top of `CHANGELOG.md`: `[contract]` › `[safety]` › `[process]` ›
   `[docs]`. A new file in `migrations/` marks its change as `[contract]`.
   Never invent an entry from the commit message alone.
3. Propose the version:
   - **major** — a `[contract]` change installed copies can't absorb by
     following the migration note;
   - **minor** — anything else that adds or changes behavior: `[contract]`
     with an adequate migration, `[safety]`, new features, `[process]`;
   - **patch** — fixes and docs only.
4. Show the user: proposed version + the drafted changelog section. Apply
   their edits. Do not proceed without explicit approval of both.
5. Write the approved section into `CHANGELOG.md` as a new
   `## v<X>.<Y>.<Z> — <today>` heading directly under the header block,
   newest first, then commit: `docs: changelog for <version>`.
6. Run `bash bin/release.sh v<X>.<Y>.<Z>`. If it fails, fix the cause
   (usually: uncommitted files, behind origin, missing heading) and re-run —
   never work around it.
7. Report: version, tag URL (`https://github.com/MShokry/agent-toolkit/releases/tag/v…`),
   one line per impact class in the release.

## Hard gates

- User approves version AND drafted entry before anything is written.
- No force-push, no retagging an existing version — if a released tag is
  wrong, the fix is a new patch release, not a rewrite.
- If any commit is unclassified because its diff is unclear, ask — don't guess.
