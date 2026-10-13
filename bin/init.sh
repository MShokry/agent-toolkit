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
#     [--leader all|claude|codex|opencode] [--extras all|none|dashboard,herdr,launcher]
#   --leader selects installed lead adapters, not model providers. OpenCode
#   workers remain available with any leader. Default all retains compatibility;
#   a selected leader defaults to no extras. Herdr includes the dashboard.
#   Existing stamps without profile fields retain all tools/extras. Selecting a
#   smaller profile never deletes existing files; refresh the stamp only after
#   reviewing and approving the new installation baseline.
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
#   A codex/<model-id> reviewer, fallback, or tester selects an optional native
#   Codex agent. Native workers require a Codex lead with live agent discovery;
#   other leaders must stop or obtain an approved alternative dispatch mechanism.
#
# On a fresh scaffold this also writes .agent-pipeline/.toolkit-version — a stamp
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
#     Rewrites .agent-pipeline/.toolkit-version after you have accepted a merge.
#     This is the ONLY thing that updates the stamp besides a fresh scaffold.
#
# Legacy .agents/ pipeline layouts: --update reads the old baseline without
# writes. Apply migrations/03-pipeline-directory.md with the lead before any
# plain scaffold or stamp refresh. Native .agents/skills/ must stay in place.
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
BUILDER_MODEL=""
REVIEWER_MODEL=""
REVIEWER_FALLBACK_MODEL=""
TESTER_MODEL=""
TEST_DIR=""
UPDATE=0
SHOW_DIFF=0
ONLY=""
REFRESH_STAMP=0
LEADER_TOOLS=""
EXTRAS=""

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
    --leader)                    [ $# -ge 2 ] || die "--leader needs a value"; LEADER_TOOLS="$2"; shift 2 ;;
    --extras)                    [ $# -ge 2 ] || die "--extras needs a value"; EXTRAS="$2"; shift 2 ;;
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

# Runtime templates require OpenCode v2: authenticated API calls, shell
# permissions, and --server dispatch. The version warning is informational;
# scaffolding does not require a running agent runtime.
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
    # shellcheck disable=SC2016 # Native skill spelling is intentionally literal.
    printf 'init.sh: .agent-pipeline/bin/oc.sh and .agent-pipeline/bin/team.sh need opencode v2 installed to run the pipeline (not to scaffold it). Install it before your first /feature or $feature run.\n\n' >&2
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
      # shellcheck disable=SC2016 # Command names in diagnostics are literal.
      printf 'init.sh: v1 lacks v2'"'"'s password-gated `serve` (auth will just fail), the `shell` permission action name (v1 used `bash`, so deny/ask rules silently will not match), the `opencode api` CLI subcommand .agent-pipeline/bin/oc.sh polls with, and the `--server` flag .agent-pipeline/bin/oc.sh passes to `opencode run` (v1 used `--attach`/`--dir`, both removed in v2). Running this toolkit'"'"'s generated scripts against opencode v1 as-is will fail or silently under-enforce permissions.\n' >&2
      # shellcheck disable=SC2016 # Instructions name a command, not substitution.
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

STAMP="$TARGET/.agent-pipeline/.toolkit-version"
LEGACY_LAYOUT=0
for legacy_file in "$TARGET/.agents/.toolkit-version" "$TARGET/.agents/TEMPLATE.md" "$TARGET"/.agents/T-*.md; do
  if [ -f "$legacy_file" ]; then LEGACY_LAYOUT=1; break; fi
done
if [ "$LEGACY_LAYOUT" -eq 1 ]; then
  [ "$REFRESH_STAMP" -eq 0 ] || die "migrate .agents/ pipeline files first; refusing to refresh the legacy baseline (see migrations/03-pipeline-directory.md)"
  [ "$UPDATE" -eq 1 ] || die "legacy pipeline layout at .agents/: run --update and apply migrations/03-pipeline-directory.md before scaffolding; no files were written"
  if [ -f "$TARGET/.agents/.toolkit-version" ]; then
    [ ! -f "$STAMP" ] || die "both pipeline provenance stamps exist; reconcile the collision before updating"
    STAMP="$TARGET/.agents/.toolkit-version"
  fi
  printf 'init.sh: directory migration required: .agents/ pipeline files -> .agent-pipeline/ (keep .agents/skills/). See migrations/03-pipeline-directory.md.\n'
fi

# Keep in sync with the number of check_pair/render lines below.
OLD_CORE_LAYOUT=0
for old_file in "$TARGET/.agent-pipeline/TEMPLATE.md" "$TARGET"/.agent-pipeline/T-*.md; do
  if [ -e "$old_file" ] || [ -L "$old_file" ]; then OLD_CORE_LAYOUT=1; break; fi
done
if [ "$OLD_CORE_LAYOUT" -eq 1 ]; then
  [ "$REFRESH_STAMP" -eq 0 ] || die "apply migration 04's approved bulk layout move before refreshing provenance"
  [ "$UPDATE" -eq 1 ] || die "old toolkit layout: use --update and bin/migrate-layout.py plan/apply before scaffolding; no files written"
  printf 'init.sh: migration 04 required: tasks -> .agent-pipeline/tasks/; runtime -> .agent-pipeline/bin/. Preview only.\n'
fi
RENDER_TOTAL=0

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
    printf 'leader_tools:  %s\n' "$LEADER_TOOLS"
    printf 'extras:        %s\n' "$EXTRAS"
    printf 'layout_schema: 2\n'
    # Refresh owned fields only. Project extensions and dated notes are evidence,
    # not disposable generator output; never erase them during acceptance.
    if [ -f "$STAMP" ]; then
      awk '
        /^[a-z_]+:/ {
          key=$0; sub(/:.*/, "", key)
          if (key ~ /^(toolkit_sha|toolkit_tag|scaffolded|project_name|claude_model|builder_model|reviewer_model|reviewer_fallback_model|tester_model|test_dir|leader_tools|extras|layout_schema)$/) next
        }
        { print }
      ' "$STAMP"
    fi
  } > "$STAMP.tmp"
  mv "$STAMP.tmp" "$STAMP"
}

# --- resolve flag values -----------------------------------------------------
# Fresh scaffolds take explicit flags or the defaults below.
# Every later run prefers explicit flags, then falls back to the provenance
# stamp. That makes both update triage and a plain missing-file bootstrap
# flag-free without changing render()'s never-overwrite behavior.

apply_defaults() {
  [ -n "$LEADER_TOOLS" ] || LEADER_TOOLS="all"
  if [ -z "$EXTRAS" ]; then
    if [ "$LEADER_TOOLS" = all ]; then EXTRAS=all; else EXTRAS=none; fi
  fi
  case "$LEADER_TOOLS" in all|claude|codex|opencode) ;; *) die "invalid --leader: $LEADER_TOOLS" ;; esac
  case "$EXTRAS" in
    all|none) ;;
    *)
      case "$EXTRAS" in ,*|*,|*,,*) die "invalid --extras: $EXTRAS" ;; esac
      local extra
      local -a requested_extras
      IFS=, read -r -a requested_extras <<< "$EXTRAS"
      for extra in "${requested_extras[@]}"; do
        case "$extra" in dashboard|herdr|launcher) ;; *) die "invalid --extras: $EXTRAS" ;; esac
      done ;;
  esac
  [ -n "$CLAUDE_MODEL" ] || CLAUDE_MODEL="sonnet"
  [ -n "$TEST_DIR" ] || TEST_DIR="e2e"
  # Lineup two independent real projects converged on. Not a guarantee these
  # exact ids exist on your OpenCode server — run `opencode models` and pass
  # explicit flags when they don't.
  [ -n "$BUILDER_MODEL" ] || BUILDER_MODEL="opencode-go/glm-5.3-flash"
  [ -n "$REVIEWER_MODEL" ] || REVIEWER_MODEL="opencode-go/minimax-m2.7"
  [ -n "$REVIEWER_FALLBACK_MODEL" ] || REVIEWER_FALLBACK_MODEL="opencode-go/deepseek-v4-flash"
  [ -n "$TESTER_MODEL" ] || TESTER_MODEL="hcnsec/auto"
  case "$BUILDER_MODEL" in
    codex/*|claude/*) die "--builder-model selects an OpenCode provider/model; native implementation is a per-task codex-dev or senior-dev choice" ;;
  esac
  # These ids are embedded in TOML strings. Reject empty/unsafe native slugs
  # before any rendering or stamp refresh, without adding a parser dependency.
  for model in "$REVIEWER_MODEL" "$REVIEWER_FALLBACK_MODEL" "$TESTER_MODEL"; do
    case "$model" in
      codex/*|claude/*) [[ "${model#*/}" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || die "invalid native model id: $model" ;;
    esac
  done
}

load_stamp_value() { # $1 = key, sets REPLY
  REPLY="$(sed -n "s/^$1: *//p" "$STAMP" | head -1)"
}

load_flags_from_stamp() {
  for spec in \
    "project_name|PROJECT_NAME" \
    "claude_model|CLAUDE_MODEL" \
    "builder_model|BUILDER_MODEL" \
    "reviewer_model|REVIEWER_MODEL" \
    "reviewer_fallback_model|REVIEWER_FALLBACK_MODEL" \
    "tester_model|TESTER_MODEL" \
    "test_dir|TEST_DIR" \
    "leader_tools|LEADER_TOOLS" \
    "extras|EXTRAS"; do
    key="${spec%%|*}"; var="${spec##*|}"
    if [ -z "${!var}" ]; then
      load_stamp_value "$key"
      # printf -v: portable indirect assignment (bash's ${!var:=x} does
      # not actually assign on the macOS-shipped bash 3.2).
      [ -n "$REPLY" ] && printf -v "$var" '%s' "$REPLY"
    fi
  done
  if [ -z "$REVIEWER_FALLBACK_MODEL" ]; then
    REVIEWER_FALLBACK_MODEL=none
    printf 'init.sh: legacy stamp has no reviewer fallback; keeping it disabled (none). Configure a new fallback only with explicit approval.\n'
  fi
  # A legacy baseline owned the complete scaffold. An explicit smaller leader
  # selection must not accidentally infer a lean extras baseline for that stamp.
  if [ -z "$EXTRAS" ]; then
    load_stamp_value extras
    [ -n "$REPLY" ] || EXTRAS=all
  fi
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
      REPLY="$(sed -n 's/^model: //p' "$TARGET/.opencode/agent/reviewer.md" | head -1)"
      if [ -z "$REPLY" ] && [ -f "$TARGET/.codex/agents/reviewer.toml" ]; then
        REPLY="$(sed -n 's/^model = "\([^"]*\)".*/codex\/\1/p' "$TARGET/.codex/agents/reviewer.toml" | head -1)"
      fi
      if [ -z "$REPLY" ] && [ -f "$TARGET/.claude/agents/reviewer.md" ]; then
        REPLY="$(sed -n 's/^model: /claude\//p' "$TARGET/.claude/agents/reviewer.md" | head -1)"
      fi ;;
    reviewer_fallback_model)
      # Modern neutral assignment line, with historical feature prose fallback.
      local flow="$TARGET/.claude/commands/feature.md"
      [ ! -f "$TARGET/.agents/roles/leader.md" ] || flow="$TARGET/.agents/roles/leader.md"
      [ ! -f "$TARGET/.agent-pipeline/roles/leader.md" ] || flow="$TARGET/.agent-pipeline/roles/leader.md"
      # shellcheck disable=SC2016 # Match literal Markdown backticks.
      REPLY="$(sed -n -e 's/^reviewer fallback `\([^`]*\)`.*/\1/p' \
        -e 's/.*switch to `\([^`]*\)`.*/\1/p' "$flow" | head -1)" ;;
    tester_model)
      REPLY="$(sed -n 's/^model: //p' "$TARGET/.opencode/agent/tester.md" | head -1)"
      if [ -z "$REPLY" ] && [ -f "$TARGET/.codex/agents/tester.toml" ]; then
        REPLY="$(sed -n 's/^model = "\([^"]*\)".*/codex\/\1/p' "$TARGET/.codex/agents/tester.toml" | head -1)"
      fi ;;
    claude_model)
      REPLY="$(sed -n 's/^model: //p' "$TARGET/.claude/agents/planner.md" 2>/dev/null | head -1)" ;;
    project_name)
      # team.sh: SESSION="__PROJECT_NAME__"
      REPLY="$(sed -n 's/^SESSION="\(.*\)"/\1/p' \
        "$TARGET/.agent-pipeline/bin/team.sh" 2>/dev/null | head -1)"
      if [ -z "$REPLY" ]; then
        REPLY="$(sed -n 's/^SESSION="\(.*\)"/\1/p' "$TARGET/scripts/team.sh" 2>/dev/null | head -1)"
      fi
      if [ -z "$REPLY" ] && [ -f "$TARGET/AGENTS.md" ]; then
        REPLY="$(sed -n 's/^# \(.*\) — project entrypoint$/\1/p' "$TARGET/AGENTS.md" | head -1)"
      fi ;;
    test_dir)
      # tester.md: "__TEST_DIR__/**": allow
      REPLY="$(sed -n 's/^ *"\(.*\)\/\*\*": allow.*/\1/p' \
        "$TARGET/.opencode/agent/tester.md" 2>/dev/null | head -1)"
      if [ -z "$REPLY" ] && [ -f "$TARGET/.agent-pipeline/roles/tester.md" ]; then
        # shellcheck disable=SC2016 # Match literal Markdown backticks.
        REPLY="$(sed -n 's/^scope under `\(.*\)\/`.*/\1/p' "$TARGET/.agent-pipeline/roles/tester.md" | head -1)"
      fi ;;
  esac
}

if [ -f "$STAMP" ]; then
  load_flags_from_stamp
fi

if [ "$UPDATE" -eq 1 ]; then
  if [ ! -f "$STAMP" ]; then
    # New lean layouts can be recovered without adding unselected tools.
    # Legacy layouts have no neutral contracts and retain the all-tools default.
    if [ -f "$TARGET/.agent-pipeline/roles/leader.md" ]; then
      if [ -z "$LEADER_TOOLS" ]; then
        found_leaders=""
        [ ! -f "$TARGET/.claude/commands/feature.md" ] || found_leaders="${found_leaders}claude "
        [ ! -f "$TARGET/.agents/skills/feature/SKILL.md" ] || found_leaders="${found_leaders}codex "
        [ ! -f "$TARGET/.opencode/commands/feature.md" ] || found_leaders="${found_leaders}opencode "
        case "$found_leaders" in
          'claude codex opencode ') LEADER_TOOLS=all ;;
          'claude '| 'codex '| 'opencode ') LEADER_TOOLS="${found_leaders% }" ;;
          *) die "cannot infer mixed/missing lead profile; pass --leader explicitly" ;;
        esac
      fi
      if [ -z "$EXTRAS" ] && [ -f "$TARGET/.agent-pipeline/README.md" ]; then
        # Recover only this generated metadata field, never instructions. The
        # dependency files alone cannot distinguish launcher from dashboard,launcher.
        # apply_defaults validates the recovered flag; report it for human review.
        EXTRAS="$(sed -n 's/^Installed lead profile: .*Optional extras: \*\*\([^*]*\)\*\*.*/\1/p' \
          "$TARGET/.agent-pipeline/README.md" | head -1)"
      fi
      if [ -z "$EXTRAS" ]; then
        EXTRAS=""
        [ ! -f "$TARGET/.agent-pipeline/bin/dashboard" ] || EXTRAS=dashboard
        [ ! -f "$TARGET/.agent-pipeline/bin/herdr-team.sh" ] || EXTRAS="${EXTRAS:+$EXTRAS,}herdr"
        [ ! -f "$TARGET/.agent-pipeline/bin/team.sh" ] || EXTRAS="${EXTRAS:+$EXTRAS,}launcher"
        [ -n "$EXTRAS" ] || EXTRAS=none
      fi
    fi
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
    if [ -z "$REVIEWER_FALLBACK_MODEL" ]; then
      # A missing historical assignment is not consent to a new provider.
      if [ -f "$TARGET/.agent-pipeline/roles/leader.md" ] \
          || [ -f "$TARGET/.agents/roles/leader.md" ] \
          || [ -f "$TARGET/.claude/commands/feature.md" ]; then
        die "cannot recover reviewer fallback from unstamped project; pass --reviewer-fallback-model <provider/model> or none explicitly; nothing written"
      fi
    fi
    apply_defaults
    RECOVERED=""
    for var in PROJECT_NAME BUILDER_MODEL REVIEWER_MODEL REVIEWER_FALLBACK_MODEL TESTER_MODEL LEADER_TOOLS EXTRAS; do
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

# Stamped plain runs do not call apply_defaults() until the normal branch;
# stamped --update needs the same native-model validation before render.
apply_defaults

# Captured before any render() call touches the target, so it reflects
# whether this is the very first scaffold of this project — used below to
# decide whether to drop the first-run customization marker and write the
# provenance stamp.
FRESH_SCAFFOLD=0
if [ ! -f "$STAMP" ] && [ ! -f "$TARGET/.claude/commands/feature.md" ] \
    && [ ! -f "$TARGET/.agent-pipeline/tasks/TEMPLATE.md" ]; then FRESH_SCAFFOLD=1; fi

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
  -e "s|__CODEX_TESTER_MODEL__|${TESTER_MODEL#codex/}|g"
  -e "s|__LEADER_TOOLS__|$LEADER_TOOLS|g"
  -e "s|__EXTRAS__|$EXTRAS|g"
)

# Portable README embeds the leader body from ONE source, not a hand-maintained
# policy copy. Render and read-only preview use exactly the same composition.
render_content() {
  if [ "$1" = "$TEMPLATES/pipeline/README.md.tmpl" ]; then
    awk -v contract="$TEMPLATES/pipeline/roles/leader.md.tmpl" '
      $0 == "__LEADER_CONTRACT__" {
        n = 0
        while ((getline line < contract) > 0) { if (++n > 1) print line }
        close(contract)
        next
      }
      { print }
    ' "$1" | sed "${SED_ARGS[@]}"
  else
    sed "${SED_ARGS[@]}" "$1"
  fi
}

# The same reviewer contract renders primary and fallback with distinct names
# and pinned models. Locally scoped substitutions leave all other renders alone.
codex_reviewer_pair() { # name, model, render/check_pair
  local name="$1" model="${2#codex/}"
  local -a SED_ARGS=("${SED_ARGS[@]}"
    -e "s|__CODEX_REVIEWER_NAME__|$name|g"
    -e "s|__CODEX_REVIEWER_MODEL__|$model|g")
  "$3" "$TEMPLATES/codex/agents/reviewer.toml.tmpl" "$TARGET/.codex/agents/$name.toml"
}

claude_reviewer_pair() { # name, model, render/check_pair
  local name="$1" model="${2#claude/}"
  local -a SED_ARGS=("${SED_ARGS[@]}"
    -e "s|__CLAUDE_REVIEWER_NAME__|$name|g"
    -e "s|__CLAUDE_REVIEWER_MODEL__|$model|g")
  "$3" "$TEMPLATES/claude/agents/reviewer.md.tmpl" "$TARGET/.claude/agents/$name.md"
}

# Retain the shared OpenCode role body/permissions as a readable contract, but
# never put a native model alias into its runtime model metadata. Explicit
# OpenCode dispatches still pass their model through oc.sh.
opencode_role_pair() { # role, selected model, render/check_pair
  local role="$1" model="$2"
  local -a SED_ARGS=("${SED_ARGS[@]}")
  case "$model" in codex/*|claude/*) SED_ARGS+=(-e '/^model: /d') ;; esac
  "$3" "$TEMPLATES/opencode/agent/$role.md.tmpl" "$TARGET/.opencode/agent/$role.md"
}

has_leader() { [ "$LEADER_TOOLS" = all ] || [ "$LEADER_TOOLS" = "$1" ]; }
has_extra() {
  [ "$EXTRAS" = all ] && return 0
  case ",$EXTRAS," in *",$1,"*) return 0 ;; esac
  return 1
}
has_native_review() {
  case "$REVIEWER_MODEL" in "$1/"*) return 0 ;; esac
  case "$REVIEWER_FALLBACK_MODEL" in "$1/"*) return 0 ;; esac
  return 1
}
selected_file() {
  local rel="${1#"$TARGET/"}"
  # Contracts are shared; adapters are installed only for selected backends.
  case "$rel" in
    .agent-pipeline/adapters/claude.md)
      has_leader claude || has_native_review claude ;;
    .agent-pipeline/bin/claude-review.sh)
      [ "$LEADER_TOOLS" = all ] || has_native_review claude ;;
    .agent-pipeline/adapters/codex.md)
      has_leader codex || has_native_review codex || [[ "$TESTER_MODEL" = codex/* ]] ;;
    .claude/agents/reviewer*.md|.codex/agents/reviewer*.toml|.codex/agents/tester.toml) return 0 ;;
    .claude/*) has_leader claude ;;
    .codex/hooks.json|.agent-pipeline/bin/codex-lead.sh|.agent-pipeline/bin/codex-session.py)
      has_extra launcher ;;
    .codex/*|.agents/skills/*) has_leader codex ;;
    .opencode/agents/*|.opencode/commands/*) has_leader opencode ;;
    .opencode/agent/reviewer.md)
      [ "$LEADER_TOOLS" = all ] && return 0
      case "$REVIEWER_MODEL,$REVIEWER_FALLBACK_MODEL" in codex/*,codex/*|codex/*,claude/*|claude/*,codex/*|claude/*,claude/*) return 1 ;; esac
      return 0 ;;
    .opencode/agent/tester.md)
      [ "$LEADER_TOOLS" = all ] || [[ "$TESTER_MODEL" != codex/* ]] ;;
    .agent-pipeline/bin/herdr-team.sh) has_extra herdr ;;
    .agent-pipeline/bin/dashboard) has_extra dashboard || has_extra herdr || has_extra launcher ;;
    .agent-pipeline/bin/team.sh|.agent-pipeline/bin/team-completion.bash) has_extra launcher ;;
    *) return 0 ;;
  esac
}

# One manifest for count, additive render, and read-only update preview.
scaffold_files() {
  local mode="$1" role backend
  "$mode" "$TEMPLATES/pipeline/README.md.tmpl" "$TARGET/.agent-pipeline/README.md"
  for role in leader planner implementer reviewer tester; do
    "$mode" "$TEMPLATES/pipeline/roles/$role.md.tmpl" "$TARGET/.agent-pipeline/roles/$role.md"
  done
  for backend in opencode codex claude; do
    "$mode" "$TEMPLATES/pipeline/adapters/$backend.md.tmpl" "$TARGET/.agent-pipeline/adapters/$backend.md"
  done
  "$mode" "$TEMPLATES/claude/commands/toolkit-update.md.tmpl" "$TARGET/.agent-pipeline/update.md"
  "$mode" "$TEMPLATES/claude/agents/planner.md.tmpl" "$TARGET/.claude/agents/planner.md"
  "$mode" "$TEMPLATES/claude/agents/senior-dev.md.tmpl" "$TARGET/.claude/agents/senior-dev.md"
  "$mode" "$TEMPLATES/claude/commands/feature.md.tmpl" "$TARGET/.claude/commands/feature.md"
  "$mode" "$TEMPLATES/claude/commands/toolkit-update.md.tmpl" "$TARGET/.claude/commands/toolkit-update.md"
  "$mode" "$TEMPLATES/codex/AGENTS.md.tmpl" "$TARGET/AGENTS.md"
  "$mode" "$TEMPLATES/codex/agents/planner.toml.tmpl" "$TARGET/.codex/agents/planner.toml"
  "$mode" "$TEMPLATES/codex/agents/codex-dev.toml.tmpl" "$TARGET/.codex/agents/codex-dev.toml"
  "$mode" "$TEMPLATES/codex/hooks.json.tmpl" "$TARGET/.codex/hooks.json"
  "$mode" "$TEMPLATES/scripts/codex-lead.sh.tmpl" "$TARGET/.agent-pipeline/bin/codex-lead.sh"
  "$mode" "$TEMPLATES/scripts/codex-session.py.tmpl" "$TARGET/.agent-pipeline/bin/codex-session.py"
  "$mode" "$TEMPLATES/scripts/claude-review.sh.tmpl" "$TARGET/.agent-pipeline/bin/claude-review.sh"
  "$mode" "$TEMPLATES/scripts/herdr-team.sh.tmpl" "$TARGET/.agent-pipeline/bin/herdr-team.sh"
  case "$REVIEWER_MODEL" in claude/*) claude_reviewer_pair reviewer "$REVIEWER_MODEL" "$mode" ;; esac
  case "$REVIEWER_FALLBACK_MODEL" in claude/*) claude_reviewer_pair reviewer_fallback "$REVIEWER_FALLBACK_MODEL" "$mode" ;; esac
  case "$REVIEWER_MODEL" in codex/*) codex_reviewer_pair reviewer "$REVIEWER_MODEL" "$mode" ;; esac
  case "$REVIEWER_FALLBACK_MODEL" in codex/*) codex_reviewer_pair reviewer_fallback "$REVIEWER_FALLBACK_MODEL" "$mode" ;; esac
  case "$TESTER_MODEL" in codex/*) "$mode" "$TEMPLATES/codex/agents/tester.toml.tmpl" "$TARGET/.codex/agents/tester.toml" ;; esac
  "$mode" "$TEMPLATES/codex/skills/feature/SKILL.md.tmpl" "$TARGET/.agents/skills/feature/SKILL.md"
  "$mode" "$TEMPLATES/codex/skills/toolkit-update/SKILL.md.tmpl" "$TARGET/.agents/skills/toolkit-update/SKILL.md"
  "$mode" "$TEMPLATES/opencode/agent/builder.md.tmpl" "$TARGET/.opencode/agent/builder.md"
  opencode_role_pair reviewer "$REVIEWER_MODEL" "$mode"
  opencode_role_pair tester "$TESTER_MODEL" "$mode"
  "$mode" "$TEMPLATES/opencode/agents/planner.md.tmpl" "$TARGET/.opencode/agents/planner.md"
  "$mode" "$TEMPLATES/opencode/agents/leader.md.tmpl" "$TARGET/.opencode/agents/leader.md"
  "$mode" "$TEMPLATES/opencode/commands/feature.md.tmpl" "$TARGET/.opencode/commands/feature.md"
  "$mode" "$TEMPLATES/opencode/commands/toolkit-update.md.tmpl" "$TARGET/.opencode/commands/toolkit-update.md"
  "$mode" "$TEMPLATES/agents-state/TEMPLATE.md.tmpl" "$TARGET/.agent-pipeline/tasks/TEMPLATE.md"
  "$mode" "$TEMPLATES/scripts/oc.sh.tmpl" "$TARGET/.agent-pipeline/bin/oc.sh"
  "$mode" "$TEMPLATES/scripts/bg-dispatch.sh.tmpl" "$TARGET/.agent-pipeline/bin/bg-dispatch.sh"
  "$mode" "$TEMPLATES/scripts/verify-models.sh.tmpl" "$TARGET/.agent-pipeline/bin/verify-models.sh"
  "$mode" "$TOOLKIT_ROOT/integrations/herdr/dashboard.py" "$TARGET/.agent-pipeline/bin/dashboard"
  "$mode" "$TEMPLATES/scripts/team.sh.tmpl" "$TARGET/.agent-pipeline/bin/team.sh"
  "$mode" "$TEMPLATES/scripts/team-completion.bash.tmpl" "$TARGET/.agent-pipeline/bin/team-completion.bash"
  "$mode" "$TEMPLATES/scripts/verify-state.sh.tmpl" "$TARGET/.agent-pipeline/bin/verify-state.sh"
  "$mode" "$TEMPLATES/scripts/verify-spec.sh.tmpl" "$TARGET/.agent-pipeline/bin/verify-spec.sh"
  "$mode" "$TEMPLATES/scripts/promote-findings.sh.tmpl" "$TARGET/.agent-pipeline/bin/promote-findings.sh"
  "$mode" "$TEMPLATES/scripts/task-record.py.tmpl" "$TARGET/.agent-pipeline/bin/task-record.py"
  "$mode" "$TOOLKIT_ROOT/bin/migrate-layout.py" "$TARGET/.agent-pipeline/bin/migrate-layout.py"
}
count_pair() { if selected_file "$2"; then RENDER_TOTAL=$((RENDER_TOTAL + 1)); fi; }
scaffold_files count_pair

if [ "$UPDATE" -eq 1 ]; then
  # --- triage mode -------------------------------------------------------
  # Summary first, hunks on demand (docs/UPGRADING.md). A wall of
  # raw diff is why nobody merged updates; a list of files plus the
  # changelog's impact tags is what makes merging a decision instead of a
  # chore.
  DIFFS=()
  NEW_UPSTREAM=()
  MATCHED=0
  TOTAL=0

  # shellcheck disable=SC2317,SC2329 # Used through the shared manifest callback.
  note_result() { # $1 = status (same|differ|new), $2 = dest
    TOTAL=$((TOTAL + 1))
    case "$1" in
      differ) DIFFS+=("$2") ;;
      new)    NEW_UPSTREAM+=("$2") ;;
      same)   MATCHED=$((MATCHED + 1)) ;;
    esac
  }

  # shellcheck disable=SC2317,SC2329 # Invoked indirectly by manifest.
  check_pair() { # $1 = template, $2 = destination
    selected_file "$2" || return 0
    if [ -n "$ONLY" ]; then
      case "$2" in *"$ONLY"*) ;; *) return ;; esac
    fi
    tmp="$(mktemp)"
    render_content "$1" > "$tmp"
    local live
    live="$2"
    if [ "$OLD_CORE_LAYOUT" -eq 1 ] && [ ! -f "$live" ]; then
      case "$2" in
        "$TARGET/.agent-pipeline/tasks/TEMPLATE.md") live="$TARGET/.agent-pipeline/TEMPLATE.md" ;;
        "$TARGET/.agent-pipeline/bin/"*) live="$TARGET/scripts/${2##*/}" ;;
      esac
    fi
    if [ "$LEGACY_LAYOUT" -eq 1 ] && [ "$2" = "$TARGET/.agent-pipeline/tasks/TEMPLATE.md" ] && [ ! -f "$2" ]; then
      live="$TARGET/.agents/TEMPLATE.md"
    fi
    if [ ! -f "$live" ]; then
      note_result new "$2"
    elif diff -u "$live" "$tmp" > /dev/null 2>&1; then
      note_result same "$2"
    else
      note_result differ "$2"
      if [ "$SHOW_DIFF" -eq 1 ]; then
        printf 'init.sh: upstream changes for %s\n' "$2"
        diff -u "$live" "$tmp" || true
        printf '\n'
      fi
    fi
    rm -f "$tmp"
  }

  scaffold_files check_pair

  CUR_SHA="$(git -C "$TOOLKIT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  printf 'init.sh: toolkit is at %s; checking %s rendered file(s)%s\n' \
    "$CUR_SHA" "$TOTAL" "${ONLY:+ (filtered by --only $ONLY; full set is $RENDER_TOTAL)}"
  if [ -f "$STAMP" ]; then
    load_stamp_value toolkit_sha
    STAMPED_SHA="$REPLY"
    load_stamp_value scaffolded
    printf 'init.sh: this project scaffolded from %s (%s)\n' "${STAMPED_SHA:-unknown}" "${REPLY:-unknown date}"
  fi

  DRIFT="$LEGACY_LAYOUT"
  [ "$OLD_CORE_LAYOUT" -eq 0 ] || DRIFT=1
  if [ "${#NEW_UPSTREAM[@]}" -gt 0 ]; then
    DRIFT=1
    if [ "$LEGACY_LAYOUT" -eq 1 ]; then
      printf 'init.sh: %s new upstream file(s) — complete the directory migration before re-running without --update:\n' "${#NEW_UPSTREAM[@]}"
    else
      printf 'init.sh: %s new upstream file(s) — re-run with the same flags without --update to add:\n' "${#NEW_UPSTREAM[@]}"
    fi
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
  selected_file "$2" || return 0
  if [ -f "$2" ]; then
    printf 'init.sh: skip (exists) %s\n' "$2"
    return
  fi
  mkdir -p "$(dirname "$2")"
  render_content "$1" > "$2"
  printf 'init.sh: wrote %s\n' "$2"
}

scaffold_files render

chmod +x "$TARGET/.agent-pipeline/bin/oc.sh" "$TARGET/.agent-pipeline/bin/bg-dispatch.sh" "$TARGET/.agent-pipeline/bin/team.sh" "$TARGET/.agent-pipeline/bin/dashboard" \
          "$TARGET/.agent-pipeline/bin/codex-lead.sh" "$TARGET/.agent-pipeline/bin/claude-review.sh" \
          "$TARGET/.agent-pipeline/bin/herdr-team.sh" \
          "$TARGET/.agent-pipeline/bin/verify-state.sh" "$TARGET/.agent-pipeline/bin/verify-spec.sh" \
          "$TARGET/.agent-pipeline/bin/promote-findings.sh" "$TARGET/.agent-pipeline/bin/verify-models.sh" 2>/dev/null || true

mkdir -p "$TARGET/.agent-pipeline"
if [ "$FRESH_SCAFFOLD" -eq 1 ]; then
  touch "$TARGET/.agent-pipeline/.needs-customization"
fi

# Provenance stamp — written exactly once, on a genuine fresh scaffold,
# never by --update (that would erase the baseline it exists to record).
# Same "computed before any render()" ordering rule as .needs-customization.
# Committed, unlike .oc-port: it describes the project, not this laptop.
if [ "$FRESH_SCAFFOLD" -eq 1 ] && [ ! -f "$STAMP" ]; then
  write_stamp
  printf 'init.sh: wrote %s\n' "$STAMP"
fi

# .agent-pipeline/.oc-port and .agent-pipeline/.claude-session-id.* are local machine state
# (which port scripts/team.sh last bound; which Claude conversation each
# tmux session name is pinned to), never something to commit. Codex exact lead
# pins, launch markers, and locks are local machine state as well.
# Append-if-missing when the target is a git repo — additive only, in
# keeping with this script's never-overwrite stance; a project that ignores
# these differently is left alone.
if [ -e "$TARGET/.git" ]; then
  GITIGNORE="$TARGET/.gitignore"
  if ! grep -qxF '.agent-pipeline/.oc-port' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# local opencode server port written by scripts/team.sh\n'
      printf '.agent-pipeline/.oc-port\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .agent-pipeline/.oc-port to %s\n' "$GITIGNORE"
  fi
  # opencode v2's `serve` always requires a password (v1 had none); this is
  # the secret scripts/team.sh generates for it — never commit it.
  if ! grep -qxF '.agent-pipeline/.oc-password' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# local opencode server password written by scripts/team.sh\n'
      printf '.agent-pipeline/.oc-password\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .agent-pipeline/.oc-password to %s\n' "$GITIGNORE"
  fi
  if ! grep -qxF '.agent-pipeline/.claude-session-id.*' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# local Claude session ids pinned per tmux session name by scripts/team.sh\n'
      printf '.agent-pipeline/.claude-session-id.*\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .agent-pipeline/.claude-session-id.* to %s\n' "$GITIGNORE"
  fi
  if ! grep -qxF '.agent-pipeline/logs/' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# per-call pipeline telemetry written by scripts/oc.sh\n'
      printf '.agent-pipeline/logs/\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .agent-pipeline/logs/ to %s\n' "$GITIGNORE"
  fi
  for pattern in '.agent-pipeline/.codex-session-id.*' '.agent-pipeline/.codex-started.*' '.agent-pipeline/.codex-lead-lock.*'; do
    if ! grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null; then
      printf '\n# local Codex lead launch state\n%s\n' "$pattern" >> "$GITIGNORE"
      printf 'init.sh: added %s to %s\n' "$pattern" "$GITIGNORE"
    fi
  done
  for pattern in '.agent-pipeline/.layout-backup-*/' '.agent-pipeline/.layout-lock/'; do
    if ! grep -qxF "$pattern" "$GITIGNORE" 2>/dev/null; then
      printf '\n# private bulk-layout migration backup/lock\n%s\n' "$pattern" >> "$GITIGNORE"
    fi
  done
  if ! grep -qxF '.agent-pipeline/prompts/' "$GITIGNORE" 2>/dev/null; then
    {
      printf '\n# generated pipeline dispatch prompts\n'
      printf '.agent-pipeline/prompts/\n'
    } >> "$GITIGNORE"
    printf 'init.sh: added .agent-pipeline/prompts/ to %s\n' "$GITIGNORE"
  fi
fi

cat <<MSG

init.sh: done.

Next steps:
  1. Review selected role contracts/native adapters and verify exact generated
     permissions live. Text/configuration is not sandbox enforcement evidence.
  2. Fill real project constraints/test commands in CLAUDE.md or AGENTS.md.
     Explicit workers load their role only, not the leader workflow.
  3. Connect .agent-pipeline/bin/oc.sh to an authenticated OpenCode server for worker calls.
     Start your selected lead ($LEADER_TOOLS); Claude/OpenCode use /feature,
     Codex uses \$feature. Optional helpers are installed only by --extras.
  4. Later use --update --target $TARGET for read-only drift preview. Reconcile
     at an idle boundary; --refresh-stamp explicitly records an approved merge.
     Profiles: --leader $LEADER_TOOLS --extras $EXTRAS (existing files are never deleted).

MSG
