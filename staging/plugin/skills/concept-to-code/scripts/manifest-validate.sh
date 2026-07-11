#!/usr/bin/env bash
# concept-to-code: manifest-validate.sh — bash 3.2-clean
# Validates a manifest YAML file against schema invariants.
# Usage: manifest-validate.sh <manifest-path>
# Exit: 0 valid | 1 invalid (errors to stderr) | 2 file not found
set -u

if [ "$#" != "1" ]; then
  echo "usage: manifest-validate.sh <manifest-path>" >&2
  exit 1
fi

MANIFEST="$1"
ERRORS=0

# Invariant 0: file must exist
if [ ! -f "$MANIFEST" ]; then
  echo "manifest-validate: file not found: $MANIFEST" >&2
  exit 2
fi

# Helper: fail with message
fail() {
  echo "manifest-validate: $1" >&2
  ERRORS=$((ERRORS+1))
}

# Invariant 1: manifest_schema_version must be "1.0", "1.1", "1.2", or "1.3"
if ! grep -Eq '^manifest_schema_version: "(1\.0|1\.1|1\.2|1\.3)"$' "$MANIFEST"; then
  fail "manifest_schema_version missing or not 1.0/1.1/1.2/1.3"
fi

# Invariant 2: topic must be non-empty and match slug pattern
topic_val="$(grep '^topic:' "$MANIFEST" | sed 's/^topic: *//;s/"//g' | head -1)"
if [ -z "$topic_val" ]; then
  fail "topic field missing or empty"
elif ! echo "$topic_val" | grep -Eq '^[a-z0-9-]{1,40}$'; then
  fail "topic '$topic_val' does not match ^[a-z0-9-]{1,40}$"
fi

# Invariant 3: topic_full_title must be present
if ! grep -q '^topic_full_title:' "$MANIFEST"; then
  fail "topic_full_title field missing"
fi

# Invariant 4: project_root must be a directory that exists
project_root_val="$(grep '^project_root:' "$MANIFEST" | sed 's/^project_root: *//;s/"//g' | head -1)"
if [ -z "$project_root_val" ]; then
  fail "project_root field missing or empty"
elif [ ! -d "$project_root_val" ]; then
  fail "project_root '$project_root_val' is not an existing directory"
fi

# Invariant 5: current_step must be in valid enum
current_step_val="$(grep '^current_step:' "$MANIFEST" | sed 's/^current_step: *//;s/"//g' | head -1)"

VALID_STEPS="$(mktemp)"
trap 'rm -f "${VALID_STEPS:-}"' EXIT
echo "step_0_init" > "$VALID_STEPS"
echo "step_1_interview" >> "$VALID_STEPS"
echo "gate_1_spec_review" >> "$VALID_STEPS"
echo "step_2_architecture" >> "$VALID_STEPS"
echo "gate_2_architecture_review" >> "$VALID_STEPS"
echo "step_3_project_memory" >> "$VALID_STEPS"
echo "gate_3_project_memory_review" >> "$VALID_STEPS"
echo "step_4_session_boundary" >> "$VALID_STEPS"
echo "ready_for_implementation" >> "$VALID_STEPS"
echo "step_5_implementation" >> "$VALID_STEPS"
echo "step_6_review" >> "$VALID_STEPS"
echo "gate_1b_brainstorm_decision" >> "$VALID_STEPS"
echo "gate_1c_macos_ux_decision" >> "$VALID_STEPS"
echo "gate_5_review_decision" >> "$VALID_STEPS"
echo "step_7_commit" >> "$VALID_STEPS"
echo "gate_0d_scaffolding" >> "$VALID_STEPS"
echo "completed" >> "$VALID_STEPS"
echo "failed" >> "$VALID_STEPS"
echo "aborted" >> "$VALID_STEPS"
# Express path states (ADR-0017)
echo "step_e1_plan" >> "$VALID_STEPS"
echo "step_e2_execute" >> "$VALID_STEPS"
echo "gate_e3_verify" >> "$VALID_STEPS"
echo "step_e4_commit" >> "$VALID_STEPS"
# Hybrid path states (ADR-0017)
echo "step_h1_interview" >> "$VALID_STEPS"
echo "gate_h1_spec_review" >> "$VALID_STEPS"
echo "gate_h1b_brainstorm" >> "$VALID_STEPS"
echo "gate_h1c_macos_ux" >> "$VALID_STEPS"
echo "step_h2_plan" >> "$VALID_STEPS"
echo "step_h3_execute" >> "$VALID_STEPS"
echo "gate_h3_verify" >> "$VALID_STEPS"
echo "step_h4_review" >> "$VALID_STEPS"
echo "step_h5_commit" >> "$VALID_STEPS"

if [ -z "$current_step_val" ]; then
  fail "current_step field missing or empty"
elif ! grep -Fxq "$current_step_val" "$VALID_STEPS"; then
  fail "current_step '$current_step_val' is not a valid state"
fi
rm -f "$VALID_STEPS"

# Invariant 6: status must be in valid enum
status_val="$(grep '^status:' "$MANIFEST" | sed 's/^status: *//;s/"//g' | head -1)"
case "$status_val" in
  in_progress|failed|completed|aborted) ;;
  *) fail "status '$status_val' is not valid (must be: in_progress|failed|completed|aborted)" ;;
esac

# Invariant 7: if status=completed, artifacts spec/adr/plan must be non-null (absolute paths)
# -- conditional on chain_path (ADR-0017/ADR-0027): Express produces none of the three (no
# sub-agents, no SPEC/ARCH/ADR); Hybrid produces spec only (plan mode replaces the architect
# step, no ADR/plan); Standard/legacy (chain_path=standard, null, or absent) keeps the
# original unconditional three-way check, byte-identical wording.
chain_path_val="$(grep '^chain_path:' "$MANIFEST" | sed 's/^chain_path: *//;s/"//g' | head -1)"
if [ "$status_val" = "completed" ]; then
  case "$chain_path_val" in
    express)
      : # no artifact files expected for the express path; invariant 7 does not apply
      ;;
    hybrid)
      if ! grep -Eq '^  spec: "/[^"]+"$' "$MANIFEST"; then
        fail "status=completed (chain_path=hybrid) but artifacts.spec is null or not a quoted absolute path"
      fi
      ;;
    *)
      if ! grep -Eq '^  spec: "/[^"]+"$' "$MANIFEST"; then
        fail "status=completed but artifacts.spec is null or not a quoted absolute path"
      fi
      if ! grep -Eq '^  adr: "/[^"]+"$' "$MANIFEST"; then
        fail "status=completed but artifacts.adr is null or not a quoted absolute path"
      fi
      if ! grep -Eq '^  plan: "/[^"]+"$' "$MANIFEST"; then
        fail "status=completed but artifacts.plan is null or not a quoted absolute path"
      fi
      ;;
  esac
fi

# Invariant 8: if status=failed, failure.failed_step must be non-null
if [ "$status_val" = "failed" ]; then
  failed_step_val="$(grep '^  failed_step:' "$MANIFEST" | sed 's/^  failed_step: *//;s/"//g' | head -1)"
  if [ -z "$failed_step_val" ] || [ "$failed_step_val" = "null" ]; then
    fail "status=failed but failure.failed_step is null or missing"
  fi
fi

# Invariant 9: hitl_gates minimum count — conditional on chain_path (ADR-0017)
gate_count="$(grep -c '^  - gate:' "$MANIFEST" 2>/dev/null)"
if [ -z "$gate_count" ]; then
  gate_count=0
fi
chain_path_val="$(grep '^chain_path:' "$MANIFEST" | sed 's/^chain_path: *//;s/"//g' | head -1)"
min_gates=4
case "$chain_path_val" in
  express) min_gates=2 ;;
  hybrid)  min_gates=3 ;;
  *)       min_gates=4 ;;
esac
if [ "$gate_count" -lt "$min_gates" ]; then
  fail "hitl_gates must have at least $min_gates entries for chain_path='$chain_path_val' (found $gate_count)"
fi

# Invariant 10 (conditional): if mode field present, value must be greenfield or brownfield
if grep -q '^mode:' "$MANIFEST"; then
  mode_val="$(grep '^mode:' "$MANIFEST" | sed 's/^mode: *//;s/"//g' | head -1)"
  case "$mode_val" in
    greenfield|brownfield) ;;
    *) fail "mode '$mode_val' invalid (greenfield|brownfield)" ;;
  esac
fi

# Invariant 11 (conditional, schema 1.2): if anonymize field present, must be true or false
# Absent = valid (retrocompat 1.0/1.1). NOT mandatory.
if grep -q '^anonymize:' "$MANIFEST"; then
  if ! grep -Eq '^anonymize: (true|false)$' "$MANIFEST"; then
    fail "anonymize field present but value is not 'true' or 'false'"
  fi
fi

# Invariant 12 (conditional, schema 1.2): if humanize field present, must be true or false
# Absent = valid (retrocompat 1.0/1.1/1.2). NOT mandatory.
if grep -q '^humanize:' "$MANIFEST"; then
  if ! grep -Eq '^humanize: (true|false)$' "$MANIFEST"; then
    fail "humanize field present but value is not 'true' or 'false'"
  fi
fi

# Invariant 13 (conditional, schema 1.3): if chain_path present and non-null, must be valid enum
# Absent or null = valid (retrocompat 1.0/1.1/1.2 and new 1.3 manifests before Gate 0 fires).
if grep -q '^chain_path:' "$MANIFEST"; then
  cp_raw="$(grep '^chain_path:' "$MANIFEST" | sed 's/^chain_path: *//;s/"//g' | head -1)"
  case "$cp_raw" in
    express|hybrid|standard|null) ;;
    *) fail "chain_path '$cp_raw' invalid (must be: express|hybrid|standard|null)" ;;
  esac
fi

if [ "$ERRORS" != "0" ]; then
  exit 1
fi

exit 0
