#!/bin/bash
# hook-probe-verify v1.0 — turn a hook-probe log into a per-context verdict.
#
# Usage: hook-probe-verify.sh [<path-to-hook-probe.jsonl>]
#        default: ./.claude/hook-probe.jsonl
#
# Exit codes:
#   0  a verdict was produced (read it; it may still be hook_verified=false)
#   3  INCONCLUSIVE — the log is missing or empty
#   4  the log exists but jq is unavailable, so it cannot be read
#
# The exit-3 case is the important one. An empty log means the probe was never registered or the
# session never restarted. It does NOT mean hooks do not fire. Absence of evidence is not evidence
# of absence, and reading it that way would flip hook_verified for the wrong reason.
#
# What this checks, per context:
#   - did PreToolUse fire?  did PostToolUse fire?
#   - is agent_id present (i.e. was the hook inside a subagent call)?
#   - what is the LITERAL agent_type?
#   - would pre-flight-pattern-enforce actually enforce? It bails unless agent_type == "coder".
#   - does the subagent transcript live where pre-flight-pattern-enforce looks for it? The script
#     tries <proj>/<sid>/subagents/agent-<agent_id>.jsonl, then globs
#     <proj>/<sid>/subagents/workflows/ for the same basename, then falls open. A miss on both means
#     the guard fails open in silence.
#
# Bash 3.2 clean. Read-only: never writes, never mutates a manifest.

set -u

LOG="${1:-./.claude/hook-probe.jsonl}"

if [ ! -f "$LOG" ] || [ ! -s "$LOG" ]; then
  printf 'HOOK_PROBE status=INCONCLUSIVE\n'
  printf 'reason=%s\n' "probe log missing or empty: $LOG"
  printf 'note=%s\n' "an empty log means the probe never ran, NOT that hooks do not fire"
  printf 'RECOMMEND hook_verified=unchanged\n'
  exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'HOOK_PROBE status=UNREADABLE\n'
  printf 'reason=%s\n' "jq is required to read the probe log"
  printf 'RECOMMEND hook_verified=unchanged\n'
  exit 4
fi

RAW_COUNT=$(jq -s '[.[] | select(.probe == "raw")] | length' "$LOG" 2>/dev/null) || RAW_COUNT=0
if [ "${RAW_COUNT:-0}" -gt 0 ]; then
  printf 'WARN %s raw (unparsed) probe lines present — jq was missing when they were recorded\n' "$RAW_COUNT"
fi

CONTEXTS=$(jq -r 'select(.probe == "parsed") | .context' "$LOG" 2>/dev/null | sort -u)
if [ -z "$CONTEXTS" ]; then
  printf 'HOOK_PROBE status=INCONCLUSIVE\n'
  printf 'reason=%s\n' "no parsed probe lines in $LOG"
  printf 'RECOMMEND hook_verified=unchanged\n'
  exit 3
fi

# --- matrix -------------------------------------------------------------------------------------
printf '\n'
printf '%-8s %-10s %-11s %-10s %-28s %-12s %s\n' \
  CONTEXT PreToolUse PostToolUse agent_id agent_type transcript SubagentStop
printf '%s\n' "--------------------------------------------------------------------------------------------------"

# Resolve a transcript exactly the way pre-flight-pattern-enforce.sh does.
resolve_transcript() {
  # $1 transcript_path  $2 session_id  $3 agent_id
  _tp="$1"; _sid="$2"; _aid="$3"
  [ -n "$_tp" ] && [ -n "$_sid" ] && [ -n "$_aid" ] || { printf 'n/a'; return; }
  _proj=$(dirname "$_tp")
  if [ -f "$_proj/$_sid/subagents/agent-$_aid.jsonl" ]; then printf 'match'; return; fi
  _wf="$_proj/$_sid/subagents/workflows"
  if [ -d "$_wf" ]; then
    _cand=$(find "$_wf" -name "agent-$_aid.jsonl" 2>/dev/null | head -1)
    [ -n "$_cand" ] && [ -f "$_cand" ] && { printf 'match'; return; }
  fi
  printf 'MISS'
}

C3_FIRE="no"; C3_TYPE=""; C3_ENFORCE="no"; C3_TRANSCRIPT="n/a"
C4_STOP="no"; C4_SUBSTOP="no"

for ctx in $CONTEXTS; do
  pre=$(jq -r --arg c "$ctx" 'select(.probe=="parsed" and .context==$c and .hook_event_name=="PreToolUse")  | .seq' "$LOG" | wc -l | tr -d ' ')
  post=$(jq -r --arg c "$ctx" 'select(.probe=="parsed" and .context==$c and .hook_event_name=="PostToolUse") | .seq' "$LOG" | wc -l | tr -d ' ')
  substop=$(jq -r --arg c "$ctx" 'select(.probe=="parsed" and .context==$c and .hook_event_name=="SubagentStop") | .seq' "$LOG" | wc -l | tr -d ' ')
  stop=$(jq -r --arg c "$ctx" 'select(.probe=="parsed" and .context==$c and .hook_event_name=="Stop") | .seq' "$LOG" | wc -l | tr -d ' ')

  aid=$(jq -r --arg c "$ctx" 'select(.probe=="parsed" and .context==$c and .agent_id != null) | .agent_id' "$LOG" | head -1)
  atype=$(jq -r --arg c "$ctx" 'select(.probe=="parsed" and .context==$c and .agent_type != null) | .agent_type' "$LOG" | head -1)
  tp=$(jq -r --arg c "$ctx" 'select(.probe=="parsed" and .context==$c and .transcript_path != null) | .transcript_path' "$LOG" | head -1)
  sid=$(jq -r --arg c "$ctx" 'select(.probe=="parsed" and .context==$c and .session_id != null) | .session_id' "$LOG" | head -1)

  [ -n "$aid" ] && aid_disp="yes" || aid_disp="no"
  [ -n "$atype" ] || atype="(absent)"

  if [ -n "$aid" ]; then tr_state=$(resolve_transcript "$tp" "$sid" "$aid"); else tr_state="n/a"; fi

  [ "$pre" -gt 0 ] && pre_disp="yes($pre)" || pre_disp="no"
  [ "$post" -gt 0 ] && post_disp="yes($post)" || post_disp="no"
  [ "$substop" -gt 0 ] && ss_disp="yes($substop)" || ss_disp="no"

  printf '%-8s %-10s %-11s %-10s %-28s %-12s %s\n' \
    "$ctx" "$pre_disp" "$post_disp" "$aid_disp" "$atype" "$tr_state" "$ss_disp"

  if [ "$ctx" = "C3" ]; then
    [ "$pre" -gt 0 ] && C3_FIRE="yes"
    C3_TYPE="$atype"
    [ "$atype" = "coder" ] && C3_ENFORCE="yes"
    C3_TRANSCRIPT="$tr_state"
  fi
  if [ "$ctx" = "C4" ]; then
    [ "$stop" -gt 0 ] && C4_STOP="yes"
    [ "$substop" -gt 0 ] && C4_SUBSTOP="yes"
  fi
done

printf '\n'

# --- verdicts -----------------------------------------------------------------------------------
printf 'HOOK_PROBE C3 hooks_fire=%s\n' "$C3_FIRE"
printf 'HOOK_PROBE C3 agent_type=%s\n' "${C3_TYPE:-(absent)}"
printf 'HOOK_PROBE C3 enforce_would_run=%s\n' "$C3_ENFORCE"
printf 'HOOK_PROBE C3 transcript_glob=%s\n' "$(printf '%s' "$C3_TRANSCRIPT" | tr 'A-Z' 'a-z')"
printf 'HOOK_PROBE C4 stop_hook_fired=%s\n' "$C4_STOP"
printf 'HOOK_PROBE C4 subagent_stop_fired=%s\n' "$C4_SUBSTOP"
printf '\n'

if [ "$C3_FIRE" = "no" ]; then
  printf 'RECOMMEND hook_verified=false\n'
  printf 'reason=%s\n' "PreToolUse never fired inside the workflow subagent (C3). The ADR-0016 blocker is real as written; keep the Agent-tool fallback."
  exit 0
fi

if [ "$C3_ENFORCE" = "no" ]; then
  printf 'RECOMMEND hook_verified=false\n'
  printf 'reason=%s\n' "hooks DO fire in a workflow subagent, but agent_type is '${C3_TYPE}', not 'coder'. pre-flight-pattern-enforce bails at its agent_type check and enforces nothing. The guard is inert while appearing installed. Fix ADR-0004's matcher before flipping the flag."
  exit 0
fi

if [ "$C3_TRANSCRIPT" = "MISS" ]; then
  printf 'RECOMMEND hook_verified=false\n'
  printf 'reason=%s\n' "hooks fire and agent_type is 'coder', but the subagent transcript is not where pre-flight-pattern-enforce looks. It fails open in silence, so the PATTERN header is never checked."
  exit 0
fi

printf 'RECOMMEND hook_verified=true\n'
printf 'reason=%s\n' "PreToolUse fires inside the workflow subagent, agent_type is 'coder', and the transcript resolves. pre-flight-pattern-enforce can enforce there. The Step-5 workflow path may be opened."
exit 0
