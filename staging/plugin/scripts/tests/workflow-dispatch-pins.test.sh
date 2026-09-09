#!/bin/bash
# workflow-dispatch-pins.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash workflow-dispatch-pins.test.sh
#
# One class of defect, two skills: a reference that named something which later moved.
#
# Section A stood here — deep-refactor's audit-phase Branch A model/effort pin (A1-A3), plus the
# DR variable pointing at deep-refactor/SKILL.md. Removed 2026-09-08,
# migrate-deep-refactor-out-of-vendored-pa / ADR-0197 (rule 19). A1 was NEGATIVE-shaped
# (`if grep -q ... "$DR"; then bad; else ok`), so with staging/plugin/skills/deep-refactor/SKILL.md
# gone (Task 5 of that plan) it would pass VACUOUSLY — removed along with A2/A3, not left to rot as
# a check that can no longer fail. codex-audit-mode.test.sh's CX20/CX21 pinned the same
# model/effort-pin content from the same file; see that file's own rule-19 comments for the same
# reasoning.
#
# B. autopilot-build delegates to concept-to-code by LINE RANGE (c2c §475-486 etc.).
#    Every one of those ranges had drifted off its target. Line numbers cannot survive
#    edits to the file they point into; heading names can. autopilot-build is the
#    unattended runner, so a misleading pointer there is read by nobody in real time.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
AB="$SKILLS/autopilot-build/SKILL.md"
CC="$SKILLS/concept-to-code/SKILL.md"
STEP5_REF="$SKILLS/concept-to-code/references/step5-implementation.md"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# =====================================================================================
# B. autopilot-build cross-references.

# B1: no line-range references into another skill's file may remain. The regex matches the
# "§<digits>" form specifically, so a "§5 Gate" style section reference stays legal.
STALE=$(grep -c '§[0-9]' "$AB")
if [ "$STALE" -eq 0 ]; then
  ok "B1: no line-number cross-references left in autopilot-build"
else
  bad "B1: $STALE line-number cross-reference(s) still present in autopilot-build"
fi

# B2..B5: every heading autopilot-build now names must actually exist in c2c. This is the
# assertion that makes the reference self-checking: rename a section in c2c and this fails
# instead of silently pointing at nothing.
# VCS-047/ADR-0174: optional 3rd arg names the c2c-side source file — defaults to $CC, but
# B2/B3's needles physically moved into references/step5-implementation.md with the rest of
# Step 5's body.
check_ref() {
  _label="$1"; _needle="$2"; _src="${3:-$CC}"
  if grep -q "$_needle" "$AB"; then
    if grep -q "$_needle" "$_src"; then
      ok "$_label: named in autopilot-build and present in concept-to-code"
    else
      bad "$_label: autopilot-build names it but concept-to-code has no such text"
    fi
  else
    bad "$_label: autopilot-build no longer names this section"
  fi
}
check_ref "B2" "Pre-dispatch: worktree isolation check" "$STEP5_REF"
check_ref "B3" "parallel task conflict scan" "$STEP5_REF"

# B4a/B4b: the Step 5 and Step 6 workflow blocks used to share a heading verbatim, which made any
# bare reference ambiguous. They now carry distinct names. Each must be named by autopilot-build AND
# resolve to exactly one heading in c2c — stricter than mere existence, because it fails both on a
# rename in c2c and on a duplicate being reintroduced.
# VCS-047/ADR-0174: optional 3rd arg names the c2c-side source file — defaults to $CC, but
# B4a's heading physically moved into references/step5-implementation.md with the rest of
# Step 5's body.
check_unique_ref() {
  _label="$1"; _needle="$2"; _src="${3:-$CC}"
  if ! grep -q "$_needle" "$AB"; then
    bad "$_label: autopilot-build does not name \"$_needle\""
    return
  fi
  _n=$(grep -c "^#### $_needle\$" "$_src")
  if [ "$_n" -eq 1 ]; then
    ok "$_label: named in autopilot-build, exactly one such heading in concept-to-code"
  else
    bad "$_label: expected exactly 1 heading \"$_needle\" in concept-to-code, found $_n"
  fi
}
check_unique_ref "B4a" "Workflow dispatch path — Step 5 implementation (hook_verified = true)" "$STEP5_REF"

# B4b — corrected 2026-08-22 (issue #412, ADR-0164). The Step 6 Workflow path was renamed to say
# outright that it is not selected: `hook_verified` never chose between two Step 6 paths correctly,
# because Phase 4's re-review has no orchestrator turn in which to merge Phase 3's worktrees back
# first (measured: zero manifests out of 60 ever recorded step6_mode: "workflow"). autopilot-build
# no longer names the old heading either (see its own Step 6 section) — B4b now asserts the NEW
# heading is unique in c2c and that the retired form is gone from both files, not that the old form
# is still named.
NEW_B4B="Workflow dispatch path — Step 6 review cycle (NOT SELECTED — see above, issue #412)"
_n_b4b=$(grep -c "^#### $NEW_B4B\$" "$CC")
if [ "$_n_b4b" -eq 1 ]; then
  ok "B4b: exactly one heading for the (not selected) Step 6 workflow path in concept-to-code"
else
  bad "B4b: expected exactly 1 heading \"$NEW_B4B\" in concept-to-code, found $_n_b4b"
fi
if grep -q "Workflow dispatch path — Step 6 review cycle (hook_verified = true)" "$AB"; then
  bad "B4b: autopilot-build still names the retired hook_verified=true Step 6 heading"
else
  ok "B4b: autopilot-build no longer names the retired hook_verified=true Step 6 heading"
fi

# B5: the old ambiguous form must be gone entirely. Leaving one behind would mean a half-done
# rename, with some references pointing at a heading that still collides. Negative-shaped (rule
# 8): must scan the whole population, not just the part that used to hold it — VCS-047/ADR-0174
# split concept-to-code's body across SKILL.md and references/step5-implementation.md, and a
# check that only re-read $CC would go quietly blind to a stale heading left in the moved half.
OLD=$(cat "$CC" "$STEP5_REF" 2>/dev/null | grep -c '^#### Workflow dispatch path (hook_verified = true)$')
if [ "$OLD" -eq 0 ]; then
  ok "B5: the old shared heading no longer appears in concept-to-code"
else
  bad "B5: the old shared heading still appears $OLD time(s) — rename incomplete"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
