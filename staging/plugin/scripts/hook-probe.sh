#!/bin/bash
# hook-probe v1.0 — observational hook. Records what the hook system sees. Decides nothing.
#
# Purpose: settle three open questions with evidence instead of inference —
#   ADR-0016  do PreToolUse/PostToolUse hooks fire inside a Workflow subagent, and does
#             pre-flight-pattern-enforce actually ENFORCE there (it keys on agent_type == "coder")?
#   ADR-0022  does a project Stop hook coexist with /goal's evaluator (itself a Stop hook)?
#   Routines  (later) do hooks fire at all in a cloud routine?
#
# Contract:
#   - reads the hook event JSON on stdin
#   - appends exactly one JSONL line to the probe log
#   - ALWAYS exits 0
#   - ALWAYS writes an empty stdout
#
# The empty stdout matters. For every blockable event, "exit 0 + empty stdout" means allow. A probe
# that printed anything on stdout could be parsed as a hook decision and would silently start
# blocking tool calls. So: diagnostics go to stderr, never stdout.
#
# Fail-open by construction. Every other hook in this system chooses its failure direction on
# purpose (protect-files and autopilot-guard fail closed; stop-gate and auto-format fail open). This
# one has no direction to choose, because it never returns a decision. A malfunctioning probe must
# never break a session, so every path ends in exit 0.
#
# Log location, first match wins:
#   1. $HOOK_PROBE_LOG
#   2. <cwd from the payload>/.claude/hook-probe.jsonl
#   3. $PWD/.claude/hook-probe.jsonl
#
# Context label: read from <log dir>/hook-probe-context if present, else "unset". The runbook has
# the human bump that file between contexts (C1..C4), because hook env vars are fixed at session
# start and cannot be varied per prompt.
#
# Bash 3.2 clean.
#
# transcript-scan-exempt: probe-only, never registered. WRITES its own log; does not read a CC
#   transcript.

set -u

# Never let a failure anywhere below escape as a non-zero exit.
trap 'exit 0' EXIT

PAYLOAD=$(cat 2>/dev/null) || PAYLOAD=""

have_jq=0
command -v jq >/dev/null 2>&1 && have_jq=1

# --- resolve the log path -----------------------------------------------------------------------
LOG="${HOOK_PROBE_LOG:-}"
if [ -z "$LOG" ]; then
  CWD=""
  if [ "$have_jq" -eq 1 ] && [ -n "$PAYLOAD" ]; then
    CWD=$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""
  fi
  [ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
  LOG="$CWD/.claude/hook-probe.jsonl"
fi

LOGDIR=$(dirname "$LOG")
mkdir -p "$LOGDIR" 2>/dev/null || exit 0

# --- context label ------------------------------------------------------------------------------
CONTEXT="unset"
if [ -r "$LOGDIR/hook-probe-context" ]; then
  CONTEXT=$(head -1 "$LOGDIR/hook-probe-context" 2>/dev/null | tr -d '[:space:]') || CONTEXT="unset"
  [ -n "$CONTEXT" ] || CONTEXT="unset"
fi

SEQ=0
[ -f "$LOG" ] && SEQ=$(wc -l < "$LOG" 2>/dev/null | tr -d '[:space:]')
[ -n "$SEQ" ] || SEQ=0

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TS="unknown"

# --- record -------------------------------------------------------------------------------------
# Without jq we cannot parse, but we must still record: an empty log is indistinguishable from
# "hooks never fired", which is the single most dangerous misreading of this probe's output.
if [ "$have_jq" -eq 0 ] || [ -z "$PAYLOAD" ]; then
  B64=$(printf '%s' "$PAYLOAD" | base64 2>/dev/null | tr -d '\n') || B64=""
  printf '{"probe":"raw","seq":%s,"ts":"%s","context":"%s","reason":"%s","payload_b64":"%s"}\n' \
    "$SEQ" "$TS" "$CONTEXT" \
    "$([ "$have_jq" -eq 0 ] && printf 'no-jq' || printf 'empty-stdin')" \
    "$B64" >> "$LOG" 2>/dev/null
  exit 0
fi

printf '%s' "$PAYLOAD" | jq -c \
  --argjson seq "$SEQ" \
  --arg ts "$TS" \
  --arg context "$CONTEXT" \
  '{
     probe: "parsed",
     seq: $seq,
     ts: $ts,
     context: $context,
     hook_event_name: (.hook_event_name // null),
     tool_name: (.tool_name // null),
     agent_id: (.agent_id // null),
     agent_type: (.agent_type // null),
     session_id: (.session_id // null),
     transcript_path: (.transcript_path // null),
     cwd: (.cwd // null),
     permission_mode: (.permission_mode // null)
   }' >> "$LOG" 2>/dev/null

exit 0
