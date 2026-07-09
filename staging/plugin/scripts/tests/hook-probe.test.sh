#!/bin/bash
# hook-probe test harness — offline, no network, no live claude session.
# Bash 3.2 clean. Run: bash hook-probe.test.sh
#
# IMPORTANT: this tests the PROBE, not the platform. A green run here says the probe records what it
# is given and the verifier reads it correctly. It says NOTHING about whether hooks fire inside a
# workflow subagent. Only the live run in the sandbox produces that evidence.

set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
PROBE="$SCRIPTS/hook-probe.sh"
VERIFY="$SCRIPTS/hook-probe-verify.sh"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP hook-probe tests: jq not available\n'
  exit 0
fi

# fire <log> <context> <json>
fire() {
  printf '%s\n' "$2" > "$(dirname "$1")/hook-probe-context"
  printf '%s' "$3" | HOOK_PROBE_LOG="$1" bash "$PROBE"
}

# --- probe: contract ------------------------------------------------------------------------------
L="$tmp/a/.claude/hook-probe.jsonl"; mkdir -p "$(dirname "$L")"

OUT=$(printf '{"hook_event_name":"PreToolUse","tool_name":"Edit","cwd":"/x"}' | HOOK_PROBE_LOG="$L" bash "$PROBE" 2>/dev/null)
[ -z "$OUT" ] && ok "probe: stdout is empty (cannot be read as a hook decision)" \
              || no "probe: stdout is empty (got: $OUT)"

printf '{"hook_event_name":"PreToolUse"}' | HOOK_PROBE_LOG="$L" bash "$PROBE" >/dev/null 2>&1
[ $? -eq 0 ] && ok "probe: exits 0 on a well-formed event" || no "probe: exits 0 on a well-formed event"

printf 'this is not json at all' | HOOK_PROBE_LOG="$L" bash "$PROBE" >/dev/null 2>&1
[ $? -eq 0 ] && ok "probe: exits 0 on malformed stdin" || no "probe: exits 0 on malformed stdin"

printf '' | HOOK_PROBE_LOG="$L" bash "$PROBE" >/dev/null 2>&1
[ $? -eq 0 ] && ok "probe: exits 0 on empty stdin" || no "probe: exits 0 on empty stdin"

RAW=$(grep -c '"probe":"raw"' "$L" 2>/dev/null | tr -d ' ')
[ "${RAW:-0}" -ge 1 ] && ok "probe: unparseable payload still recorded (empty log would be a lie)" \
                      || no "probe: unparseable payload still recorded"

# --- probe: no-jq degradation ---------------------------------------------------------------------
L2="$tmp/nojq/.claude/hook-probe.jsonl"; mkdir -p "$(dirname "$L2")"
FAKEBIN="$tmp/fakebin"; mkdir -p "$FAKEBIN"
# A PATH with no jq. coreutils still needed, so keep the real dirs minus any jq shim.
printf '{"hook_event_name":"PreToolUse"}' \
  | PATH="/usr/bin:/bin" HOOK_PROBE_LOG="$L2" bash "$PROBE" >/dev/null 2>&1
RC=$?
if command -v /usr/bin/jq >/dev/null 2>&1 || command -v /bin/jq >/dev/null 2>&1; then
  ok "probe: no-jq path skipped (jq present in /usr/bin or /bin)"
else
  [ "$RC" -eq 0 ] && grep -q '"reason":"no-jq"' "$L2" 2>/dev/null \
    && ok "probe: degrades to raw capture without jq, still exit 0" \
    || no "probe: degrades to raw capture without jq, still exit 0"
fi

# --- verifier: inconclusive paths -------------------------------------------------------------------
bash "$VERIFY" "$tmp/does-not-exist.jsonl" >/dev/null 2>&1
[ $? -eq 3 ] && ok "verify: missing log => exit 3 INCONCLUSIVE" || no "verify: missing log => exit 3"

: > "$tmp/empty.jsonl"
OUT=$(bash "$VERIFY" "$tmp/empty.jsonl" 2>&1); RC=$?
[ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'hook_verified=unchanged' \
  && ok "verify: empty log => INCONCLUSIVE, never recommends a flip" \
  || no "verify: empty log => INCONCLUSIVE, never recommends a flip"

# --- verifier: C3 fires, agent_type is coder, transcript resolves => true ---------------------------
build_c3() {
  # $1 log  $2 agent_type  $3 make-transcript(yes|no)  $4 layout(plain|workflows)
  _log="$1"; mkdir -p "$(dirname "$_log")"; : > "$_log"
  # The project dir must be unique per case. Deriving it from the log path guarantees that: a shared
  # dir would let one case's transcript satisfy another case's lookup and mask a real MISS.
  _proj="$(dirname "$(dirname "$_log")")/proj"; _sid="sess1"; _aid="a1"
  mkdir -p "$_proj"
  if [ "$3" = "yes" ]; then
    if [ "$4" = "workflows" ]; then
      mkdir -p "$_proj/$_sid/subagents/workflows/wf1"
      : > "$_proj/$_sid/subagents/workflows/wf1/agent-$_aid.jsonl"
    else
      mkdir -p "$_proj/$_sid/subagents"
      : > "$_proj/$_sid/subagents/agent-$_aid.jsonl"
    fi
  fi
  fire "$_log" C1 '{"hook_event_name":"PreToolUse","tool_name":"Edit","session_id":"'$_sid'","cwd":"/x"}'
  fire "$_log" C3 '{"hook_event_name":"PreToolUse","tool_name":"Edit","agent_id":"'$_aid'","agent_type":"'$2'","session_id":"'$_sid'","transcript_path":"'$_proj'/main.jsonl","cwd":"/x"}'
  fire "$_log" C3 '{"hook_event_name":"PostToolUse","tool_name":"Edit","agent_id":"'$_aid'","agent_type":"'$2'","session_id":"'$_sid'","transcript_path":"'$_proj'/main.jsonl","cwd":"/x"}'
}

L3="$tmp/c3ok/.claude/hook-probe.jsonl"
build_c3 "$L3" coder yes workflows
OUT=$(bash "$VERIFY" "$L3" 2>&1)
printf '%s' "$OUT" | grep -q 'HOOK_PROBE C3 hooks_fire=yes'       && ok "verify: C3 hooks_fire=yes"        || no "verify: C3 hooks_fire=yes"
printf '%s' "$OUT" | grep -q 'HOOK_PROBE C3 enforce_would_run=yes' && ok "verify: C3 enforce_would_run=yes" || no "verify: C3 enforce_would_run=yes"
printf '%s' "$OUT" | grep -q 'transcript_glob=match'               && ok "verify: C3 transcript resolves via workflows/ glob" || no "verify: C3 transcript resolves via workflows/ glob"
printf '%s' "$OUT" | grep -q 'RECOMMEND hook_verified=true'        && ok "verify: all three green => recommend true" || no "verify: all three green => recommend true"

# --- verifier: the silent-bypass case (the one the old smoke test could not see) --------------------
L4="$tmp/c3bypass/.claude/hook-probe.jsonl"
build_c3 "$L4" "stefano-vibe-coding:coder" yes workflows
OUT=$(bash "$VERIFY" "$L4" 2>&1)
printf '%s' "$OUT" | grep -q 'HOOK_PROBE C3 hooks_fire=yes'       && ok "verify: bypass case still reports hooks DO fire" || no "verify: bypass case still reports hooks DO fire"
printf '%s' "$OUT" | grep -q 'HOOK_PROBE C3 enforce_would_run=no' && ok "verify: plugin-scoped agent_type => enforce_would_run=no" || no "verify: plugin-scoped agent_type => enforce_would_run=no"
printf '%s' "$OUT" | grep -q 'RECOMMEND hook_verified=false'      && ok "verify: bypass case => recommend false" || no "verify: bypass case => recommend false"
printf '%s' "$OUT" | grep -q 'inert while appearing installed'    && ok "verify: bypass reason names the silent failure" || no "verify: bypass reason names the silent failure"

# --- verifier: transcript miss => fail-open in silence ----------------------------------------------
L5="$tmp/c3miss/.claude/hook-probe.jsonl"
build_c3 "$L5" coder no plain
OUT=$(bash "$VERIFY" "$L5" 2>&1)
printf '%s' "$OUT" | grep -q 'transcript_glob=miss'          && ok "verify: absent transcript => miss" || no "verify: absent transcript => miss"
printf '%s' "$OUT" | grep -q 'RECOMMEND hook_verified=false' && ok "verify: transcript miss => recommend false" || no "verify: transcript miss => recommend false"

# --- verifier: C3 never fires => the ADR-0016 blocker is real ---------------------------------------
L6="$tmp/c3none/.claude/hook-probe.jsonl"; mkdir -p "$(dirname "$L6")"; : > "$L6"
fire "$L6" C1 '{"hook_event_name":"PreToolUse","tool_name":"Edit","session_id":"s","cwd":"/x"}'
OUT=$(bash "$VERIFY" "$L6" 2>&1)
printf '%s' "$OUT" | grep -q 'HOOK_PROBE C3 hooks_fire=no'   && ok "verify: no C3 events => hooks_fire=no" || no "verify: no C3 events => hooks_fire=no"
printf '%s' "$OUT" | grep -q 'RECOMMEND hook_verified=false' && ok "verify: hooks do not fire => recommend false" || no "verify: hooks do not fire => recommend false"

# --- regression: bare SubagentStop rows must not poison the agent_type selection ----------------------
# The live run of 2026-07-10 found this the hard way. A bare SubagentStop fires after nearly every
# main-loop turn carrying agent_id plus an EMPTY-STRING agent_type. Empty string is non-null, so the
# old `.agent_type != null | head -1` picked it and reported "(absent)" for a context that actually
# contained a coder. The verdict was right by luck and the reason was wrong.
L8="$tmp/spurious/.claude/hook-probe.jsonl"; mkdir -p "$(dirname "$L8")"; : > "$L8"
_proj8="$tmp/spurious/proj"; mkdir -p "$_proj8/s8/subagents/workflows/wf1"
: > "$_proj8/s8/subagents/workflows/wf1/agent-real.jsonl"
# the spurious row lands FIRST, exactly as it does in a real session
fire "$L8" C3 '{"hook_event_name":"SubagentStop","agent_id":"bogus","agent_type":"","session_id":"s8","transcript_path":"'$_proj8'/main.jsonl","cwd":"/x"}'
fire "$L8" C3 '{"hook_event_name":"PreToolUse","tool_name":"Edit","agent_id":"real","agent_type":"coder","session_id":"s8","transcript_path":"'$_proj8'/main.jsonl","cwd":"/x"}'
OUT=$(bash "$VERIFY" "$L8" 2>&1)
printf '%s' "$OUT" | grep -q 'HOOK_PROBE C3 enforce_would_run=yes' \
  && ok "verify: empty-string agent_type does not mask a real coder" \
  || no "verify: empty-string agent_type does not mask a real coder"
printf '%s' "$OUT" | grep -q 'transcript_glob=match' \
  && ok "verify: transcript resolved from the REAL agent_id, not the bogus one" \
  || no "verify: transcript resolved from the REAL agent_id, not the bogus one"
printf '%s' "$OUT" | grep -q 'bare SubagentStop rows' \
  && ok "verify: spurious SubagentStop rows are counted and disclosed" \
  || no "verify: spurious SubagentStop rows are counted and disclosed"

# both agent types present in one context: the coder must still win the enforce check
L9="$tmp/mixed/.claude/hook-probe.jsonl"; mkdir -p "$(dirname "$L9")"; : > "$L9"
_proj9="$tmp/mixed/proj"; mkdir -p "$_proj9/s9/subagents/workflows/wf1"
: > "$_proj9/s9/subagents/workflows/wf1/agent-w.jsonl"
fire "$L9" C3 '{"hook_event_name":"PreToolUse","tool_name":"Edit","agent_id":"w","agent_type":"workflow-subagent","session_id":"s9","transcript_path":"'$_proj9'/main.jsonl","cwd":"/x"}'
fire "$L9" C3 '{"hook_event_name":"PreToolUse","tool_name":"Edit","agent_id":"w","agent_type":"coder","session_id":"s9","transcript_path":"'$_proj9'/main.jsonl","cwd":"/x"}'
OUT=$(bash "$VERIFY" "$L9" 2>&1)
printf '%s' "$OUT" | grep -q 'enforce_would_run=yes' && ok "verify: coder among several agent_types => enforce yes" || no "verify: coder among several agent_types => enforce yes"
printf '%s' "$OUT" | grep -q 'agent_types=.*coder' && ok "verify: reports the full agent_type set" || no "verify: reports the full agent_type set"

# default workflow subagent alone => still false, with the actionable reason
L10="$tmp/defonly/.claude/hook-probe.jsonl"; mkdir -p "$(dirname "$L10")"; : > "$L10"
_proj10="$tmp/defonly/proj"; mkdir -p "$_proj10/s10/subagents/workflows/wf1"
: > "$_proj10/s10/subagents/workflows/wf1/agent-w.jsonl"
fire "$L10" C3 '{"hook_event_name":"PreToolUse","tool_name":"Edit","agent_id":"w","agent_type":"workflow-subagent","session_id":"s10","transcript_path":"'$_proj10'/main.jsonl","cwd":"/x"}'
OUT=$(bash "$VERIFY" "$L10" 2>&1)
printf '%s' "$OUT" | grep -q 'RECOMMEND hook_verified=false' && ok "verify: default workflow subagent alone => false" || no "verify: default workflow subagent alone => false"
printf '%s' "$OUT" | grep -q "agentType: 'coder'" && ok "verify: reason names the actual fix (pass agentType)" || no "verify: reason names the actual fix (pass agentType)"

# --- verifier: C4 stop / subagent-stop reporting -----------------------------------------------------
L7="$tmp/c4/.claude/hook-probe.jsonl"; mkdir -p "$(dirname "$L7")"; : > "$L7"
fire "$L7" C4 '{"hook_event_name":"Stop","session_id":"s","cwd":"/x"}'
fire "$L7" C4 '{"hook_event_name":"SubagentStop","agent_id":"a","agent_type":"coder","session_id":"s","cwd":"/x"}'
OUT=$(bash "$VERIFY" "$L7" 2>&1)
printf '%s' "$OUT" | grep -q 'HOOK_PROBE C4 stop_hook_fired=yes'      && ok "verify: C4 Stop hook reported" || no "verify: C4 Stop hook reported"
printf '%s' "$OUT" | grep -q 'HOOK_PROBE C4 subagent_stop_fired=yes'  && ok "verify: C4 SubagentStop reported" || no "verify: C4 SubagentStop reported"

# --- summary -----------------------------------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
