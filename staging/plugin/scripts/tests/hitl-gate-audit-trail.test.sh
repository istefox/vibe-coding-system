#!/bin/bash
# hitl-gate-audit-trail.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash hitl-gate-audit-trail.test.sh
#
# Issue #238 / ADR-0099. Two defects in one subject; fixing either alone leaves the other making it
# useless.
#
#   PART A — `manifest-set-gate.sh` had no instructed call site. Correct, tested, deployed,
#            unreachable. Every gate approval a human gave was recorded nowhere, and the trail
#            stayed `pending` for the life of the manifest.
#   PART B — the template had slots for gates 1, 2, 3 and 5. **Gate 4 had none**, so
#            `manifest-set-gate.sh <m> 4 approved` exited 3 — the script behaving correctly on a
#            template that does not describe the chain.
#
# Gate 4 is the one whose answer has the widest blast radius: it can set `autopilot: true`, which
# drives five downstream gates to their safe defaults. **And that flag is ambiguous by
# construction** — `project-conductor`'s autopilot roadmap mode sets the same `true` with no human at
# Gate 4 at all (ADR-0022). Reading a manifest afterwards, `autopilot: true` cannot distinguish "a
# human chose unattended implementation" from "a roadmap pre-authorised the whole run". The field
# that disambiguates it is the one that had no slot.
#
# THE BASELINE, measured before the fix and recorded so a later run can tell whether it worked:
# 164 gate entries across 41 manifests, **39 approved / 125 pending**, and the distribution is
# bimodal rather than gradual — four manifests at 4/4, two at 2/4, thirteen at 1/4. That is not
# gates being answered differently. It is orchestrators remembering differently.
#
# NO STATUS INVARIANT IS ADDED, deliberately. A chain legitimately sits at `pending` mid-run, and a
# completed chain with a pending Gate 5 is a real state (the `step_6_review → completed` direct
# close skips it). Any status check would have to be conditional on `current_step`, which is
# ADR-0076's rule and the same trap. H7 pins the absence.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: H3 | plugin/skills/concept-to-code/scripts/manifest-init.sh | label: \"implementation_mode\" | label: \"session_boundary\"
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
INIT="$STAGING/plugin/skills/concept-to-code/scripts/manifest-init.sh"
SETGATE="$STAGING/plugin/skills/concept-to-code/scripts/manifest-set-gate.sh"
VALIDATE="$STAGING/plugin/skills/concept-to-code/scripts/manifest-validate.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for _f in "$CC" "$INIT" "$SETGATE" "$VALIDATE"; do
  [ -f "$_f" ] || { echo "FATAL: missing $_f"; exit 1; }
done

# --- a real, freshly-initialised manifest, produced by RUNNING the generator ------------------
ROOT="$TMP/proj"
mkdir -p "$ROOT/docs/manifests"
MAN=$(cd "$ROOT" && bash "$INIT" "238-audit-trail" "Audit trail for HITL gates" "$ROOT" greenfield 2>/dev/null)
if [ -n "${MAN:-}" ] && [ -f "$MAN" ]; then
  ok "H0 manifest-init.sh produced a manifest to read"
else
  echo "FATAL: manifest-init.sh produced nothing (got '${MAN:-}')"; echo "PASS=$PASS FAIL=$((FAIL+1))"; exit 1
fi

GATES=$(grep '^  - gate:' "$MAN" | sed 's/^  - gate: *//' | tr -d ' ' | tr '\n' ' ')
GATE_N=$(grep -c '^  - gate:' "$MAN")

# ===========================================================================
# H1..H3 — Part B: the template describes the chain's gates.
# ===========================================================================
if [ "$GATE_N" -eq 5 ]; then
  ok "H1 the template writes five gate slots ($GATES)"
else
  bad "H1 the template writes $GATE_N slots ($GATES) — Gate 4 has no entry, so recording it exits 3 (#238)"
fi

if printf '%s ' $GATES | grep -q '\b4\b'; then
  ok "H2 gate 4 has a slot"
else
  bad "H2 gate 4 has no slot; it is the gate that switches five other gates off and the only one with no audit entry"
fi

if grep -q 'label: "implementation_mode"' "$MAN"; then
  ok "H3 gate 4's label names what it records (implementation_mode)"
else
  bad "H3 gate 4's slot is not labelled implementation_mode"
fi

# Every slot keeps the four fields; a slot without approved_at records nothing useful.
BAD_SHAPE=""
for _g in $GATES; do
  _blk=$(awk -v g="  - gate: $_g" '$0==g{f=1;next} f&&/^  - gate:/{exit} f{print}' "$MAN")
  for _k in label status approved_at notes; do
    printf '%s\n' "$_blk" | grep -q "^    $_k:" || BAD_SHAPE="$BAD_SHAPE gate$_g/$_k"
  done
done
if [ -z "$BAD_SHAPE" ]; then ok "H3b every slot carries label/status/approved_at/notes"
else bad "H3b slot field(s) missing:$BAD_SHAPE"; fi

# ===========================================================================
# H4 — Part B, executed: the call that used to exit 3 now works.
# ===========================================================================
out=$(bash "$SETGATE" "$MAN" 4 approved "attended, this session" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q 'label: "implementation_mode"' "$MAN" \
   && awk '/^  - gate: 4/{f=1;next} f&&/^  - gate:/{exit} f' "$MAN" | grep -q 'status: "approved"'; then
  ok "H4 manifest-set-gate.sh <m> 4 approved now succeeds (it exited 3 before)"
else
  bad "H4 recording gate 4 failed: rc=$rc out=$out"
fi

# ===========================================================================
# H5/H6 — Part A: the helper has instructed call sites, defined once and referenced.
# ===========================================================================
DEF_N=$(grep -c '^#### Gate approval recording' "$CC")
if [ "$DEF_N" -eq 1 ]; then
  ok "H5 the recording rule is defined exactly once"
else
  bad "H5 expected one 'Gate approval recording' definition, found $DEF_N — a rule stated in five places drifts in five places"
fi

REF_N=$(grep -c 'Record the gate outcome' "$CC")
if [ "$REF_N" -ge 5 ]; then
  ok "H6 five or more gate branches record their outcome ($REF_N references)"
else
  bad "H6 only $REF_N gate branch(es) record an outcome — gates 1, 2, 3, 4 and 5 all need one (#238)"
fi

# The Gate 4 recording is the one that disambiguates `autopilot: true`, so it must say so.
FLAT=$(tr '\n' ' ' <"$CC" | tr -d '`*' | tr -s ' ')
if printf '%s\n' "$FLAT" | grep -q 'cannot distinguish a human choosing unattended implementation from a roadmap'; then
  ok "H6b the Gate 4 recording states what it disambiguates"
else
  bad "H6b nothing says why Gate 4's notes matter — autopilot: true alone cannot tell a human choice from an autopilot roadmap (ADR-0022)"
fi

# ===========================================================================
# H7 — no status invariant, and historical manifests still validate. Both executed.
# ===========================================================================
if bash "$VALIDATE" "$MAN" >/dev/null 2>&1; then
  ok "H7 a fresh manifest with every gate pending still validates — mid-run pending is a legitimate state"
else
  bad "H7 a fresh all-pending manifest no longer validates; a status invariant was added, which ADR-0076's rule warns against"
fi

HIST=$(ls "$REPO"/docs/manifests/*.manifest.yml 2>/dev/null | head -1)
HIST_N=$(ls "$REPO"/docs/manifests/*.manifest.yml 2>/dev/null | wc -l | tr -d ' ')
if [ "$HIST_N" -ge 30 ]; then
  ok "H8 the historical corpus is readable ($HIST_N manifests)"
else
  bad "H8 the historical corpus is $HIST_N manifests (expected >= 30) — H8b asserts nothing"
fi

# Four-slot manifests predate the fifth. Raising invariant 9's minimum to 5 would make every one of
# them fail for a change they predate — ADR-0078's rule, applied to a count instead of a path.
OLD_FAIL=""
for _m in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_m" ] || continue
  _n=$(grep -c '^  - gate:' "$_m" 2>/dev/null || true)
  [ "${_n:-0}" -eq 4 ] || continue
  bash "$VALIDATE" "$_m" >/dev/null 2>&1 || OLD_FAIL="$OLD_FAIL $(basename "$_m")"
done
if [ -z "$OLD_FAIL" ]; then
  ok "H8b every four-slot historical manifest still validates"
else
  bad "H8b four-slot manifest(s) now fail validation — invariant 9's minimum was raised past the era they were written in:$OLD_FAIL"
fi

# ===========================================================================
# H9 — the measured baseline is on the record, derived rather than quoted.
# ===========================================================================
ENTRIES=$(grep -h '^  - gate:' "$REPO"/docs/manifests/*.manifest.yml 2>/dev/null | wc -l | tr -d ' ')
APPROVED=$(grep -h 'status: "approved"' "$REPO"/docs/manifests/*.manifest.yml 2>/dev/null | wc -l | tr -d ' ')
if [ "$ENTRIES" -ge 100 ] && [ "$APPROVED" -lt "$ENTRIES" ]; then
  ok "H9 baseline readable: $APPROVED of $ENTRIES historical gate entries approved (was 39/164 pre-fix)"
else
  bad "H9 the baseline derivation returned $APPROVED/$ENTRIES — a broken parse reads like a perfect trail"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 12 ]; then ok "Z1 assertion-count floor ($_total >= 12)"
else bad "Z1 assertion count fell to $_total (floor 12) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
