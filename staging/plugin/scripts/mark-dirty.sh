#!/bin/bash
# PostToolUse hook on Edit|Write. Records THAT a write happened — the marker's existence, which
# is what arms stop-gate.sh — and, since ADR-0137 D1, also WHICH path was written, as the
# marker's content. It records; stop-gate.sh decides. Fail-open on every branch, exit 0 always.
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0
mkdir -p "$DIR" 2>/dev/null || true
F="$DIR/$SID.dirty"
# Create if absent, NEVER truncate. The previous `: >` destroyed every path recorded earlier in
# the session on each new write; `: >>` creates the file and appends nothing.
: >> "$F" 2>/dev/null || true
# tool_input.file_path — the field post-write-check.sh reads on this same event, in the jq form
# its sibling auto-format.sh uses. A failed parse yields "" and is NOT an error: the marker
# still exists, and a marker carrying no paths arms the gate (ADR-0137 D1).
P=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$P" ] && exit 0
# A path containing a newline cannot be one record line. Keep it anyway — R-06 discards none —
# on a single line, newlines as spaces and prefixed with one space so it cannot begin with '/'.
# stop-gate.sh treats any line not beginning with '/' as unmatchable, so such a write arms.
case "$P" in *'
'*) P=" $(printf '%s' "$P" | tr '\n' ' ')" ;; esac
# Deduplicated so a long session cannot grow the file without bound. -F literal, -x whole line,
# -- so a path beginning with '-' is not read as an option.
grep -F -x -q -- "$P" "$F" 2>/dev/null || printf '%s\n' "$P" >> "$F" 2>/dev/null || true
exit 0
