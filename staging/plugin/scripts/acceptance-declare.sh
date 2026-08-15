#!/bin/bash
# acceptance-declare v1.0 (issue #439 Wave 2, ADR-0142). Reconciles a SPEC's requirement set with
# an ACCEPTANCE.md, in BOTH directions.
#
# Usage: acceptance-declare.sh --spec <SPEC.md> --acceptance <ACCEPTANCE.md> [--predicates <dir>]
#
# THIS IS A CHECKER, NOT A REPORTER, and the distinction matters because its two closest neighbours
# go the other way. `acceptance-run.sh` and `acceptance-adapter-swift.sh` sit one directory away and
# always exit 0, signalling on stdout, because a failing product is a RESULT. Here a SPEC and an
# ACCEPTANCE that disagree is not a result, it is a defect in the documents, so the exit code is the
# policy channel — the same idiom as `spec-coverage.sh`, this script's sibling in subject matter.
# Do not copy one block's branching into the other (ADR-0047/ADR-0048).
#
#   exit 0  reconciled                     stdout: nothing
#   exit 1  a testable criterion has no acceptance case   stdout: UNDECLARED<TAB>R-NN
#   exit 2  invalid invocation, unreadable file           stdout: nothing
#   exit 3  structural / could-not-run     stdout: ORPHAN<TAB>R-NN — a case naming an id the SPEC
#                                                   does not declare
#                                                  CONTRADICTION<TAB>R-NN — declared (no-test: …)
#                                                   in the SPEC and given a case anyway
#                                                  NO-IDS — the SPEC declares nothing
#                                                  NO-PREDICATE — the shared awk files are missing
#
# BOTH DIRECTIONS (CLAUDE.md rule 8). Checking that every testable criterion has a case is blind by
# construction to a case that names an id the SPEC never declared — a criterion someone deleted
# from the SPEC leaves its acceptance case behind, and the forward check reports clean.
#
# `NO-IDS` IS EXIT 3, AND THAT IS A DELIBERATE DIVERGENCE FROM spec-coverage.sh, which exits 0
# silently on a SPEC declaring no ids (ADR-0048 §D7/§D8, for backward compatibility with SPECs
# written before ids existed). This script has no legacy corpus: a reconciliation whose subject set
# is empty covers nothing and would read as clean, which is rule 9. The divergence is stated at both
# ends so the next reader does not "fix" the two into agreement.
#
# THE PREDICATE IS LOADED, NEVER RESTATED. `plan-task-predicate.awk` and `spec-id-predicate.awk`
# define what a checklist item, a requirements heading and an item's text ARE, and spec-coverage.sh
# reads the same two files. A second definition here would disagree eventually, and the symptom
# would be a criterion reported UNDECLARED because one side stripped a separator the other kept.
# An unresolvable predicate is exit 3 and NEVER 0: a check that could not run must not read as a
# check that found nothing (rule 4).
#
# Bash 3.2 clean.
set -u

SELF="acceptance-declare"
SPEC=""; ACC=""; PREDIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --spec)       SPEC="${2:-}";   shift 2 ;;
    --acceptance) ACC="${2:-}";    shift 2 ;;
    --predicates) PREDIR="${2:-}"; shift 2 ;;
    -h|--help)
      printf 'usage: %s --spec <SPEC.md> --acceptance <ACCEPTANCE.md> [--predicates <dir>]\n' "$SELF"
      exit 0 ;;
    *) printf '%s: unknown argument: %s\n' "$SELF" "$1" >&2; exit 2 ;;
  esac
done

[ -n "$SPEC" ] || { printf '%s: --spec is required\n' "$SELF" >&2; exit 2; }
[ -n "$ACC" ]  || { printf '%s: --acceptance is required\n' "$SELF" >&2; exit 2; }
[ -r "$SPEC" ] || { printf '%s: --spec not readable: %s\n' "$SELF" "$SPEC" >&2; exit 2; }
[ -r "$ACC" ]  || { printf '%s: --acceptance not readable: %s\n' "$SELF" "$ACC" >&2; exit 2; }

# Two-tier resolution, source tree then deployed tree. Readability, not the execute bit: these are
# awk program files loaded with -f, never executed, and staging/ is inconsistent about that bit.
#
# `--predicates` is AUTHORITATIVE, not a first preference. Falling through to another directory when
# the caller named one would hand back a different predicate than the one asked for, and the run
# would look normal — the same shape as a check that agrees with itself. It also made the exit-3
# branch unreachable from outside, which is a state nothing can produce (rule 17): the first probe
# of this script reported exit 1 where NO-PREDICATE was expected, and that is how this was found.
_here=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
if [ -n "$PREDIR" ]; then
  CANDIDATES="$PREDIR"
else
  CANDIDATES="$_here/../skills/concept-to-code/scripts
$HOME/.claude/skills/concept-to-code/scripts"
fi
while IFS= read -r d; do
  [ -n "$d" ] || continue
  if [ -r "$d/plan-task-predicate.awk" ] && [ -r "$d/spec-id-predicate.awk" ]; then
    P1="$d/plan-task-predicate.awk"; P2="$d/spec-id-predicate.awk"; break
  fi
done <<CANDEOF
$CANDIDATES
CANDEOF
if [ -z "${P1:-}" ]; then
  printf 'NO-PREDICATE\n'
  printf '%s: plan-task-predicate.awk / spec-id-predicate.awk not resolvable — the check DID NOT RUN\n' "$SELF" >&2
  exit 3
fi

TMP=$(mktemp -d) || { printf '%s: mktemp failed\n' "$SELF" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# --- one parser, two documents ------------------------------------------------------------------
# WANT_NOTEST=1 emits the `(no-test: …)` column as well. Both documents are read by the SAME
# program: an ACCEPTANCE.md parsed by a looser rule than the SPEC would report a mismatch that only
# the parsers disagree about.
cat >"$TMP/parse.awk" <<'AWKEOF'
BEGIN { collecting = 0 }
{
  line = $0
  if (heading_level(line) >= 2) {
    collecting = is_spec_section_heading(line) ? 1 : 0
    next
  }
  if (!collecting) next
  if (!is_checklist_item(line)) next
  txt = strip_emphasis(item_text(line))
  if (!match(txt, /^R-[0-9][0-9]([^0-9]|$)/)) next
  tok = substr(txt, RSTART, 4)
  rest = strip_sep(strip_emphasis(substr(txt, 5)))
  notest = 0
  low = tolower(rest)
  # The SAME marker search spec-coverage.sh performs, including the 20-character reason floor: a
  # `(no-test:)` whose reason is too short is NOT an exemption there, so it must not be one here.
  if (match(low, /\(no-test:/)) {
    after = substr(rest, RSTART + RLENGTH)
    reason = after
    if (match(after, /\)/)) reason = substr(after, 1, RSTART - 1)
    reason = strip_sep(reason)
    if (length(reason) >= 20) notest = 1
  }
  printf "%s\t%d\n", tok, notest
}
AWKEOF

awk -f "$P1" -f "$P2" -f "$TMP/parse.awk" "$SPEC" 2>/dev/null | sort -u > "$TMP/spec.tsv"
awk -f "$P1" -f "$P2" -f "$TMP/parse.awk" "$ACC"  2>/dev/null | sort -u > "$TMP/acc.tsv"

cut -f1 "$TMP/spec.tsv" | sort -u > "$TMP/spec.ids"
cut -f1 "$TMP/acc.tsv"  | sort -u > "$TMP/acc.ids"
awk -F'\t' '$2==1 {print $1}' "$TMP/spec.tsv" | sort -u > "$TMP/notest.ids"
comm -23 "$TMP/spec.ids" "$TMP/notest.ids" > "$TMP/testable.ids"

SPEC_N=$(grep -c . "$TMP/spec.ids" 2>/dev/null || true)
case "${SPEC_N:-}" in ''|*[!0-9]*) SPEC_N=0 ;; esac

# Rule 9, and the divergence declared in the header: an empty subject set is not a clean run.
if [ "$SPEC_N" -eq 0 ]; then
  printf 'NO-IDS\n'
  printf '%s: %s declares no R-NN requirements, so this reconciliation has no subject\n' "$SELF" "$SPEC" >&2
  exit 3
fi

RC=0
# Structural first (exit 3 outranks exit 1): a document that contradicts itself is a different
# repair from a criterion nobody wrote a case for, and reporting the milder one first would send
# the reader to the wrong fix.
comm -23 "$TMP/acc.ids" "$TMP/spec.ids" > "$TMP/orphan.ids"
comm -12 "$TMP/acc.ids" "$TMP/notest.ids" > "$TMP/contradiction.ids"
while IFS= read -r id; do [ -n "$id" ] && { printf 'ORPHAN\t%s\n' "$id"; RC=3; }; done < "$TMP/orphan.ids"
while IFS= read -r id; do [ -n "$id" ] && { printf 'CONTRADICTION\t%s\n' "$id"; RC=3; }; done < "$TMP/contradiction.ids"

comm -23 "$TMP/testable.ids" "$TMP/acc.ids" > "$TMP/undeclared.ids"
UNDEC=0
while IFS= read -r id; do [ -n "$id" ] && { printf 'UNDECLARED\t%s\n' "$id"; UNDEC=1; }; done < "$TMP/undeclared.ids"
[ "$UNDEC" -eq 1 ] && [ "$RC" -eq 0 ] && RC=1

TESTABLE_N=$(grep -c . "$TMP/testable.ids" 2>/dev/null || true)
case "${TESTABLE_N:-}" in ''|*[!0-9]*) TESTABLE_N=0 ;; esac
ACC_N=$(grep -c . "$TMP/acc.ids" 2>/dev/null || true)
case "${ACC_N:-}" in ''|*[!0-9]*) ACC_N=0 ;; esac
printf '%s: spec=%s testable=%s acceptance=%s\n' "$SELF" "$SPEC_N" "$TESTABLE_N" "$ACC_N" >&2

exit "$RC"
