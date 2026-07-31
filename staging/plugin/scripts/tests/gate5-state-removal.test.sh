#!/bin/bash
# gate5-state-removal.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash gate5-state-removal.test.sh
#
# Issue #265 / ADR-0105. Found by the derived producer guard shipped with #248, on its first run:
# `gate_5_review_decision` was entered by NOTHING. Step 5 transitions to `step_6_review` and presents
# Gate 5 from there, while Gate 5's own block asserted `Trigger: … current_step =
# gate_5_review_decision`, the advisory roll-up spoke of "the transition to" it, and Step 7 listed it
# as a valid source state. Four legal pairs, structurally unreachable.
#
# THE ISSUE OFFERED TWO OPTIONS AND NEITHER NAMED THE DECIDING ARGUMENT. §3 already documents a
# pattern for gates that do NOT get their own `current_step`: "Gate 2b and Gate 5.05/5.06 are already
# inline sub-gates with no dedicated state", and Step 4.5 follows the same shape. **Gate 5 is the
# fifth instance of that pattern.** So the state is the anomaly, not the missing producer, and
# deleting it makes Gate 5 consistent with four siblings rather than merely making the graph smaller.
#
# Measured before deciding: **zero** manifests have ever carried `current_step:
# "gate_5_review_decision"`. Nothing is being taken away from any record.
#
# The four pairs go, so the count moves 49 → 45. Five assertions across three files pinned 49; they
# are updated rather than relaxed, and GR3 re-derives the number from the script rather than trusting
# any of them.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: GR4 | plugin/skills/concept-to-code/SKILL.md | Trigger: post Step 5 (coder complete), `current_step = step_6_review` | Trigger: post Step 5 (coder complete), `current_step = gate_5_review_decision`
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
TR="$STAGING/plugin/skills/concept-to-code/scripts/manifest-transition.sh"
VA="$STAGING/plugin/skills/concept-to-code/scripts/manifest-validate.sh"
SM="$STAGING/plugin/skills/concept-to-code/tests/smoke-e2e.sh"
GONE="gate_5_review_decision"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for _f in "$CC" "$TR" "$VA"; do
  [ -f "$_f" ] || { echo "FATAL: missing $_f"; exit 1; }
done
FLAT=$(tr '\n' ' ' <"$CC" | tr -d '`*' | tr -s ' ')

# ===========================================================================
# GR0 — the premise, derived: no record is being invalidated.
# ===========================================================================
MAN_N=$(ls "$REPO"/docs/manifests/*.manifest.yml 2>/dev/null | wc -l | tr -d ' ')
OCC=$(grep -l "current_step: \"$GONE\"" "$REPO"/docs/manifests/*.manifest.yml 2>/dev/null | wc -l | tr -d ' ')
if [ "$MAN_N" -ge 30 ] && [ "$OCC" -eq 0 ]; then
  ok "GR0 no manifest has ever occupied the removed state (0 of $MAN_N)"
else
  bad "GR0 $OCC of $MAN_N manifests carry current_step=$GONE — removing the state invalidates a real record; re-open the design question"
fi

# ===========================================================================
# GR1..GR2 — the state is gone from the machine.
# ===========================================================================
# The needle targets the MECHANISM — a pair line, or a producer exemption — never the name. The
# script legitimately names the state while explaining why it no longer has one, and a bare
# `grep -q "$GONE"` counts that explanation as the defect. Rule 12, third instance today after
# spec-archive.test.sh SA10 and gate0-recommendation.test.sh N9.
_pairs=$(grep -c "^[[:space:]]*echo \".*$GONE.*\" >> \"\$PAIRS\"" "$TR" 2>/dev/null || true)
_pairs=${_pairs:-0}
_exempt=$(grep -c "^# transition-producer-exempt:.*$GONE" "$TR" 2>/dev/null || true)
_exempt=${_exempt:-0}
if [ "$_pairs" -eq 0 ] && [ "$_exempt" -eq 0 ]; then
  ok "GR1 manifest-transition.sh declares no pair and no exemption for the state"
else
  bad "GR1 manifest-transition.sh still declares $_pairs pair(s) and $_exempt exemption(s) for $GONE"
fi

if ! grep -q "$GONE" "$VA"; then
  ok "GR2 manifest-validate.sh no longer lists it as a valid step"
else
  bad "GR2 manifest-validate.sh still accepts $GONE — a valid state nothing can reach is the defect this closes"
fi

# ===========================================================================
# GR3 — the count, DERIVED from the script and compared against every place that states it.
# A count asserted in four files and derived in none is four chances to drift.
# ===========================================================================
ACTUAL=$(awk -F'"' '/^[[:space:]]*echo "[a-z0-9_]+,[a-z0-9_]+"/{print $2}' "$TR" | sort -u | wc -l | tr -d ' ')
if [ "$ACTUAL" -eq 45 ]; then
  ok "GR3 the script builds 45 distinct pairs (49 minus the four unreachable ones)"
else
  bad "GR3 the script builds $ACTUAL pairs, expected 45"
fi

STATED=$(grep -c '45 total\|(45 pairs)\|§3.3, 45 transitions' "$CC" "$TR" 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')
if [ "$STATED" -ge 3 ]; then
  ok "GR3b the new count is stated in SKILL.md and the script ($STATED sites)"
else
  bad "GR3b only $STATED site(s) state 45; the count is written in three places and all must move together"
fi

if grep -q '49 total\|49 transitions\|(49 pairs)' "$CC" "$TR" 2>/dev/null; then
  bad "GR3c a stale 49 survives in SKILL.md or the transition script"
else
  ok "GR3c no stale 49 remains"
fi

# ===========================================================================
# GR4..GR7 — the three prose sites that relied on the state, plus §3's graph.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'Trigger: post Step 5 (coder complete), current_step = step_6_review'; then
  ok "GR4 Gate 5's Trigger names the state the chain is actually in"
else
  bad "GR4 Gate 5's Trigger does not name step_6_review — it asserted a state nothing entered (#265)"
fi

# Same rule-12 shape as GR1: SKILL.md legitimately names the state while explaining why it no longer
# exists. What must be gone is every reference that treats it as LIVE — a graph arrow, an asserted
# current_step, or a transition instruction naming it.
_live=$(grep -nE "(→|->)[[:space:]]*\`?$GONE|current_step = \`?$GONE|[Tt]ransition[^.]*$GONE" "$CC" | head -3)
if [ -z "$_live" ]; then
  ok "GR5 no live reference to the removed state survives in SKILL.md"
else
  bad "GR5 SKILL.md still treats $GONE as a reachable state: $(printf '%s' "$_live" | tr '\n' ' ' | cut -c1-140)"
fi

if printf '%s\n' "$FLAT" | grep -qi 'inline sub-gate with no dedicated current_step state, the fifth'; then
  ok "GR6 Gate 5 is stated as the fifth inline sub-gate — the reason it has no state"
else
  bad "GR6 nothing records WHY Gate 5 has no state; without it the next reader adds one back"
fi

if [ -f "$SM" ]; then
  if ! grep -q "$GONE" "$SM"; then
    ok "GR7 the smoke-e2e transition script no longer walks through the removed state"
  else
    bad "GR7 smoke-e2e.sh still walks step_6_review → $GONE, which is now illegal"
  fi
else
  bad "GR7 smoke-e2e.sh is missing; the transition walk it documents is unchecked"
fi

# ===========================================================================
# GR8 — forward guard: the two pairs that actually carry the flow survive.
# ===========================================================================
if grep -qF 'step_6_review,step_7_commit' "$TR" && grep -qF 'step_6_review,completed' "$TR"; then
  ok "GR8 (forward guard) step_6_review's real exits are untouched"
else
  bad "GR8 step_6_review lost an exit pair; the chain cannot leave the review phase"
fi

# ===========================================================================
# GR9/GR10 — executed. The removed transition must now be refused, and the surviving one accepted.
# ===========================================================================
mk_manifest() {  # -> path to a valid manifest sitting at step_6_review
  _d="$TMP/m$$$RANDOM"; mkdir -p "$_d/docs/manifests"
  _src=$(ls "$REPO"/docs/manifests/*.manifest.yml | head -1)
  _m="$_d/docs/manifests/test.manifest.yml"
  sed 's/^current_step: .*/current_step: "step_6_review"/; s/^status: .*/status: "in_progress"/' "$_src" >"$_m"
  _root=$(grep '^project_root:' "$_m" | sed 's/.*: *//; s/"//g')
  sed -i.bak "s|^project_root: .*|project_root: \"$_d\"|" "$_m" && rm -f "$_m.bak"
  printf '%s' "$_m"
}

M=$(mk_manifest)
if bash "$VA" "$M" >/dev/null 2>&1; then
  ok "GR9 the fixture manifest is valid at step_6_review (GR10 needs it to be)"
else
  bad "GR9 the fixture manifest does not validate; GR10 would fail for the wrong reason"
fi

out=$(bash "$TR" "$M" "$GONE" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -qi 'illegal transition'; then
  ok "GR10 step_6_review → $GONE is now refused as illegal"
else
  bad "GR10 the removed transition still succeeds (rc=$rc out=$out) — the pairs were not actually deleted"
fi

M=$(mk_manifest)
if bash "$TR" "$M" step_7_commit >/dev/null 2>&1 && grep -q 'current_step: "step_7_commit"' "$M"; then
  ok "GR11 step_6_review → step_7_commit still works — the path the chain actually takes"
else
  bad "GR11 the surviving exit broke; removing four pairs took a fifth with it"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 13 ]; then ok "Z1 assertion-count floor ($_total >= 13)"
else bad "Z1 assertion count fell to $_total (floor 13) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
