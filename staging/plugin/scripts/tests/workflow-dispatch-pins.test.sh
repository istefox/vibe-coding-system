#!/bin/bash
# workflow-dispatch-pins.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash workflow-dispatch-pins.test.sh
#
# One class of defect, two skills: a reference that named something which later moved.
#
# A. deep-refactor's audit phase has two dispatch branches. Branch B (Agent tool) pins
#    model: opus; Branch A (Workflow, the DEFAULT) pinned nothing. The skill's own
#    "model: opus requirement" section said "in every Agent-tool dispatch" — naming one
#    mechanism when there are two — so Branch A inherited the session model and effort.
#    The model half was wrong on every default run; the effort half only coincided with
#    reviewer's frontmatter while the orchestrator happened to sit at high.
#
# B. autopilot-build delegates to concept-to-code by LINE RANGE (c2c §475-486 etc.).
#    Every one of those ranges had drifted off its target. Line numbers cannot survive
#    edits to the file they point into; heading names can. autopilot-build is the
#    unattended runner, so a misleading pointer there is read by nobody in real time.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SKILLS="$STAGING/plugin/skills"
DR="$SKILLS/deep-refactor/SKILL.md"
AB="$SKILLS/autopilot-build/SKILL.md"
CC="$SKILLS/concept-to-code/SKILL.md"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# =====================================================================================
# A. deep-refactor Branch A.

# A1: the requirement sentence must not scope itself to one dispatch mechanism. Naming
# "Agent-tool" was what left the Workflow branch uncovered.
if grep -q 'in every Agent-tool dispatch' "$DR"; then
  bad "A1: 'model: opus requirement' still scoped to Agent-tool only, Workflow branch uncovered"
else
  ok "A1: the opus requirement is no longer scoped to a single dispatch mechanism"
fi

# A2: Branch A must pin the model explicitly. Omitting it means the audit reviewers run on
# whatever model the CLI session happens to use, contradicting this skill's own requirement.
if grep -q 'model: "opus", effort: "high"' "$DR"; then
  ok "A2: Branch A pins model and effort explicitly"
else
  bad "A2: Branch A does not pin model and effort"
fi

# A3: the reason must travel with the pin, or a future editor reads it as noise and drops it.
if grep -q 'inherit the session' "$DR"; then
  ok "A3: the inheritance reason is stated in deep-refactor"
else
  bad "A3: no inheritance reason recorded in deep-refactor"
fi

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
check_ref() {
  _label="$1"; _needle="$2"
  if grep -q "$_needle" "$AB"; then
    if grep -q "$_needle" "$CC"; then
      ok "$_label: named in autopilot-build and present in concept-to-code"
    else
      bad "$_label: autopilot-build names it but concept-to-code has no such text"
    fi
  else
    bad "$_label: autopilot-build no longer names this section"
  fi
}
check_ref "B2" "Pre-dispatch: worktree isolation check"
check_ref "B3" "parallel task conflict scan"

# B4a/B4b: the Step 5 and Step 6 workflow blocks used to share a heading verbatim, which made any
# bare reference ambiguous. They now carry distinct names. Each must be named by autopilot-build AND
# resolve to exactly one heading in c2c — stricter than mere existence, because it fails both on a
# rename in c2c and on a duplicate being reintroduced.
check_unique_ref() {
  _label="$1"; _needle="$2"
  if ! grep -q "$_needle" "$AB"; then
    bad "$_label: autopilot-build does not name \"$_needle\""
    return
  fi
  _n=$(grep -c "^#### $_needle\$" "$CC")
  if [ "$_n" -eq 1 ]; then
    ok "$_label: named in autopilot-build, exactly one such heading in concept-to-code"
  else
    bad "$_label: expected exactly 1 heading \"$_needle\" in concept-to-code, found $_n"
  fi
}
check_unique_ref "B4a" "Workflow dispatch path — Step 5 implementation (hook_verified = true)"
check_unique_ref "B4b" "Workflow dispatch path — Step 6 review cycle (hook_verified = true)"

# B5: the old ambiguous form must be gone entirely. Leaving one behind would mean a half-done
# rename, with some references pointing at a heading that still collides.
OLD=$(grep -c '^#### Workflow dispatch path (hook_verified = true)$' "$CC")
if [ "$OLD" -eq 0 ]; then
  ok "B5: the old shared heading no longer appears in concept-to-code"
else
  bad "B5: the old shared heading still appears $OLD time(s) — rename incomplete"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
