#!/usr/bin/env bash
#
# BEGIN USAGE
# Scaffolds the planner -> implement -> review -> test agent pipeline into a
# target project. Copies templates/, substituting __PLACEHOLDER__ tokens for
# values passed as flags. Never overwrites an existing file — prints what it
# skipped instead, so an existing project can diff and merge by hand.
#
# Usage:
#   bin/init.sh --target <path> --project-name <name> \
#     --builder-model <vendor/model> \
#     --reviewer-model <vendor/model> \
#     --reviewer-fallback-model <vendor/model> \
#     --tester-model <vendor/model> \
#     [--claude-model sonnet] [--test-dir e2e]
#
#   bin/init.sh --update (same flags)
#     Never writes anything. Renders the current templates into a temp file
#     and diffs each one against the live file in --target, so you can see
#     what changed upstream since this project was scaffolded, and merge by
#     hand (or hand the diff to your AI lead to reconcile). Pass the SAME
#     model/name flags used at the original init — different values would
#     show up as spurious diff noise on every substituted line.
#
# Requires: bash, sed, diff. No other dependency — matches the rest of this
# toolkit's zero-runtime-dependency stance.
# END USAGE

set -eu

TOOLKIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES="$TOOLKIT_ROOT/templates"

TARGET=""
PROJECT_NAME=""
CLAUDE_MODEL="sonnet"
BUILDER_MODEL=""
REVIEWER_MODEL=""
REVIEWER_FALLBACK_MODEL=""
TESTER_MODEL=""
TEST_DIR="e2e"
UPDATE=0

die() { printf '%s\n' "init.sh: $*" >&2; exit 1; }

usage() {
  awk '/^# BEGIN USAGE$/ {f=1; next} /^# END USAGE$/ {f=0} f' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)                  [ $# -ge 2 ] || die "--target needs a value"; TARGET="$2"; shift 2 ;;
    --project-name)             [ $# -ge 2 ] || die "--project-name needs a value"; PROJECT_NAME="$2"; shift 2 ;;
    --claude-model)              [ $# -ge 2 ] || die "--claude-model needs a value"; CLAUDE_MODEL="$2"; shift 2 ;;
    --builder-model)             [ $# -ge 2 ] || die "--builder-model needs a value"; BUILDER_MODEL="$2"; shift 2 ;;
    --reviewer-model)            [ $# -ge 2 ] || die "--reviewer-model needs a value"; REVIEWER_MODEL="$2"; shift 2 ;;
    --reviewer-fallback-model)   [ $# -ge 2 ] || die "--reviewer-fallback-model needs a value"; REVIEWER_FALLBACK_MODEL="$2"; shift 2 ;;
    --tester-model)              [ $# -ge 2 ] || die "--tester-model needs a value"; TESTER_MODEL="$2"; shift 2 ;;
    --test-dir)                  [ $# -ge 2 ] || die "--test-dir needs a value"; TEST_DIR="$2"; shift 2 ;;
    --update)                    UPDATE=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -n "$TARGET" ] || die "--target is required"
[ -n "$PROJECT_NAME" ] || die "--project-name is required"
[ -n "$BUILDER_MODEL" ] || die "--builder-model is required"
[ -n "$REVIEWER_MODEL" ] || die "--reviewer-model is required"
[ -n "$REVIEWER_FALLBACK_MODEL" ] || die "--reviewer-fallback-model is required"
[ -n "$TESTER_MODEL" ] || die "--tester-model is required"

[ -d "$TARGET" ] || die "target does not exist: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"

[ "$TARGET" != "$TOOLKIT_ROOT" ] || die "refusing to scaffold into the toolkit's own checkout — pick another --target"

# Captured before any render() call touches the target, so it reflects
# whether this is the very first scaffold of this project — used below to
# decide whether to drop the first-run customization marker.
FRESH_SCAFFOLD=0
[ -f "$TARGET/.claude/commands/feature.md" ] || FRESH_SCAFFOLD=1

# The substitution list, built once — a new placeholder gets added here and
# nowhere else (render()'s two branches used to duplicate it by hand).
SED_ARGS=(
  -e "s|__PROJECT_NAME__|$PROJECT_NAME|g"
  -e "s|__CLAUDE_MODEL__|$CLAUDE_MODEL|g"
  -e "s|__BUILDER_MODEL__|$BUILDER_MODEL|g"
  -e "s|__REVIEWER_MODEL__|$REVIEWER_MODEL|g"
  -e "s|__REVIEWER_FALLBACK_MODEL__|$REVIEWER_FALLBACK_MODEL|g"
  -e "s|__TESTER_MODEL__|$TESTER_MODEL|g"
  -e "s|__TEST_DIR__|$TEST_DIR|g"
)

render() {
  # $1 = template file, $2 = destination file
  if [ "$UPDATE" -eq 1 ]; then
    tmp="$(mktemp)"
    sed "${SED_ARGS[@]}" "$1" > "$tmp"
    if [ ! -f "$2" ]; then
      printf 'init.sh: %s does not exist yet (new upstream file — re-run without --update to add it)\n' "$2"
    elif diff -u "$2" "$tmp" > /dev/null 2>&1; then
      printf 'init.sh: up to date — %s\n' "$2"
    else
      printf 'init.sh: upstream changes for %s\n' "$2"
      diff -u "$2" "$tmp" || true
      printf '\n'
    fi
    rm -f "$tmp"
    return
  fi

  if [ -f "$2" ]; then
    printf 'init.sh: skip (exists) %s\n' "$2"
    return
  fi
  mkdir -p "$(dirname "$2")"
  sed "${SED_ARGS[@]}" "$1" > "$2"
  printf 'init.sh: wrote %s\n' "$2"
}

render "$TEMPLATES/claude/agents/planner.md.tmpl"    "$TARGET/.claude/agents/planner.md"
render "$TEMPLATES/claude/agents/senior-dev.md.tmpl" "$TARGET/.claude/agents/senior-dev.md"
render "$TEMPLATES/claude/commands/feature.md.tmpl"  "$TARGET/.claude/commands/feature.md"
render "$TEMPLATES/opencode/agent/builder.md.tmpl"   "$TARGET/.opencode/agent/builder.md"
render "$TEMPLATES/opencode/agent/reviewer.md.tmpl"  "$TARGET/.opencode/agent/reviewer.md"
render "$TEMPLATES/opencode/agent/tester.md.tmpl"    "$TARGET/.opencode/agent/tester.md"
render "$TEMPLATES/agents-state/TEMPLATE.md.tmpl"    "$TARGET/.agents/TEMPLATE.md"
render "$TEMPLATES/scripts/oc.sh.tmpl"               "$TARGET/scripts/oc.sh"
render "$TEMPLATES/scripts/team.sh.tmpl"             "$TARGET/scripts/team.sh"
render "$TEMPLATES/scripts/team-completion.bash.tmpl" "$TARGET/scripts/team-completion.bash"
render "$TEMPLATES/scripts/verify-state.sh.tmpl"     "$TARGET/scripts/verify-state.sh"
render "$TEMPLATES/scripts/verify-spec.sh.tmpl"      "$TARGET/scripts/verify-spec.sh"
render "$TEMPLATES/scripts/promote-findings.sh.tmpl" "$TARGET/scripts/promote-findings.sh"

if [ "$UPDATE" -eq 1 ]; then
  cat <<MSG

init.sh: --update done. Nothing was written above — those are diffs between
the current templates and what's already in $TARGET. Merge by hand, or hand
this output to your AI lead and ask it to reconcile against anything you've
customized locally.

MSG
  exit 0
fi

chmod +x "$TARGET/scripts/oc.sh" "$TARGET/scripts/team.sh" \
         "$TARGET/scripts/verify-state.sh" "$TARGET/scripts/verify-spec.sh" \
         "$TARGET/scripts/promote-findings.sh" 2>/dev/null || true

mkdir -p "$TARGET/.agents"
if [ "$FRESH_SCAFFOLD" -eq 1 ]; then
  touch "$TARGET/.agents/.needs-customization"
fi

# .agents/.oc-port is local machine state (which port scripts/team.sh last
# bound), never something to commit. Append-if-missing when the target is a
# git repo — additive only, in keeping with this script's never-overwrite
# stance; a project that ignores it differently is left alone.
if [ -d "$TARGET/.git" ]; then
  GITIGNORE="$TARGET/.gitignore"
  if ! grep -qxF '.agents/.oc-port' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# local opencode server port written by scripts/team.sh\n'
      printf '.agents/.oc-port\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .agents/.oc-port to %s\n' "$GITIGNORE"
  fi
fi

cat <<MSG

init.sh: done.

Next steps:
  1. Read every generated file before trusting it — especially
     .opencode/agent/reviewer.md's permission block. A blanket "deny" has
     failed to actually block a write before in at least one real project;
     verify it against your real OpenCode server rather than assuming it
     from the YAML.
  2. Start opencode serve (or run $TARGET/scripts/team.sh) so scripts/oc.sh
     has something to attach to.
  3. Load the "delegate" skill at the start of the lead's own session — it
     is the context-discipline half of this, the workflow half is
     .claude/commands/feature.md.
  4. Make sure $TARGET has its own CLAUDE.md/AGENTS.md — the generated
     files defer project-specific constraints to it and have nothing to
     say without one.
  5. On the first /feature run, the lead will notice
     .agents/.needs-customization and ask whether to fill the role files'
     generic pitfalls/hard-rules sections with this project's real ones.
     If your lead isn't Claude Code (that check lives in feature.md, which
     is Claude-specific), do that pass yourself, once, by hand — and
     delete the marker file when done.
  6. Later, once the toolkit itself has moved on: bin/init.sh --update
     (same flags as above) shows you what changed upstream, without
     writing anything.

MSG
