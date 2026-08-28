#!/bin/bash
# tracer-bullet-probe.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash tracer-bullet-probe.test.sh
#
# Covers issue #111 / ADR-0057: an optional Step 4.5 between Gate 4 and Step 5 that dispatches one
# coder on the thinnest end-to-end slice, computes a green|amber|red verdict from MECHANICAL FACTS
# (never from the coder's own opinion), and routes: green -> Step 5 (slice kept as pattern seed),
# amber -> back to Gate 2 for scope reduction, red -> a new gate offering continue-anyway /
# reduce-scope / hand-code (abort, reason recorded).
#
# ASSERTION LABELS ARE TB-PREFIXED (TBA1, TBB1, ...). NOTE ON THE PREFIX ITSELF: the dispatch brief
# for this task claimed test-write-scope.test.sh "already uses a bare T" and asked for a TB prefix
# to stay distinguishable from it. Checked rather than assumed (grep against that file): it
# actually uses TA/TB/TC/TE/TF/TH/TI/TJ/TK/TL, INCLUDING TB1..TB8 already. A bare "TB" prefix would
# have collided. What is actually collision-free is what this file uses: three-letter section
# prefixes (TBA, TBB, TBC, ...) exactly matching this feature's own plan-document section names —
# "TBA1:" is not a substring of "TB1:" or vice versa, so grep/log-scan on either stays exact.
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL and no fixture path contains "secret",
# "credential", ".env", ".pem", or ".key" — protect-files.sh denies creating such paths (singular
# "secret", not the plural "secrets" the hook actually matches on, still avoided) and
# secret-dep-gate.test.sh section D scans this repository's tracked files as its false-positive
# corpus.
#
# STATE-MACHINE DESIGN NOTE (verified, not assumed — this is the point of the task's own warning
# about ADR-0027's Gates 0c/0d lesson): Step 4.5 and its red-decision gate do NOT get dedicated
# `current_step` states. Checked against the existing precedent first: Gate 2b (test-cmd TOFU) and
# Gate 5.05/5.06 (UI layout audit, specialized review) are already inline sub-gates that run WITHIN
# their enclosing state (`gate_2_architecture_review`, `step_6_review`) and never appear in
# manifest-transition.sh's VALID_STEPS or PAIRS as their own node. Step 4.5 follows the same shape:
# it runs inline at `ready_for_implementation`. Consequence: green and "red -> continue anyway"
# reuse the EXISTING `ready_for_implementation,step_5_implementation` pair unchanged; hand-code
# reuses the existing "any state -> aborted" wildcard unchanged. Exactly ONE new pair was actually
# missing: `ready_for_implementation,gate_2_architecture_review` (amber, and "red -> reduce scope").
# Section TBP proves this by driving the real state machine, not by re-deriving it from prose.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
REPO=$(cd "$STAGING/.." && pwd)
SKILL_DIR="$STAGING/plugin/skills/concept-to-code"
SKILL_MD="$SKILL_DIR/SKILL.md"
HITL_REF="$SKILL_DIR/references/hitl-gates.md"
STEP5_REF="$SKILL_DIR/references/step5-implementation.md"
INIT="$SKILL_DIR/scripts/manifest-init.sh"
VAL="$SKILL_DIR/scripts/manifest-validate.sh"
TRN="$SKILL_DIR/scripts/manifest-transition.sh"
SETGATE="$SKILL_DIR/scripts/manifest-set-gate.sh"
DBC="$SKILL_DIR/scripts/diff-budget-check.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ==================================================================================================
# TB0. Anchor — every other assertion below depends on these files existing and being readable.
# ==================================================================================================
TB0_MISSING=""
for f in "$SKILL_MD" "$INIT" "$VAL" "$TRN" "$DBC"; do
  [ -f "$f" ] && [ -r "$f" ] || TB0_MISSING="$TB0_MISSING $f"
done
if [ -z "$TB0_MISSING" ]; then
  ok "TB0: SKILL.md, manifest-init.sh, manifest-validate.sh, manifest-transition.sh, diff-budget-check.sh all exist and are readable"
else
  bad "TB0: missing/unreadable:$TB0_MISSING — every assertion below is meaningless"
fi

# --- fixture helper: fresh mktemp -d project dir, manifest-init.sh, chain_path patched to
# "standard" (Step 4.5 only exists on the standard path). Sets FIX to the manifest path. ---
mk_fixture() {
  _slug="$1"
  _proj="$(mktemp -d "$TMP/proj-$_slug.XXXXXX")"
  FIX="$(bash "$INIT" "$_slug" "Test $_slug" "$_proj")"
  sed -i.bak "s/^chain_path: null\$/chain_path: \"standard\"/" "$FIX"
}

# advance <manifest> <step> [<step> ...] -- drive sequential legal transitions; returns 0 only if
# every hop succeeds (rc 0). Stops at the first failure.
advance() {
  _m="$1"; shift
  for _s in "$@"; do
    bash "$TRN" "$_m" "$_s" >/dev/null 2>&1 || return 1
  done
  return 0
}

current_step_of() {
  grep '^current_step:' "$1" | sed 's/^current_step: *//;s/"//g' | head -1
}

# mk_ready <slug> -- drives a fresh fixture all the way to ready_for_implementation via the
# existing, unmodified standard-path pairs (step_0_init through step_4_session_boundary). Sets
# FIX to the manifest path, ready for the Step-4.5-specific pairs under test.
#
# Gates 1-3 are approved via manifest-set-gate.sh right before the hop that crosses each one —
# manifest-transition.sh now refuses a gate-advancing pair whose hitl_gates entry is not
# "approved" (the gate-audit-trail-check fix), and a fixture that skips real approval is exactly
# the unenforced state that fix closes, not a shape this helper should keep simulating.
mk_ready() {
  mk_fixture "$1"
  advance "$FIX" gate_0d_scaffolding step_1_interview gate_1_spec_review || return 1
  bash "$SETGATE" "$FIX" 1 approved >/dev/null 2>&1 || return 1
  advance "$FIX" step_2_architecture gate_2_architecture_review || return 1
  bash "$SETGATE" "$FIX" 2 approved >/dev/null 2>&1 || return 1
  advance "$FIX" step_3_project_memory gate_3_project_memory_review || return 1
  bash "$SETGATE" "$FIX" 3 approved >/dev/null 2>&1 || return 1
  advance "$FIX" step_4_session_boundary ready_for_implementation
}

# ==================================================================================================
# TBA. Step 4.5 exists between Gate 4 and Step 5, and is optional, defaulting to skipped
# (ADR-0057 §D1 / plan §TBA). Absent/skip means skipped — the OPPOSITE default direction from
# ADR-0055 §D2, which removes a constraint and so must default strict; this feature ADDS a step,
# so inert must equal the pre-feature behaviour.
# ==================================================================================================
if grep -qF '### Step 4.5 —' "$SKILL_MD"; then
  ok "TBA1: SKILL.md declares a '### Step 4.5 —' section"
else
  bad "TBA1: no '### Step 4.5 —' section found in SKILL.md"
fi

# TBA2: it is positioned in §4's dispatch-template flow between Step 3 (which is where Gate 4 is
# reached from — Gate 4 itself lives entirely in §5, referenced by pointer, not by its own §4
# dispatch-template heading) and the Step 5 heading (doc-order proof).
STEP45_LINE=$(grep -n '^### Step 4.5 —' "$SKILL_MD" | head -1 | cut -d: -f1)
STEP3_LINE=$(grep -n '^### Step 3 —' "$SKILL_MD" | head -1 | cut -d: -f1)
STEP5_LINE=$(grep -n '^### Step 5 —' "$SKILL_MD" | head -1 | cut -d: -f1)
# VCS-048/ADR-0175: ## 5. HITL gates (the Gate 4/4.5/5 headings) moved into
# references/hitl-gates.md — its own doc-order is checked there, separately from §4's.
GATE45_LINE=$(grep -n '^\*\*Gate 4\.5 —' "$HITL_REF" | head -1 | cut -d: -f1)
GATE4_LINE=$(grep -n '^\*\*Gate 4 —' "$HITL_REF" | head -1 | cut -d: -f1)
GATE5_LINE=$(grep -n '^\*\*Gate 5 —' "$HITL_REF" | head -1 | cut -d: -f1)
if [ -n "$STEP45_LINE" ] && [ -n "$STEP3_LINE" ] && [ -n "$STEP5_LINE" ] \
   && [ "$STEP45_LINE" -gt "$STEP3_LINE" ] && [ "$STEP45_LINE" -lt "$STEP5_LINE" ] \
   && [ -n "$GATE45_LINE" ] && [ -n "$GATE4_LINE" ] && [ -n "$GATE5_LINE" ] \
   && [ "$GATE45_LINE" -gt "$GATE4_LINE" ] && [ "$GATE45_LINE" -lt "$GATE5_LINE" ]; then
  ok "TBA2: '### Step 4.5' sits between Step 3 and Step 5 in §4's dispatch flow, and 'Gate 4.5' sits between Gate 4 and Gate 5 in §5's gate list"
else
  bad "TBA2: expected Step3($STEP3_LINE) < Step4.5($STEP45_LINE) < Step5($STEP5_LINE) and Gate4($GATE4_LINE) < Gate4.5($GATE45_LINE) < Gate5($GATE5_LINE)"
fi

STEP45_TXT="$TMP/step45.txt"
awk '/^### Step 4\.5 —/{f=1} /^### Step 5 —/{f=0} f' "$SKILL_MD" >"$STEP45_TXT"

if [ -s "$STEP45_TXT" ] && grep -qi 'default' "$STEP45_TXT" \
   && grep -qi 'skip' "$STEP45_TXT"; then
  ok "TBA3: the Step 4.5 section states a default/skip behavior"
else
  bad "TBA3: Step 4.5 section does not state a default/skip behavior"
fi

if grep -qF 'tracer_bullet_mode: skip' "$STEP45_TXT"; then
  ok "TBA4: Step 4.5 names the manifest field and its default value 'tracer_bullet_mode: skip'"
else
  bad "TBA4: 'tracer_bullet_mode: skip' not found in the Step 4.5 section"
fi

if grep -qF 'ADR-0055' "$STEP45_TXT" && grep -qi 'contrast\|opposite' "$STEP45_TXT"; then
  ok "TBA5: Step 4.5 explicitly contrasts its default direction with ADR-0055 §D2"
else
  bad "TBA5: Step 4.5 does not contrast its default with ADR-0055 §D2"
fi

# TBA6: manifest-init.sh actually emits the skip default (not just documented in prose).
if grep -qF 'tracer_bullet_mode: skip' "$INIT"; then
  ok "TBA6: manifest-init.sh writes tracer_bullet_mode: skip"
else
  bad "TBA6: manifest-init.sh does not write tracer_bullet_mode: skip"
fi

# TBA7 (dynamic): skip mode leaves the existing ready_for_implementation -> step_5_implementation
# pair fully unaffected -- the backward-compatibility hard gate for this feature, same spirit as
# ADR-0052 §D1's plan-level inertness proof.
mk_ready "tba7"
if [ "$?" -eq 0 ] || [ -n "${FIX:-}" ]; then :; fi
if [ -n "${FIX:-}" ] && [ "$(current_step_of "$FIX")" = "ready_for_implementation" ]; then
  bash "$SETGATE" "$FIX" 4 approved >/dev/null 2>&1
  bash "$TRN" "$FIX" step_5_implementation; rc=$?
  if [ "$rc" -eq 0 ] && [ "$(current_step_of "$FIX")" = "step_5_implementation" ]; then
    ok "TBA7: skip-mode path ready_for_implementation -> step_5_implementation is legal and unmodified by this feature"
  else
    bad "TBA7: ready_for_implementation -> step_5_implementation regressed (rc=$rc)"
  fi
else
  bad "TBA7: could not drive fixture to ready_for_implementation"
fi

# ==================================================================================================
# TBB. All three verdicts exist; red gets its own gate naming continue-anyway / reduce-scope /
# hand-code (abort, with the reason recorded) as a first-class option (ADR-0057 §D2 / plan §TBB).
# ==================================================================================================
if grep -qi 'green' "$STEP45_TXT" && grep -qi 'amber' "$STEP45_TXT" && grep -qi '\bred\b' "$STEP45_TXT"; then
  ok "TBB1: Step 4.5 names all three verdicts (green, amber, red)"
else
  bad "TBB1: Step 4.5 does not name all three verdicts"
fi

# VCS-048/ADR-0175: ## 5. HITL gates moved into references/hitl-gates.md; the reference file's
# body IS the block, so no awk range is needed any more.
GATES_TXT="$TMP/gates.txt"
cp "$HITL_REF" "$GATES_TXT" 2>/dev/null

if grep -qF 'Gate 4.5' "$GATES_TXT"; then
  ok "TBB2: a 'Gate 4.5' block exists in the HITL gates section"
else
  bad "TBB2: no 'Gate 4.5' block found in the HITL gates section"
fi

GATE45_TXT="$TMP/gate45.txt"
awk '/^\*\*Gate 4\.5 —/{f=1} /^\*\*Gate 5 —/{f=0} f' "$HITL_REF" >"$GATE45_TXT"

if [ -s "$GATE45_TXT" ] && grep -qi 'continue anyway' "$GATE45_TXT" \
   && grep -qi 'reduce scope' "$GATE45_TXT" \
   && grep -qi 'hand-code' "$GATE45_TXT"; then
  ok "TBB3: Gate 4.5 names all three red-route options: continue anyway, reduce scope, hand-code"
else
  bad "TBB3: Gate 4.5 is missing one of continue-anyway/reduce-scope/hand-code"
fi

if grep -qi 'abort' "$GATE45_TXT"; then
  ok "TBB4: Gate 4.5's hand-code option is explicitly an abort of the chain"
else
  bad "TBB4: Gate 4.5 does not state that hand-code aborts the chain"
fi

if grep -qF 'tracer_bullet_abort_reason' "$GATE45_TXT"; then
  ok "TBB5: Gate 4.5 records the abort reason in the manifest (tracer_bullet_abort_reason)"
else
  bad "TBB5: Gate 4.5 does not record an abort reason field"
fi

# TBB6 (dynamic): red route wiring — reduce-scope needs the (only) new pair; continue-anyway and
# hand-code reuse existing/universal pairs. Proven by actually driving manifest-transition.sh.
mk_ready "tbb6-continue"
FIX_CONT="$FIX"
mk_ready "tbb6-reduce"
FIX_RED="$FIX"
mk_ready "tbb6-abort"
FIX_ABORT="$FIX"

if [ -n "${FIX_CONT:-}" ]; then
  bash "$SETGATE" "$FIX_CONT" 4 approved >/dev/null 2>&1
  bash "$TRN" "$FIX_CONT" step_5_implementation; rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "TBB6a: red + continue-anyway -> step_5_implementation is legal (reuses the existing ready_for_implementation pair)"
  else
    bad "TBB6a: red + continue-anyway route (ready_for_implementation -> step_5_implementation) is NOT legal (rc=$rc)"
  fi
fi

if [ -n "${FIX_RED:-}" ]; then
  bash "$TRN" "$FIX_RED" gate_2_architecture_review; rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "TBB6b: red + reduce-scope -> gate_2_architecture_review is legal"
  else
    bad "TBB6b: red + reduce-scope route (ready_for_implementation -> gate_2_architecture_review) is NOT legal (rc=$rc) — this is the one pair this feature must add"
  fi
fi

if [ -n "${FIX_ABORT:-}" ]; then
  bash "$TRN" "$FIX_ABORT" aborted aborted; rc=$?
  if [ "$rc" -eq 0 ] && [ "$(current_step_of "$FIX_ABORT")" = "aborted" ]; then
    ok "TBB6c: red + hand-code -> aborted is legal (the universal any-state-to-aborted wildcard, unmodified)"
  else
    bad "TBB6c: red + hand-code -> aborted failed (rc=$rc)"
  fi
fi

# ==================================================================================================
# TBC. The verdict is derived from mechanical facts, never from the coder's opinion — the assertion
# that matters most in this file (ADR-0057 §D3 / plan §TBC).
# ==================================================================================================
if grep -qi 'build' "$STEP45_TXT" && grep -qi 'attempt' "$STEP45_TXT" \
   && grep -qF 'diff-budget-check.sh' "$STEP45_TXT"; then
  ok "TBC1: Step 4.5 lists build/run, attempt count and the diff-budget-check.sh scope check among the mechanical facts"
else
  bad "TBC1: Step 4.5 is missing one of the mechanical facts (build/run, attempt count, diff-budget-check.sh)"
fi

if grep -qF 'cannot upgrade a mechanically failing slice to green' "$STEP45_TXT"; then
  ok "TBC2: Step 4.5 states verbatim that a recommendation cannot upgrade a mechanically failing slice to green"
else
  bad "TBC2: the 'cannot upgrade a mechanically failing slice to green' sentence is missing from Step 4.5"
fi

if grep -qF 'tracer_bullet_recommendation' "$STEP45_TXT"; then
  ok "TBC3: the coder's own recommendation is recorded (tracer_bullet_recommendation) but is distinct from the computed verdict"
else
  bad "TBC3: tracer_bullet_recommendation field not referenced in Step 4.5"
fi

if grep -qi 'context only\|informational only\|never authoritative' "$STEP45_TXT"; then
  ok "TBC4: Step 4.5 states the coder's narrative is context/informational only, never authoritative"
else
  bad "TBC4: Step 4.5 does not state the narrative is non-authoritative"
fi

# ==================================================================================================
# TBD. The slice is end-to-end, not single-layer (ADR-0057 §D1 / plan §TBD).
# ==================================================================================================
if grep -qi 'end-to-end' "$STEP45_TXT" && grep -qi 'single layer' "$STEP45_TXT"; then
  ok "TBD1: Step 4.5 states the slice is end-to-end and explicitly rejects a single-layer probe"
else
  bad "TBD1: Step 4.5 is missing the end-to-end / not-single-layer statement"
fi

# ==================================================================================================
# TBE. The cost cap exists and reuses ADR-0052's budget mechanism (diff-budget-check.sh) rather
# than a second one; exceeding either the budget or the attempt cap is itself a signal
# (ADR-0057 §D4 / plan §TBE).
# ==================================================================================================
if grep -qF 'diff-budget-check.sh' "$STEP45_TXT" && grep -qF 'ADR-0052' "$STEP45_TXT"; then
  ok "TBE1: Step 4.5 reuses diff-budget-check.sh / ADR-0052's mechanism, not a second budget control"
else
  bad "TBE1: Step 4.5 does not reference diff-budget-check.sh / ADR-0052 for the budget"
fi

if grep -qi 'attempt cap' "$STEP45_TXT"; then
  ok "TBE2: Step 4.5 states a hard attempt cap"
else
  bad "TBE2: Step 4.5 does not state a hard attempt cap"
fi

if grep -qi 'exceed' "$STEP45_TXT" && grep -qi 'signal' "$STEP45_TXT"; then
  ok "TBE3: Step 4.5 states that exceeding the budget or attempt cap is itself a signal (not a reason to keep spending)"
else
  bad "TBE3: Step 4.5 does not state that exceeding the cap is itself a signal"
fi

# ==================================================================================================
# TBF. On green, the slice is kept and referenced as the pattern seed by the Step 5 briefs
# (ADR-0057 §D5 / plan §TBF).
# ==================================================================================================
if grep -qi 'pattern seed' "$STEP45_TXT"; then
  ok "TBF1: Step 4.5 names the green-verdict slice as the pattern seed"
else
  bad "TBF1: Step 4.5 does not name the slice as a pattern seed on green"
fi

if grep -qi 'kept\|not.*revert\|not.*discard' "$STEP45_TXT"; then
  ok "TBF2: Step 4.5 states the slice is kept (not reverted/discarded) on green"
else
  bad "TBF2: Step 4.5 does not state the slice is kept on green"
fi

STEP5_TXT="$TMP/step5.txt"
# The Step 5 range moved to references/step5-implementation.md (VCS-047, ADR-0174); the
# reference file's body IS the block, so no awk range is needed any more.
cp "$STEP5_REF" "$STEP5_TXT" 2>/dev/null

if [ -s "$STEP5_TXT" ]; then
  ok "TBF0: Step 5 (references/step5-implementation.md) is extractable (TBF3 below reads)"
else
  bad "TBF0: could not read references/step5-implementation.md — TBF3 below would pass vacuously (empty extract, negative-shaped risk)"
fi

if grep -qi 'pattern seed' "$STEP5_TXT" && grep -qF 'tracer_bullet_verdict' "$STEP5_TXT"; then
  ok "TBF3: the Step 5 section itself references the tracer-bullet pattern seed (coder briefs must cite it)"
else
  bad "TBF3: Step 5 does not reference the tracer-bullet pattern seed / tracer_bullet_verdict"
fi

# TBF4 (dynamic): green -> step_5_implementation is legal (reuses the existing pair, unmodified).
mk_ready "tbf4-green"
if [ -n "${FIX:-}" ]; then
  bash "$SETGATE" "$FIX" 4 approved >/dev/null 2>&1
  bash "$TRN" "$FIX" step_5_implementation; rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "TBF4: green -> step_5_implementation is legal (the existing pair, unmodified by this feature)"
  else
    bad "TBF4: green route (ready_for_implementation -> step_5_implementation) failed (rc=$rc)"
  fi
fi

# ==================================================================================================
# TBG. Amber routes back to Gate 2 for scope reduction (ADR-0057 §D2 / plan §TBG).
# ==================================================================================================
if grep -qi 'amber' "$STEP45_TXT" && grep -qi 'gate 2' "$STEP45_TXT" && grep -qi 'scope reduction' "$STEP45_TXT"; then
  ok "TBG1: Step 4.5 states amber routes back to Gate 2 for scope reduction"
else
  bad "TBG1: Step 4.5 does not state the amber -> Gate 2 scope-reduction route"
fi

# TBG2 (dynamic): amber -> gate_2_architecture_review is legal.
mk_ready "tbg2-amber"
if [ -n "${FIX:-}" ]; then
  bash "$TRN" "$FIX" gate_2_architecture_review; rc=$?
  if [ "$rc" -eq 0 ] && [ "$(current_step_of "$FIX")" = "gate_2_architecture_review" ]; then
    ok "TBG2: amber route (ready_for_implementation -> gate_2_architecture_review) is legal"
  else
    bad "TBG2: amber route (ready_for_implementation -> gate_2_architecture_review) is NOT legal (rc=$rc)"
  fi
fi

# TBG3: the resulting manifest (now sitting at gate_2_architecture_review, having come from
# ready_for_implementation) still validates cleanly -- no new invariant silently broken.
if [ -n "${FIX:-}" ]; then
  bash "$VAL" "$FIX" >"$TMP/tbg3.err" 2>&1; rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "TBG3: a manifest that took the amber route still passes manifest-validate.sh"
  else
    bad "TBG3: manifest-validate.sh rejects a manifest that took the amber route: $(cat "$TMP/tbg3.err")"
  fi
fi

# ==================================================================================================
# TBH. Registration in both CI registries (Task 6).
# ==================================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]tracer-bullet-probe[[:space:];]'; then
  ok "TBH1: docs-ci.yml's shell-tests loop list runs tracer-bullet-probe"
else
  bad "TBH1: tracer-bullet-probe is not in docs-ci.yml's explicit harness list — append it after sast-security-audit"
fi
if printf '%s' "$DOCSCI_LOOP" | grep -qE 'sast-security-audit[[:space:]]+tracer-bullet-probe([[:space:];]|$)'; then
  ok "TBH1b: tracer-bullet-probe is appended immediately after sast-security-audit, as instructed"
else
  bad "TBH1b: tracer-bullet-probe is not placed immediately after sast-security-audit in the docs-ci.yml list"
fi

CI_YML="$REPO/.github/workflows/ci.yml"
if [ -f "$CI_YML" ] && grep -qE 'tests/\*\.test\.sh|scripts/tests' "$CI_YML"; then
  ok "TBH2: ci.yml discovers *.test.sh via a glob (automatic registration, no per-file edit needed)"
else
  bad "TBH2: ci.yml does not appear to glob staging/plugin/scripts/tests/*.test.sh — check the workflow"
fi

SYNCSH="$STAGING/sync-to-claude.sh"
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" >"$TMP/pairs"
if grep -q 'tracer-bullet-probe.test' "$TMP/pairs"; then
  bad "TBH3: PAIRS gained an entry for this harness — test files do not deploy (established precedent, e.g. diff-budget-scope.test.sh BH4)"
else
  ok "TBH3: no PAIRS entry for tracer-bullet-probe.test.sh (harnesses do not deploy)"
fi

# ==================================================================================================
# TBP. Transition-pair reconciliation (the task's explicit "verify, don't assume" instruction,
# ADR-0027 precedent). Proves the documented count in SKILL.md matches manifest-transition.sh's
# comment AND the actual number of pairs the script builds.
#
# ISSUE #289 / ADR-0120: ACTUAL_PAIRS is NOT derived locally any more -- it consumes
# transition-pair-count.sh (staging/plugin/scripts/tests/), the single shared checker. ADR-0120 M3
# measured three ad-hoc derivations disagreeing on three of five mutation fixtures; this file's own
# local grep was one of them (neither block-bounded nor deduplicated). TBP2/TBP3 keep their own
# comparisons unchanged -- only the derivation input moves.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: TBP1 | plugin/scripts/tests/transition-pair-count.sh | STATS_TOTAL="$TOTAL_D" | STATS_TOTAL="1"
# plant: TBP2 | plugin/scripts/tests/transition-pair-count.sh | STATS_TOTAL="$TOTAL_D" | STATS_TOTAL="41"
# plant: TBP3 | plugin/scripts/tests/transition-pair-count.sh | STATS_TOTAL="$TOTAL_D" | STATS_TOTAL="41"
# ==================================================================================================
PTC="$SCRIPTS/tests/transition-pair-count.sh"
_tbp_stats="$(bash "$PTC" "$TRN" "$SKILL_MD" 2>&1 >/dev/null)"
ACTUAL_PAIRS="$(printf '%s\n' "$_tbp_stats" | grep -o 'pairs=[0-9]*' | head -1 | cut -d= -f2)"
ACTUAL_PAIRS="${ACTUAL_PAIRS:-0}"
TRN_COMMENT_N=$(grep -oE '[0-9]+ transitions\)' "$TRN" | grep -oE '[0-9]+' | head -1)
SKILL_TOTAL_N=$(grep -oE 'Legal transition pairs \([0-9]+ total' "$SKILL_MD" | grep -oE '[0-9]+' | head -1)

# TBP1 asserts the PAIR, not a count that stands in for it, and this is UNCHANGED by issue #289 /
# ADR-0120 D4 on purpose: ADR-0105 changed it in kind (a total is never evidence about a specific
# pair) and this chain must not reverse an Accepted decision by "consolidating" it into an equality.
# The count was 49 and is now 45 (issue #265 removed four unreachable gate_5_review_decision
# pairs), and a threshold that moves whenever an unrelated pair is added or removed was never
# evidence that THIS pair is present. The `>= 40` count guard (now sourced from the shared checker,
# not derived locally) below keeps the derivation from going vacuous -- it does not replace the
# pair-presence grep.
if [ -n "$ACTUAL_PAIRS" ] && [ "$ACTUAL_PAIRS" -ge 40 ] \
   && grep -qF 'ready_for_implementation,gate_2_architecture_review' "$TRN"; then
  ok "TBP1: the amber/reduce-scope pair ready_for_implementation,gate_2_architecture_review is present ($ACTUAL_PAIRS pairs built)"
else
  bad "TBP1: the amber/reduce-scope pair is missing, or the pair derivation returned only $ACTUAL_PAIRS"
fi

if [ -n "$TRN_COMMENT_N" ] && [ "$TRN_COMMENT_N" = "$ACTUAL_PAIRS" ]; then
  ok "TBP2: manifest-transition.sh's own comment count ($TRN_COMMENT_N) matches the actual pairs built ($ACTUAL_PAIRS)"
else
  bad "TBP2: manifest-transition.sh's comment count ($TRN_COMMENT_N) does not match the actual pairs built ($ACTUAL_PAIRS)"
fi

if [ -n "$SKILL_TOTAL_N" ] && [ "$SKILL_TOTAL_N" = "$ACTUAL_PAIRS" ]; then
  ok "TBP3: SKILL.md's documented pair total ($SKILL_TOTAL_N) matches the actual pairs built ($ACTUAL_PAIRS) — ADR-0028's reconciliation lesson applied here"
else
  bad "TBP3: SKILL.md's documented pair total ($SKILL_TOTAL_N) does not match the actual pairs built ($ACTUAL_PAIRS)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
