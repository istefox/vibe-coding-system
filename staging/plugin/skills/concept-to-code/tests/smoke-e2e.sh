#!/usr/bin/env bash
# concept-to-code smoke E2E test. Exercises full state machine composition.
# bash 3.2-clean. No assoc arrays, no mapfile, no ${v^^}, no <().
set -u
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SKILL_DIR="$HOME/.claude/skills/concept-to-code"
INIT="$SKILL_DIR/scripts/manifest-init.sh"
VAL="$SKILL_DIR/scripts/manifest-validate.sh"
TRN="$SKILL_DIR/scripts/manifest-transition.sh"

fail() { echo "SMOKE=FAIL:$1:$2"; exit 1; }

# Phase: setup
echo "[smoke] setup OK tmp=$TMP" >&2

# Phase: init (proj/ — primary happy path manifest)
PROJ="$TMP/proj"
mkdir -p "$PROJ"
bash "$INIT" demo "Demo Feature" "$PROJ" >/dev/null 2>&1 \
  || fail "init" "init exit non-zero"
M="$PROJ/docs/manifests/$(date +%Y-%m-%d)-demo.manifest.yml"
[ -f "$M" ] || fail "init" "manifest file missing $M"
echo "[smoke] init OK M=$M" >&2

# Phase: happy — 18 transitions covering 15/16 unique pairs (proj/)
step() {
  local idx="$1" from="$2" to="$3"
  bash "$TRN" "$M" "$to" >/dev/null 2>&1 \
    || fail "happy" "$idx $from->$to transition rejected"
  local cur
  cur="$(grep '^current_step:' "$M" | sed 's/^current_step: *//;s/"//g' | head -1)"
  [ "$cur" = "$to" ] || fail "happy" "$idx after $from->$to current_step=$cur expected=$to"
  echo "[smoke] happy $idx/18 $from->$to OK current_step=$to" >&2
}

step  1  step_0_init               step_1_interview
step  2  step_1_interview          gate_1_spec_review
step  3  gate_1_spec_review        step_1_interview
step  4  step_1_interview          gate_1_spec_review
step  5  gate_1_spec_review        step_2_architecture
step  6  step_2_architecture       gate_2_architecture_review
step  7  gate_2_architecture_review step_2_architecture
step  8  step_2_architecture       gate_2_architecture_review
step  9  gate_2_architecture_review step_3_project_memory
step 10  step_3_project_memory     gate_3_project_memory_review
step 11  gate_3_project_memory_review step_3_project_memory
step 12  step_3_project_memory     gate_3_project_memory_review
step 13  gate_3_project_memory_review step_4_session_boundary
step 14  step_4_session_boundary   ready_for_implementation
step 15  ready_for_implementation  step_5_implementation
step 16  step_5_implementation     step_6_review
step 17  step_6_review             gate_5_review_decision
step 18  gate_5_review_decision    completed

# Phase: happy2 — 11 transitions covering shortcut pair (proj2/)
PROJ2="$TMP/proj2"
mkdir -p "$PROJ2"
bash "$INIT" demo2 "Demo 2" "$PROJ2" >/dev/null 2>&1 \
  || fail "init" "init proj2 exit non-zero"
M2="$PROJ2/docs/manifests/$(date +%Y-%m-%d)-demo2.manifest.yml"
[ -f "$M2" ] || fail "init" "manifest2 missing $M2"
echo "[smoke] init OK M2=$M2 (shortcut flow)" >&2

step2() {
  local idx="$1" from="$2" to="$3"
  bash "$TRN" "$M2" "$to" >/dev/null 2>&1 \
    || fail "happy2" "$idx $from->$to transition rejected"
  echo "[smoke] happy2 $idx/11 $from->$to OK" >&2
}

step2  1  step_0_init                    step_1_interview
step2  2  step_1_interview               gate_1_spec_review
step2  3  gate_1_spec_review             step_2_architecture
step2  4  step_2_architecture            gate_2_architecture_review
step2  5  gate_2_architecture_review     step_3_project_memory
step2  6  step_3_project_memory          gate_3_project_memory_review
step2  7  gate_3_project_memory_review   step_4_session_boundary
step2  8  step_4_session_boundary        ready_for_implementation
step2  9  ready_for_implementation       step_5_implementation
step2 10  step_5_implementation          gate_5_review_decision
step2 11  gate_5_review_decision         completed

# Phase: illegal — 3 attempts from step_0_init (proj3/, fresh manifest)
PROJ3="$TMP/proj3"
mkdir -p "$PROJ3"
bash "$INIT" illegal "Illegal Tests" "$PROJ3" >/dev/null 2>&1
M3="$PROJ3/docs/manifests/$(date +%Y-%m-%d)-illegal.manifest.yml"
illegal() {
  local idx="$1" target="$2"
  bash "$TRN" "$M3" "$target" >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "1" ] || fail "illegal" "$idx target=$target expected exit 1 got $rc"
  echo "[smoke] illegal $idx/3 step_0->$target REJECTED OK" >&2
}
illegal 1 step_5_implementation
illegal 2 completed
illegal 3 gate_2_architecture_review

# Phase: failure-force — proj4/, transition to failed
PROJ4="$TMP/proj4"
mkdir -p "$PROJ4"
bash "$INIT" failtest "Fail Force" "$PROJ4" >/dev/null 2>&1
M4="$PROJ4/docs/manifests/$(date +%Y-%m-%d)-failtest.manifest.yml"
bash "$TRN" "$M4" failed failed >/dev/null 2>&1 \
  || fail "failure-force" "transition to failed rejected"
grep -q '^status: "failed"' "$M4" \
  || fail "failure-force" "status not failed"
echo "[smoke] failure-force OK status=failed" >&2

# Phase: brainstorm path (g1→g1b→2) — proj5/
PROJ5="$TMP/proj5"
mkdir -p "$PROJ5"
bash "$INIT" brainstorm-path "Brainstorm Path" "$PROJ5" >/dev/null 2>&1 \
  || fail "init" "init proj5 exit non-zero"
M5="$PROJ5/docs/manifests/$(date +%Y-%m-%d)-brainstorm-path.manifest.yml"
[ -f "$M5" ] || fail "init" "manifest5 missing $M5"
echo "[smoke] brainstorm-path init OK M5=$M5" >&2

bash "$TRN" "$M5" step_1_interview >/dev/null 2>&1 || fail "brainstorm" "0->1 rejected"
bash "$TRN" "$M5" gate_1_spec_review >/dev/null 2>&1 || fail "brainstorm" "1->g1 rejected"
bash "$TRN" "$M5" gate_1b_brainstorm_decision >/dev/null 2>&1 || fail "brainstorm" "g1->g1b rejected"
bash "$TRN" "$M5" step_2_architecture >/dev/null 2>&1 || fail "brainstorm" "g1b->2 rejected"

cur5="$(grep '^current_step:' "$M5" | sed 's/^current_step: *//;s/"//g' | head -1)"
[ "$cur5" = "step_2_architecture" ] || fail "brainstorm" "expected step_2_architecture got $cur5"
echo "[smoke] brainstorm-path g1->g1b->2 OK current_step=step_2_architecture" >&2

# Phase: macos-ux path (g1b->g1c->2) — proj6/
PROJ6="$TMP/proj6"
mkdir -p "$PROJ6"
bash "$INIT" macos-ux-path "macOS UX Path" "$PROJ6" >/dev/null 2>&1 \
  || fail "init" "init proj6 exit non-zero"
M6="$PROJ6/docs/manifests/$(date +%Y-%m-%d)-macos-ux-path.manifest.yml"
[ -f "$M6" ] || fail "init" "manifest6 missing $M6"
# Verify ux_blueprint: null line exists in manifest (manifest-init.sh write)
grep -q '^  ux_blueprint: null' "$M6" \
  || fail "macos-ux" "ux_blueprint not in manifest artifacts"
echo "[smoke] macos-ux-path init OK M6=$M6 (ux_blueprint field present)" >&2

bash "$TRN" "$M6" step_1_interview >/dev/null 2>&1 || fail "macos-ux" "0->1 rejected"
bash "$TRN" "$M6" gate_1_spec_review >/dev/null 2>&1 || fail "macos-ux" "1->g1 rejected"
bash "$TRN" "$M6" gate_1b_brainstorm_decision >/dev/null 2>&1 || fail "macos-ux" "g1->g1b rejected"
bash "$TRN" "$M6" gate_1c_macos_ux_decision >/dev/null 2>&1 || fail "macos-ux" "g1b->g1c rejected"
bash "$TRN" "$M6" step_2_architecture >/dev/null 2>&1 || fail "macos-ux" "g1c->2 rejected"

cur6="$(grep '^current_step:' "$M6" | sed 's/^current_step: *//;s/"//g' | head -1)"
[ "$cur6" = "step_2_architecture" ] || fail "macos-ux" "expected step_2_architecture got $cur6"
echo "[smoke] macos-ux-path g1b->g1c->2 OK current_step=step_2_architecture" >&2

# Phase: macos-ux hybrid path (gate_h1b->gate_h1c->step_h2) — proj7/
PROJ7="$TMP/proj7"
mkdir -p "$PROJ7"
bash "$INIT" macos-ux-hybrid "macOS UX Hybrid" "$PROJ7" >/dev/null 2>&1 \
  || fail "init" "init proj7 exit non-zero"
M7="$PROJ7/docs/manifests/$(date +%Y-%m-%d)-macos-ux-hybrid.manifest.yml"
[ -f "$M7" ] || fail "init" "manifest7 missing $M7"
echo "[smoke] macos-ux-hybrid init OK M7=$M7" >&2

bash "$TRN" "$M7" step_h1_interview >/dev/null 2>&1 || fail "macos-ux-hybrid" "0->h1 rejected"
bash "$TRN" "$M7" gate_h1_spec_review >/dev/null 2>&1 || fail "macos-ux-hybrid" "h1->gh1 rejected"
bash "$TRN" "$M7" gate_h1b_brainstorm >/dev/null 2>&1 || fail "macos-ux-hybrid" "gh1->gh1b rejected"
bash "$TRN" "$M7" gate_h1c_macos_ux >/dev/null 2>&1 || fail "macos-ux-hybrid" "gh1b->gh1c rejected"
bash "$TRN" "$M7" step_h2_plan >/dev/null 2>&1 || fail "macos-ux-hybrid" "gh1c->h2 rejected"

cur7="$(grep '^current_step:' "$M7" | sed 's/^current_step: *//;s/"//g' | head -1)"
[ "$cur7" = "step_h2_plan" ] || fail "macos-ux-hybrid" "expected step_h2_plan got $cur7"
echo "[smoke] macos-ux-hybrid gh1b->gh1c->h2 OK current_step=step_h2_plan" >&2

# Phase: consistency — re-check M from proj/ (primary happy path)
# manifest-transition.sh does not auto-set status=completed; only current_step is verified.
final_step="$(grep '^current_step:' "$M" | sed 's/^current_step: *//;s/"//g' | head -1)"
[ "$final_step" = "completed" ] || fail "consistency" "final current_step=$final_step expected completed"
echo "[smoke] consistency OK current_step=completed" >&2

echo "[smoke] teardown OK" >&2
echo "SMOKE=PASS"
exit 0
