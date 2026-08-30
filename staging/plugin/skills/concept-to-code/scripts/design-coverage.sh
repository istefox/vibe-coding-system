#!/bin/bash
# design-coverage v1.0 — DESIGN.md "## Screens" table -> plan-task coverage CHECKER
# (VCS-052; ADR-0181). Modeled on spec-coverage.sh's shape (rule 5), deliberately
# simpler: a screen name is prose, not an R-NN-shaped identifier, so there is no
# ADR-NNNN-style false-positive boundary to defend.
#
# CONTRACT. This is a CHECKER: the exit code is the policy channel.
#   exit 0  every DESIGN.md Screens-table row is cited by the plan file (or the
#           table itself declares zero rows is impossible to reach here — see exit 3)
#   exit 1  at least one screen uncovered              stdout: UNCOVERED<TAB><screen>
#   exit 2  bad invocation, unreadable file             stdout: nothing
#   exit 3  DID-NOT-RUN — the "## Screens" table parsed to zero data rows (rule 7,
#           denominator guard). Zero *matches* can be a correct clean pass; zero
#           *candidates* is a broken derivation, and from outside they look
#           identical, so this is never allowed to read as exit 0.
#
# Population guard (rule 18): a screen name is checked against the --plan file
# ONLY, never a repo-wide file set — screen names, like spec-coverage.sh's
# requirement ids, are feature-scoped and must not be satisfied by a stranger's file.
#
# Matching (rule 3): the screen cell has its markdown emphasis/backtick decoration
# stripped and its whitespace collapsed, then a plain case-insensitive containment
# test runs against the plan file's own flattened (whitespace-collapsed,
# lower-cased) text. This is intentionally not spec-coverage.sh's token-boundary
# regex machinery — the plan explicitly asks for "much simpler" here.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="design-coverage"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: design-coverage.sh --design <file> --plan <file>

stdout (machine channel): UNCOVERED<TAB><screen>, one line per uncovered screen.
Exit: 0 covered | 1 uncovered | 2 bad invocation | 3 DID-NOT-RUN (zero Screens rows).
EOF
}

DESIGN=""; PLAN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --design)
      [ $# -ge 2 ] || { usage "--design needs a file argument"; exit 2; }
      DESIGN="$2"; shift 2 ;;
    --plan)
      [ $# -ge 2 ] || { usage "--plan needs a file argument"; exit 2; }
      PLAN="$2"; shift 2 ;;
    -h|--help)
      usage; exit 2 ;;
    *)
      usage "unrecognized argument: $1"; exit 2 ;;
  esac
done

[ -n "$DESIGN" ] || { usage "--design is required"; exit 2; }
[ -n "$PLAN" ] || { usage "--plan is required"; exit 2; }
[ -r "$DESIGN" ] || { usage "cannot read --design file: $DESIGN"; exit 2; }
[ -r "$PLAN" ] || { usage "cannot read --plan file: $PLAN"; exit 2; }

SCREENS_FILE=$(mktemp)
trap 'rm -f "$SCREENS_FILE"' EXIT

# Extract data-row Screen cells from the first "## Screens" table: skip the
# header row and the |---|---| separator row, stop at the next heading or the
# first line that is no longer a table row.
awk '
  /^##[[:space:]]+Screens[[:space:]]*$/ { in_section = 1; rows = 0; next }
  in_section && /^##[[:space:]]/ { in_section = 0 }
  in_section && /^\|/ {
    rows++
    if (rows <= 2) next   # header row, then the |---|---| separator row
    line = $0
    sub(/^\|[[:space:]]*/, "", line)
    sub(/[[:space:]]*\|.*/, "", line)
    print line
  }
' "$DESIGN" > "$SCREENS_FILE"

rows=$(wc -l < "$SCREENS_FILE" | tr -d '[:space:]')

if [ "$rows" -eq 0 ]; then
  exit 3
fi

TAB=$(printf '\t')
PLAN_FLAT=$(tr '[:upper:]' '[:lower:]' < "$PLAN" | tr -s '[:space:]' ' ')

STATUS=0
while IFS= read -r screen; do
  [ -n "$screen" ] || continue
  clean=$(printf '%s' "$screen" | tr -d '`*_' | tr -s '[:space:]' ' ')
  clean=$(printf '%s' "$clean" | sed -e 's/^ *//' -e 's/ *$//')
  [ -n "$clean" ] || continue
  needle=$(printf '%s' "$clean" | tr '[:upper:]' '[:lower:]')
  case "$PLAN_FLAT" in
    *"$needle"*) : ;;
    *)
      printf 'UNCOVERED%s%s\n' "$TAB" "$clean"
      STATUS=1
      ;;
  esac
done < "$SCREENS_FILE"

exit "$STATUS"
