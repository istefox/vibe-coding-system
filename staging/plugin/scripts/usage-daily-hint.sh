#!/usr/bin/env bash
# usage-daily-hint.sh — Stop hook: compact daily usage diff at session end.
# Runs with a 4s timeout; fail-open on any error or timeout.
# Output appears as a note in the terminal transcript, not a block decision.
# Exit: 0 always.
set -u

SCRIPT="$HOME/.claude/scripts/usage-report.py"
[ ! -f "$SCRIPT" ] && exit 0

if command -v timeout >/dev/null 2>&1; then
  timeout 4s python3 "$SCRIPT" --compact 2>/dev/null || true
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout 4s python3 "$SCRIPT" --compact 2>/dev/null || true
else
  # No timeout available: run with background kill
  python3 "$SCRIPT" --compact 2>/dev/null &
  PID=$!
  sleep 4 && kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null &
  wait "$PID" 2>/dev/null || true
fi

exit 0
