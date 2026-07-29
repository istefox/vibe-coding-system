#!/bin/bash
# agent-write-scope v1.0 — PreToolUse gate constraining the architect agent's writes to the two
# documentation roots it is meant to produce (issue #58, gap 2; ADR-0036 §3.3 disclosed the gap).
#
# Why a hook: Claude Code's frontmatter grammar documents path patterns for Read/Grep/Edit but
# not for Write, so architect.md's "you may only write under docs/..." is prose, not a control.
# ADR-0036 recorded that it had no frontmatter-level fix and needed a dedicated hook. This is it.
#
# Contract: exit 0 + empty stdout = allow. exit 0 + {"hookSpecificOutput":{...,"deny"}} = deny.
# NEVER exits non-zero. Every failure mode allows.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution.
#
# TWO ROOTS, NOT ONE. architect.md claimed "docs/architecture/** only", but concept-to-code
# Step 2 orders the architect to write its plan to docs/superpowers/plans/<date>-<slug>.md
# (its "**Dispatch architect:**" brief) and HARD ABORTs when that path is absent from the report
# (its "**Validate architect output fields (before populating artifacts):**" table).
# Both references name a heading, not a line number: the two they used to carry had rotted into
# a bare code-fence delimiter and a blank line (issue #210), which is the worst shape a stale
# pointer takes — the reasoning behind a live guardrail becomes unverifiable at exactly the
# moment someone tries to verify it.
# Enforcing the file's literal claim would have broken every chain run at Step 2. The agent file
# has been corrected to match; agent-write-scope.test.sh section E keeps the two in agreement,
# and B2 is the regression guard for the plan path specifically.
#
# Simpler than write-scope-enforce.sh (#87) on purpose: that hook derives a per-dispatch scope
# from the prompt and must read the subagent transcript to find it. Here the scope is static per
# agent type, so .agent_type and .tool_input.file_path are the whole input.

DIR="${AGENT_WRITE_SCOPE_DIR:-$HOME/.claude/state/agent-write-scope}"
LOG="$DIR/audit.log"
mkdir -p "$DIR" 2>/dev/null || true

log_audit() {
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >>"$LOG" 2>/dev/null || true
}

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || { log_audit "?" "allow" "jq missing"; exit 0; }

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)

# Inert for the orchestrator and every other agent. This is the common path.
[ "$AGENT_TYPE" = "architect" ] || { log_audit "?" "allow" "agent_type=$AGENT_TYPE (not architect)"; exit 0; }

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -z "$FILE_PATH" ] && { log_audit "$SID" "allow" "no tool_input.file_path"; exit 0; }

# Substring match on the path, deliberately not a prefix match against the project root: the
# payload's cwd is not a reliable stand-in for the project root when the architect runs from a
# subdirectory, and a wrong root would deny legitimate writes. Matching the two documentation
# segments anywhere in the path is looser but errs toward allowing, which is the right direction
# for a guard whose false positives would break the chain.
case "$FILE_PATH" in
  */docs/architecture/*|*/docs/superpowers/plans/*)
    log_audit "$SID" "allow" "in scope: $FILE_PATH"
    exit 0
    ;;
  docs/architecture/*|docs/superpowers/plans/*)
    log_audit "$SID" "allow" "in scope (relative): $FILE_PATH"
    exit 0
    ;;
esac

log_audit "$SID" "deny" "$TOOL out of scope: $FILE_PATH"

REASON="agent-write-scope: the architect may write only under docs/architecture/ (ADRs) or docs/superpowers/plans/ (implementation plans). This call targets $FILE_PATH, which is outside both. You never write production code, config, or tests — that is the coder's job. Do NOT retry and do NOT route around this: state the change you believe is needed in your report and let the orchestrator decide."

printf '%s' "$REASON" | jq -R -s \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"agent-write-scope: architect may write only under docs/architecture/ or docs/superpowers/plans/"}}\n'
exit 0
