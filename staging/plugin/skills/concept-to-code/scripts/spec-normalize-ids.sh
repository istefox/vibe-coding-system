#!/bin/bash
# spec-normalize-ids.sh v1.0 — repair a SPEC whose requirement IDs are plain bullets (issue #171;
# ADR-0072 §D2).
#
# WHAT THIS IS. `- R-01 — the system does X` and `- [ ] R-01 — the system does X` declare the same
# requirement; only the second is one the coverage checker can read. This adds the missing marker
# and touches nothing else. It is NORMALISATION, not regeneration: re-running the producer
# (interview-driver, spec-from-issue) would redo the interview or rebuild from the issue and throw
# away a SPEC that has already passed Gate 1 (ADR-0072 §D1).
#
# WHAT IT WILL NOT DO. It rewrites a line only when ALL of these hold, per spec-id-predicate.awk:
# the line is inside a recognised requirements section, is a plain bullet (not already a checklist
# item), and its text begins with a well-formed R-NN token OR a well-formed R-NN token wrapped in a
# leading run of `*`/`_` (ADR-0122, issue #291) — e.g. `- **R-01** — …`. The emphasis is PRESERVED
# in the rewrite: only the checklist marker is added, so `- **R-01** — x` becomes
# `- [ ] **R-01** — x`, never `- [ ] R-01 — x`. This required no code change here — the predicate
# is shared with spec-coverage.sh, so the widened tolerance reaches this script for free. Prose,
# nested notes, headings and anything outside those sections are left byte-identical.
#
# CONTRACT.
#   dry run (default): prints a unified diff to stdout and writes nothing; prints the sentinel
#                      CLEAN when there is nothing to repair. Exit 0 either way.
#   --apply:           rewrites the file in place and prints the same diff, so the caller can show
#                      what it did rather than assert that it did something.
#   exit 2  bad invocation, or the SPEC is missing/unreadable
#   exit 3  awk could not run the predicates — the repair DID NOT RUN, which is not the same as
#           finding nothing to repair (the distinction ADR-0048 §D7 and secret-scan.sh both make).
#
# The caller decides whether to apply. concept-to-code Step 5 applies automatically and prints the
# diff afterwards (ADR-0072 §D3) — safe because ADR-0071's Gate 4.0 committed the planning
# artifacts, so `git checkout -- <spec>` reverses it. On a tree where the SPEC is NOT committed,
# --apply is destructive in the ordinary sense that any in-place edit is: there is nothing to
# revert to.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

SELF="spec-normalize-ids"
DIR=$(cd "$(dirname "$0")" && pwd)
PRED_TASK="$DIR/plan-task-predicate.awk"
PRED_SPEC="$DIR/spec-id-predicate.awk"

usage() {
  [ "${1:-}" = "" ] || printf '%s: %s\n' "$SELF" "$1" >&2
  cat >&2 <<'EOF'
usage: spec-normalize-ids.sh --spec <file> [--apply]

Rewrites plain `- R-NN — …` bullets inside a recognised requirements section into
`- [ ] R-NN — …` checklist items, the only form spec-coverage.sh reads. Content untouched.

stdout: a unified diff of what would change (or did), or the sentinel CLEAN.
Exit: 0 ran | 2 bad invocation or unreadable SPEC | 3 awk could not run — the repair did not run.
EOF
  exit 2
}

SPEC=""; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --spec)  shift; [ $# -gt 0 ] || usage "--spec needs a file"; SPEC="$1"; shift ;;
    --apply) APPLY=1; shift ;;
    -h|--help) usage "" ;;
    *) usage "unknown argument: $1" ;;
  esac
done

[ -n "$SPEC" ] || usage "--spec is required"
[ -f "$SPEC" ] && [ -r "$SPEC" ] || { printf '%s: SPEC not found or unreadable: %s\n' "$SELF" "$SPEC" >&2; exit 2; }
for _p in "$PRED_TASK" "$PRED_SPEC"; do
  [ -f "$_p" ] && [ -r "$_p" ] || { printf '%s: predicate not found: %s\n' "$SELF" "$_p" >&2; exit 3; }
done

TMPD=$(mktemp -d) || { printf '%s: cannot create a temp directory\n' "$SELF" >&2; exit 3; }
trap 'rm -rf "$TMPD"' EXIT

cat >"$TMPD/normalize.awk" <<'AWKEOF'
BEGIN { insec = 0 }
{
  line = $0
  # A heading at H1/H2 closes the section, exactly as spec-coverage.sh's parser does. Kept in step
  # with it by spec-coverage.test.sh, not by hope.
  hl = heading_level(line)
  if (insec && hl >= 1 && hl <= 2) insec = 0
  if (is_spec_section_heading(line)) { insec = 1; print line; next }
  if (insec && is_near_miss_bullet(line)) { print to_checklist_item(line); next }
  print line
}
AWKEOF

awk -f "$PRED_TASK" -f "$PRED_SPEC" -f "$TMPD/normalize.awk" "$SPEC" >"$TMPD/out.md" 2>/dev/null \
  || { printf '%s: awk failed on %s — the repair did not run\n' "$SELF" "$SPEC" >&2; exit 3; }

# A zero-byte result on a non-empty input means awk produced nothing rather than a rewritten file.
# Writing that over the SPEC would destroy it, so treat it as did-not-run.
if [ -s "$SPEC" ] && [ ! -s "$TMPD/out.md" ]; then
  printf '%s: awk produced an empty result for a non-empty SPEC — the repair did not run\n' "$SELF" >&2
  exit 3
fi

if cmp -s "$SPEC" "$TMPD/out.md"; then
  echo CLEAN
  exit 0
fi

diff -u "$SPEC" "$TMPD/out.md" 2>/dev/null | sed "s|$TMPD/out.md|$SPEC (normalized)|"

if [ "$APPLY" -eq 1 ]; then
  cat "$TMPD/out.md" >"$SPEC" || { printf '%s: could not write %s\n' "$SELF" "$SPEC" >&2; exit 3; }
fi
exit 0
