#!/usr/bin/env bash
# Release the toolkit: verify readiness, tag, push.
#
#   bin/release.sh v0.3.1
#
# Deterministic checks only — drafting the CHANGELOG entry is judgment work
# and belongs to whoever runs this (see skills/toolkit-release/):
#   1. working tree clean, on main, not behind origin/main
#   2. CHANGELOG.md has a "## <version>" heading
#   3. the tag doesn't exist yet
#   4. test/invariants.sh and test/smoke.sh pass (RELEASE_SKIP_TESTS=1 skips)
# Then: annotated tag + push of the checked branch and the tag.
set -euo pipefail

VERSION="${1:-}"
die() { echo "release: $1" >&2; exit 1; }

case "$VERSION" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) die "usage: bin/release.sh v<MAJOR>.<MINOR>.<PATCH>  (got: '${VERSION:-nothing}')" ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || die "not inside a git repository"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || [ "${RELEASE_ANY_BRANCH:-}" = "1" ] \
  || die "on branch '$BRANCH', expected 'main' (set RELEASE_ANY_BRANCH=1 to override)"

if ! git diff-index --quiet HEAD -- || [ -n "$(git status --porcelain)" ]; then
  die "working tree not clean:
$(git status --short)
commit first — a release tag must point at a committed state"
fi

git fetch origin --quiet >/dev/null 2>&1 || true
if git rev-parse --verify -q origin/main >/dev/null; then
  BEHIND="$(git rev-list --count HEAD..origin/main)"
  [ "$BEHIND" = "0" ] || die "local main is $BEHIND commit(s) behind origin/main — pull first"
fi

grep -qE "^## ${VERSION//./\\.}( |$)" CHANGELOG.md \
  || die "CHANGELOG.md has no '## $VERSION' entry — write it first (see skills/toolkit-release/)"

git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null \
  && die "tag $VERSION already exists"

# A tag is permanent; do not publish one the deterministic suites reject.
if [ "${RELEASE_SKIP_TESTS:-}" != "1" ]; then
  ROOT="$(git rev-parse --show-toplevel)"
  bash "$ROOT/test/invariants.sh" >/dev/null || die "test/invariants.sh failed — fix before tagging"
  bash "$ROOT/test/smoke.sh" >/dev/null || die "test/smoke.sh failed — fix before tagging (RELEASE_SKIP_TESTS=1 to override)"
fi

DATE="$(date +%Y-%m-%d)"
SUMMARY="$(sed -n "/^## ${VERSION//./\\.}/,/^-/p" CHANGELOG.md | sed -n '2p' | sed 's/^- //')"

git tag -a "$VERSION" -m "$VERSION — $DATE
${SUMMARY:-}"
# Push the branch that was actually checked: the override releases from another
# branch, it must never move main to that branch's HEAD.
git push origin "HEAD:refs/heads/$BRANCH" "$VERSION"

echo "release: tagged and pushed $VERSION"
echo "release: downstream projects update via: git pull (their toolkit checkout) then /toolkit-update"
