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

# Invariant 4: project_root must be present, and must be an existing directory UNLESS the chain
# has reached a terminal state (issue #197, ADR-0078).
#
# WHY THE CONDITION. The field records where a chain ran. On a terminal manifest that is a
# HISTORICAL FACT, not a live precondition, and requiring the directory to exist asserts that every
# manifest is validated on the machine that produced it. Five of this repository's own manifests
# carry a path from a different machine and failed this invariant for that reason alone.
#
# TERMINAL MEANS ABSORBING, and that was verified against the state machine rather than assumed:
# no transition pair in manifest-transition.sh has completed, failed or aborted as its SOURCE, so a
# manifest in one of them can never move again. Wider than ADR-0075's `completed`-only tolerance
# for hook_verified, and for a stated reason — that rule's argument ("a finished chain cannot
# affect a future run") covers all three absorbing states, and narrowing to one would be following
# its letter past its reason.
#
# IT CANNOT WEAKEN A LIVE PATH. Every consumer reads a manifest that is in flight:
# manifest-transition.sh validates pre-transition and a terminal manifest never transitions;
# autopilot-build check 2 requires current_step = ready_for_implementation immediately after
# validating. On those, the existence check is unchanged.
#
# PRESENCE is still required in every state — a missing project_root is corruption at any point.
project_root_val="$(grep '^project_root:' "$MANIFEST" | sed 's/^project_root: *//;s/"//g' | head -1)"
project_root_step="$(grep '^current_step:' "$MANIFEST" | sed 's/^current_step: *//;s/"//g' | head -1)"
if [ -z "$project_root_val" ]; then
  fail "project_root field missing or empty"
elif [ ! -d "$project_root_val" ]; then
  case "$project_root_step" in
    completed|failed|aborted)
      # Terminal: the path is a record of where this chain ran, and nothing will run again.
      # Silent rather than a note — this script's only output channel is fail(), and its main
      # caller (manifest-transition.sh) discards stderr, so a note would reach nobody.
      : ;;
    *)
      fail "project_root '$project_root_val' is not an existing directory" ;;
  esac
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
# The bare `min_gates=4` that used to sit here was DEAD: the case below has a `*)` catch-all, so it
# was overwritten on every path. Found by planting a raised minimum on it and watching nothing
# change (issue #238) — which is exactly how a future edit meaning to raise it would fail, silently
# and while looking correct. Raise the `*)` arm, not a default above it.
#
# The minimum stays 4 with five slots written since ADR-0099: it is a MINIMUM, and raising it to 5
# would fail all 41 historical manifests for a change they predate (ADR-0078's rule, applied to a
# count instead of a path). That the template writes five is asserted against the template itself,
# in hitl-gate-audit-trail.test.sh, not against every manifest ever produced.
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

# Invariant 14 (conditional, ADR-0039 D8): if step5_review_mode present, must be none or checkpoint
# Absent = valid. Every manifest written before ADR-0039 lacks the field, and none of them needs
# a migration: absent and 'none' mean the same thing.
if grep -q '^step5_review_mode:' "$MANIFEST"; then
  if ! grep -Eq '^step5_review_mode: (none|checkpoint)$' "$MANIFEST"; then
    fail "step5_review_mode present but value is not 'none' or 'checkpoint'"
  fi
fi

# Invariant 15 (conditional, ADR-0050): if recovery_baseline_sha present, must be null or a
# quoted hex sha string. Absent = valid (retrocompat with every pre-ADR-0050 manifest). Written
# once at Step 5 pre-flight and never rewritten — this checks shape only, not the "once" rule,
# which is an instruction to the model, not something a static validator can observe.
if grep -q '^recovery_baseline_sha:' "$MANIFEST"; then
  rbs_val="$(grep '^recovery_baseline_sha:' "$MANIFEST" | sed 's/^recovery_baseline_sha: *//' | head -1)"
  case "$rbs_val" in
    null) ;;
    \"*\")
      rbs_inner="$(printf '%s' "$rbs_val" | sed 's/^"//;s/"$//')"
      if ! printf '%s' "$rbs_inner" | grep -Eq '^[0-9a-f]{7,64}$'; then
        fail "recovery_baseline_sha value '$rbs_inner' is not a valid hex sha"
      fi
      ;;
    *) fail "recovery_baseline_sha '$rbs_val' is not null or a quoted hex sha" ;;
  esac
fi

# Invariant 16 (conditional, ADR-0055): if risk present, must be low, high, or null.
# Absent = valid (retrocompat with every pre-ADR-0055 manifest). Absent/null resolves to the
# STRICT profile at the resolution site (concept-to-code/SKILL.md § Proportional audit depth),
# never to "no profile applies" — this feature removes constraints rather than adding one, so
# inert-when-absent would silently downgrade every existing manifest (ADR-0055 §D2).
if grep -q '^risk:' "$MANIFEST"; then
  risk_val="$(grep '^risk:' "$MANIFEST" | sed 's/^risk: *//;s/"//g' | head -1)"
  case "$risk_val" in
    low|high|null) ;;
    *) fail "risk '$risk_val' is not valid (must be: low|high|null)" ;;
  esac
fi

# Invariant 17 (conditional, ADR-0055): if task_type present, must be one of the six enum
# values, or null. Absent = valid, same retrocompat / default-strict note as Invariant 16.
if grep -q '^task_type:' "$MANIFEST"; then
  task_type_val="$(grep '^task_type:' "$MANIFEST" | sed 's/^task_type: *//;s/"//g' | head -1)"
  case "$task_type_val" in
    boilerplate|glue|novel-algorithm|regulated|legacy-integration|perf-critical|null) ;;
    *) fail "task_type '$task_type_val' is not valid (must be: boilerplate|glue|novel-algorithm|regulated|legacy-integration|perf-critical|null)" ;;
  esac
fi

# Invariant 18 (conditional, ADR-0057): if tracer_bullet_mode present, must be skip or probe.
# Absent = valid (retrocompat with every pre-ADR-0057 manifest) and means the same thing as 'skip'
# — this feature ADDS a step, so absent/skip is the inert, pre-feature-equivalent default.
if grep -q '^tracer_bullet_mode:' "$MANIFEST"; then
  if ! grep -Eq '^tracer_bullet_mode: (skip|probe)$' "$MANIFEST"; then
    fail "tracer_bullet_mode present but value is not 'skip' or 'probe'"
  fi
fi

# Invariant 19 (conditional, ADR-0057): if tracer_bullet_verdict present, must be null or one of
# the three computed verdicts. Absent = valid.
if grep -q '^tracer_bullet_verdict:' "$MANIFEST"; then
  tbv_val="$(grep '^tracer_bullet_verdict:' "$MANIFEST" | sed 's/^tracer_bullet_verdict: *//;s/"//g' | head -1)"
  case "$tbv_val" in
    null|green|amber|red) ;;
    *) fail "tracer_bullet_verdict '$tbv_val' is not valid (must be: null|green|amber|red)" ;;
  esac
fi

# Invariant 20 (conditional, ADR-0057): if tracer_bullet_red_decision present, must be null or one
# of the three named options from Gate 4.5 (continue anyway / reduce scope / hand-code). Absent =
# valid.
if grep -q '^tracer_bullet_red_decision:' "$MANIFEST"; then
  tbrd_val="$(grep '^tracer_bullet_red_decision:' "$MANIFEST" | sed 's/^tracer_bullet_red_decision: *//;s/"//g' | head -1)"
  case "$tbrd_val" in
    null|continue|reduce_scope|hand_code) ;;
    *) fail "tracer_bullet_red_decision '$tbrd_val' is not valid (must be: null|continue|reduce_scope|hand_code)" ;;
  esac
fi

# Invariant 21 (conditional, ADR-0060): if external_dependencies present, must be an empty flow
# list `[]` or a bracketed flow list of maps `[{...}]`. Absent = valid (retrocompat with every
# pre-ADR-0060 manifest); a manifest without the field still validates (SPEC edge case) — this
# feature ADDS a constraint, so absent equals the pre-feature behaviour, same direction as
# tracer_bullet_mode (Invariant 18), the opposite of risk/task_type (Invariants 16/17). Shallow
# shape check only, matching every other invariant's grep-based validation style.
if grep -q '^external_dependencies:' "$MANIFEST"; then
  ed_val="$(grep '^external_dependencies:' "$MANIFEST" | sed 's/^external_dependencies: *//' | head -1)"
  case "$ed_val" in
    '[]') ;;
    '[{'*'}]') ;;
    *) fail "external_dependencies '$ed_val' is not '[]' or a bracketed flow list of maps" ;;
  esac
fi

# Invariant 22 (conditional, ADR-0068 §D11): if worktree_baseref_verified present, must be true or
# false. Absent = valid (retrocompat with every pre-ADR-0068 manifest); Step 5.0.4 sets it true
# only after confirming worktree.baseRef == "head" in the effective settings.json — this feature
# ADDS a pre-flight check, so absent/false is the pre-feature-equivalent default, same direction as
# tracer_bullet_mode (Invariant 18) and external_dependencies (Invariant 21).
if grep -q '^worktree_baseref_verified:' "$MANIFEST"; then
  if ! grep -Eq '^worktree_baseref_verified: (true|false)$' "$MANIFEST"; then
    fail "worktree_baseref_verified present but value is not 'true' or 'false'"
  fi
fi

# Invariant 23 (conditional, ADR-0068 §D11): if worktree_merges present, must be an empty flow
# list '[]' or a bracketed flow list of maps '[{...}]'. Absent = valid (retrocompat with every
# pre-ADR-0068 manifest). Shallow shape check only, the same style as external_dependencies
# (Invariant 21) — one entry per merged stage ({stage, agent_type, branch, base_sha,
# merge_result}), appended by bash sed on the additive field, never via manifest-set-flag.sh.
if grep -q '^worktree_merges:' "$MANIFEST"; then
  wm_val="$(grep '^worktree_merges:' "$MANIFEST" | sed 's/^worktree_merges: *//' | head -1)"
  case "$wm_val" in
    '[]') ;;
    '[{'*'}]') ;;
    *) fail "worktree_merges '$wm_val' is not '[]' or a bracketed flow list of maps" ;;
  esac
fi

if [ "$ERRORS" != "0" ]; then
  exit 1
fi

exit 0
