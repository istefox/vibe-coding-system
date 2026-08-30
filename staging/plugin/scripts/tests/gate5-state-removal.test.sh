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
# plant: GR4 | plugin/skills/concept-to-code/references/hitl-gates.md | Trigger: post Step 5 (coder complete), `current_step = step_6_review` | Trigger: post Step 5 (coder complete), `current_step = gate_5_review_decision`
# plant: GR3 | plugin/scripts/tests/transition-pair-count.sh | STATS_TOTAL="$TOTAL_D" | STATS_TOTAL="999"
# plant: GR3b | plugin/skills/concept-to-code/SKILL.md | Legal transition pairs (51 total — 28 standard + 6 express + 17 hybrid | Legal transition pairs (52 total — 28 standard + 6 express + 17 hybrid
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
HITL_REF="$STAGING/plugin/skills/concept-to-code/references/hitl-gates.md"
TR="$STAGING/plugin/skills/concept-to-code/scripts/manifest-transition.sh"
VA="$STAGING/plugin/skills/concept-to-code/scripts/manifest-validate.sh"
SM="$STAGING/plugin/skills/concept-to-code/tests/smoke-e2e.sh"
GONE="gate_5_review_decision"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for _f in "$CC" "$HITL_REF" "$TR" "$VA"; do
  [ -f "$_f" ] || { echo "FATAL: missing $_f"; exit 1; }
done
# VCS-048/ADR-0175: ## 5. HITL gates (Gate 5's Trigger/reasoning prose) moved into
# references/hitl-gates.md — flatten both files, not just SKILL.md (population-glob coupling).
FLAT=$(cat "$CC" "$HITL_REF" | tr '\n' ' ' | tr -d '`*' | tr -s ' ')

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
# GR3/GR3b — issue #289 / ADR-0120: the count is no longer derived locally in this file. It is
# derived ONCE by transition-pair-count.sh (staging/plugin/scripts/tests/), the single place that
# decides what a transition pair is (ADR-0120 D1), and both assertions below consume its output.
# ADR-0120 M3 measured THREE ad-hoc derivations across three files disagreeing with each other on
# three of five mutation fixtures -- this file's own GR3 was one of them (deduped, but NOT bounded
# to the pair-building block). Do not re-derive the count here; call the checker.
# ===========================================================================
PTC="$STAGING/plugin/scripts/tests/transition-pair-count.sh"
gr3_stats="$(bash "$PTC" "$TR" "$CC" 2>&1 >/dev/null)"
gr3_rc=$?
ACTUAL="$(printf '%s\n' "$gr3_stats" | grep -o 'pairs=[0-9]*' | head -1 | cut -d= -f2)"
ACTUAL="${ACTUAL:-0}"
if [ "$ACTUAL" -eq 51 ]; then
  ok "GR3 transition-pair-count.sh (the shared derivation, not a local recount) reports 51 distinct pairs (45 plus the six Gate 1d/H1d pairs, VCS-052)"
else
  bad "GR3 transition-pair-count.sh reports $ACTUAL pairs, expected 51"
fi

# GR3b REPLACES the old `>= 3` line-floor over an OR'd needle set (ADR-0120 D-C: a floor over
# matching lines cannot say WHICH site moved, and passes if a fourth site appears while one of the
# three vanishes). It now asserts the checker's own per-site comparison found nothing wrong: zero
# findings means every one of the three shipping literals (SKILL.md header, SKILL.md "atomically
# (<n> pairs)", and the script's own §3.3 comment) agrees with the derived total. A finding, were
# there one, would print naming the specific stale site -- see transition-pair-count.sh's own
# COMPARISONS section.
if [ "$gr3_rc" -eq 0 ]; then
  ok "GR3b transition-pair-count.sh reports zero findings across SKILL.md and manifest-transition.sh -- a finding would name the stale site"
else
  bad "GR3b transition-pair-count.sh reports findings (rc=$gr3_rc): $gr3_stats -- one or more of the three shipping literals disagrees with the derived count"
fi

# GR3c (forward guard, ADR-0120 D4: subsumed by GR3b's per-site mechanism -- a literal that
# disagrees with the derivation is now a finding whatever its value, so a hardcoded ban on one
# specific historical number is no longer the mechanism doing the work. Kept as a cheap check and
# LABELLED here: it passes before AND after this chain and must never be read as fix evidence.)
if grep -q '49 total\|49 transitions\|(49 pairs)' "$CC" "$TR" 2>/dev/null; then
  bad "GR3c a stale 49 survives in SKILL.md or the transition script"
else
  ok "GR3c no stale 49 remains (forward guard only -- passes before and after this chain, not fix evidence; GR3b is the real mechanism now)"
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
_live=$(grep -nE "(→|->)[[:space:]]*\`?$GONE|current_step = \`?$GONE|[Tt]ransition[^.]*$GONE" "$CC" "$HITL_REF" | head -3)
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
