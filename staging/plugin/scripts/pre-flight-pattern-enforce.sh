#!/bin/bash
# pre-flight-pattern-enforce v1.4 — gate for coder agent: blocks Edit/Write/MultiEdit
# if PATTERN: header is missing in the sliding window (ADR-0004, ADR-0001 contract).
# Contract: exit 0 + empty stdout = allow; exit 0 + {"decision":"block",...} = block.
# Fail-open on any internal error (never exit non-zero, never crash visibly).
# Bash 3.2 clean: no assoc array, no mapfile, no ${v^^}, no process substitution.
#
# v1.1 fix (2026-05-21, debugger root-cause):
# - agent_type is in the PreToolUse payload directly (.agent_type), NOT in transcript.
#   The old code searched .subagent_type in the transcript jsonl — that field does not
#   exist; the correct field is .agent_type in stdin JSON.
# - The PATTERN: search must use the subagent's own jsonl
#   (<proj>/<SID>/subagents/agent-<agent_id>.jsonl), not the main session jsonl
#   (transcript_path in the payload points to the main jsonl which contains NO sub-agent
#   messages; sub-agent messages live in the separate subagent file).
#
# v1.2 fix (2026-05-22, debugger root-cause):
# - Path-encoding bug: the old code re-encoded cwd via tr '/' '-', but Claude Code also
#   converts '_' (and potentially other chars) to '-' when encoding project dirs. The
#   encoding rule is not stable across CC versions (both Obsidian-MCP and Obsidian_MCP
#   exist in ~/.claude/projects/). Fix: derive project dir from transcript_path field
#   in the payload (already correctly encoded by CC), never re-encode cwd.
# - Block message: removed bypass instructions from coder-visible reason; bypass is an
#   orchestrator/user decision, not a coder action.
#
# v1.3 fix (2026-05-29, smoke test 2026-05-29):
# - Workflow subagent path: Dynamic Workflows (v2.1.154+) store subagent transcripts
#   at <proj>/<SID>/subagents/workflows/<wf_id>/agent-<id>.jsonl, not at the regular
#   <proj>/<SID>/subagents/agent-<id>.jsonl path. Added a find-based fallback that
#   searches under workflows/ when the direct path is missing.
#
# v1.4 fix (2026-06-11, extended-thinking models):
# - Extended-thinking models (Fable 5) emit the PATTERN: header inside `.thinking`
#   content blocks rather than `.text` blocks — the old jq filter `.text? // empty`
#   never saw them, so every Write was blocked even with a correct header.
#   Fix: extract BOTH .text and .thinking content from assistant turns so the grep
#   finds the header regardless of which block type the model used.

DIR="${PATTERN_ENFORCE_DIR:-$HOME/.claude/state/pattern-enforce}"
LOG="$DIR/audit.log"
DISABLED="$DIR/disabled"
WINDOW="${PATTERN_ENFORCE_WINDOW:-20}"

mkdir -p "$DIR" 2>/dev/null || true

# Audit log helper: $1=session $2=tool $3=action $4=reason
log_audit() {
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" >>"$LOG" 2>/dev/null || true
}

# --- Bypass mechanisms: HUMAN-ONLY (P4 contract) ---
# The bypasses below (PATTERN_ENFORCE=off env var, the `disabled` file flag) are
# EXPLICIT HUMAN decisions. Neither sub-agents nor the orchestrator may set/create them
# autonomously to get past a block. If this hook looks buggy: a sub-agent STOPS and
# reports; the orchestrator asks the user. Disabling a guardrail is the user's call only.
# (In auto mode the env var does not propagate from a shell subprocess and the file
# flag creation is denied by the classifier — both by design, not a defect to work around.)

# Bypass 1: env var single-call
if [ "$PATTERN_ENFORCE" = "off" ]; then
  log_audit "?" "?" "bypass-env" "env PATTERN_ENFORCE=off"
  exit 0
fi

# Bypass 2: file flag global
if [ -f "$DISABLED" ]; then
  log_audit "?" "?" "bypass-file" "$DISABLED present"
  exit 0
fi

# Read stdin (consume once)
INPUT=$(cat)

# Require jq
command -v jq >/dev/null 2>&1 || { log_audit "?" "?" "fail-open" "jq missing"; exit 0; }

# Extract session_id (fail-open if missing or malformed JSON)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && { log_audit "?" "?" "fail-open" "no session_id (malformed or empty JSON)"; exit 0; }

# Extract tool_name, cwd, agent_type, agent_id from payload
# v1.1: agent_type is a first-class field in the PreToolUse payload (not in transcript).
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)

# Discriminator: agent_type in payload (not subagent_type in transcript).
# Non-coder or orchestrator (agent_type absent or != coder) → bypass silent.
if [ "$AGENT_TYPE" != "coder" ]; then
  log_audit "$SID" "$TOOL" "bypass-noncoder" "agent_type=$AGENT_TYPE"
  exit 0
fi

# Coder path: find the subagent's own jsonl for PATTERN: search.
# v1.2: derive project dir from transcript_path in the payload (already CC-encoded).
# Never re-encode cwd — Claude Code's encoding is not stable (e.g. '_' may become '-').
# transcript_path points to the main session jsonl: <proj_dir>/<SID>.jsonl
# Regular subagent jsonl:  <proj_dir>/<SID>/subagents/agent-<id>.jsonl
# Workflow subagent jsonl: <proj_dir>/<SID>/subagents/workflows/<wf_id>/agent-<id>.jsonl
TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
TRANSCRIPT=""
if [ -n "$AGENT_ID" ] && [ -n "$TP" ]; then
  PROJ_DIR=$(dirname "$TP")
  SUBAGENT_CANDIDATE="$PROJ_DIR/$SID/subagents/agent-$AGENT_ID.jsonl"
  [ -f "$SUBAGENT_CANDIDATE" ] && TRANSCRIPT="$SUBAGENT_CANDIDATE"
fi

# v1.3: workflow subagent path — search under subagents/workflows/*/
if [ -z "$TRANSCRIPT" ] && [ -n "$AGENT_ID" ] && [ -n "$TP" ]; then
  PROJ_DIR=$(dirname "$TP")
  WORKFLOWS_DIR="$PROJ_DIR/$SID/subagents/workflows"
  if [ -d "$WORKFLOWS_DIR" ]; then
    WF_CANDIDATE=$(find "$WORKFLOWS_DIR" -name "agent-$AGENT_ID.jsonl" 2>/dev/null | head -1)
    [ -n "$WF_CANDIDATE" ] && [ -f "$WF_CANDIDATE" ] && TRANSCRIPT="$WF_CANDIDATE"
  fi
fi

# Fallback: main session jsonl from transcript_path (already correctly encoded).
# Do NOT fall back to re-encoding cwd — that is the source of the path-encoding bug.
if [ -z "$TRANSCRIPT" ]; then
  if [ -n "$TP" ] && [ -f "$TP" ]; then
    TRANSCRIPT="$TP"
  fi
fi

# Fail-open if transcript still not found
if [ ! -f "$TRANSCRIPT" ]; then
  log_audit "$SID" "$TOOL" "fail-open" "transcript not found (agent_id=$AGENT_ID)"
  exit 0
fi

# Coder path: extract WINDOW most recent assistant message texts from subagent transcript
# v1.4: include .thinking blocks — extended-thinking models emit the header there.
RECENT=$(tail -n 200 "$TRANSCRIPT" 2>/dev/null \
  | jq -r 'select(.type=="assistant") | .message.content[]? | (.text? // empty), (.thinking? // empty)' 2>/dev/null \
  | tail -n "$WINDOW")

# Match PATTERN: header. Canonical categories: ADD|REMOVE|REPLACE|MODIFY.
# CREATE|NEW are tolerated aliases of ADD (the model emits them naturally for new
# files); the hook enforces the *presence* of a declarative header, not the exact
# taxonomy word — fine-grained category validation is the reviewer's pattern-drift job.
if printf '%s\n' "$RECENT" | grep -E '^PATTERN: (ADD|REMOVE|REPLACE|MODIFY|CREATE|NEW) \|' >/dev/null 2>&1; then
  log_audit "$SID" "$TOOL" "allow" "PATTERN found in window"
  exit 0
fi

# Block: PATTERN missing
log_audit "$SID" "$TOOL" "block" "PATTERN missing in window=$WINDOW"
jq -nc --arg r "pre-flight-pattern-enforce: PATTERN: header missing in sliding window. ADR-0001 requires emitting \`PATTERN: <CATEGORY> | <payload>\` before every Edit/Write/MultiEdit. Example: \`PATTERN: MODIFY | path/file.py:42 rename var\`. Emit the header and retry. If the block persists, STOP and report to the orchestrator — do NOT attempt to bypass or disable this guardrail." \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"block",permissionDecisionReason:$r}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"block","permissionDecisionReason":"missing PATTERN header (see ADR-0001)"}}\n'
exit 0
