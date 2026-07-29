#!/bin/bash
# precompact-guard.sh v1.0 — PreCompact hook (issue #112; ADR-0058).
#
# WHAT THIS DOES. When a manifest's `current_step` is a chain dispatch state (a coder/reviewer
# agent is mid-flight — step_5_implementation / step_6_review on the Standard path,
# step_e2_execute on Express, step_h3_execute / step_h4_review on Hybrid), this hook forces a
# fresh handoff write to chain-history/<slug>.md (ADR-0021's chain-memory artifact — this feature
# builds on it, does not replace it) before compaction, and refuses the FIRST PreCompact of the
# cycle. The SECOND PreCompact in the same cycle proceeds regardless of manifest state.
#
# THE REFUSAL IS ONE-SHOT, ON PURPOSE, AND THIS IS THE PART THAT MUST NEVER BE "FIXED" INTO A
# PERSISTENT REFUSAL (ADR-0058 §D2). PreCompact fires because the context window is full. A hook
# that can refuse repeatedly does not protect the session, it STRANDS it: nothing can be evicted,
# and the run dies holding the exact state this hook exists to save. Refuse at most once per
# compaction cycle — a "cycle" here is operationally the run of consecutive PreCompact calls up to
# and including the first one this hook lets through. Do not add a retry loop, a counter above 1,
# or a config knob to refuse more than once per cycle: that is the failure mode this hook exists
# to avoid, not a missing feature.
#
# FAIL OPEN ON EVERY ERROR (§D3), and this is a SEPARATE guarantee from the one-shot rule (§D2).
# No manifest, unreadable manifest, jq missing, unwritable state dir, malformed JSON -> allow.
# Fail-open covers ERRORS; one-shot covers CORRECT operation. A hook that only failed open would
# still hang a healthy session in a refusal loop when current_step never leaves a dispatch state
# for two consecutive calls with a state dir that CAN be written — both guards are required.
#
# OCCUPANCY IS NOT READ HERE, ON PURPOSE (§D4). This hook's refusal decision is driven only by the
# mechanical fact of current_step; it never reads a heuristic occupancy figure and never compares
# against a threshold (CLAUDE_AUTOCOMPACT_PCT_OVERRIDE or otherwise). Occupancy is reported
# elsewhere (context-occupancy.sh / usage-daily-hint.sh) and never gates. Do not add a threshold
# comparison to this file — that would re-introduce exactly the reward-hacking-adjacent shape this
# roadmap has rejected three times already (ADR-0051 §D2, ADR-0053 §D2, ADR-0054 §D5): a heuristic
# deciding to block.
#
# Contract: exit 0 on every path. Empty stdout = allow. `{"decision":"block","reason":...}` =
# refuse this one PreCompact (documented top-level shape for PreCompact, unlike Stop/PreToolUse's
# hookSpecificOutput envelopes). State dir + audit log in the same shape as agent-command-scope.sh.
# Bash 3.2 clean: no associative arrays, no mapfile, no process substitution.
#
# transcript-scan-exempt: uses dirname(transcript_path) to locate the project memory dir. Never
#   opens the transcript.
set -u

DIR="${PRECOMPACT_GUARD_DIR:-$HOME/.claude/state/precompact-guard}"
LOG="$DIR/audit.log"

log_audit() {
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >>"$LOG" 2>/dev/null || true
}

INPUT=$(cat 2>/dev/null) || INPUT=""
[ -z "$INPUT" ] && exit 0

command -v jq >/dev/null 2>&1 || { log_audit "?" "allow" "jq missing"; exit 0; }

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

MKDIR_OK=0
mkdir -p "$DIR" 2>/dev/null && MKDIR_OK=1

# --- locate a project root: walk up from CWD looking for docs/manifests/ -----------------------
ROOT=""; d="$CWD"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -d "$d/docs/manifests" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done

if [ -z "$ROOT" ]; then
  log_audit "$SID" "allow" "no docs/manifests found walking up from $CWD"
  exit 0
fi

# Chain dispatch states across the Standard / Express / Hybrid chain paths (concept-to-code
# SKILL.md's step table): the states in which a coder/reviewer agent is actually mid-flight and
# chain state could be lost to a compaction. step_2_architecture (architect) is deliberately
# excluded — the architect writes only ADR/plan artifacts already tracked by git, not the
# hand-off-sensitive multi-turn coding state this hook exists to protect.
is_dispatch_state() {
  case "$1" in
    step_5_implementation|step_6_review|step_e2_execute|step_h3_execute|step_h4_review) return 0 ;;
    *) return 1 ;;
  esac
}

yval() { grep -aE "^$1:" "$2" 2>/dev/null | head -1 | sed -E "s/^$1:[[:space:]]*//; s/^\"//; s/\"\$//"; }

# --- force the handoff write for an in-progress, mid-dispatch manifest -------------------------
# Best-effort and idempotent: freshens chain-history/<slug>.md's STATE OF FACT header and appends
# one Event log line. Mirrors chain-memory-capture.sh (ADR-0021) minus the MEMORY.md pointer
# upsert, which is out of scope here — C3 only asks for the chain-history handoff record itself.
force_handoff_write() {
  _manifest="$1"
  [ -r "$_manifest" ] || return 0
  _base=$(basename "$_manifest")
  _slug=$(printf '%s' "$_base" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//; s/\.manifest\.yml$//')
  [ -z "$_slug" ] && return 0

  if [ -n "$TRANSCRIPT" ]; then
    _proj_dir=$(dirname "$TRANSCRIPT")
  else
    _enc=$(printf '%s' "$CWD" | tr '/' '-')
    _proj_dir="$HOME/.claude/projects/$_enc"
  fi
  _mem_dir="$_proj_dir/memory"
  _hist_dir="$_mem_dir/chain-history"
  _hist_file="$_hist_dir/$_slug.md"
  mkdir -p "$_hist_dir" 2>/dev/null || return 0

  _cur_step=$(yval current_step "$_manifest"); [ -z "$_cur_step" ] && _cur_step="?"
  _cur_status=$(yval status "$_manifest"); [ -z "$_cur_status" ] && _cur_status="?"
  _cur_path=$(yval chain_path "$_manifest"); [ -z "$_cur_path" ] && _cur_path="?"
  _next_action=$(yval next_action "$_manifest")
  _now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")

  _prev_events=""
  if [ -f "$_hist_file" ]; then
    _prev_events=$(awk 'f && /^- /{print} /^## Event log/{f=1}' "$_hist_file" 2>/dev/null)
  fi

  _tmp=$(mktemp "$_hist_dir/.${_slug}.XXXXXX" 2>/dev/null) || return 0
  {
    printf -- '---\n'
    printf 'node_type: chain-history\n'
    printf 'topic: %s\n' "$_slug"
    printf 'manifest: %s\n' "$_manifest"
    printf -- '---\n\n'
    printf '# Chain history — %s\n\n' "$_slug"
    printf '## STATE OF FACT\n'
    printf -- '- current_step: %s\n' "$_cur_step"
    printf -- '- status: %s\n' "$_cur_status"
    printf -- '- chain_path: %s\n' "$_cur_path"
    printf -- '- next_action: %s\n' "${_next_action:-(none)}"
    printf -- '- updated_at: %s\n\n' "$_now"
    printf '## Event log\n'
    [ -n "$_prev_events" ] && printf '%s\n' "$_prev_events"
    printf -- '- %s  precompact-guard forced handoff (current_step=%s)\n' "$_now" "$_cur_step"
  } >"$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 0; }
  mv -f "$_tmp" "$_hist_file" 2>/dev/null || rm -f "$_tmp" 2>/dev/null
}

DISPATCH_FOUND=0
for _m in "$ROOT"/docs/manifests/*.manifest.yml; do
  [ -e "$_m" ] || continue
  _step=$(yval current_step "$_m")
  _status=$(yval status "$_m")
  [ "$_status" = "in_progress" ] || continue
  if is_dispatch_state "$_step"; then
    DISPATCH_FOUND=1
    force_handoff_write "$_m"
  fi
done

if [ "$MKDIR_OK" -ne 1 ] || [ -z "$SID" ]; then
  log_audit "$SID" "allow" "cannot track one-shot state (mkdir_ok=$MKDIR_OK)"
  exit 0
fi

FLAG="$DIR/$SID.refused"

if [ "$DISPATCH_FOUND" -eq 0 ]; then
  rm -f "$FLAG" 2>/dev/null || true
  log_audit "$SID" "allow" "no in-progress dispatch-state manifest found under $ROOT"
  exit 0
fi

if [ -f "$FLAG" ]; then
  rm -f "$FLAG" 2>/dev/null || true
  log_audit "$SID" "allow" "one-shot already used this cycle — proceeding regardless of manifest state"
  exit 0
fi

if ! ( : >"$FLAG" ) 2>/dev/null; then
  log_audit "$SID" "allow" "cannot write one-shot flag — fail open rather than refuse unboundedly"
  exit 0
fi

log_audit "$SID" "block" "current_step is a dispatch state — one-shot refusal, handoff write forced"
REASON="precompact-guard: mid-flight chain state detected under $ROOT. The handoff record was force-saved to chain-history before this refusal. This is a ONE-SHOT refusal — the next PreCompact proceeds regardless of manifest state, so do not retry and do not wait for a different outcome; compaction will go through on its own next attempt."
printf '%s' "$REASON" | jq -R -s '{decision:"block", reason:.}' 2>/dev/null \
  || printf '{"decision":"block","reason":"precompact-guard: mid-flight chain state detected; handoff saved; this refusal is one-shot."}\n'
exit 0
