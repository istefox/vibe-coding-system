#!/usr/bin/env bash
# concept-to-code: manifest-init.sh — bash 3.2-clean
# Creates a new manifest YAML file for a concept-to-code chain.
# Usage: manifest-init.sh <topic-slug> <topic-full-title> <project-root> [<mode>]
#   <mode>: greenfield (default) | brownfield
# Exit: 0 ok | 1 invalid args/root | 2 manifest already exists (use resume)
set -u

if [ "$#" -lt "3" ] || [ "$#" -gt "4" ]; then
  echo "usage: manifest-init.sh <topic-slug> <topic-full-title> <project-root> [mode]" >&2
  exit 1
fi

slug="$1"
title="$2"
root="$3"
mode="${4:-greenfield}"

# Validate mode
case "$mode" in
  greenfield|brownfield) ;;
  *) echo "manifest-init: invalid mode '$mode' (greenfield|brownfield)" >&2; exit 1 ;;
esac

# Validate slug: lowercase, kebab-case, 1-40 chars
if ! echo "$slug" | grep -Eq '^[a-z0-9-]{1,40}$'; then
  echo "manifest-init: invalid topic-slug '$slug' (must match ^[a-z0-9-]{1,40}$)" >&2
  exit 1
fi

# Validate project root exists
if [ ! -d "$root" ]; then
  echo "manifest-init: project root not found: $root" >&2
  exit 1
fi

# Create manifests directory (idempotent)
if ! mkdir -p "$root/docs/manifests"; then
  echo "manifest-init: cannot create $root/docs/manifests" >&2
  exit 1
fi

# Compute date and manifest path
today="$(date +%Y-%m-%d)"
manifest="$root/docs/manifests/$today-$slug.manifest.yml"

# Refuse double-init for same slug same day
if [ -f "$manifest" ]; then
  echo "manifest-init: manifest already exists for '$slug' on $today — use resume" >&2
  exit 2
fi

# ISO 8601 UTC timestamp
now="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"

# Escape YAML-breaking characters (backslash first, then double-quote -- order matters: a
# quote-escape's inserted backslash must not itself be re-escaped) before embedding the title
# inside a double-quoted YAML scalar (ADR-0028 Finding 3).
title_esc="$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g')"

# Atomic write via mktemp + mv
T="$(mktemp)"

echo "manifest_schema_version: \"1.3\"" > "$T"
echo "topic: \"$slug\"" >> "$T"
echo "topic_full_title: \"$title_esc\"" >> "$T"
echo "project_root: \"$root\"" >> "$T"
echo "mode: \"$mode\"" >> "$T"
echo "anonymize: false" >> "$T"
echo "chain_path: null" >> "$T"
echo "created_at: \"$now\"" >> "$T"
echo "last_updated_at: \"$now\"" >> "$T"
echo "current_step: \"step_0_init\"" >> "$T"
echo "status: \"in_progress\"" >> "$T"
echo "" >> "$T"
echo "# Gate 0 routing result (ADR-0017)" >> "$T"
echo "gate0:" >> "$T"
echo "  decision: null" >> "$T"
echo "  chain_path: null" >> "$T"
echo "  auto_detect_reason: null" >> "$T"
echo "  criteria_spec_adr_exist: false" >> "$T"
echo "  decided_at: null" >> "$T"
echo "" >> "$T"
echo "# test-cmd tracking (ADR-0014)" >> "$T"
echo "test_cmd_placeholder: false" >> "$T"
echo "test_cmd_candidate: null" >> "$T"
echo "test_cmd_provisional: false" >> "$T"
echo "coder_model: null" >> "$T"
echo "" >> "$T"
echo "# Autopilot mode (project-conductor): all HITL gates auto-select safe defaults" >> "$T"
echo "autopilot: false" >> "$T"
echo "" >> "$T"
echo "# Dynamic Workflows Step 5 tracking (ADR-0016) — default false; smoke test flips it true per environment" >> "$T"
echo "hook_verified: false" >> "$T"
echo "step5_mode: null" >> "$T"
echo "" >> "$T"
echo "# Recovery-readiness pre-flight (ADR-0050) — HEAD sha recorded once at Step 5 entry" >> "$T"
echo "recovery_baseline_sha: null" >> "$T"
echo "" >> "$T"
echo "# Worktree isolation contract (ADR-0068 §D1, §D11). worktree_baseref_verified is boolean," >> "$T"
echo "# set true by Step 5.0.4 via manifest-set-flag.sh once worktree.baseRef == \"head\" is" >> "$T"
echo "# confirmed in the effective settings.json; it is NOT named worktree_hook_verified — no hook" >> "$T"
echo "# is verified, and that name would collide with ADR-0016's unrelated hook_verified." >> "$T"
echo "# worktree_merges is an array, so manifest-set-flag.sh (true|false only) cannot write it;" >> "$T"
echo "# it goes via bash sed on the additive field, the step5_review_mode precedent above. Flip" >> "$T"
echo "# with, per merged stage ({stage, agent_type, branch, base_sha, merge_result}):" >> "$T"
echo "# sed -i '' 's/^worktree_merges: \[\]$/worktree_merges: [{stage: ..., agent_type: ..., branch: ..., base_sha: ..., merge_result: ...}]/' <manifest>" >> "$T"
echo "worktree_baseref_verified: false" >> "$T"
echo "worktree_merges: []" >> "$T"
echo "" >> "$T"
echo "# Proportional audit depth (ADR-0055) — risk and task_type axes. Absent/null means STRICT" >> "$T"
echo "# here, not inert (inverts the ADR-0052/0053/0054 pattern) — see concept-to-code/SKILL.md" >> "$T"
echo "# section '#### Proportional audit depth' for the resolution rule and the §D4 floor." >> "$T"
echo "risk: null" >> "$T"
echo "task_type: null" >> "$T"
echo "" >> "$T"
echo "# External dependencies (ADR-0060 G13). Empty list means nobody declared any — NOT that" >> "$T"
echo "# none exist (§D5); the gate is inert on an empty list. This is the OPPOSITE default" >> "$T"
echo "# direction from risk/task_type above: those default to the strict profile on null because" >> "$T"
echo "# they REMOVE a leniency; this feature ADDS a constraint, so absent/empty must equal the" >> "$T"
echo "# pre-feature behaviour (ADR-0055 §D2's rule, applied here per ADR-0060). Populated at Gate" >> "$T"
echo "# 2c from the architect's EXTERNAL DEPENDENCY: lines, confirmed by the operator." >> "$T"
echo "external_dependencies: []" >> "$T"
echo "" >> "$T"
echo "# Per-task checkpoint review in Step 5 (ADR-0039 D5-D9). Opt-in: 'none' | 'checkpoint'." >> "$T"
echo "# Flip with: sed -i '' 's/^step5_review_mode: none/step5_review_mode: checkpoint/' <manifest>" >> "$T"
echo "# (not manifest-set-flag.sh — that helper only accepts true|false, same as step5_mode)" >> "$T"
echo "step5_review_mode: none" >> "$T"
echo "" >> "$T"
echo "# Tracer-bullet probe (ADR-0057, Step 4.5, optional, between Gate 4 and Step 5). Absent/skip" >> "$T"
echo "# means skipped — the OPPOSITE default direction from ADR-0055 §D2 (contrast: that feature" >> "$T"
echo "# REMOVES a constraint so it defaults strict; this feature ADDS a step so inert must equal" >> "$T"
echo "# the pre-feature behaviour). Flip with:" >> "$T"
echo "# sed -i '' 's/^tracer_bullet_mode: skip/tracer_bullet_mode: probe/' <manifest>" >> "$T"
echo "tracer_bullet_mode: skip" >> "$T"
echo "tracer_bullet_verdict: null" >> "$T"
echo "tracer_bullet_recommendation: null" >> "$T"
echo "tracer_bullet_attempts: 0" >> "$T"
echo "tracer_bullet_red_decision: null" >> "$T"
echo "tracer_bullet_abort_reason: null" >> "$T"
echo "" >> "$T"
echo "# Scaffolding / repo bootstrap tracking (Gate 0d)" >> "$T"
echo "git_init: null" >> "$T"
echo "git_visibility: null" >> "$T"
echo "license: null" >> "$T"
echo "xcode_project: false" >> "$T"
echo "initial_commit_push: null" >> "$T"
echo "git_remote_url: null" >> "$T"
echo "step6_mode: null" >> "$T"
echo "" >> "$T"
echo "# Artifacts (absolute paths, populated as steps complete)" >> "$T"
echo "artifacts:" >> "$T"
echo "  spec: null" >> "$T"
echo "  brainstorm: null" >> "$T"
echo "  ux_blueprint: null" >> "$T"
echo "  adr: null" >> "$T"
echo "  arch: null" >> "$T"
echo "  plan: null" >> "$T"
echo "  project_claude_md: null" >> "$T"
echo "" >> "$T"
echo "# HITL gates audit trail" >> "$T"
echo "hitl_gates:" >> "$T"
echo "  - gate: 1" >> "$T"
echo "    label: \"spec_review\"" >> "$T"
echo "    status: \"pending\"" >> "$T"
echo "    approved_at: null" >> "$T"
echo "    notes: null" >> "$T"
echo "  - gate: 2" >> "$T"
echo "    label: \"architecture_review\"" >> "$T"
echo "    status: \"pending\"" >> "$T"
echo "    approved_at: null" >> "$T"
echo "    notes: null" >> "$T"
echo "  - gate: 3" >> "$T"
echo "    label: \"project_memory_review\"" >> "$T"
echo "    status: \"pending\"" >> "$T"
echo "    approved_at: null" >> "$T"
echo "    notes: null" >> "$T"
echo "  - gate: 5" >> "$T"
echo "    label: \"review_cycle_decision\"" >> "$T"
echo "    status: \"pending\"" >> "$T"
echo "    approved_at: null" >> "$T"
echo "    notes: null" >> "$T"
echo "" >> "$T"
echo "# Session boundary tracking" >> "$T"
echo "session_boundary:" >> "$T"
echo "  pre_step_4_session_id: null" >> "$T"
echo "  fresh_session_started_at: null" >> "$T"
echo "  resumed_at: null" >> "$T"
echo "" >> "$T"
echo "# Failure tracking (populated only on status=failed)" >> "$T"
echo "failure:" >> "$T"
echo "  failed_at: null" >> "$T"
echo "  failed_step: null" >> "$T"
echo "  failure_reason: null" >> "$T"
echo "  partial_artifacts: []" >> "$T"
echo "" >> "$T"
echo "# Hint for next action (UX)" >> "$T"
echo "next_action: \"Run /skill concept-to-code $slug to start Step 1 interview\"" >> "$T"

if mv "$T" "$manifest"; then
  echo "$manifest"
  exit 0
else
  echo "manifest-init: failed to write manifest to $manifest" >&2
  rm -f "$T"
  exit 1
fi
