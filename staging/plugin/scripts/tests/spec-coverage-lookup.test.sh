#!/bin/bash
# spec-coverage-lookup.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Run: bash spec-coverage-lookup.test.sh
#
# Issue #414 / ADR-0134 §D13. Pins the shared coverage predicate used by both `autopilot` Phase P
# step 3 (prep-row-select.sh) and project-conductor's SPEC-copy fence, replacing two divergent
# predicates (map-slug-exact vs. issue-number-glob-with-unsorted-head-1) with one.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
SCL="$SCRIPTS/spec-coverage-lookup.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ==================================================================================================
# SCL1 — no SPEC for this issue -> empty stdout, exit 0.
# ==================================================================================================
D1="$TMP/d1"; mkdir -p "$D1"
_out=$(bash "$SCL" "$D1" "9001"); _rc=$?
if [ "$_rc" = "0" ] && [ -z "$_out" ]; then
  ok "SCL1: no SPEC for the issue -> empty stdout, exit 0"
else
  bad "SCL1: expected empty|0, got '$_out'|$_rc"
fi

# ==================================================================================================
# SCL2 — a SPEC exists exactly at <issue>-<slug>.spec.md -> resolved.
# ==================================================================================================
D2="$TMP/d2"; mkdir -p "$D2"; : > "$D2/9002-a-real-slug.spec.md"
_out=$(bash "$SCL" "$D2" "9002")
if [ "$_out" = "$D2/9002-a-real-slug.spec.md" ]; then
  ok "SCL2: SPEC at <issue>-<slug>.spec.md is resolved"
else
  bad "SCL2: expected $D2/9002-a-real-slug.spec.md, got '$_out'"
fi

# ==================================================================================================
# SCL3 — THE BUG THIS CLOSES (issue #414): two candidates for the same issue number, under
# different slugs, resolve DETERMINISTICALLY (lexicographically first), never an arbitrary
# directory-entry order — this is what made the pre-fix `head -1` at the project-conductor site
# arbitrary.
# plant: SCL3 | plugin/scripts/spec-coverage-lookup.sh | | head -1) | | tail -1)
# ==================================================================================================
D3="$TMP/d3"; mkdir -p "$D3"
: > "$D3/9003-zzz-later-alphabetically.spec.md"
: > "$D3/9003-aaa-earlier-alphabetically.spec.md"
_out=$(bash "$SCL" "$D3" "9003")
if [ "$_out" = "$D3/9003-aaa-earlier-alphabetically.spec.md" ]; then
  ok "SCL3: two candidates for one issue resolve deterministically (lexicographically first, issue #414)"
else
  bad "SCL3: expected the alphabetically-first candidate, got '$_out'"
fi

# ==================================================================================================
# SCL4 — a SPEC for a DIFFERENT issue number is never matched, even with a similar prefix
# (guard the denominator, rule 7: the glob must not over-match a numeric prefix collision).
# ==================================================================================================
D4="$TMP/d4"; mkdir -p "$D4"; : > "$D4/90-other-issue.spec.md"
_out=$(bash "$SCL" "$D4" "9")
if [ -z "$_out" ]; then
  ok "SCL4: a SPEC for issue #90 does not satisfy a lookup for issue #9 (no numeric-prefix over-match)"
else
  bad "SCL4: expected empty, got '$_out' — issue #9's glob matched issue #90's file"
fi

# ==================================================================================================
# SCL5 — bad invocation (missing args) -> exit 2, distinct from the "not found" exit-0-empty case.
# ==================================================================================================
_out=$(bash "$SCL" 2>&1); _rc=$?
if [ "$_rc" = "2" ]; then
  ok "SCL5: missing arguments -> exit 2 (bad invocation), distinct from not-found"
else
  bad "SCL5: expected exit 2, got rc=$_rc out='$_out'"
fi

# ==================================================================================================
# Z1 — assertion-count floor (rule 10).
# ==================================================================================================
Z1_FLOOR=5
if [ "$((PASS + FAIL))" -ge "$Z1_FLOOR" ]; then
  ok "Z1: assertion count $((PASS + FAIL)) >= floor $Z1_FLOOR"
else
  bad "Z1: assertion count $((PASS + FAIL)) < floor $Z1_FLOOR — assertions vanished"
fi

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
