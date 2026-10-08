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
#     [--builder-model <vendor/model>] \
#     [--reviewer-model <vendor/model>] \
#     [--reviewer-fallback-model <vendor/model>] \
#     [--tester-model <vendor/model>] \
#     [--claude-model sonnet] [--test-dir e2e]
#     [--codex-model <id|inherit>] [--codex-reasoning <effort|inherit>]
#     [--codex-planner-model <id|inherit>] [--codex-planner-reasoning <effort|inherit>]
#   Codex settings default to inherit: preserve local/parent choices.
#
#   The four model flags and --claude-model/--test-dir all default (see
#   apply_defaults() below) to the lineup two independent real projects
#   converged on: --claude-model sonnet, --builder-model
#   opencode-go/glm-5.3-flash, --reviewer-model opencode-go/minimax-m2.7,
#   --reviewer-fallback-model opencode-go/deepseek-v4-flash, --tester-model
#   hcnsec/auto, --test-dir e2e. Pin your own strings from `opencode models`
#   when your server's list differs — these are a starting point, not a
#   guarantee those exact ids still exist. --project-name has no default
#   and is still required.
#
# On a fresh scaffold this also writes .pipeline/.toolkit-version — a stamp
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
#     Rewrites .pipeline/.toolkit-version after you have accepted a merge.
#     This is the ONLY thing that updates the stamp besides a fresh scaffold.
#
# See docs/UPGRADING.md for the full workflow, CHANGELOG.md for what changed
# per release (impact-tagged: contract > safety > process > docs).
#
# Requires: bash, sed, diff, git (for the stamp's SHA/tag; falls back to
# "unknown"). Matches the rest of this toolkit's zero-runtime-dependency
# stance.
#
# Every run (scaffold or --update) checks `opencode --version` on PATH and
# warns (non-fatally) if it's missing, v1, or newer than the v2 these
# templates were written and verified against.
# END USAGE

set -eu

TOOLKIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES="$TOOLKIT_ROOT/templates"

TARGET=""
PROJECT_NAME=""
CLAUDE_MODEL=""
CODEX_MODEL=""
CODEX_REASONING=""
CODEX_PLANNER_MODEL=""
CODEX_PLANNER_REASONING=""
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
    --codex-model)              [ $# -ge 2 ] || die "--codex-model needs a value"; CODEX_MODEL="$2"; shift 2 ;;
    --codex-reasoning)          [ $# -ge 2 ] || die "--codex-reasoning needs a value"; CODEX_REASONING="$2"; shift 2 ;;
    --codex-planner-model)      [ $# -ge 2 ] || die "--codex-planner-model needs a value"; CODEX_PLANNER_MODEL="$2"; shift 2 ;;
    --codex-planner-reasoning)  [ $# -ge 2 ] || die "--codex-planner-reasoning needs a value"; CODEX_PLANNER_REASONING="$2"; shift 2 ;;
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

# These templates assume opencode v2 (password-gated `serve`, the `shell`
# permission action name, the hardcoded Basic Auth username `opencode`, the
# `opencode api` CLI subcommand scripts/oc.sh polls with — see
# templates/scripts/oc.sh.tmpl's own --auto comment for the full v1→v2
# migration writeup). Warn loudly rather than let someone hit a wall of 401s
# and "unrecognized flag" errors with no idea why. Non-fatal: this is
# information for the human running init.sh, not a reason to abort a
# scaffold or update.
# Extracts the major version number from an `opencode --version` line. Two
# passes: first anchored on the literal "opencode" prefix real builds use
# ("opencode v2.0.18") so a trailing runtime/build version in the same line
# (e.g. "opencode v2.0.18 (go v1.22.1)") can't be mistaken for opencode's own
# — a naive `.*[vV]<digits>.` pattern is greedy and matches the LAST such
# token in the line, not opencode's; anchoring avoids that class of bug
# entirely instead of just handling the one example found in review. Second
# pass (only if the first finds nothing) falls back to the first bare X.Y
# version-looking token anywhere in the line, in case some build prints a
# version with no leading "opencode"/"v" at all.
parse_opencode_major() {
  local s major
  s="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  major="$(printf '%s' "$s" | sed -n 's/^opencode[[:space:]]\{1,\}v\{0,1\}\([0-9][0-9]*\)\..*/\1/p')"
  if [ -z "$major" ]; then
    major="$(printf '%s' "$s" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)"
  fi
  printf '%s' "$major"
}

check_opencode_version() {
  if ! command -v opencode >/dev/null 2>&1; then
    printf '\ninit.sh: NOTE — opencode CLI not found on PATH.\n' >&2
    # shellcheck disable=SC2016 # literal backticks/quotes are intentional
    printf 'init.sh: scripts/oc.sh and scripts/team.sh need opencode v2 installed to run the pipeline (not to scaffold it). Install it before your first /feature or $feature run.\n\n' >&2
    return 0
  fi
  local ver_str major
  # No timeout here: a hung `opencode --version` hangs init.sh with it. Left
  # as-is because macOS ships no `timeout` by default and this toolkit has
  # no other cross-platform timeout resolution outside templates/scripts/
  # (see oc.sh.tmpl's $TIMEOUT_BIN) — acceptable for a one-shot version
  # check that every real build answers instantly.
  ver_str="$(opencode --version 2>/dev/null | head -1)"
  major="$(parse_opencode_major "$ver_str")"
  case "$major" in
    1)
      printf '\ninit.sh: WARNING — installed opencode is v1 (%s); these templates assume opencode v2.\n' "$ver_str" >&2
      # shellcheck disable=SC2016 # literal backticks/quotes are intentional
      printf 'init.sh: v1 lacks v2'"'"'s password-gated `serve` (auth will just fail), the `shell` permission action name (v1 used `bash`, so deny/ask rules silently will not match), the `opencode api` CLI subcommand scripts/oc.sh polls with, and the `--server` flag scripts/oc.sh passes to `opencode run` (v1 used `--attach`/`--dir`, both removed in v2). Running this toolkit'"'"'s generated scripts against opencode v1 as-is will fail or silently under-enforce permissions.\n' >&2
      # shellcheck disable=SC2016 # literal backticks/quotes are intentional
      printf 'init.sh: upgrade opencode first — `opencode upgrade` (or however you installed it) — then re-run.\n\n' >&2
      ;;
    2)
      : # current baseline these templates were written and verified against — nothing to say
      ;;
    '')
      printf '\ninit.sh: NOTE — could not parse an opencode version from %s — skipping the v1/v2 check.\n\n' "${ver_str:-<empty output>}" >&2
      ;;
    *)
      printf '\ninit.sh: NOTE — installed opencode is v%s (%s); these templates were last verified against v2.0.18.\n' "$major" "$ver_str" >&2
      printf 'init.sh: a newer major version may have changed the server API, permission schema, or --auto behavior again the way v1->v2 did. Check opencode'"'"'s own changelog and this toolkit'"'"'s CHANGELOG.md before trusting the generated scripts unchanged.\n\n' >&2
      ;;
  esac
}
check_opencode_version

STAMP="$TARGET/.pipeline/.toolkit-version"
STAMP_SOURCE="$STAMP"
[ -f "$STAMP_SOURCE" ] || STAMP_SOURCE="$TARGET/.agents/.toolkit-version"
# Never bootstrap a half-migrated runtime or move customized state implicitly.
if [ "$UPDATE" -eq 0 ] && { [ -f "$TARGET/.agents/TEMPLATE.md" ] || compgen -G "$TARGET/.agents/T-*.md" >/dev/null; }; then
  die "legacy .agents runtime state: complete migrations/02-pipeline-directory.md at a task boundary before bootstrapping"
fi
# Worker files, not the directory: an upstream scaffold already has .opencode/agents/
# (leader/planner) beside the legacy .opencode/agent/ workers.
if [ "$UPDATE" -eq 0 ] && [ -f "$TARGET/.opencode/agent/builder.md" ] && [ ! -f "$TARGET/.opencode/agents/builder.md" ]; then
  die "legacy .opencode/agent role layout: complete migrations/03-opencode-v2-agents-directory.md at a task boundary before bootstrapping"
fi

# Keep in sync with the number of check_pair/render lines below.
RENDER_TOTAL=31

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
    printf 'codex_model: %s\n' "$CODEX_MODEL"
    printf 'codex_reasoning: %s\n' "$CODEX_REASONING"
    printf 'codex_planner_model: %s\n' "$CODEX_PLANNER_MODEL"
    printf 'codex_planner_reasoning: %s\n' "$CODEX_PLANNER_REASONING"
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
# Every later run prefers explicit flags, then falls back to the provenance
# stamp. That makes both update triage and a plain missing-file bootstrap
# flag-free without changing render()'s never-overwrite behavior.

apply_defaults() {
  [ -n "$CLAUDE_MODEL" ] || CLAUDE_MODEL="sonnet"
  [ -n "$CODEX_MODEL" ] || CODEX_MODEL="inherit"
  [ -n "$CODEX_REASONING" ] || CODEX_REASONING="inherit"
  [ -n "$CODEX_PLANNER_MODEL" ] || CODEX_PLANNER_MODEL="inherit"
  [ -n "$CODEX_PLANNER_REASONING" ] || CODEX_PLANNER_REASONING="inherit"

  for value in "$CODEX_MODEL" "$CODEX_PLANNER_MODEL"; do
    [[ "$value" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ ]] || die "invalid Codex model id: $value"
  done
  for value in "$CODEX_REASONING" "$CODEX_PLANNER_REASONING"; do
    case "$value" in inherit|minimal|low|medium|high|xhigh|max|ultra) ;; *) die "invalid Codex reasoning effort: $value" ;; esac
  done
  [ -n "$TEST_DIR" ] || TEST_DIR="e2e"
  # Lineup two independent real projects converged on. Not a guarantee these
  # exact ids exist on your OpenCode server — run `opencode models` and pass
  # explicit flags when they don't.
  [ -n "$BUILDER_MODEL" ] || BUILDER_MODEL="opencode-go/glm-5.3-flash"
  [ -n "$REVIEWER_MODEL" ] || REVIEWER_MODEL="opencode-go/minimax-m2.7"
  [ -n "$REVIEWER_FALLBACK_MODEL" ] || REVIEWER_FALLBACK_MODEL="opencode-go/deepseek-v4-flash"
  [ -n "$TESTER_MODEL" ] || TESTER_MODEL="hcnsec/auto"
}

load_stamp_value() { # $1 = key, sets REPLY
  REPLY="$(sed -n "s/^$1: *//p" "$STAMP_SOURCE" | head -1)"
}

load_flags_from_stamp() {
  for spec in \
    "project_name|PROJECT_NAME" \
    "claude_model|CLAUDE_MODEL" \
    "codex_model|CODEX_MODEL" \
    "codex_reasoning|CODEX_REASONING" \
    "codex_planner_model|CODEX_PLANNER_MODEL" \
    "codex_planner_reasoning|CODEX_PLANNER_REASONING" \
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
}

# Recover an init value from the target's own scaffolded files (pre-stamp
# projects). Each pattern matches the substituted form of a __VAR__ token in
# exactly one rendered file. Sets REPLY; empty if not found.
recover_from_target() { # $1 = key
  REPLY=""
  local agent_dir="$TARGET/.opencode/agents"
  [ -f "$agent_dir/builder.md" ] || agent_dir="$TARGET/.opencode/agent"
  case "$1" in
    builder_model)
      REPLY="$(sed -n 's/^model: //p' "$agent_dir/builder.md" | head -1)" ;;
    reviewer_model)
      REPLY="$(sed -n 's/^model: //p' "$agent_dir/reviewer.md" | head -1)" ;;
    reviewer_fallback_model)
      # feature.md: "switch to `__REVIEWER_FALLBACK_MODEL__`"
      # shellcheck disable=SC2016 # literal backticks/quotes are intentional
      REPLY="$(sed -n 's/.*switch to `\([^`]*\)`.*/\1/p' \
        "$TARGET/.claude/commands/feature.md" | head -1)" ;;
    tester_model)
      REPLY="$(sed -n 's/^model: //p' "$agent_dir/tester.md" | head -1)" ;;
    claude_model)
      REPLY="$(sed -n 's/^model: //p' "$TARGET/.claude/agents/planner.md" 2>/dev/null | head -1)" ;;
    codex_model)
      REPLY="$(sed -n 's/^MODEL="\(.*\)"/\1/p' "$TARGET/scripts/codex-lead.sh" 2>/dev/null | head -1)" ;;
    codex_reasoning)
      REPLY="$(sed -n 's/^REASONING="\(.*\)"/\1/p' "$TARGET/scripts/codex-lead.sh" 2>/dev/null | head -1)" ;;
    codex_planner_model)
      REPLY="$(sed -n 's/^model = "\(.*\)"/\1/p' "$TARGET/.codex/agents/planner.toml" 2>/dev/null | head -1)" ;;
    codex_planner_reasoning)
      REPLY="$(sed -n 's/^model_reasoning_effort = "\(.*\)"/\1/p' "$TARGET/.codex/agents/planner.toml" 2>/dev/null | head -1)" ;;
    project_name)
      # team.sh: SESSION="__PROJECT_NAME__"
      REPLY="$(sed -n 's/^SESSION="\(.*\)"/\1/p' \
        "$TARGET/scripts/team.sh" | head -1)" ;;
    test_dir)
      # tester.md: "__TEST_DIR__/**": allow
      REPLY="$(sed -n 's/^ *"\(.*\)\/\*\*": allow.*/\1/p' \
        "$agent_dir/tester.md" | head -1)" ;;
  esac
}

if [ -f "$STAMP_SOURCE" ]; then
  load_flags_from_stamp
fi

if [ "$UPDATE" -eq 1 ]; then
  if [ ! -f "$STAMP_SOURCE" ]; then
    # No stamp (pre-v0.3.0 scaffold): recover the original values from the
    # target's own scaffolded files — they carry the substituted forms of the
    # same tokens. Anything still missing falls back to defaults, then to an
    # explicit-flags error below.
    for spec in \
      "project_name|PROJECT_NAME" \
      "claude_model|CLAUDE_MODEL" \
      "codex_model|CODEX_MODEL" \
      "codex_reasoning|CODEX_REASONING" \
      "codex_planner_model|CODEX_PLANNER_MODEL" \
      "codex_planner_reasoning|CODEX_PLANNER_REASONING" \
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

  # The model flags and --test-dir/--claude-model always end up set by
  # apply_defaults() above; only --project-name has no default and can
  # still be genuinely missing here (no stamp, and nothing recoverable from
  # the target's own files).
  [ -n "$PROJECT_NAME" ] || die "no provenance stamp at $STAMP and --project-name is unset
  (pass it once, exactly as at the original init, or scaffold freshly to get a stamp)"

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
fi

apply_defaults
CODEX_PLANNER_MODEL_LINE="# model inherits from the lead"
CODEX_PLANNER_REASONING_LINE="# reasoning effort inherits from the lead"
[ "$CODEX_PLANNER_MODEL" = inherit ] || CODEX_PLANNER_MODEL_LINE="model = \"$CODEX_PLANNER_MODEL\""
[ "$CODEX_PLANNER_REASONING" = inherit ] || CODEX_PLANNER_REASONING_LINE="model_reasoning_effort = \"$CODEX_PLANNER_REASONING\""

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
  -e "s|__CODEX_MODEL__|$CODEX_MODEL|g"
  -e "s|__CODEX_REASONING__|$CODEX_REASONING|g"
  -e "s|__CODEX_PLANNER_MODEL_LINE__|$CODEX_PLANNER_MODEL_LINE|g"
  -e "s|__CODEX_PLANNER_REASONING_LINE__|$CODEX_PLANNER_REASONING_LINE|g"
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
  check_pair "$TEMPLATES/codex/AGENTS.md.tmpl"              "$TARGET/AGENTS.md"
  check_pair "$TEMPLATES/codex/agents/planner.toml.tmpl"   "$TARGET/.codex/agents/planner.toml"
  check_pair "$TEMPLATES/codex/hooks.json.tmpl" "$TARGET/.codex/hooks.json"
  check_pair "$TEMPLATES/codex/hooks/session.py.tmpl" "$TARGET/scripts/codex-session.py"
  check_pair "$TEMPLATES/scripts/codex-lead.sh.tmpl" "$TARGET/scripts/codex-lead.sh"
  check_pair "$TEMPLATES/scripts/codex-preflight.sh.tmpl" "$TARGET/scripts/codex-preflight.sh"
  check_pair "$TOOLKIT_ROOT/skills/delegate/SKILL.md" "$TARGET/.agents/skills/delegate/SKILL.md"
  check_pair "$TOOLKIT_ROOT/skills/status-board/SKILL.md" "$TARGET/.agents/skills/status-board/SKILL.md"
  check_pair "$TOOLKIT_ROOT/skills/karpathy-guidelines/SKILL.md" "$TARGET/.agents/skills/karpathy-guidelines/SKILL.md"
  check_pair "$TEMPLATES/codex/skills/feature/SKILL.md.tmpl" "$TARGET/.agents/skills/feature/SKILL.md"
  check_pair "$TEMPLATES/codex/skills/toolkit-update/SKILL.md.tmpl" "$TARGET/.agents/skills/toolkit-update/SKILL.md"
  check_pair "$TEMPLATES/opencode/agents/builder.md.tmpl" "$TARGET/.opencode/agents/builder.md"
  check_pair "$TEMPLATES/opencode/agents/reviewer.md.tmpl" "$TARGET/.opencode/agents/reviewer.md"
  check_pair "$TEMPLATES/opencode/agents/tester.md.tmpl" "$TARGET/.opencode/agents/tester.md"
  check_pair "$TEMPLATES/opencode/agents/planner.md.tmpl" "$TARGET/.opencode/agents/planner.md"
  check_pair "$TEMPLATES/opencode/agents/leader.md.tmpl" "$TARGET/.opencode/agents/leader.md"
  check_pair "$TEMPLATES/opencode/commands/feature.md.tmpl" "$TARGET/.opencode/commands/feature.md"
  check_pair "$TEMPLATES/opencode/commands/toolkit-update.md.tmpl" "$TARGET/.opencode/commands/toolkit-update.md"
  check_pair "$TEMPLATES/agents-state/TEMPLATE.md.tmpl" "$TARGET/.pipeline/TEMPLATE.md"
  check_pair "$TEMPLATES/scripts/oc.sh.tmpl"               "$TARGET/scripts/oc.sh"
  check_pair "$TOOLKIT_ROOT/integrations/herdr/dashboard.py" "$TARGET/scripts/dashboard"
  check_pair "$TEMPLATES/scripts/team.sh.tmpl"             "$TARGET/scripts/team.sh"
  check_pair "$TEMPLATES/scripts/team-completion.bash.tmpl" "$TARGET/scripts/team-completion.bash"
  check_pair "$TEMPLATES/scripts/verify-state.sh.tmpl"     "$TARGET/scripts/verify-state.sh"
  check_pair "$TEMPLATES/scripts/verify-spec.sh.tmpl"      "$TARGET/scripts/verify-spec.sh"
  check_pair "$TEMPLATES/scripts/verify-models.sh.tmpl"    "$TARGET/scripts/verify-models.sh"
  check_pair "$TEMPLATES/scripts/promote-findings.sh.tmpl" "$TARGET/scripts/promote-findings.sh"
  check_pair "$TEMPLATES/scripts/bg-dispatch.sh.tmpl"     "$TARGET/scripts/bg-dispatch.sh"
  check_pair "$TEMPLATES/scripts/claude-review.sh.tmpl"   "$TARGET/scripts/claude-review.sh"

  CUR_SHA="$(git -C "$TOOLKIT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  # shellcheck disable=SC2016 # literal backticks/quotes are intentional
  printf 'init.sh: toolkit is at %s; checking %s rendered file(s)%s\n' \
    "$CUR_SHA" "$TOTAL" "${ONLY:+ (filtered by --only '$ONLY'; full set is $RENDER_TOTAL)}"
  if [ -f "$STAMP_SOURCE" ]; then
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
render "$TEMPLATES/codex/AGENTS.md.tmpl"              "$TARGET/AGENTS.md"
render "$TEMPLATES/codex/agents/planner.toml.tmpl"   "$TARGET/.codex/agents/planner.toml"
render "$TEMPLATES/codex/hooks.json.tmpl" "$TARGET/.codex/hooks.json"
render "$TEMPLATES/codex/hooks/session.py.tmpl" "$TARGET/scripts/codex-session.py"
render "$TEMPLATES/scripts/codex-lead.sh.tmpl" "$TARGET/scripts/codex-lead.sh"
render "$TEMPLATES/scripts/codex-preflight.sh.tmpl" "$TARGET/scripts/codex-preflight.sh"
render "$TOOLKIT_ROOT/skills/delegate/SKILL.md" "$TARGET/.agents/skills/delegate/SKILL.md"
render "$TOOLKIT_ROOT/skills/status-board/SKILL.md" "$TARGET/.agents/skills/status-board/SKILL.md"
render "$TOOLKIT_ROOT/skills/karpathy-guidelines/SKILL.md" "$TARGET/.agents/skills/karpathy-guidelines/SKILL.md"
render "$TEMPLATES/codex/skills/feature/SKILL.md.tmpl" "$TARGET/.agents/skills/feature/SKILL.md"
render "$TEMPLATES/codex/skills/toolkit-update/SKILL.md.tmpl" "$TARGET/.agents/skills/toolkit-update/SKILL.md"
render "$TEMPLATES/opencode/agents/builder.md.tmpl" "$TARGET/.opencode/agents/builder.md"
render "$TEMPLATES/opencode/agents/reviewer.md.tmpl" "$TARGET/.opencode/agents/reviewer.md"
render "$TEMPLATES/opencode/agents/tester.md.tmpl" "$TARGET/.opencode/agents/tester.md"
render "$TEMPLATES/opencode/agents/planner.md.tmpl" "$TARGET/.opencode/agents/planner.md"
render "$TEMPLATES/opencode/agents/leader.md.tmpl" "$TARGET/.opencode/agents/leader.md"
render "$TEMPLATES/opencode/commands/feature.md.tmpl" "$TARGET/.opencode/commands/feature.md"
render "$TEMPLATES/opencode/commands/toolkit-update.md.tmpl" "$TARGET/.opencode/commands/toolkit-update.md"
render "$TEMPLATES/agents-state/TEMPLATE.md.tmpl" "$TARGET/.pipeline/TEMPLATE.md"
render "$TEMPLATES/scripts/oc.sh.tmpl"               "$TARGET/scripts/oc.sh"
render "$TOOLKIT_ROOT/integrations/herdr/dashboard.py" "$TARGET/scripts/dashboard"
render "$TEMPLATES/scripts/team.sh.tmpl"             "$TARGET/scripts/team.sh"
render "$TEMPLATES/scripts/team-completion.bash.tmpl" "$TARGET/scripts/team-completion.bash"
render "$TEMPLATES/scripts/verify-state.sh.tmpl"     "$TARGET/scripts/verify-state.sh"
render "$TEMPLATES/scripts/verify-spec.sh.tmpl"      "$TARGET/scripts/verify-spec.sh"
render "$TEMPLATES/scripts/verify-models.sh.tmpl"    "$TARGET/scripts/verify-models.sh"
render "$TEMPLATES/scripts/promote-findings.sh.tmpl" "$TARGET/scripts/promote-findings.sh"
render "$TEMPLATES/scripts/bg-dispatch.sh.tmpl"     "$TARGET/scripts/bg-dispatch.sh"
render "$TEMPLATES/scripts/claude-review.sh.tmpl"   "$TARGET/scripts/claude-review.sh"

chmod +x "$TARGET/scripts/oc.sh" "$TARGET/scripts/team.sh" "$TARGET/scripts/dashboard" \
         "$TARGET/scripts/verify-state.sh" "$TARGET/scripts/verify-spec.sh" \
         "$TARGET/scripts/verify-models.sh" "$TARGET/scripts/promote-findings.sh" \
         "$TARGET/scripts/bg-dispatch.sh" "$TARGET/scripts/claude-review.sh" \
         "$TARGET/scripts/codex-lead.sh" \
         "$TARGET/scripts/codex-preflight.sh" 2>/dev/null || true

mkdir -p "$TARGET/.pipeline"
if [ "$FRESH_SCAFFOLD" -eq 1 ]; then
  touch "$TARGET/.pipeline/.needs-customization"
fi

# Provenance stamp — written exactly once, on a genuine fresh scaffold,
# never by --update (that would erase the baseline it exists to record).
# Same "computed before any render()" ordering rule as .needs-customization.
# Committed, unlike .oc-port: it describes the project, not this laptop.
if [ "$FRESH_SCAFFOLD" -eq 1 ] && [ ! -f "$STAMP" ]; then
  write_stamp
  printf 'init.sh: wrote %s\n' "$STAMP"
fi

# .pipeline/.oc-port and .pipeline/.claude-session-id.* are local machine state
# (which port scripts/team.sh last bound; which Claude conversation each
# tmux session name is pinned to), never something to commit. Codex also
# pins the exact lead id through its reviewed lifecycle hooks.
# Append-if-missing when the target is a git repo — additive only, in
# keeping with this script's never-overwrite stance; a project that ignores
# these differently is left alone.
if [ -d "$TARGET/.git" ]; then
  GITIGNORE="$TARGET/.gitignore"
  if ! grep -qxF '.pipeline/.oc-port' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# local opencode server port written by scripts/team.sh\n'
      printf '.pipeline/.oc-port\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .pipeline/.oc-port to %s\n' "$GITIGNORE"
  fi
  # opencode v2's `serve` always requires a password (v1 had none); this is
  # the secret scripts/team.sh generates for it — never commit it.
  if ! grep -qxF '.pipeline/.oc-password' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# local opencode server password written by scripts/team.sh\n'
      printf '.pipeline/.oc-password\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .pipeline/.oc-password to %s\n' "$GITIGNORE"
  fi
  if ! grep -qxF '.pipeline/.claude-session-id.*' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# local Claude session ids pinned per tmux session name by scripts/team.sh\n'
      printf '.pipeline/.claude-session-id.*\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .pipeline/.claude-session-id.* to %s\n' "$GITIGNORE"
  fi
  for pattern in '.pipeline/.codex-session-id.*' '.pipeline/.codex-started.*' '.pipeline/.codex-lead-lock.*'; do
    if ! grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null; then
      printf '\n%s\n' "$pattern" >> "$GITIGNORE"
      printf 'init.sh: added %s to %s\n' "$pattern" "$GITIGNORE"
    fi
  done
  # scripts/bg-dispatch.sh's per-dispatch pid/output files and the lead's
  # review briefs: runtime traces, not records (the state file is the record).
  for pattern in '/.pipeline/T-*.out' '/.pipeline/T-*.err' '/.pipeline/T-*.pid' '/.pipeline/T-*.brief'; do
    if ! grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null; then
      printf '\n%s\n' "$pattern" >> "$GITIGNORE"
      printf 'init.sh: added %s to %s\n' "$pattern" "$GITIGNORE"
    fi
  done
  if ! grep -qxF '.pipeline/logs/' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# per-call pipeline telemetry written by scripts/oc.sh\n'
      printf '.pipeline/logs/\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .pipeline/logs/ to %s\n' "$GITIGNORE"
  fi
fi

cat <<MSG

init.sh: done.

Next steps:
  1. Read every generated file before trusting it — especially
     .opencode/agents/reviewer.md's permission block. A blanket "deny" has
     failed to actually block a write before in at least one real project;
     verify it against your real OpenCode server rather than assuming it
     from the YAML.
  2. Start opencode serve (or run $TARGET/scripts/team.sh) so scripts/oc.sh
     has something to attach to.
  3. Start the lead with Claude, Codex, or OpenCode. In
     Claude run /feature; in Codex invoke the feature skill (for example,
     \$feature). In OpenCode run /feature; use scripts/team.sh --lead opencode
     for an OpenCode-only team. Auto selection prefers Claude, then Codex,
     then OpenCode.
     Load the "delegate" skill when available; it is the context-discipline
     half of this.
  4. In Codex, review/trust the generated hooks with /hooks (existing hooks
     are never overwritten). Run scripts/codex-preflight.sh from the lead
     sandbox. Git/config writes may need runtime approval after pipeline consent.
     Make sure $TARGET has real project-specific guidance. The generated
     AGENTS.md is lead integration plus an explicitly unpopulated guidance
     section; fill it when no project CLAUDE.md already supplies constraints.
  5. On the first feature run, the selected lead will notice
     .pipeline/.needs-customization and ask whether to fill the role files'
      generic pitfalls/hard-rules sections with this project's real ones.
      View task progress anytime: $TARGET/scripts/dashboard
      (Python 3.8+; no Herdr or model calls; --once prints a snapshot).
  6. Later, once the toolkit itself has moved on: bin/init.sh --update
     --target $TARGET shows a drift summary (exit 1 = something to merge),
     and /toolkit-update (Claude/OpenCode) or \$toolkit-update (Codex) walks your
     lead through the merge. Refresh the
     stamp afterwards: bin/init.sh --refresh-stamp --target $TARGET.

MSG
