#!/usr/bin/env bash
# usage-daily-hint.sh v2.0 — Stop hook: compact daily usage diff + context occupancy at session
# end (issue #112; ADR-0058 Task 4 extends the pre-existing v1 usage note with occupancy).
#
# UNWIRED 2026-07-27 (found live in production, same night as deploy). additionalContext on a
# Stop event forces one extra turn ("the conversation continues so Claude can act on the
# feedback" -- see below): that is how the mechanism works, not a bug the stop_hook_active guard
# can remove. With this hook wired, EVERY turn in EVERY session pays that extra round-trip,
# forever, just to surface a usage hint. Decided not worth the permanent cost: removed from the
# Stop array in settings.json (both here and the deployed copy). The stop_hook_active guard stays
# in the script (still correct, still needed if this is ever re-wired) but the hook itself is
# inert until a settings.json entry exists again -- same "deployed but not wired" contract as
# test-write-scope.sh and precompact-guard.sh, just in the opposite direction (this one WAS wired
# and got un-wired, not left pending).
#
# CHANNEL, VERIFIED BEFORE RELYING ON IT (do not skip this if touching this file again). Per
# code.claude.com/docs/en/hooks, plain stdout on exit 0 is added to the model's context ONLY for
# UserPromptSubmit, UserPromptExpansion and SessionStart — every other event's stdout, Stop
# included, goes to the debug log only. v1 of this script printed plain text directly and was
# therefore the SAME class of no-op ADR-0039/ADR-0040 found in post-md-tells-hint.sh: whatever it
# printed was visible in --debug output, never to the model.
#
# The channel that DOES reach the model for Stop, per the same docs page: `decision: "block"`
# (blocks the stop) OR `hookSpecificOutput.additionalContext` used ALONE, with no `decision` field
# (non-blocking — "the conversation continues so Claude can act on the feedback"). This hook never
# blocks, so it uses the second, non-blocking shape exclusively.
#
# THIS DOES NOT CONTRADICT stop-gate.sh's OWN COMMENT ("hookSpecificOutput is not valid for Stop
# events and causes JSON validation errors"). That finding was about COMBINING hookSpecificOutput
# with a top-level `decision:"block"` in the SAME payload — stop-gate.sh needs `decision` to
# actually block, so it folds everything into `reason` instead of also trying hookSpecificOutput.
# This hook never emits `decision` at all, so the two payloads are never combined. Still: this is a
# documentation-based conclusion, not something live-tested against the real runtime in the
# environment that wrote it (checked 2026-07-26). Re-verify after a major Claude Code version bump,
# the same caveat this codebase already applies to every other runtime-behaviour fact
# (ADR-0016/ADR-0038) — if additionalContext ever again produces a validation error on Stop, the
# safe fallback is to drop back to plain stdout (human-visible in --debug, silent to the model,
# exactly v1's behaviour) rather than to `decision:"block"` (which would turn an advisory hint into
# a hang).
#
# CONSEQUENCE FOR THIS SCRIPT'S SHAPE: a JSON-only stdout contract means the daily usage line can
# no longer be printed directly — mixing plain text and JSON on the same stdout stream would make
# the JSON unparseable and silently drop BOTH pieces of information. usage-report.py's output is
# captured into a variable instead and folded into one JSON object at the end.
#
# OCCUPANCY IS REPORTED, NEVER GATED (§D4). There is no threshold comparison in this file and none
# should be added — see context-occupancy.sh's own header for why. This hook only ever emits
# additionalContext or nothing; it never emits `decision`.
#
# Fail-open on every path (§D3, matching every hook here): never blocks, always exits 0.
#
# transcript-scan-exempt: passes transcript_path to context-occupancy.sh and never reads the file
#   itself. The exemption travels with that one: if the delegate ever extracts a marker, this line
#   is wrong.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="${USAGE_REPORT_SCRIPT:-$HOME/.claude/scripts/usage-report.py}"
OCCUPANCY_SCRIPT="${CONTEXT_OCCUPANCY_SCRIPT:-$HERE/context-occupancy.sh}"

INPUT=$(cat 2>/dev/null) || INPUT=""

# stop_hook_active guard: this hook's own additionalContext triggers a re-invocation of the Stop
# event (the runtime lets Claude act on the injected context, which ends in another Stop), and
# with no guard that re-invocation re-emits additionalContext forever -- the exact loop this field
# exists to break. Exit silently and immediately, before the usage-report.py / occupancy work, on
# any re-invocation.
if [ -n "$INPUT" ] && command -v python3 >/dev/null 2>&1; then
  ACTIVE=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print('1' if d.get('stop_hook_active') else '')
except Exception:
    print('')
" 2>/dev/null)
  [ "$ACTIVE" = "1" ] && exit 0
fi

# capture_with_timeout <secs> <cmd...> — runs a command with a best-effort timeout, printing its
# stdout. Mirrors v1's fallback ladder (timeout -> gtimeout -> background+kill) so behaviour on a
# machine with neither binary is unchanged.
capture_with_timeout() {
  _t="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_t" "$@" 2>/dev/null
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$_t" "$@" 2>/dev/null
  else
    "$@" 2>/dev/null &
    _pid=$!
    ( sleep "$_t"; kill -0 "$_pid" 2>/dev/null && kill -9 "$_pid" 2>/dev/null ) &
    _wpid=$!
    wait "$_pid" 2>/dev/null
    kill -9 "$_wpid" 2>/dev/null; wait "$_wpid" 2>/dev/null
  fi
}

USAGE_LINE=""
if [ -f "$SCRIPT" ]; then
  USAGE_LINE=$(capture_with_timeout 4 python3 "$SCRIPT" --compact)
fi

PCT=""
if [ -n "$INPUT" ] && command -v python3 >/dev/null 2>&1; then
  TRANSCRIPT=$(printf '%s' "$INPUT" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('transcript_path') or '')
except Exception:
    print('')
" 2>/dev/null)
  if [ -n "$TRANSCRIPT" ] && [ -r "$OCCUPANCY_SCRIPT" ]; then
    PCT=$(bash "$OCCUPANCY_SCRIPT" "$TRANSCRIPT" 2>/dev/null)
    case "$PCT" in ''|*[!0-9]*) PCT="" ;; esac
  fi
fi

# Nothing to report -> silent allow, indistinguishable from v1's "no data yet" no-op.
if [ -z "$USAGE_LINE" ] && [ -z "$PCT" ]; then
  exit 0
fi

USAGE_LINE="$USAGE_LINE" PCT="$PCT" python3 -c "
import json, os

usage_line = os.environ.get('USAGE_LINE', '').strip()
pct = os.environ.get('PCT', '').strip()
parts = []
if usage_line:
    parts.append(usage_line)
if pct:
    parts.append(
        'context_occupancy=%s%% of window (from runtime-recorded transcript token usage; '
        'reported only, never used to gate anything — ADR-0058)' % pct
    )
if not parts:
    raise SystemExit(0)
ctx = chr(10).join(parts)
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'Stop', 'additionalContext': ctx}}))
" 2>/dev/null || true

exit 0
