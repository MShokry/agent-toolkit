#!/usr/bin/env bash
#
# Mechanically copies "Findings for docs" lines from a task state file into
# the project docs they name. This is how a review finding that's true
# beyond one task (a platform gotcha, a design gap, an incident) ends up
# documented without either (a) the lead retyping it by hand, or (b)
# granting a review/implementer agent direct write access to project docs.
#
# No LLM call. No agent ever writes to docs/ directly through this path —
# a role only *proposes* a line (in its own state-file scope), and this
# script does the literal, non-interpretive copy. That keeps project
# documentation out of the blast radius of an agent permission mistake.
#
# Findings are written as:
#   - [docs/SOME-DOC.md] one-line finding text
# under a "## Findings for docs" heading in the task's .agents/T-<id>.md.
#
# Usage: scripts/promote-findings.sh T-03

set -eu

ID="${1:?usage: promote-findings.sh <task-id, e.g. T-03>}"
FILE=".agents/${ID}.md"
[ -f "$FILE" ] || { echo "promote-findings.sh: no such file: $FILE" >&2; exit 1; }

LINES="$(awk '/^## Findings for docs/{f=1;next} /^## /{f=0} f && /^- \[/' "$FILE")"

if [ -z "$LINES" ]; then
  echo "promote-findings.sh: no findings tagged for promotion in $FILE"
  exit 0
fi

DATE="$(date +%Y-%m-%d)"

printf '%s\n' "$LINES" | while IFS= read -r line; do
  DOC="$(printf '%s\n' "$line" | sed -n 's/^- \[\([^]]*\)\].*/\1/p')"
  TEXT="$(printf '%s\n' "$line" | sed 's/^- \[[^]]*\] *//')"
  if [ -z "$DOC" ]; then
    echo "promote-findings.sh: skip malformed line: $line" >&2
    continue
  fi
  mkdir -p "$(dirname "$DOC")"
  [ -f "$DOC" ] || printf '# %s\n' "$(basename "$DOC" .md)" > "$DOC"
  if grep -qF "$TEXT" "$DOC" 2>/dev/null; then
    echo "promote-findings.sh: already present, skipped: $DOC <- $TEXT"
    continue
  fi
  {
    printf '\n## From %s — %s\n\n' "$ID" "$DATE"
    printf -- '- %s\n' "$TEXT"
  } >> "$DOC"
  echo "promote-findings.sh: appended to $DOC: $TEXT"
done
