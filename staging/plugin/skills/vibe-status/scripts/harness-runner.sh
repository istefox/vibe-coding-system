#!/bin/bash
# harness-runner: invoke a single harness with timeout.
# Output format: first line "RC=<rc> DUR=<sec>s", then harness stdout/stderr.
# RC=0   → harness passed (exit 0)
# RC=1   → harness failed (exit 1)
# RC=124 → timeout
# RC=127 → file not found / no arg
# 3.2-clean, fail-graceful.

H="$1"; TMO="${2:-12}"

[ -z "$H" ] && { echo "RC=127 DUR=0s"; echo "ERROR: no harness arg"; exit 0; }
[ ! -f "$H" ] && { echo "RC=127 DUR=0s"; echo "ERROR: harness file not found: $H"; exit 0; }

START=$(date +%s)
OUT=$(mktemp)

if command -v timeout >/dev/null 2>&1; then
  timeout "$TMO" bash "$H" >"$OUT" 2>&1
  RC=$?
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout "$TMO" bash "$H" >"$OUT" 2>&1
  RC=$?
else
  bash "$H" >"$OUT" 2>&1 &
  P=$!
  ( sleep "$TMO"; kill -0 "$P" 2>/dev/null && kill -9 "$P" 2>/dev/null ) &
  W=$!
  wait "$P" 2>/dev/null; RC=$?
  kill -9 "$W" 2>/dev/null; wait "$W" 2>/dev/null
  [ "$RC" -eq 137 ] && RC=124
fi

END=$(date +%s)
DUR=$((END - START))
echo "RC=$RC DUR=${DUR}s"
cat "$OUT"
rm -f "$OUT"
exit 0
