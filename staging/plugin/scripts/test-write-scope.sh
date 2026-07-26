#!/bin/bash
# test-write-scope v1.0 — PreToolUse gate denying the CODER agent create/edit of test-file-shaped
# paths, but only when its own dispatch prompt carries the tester/coder separation marker
# (issue #103; ADR-0049 — generator/verifier separation).
#
# THREAT MODEL — do not mistake this for more than it is.
# A guardrail against a shortcut, NOT a sandbox: a coder can still write a test file by piping it
# through Bash (a Bash tool_input carries no .file_path — see test-write-scope.test.sh section TE),
# and the predicate below classifies by path only, content is never inspected. Mirrors the same
# stated limit in agent-command-scope.sh and agent-write-scope.sh.
#
# CHECK ORDER (the order is the design, not an implementation detail — ADR-0049 §D3):
#   1. agent_type != "coder" -> allow and exit FIRST. This is what lets the tester agent write
#      test files at all, and it is why refactorer/debugger/the orchestrator/anyone else is
#      untouched, marker or no marker.
#   2. agent_id missing -> allow. No main-session fallback: an orchestrator turn that happens to
#      quote the marker must never bind the whole session (same deliberate divergence
#      agent-write-scope.sh and agent-command-scope.sh already state for their own hooks).
#   3. The subagent's OWN transcript must exist and parse. It is derived from transcript_path's
#      directory plus session_id plus agent_id — transcript_path itself is the MAIN session's
#      file, never read directly for the marker. Missing file, malformed JSONL, missing jq: all
#      allow.
#   4. The marker is read from the FIRST `user`-type entry of that transcript ONLY
#      (`jq ... | head -1 | grep ...` — the `head -1` is the entire point). A dispatch prompt is
#      structurally the first entry in a subagent transcript; a tool result can never be.
#      ADR-0049 §D9 records a sibling hook scanning every `user` entry instead and self-arming on
#      an agent that read its own marker-bearing source, because a tool result is recorded as a
#      `user` entry too. This hook must not reproduce that mechanism — test-write-scope.test.sh
#      section TB (TB7/TB8) pins the first-entry-only contract as a regression guard.
#   5. No marker in that first entry -> allow.
#   6. Marker present -> classify tool_input.file_path against the predicate below. No file_path
#      at all (e.g. a Bash tool_input, which carries .command instead) -> allow.
#
# PATH PREDICATE (ADR-0049 §D4) — the broad union minus .md, checked in this order:
#   *.md is allowed FIRST and unconditionally (docs/specs/*.spec.md must stay writable, or the
#   coder could never write a SPEC — ADR-0048's discovery predicate hit the identical collision
#   from its own side).
#   Then a directory-COMPONENT check (tests/, test/, spec/ as a path component, never a
#   substring — testing-app/ is not a test tree).
#   Then a basename check for *.test.*, *.spec.*, test_*, *_test.*, *Test.*, *Tests.*, test-*.sh,
#   run-tests.sh.
#   This is deliberately NOT reconciled with spec-coverage.sh's own (narrower) discovery
#   predicate: a discovery predicate must not over-match (a false coverage pass), a denial
#   predicate must not under-match (a missed test path is invisible) — opposite error directions.
#   [convention] do not "fix" this into agreement with spec-coverage.sh.
#
# Contract: exit 0 + empty stdout = allow. exit 0 + {"hookSpecificOutput":{...,"deny"}} = deny.
# permissionDecision is "deny", never "block" (ADR-0009's verified enum). NEVER exits non-zero.
# Every failure mode allows.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution.

DIR="${TEST_WRITE_SCOPE_DIR:-$HOME/.claude/state/test-write-scope}"
LOG="$DIR/audit.log"
mkdir -p "$DIR" 2>/dev/null || true

log_audit() {
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >>"$LOG" 2>/dev/null || true
}

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || { log_audit "?" "allow" "jq missing"; exit 0; }

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)

# Step 1 — the ordering decision (§D1/§D3). Everyone but the coder is untouched, unconditionally.
[ "$AGENT_TYPE" = "coder" ] || { log_audit "?" "allow" "agent_type=$AGENT_TYPE (not coder)"; exit 0; }

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

# Step 2 — no agent_id, no fallback. Decided before any transcript is even opened.
[ -n "$AGENT_ID" ] || { log_audit "$SID" "allow" "no agent_id (no main-session fallback)"; exit 0; }
[ -n "$TRANSCRIPT_PATH" ] || { log_audit "$SID" "allow" "no transcript_path"; exit 0; }
[ -n "$SID" ] || { log_audit "?" "allow" "no session_id"; exit 0; }

# Step 3 — locate the SUBAGENT's own transcript. transcript_path is the MAIN session's file; the
# subagent-specific one lives alongside it at <dir>/<session_id>/subagents/agent-<agent_id>.jsonl.
PROJ_DIR=$(dirname "$TRANSCRIPT_PATH" 2>/dev/null)
SUB_TRANSCRIPT="$PROJ_DIR/$SID/subagents/agent-$AGENT_ID.jsonl"

[ -f "$SUB_TRANSCRIPT" ] || { log_audit "$SID" "allow" "no subagent transcript at $SUB_TRANSCRIPT"; exit 0; }

# Step 4 — the FIRST `user` entry only. head -1 is the whole point (ADR-0049 §D9).
FIRST_USER=$(jq -c 'select(.type=="user")' "$SUB_TRANSCRIPT" 2>/dev/null | head -1)

MARKER='TEST-AUTHORING SCOPE - the tester agent owns test files for this task. Do NOT create or edit tests.'

# Step 5 — no marker in the first entry -> allow.
printf '%s' "$FIRST_USER" | grep -qF "$MARKER" 2>/dev/null \
  || { log_audit "$SID" "allow" "no marker in first user entry"; exit 0; }

# Step 6 — marker present. Classify tool_input.file_path.
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

[ -n "$FILE_PATH" ] || { log_audit "$SID" "allow" "marker present but no tool_input.file_path (e.g. Bash)"; exit 0; }

P="$FILE_PATH"

case "$P" in
  *.md)
    log_audit "$SID" "allow" "*.md exempt: $P"
    exit 0
    ;;
esac

DENY=0
case "$P" in
  */tests/*|tests/*|*/test/*|test/*|*/spec/*|spec/*) DENY=1 ;;
esac

if [ "$DENY" -eq 0 ]; then
  BN="${P##*/}"
  case "$BN" in
    *.test.*|*.spec.*|test_*|*_test.*|*Test.*|*Tests.*|test-*.sh|run-tests.sh) DENY=1 ;;
  esac
fi

if [ "$DENY" -eq 0 ]; then
  log_audit "$SID" "allow" "not test-shaped: $P"
  exit 0
fi

log_audit "$SID" "deny" "coder test-write: $P"

REASON="test-write-scope: this task's tests are owned by the tester agent, not the coder (ADR-0049, generator/verifier separation). This call targets $P, which is a test-shaped path. Do NOT create or edit it. If you believe a test genuinely needs a change outside your scope, report it in your output — do not retry, do not route around this hook, and do not write the test yourself."

printf '%s' "$REASON" | jq -R -s \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"test-write-scope: the coder may not create or edit test files for this task. Test files belong to the tester agent. Report the needed change instead of writing it."}}\n'
exit 0
