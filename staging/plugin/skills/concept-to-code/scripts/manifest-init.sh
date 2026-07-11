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
