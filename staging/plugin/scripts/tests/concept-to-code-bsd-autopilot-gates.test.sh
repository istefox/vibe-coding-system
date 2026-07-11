#!/bin/bash
# concept-to-code-bsd-autopilot-gates test harness (ADR-0027) — Findings 1-5 from the
# concept-to-code audit (SPEC.md / issue #31). Four lettered sections:
#   Section A (Finding 1, 3 tests) — Step 1's "stamp slug marker" command must be BSD-safe
#     (awk + temp-file + mv, not GNU sed's a\ one-liner extension). A1/A2 are static text
#     anchors against SKILL.md. A3 is a live extract-and-execute test against a fixture
#     SPEC.md, disclosed as a forward-correctness/idempotency regression guard rather than a
#     RED-before/GREEN-after pair on ubuntu-latest CI specifically (GNU sed's a\ one-liner
#     extension is documented to accept this exact syntax, so the bug does not reproduce
#     there) — see ADR-0027 SS2.1/SS2.6. On a real BSD/macOS runner, by contrast, A3 DOES
#     reproduce the bug pre-fix (empirically confirmed during this implementation session,
#     Darwin/BSD sed): the old command exits 1 and never writes the marker, so A3 is
#     genuine RED here too until Task 2 lands, not merely a non-regression companion — this
#     is the platform-specific failure the P1 finding is about, observed directly rather
#     than assumed.
#   Section B (Findings 2+3, 4 tests) — autopilot must never grant TOFU trust unattended
#     (Gate 2b) and must never push unattended (Gate 0d + Step 7). Static anchors only.
#   Section C (Finding 5, 6 tests) — invariant 7 (manifest-validate.sh) must be conditional
#     on chain_path (Express: no artifacts required; Hybrid: spec only; Standard/legacy:
#     spec+adr+plan, unchanged); Gate E3's Abort must transition to aborted, not completed.
#   Section D (Finding 4, 4 tests) — Gate order: step_0_init -> gate_0d_scaffolding -> the
#     path-specific Step 1 state is the single documented routing transition for all three
#     chain_path values; the old direct Gate-0-bypassing fast path must be gone from SS2.
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... — that is the deployed copy, out of scope.
# Bash 3.2 clean. Run: bash concept-to-code-bsd-autopilot-gates.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
SKILL_DIR="$STAGING/plugin/skills/concept-to-code"
SKILL_MD="$SKILL_DIR/SKILL.md"
INIT="$SKILL_DIR/scripts/manifest-init.sh"
VAL="$SKILL_DIR/scripts/manifest-validate.sh"
TRN="$SKILL_DIR/scripts/manifest-transition.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# extract_slug_stamp: pulls the fenced bash block under the "Stamp slug marker" heading,
# regardless of the block's list-item indentation (the heading anchor and fence markers are
# unique enough within this file; anchoring the fence regex to column 1 would miss the
# actual 3-space list-item indentation SKILL.md uses here).
extract_slug_stamp() {
  awk '
    /Stamp slug marker/ { grab=1 }
    grab && /```bash/ { infence=1; next }
    grab && infence && /```/ { exit }
    grab && infence { print }
  ' "$SKILL_MD"
}

# =====================================================================================
# Section A -- Finding 1: BSD-safe slug stamp
# =====================================================================================

# A1 (static, genuine RED now): old GNU sed a\ one-liner must be gone.
if grep -qF 'a\\n**Topic slug:**' "$SKILL_MD"; then
  bad "A1: old GNU-only sed a\\ one-liner slug stamp is still present in SKILL.md"
else
  ok "A1: old GNU-only sed a\\ one-liner slug stamp is gone from SKILL.md"
fi

# A2 (static, genuine RED now): new portable awk replacement must be present.
if grep -qF 'awk -v slug=' "$SKILL_MD"; then
  ok "A2: new awk -v slug= replacement is present in SKILL.md"
else
  bad "A2: new awk -v slug= replacement not found in SKILL.md"
fi

# A3 (dynamic): live extract-and-execute against a fixture SPEC.md. Forward-correctness and
# idempotency regression guard for whichever slug-stamp command is currently in SKILL.md —
# see file header for why this is not a uniform RED-before/GREEN-after pair across runners.
FIXTURE_DIR="$TMP/a3"
mkdir -p "$FIXTURE_DIR"
printf '# Some Feature Title\n\nBody text.\n' > "$FIXTURE_DIR/SPEC.md"

RAW="$(extract_slug_stamp)"
CMD="${RAW//<project-root>/$FIXTURE_DIR}"
CMD="${CMD//<topic-slug>/test-topic-slug}"
printf '%s\n' "$CMD" > "$TMP/stamp-cmd.sh"

if bash "$TMP/stamp-cmd.sh" && grep -q '\*\*Topic slug:\*\* test-topic-slug' "$FIXTURE_DIR/SPEC.md"; then
  EXPECTED="$TMP/a3-expected"
  printf '# Some Feature Title\n\n**Topic slug:** test-topic-slug\n' > "$EXPECTED"
  ACTUAL="$TMP/a3-actual"
  awk 'NR==1,NR==3' "$FIXTURE_DIR/SPEC.md" > "$ACTUAL"
  if diff -q "$EXPECTED" "$ACTUAL" >/dev/null 2>&1; then
    BEFORE_COPY="$TMP/a3-before-rerun"
    cp "$FIXTURE_DIR/SPEC.md" "$BEFORE_COPY"
    bash "$TMP/stamp-cmd.sh"
    if diff -q "$BEFORE_COPY" "$FIXTURE_DIR/SPEC.md" >/dev/null 2>&1; then
      ok "A3: slug stamp command inserts the marker correctly and is idempotent on re-run"
    else
      bad "A3: slug stamp command is not idempotent -- file changed on second run"
    fi
  else
    bad "A3: marker not inserted in the expected position (H1, blank line, marker)"
  fi
else
  bad "A3: slug stamp command failed to run or did not write the marker"
fi

# =====================================================================================
# Section D -- Finding 4: Gate order (step_0_init -> gate_0d_scaffolding -> path Step 1)
# =====================================================================================

# mk_manifest_fixture <slug> <chain_path> -- fresh mktemp -d project dir, manifest-init.sh,
# then patches chain_path: null -> chain_path: "<chain_path>" via the exact sed shape
# SKILL.md's own Gate 0 click handler uses. Sets FIX_MANIFEST for the caller.
mk_manifest_fixture() {
  _slug="$1"; _cp="$2"
  _proj="$(mktemp -d "$TMP/proj-$_slug.XXXXXX")"
  FIX_MANIFEST="$(bash "$INIT" "$_slug" "Test $_slug" "$_proj")"
  sed -i.bak "s/^chain_path: null\$/chain_path: \"$_cp\"/" "$FIX_MANIFEST"
}

# D1 (dynamic, non-regression/mechanical proof -- expected already passing): standard.
mk_manifest_fixture "d1-standard" "standard"
MD1="$FIX_MANIFEST"
bash "$TRN" "$MD1" gate_0d_scaffolding; rc1=$?
bash "$TRN" "$MD1" step_1_interview; rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
  ok "D1: standard -- step_0_init -> gate_0d_scaffolding -> step_1_interview both legal (manifest-transition.sh unmodified)"
else
  bad "D1: standard routing sequence failed (gate_0d_scaffolding rc=$rc1, step_1_interview rc=$rc2)"
fi

# D2 (dynamic, same category): express.
mk_manifest_fixture "d2-express" "express"
MD2="$FIX_MANIFEST"
bash "$TRN" "$MD2" gate_0d_scaffolding; rc1=$?
bash "$TRN" "$MD2" step_e1_plan; rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
  ok "D2: express -- step_0_init -> gate_0d_scaffolding -> step_e1_plan both legal (manifest-transition.sh unmodified)"
else
  bad "D2: express routing sequence failed (gate_0d_scaffolding rc=$rc1, step_e1_plan rc=$rc2)"
fi

# D3 (dynamic, same category): hybrid.
mk_manifest_fixture "d3-hybrid" "hybrid"
MD3="$FIX_MANIFEST"
bash "$TRN" "$MD3" gate_0d_scaffolding; rc1=$?
bash "$TRN" "$MD3" step_h1_interview; rc2=$?
if [ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ]; then
  ok "D3: hybrid -- step_0_init -> gate_0d_scaffolding -> step_h1_interview both legal (manifest-transition.sh unmodified)"
else
  bad "D3: hybrid routing sequence failed (gate_0d_scaffolding rc=$rc1, step_h1_interview rc=$rc2)"
fi

# D4 (static, genuine RED now): the old fast-path bypass phrase must be gone from SS2 Form A.
if grep -qF '`express` → transition `step_0_init → step_e1_plan`' "$SKILL_MD"; then
  bad "D4: old Gate-0-bypassing fast-path phrase is still present in SS2 Form A"
else
  ok "D4: old Gate-0-bypassing fast-path phrase is gone from SS2 Form A"
fi

# =====================================================================================
# Section B -- Findings 2+3: autopilot no-unattended-trust / no-unattended-push
# =====================================================================================
# All four are static text anchors against SKILL.md -- no subprocess execution.

# B1 (static, genuine RED now): Gate 2b's autopilot bracket must not call approve-test-cmd.sh
# unconditionally.
if grep -qF '"Approve" → run `approve-test-cmd.sh` and proceed' "$SKILL_MD"; then
  bad "B1: Gate 2b autopilot bracket still calls approve-test-cmd.sh unconditionally"
else
  ok "B1: Gate 2b autopilot bracket no longer calls approve-test-cmd.sh unconditionally"
fi

# B2 (static, genuine RED now): the TRUSTED/NOT_TRUSTED probe must be present.
if grep -qF 'NOT_TRUSTED → autopilot must never establish trust unattended' "$SKILL_MD"; then
  ok "B2: Gate 2b autopilot bracket probes pre-existing trust (TRUSTED/NOT_TRUSTED)"
else
  bad "B2: Gate 2b autopilot bracket does not yet probe pre-existing trust"
fi

# B3 (static, genuine RED now): Gate 0d's autopilot bracket must not condition push on remote
# presence. Compound anchor deliberate -- see file header / ADR-0027 SS2.6 for why a bare
# 'initial_commit_push: "push"' substring would also match the legitimate interactive Q4
# option and never be satisfiable as an anchor.
if grep -qF '`_git_remote` non-empty → `initial_commit_push: "push"`' "$SKILL_MD"; then
  bad "B3: Gate 0d autopilot bracket still conditions push on remote presence"
else
  ok "B3: Gate 0d autopilot bracket no longer conditions push on remote presence"
fi

# B4 (static, genuine RED now): Step 7's push trigger must add the autopilot guard clause.
if grep -qF 'AND manifest.autopilot != true' "$SKILL_MD"; then
  ok "B4: Step 7 push trigger has the autopilot guard clause"
else
  bad "B4: Step 7 push trigger is missing the autopilot guard clause"
fi

# =====================================================================================
# Section C -- Finding 5: invariant 7 conditional on chain_path + Gate E3 Abort split
# =====================================================================================

# mk_c_fixture <slug> -- fresh mktemp -d project dir + manifest-init.sh, no field patches.
# Sets FIX_MANIFEST for the caller. chain_path/status/artifacts.spec patched separately by
# the caller via the patch_* helpers below, so each C-test can compose exactly the fields it
# needs (unlike Section D's mk_manifest_fixture, which always patches chain_path).
mk_c_fixture() {
  _slug="$1"
  _proj="$(mktemp -d "$TMP/proj-$_slug.XXXXXX")"
  FIX_MANIFEST="$(bash "$INIT" "$_slug" "Test $_slug" "$_proj")"
}
patch_chain_path() {
  sed -i.bak "s/^chain_path: null\$/chain_path: \"$2\"/" "$1"
}
patch_status_completed() {
  sed -i.bak 's/^status: .*/status: "completed"/' "$1"
}
patch_spec_artifact() {
  sed -i.bak 's|^  spec: null|  spec: "/tmp/SPEC.md"|' "$1"
}

# C1 (dynamic, genuine RED now): express + completed + null artifacts -- must validate PASS.
mk_c_fixture "c1-express"
M1="$FIX_MANIFEST"
patch_chain_path "$M1" "express"
patch_status_completed "$M1"
if bash "$VAL" "$M1"; then
  ok "C1: express + completed + null artifacts -- validate PASS (invariant 7 skips express)"
else
  bad "C1: express + completed + null artifacts -- validate FAILs (invariant 7 still unconditional)"
fi

# C2 (dynamic, non-regression companion -- expected already passing, must stay failing after
# Task 8 too): standard/legacy (chain_path stays null) + completed + null artifacts -- must
# still validate FAIL.
mk_c_fixture "c2-standard"
M2="$FIX_MANIFEST"
patch_status_completed "$M2"
if bash "$VAL" "$M2"; then
  bad "C2: standard/legacy + completed + null artifacts -- validate unexpectedly PASSed"
else
  ok "C2: standard/legacy + completed + null artifacts -- validate correctly FAILs (guard against Task 8 over-relaxing Standard)"
fi

# C3 (dynamic, genuine RED now): hybrid + completed + spec set (adr/plan null) -- must
# validate PASS (narrower carve-out than express's blanket skip).
mk_c_fixture "c3-hybrid"
M3="$FIX_MANIFEST"
patch_chain_path "$M3" "hybrid"
patch_status_completed "$M3"
patch_spec_artifact "$M3"
if bash "$VAL" "$M3"; then
  ok "C3: hybrid + completed + spec set (adr/plan null) -- validate PASS"
else
  bad "C3: hybrid + completed + spec set -- validate FAILs (invariant 7 still requires adr/plan)"
fi

# C4 (dynamic, non-regression companion -- expected already passing, must stay failing after
# Task 8 too): hybrid + completed + spec ALSO null -- must still validate FAIL (proves the
# hybrid carve-out is narrower than express's, not a second blanket skip).
mk_c_fixture "c4-hybrid-nospec"
M4="$FIX_MANIFEST"
patch_chain_path "$M4" "hybrid"
patch_status_completed "$M4"
if bash "$VAL" "$M4"; then
  bad "C4: hybrid + completed + spec also null -- validate unexpectedly PASSed"
else
  ok "C4: hybrid + completed + spec also null -- validate correctly FAILs (hybrid still requires spec)"
fi

# C5 (static, genuine RED now): Gate E3's Commit later / Abort must no longer share one
# transition block.
if grep -qF '`Commit later` / `Abort`:' "$SKILL_MD"; then
  bad "C5: Gate E3 still shares one label/transition block for Commit later and Abort"
else
  ok "C5: Gate E3's Commit later and Abort blocks are split"
fi

# C6 (dynamic, non-regression/mechanical proof -- expected already passing): fresh manifest,
# no chain_path/status patch needed, straight to aborted -- must be legal and validate clean.
mk_c_fixture "c6-abort"
M6="$FIX_MANIFEST"
if bash "$TRN" "$M6" aborted aborted \
  && grep -q '^status: "aborted"$' "$M6" \
  && bash "$VAL" "$M6"; then
  ok "C6: fresh manifest -> aborted transition is legal and validates clean (manifest-transition.sh unmodified)"
else
  bad "C6: aborted transition or the resulting manifest's validation failed"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
