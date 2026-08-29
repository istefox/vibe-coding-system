#!/bin/bash
# test-write-scope v1.1 — PreToolUse gate on Write|Edit|MultiEdit merging TWO agent-type scopes
# under one dispatch (VCS-046): the ARCHITECT write-scope gate (ADR-0041/issue #58, ported
# verbatim below from the now-deleted agent-write-scope.sh — see the ARCHITECT SCOPE block) and
# this file's original CODER test-file deny, preserved unchanged (issue #103; ADR-0049 —
# generator/verifier separation).
#
# WHY MERGED. Both hooks already opened by extracting .agent_type via one jq call and bailing
# immediately on a mismatch — "not architect, not coder, allow" — but settings.json wired them as
# two SEPARATE PreToolUse entries on the same Write|Edit|MultiEdit matcher, so every single
# Edit/Write/MultiEdit call in the whole system, including every orchestrator call, spawned two
# bash processes and two jq processes just to reach that same "allow" for every agent type neither
# hook actually cares about. That cost is universal per-call overhead, not agent-type-gated work,
# and one dispatch removes half of it.
#
# THE NAME IS NOW SLIGHTLY IMPRECISE — it also gates the architect, not only tests — accepted as a
# stated tradeoff: this file's own TI1-TI4 registration assertions, agent-metrics.test.sh's
# GT0/GT1, and 8 mentions across concept-to-code/references/step5-implementation.md all key off
# this exact name and stay valid by keeping it.
#
# =====================================================================================
# ARCHITECT SCOPE (ADR-0041/issue #58) — ex agent-write-scope.sh, ported verbatim below.
#
# Original purpose: PreToolUse gate constraining the architect agent's writes to the two
# documentation roots it is meant to produce (ADR-0036 §3.3 disclosed the gap).
#
# Why a hook: Claude Code's frontmatter grammar documents path patterns for Read/Grep/Edit but
# not for Write, so architect.md's "you may only write under docs/..." is prose, not a control.
# ADR-0036 recorded that it had no frontmatter-level fix and needed a dedicated hook. This is it.
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
#
# =====================================================================================
# CODER SCOPE (ADR-0049/issue #103) — this file's original purpose, preserved unchanged below.
#
# THREAT MODEL — do not mistake this for more than it is.
# A guardrail against a shortcut, NOT a sandbox: a coder can still write a test file by piping it
# through Bash (a Bash tool_input carries no .file_path — see test-write-scope.test.sh section TE),
# and the predicate below classifies by path only, content is never inspected. Mirrors the same
# stated limit in agent-command-scope.sh and this file's own ARCHITECT SCOPE block above.
#
# CHECK ORDER (the order is the design, not an implementation detail — ADR-0049 §D3):
#   1. agent_type != "coder" -> allow and exit FIRST. This is what lets the tester agent write
#      test files at all, and it is why refactorer/debugger/the orchestrator/anyone else is
#      untouched, marker or no marker.
#   2. agent_id missing -> allow. No main-session fallback: an orchestrator turn that happens to
#      quote the marker must never bind the whole session (same deliberate divergence the
#      ARCHITECT SCOPE block above and agent-command-scope.sh already state for their own hooks).
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

# Two separate log_audit helpers, one per branch, each doing its own mkdir lazily — only the
# state directory for the branch actually taken gets created (VCS-046: the merge exists to remove
# universal per-call overhead, so it should not trade "two hook processes" for "two directories
# unconditionally created on every call" either).
DIR_ARCH="${AGENT_WRITE_SCOPE_DIR:-$HOME/.claude/state/agent-write-scope}"
log_audit_arch() {
  mkdir -p "$DIR_ARCH" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >>"$DIR_ARCH/audit.log" 2>/dev/null || true
}

DIR="${TEST_WRITE_SCOPE_DIR:-$HOME/.claude/state/test-write-scope}"
LOG="$DIR/audit.log"
log_audit() {
  mkdir -p "$DIR" 2>/dev/null || true
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >>"$LOG" 2>/dev/null || true
}

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)

if [ "$AGENT_TYPE" = "architect" ]; then
  # --- ARCHITECT BRANCH START (ADR-0041, ex agent-write-scope.sh) ---
  SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

  [ -z "$FILE_PATH" ] && { log_audit_arch "$SID" "allow" "no tool_input.file_path"; exit 0; }

  # Substring match on the path, deliberately not a prefix match against the project root: the
  # payload's cwd is not a reliable stand-in for the project root when the architect runs from a
  # subdirectory, and a wrong root would deny legitimate writes. Matching the two documentation
  # segments anywhere in the path is looser but errs toward allowing, which is the right direction
  # for a guard whose false positives would break the chain.
  case "$FILE_PATH" in
    */docs/architecture/*|*/docs/superpowers/plans/*)
      log_audit_arch "$SID" "allow" "in scope: $FILE_PATH"
      exit 0
      ;;
    docs/architecture/*|docs/superpowers/plans/*)
      log_audit_arch "$SID" "allow" "in scope (relative): $FILE_PATH"
      exit 0
      ;;
  esac

  log_audit_arch "$SID" "deny" "$TOOL out of scope: $FILE_PATH"

  REASON="agent-write-scope: the architect may write only under docs/architecture/ (ADRs) or docs/superpowers/plans/ (implementation plans). This call targets $FILE_PATH, which is outside both. You never write production code, config, or tests — that is the coder's job. Do NOT retry and do NOT route around this: state the change you believe is needed in your report and let the orchestrator decide."

  printf '%s' "$REASON" | jq -R -s \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}' 2>/dev/null \
    || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"agent-write-scope: architect may write only under docs/architecture/ or docs/superpowers/plans/"}}\n'
  exit 0
  # --- ARCHITECT BRANCH END ---
elif [ "$AGENT_TYPE" != "coder" ]; then
  log_audit "?" "allow" "agent_type=$AGENT_TYPE (not coder)"
  exit 0
fi

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
