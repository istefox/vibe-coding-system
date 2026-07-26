#!/usr/bin/env bash
# concept-to-code: manifest-transition.sh — bash 3.2-clean
# Performs a legal state machine transition on a manifest.
# Usage: manifest-transition.sh <manifest-path> <new-current-step> [<new-status>]
# Exit: 0 ok | 1 transition illegal | 2 manifest invalid pre-transition | 3 write error
set -u

if [ "$#" -lt "2" ] || [ "$#" -gt "3" ]; then
  echo "usage: manifest-transition.sh <manifest-path> <new-current-step> [<new-status>]" >&2
  exit 1
fi

manifest="$1"
new_step="$2"
new_status="${3:-}"

# Validate new_status if provided — guard against LLM passing a step-name as the 3rd arg
if [ -n "$new_status" ]; then
  case "$new_status" in
    in_progress|failed|completed|aborted) ;;
    *)
      echo "manifest-transition: invalid status '$new_status' (must be: in_progress|failed|completed|aborted)" >&2
      exit 1
      ;;
  esac
fi

# Locate scripts dir (sibling to this script)
SCRIPT_DIR="$(dirname "$0")"
VALIDATE="$SCRIPT_DIR/manifest-validate.sh"

# Pre-flight: validate manifest
if ! bash "$VALIDATE" "$manifest" 2>/dev/null; then
  echo "manifest-transition: manifest validation failed pre-transition: $manifest" >&2
  exit 2
fi

# Read current_step from manifest
current_step="$(grep '^current_step:' "$manifest" | sed 's/^current_step: *//;s/"//g' | head -1)"

# Idempotent: same → same is a no-op (chain retries should not error)
if [ "$current_step" = "$new_step" ]; then
  exit 0
fi

# Allow any state → failed or → aborted (unconditionally)
if [ "$new_step" = "failed" ] || [ "$new_step" = "aborted" ]; then
  : # always legal
else
  # Build legal transition pairs into temp file (spec §3.3, 49 transitions)
  PAIRS="$(mktemp)"
  echo "step_0_init,step_1_interview" > "$PAIRS"
  echo "step_0_init,gate_0d_scaffolding" >> "$PAIRS"
  echo "gate_0d_scaffolding,step_1_interview" >> "$PAIRS"
  echo "gate_0d_scaffolding,step_e1_plan" >> "$PAIRS"
  echo "gate_0d_scaffolding,step_h1_interview" >> "$PAIRS"
  echo "step_1_interview,gate_1_spec_review" >> "$PAIRS"
  echo "gate_1_spec_review,step_2_architecture" >> "$PAIRS"
  echo "gate_1_spec_review,step_1_interview" >> "$PAIRS"
  echo "gate_1_spec_review,gate_1b_brainstorm_decision" >> "$PAIRS"
  echo "gate_1b_brainstorm_decision,step_2_architecture" >> "$PAIRS"
  echo "gate_1b_brainstorm_decision,gate_1c_macos_ux_decision" >> "$PAIRS"
  echo "gate_1c_macos_ux_decision,step_2_architecture" >> "$PAIRS"
  echo "step_2_architecture,gate_2_architecture_review" >> "$PAIRS"
  echo "gate_2_architecture_review,step_3_project_memory" >> "$PAIRS"
  echo "gate_2_architecture_review,step_2_architecture" >> "$PAIRS"
  echo "step_3_project_memory,gate_3_project_memory_review" >> "$PAIRS"
  echo "gate_3_project_memory_review,step_4_session_boundary" >> "$PAIRS"
  echo "gate_3_project_memory_review,step_3_project_memory" >> "$PAIRS"
  echo "step_4_session_boundary,ready_for_implementation" >> "$PAIRS"
  echo "ready_for_implementation,step_5_implementation" >> "$PAIRS"
  echo "step_5_implementation,step_6_review" >> "$PAIRS"
  echo "step_6_review,gate_5_review_decision" >> "$PAIRS"
  echo "step_6_review,step_7_commit" >> "$PAIRS"
  echo "gate_5_review_decision,step_7_commit" >> "$PAIRS"
  echo "gate_5_review_decision,completed" >> "$PAIRS"
  echo "step_7_commit,completed" >> "$PAIRS"
  echo "step_5_implementation,gate_5_review_decision" >> "$PAIRS"
  echo "step_6_review,completed" >> "$PAIRS"
  # Tracer-bullet probe, Step 4.5 (ADR-0057). Inline sub-gate at ready_for_implementation — same
  # shape as Gate 2b (TOFU) and Gate 5.05/5.06, which also have no dedicated current_step state.
  # green and "red -> continue anyway" reuse ready_for_implementation,step_5_implementation above
  # unchanged; hand-code reuses the unconditional any-state-to-aborted wildcard below. This is the
  # ONE new pair the feature actually needs, for amber and "red -> reduce scope" alike:
  echo "ready_for_implementation,gate_2_architecture_review" >> "$PAIRS"
  # Express path transitions (ADR-0017)
  echo "step_0_init,step_e1_plan" >> "$PAIRS"
  echo "step_e1_plan,step_e2_execute" >> "$PAIRS"
  echo "step_e2_execute,gate_e3_verify" >> "$PAIRS"
  echo "gate_e3_verify,step_e4_commit" >> "$PAIRS"
  echo "step_e4_commit,completed" >> "$PAIRS"
  echo "gate_e3_verify,completed" >> "$PAIRS"
  # Hybrid path transitions (ADR-0017)
  echo "step_0_init,step_h1_interview" >> "$PAIRS"
  echo "step_h1_interview,gate_h1_spec_review" >> "$PAIRS"
  echo "gate_h1_spec_review,step_h2_plan" >> "$PAIRS"
  echo "gate_h1_spec_review,gate_h1b_brainstorm" >> "$PAIRS"
  echo "gate_h1_spec_review,step_h1_interview" >> "$PAIRS"
  echo "gate_h1b_brainstorm,step_h2_plan" >> "$PAIRS"
  echo "gate_h1b_brainstorm,gate_h1c_macos_ux" >> "$PAIRS"
  echo "gate_h1c_macos_ux,step_h2_plan" >> "$PAIRS"
  echo "step_h2_plan,step_h3_execute" >> "$PAIRS"
  echo "step_h3_execute,gate_h3_verify" >> "$PAIRS"
  echo "gate_h3_verify,step_h4_review" >> "$PAIRS"
  echo "gate_h3_verify,step_h5_commit" >> "$PAIRS"
  echo "step_h4_review,step_h5_commit" >> "$PAIRS"
  echo "step_h5_commit,completed" >> "$PAIRS"

  if ! grep -Fxq "$current_step,$new_step" "$PAIRS"; then
    rm -f "$PAIRS"
    echo "manifest-transition: illegal transition $current_step → $new_step" >&2
    # Suggest the intermediate step if one exists in a common two-hop path
    case "$current_step,$new_step" in
      step_h3_execute,step_h5_commit) echo "  hint: required path is step_h3_execute → gate_h3_verify → step_h5_commit (two calls)" >&2 ;;
      step_e2_execute,step_e4_commit)  echo "  hint: required path is step_e2_execute → gate_e3_verify → step_e4_commit (two calls)" >&2 ;;
      step_5_implementation,step_7_commit) echo "  hint: required path is step_5_implementation → step_6_review → step_7_commit (two calls)" >&2 ;;
    esac
    exit 1
  fi
  rm -f "$PAIRS"
fi

# Compute fresh ISO 8601 UTC timestamp
now="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"

# Atomic write via mktemp + mv
TMP_OUT="$(mktemp)"

# Process manifest line-by-line, replacing target fields
while IFS= read -r line; do
  case "$line" in
    current_step:*)
      echo "current_step: \"$new_step\""
      ;;
    last_updated_at:*)
      echo "last_updated_at: \"$now\""
      ;;
    status:*)
      if [ -n "$new_status" ]; then
        echo "status: \"$new_status\""
      else
        echo "$line"
      fi
      ;;
    *)
      echo "$line"
      ;;
  esac
done < "$manifest" > "$TMP_OUT"

if mv "$TMP_OUT" "$manifest"; then
  exit 0
else
  echo "manifest-transition: failed to write manifest: $manifest" >&2
  rm -f "$TMP_OUT"
  exit 3
fi
