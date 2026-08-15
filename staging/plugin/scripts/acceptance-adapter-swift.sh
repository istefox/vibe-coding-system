#!/bin/bash
# acceptance-adapter-swift v1.0 (issue #439, ADR-0141). Turns an Xcode result bundle's test list
# into an acceptance verdict per requirement id.
#
# INPUT   the JSON emitted by:
#           xcrun xcresulttool get test-results tests --path <bundle> --schema-version 0.1.0
#         on stdin, or via --json-file. The schema version is PINNED by the caller on purpose: a
#         future Xcode default bump must be caught here, not absorbed silently.
# OUTPUT  see the contract below.
#
# THIS IS A REPORTER, NOT A CHECKER (ADR-0047/ADR-0048 idiom). It exits 0 on any determined
# outcome, including a total failure, and the CALLER gates on stdout. Exit 2 means the invocation
# itself was wrong (bad flag, unreadable --json-file) and nothing was measured.
#
#   THE CALLER IDIOM, stated because getting it wrong is silent:
#     out=$(acceptance-adapter-swift.sh --json-file "$f") || { bad invocation; }
#     case "$out" in *'ACCEPTANCE-HALT'*) ... ;; esac   # check HALT FIRST
#     printf '%s\n' "$out" | grep '^ACCEPTANCE-RESULT '
#   NEVER `[ -n "$out" ]` — this reporter always prints something, so that test is true on a clean
#   run, on a total failure and on a halt alike. There is no CLEAN sentinel here because
#   ACCEPTANCE-RESULT is always emitted when a result exists; absence of it means a HALT.
#
# THE CONTRACT
#   ACCEPTANCE-RESULT pass=<n> fail=<m> skip=<k> total=<t> declared=<d|-> missing=<x|-> unbound=<u>
#   ACCEPTANCE-CASE <R-NN> PASS|FAIL|SKIP|MISSING          (one per criterion, sorted)
#   ACCEPTANCE-HALT <reason>                               (could not measure; no RESULT is emitted)
#
#   Every RESULT field earns its place by making a specific failure visible:
#     skip      a skipped criterion is not a passing one (CLAUDE.md rule 4).
#     total     pass+fail+skip == total is self-checked; a mismatch halts, because a parser that
#               dropped a node must never report a clean total.
#     declared  the reverse direction (rule 8) — a criterion declared and never executed. With no
#               --declared file both declared and missing read `-`, so "the reverse check did not
#               run" is VISIBLE in the line rather than absent from it.
#     unbound   guards the denominator (rule 7). total=0 with unbound=300 (a suite that ran, with
#               nothing bound to an id) and total=0 with unbound=0 (nothing ran at all) are
#               different defects with different repairs, so they halt with different reasons.
#               Zero bound cases is never a clean pass.
#
# RESULT MAPPING. `TestResult` is a five-value enum in Apple's own schema, verified live against
# Xcode 26.6 on 2026-08-15. The mapping below is a JUDGEMENT, not a translation:
#     Passed             -> PASS
#     Failed             -> FAIL
#     Expected Failure   -> FAIL   for an acceptance criterion, "expected to fail" means not met
#     unknown / absent   -> FAIL   indeterminate must not read as a pass; FAIL is the loud direction
#     Skipped            -> SKIP
# A criterion is PASS only when at least one bound case exists AND every bound case passed. Any FAIL
# wins; otherwise any SKIP wins. Duplicate bindings aggregate, they do not overwrite.
#
# A MEASURED TRAP: a Skipped case still carries a `Failure Message` child ("Test skipped - ..."),
# observed in a real bundle. Any heuristic keyed on that child classifies a skip as a failure.
# `result` is the only authority; do not "improve" this by looking at children.
#
# BINDING. The id is read from the Test Case node's `name`, matched as
#     (^|[^A-Za-z0-9]|test)R-?([0-9]{1,3})(?![0-9])
# and normalised to R-NN (zero-padded to two digits, so R-6 and R-06 are ONE criterion). The
# leading alternation is load-bearing and was fixed by a real fixture, not reasoned about:
#   testR01_greetReturnsHello()   -> R-01   XCTest, the id follows the mandatory `test` prefix
#   R-06: the user can archive    -> R-06   Swift Testing display name, id at the start
#   testERROR6_boundaryProbe()    -> none   the trap: a bare word-boundary rule binds this to R-6
# Known limit: `testTeardownR5_thing()` does not bind. Put the id immediately after `test`.
# `tags` is NOT emitted for XCTest cases (measured: zero nodes carried it), so name is the only
# available channel in that framework.
#
# Bash 3.2 clean — no associative arrays; aggregation is awk over sorted lines.
set -u

SELF="acceptance-adapter-swift"
JSON_FILE=""; DECLARED=""

while [ $# -gt 0 ]; do
  case "$1" in
    --json-file) JSON_FILE="${2:-}"; shift 2 ;;
    --declared)  DECLARED="${2:-}";  shift 2 ;;
    -h|--help)
      printf 'usage: %s [--json-file <xcresulttool-tests.json>] [--declared <ACCEPTANCE.md>]\n' "$SELF"
      exit 0 ;;
    *) printf '%s: unknown argument: %s\n' "$SELF" "$1" >&2; exit 2 ;;
  esac
done

halt() { printf 'ACCEPTANCE-HALT %s\n' "$1"; exit 0; }

command -v jq >/dev/null 2>&1 || halt "jq-absent — the adapter cannot read the result bundle"

TMP=$(mktemp -d) || { printf '%s: mktemp failed\n' "$SELF" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

if [ -n "$JSON_FILE" ]; then
  # READABLE, not "regular file". `-f` excludes pipes, FIFOs, process substitution and /dev/stdin,
  # all of which are perfectly readable and all of which a caller may legitimately pass. The first
  # version tested -f and worked on macOS, where bash materialises a heredoc as a temp file, while
  # failing on Linux, where bash 5 gives it a pipe — green locally, red on CI. That is the SECOND
  # wrong-permission-bit check in this feature (the adapter resolver in acceptance-run.sh tested -x
  # for a file it invokes as `bash <path>`), so the class is named here rather than fixed quietly.
  [ -r "$JSON_FILE" ] || {
    printf '%s: --json-file not readable: %s\n' "$SELF" "$JSON_FILE" >&2; exit 2; }
  cat "$JSON_FILE" > "$TMP/in.json"
else
  cat > "$TMP/in.json"
fi

jq -e . "$TMP/in.json" >/dev/null 2>&1 || halt "json-unparseable — not the output of xcresulttool get test-results tests"

# THE ID PATTERN, DEFINED EXACTLY ONCE. Three consumers read it: the binding pass, the bound-case
# count, and the reverse check against the declared set. They answer ONE question — "what is an id
# here" — so under CLAUDE.md rule 6 they must not be three literals. Two that drifted would make the
# reverse check match nothing and report a clean `missing=0`, which is the quietest way this file
# could fail. Passed into jq with --arg rather than pasted, so there is one string and one plant.
IDRE='(^|[^A-Za-z0-9]|test)R-?([0-9]{1,3})(?![0-9])'

# THE DECLARED SIDE IS A DIFFERENT DOMAIN AND GETS A DIFFERENT PATTERN (issue #439 Wave 2).
# --declared reads a MARKDOWN declaration file, which is spec-coverage.sh's domain, not a Swift
# method name. IDRE above is necessarily loose because a Swift identifier cannot contain a hyphen;
# applying that looseness to prose reads ids the rest of the system does not recognise. Measured
# 2026-08-15 across the 48 files in this repo carrying an R-NN checklist, the two diverge on exactly
# one string — `ISSUE-R-013`, in ADR-0048, which is the counterexample that ADR itself names.
#
# So the declared side takes spec-coverage.sh's BOUNDARY: `_` excluded on the left, hyphen required,
# exactly two digits. What it does NOT copy is that file's right anchor `([^0-9]|$)`, which CONSUMES
# the following character — correct for the `grep -q` membership tests it is used for there, and
# wrong here, where a global extraction would swallow the separator and miss the next id in
# `R-01 R-02`. A lookahead is the same rule without the consumption, and the harness pins the
# behaviour on both files' counterexamples rather than pinning the two strings to be equal.
DECLRE='(^|[^A-Za-z0-9_])(R-[0-9][0-9])(?![0-9])'

# --- extract every Test Case node, then its bound ids -------------------------------------------
# One jq pass emits `<id>\t<TOKEN>` per (case, id) binding, and a second counts the case nodes.
# They are separate because the counts must be taken over the CASE population, not the BINDING
# population: a case bound to two ids would otherwise inflate the denominator it is measured against.
jq -r --arg re "$IDRE" '
  def norm: (tonumber) as $n | if $n < 10 then "0\($n)" else "\($n)" end;
  def token:
    if   . == "Passed"  then "PASS"
    elif . == "Skipped" then "SKIP"
    else "FAIL" end;                                   # Failed, Expected Failure, unknown, absent
  [.. | objects | select(.nodeType? == "Test Case")]
  | .[]
  | . as $c
  | ([ ($c.name // "")
       | match($re; "g")
       | .captures[1].string | norm ] | unique) as $ids
  | if ($ids | length) == 0 then empty
    else $ids[] | "R-\(.)\t\(($c.result // "unknown") | token)"
    end
' "$TMP/in.json" > "$TMP/bindings.tsv" 2>"$TMP/jq.err" || halt "json-walk-failed — $(tr '\n' ' ' <"$TMP/jq.err" | cut -c1-120)"

NCASES=$(jq -r '[.. | objects | select(.nodeType? == "Test Case")] | length' "$TMP/in.json" 2>/dev/null)
case "${NCASES:-}" in ''|*[!0-9]*) halt "case-count-underivable — the Test Case population could not be counted" ;; esac

NBOUND=$(awk -F'\t' 'NF>=1 && $1!="" {print $1}' "$TMP/bindings.tsv" | sort -u | wc -l | tr -d ' ')
# Bound CASES, not bound criteria: unbound is a statement about test cases.
NBOUNDCASES=$(jq -r --arg re "$IDRE" '
  [.. | objects | select(.nodeType? == "Test Case")
   | select((.name // "") | test($re))] | length
' "$TMP/in.json" 2>/dev/null)
case "${NBOUNDCASES:-}" in ''|*[!0-9]*) NBOUNDCASES=0 ;; esac
UNBOUND=$((NCASES - NBOUNDCASES))

# Rule 7, in the two shapes it actually takes here. Both are halts, and they are DIFFERENT halts
# because the repairs differ: one means the suite never ran, the other means it ran and nothing in
# it is bound to a requirement. Reporting either as a clean zero is the defect this guards.
if [ "$NCASES" -eq 0 ]; then
  halt "no-cases-at-all — the bundle contains zero Test Case nodes, so nothing was measured"
fi
if [ "$NBOUND" -eq 0 ]; then
  halt "no-bound-cases — $NCASES test case(s) ran and none carries an R-NN, so no criterion was measured"
fi

# --- aggregate per criterion --------------------------------------------------------------------
# FAIL wins over SKIP wins over PASS. Sorted output so the caller and the harness see a stable order.
sort -u "$TMP/bindings.tsv" | awk -F'\t' '
  { if (!($1 in seen)) { seen[$1]=1; order[++n]=$1; v[$1]="PASS" }
    if ($2 == "FAIL") v[$1]="FAIL"
    else if ($2 == "SKIP" && v[$1] != "FAIL") v[$1]="SKIP" }
  END { for (i=1;i<=n;i++) printf "%s\t%s\n", order[i], v[order[i]] }
' | sort > "$TMP/verdicts.tsv"

# --- the reverse direction (rule 8) --------------------------------------------------------------
DECL_N="-"; MISSING_N="-"
if [ -n "$DECLARED" ]; then
  [ -f "$DECLARED" ] && [ -r "$DECLARED" ] || halt "declared-file-unreadable — $DECLARED"
  # DECLRE, not IDRE — see the definition above. The two are deliberately different because the
  # documents are: a markdown declaration versus a Swift method name. What must not differ is this
  # side and the rest of the system's idea of a declared id, and the harness pins that behaviourally
  # against ADR-0048's own counterexamples. DECLRE already yields `R-NN`, so no normalisation runs
  # here: a two-digit form has nothing to normalise, and re-padding it would be a second rule.
  jq -Rr --arg re "$DECLRE" '
    [ match($re; "g") | .captures[1].string ]
    | .[]
  ' "$DECLARED" 2>/dev/null | sort -u > "$TMP/declared.txt"
  DECL_N=$(grep -c . "$TMP/declared.txt" 2>/dev/null || true)
  case "${DECL_N:-}" in ''|*[!0-9]*) DECL_N=0 ;; esac
  # Rule 9: an exemption or a cross-check that covers nothing reads as clean. A declared file that
  # yields zero ids is a broken derivation, not an empty requirement set.
  if [ "$DECL_N" -eq 0 ]; then
    halt "declared-empty — $DECLARED yielded zero R-NN ids, so the reverse check has no subject"
  fi
  cut -f1 "$TMP/verdicts.tsv" | sort -u > "$TMP/executed.txt"
  comm -23 "$TMP/declared.txt" "$TMP/executed.txt" > "$TMP/missing.txt"
  MISSING_N=$(grep -c . "$TMP/missing.txt" 2>/dev/null || true)
  case "${MISSING_N:-}" in ''|*[!0-9]*) MISSING_N=0 ;; esac
  while IFS= read -r m; do
    [ -n "$m" ] && printf '%s\tMISSING\n' "$m" >> "$TMP/verdicts.tsv"
  done < "$TMP/missing.txt"
  sort -o "$TMP/verdicts.tsv" "$TMP/verdicts.tsv"
fi

P=$(awk -F'\t' '$2=="PASS"' "$TMP/verdicts.tsv" | wc -l | tr -d ' ')
F=$(awk -F'\t' '$2=="FAIL"' "$TMP/verdicts.tsv" | wc -l | tr -d ' ')
S=$(awk -F'\t' '$2=="SKIP"' "$TMP/verdicts.tsv" | wc -l | tr -d ' ')
T=$NBOUND

# The arithmetic self-check. MISSING is deliberately OUTSIDE this identity: `total` counts criteria
# that were executed, and a MISSING one by definition was not. Folding it in would make `total`
# mean two things at once, which is how a count starts serving two questions (ADR-0100).
if [ $((P + F + S)) -ne "$T" ]; then
  halt "arithmetic-mismatch — pass=$P fail=$F skip=$S do not sum to total=$T; a verdict was dropped"
fi

while IFS="$(printf '\t')" read -r id tok; do
  [ -n "${id:-}" ] && printf 'ACCEPTANCE-CASE %s %s\n' "$id" "$tok"
done < "$TMP/verdicts.tsv"

printf 'ACCEPTANCE-RESULT pass=%s fail=%s skip=%s total=%s declared=%s missing=%s unbound=%s\n' \
  "$P" "$F" "$S" "$T" "$DECL_N" "$MISSING_N" "$UNBOUND"
exit 0
