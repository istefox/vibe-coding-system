#!/usr/bin/env bash
# Self-test harness for concept-to-code skill. Isolated; never touches real state.
set -u
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SKILL_DIR="$HOME/.claude/skills/concept-to-code"
INIT="$SKILL_DIR/scripts/manifest-init.sh"
VAL="$SKILL_DIR/scripts/manifest-validate.sh"
TRN="$SKILL_DIR/scripts/manifest-transition.sh"

# --- Assertion 1: manifest-init creates valid manifest at expected path ---
mkdir -p "$TMP/proj1"
bash "$INIT" smoke-1 "Smoke 1" "$TMP/proj1" >/dev/null 2>&1
M1="$TMP/proj1/docs/manifests/$(date +%Y-%m-%d)-smoke-1.manifest.yml"
[ -f "$M1" ] && ok "manifest-init: writes file at expected path" || bad "manifest-init: file missing"

# --- Assertion 2: manifest-init refuses double-init same slug same day ---
bash "$INIT" smoke-1 "Smoke 1" "$TMP/proj1" >/dev/null 2>&1
[ "$?" = "2" ] && ok "manifest-init: refuses double init (exit 2)" || bad "manifest-init: double init not rejected"

# --- Assertion 3: manifest-validate PASS on fresh-init manifest ---
bash "$VAL" "$M1" >/dev/null 2>&1 && ok "manifest-validate: fresh init passes" || bad "manifest-validate: fresh init fails"

# --- Assertion 4: manifest-validate FAIL without manifest_schema_version ---
M_BAD="$TMP/bad-noversion.yml"
grep -v 'manifest_schema_version' "$M1" > "$M_BAD"
bash "$VAL" "$M_BAD" >/dev/null 2>&1
[ "$?" != "0" ] && ok "manifest-validate: rejects missing schema_version" || bad "manifest-validate: accepts missing schema_version"

# --- Assertion 5: manifest-validate FAIL with invalid current_step ---
M_BAD2="$TMP/bad-step.yml"
sed 's/^current_step: .*/current_step: "step_NOT_REAL"/' "$M1" > "$M_BAD2"
bash "$VAL" "$M_BAD2" >/dev/null 2>&1
[ "$?" != "0" ] && ok "manifest-validate: rejects invalid current_step" || bad "manifest-validate: accepts invalid current_step"

# --- Assertion 6: transition step_0_init → step_1_interview legal ---
bash "$TRN" "$M1" step_1_interview >/dev/null 2>&1 && ok "manifest-transition: 0->1 legal" || bad "manifest-transition: 0->1 rejected"

# --- Assertion 7: transition step_0_init → step_5_implementation illegal ---
mkdir -p "$TMP/proj2"
bash "$INIT" smoke-2 "Smoke 2" "$TMP/proj2" >/dev/null 2>&1
M2="$TMP/proj2/docs/manifests/$(date +%Y-%m-%d)-smoke-2.manifest.yml"
bash "$TRN" "$M2" step_5_implementation >/dev/null 2>&1
[ "$?" = "1" ] && ok "manifest-transition: skip 0->5 rejected" || bad "manifest-transition: skip 0->5 accepted"

# --- Assertion 7b: 3-arg misuse — step-name as new_status must be rejected ---
# Regression for: orchestrator passing (from, to) args instead of (to, [status]),
# e.g. manifest-transition.sh manifest.yml step_1_interview gate_1_spec_review
# This silently wrote status: "gate_1_spec_review" and corrupted the manifest.
mkdir -p "$TMP/proj2b"
bash "$INIT" smoke-2b "Smoke 2b" "$TMP/proj2b" >/dev/null 2>&1
M2B="$TMP/proj2b/docs/manifests/$(date +%Y-%m-%d)-smoke-2b.manifest.yml"
bash "$TRN" "$M2B" step_1_interview gate_1_spec_review >/dev/null 2>&1
RC2B=$?
STATUS2B="$(grep '^status:' "$M2B" | sed 's/^status: *//;s/"//g' | head -1)"
if [ "$RC2B" = "1" ] && [ "$STATUS2B" = "in_progress" ]; then
  ok "manifest-transition: step-name as new_status rejected (status field uncorrupted)"
else
  bad "manifest-transition: step-name as new_status NOT rejected (rc=$RC2B status=$STATUS2B)"
fi

# --- Assertion 8: transition updates last_updated_at ---
BEFORE="$(grep '^last_updated_at:' "$M1")"
sleep 2
bash "$TRN" "$M1" gate_1_spec_review >/dev/null 2>&1
AFTER="$(grep '^last_updated_at:' "$M1")"
[ "$BEFORE" != "$AFTER" ] && ok "manifest-transition: last_updated_at refreshed" || bad "manifest-transition: last_updated_at stale"

# --- Assertion 9: validate completed manifest requires artifacts populated ---
M_COMPL="$TMP/completed.yml"
sed -e 's/^status: .*/status: "completed"/' -e "s|^  spec: null|  spec: /tmp/SPEC.md|" "$M1" > "$M_COMPL"
# Still missing adr and plan as absolute paths → should fail validation
bash "$VAL" "$M_COMPL" >/dev/null 2>&1
[ "$?" != "0" ] && ok "manifest-validate: completed requires artifacts" || bad "manifest-validate: completed accepts null artifacts"

# --- Assertion 10: validate failed manifest requires failure.failed_step ---
M_FAIL="$TMP/failed.yml"
sed 's/^status: .*/status: "failed"/' "$M1" > "$M_FAIL"
# failure.failed_step is null in fresh-init → should fail
bash "$VAL" "$M_FAIL" >/dev/null 2>&1
[ "$?" != "0" ] && ok "manifest-validate: failed requires failed_step" || bad "manifest-validate: failed accepts null failed_step"

# --- Assertion 11: invariant-7: unquoted absolute path must NOT satisfy artifact check ---
# Bug: grep -q '^  spec: /' accepts unquoted paths (e.g. "  spec: /tmp/foo").
# The correct format is a quoted path ("  spec: \"/tmp/foo\"").
# With the old regex, an unquoted path would be accepted as valid (false positive).
# With the fixed regex (grep -Eq '^  spec: "/[^"]+"$'), unquoted paths are correctly rejected.
# This test creates a completed manifest where spec has an unquoted path (malformed) —
# validate must return exit 1, not 0.
M_UNQUOTED="$TMP/bad-unquoted.yml"
sed -e 's/^status: .*/status: "completed"/' "$M1" > "$M_UNQUOTED"
# Inject unquoted absolute paths for all three artifact fields
sed -i.bak \
    -e 's|^  spec: null|  spec: /tmp/SPEC.md|' \
    -e 's|^  adr: null|  adr: /tmp/ADR.md|' \
    -e 's|^  plan: null|  plan: /tmp/PLAN.md|' \
    "$M_UNQUOTED"
bash "$VAL" "$M_UNQUOTED" >/dev/null 2>&1
[ "$?" != "0" ] && ok "invariant-7: unquoted artifact path correctly rejected (false-positive fix)" || bad "invariant-7: unquoted artifact path accepted — old false-positive bug not fixed"

# --- Assertion 12: invariant-7: quoted paths must be accepted, null must be rejected ---
# Positive control: a completed manifest with properly quoted artifact paths passes validation.
# Separate negative: spec=null with adr+plan quoted must still fail (null not valid).
M_NULL_SPEC="$TMP/bad-null-spec.yml"
sed -e 's/^status: .*/status: "completed"/' "$M1" > "$M_NULL_SPEC"
sed -i.bak \
    -e 's|^  adr: null|  adr: "/tmp/ADR.md"|' \
    -e 's|^  plan: null|  plan: "/tmp/PLAN.md"|' \
    "$M_NULL_SPEC"
# spec is still null — validator must reject
bash "$VAL" "$M_NULL_SPEC" >/dev/null 2>&1
[ "$?" != "0" ] && ok "invariant-7: null spec with quoted adr+plan correctly rejected" || bad "invariant-7: null spec with quoted adr+plan accepted — invariant-7 not enforced"

# --- Assertion 13: end-to-end smoke ---
bash "$SKILL_DIR/tests/smoke-e2e.sh" >/dev/null 2>&1 \
  && ok "smoke-e2e: full state machine composition" \
  || bad "smoke-e2e: full state machine composition"

# --- Assertions 14-20: schema 1.1, retrocompat 1.0, gate_1b, mode ---

# Assertion 14: manifest-init writes schema 1.3 (ADR-0017)
mkdir -p "$TMP/proj14"
bash "$INIT" smoke-14 "Smoke 14" "$TMP/proj14" >/dev/null 2>&1
M14="$TMP/proj14/docs/manifests/$(date +%Y-%m-%d)-smoke-14.manifest.yml"
grep -q '^manifest_schema_version: "1.3"$' "$M14" 2>/dev/null \
  && ok "manifest-init: writes schema 1.3" \
  || bad "manifest-init: schema 1.3 not written"

# Assertion 15: validate accepts a hand-crafted 1.0 legacy manifest (retrocompat)
M15="$TMP/legacy-10.manifest.yml"
mkdir -p "$TMP/proj15"
cat > "$M15" <<YMLEOF
manifest_schema_version: "1.0"
topic: "legacy-test"
topic_full_title: "Legacy Test"
project_root: "$TMP/proj15"
created_at: "2026-05-20T10:00:00+00:00"
last_updated_at: "2026-05-20T10:00:00+00:00"
current_step: "step_0_init"
status: "in_progress"
artifacts:
  spec: null
  adr: null
  arch: null
  plan: null
  project_claude_md: null
hitl_gates:
  - gate: 1
    label: "spec_review"
    status: "pending"
    approved_at: null
    notes: null
  - gate: 2
    label: "architecture_review"
    status: "pending"
    approved_at: null
    notes: null
  - gate: 3
    label: "project_memory_review"
    status: "pending"
    approved_at: null
    notes: null
  - gate: 5
    label: "review_cycle_decision"
    status: "pending"
    approved_at: null
    notes: null
session_boundary:
  pre_step_4_session_id: null
  fresh_session_started_at: null
  resumed_at: null
failure:
  failed_at: null
  failed_step: null
  failure_reason: null
  partial_artifacts: []
next_action: "resume"
YMLEOF
bash "$VAL" "$M15" >/dev/null 2>&1 \
  && ok "manifest-validate: accepts schema 1.0 legacy (retrocompat)" \
  || bad "manifest-validate: rejects schema 1.0 legacy (regression)"

# Assertion 16: transition gate_1_spec_review → gate_1b_brainstorm_decision is legal
mkdir -p "$TMP/proj16"
bash "$INIT" smoke-16 "Smoke 16" "$TMP/proj16" >/dev/null 2>&1
M16="$TMP/proj16/docs/manifests/$(date +%Y-%m-%d)-smoke-16.manifest.yml"
bash "$TRN" "$M16" step_1_interview >/dev/null 2>&1
bash "$TRN" "$M16" gate_1_spec_review >/dev/null 2>&1
bash "$TRN" "$M16" gate_1b_brainstorm_decision >/dev/null 2>&1 \
  && ok "manifest-transition: g1→g1b legal" \
  || bad "manifest-transition: g1→g1b rejected"

# Assertion 17: transition gate_1b_brainstorm_decision → step_2_architecture is legal
bash "$TRN" "$M16" step_2_architecture >/dev/null 2>&1 \
  && ok "manifest-transition: g1b→2 legal" \
  || bad "manifest-transition: g1b→2 rejected"

# Assertion 18: validate accepts current_step gate_1b_brainstorm_decision
mkdir -p "$TMP/proj18"
bash "$INIT" smoke-18 "Smoke 18" "$TMP/proj18" >/dev/null 2>&1
M18="$TMP/proj18/docs/manifests/$(date +%Y-%m-%d)-smoke-18.manifest.yml"
M18B="$TMP/smoke-18-g1b.yml"
sed 's/^current_step: "step_0_init"/current_step: "gate_1b_brainstorm_decision"/' "$M18" > "$M18B"
bash "$VAL" "$M18B" >/dev/null 2>&1 \
  && ok "manifest-validate: accepts gate_1b_brainstorm_decision as current_step" \
  || bad "manifest-validate: rejects gate_1b_brainstorm_decision (regression)"

# Assertion 19: validate rejects mode: "bogus"
mkdir -p "$TMP/proj19"
bash "$INIT" smoke-19 "Smoke 19" "$TMP/proj19" >/dev/null 2>&1
M19="$TMP/proj19/docs/manifests/$(date +%Y-%m-%d)-smoke-19.manifest.yml"
M19B="$TMP/smoke-19-bogus.yml"
sed 's/^mode: "greenfield"/mode: "bogus"/' "$M19" > "$M19B"
bash "$VAL" "$M19B" >/dev/null 2>&1 \
  && bad "manifest-validate: accepts mode=bogus (should fail)" \
  || ok "manifest-validate: rejects mode=bogus (correct)"

# Assertion 20: gate0-detect on dir with SPEC.md+ADR prints spec_adr_exist=true and mode=brownfield
GATE0="$SKILL_DIR/scripts/gate0-detect.sh"
D20="$TMP/proj20"
mkdir -p "$D20/docs/architecture"
touch "$D20/SPEC.md"
touch "$D20/docs/architecture/ADR-0001-test.md"
OUT20="$(bash "$GATE0" "$D20" 2>/dev/null)"
echo "$OUT20" | grep -q 'spec_adr_exist=true' \
  && echo "$OUT20" | grep -q 'mode=brownfield' \
  && ok "gate0-detect: SPEC.md+ADR → spec_adr_exist=true, mode=brownfield" \
  || bad "gate0-detect: expected spec_adr_exist=true mode=brownfield"


# --- Gate 0b — anonymize (ADR-0011) ---
CC="$SKILL_DIR/SKILL.md"
grep -q -- 'Gate 0b' "$CC" 2>/dev/null && ok "concept-to-code: Gate 0b anonymize present" || bad "concept-to-code: Gate 0b missing"
grep -q -- 'anonymize' "$CC" 2>/dev/null && ok "concept-to-code: anonymize mode documented" || bad "concept-to-code: anonymize mode missing"
grep -Eq '1\.2' "$VAL" 2>/dev/null && ok "manifest-validate: schema 1.2 accepted" || bad "manifest-validate: schema 1.2 missing"
grep -Eq '1\.3' "$VAL" 2>/dev/null && ok "manifest-validate: schema 1.3 accepted" || bad "manifest-validate: schema 1.3 missing"
# Regression 2026-05-24: detect-public-remote.sh lives in clean-public-repo, not concept-to-code.
# Any unqualified `scripts/detect-public-remote` ref resolves to the wrong skill → runtime ENOENT.
CC_BARE_DPR=$(grep -n 'scripts/detect-public-remote' "$CC" 2>/dev/null | grep -v 'clean-public-repo/scripts/detect-public-remote')
[ -z "$CC_BARE_DPR" ] && ok "concept-to-code: detect-public-remote ref qualified (clean-public-repo abs path)" || bad "concept-to-code: unqualified scripts/detect-public-remote ref (runtime ENOENT)"

# ADR-0012 agent-notes round-trip assertion removed here (VCS-056, ADR-0183): the mediated
# inject/harvest mechanism it tested (agent-notes-harvest.sh, tests/agent-notes-roundtrip.sh)
# was retired when every agent that used it (architect, debugger, reviewer) moved to native
# `memory:` persistence. Rule 19.

# --- ADR-0014: chain (Step 2) proposes .claude/test-cmd + TOFU gate ---
CC="$SKILL_DIR/SKILL.md"
if grep -q -- 'TEST-CMD CANDIDATE' "$CC" 2>/dev/null && grep -q -- 'approve-test-cmd.sh' "$CC" 2>/dev/null; then
  ok "concept-to-code: ADR-0014 test-cmd candidate contract + TOFU gate present"
else
  bad "concept-to-code: ADR-0014 test-cmd contract missing"
fi

# --- ADR-0014 ext: planning placeholder NONE (non-clobber, evita Stop-gate in planning) ---
if grep -q -- 'Planning placeholder' "$CC" 2>/dev/null && grep -q -- 'NEVER overwrite.*test-cmd\|NEVER overwrite an existing test-cmd' "$CC" 2>/dev/null; then
  ok "concept-to-code: ADR-0014 ext planning placeholder NONE (non-clobber) present"
else
  bad "concept-to-code: ADR-0014 ext planning placeholder missing"
fi

# --- ADR-0014 Gate 2b redesign: AskUserQuestion TOFU + anti-self-approve ---
if grep -q -- 'Gate 2b' "$CC" 2>/dev/null && grep -q -- 'AskUserQuestion' "$CC" 2>/dev/null; then
  ok "concept-to-code: Gate 2b AskUserQuestion TOFU pattern present"
else
  bad "concept-to-code: Gate 2b AskUserQuestion TOFU pattern missing"
fi
if grep -q -- 'NEVER call.*approve-test-cmd' "$CC" 2>/dev/null && grep -q -- 'NEVER modify.*test-cmd.*autonomously' "$CC" 2>/dev/null; then
  ok "concept-to-code: anti-self-approve + anti-self-edit guardrails present"
else
  bad "concept-to-code: anti-self-approve / anti-self-edit guardrails missing"
fi

# --- Step 5 dispatch: test-cmd off-limits guardrail in both dispatch templates ---
if grep -c -- '\.claude/test-cmd.*off-limits\|test-cmd.*off-limits' "$CC" 2>/dev/null | grep -q '^[2-9]'; then
  ok "concept-to-code: test-cmd off-limits guardrail present in both Step 5 dispatch templates"
else
  bad "concept-to-code: test-cmd off-limits guardrail missing from Step 5 dispatch (needs to appear in workflow AND fallback templates)"
fi

# --- Resume path TOFU guard (Step 2b): read-only trust check before Step 5 ---
if grep -q -- 'Step 2b.*TOFU guard\|TOFU guard.*resume' "$CC" 2>/dev/null \
   && grep -q -- 'TRUSTED.*proceed to Step 5\|NOT_TRUSTED.*TOFU missing' "$CC" 2>/dev/null \
   && grep -q -- 'NEVER call.*approve-test-cmd.*Approve.*click\|NEVER call.*approve-test-cmd.sh.*before.*Approve' "$CC" 2>/dev/null; then
  ok "concept-to-code: resume-path TOFU guard (Step 2b) present with read-only check + gate"
else
  bad "concept-to-code: resume-path TOFU guard (Step 2b) missing"
fi

# --- Gate 4 session boundary: blocking AskUserQuestion + hard STOP ---
if grep -q -- 'Gate 4.*BLOCKING\|Gate 4.*blocking' "$CC" 2>/dev/null \
   && grep -q -- 'STOP.*after.*AskUserQuestion\|STOP.*turn ends' "$CC" 2>/dev/null \
   && grep -q -- 'Do not dispatch coder\|not dispatch coder' "$CC" 2>/dev/null; then
  ok "concept-to-code: Gate 4 session boundary is blocking (STOP + no-dispatch guardrail)"
else
  bad "concept-to-code: Gate 4 session boundary missing STOP / no-dispatch guardrail"
fi

# --- Step 7 commit skill integration ---
if grep -q -- 'commit' "$CC" 2>/dev/null \
   && grep -q -- 'Step 7' "$CC" 2>/dev/null \
   && grep -q -- 'step_7_commit' "$CC" 2>/dev/null; then
  ok "concept-to-code: Step 7 commit skill integration present"
else
  bad "concept-to-code: Step 7 commit skill integration missing"
fi
if grep -q -- 'invokable.*commit\|commit.*skills invokable' "$CC" 2>/dev/null; then
  ok "concept-to-code: commit in allowed-skills isolation list"
else
  bad "concept-to-code: commit missing from allowed-skills isolation list"
fi


# --- ADR-0016: Dynamic Workflows Step 5 anchors ---
# Anchor 1: workflow dispatch prompt present in Step 5
grep -qi 'use a workflow to dispatch' "$CC" 2>/dev/null \
  && ok "concept-to-code: ADR-0016 workflow dispatch prompt present in Step 5" \
  || bad "concept-to-code: ADR-0016 workflow dispatch prompt missing from Step 5"

# Anchor 2: step5-report.json schema documented
grep -q 'step5-report.json' "$CC" 2>/dev/null \
  && ok "concept-to-code: ADR-0016 step5-report.json schema documented" \
  || bad "concept-to-code: ADR-0016 step5-report.json schema missing"

# Anchor 3: fallback path present (Agent-tool batch dispatch retained)
grep -q 'Fallback' "$CC" 2>/dev/null \
  && ok "concept-to-code: ADR-0016 fallback Agent-tool path present" \
  || bad "concept-to-code: ADR-0016 fallback path missing"

# Anchor 4: smoke test gate present
grep -q 'hook_verified' "$CC" 2>/dev/null \
  && ok "concept-to-code: ADR-0016 smoke test gate (hook_verified) present" \
  || bad "concept-to-code: ADR-0016 smoke test gate missing"

# --- ADR-0017: chain-type routing at Gate 0 ---
# Anchor 1: chain_path field in manifest-init output
mkdir -p "$TMP/proj-r1"
bash "$INIT" routing-test "Routing Test" "$TMP/proj-r1" >/dev/null 2>&1
MR1="$TMP/proj-r1/docs/manifests/$(date +%Y-%m-%d)-routing-test.manifest.yml"
grep -q '^chain_path: null$' "$MR1" 2>/dev/null \
  && ok "ADR-0017: manifest-init emits chain_path field" \
  || bad "ADR-0017: manifest-init missing chain_path field"

# Anchor 2: gate0.auto_detect_reason in manifest-init output
grep -q 'auto_detect_reason: null' "$MR1" 2>/dev/null \
  && ok "ADR-0017: manifest-init emits gate0.auto_detect_reason field" \
  || bad "ADR-0017: manifest-init missing gate0.auto_detect_reason field"

# Anchor 3: gate0-detect emits repo_file_count and keyword_vote
GD_OUT="$(bash "$SKILL_DIR/scripts/gate0-detect.sh" "$TMP" "Simple test app" 2>/dev/null)"
echo "$GD_OUT" | grep -q '^repo_file_count=' \
  && ok "ADR-0017: gate0-detect emits repo_file_count" \
  || bad "ADR-0017: gate0-detect missing repo_file_count"
echo "$GD_OUT" | grep -q '^keyword_vote=' \
  && ok "ADR-0017: gate0-detect emits keyword_vote" \
  || bad "ADR-0017: gate0-detect missing keyword_vote"

# Anchor 4: Express path states in VALID_STEPS (manifest-validate)
mkdir -p "$TMP/proj-re"
bash "$INIT" routing-e "Express Test" "$TMP/proj-re" >/dev/null 2>&1
MRE="$TMP/proj-re/docs/manifests/$(date +%Y-%m-%d)-routing-e.manifest.yml"
sed -i.bak 's/^current_step: "step_0_init"$/current_step: "step_e1_plan"/' "$MRE"
bash "$VAL" "$MRE" >/dev/null 2>&1 \
  && ok "ADR-0017: manifest-validate accepts step_e1_plan (express state)" \
  || bad "ADR-0017: manifest-validate rejects step_e1_plan"

# Anchor 5: Hybrid path states in VALID_STEPS
mkdir -p "$TMP/proj-rh"
bash "$INIT" routing-h "Hybrid Test" "$TMP/proj-rh" >/dev/null 2>&1
MRH="$TMP/proj-rh/docs/manifests/$(date +%Y-%m-%d)-routing-h.manifest.yml"
sed -i.bak 's/^current_step: "step_0_init"$/current_step: "step_h2_plan"/' "$MRH"
bash "$VAL" "$MRH" >/dev/null 2>&1 \
  && ok "ADR-0017: manifest-validate accepts step_h2_plan (hybrid state)" \
  || bad "ADR-0017: manifest-validate rejects step_h2_plan"

# Anchor 6: Express transitions legal in manifest-transition
mkdir -p "$TMP/proj-rtr"
bash "$INIT" routing-tr "Transition Test" "$TMP/proj-rtr" >/dev/null 2>&1
MRTR="$TMP/proj-rtr/docs/manifests/$(date +%Y-%m-%d)-routing-tr.manifest.yml"
bash "$TRN" "$MRTR" step_e1_plan >/dev/null 2>&1 \
  && ok "ADR-0017: manifest-transition: step_0_init → step_e1_plan legal" \
  || bad "ADR-0017: manifest-transition: step_0_init → step_e1_plan illegal"

# Anchor 7: Hybrid transitions legal
mkdir -p "$TMP/proj-rth"
bash "$INIT" routing-th "Hybrid Trans" "$TMP/proj-rth" >/dev/null 2>&1
MRTH="$TMP/proj-rth/docs/manifests/$(date +%Y-%m-%d)-routing-th.manifest.yml"
bash "$TRN" "$MRTH" step_h1_interview >/dev/null 2>&1 \
  && ok "ADR-0017: manifest-transition: step_0_init → step_h1_interview legal" \
  || bad "ADR-0017: manifest-transition: step_0_init → step_h1_interview illegal"

# Anchor 8: Gate 0 routing question present in SKILL.md
grep -q 'Express.*native plan' "$CC" 2>/dev/null \
  && ok "ADR-0017: SKILL.md Gate 0 routing options present (Express)" \
  || bad "ADR-0017: SKILL.md missing Express routing option"
grep -q 'Hybrid.*SPEC.md' "$CC" 2>/dev/null \
  && ok "ADR-0017: SKILL.md Gate 0 routing options present (Hybrid)" \
  || bad "ADR-0017: SKILL.md missing Hybrid routing option"

# Anchor 9: path prefix fast-path documented in Form A
grep -q 'forced_path' "$CC" 2>/dev/null \
  && ok "ADR-0017: path prefix fast-path (forced_path) documented in SKILL.md" \
  || bad "ADR-0017: SKILL.md missing path prefix fast-path"
grep -q 'Gate 0 skipped' "$CC" 2>/dev/null \
  && ok "ADR-0017: Gate 0 skip on explicit path prefix documented" \
  || bad "ADR-0017: SKILL.md missing Gate 0 skip note"

# Anchor 10: superpowers exception in Express E1
grep -q 'using-superpowers.*Express\|Express.*using-superpowers\|superpowers.*step E1\|step E1.*superpowers' "$CC" 2>/dev/null \
  && ok "ADR-0017: superpowers allowed in Express step E1" \
  || bad "ADR-0017: SKILL.md missing superpowers exception for Express E1"

# --- Gate 2 transition wiring ---
# Gate 2b approve/skip must transition to step_3_project_memory
grep -qF 'step_3_project_memory' "$CC" 2>/dev/null \
  && ok "Gate 2: step_3_project_memory transition present (Gate 2b → Step 3)" \
  || bad "Gate 2: step_3_project_memory transition missing — Gate 2b does not advance manifest"

# Gate 2a no-TOFU path must also transition
grep -qE 'NONE.*transition.*step_3|step_3.*directly' "$CC" 2>/dev/null \
  && ok "Gate 2: no-TOFU (NONE) path transitions to step_3_project_memory" \
  || bad "Gate 2: no-TOFU (NONE) path missing step_3 transition"

# --- Gate 4 transition wiring ---
# Gate 4 confirmed must transition step_4_session_boundary → ready_for_implementation
grep -qE 'step_4_session_boundary.*ready_for_implementation|Transition.*step_4_session_boundary' "$CC" 2>/dev/null \
  && ok "Gate 4: step_4_session_boundary → ready_for_implementation transition present" \
  || bad "Gate 4: confirmed handler missing step_4 → ready_for_implementation transition"

# --- Gate 3 transition wiring ---
# Step 3 must transition to gate_3_project_memory_review before showing Gate 3
grep -qF 'gate_3_project_memory_review' "$CC" 2>/dev/null \
  && ok "Gate 3: gate_3_project_memory_review transition present in SKILL.md" \
  || bad "Gate 3: gate_3_project_memory_review transition missing — Step 3 skips gate state"

# Approve handler must transition to step_4_session_boundary
grep -qE 'Gate 3 approve.*step_4_session_boundary|step_4_session_boundary.*Gate 3 approve' "$CC" 2>/dev/null \
  && ok "Gate 3: approve handler transitions to step_4_session_boundary" \
  || bad "Gate 3: approve handler missing step_4_session_boundary transition"

# --- ADR-0018: Gate 5.1 deep-refactor linkage ---
# Anchor: Gate 5.1 block present
grep -q 'Gate 5\.1' "$CC" 2>/dev/null \
  && ok "ADR-0018: Gate 5.1 deep-refactor block present in SKILL.md" \
  || bad "ADR-0018: Gate 5.1 block missing from SKILL.md"

# Anchor: deep-refactor in allowed-skills list
grep -q 'deep-refactor' "$CC" 2>/dev/null \
  && ok "ADR-0018: deep-refactor in allowed-skills list" \
  || bad "ADR-0018: deep-refactor missing from allowed-skills list"

# Anchor: Step 6 workflow completion routes to Gate 5.05 (ui-layout-audit) then Gate 5.1
grep -q 'Evaluate Gate 5\.05' "$CC" 2>/dev/null \
  && ok "ADR-0018: Step 6 completion routes to Gate 5.05 (not bypassing review gates)" \
  || bad "ADR-0018: Step 6 completion bypasses Gate 5.05 — broken link"

# Anchor: Gate 5.1 Abort chain option present
grep -q 'Abort chain' "$CC" 2>/dev/null \
  && ok "ADR-0018: Gate 5.1 Abort chain option present" \
  || bad "ADR-0018: Gate 5.1 Abort chain option missing"

# Anchor: Gate 5.1 continuation documented. Target renamed 5.5 -> 5.6 by ADR-0040 (Gate 5.5
# was the humanize gate; only its state transition survives, as the action-free Gate 5.6).
grep -qE 'Gate 5\.1.*Gate 5\.6|proceed to Gate 5\.6' "$CC" 2>/dev/null \
  && ok "ADR-0018: Gate 5.1 continuation to Gate 5.6 documented" \
  || bad "ADR-0018: Gate 5.1 → Gate 5.6 link missing"

# === Change 1 (Bug 1) — gate0-detect SPEC.md topic-slug match ===

# A1: matching slug → mode=brownfield + spec_topic_match=true + spec_adr_exist=true
DA1="$TMP/projA1"
mkdir -p "$DA1/docs/architecture"
cat > "$DA1/SPEC.md" <<'EOF'
# SPEC

**Topic slug:** my-cool-app

Some prose here.
EOF
touch "$DA1/docs/architecture/ADR-0001-x.md"
OUTA1="$(bash "$GATE0" "$DA1" "My Cool App" "my-cool-app" 2>/dev/null)"
echo "$OUTA1" | grep -q 'spec_topic_match=true' \
  && echo "$OUTA1" | grep -q 'mode=brownfield' \
  && echo "$OUTA1" | grep -q 'spec_adr_exist=true' \
  && ok "gate0-detect: matching slug -> spec_topic_match=true, mode=brownfield" \
  || bad "gate0-detect: matching slug expected true/brownfield"

# A1b: label/value case-insensitive + whitespace-trimmed match
DA1B="$TMP/projA1b"
mkdir -p "$DA1B"
cat > "$DA1B/SPEC.md" <<'EOF'
**Topic Slug:**  My-Cool-App
EOF
OUTA1B="$(bash "$GATE0" "$DA1B" "" "my-cool-app" 2>/dev/null)"
echo "$OUTA1B" | grep -q 'spec_topic_match=true' \
  && ok "gate0-detect: slug match is case-insensitive + trimmed" \
  || bad "gate0-detect: case/whitespace normalization failed"

# A2: mismatched slug → greenfield + spec_adr_exist=false + spec_topic_match=false
DA2="$TMP/projA2"
mkdir -p "$DA2/docs/architecture"
cat > "$DA2/SPEC.md" <<'EOF'
**Topic slug:** some-other-chain
EOF
touch "$DA2/docs/architecture/ADR-0001-x.md"
OUTA2="$(bash "$GATE0" "$DA2" "My Cool App" "my-cool-app" 2>/dev/null)"
echo "$OUTA2" | grep -q 'spec_topic_match=false' \
  && echo "$OUTA2" | grep -q 'mode=greenfield' \
  && echo "$OUTA2" | grep -q 'spec_adr_exist=false' \
  && ok "gate0-detect: mismatched slug -> spec_topic_match=false, greenfield, spec_adr_exist=false" \
  || bad "gate0-detect: mismatched slug should disown SPEC"

# A3: marker absent (legacy SPEC) → spec_topic_match=unknown + mode=brownfield
DA3="$TMP/projA3"
mkdir -p "$DA3"
cat > "$DA3/SPEC.md" <<'EOF'
# Legacy SPEC with no slug marker

Just prose here.
EOF
OUTA3="$(bash "$GATE0" "$DA3" "My Cool App" "my-cool-app" 2>/dev/null)"
echo "$OUTA3" | grep -q 'spec_topic_match=unknown' \
  && echo "$OUTA3" | grep -q 'mode=brownfield' \
  && ok "gate0-detect: legacy SPEC (no marker) -> unknown + brownfield" \
  || bad "gate0-detect: missing marker should be unknown/brownfield"

# A4 (backward-compat): 2-arg call emits NO new fields
DA4="$TMP/projA4"
mkdir -p "$DA4"
cat > "$DA4/SPEC.md" <<'EOF'
**Topic slug:** my-cool-app
EOF
OUTA4="$(bash "$GATE0" "$DA4" "My Cool App" 2>/dev/null)"
if echo "$OUTA4" | grep -q 'spec_topic_match='; then
  bad "gate0-detect: 2-arg call leaked spec_topic_match (compat break)"
else
  echo "$OUTA4" | grep -q 'mode=brownfield' \
    && ok "gate0-detect: 2-arg call omits new fields (backward compat)" \
    || bad "gate0-detect: 2-arg call regression on mode"
fi

# === Feature 4 — skill_exists flag ===

# B1: arg3 present → skill_exists emitted; non-existent slug → false
DB1="$TMP/projB1"
mkdir -p "$DB1"
NOSLUG="c2c-test-nonexistent-skill-zzz999"
OUTB1="$(bash "$GATE0" "$DB1" "Some Title" "$NOSLUG" 2>/dev/null)"
echo "$OUTB1" | grep -q "skill_exists=false" \
  && ok "gate0-detect: arg3 given -> skill_exists=false for unknown slug" \
  || bad "gate0-detect: expected skill_exists=false for non-existent slug"

# B2 (backward-compat): 2-arg call does NOT emit skill_exists
OUTB2="$(bash "$GATE0" "$DB1" "Some Title" 2>/dev/null)"
if echo "$OUTB2" | grep -q 'skill_exists='; then
  bad "gate0-detect: 2-arg call leaked skill_exists (compat break)"
else
  ok "gate0-detect: 2-arg call omits skill_exists (backward compat)"
fi

# === Change 2 (Bug 2) — detect-macos.sh ===
MACDET="$SKILL_DIR/scripts/detect-macos.sh"

# C1: Swift/SwiftUI ONLY in a markdown table + inline backticks → NOT_MACOS
CFG1="$TMP/spec-c1.md"
cat > "$CFG1" <<'EOF'
# Routing SPEC

This service routes files to language handlers based on extension.

| Pattern                        | Handler   |
|--------------------------------|-----------|
| `*.swift`, `SwiftUI`, `Swift`  | swift.md  |
| `*.py`                         | python.md |

Inline note: the `SwiftUI` token is a routing key only.
EOF
OUTC1="$(bash "$MACDET" "$CFG1" 2>/dev/null)"
[ "$OUTC1" = "NOT_MACOS" ] \
  && ok "detect-macos: Swift/SwiftUI in table+backticks only -> NOT_MACOS" \
  || bad "detect-macos: false-positive on table/backtick Swift mentions"

# C1b: keyword inside a fenced code block → NOT_MACOS
CFG1B="$TMP/spec-c1b.md"
cat > "$CFG1B" <<'EOF'
# Config SPEC

Example config:

```swiftui
target: macOS menu bar app
```

This project is a CLI tool, no GUI.
EOF
OUTC1B="$(bash "$MACDET" "$CFG1B" 2>/dev/null)"
[ "$OUTC1B" = "NOT_MACOS" ] \
  && ok "detect-macos: keywords inside fenced block -> NOT_MACOS" \
  || bad "detect-macos: false-positive on fenced-code keywords"

# C2: genuine prose macOS target → MACOS_DETECTED
CFG2="$TMP/spec-c2.md"
cat > "$CFG2" <<'EOF'
# App SPEC

We are building a macOS menu bar app for tracking time.
It uses SwiftUI for the popover UI.
EOF
OUTC2="$(bash "$MACDET" "$CFG2" 2>/dev/null)"
[ "$OUTC2" = "MACOS_DETECTED" ] \
  && ok "detect-macos: prose 'macOS menu bar app' -> MACOS_DETECTED" \
  || bad "detect-macos: missed genuine macOS prose"

# C3: missing file → NOT_MACOS, exit 0
OUTC3="$(bash "$MACDET" "$TMP/does-not-exist.md" 2>/dev/null)"
RCC3="$?"
[ "$OUTC3" = "NOT_MACOS" ] && [ "$RCC3" = "0" ] \
  && ok "detect-macos: missing file -> NOT_MACOS exit 0" \
  || bad "detect-macos: missing file should be NOT_MACOS exit 0"

# === SKILL.md content assertions (Changes 2, 3, 4, 5) ===

# Bug 2: detect-macos.sh referenced at macOS detection site (standard path)
grep -q 'detect-macos.sh' "$CC" 2>/dev/null \
  && ok "SKILL.md: detect-macos.sh referenced at macOS detection site" \
  || bad "SKILL.md: detect-macos.sh not found — macOS detection still uses inline grep"

# Bug 1 + Feature 4: gate0-detect called with 3 args (slug passed)
grep -qE 'gate0-detect\.sh.*topic-slug|gate0-detect\.sh.*<topic-slug>' "$CC" 2>/dev/null \
  && ok "SKILL.md: gate0-detect.sh call passes topic-slug (3rd arg)" \
  || bad "SKILL.md: gate0-detect.sh call missing 3rd arg (slug)"

# Bug 3: Step 3 brownfield branch uses direct append (no generator dispatch)
grep -q 'orchestrator appends directly' "$CC" 2>/dev/null \
  && ok "SKILL.md: Step 3 brownfield branch -> orchestrator appends directly" \
  || bad "SKILL.md: Step 3 brownfield branch missing 'orchestrator appends directly'"

# Feature 5: Gate 3 line-count guard present
grep -q 'claude-md-slim' "$CC" 2>/dev/null \
  && ok "SKILL.md: Gate 3 line-count guard references claude-md-slim" \
  || bad "SKILL.md: Gate 3 line-count guard missing"

# Gate 4 autopilot-now option: boundary offers in-session autopilot
grep -q 'Implement now (autopilot' "$CC" 2>/dev/null \
  && ok "SKILL.md: Gate 4 offers 'Implement now (autopilot)' option" \
  || bad "SKILL.md: Gate 4 'Implement now (autopilot)' option missing"

# Smoke-test gate autopilot default: prevents unattended stall on hook_verified prompt
grep -q 'Step 5: autopilot — workflow smoke test skipped' "$CC" 2>/dev/null \
  && ok "SKILL.md: smoke-test gate has an autopilot default (no stall)" \
  || bad "SKILL.md: smoke-test gate autopilot default missing"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
