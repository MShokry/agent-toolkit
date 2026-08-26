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
# On a fresh scaffold this also writes .agents/.toolkit-version — a stamp
# recording the toolkit SHA/tag and every flag used. It is committed (it
# describes the project, not the laptop); never written again by --update.
#
#   bin/init.sh --update [--target <path>] [flags] [--diff] [--only <path>]
#     Triage mode. Renders the current templates (flags default from the
#     provenance stamp, so usually just --target is needed) and compares
#     against the live files WITHOUT writing anything:
#
#       exit 0   everything matches the current toolkit
#       exit 1   drift — differing and/or new upstream files, listed in a
#                summary first; full hunks only with --diff, one file with
#                --only <path-substring>. Merge deliberately (or run the
#                generated /toolkit-update command and let the lead do it),
#                then refresh the stamp:
#
#   bin/init.sh --refresh-stamp [--target <path>] [flags]
#     Rewrites .agents/.toolkit-version after you have accepted a merge.
#     This is the ONLY thing that updates the stamp besides a fresh scaffold.
#
# See docs/UPGRADING.md for the full workflow, CHANGELOG.md for what changed
# per release (impact-tagged: contract > safety > process > docs).
#
# Requires: bash, sed, diff, git (for the stamp's SHA/tag; falls back to
# "unknown"). Matches the rest of this toolkit's zero-runtime-dependency
# stance.
# END USAGE

set -eu

TOOLKIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES="$TOOLKIT_ROOT/templates"

TARGET=""
PROJECT_NAME=""
CLAUDE_MODEL=""
BUILDER_MODEL=""
REVIEWER_MODEL=""
REVIEWER_FALLBACK_MODEL=""
TESTER_MODEL=""
TEST_DIR=""
UPDATE=0
SHOW_DIFF=0
ONLY=""
REFRESH_STAMP=0

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
    --diff)                      SHOW_DIFF=1; shift ;;
    --only)                      [ $# -ge 2 ] || die "--only needs a value"; ONLY="$2"; shift 2 ;;
    --refresh-stamp)             REFRESH_STAMP=1; UPDATE=1; shift ;;
    -h|--help) usage ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -n "$TARGET" ] || die "--target is required"
[ -d "$TARGET" ] || die "target does not exist: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"

[ "$TARGET" != "$TOOLKIT_ROOT" ] || die "refusing to scaffold into the toolkit's own checkout — pick another --target"

STAMP="$TARGET/.agents/.toolkit-version"

# Keep in sync with the number of check_pair/render lines below.
RENDER_TOTAL=14

write_stamp() {
  local sha tag
  sha="$(git -C "$TOOLKIT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  tag="$(git -C "$TOOLKIT_ROOT" describe --tags --always --dirty 2>/dev/null || echo unknown)"
  {
    printf 'toolkit_sha:   %s\n' "$sha"
    printf 'toolkit_tag:   %s\n' "$tag"
    printf 'scaffolded:    %s\n' "$(date +%F)"
    printf 'project_name:  %s\n' "$PROJECT_NAME"
    printf 'claude_model:  %s\n' "$CLAUDE_MODEL"
    printf 'builder_model: %s\n' "$BUILDER_MODEL"
    printf 'reviewer_model: %s\n' "$REVIEWER_MODEL"
    printf 'reviewer_fallback_model: %s\n' "$REVIEWER_FALLBACK_MODEL"
    printf 'tester_model:  %s\n' "$TESTER_MODEL"
    printf 'test_dir:      %s\n' "$TEST_DIR"
  } > "$STAMP.tmp"
  mv "$STAMP.tmp" "$STAMP"
}

# --- resolve flag values -----------------------------------------------------
# Fresh scaffolds take values from flags (with two long-standing defaults).
# --update / --refresh-stamp prefer explicit flags, then fall back to the
# provenance stamp — that is what lets "init.sh --update --target ." run
# without re-typing the original flags and without spurious diff noise.

apply_defaults() {
  [ -n "$CLAUDE_MODEL" ] || CLAUDE_MODEL="sonnet"
  [ -n "$TEST_DIR" ] || TEST_DIR="e2e"
}

load_stamp_value() { # $1 = key, sets REPLY
  REPLY="$(sed -n "s/^$1: *//p" "$STAMP" | head -1)"
}

# Recover an init value from the target's own scaffolded files (pre-stamp
# projects). Each pattern matches the substituted form of a __VAR__ token in
# exactly one rendered file. Sets REPLY; empty if not found.
recover_from_target() { # $1 = key
  REPLY=""
  case "$1" in
    builder_model)
      REPLY="$(sed -n 's/^model: //p' "$TARGET/.opencode/agent/builder.md" | head -1)" ;;
    reviewer_model)
      REPLY="$(sed -n 's/^model: //p' "$TARGET/.opencode/agent/reviewer.md" | head -1)" ;;
    reviewer_fallback_model)
      # feature.md: "switch to `__REVIEWER_FALLBACK_MODEL__`"
      REPLY="$(sed -n 's/.*switch to `\([^`]*\)`.*/\1/p' \
        "$TARGET/.claude/commands/feature.md" | head -1)" ;;
    tester_model)
      REPLY="$(sed -n 's/^model: //p' "$TARGET/.opencode/agent/tester.md" | head -1)" ;;
    claude_model)
      REPLY="$(sed -n 's/^model: //p' "$TARGET/.claude/agents/planner.md" 2>/dev/null | head -1)" ;;
    project_name)
      # team.sh: SESSION="__PROJECT_NAME__"
      REPLY="$(sed -n 's/^SESSION="\(.*\)"/\1/p' \
        "$TARGET/scripts/team.sh" | head -1)" ;;
    test_dir)
      # tester.md: "__TEST_DIR__/**": allow
      REPLY="$(sed -n 's/^ *"\(.*\)\/\*\*": allow.*/\1/p' \
        "$TARGET/.opencode/agent/tester.md" | head -1)" ;;
  esac
}

if [ "$UPDATE" -eq 1 ]; then
  if [ -f "$STAMP" ]; then
    for spec in \
      "project_name|PROJECT_NAME" \
      "claude_model|CLAUDE_MODEL" \
      "builder_model|BUILDER_MODEL" \
      "reviewer_model|REVIEWER_MODEL" \
      "reviewer_fallback_model|REVIEWER_FALLBACK_MODEL" \
      "tester_model|TESTER_MODEL" \
      "test_dir|TEST_DIR"; do
      key="${spec%%|*}"; var="${spec##*|}"
      if [ -z "${!var}" ]; then
        load_stamp_value "$key"
        # printf -v: portable indirect assignment (bash's ${!var:=x} does
        # not actually assign on the macOS-shipped bash 3.2).
        [ -n "$REPLY" ] && printf -v "$var" '%s' "$REPLY"
      fi
    done
  else
    # No stamp (pre-v0.3.0 scaffold): recover the original values from the
    # target's own scaffolded files — they carry the substituted forms of the
    # same tokens. Anything still missing falls back to defaults, then to an
    # explicit-flags error below.
    for spec in \
      "project_name|PROJECT_NAME" \
      "claude_model|CLAUDE_MODEL" \
      "builder_model|BUILDER_MODEL" \
      "reviewer_model|REVIEWER_MODEL" \
      "reviewer_fallback_model|REVIEWER_FALLBACK_MODEL" \
      "tester_model|TESTER_MODEL" \
      "test_dir|TEST_DIR"; do
      key="${spec%%|*}"; var="${spec##*|}"
      if [ -z "${!var}" ]; then
        recover_from_target "$key"
        [ -n "$REPLY" ] && printf -v "$var" '%s' "$REPLY"
      fi
    done
    apply_defaults
    RECOVERED=""
    for var in PROJECT_NAME BUILDER_MODEL REVIEWER_MODEL REVIEWER_FALLBACK_MODEL TESTER_MODEL; do
      [ -n "${!var}" ] && RECOVERED="$RECOVERED ${var}: ${!var}"
    done
    [ -n "$RECOVERED" ] && printf 'init.sh: no stamp — inferred init values from the target%s\n  (verify these, then make it permanent: bin/init.sh --refresh-stamp --target %s)\n' "$RECOVERED" "$TARGET"
  fi

  missing=""
  for spec in \
    "project_name|--project-name" \
    "builder_model|--builder-model" \
    "reviewer_model|--reviewer-model" \
    "reviewer_fallback_model|--reviewer-fallback-model" \
    "tester_model|--tester-model"; do
    key="${spec%%|*}"; flag="${spec##*|}"
    val=""
    case "$key" in
      project_name)             val="$PROJECT_NAME" ;;
      builder_model)            val="$BUILDER_MODEL" ;;
      reviewer_model)           val="$REVIEWER_MODEL" ;;
      reviewer_fallback_model)  val="$REVIEWER_FALLBACK_MODEL" ;;
      tester_model)             val="$TESTER_MODEL" ;;
    esac
    [ -n "$val" ] || missing="$missing $flag"
  done
  [ -z "$missing" ] || die "no provenance stamp at $STAMP and these flags are unset:$missing
  (pass them once, exactly as at the original init, or scaffold freshly to get a stamp)"

  if [ "$REFRESH_STAMP" -eq 1 ]; then
    apply_defaults
    mkdir -p "$(dirname "$STAMP")"
    write_stamp
    printf 'init.sh: refreshed %s\n' "$STAMP"
    exit 0
  fi
else
  apply_defaults
  [ -n "$PROJECT_NAME" ] || die "--project-name is required"
  [ -n "$BUILDER_MODEL" ] || die "--builder-model is required"
  [ -n "$REVIEWER_MODEL" ] || die "--reviewer-model is required"
  [ -n "$REVIEWER_FALLBACK_MODEL" ] || die "--reviewer-fallback-model is required"
  [ -n "$TESTER_MODEL" ] || die "--tester-model is required"
fi

# Captured before any render() call touches the target, so it reflects
# whether this is the very first scaffold of this project — used below to
# decide whether to drop the first-run customization marker and write the
# provenance stamp.
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

if [ "$UPDATE" -eq 1 ]; then
  # --- triage mode -------------------------------------------------------
  # Summary first, hunks on demand (docs/UPGRADING.md Stage 3). A wall of
  # raw diff is why nobody merged updates; a list of files plus the
  # changelog's impact tags is what makes merging a decision instead of a
  # chore.
  DIFFS=()
  NEW_UPSTREAM=()
  MATCHED=0
  TOTAL=0

  note_result() { # $1 = status (same|differ|new), $2 = dest
    TOTAL=$((TOTAL + 1))
    case "$1" in
      differ) DIFFS+=("$2") ;;
      new)    NEW_UPSTREAM+=("$2") ;;
      same)   MATCHED=$((MATCHED + 1)) ;;
    esac
  }

  check_pair() { # $1 = template, $2 = destination
    if [ -n "$ONLY" ]; then
      case "$2" in *"$ONLY"*) ;; *) return ;; esac
    fi
    tmp="$(mktemp)"
    sed "${SED_ARGS[@]}" "$1" > "$tmp"
    if [ ! -f "$2" ]; then
      note_result new "$2"
    elif diff -u "$2" "$tmp" > /dev/null 2>&1; then
      note_result same "$2"
    else
      note_result differ "$2"
      if [ "$SHOW_DIFF" -eq 1 ]; then
        printf 'init.sh: upstream changes for %s\n' "$2"
        diff -u "$2" "$tmp" || true
        printf '\n'
      fi
    fi
    rm -f "$tmp"
  }

  check_pair "$TEMPLATES/claude/agents/planner.md.tmpl"    "$TARGET/.claude/agents/planner.md"
  check_pair "$TEMPLATES/claude/agents/senior-dev.md.tmpl" "$TARGET/.claude/agents/senior-dev.md"
  check_pair "$TEMPLATES/claude/commands/feature.md.tmpl"  "$TARGET/.claude/commands/feature.md"
  check_pair "$TEMPLATES/claude/commands/toolkit-update.md.tmpl" "$TARGET/.claude/commands/toolkit-update.md"
  check_pair "$TEMPLATES/opencode/agent/builder.md.tmpl"   "$TARGET/.opencode/agent/builder.md"
  check_pair "$TEMPLATES/opencode/agent/reviewer.md.tmpl"  "$TARGET/.opencode/agent/reviewer.md"
  check_pair "$TEMPLATES/opencode/agent/tester.md.tmpl"    "$TARGET/.opencode/agent/tester.md"
  check_pair "$TEMPLATES/agents-state/TEMPLATE.md.tmpl"    "$TARGET/.agents/TEMPLATE.md"
  check_pair "$TEMPLATES/scripts/oc.sh.tmpl"               "$TARGET/scripts/oc.sh"
  check_pair "$TEMPLATES/scripts/team.sh.tmpl"             "$TARGET/scripts/team.sh"
  check_pair "$TEMPLATES/scripts/team-completion.bash.tmpl" "$TARGET/scripts/team-completion.bash"
  check_pair "$TEMPLATES/scripts/verify-state.sh.tmpl"     "$TARGET/scripts/verify-state.sh"
  check_pair "$TEMPLATES/scripts/verify-spec.sh.tmpl"      "$TARGET/scripts/verify-spec.sh"
  check_pair "$TEMPLATES/scripts/promote-findings.sh.tmpl" "$TARGET/scripts/promote-findings.sh"

  CUR_SHA="$(git -C "$TOOLKIT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  printf 'init.sh: toolkit is at %s; checking %s rendered file(s)%s\n' \
    "$CUR_SHA" "$TOTAL" "${ONLY:+ (filtered by --only '$ONLY'; full set is $RENDER_TOTAL)}"
  if [ -f "$STAMP" ]; then
    load_stamp_value toolkit_sha
    STAMPED_SHA="$REPLY"
    load_stamp_value scaffolded
    printf 'init.sh: this project scaffolded from %s (%s)\n' "${STAMPED_SHA:-unknown}" "${REPLY:-unknown date}"
  fi

  DRIFT=0
  if [ "${#NEW_UPSTREAM[@]}" -gt 0 ]; then
    DRIFT=1
    printf 'init.sh: %s new upstream file(s) — re-run without --update to add:\n' "${#NEW_UPSTREAM[@]}"
    for f in "${NEW_UPSTREAM[@]}"; do printf '  new      %s\n' "$f"; done
  fi
  if [ "${#DIFFS[@]}" -gt 0 ]; then
    DRIFT=1
    printf 'init.sh: %s of %s files differ from the current toolkit:\n' "${#DIFFS[@]}" "$TOTAL"
    for f in "${DIFFS[@]}"; do printf '  differs  %s\n' "$f"; done
    printf 'init.sh: triage against CHANGELOG.md impact tags (contract > safety > process > docs).\n'
    printf 'init.sh: hunks suppressed — re-run with --diff, or --only <path-substring> [--diff] for one file.\n'
  fi
  if [ "$DRIFT" -eq 0 ]; then
    printf 'init.sh: up to date — all %s checked files match the current toolkit.\n' "$TOTAL"
  fi
  printf 'init.sh: nothing was written. After merging, refresh the stamp: bin/init.sh --refresh-stamp --target %s\n' "$TARGET"
  exit "$DRIFT"
fi

# --- normal scaffold ---------------------------------------------------------
render() {
  # $1 = template file, $2 = destination file
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
render "$TEMPLATES/claude/commands/toolkit-update.md.tmpl" "$TARGET/.claude/commands/toolkit-update.md"
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

chmod +x "$TARGET/scripts/oc.sh" "$TARGET/scripts/team.sh" \
         "$TARGET/scripts/verify-state.sh" "$TARGET/scripts/verify-spec.sh" \
         "$TARGET/scripts/promote-findings.sh" 2>/dev/null || true

mkdir -p "$TARGET/.agents"
if [ "$FRESH_SCAFFOLD" -eq 1 ]; then
  touch "$TARGET/.agents/.needs-customization"
fi

# Provenance stamp — written exactly once, on a genuine fresh scaffold,
# never by --update (that would erase the baseline it exists to record).
# Same "computed before any render()" ordering rule as .needs-customization.
# Committed, unlike .oc-port: it describes the project, not this laptop.
if [ "$FRESH_SCAFFOLD" -eq 1 ] && [ ! -f "$STAMP" ]; then
  write_stamp
  printf 'init.sh: wrote %s\n' "$STAMP"
fi

# .agents/.oc-port and .agents/.claude-session-id.* are local machine state
# (which port scripts/team.sh last bound; which Claude conversation each
# tmux session name is pinned to), never something to commit.
# Append-if-missing when the target is a git repo — additive only, in
# keeping with this script's never-overwrite stance; a project that ignores
# these differently is left alone.
if [ -d "$TARGET/.git" ]; then
  GITIGNORE="$TARGET/.gitignore"
  if ! grep -qxF '.agents/.oc-port' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# local opencode server port written by scripts/team.sh\n'
      printf '.agents/.oc-port\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .agents/.oc-port to %s\n' "$GITIGNORE"
  fi
  if ! grep -qxF '.agents/.claude-session-id.*' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# local Claude session ids pinned per tmux session name by scripts/team.sh\n'
      printf '.agents/.claude-session-id.*\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .agents/.claude-session-id.* to %s\n' "$GITIGNORE"
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
     --target $TARGET shows a drift summary (exit 1 = something to merge),
     and /toolkit-update walks your lead through the merge. Refresh the
     stamp afterwards: bin/init.sh --refresh-stamp --target $TARGET.

MSG
