#!/bin/bash
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
mkdir -p "$DIR" 2>/dev/null || true
exit 0
