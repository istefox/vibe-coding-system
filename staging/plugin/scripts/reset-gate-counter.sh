#!/bin/bash
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0
rm -f "$DIR/$SID.count" 2>/dev/null || true
exit 0
