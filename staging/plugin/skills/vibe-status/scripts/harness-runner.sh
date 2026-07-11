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

# Job control ON: the backgrounded harness becomes the leader of its own new process group
# (its PGID equals its own PID, $P) regardless of what $H itself forks — no external timeout/
# gtimeout binary required (issue #37; empirically verified: kills a forked grandchild cleanly,
# zero stray job-control text on stderr, RC=0/1/124/127 contract unchanged).
set -m
bash "$H" >"$OUT" 2>&1 &
P=$!
(
  sleep "$TMO"
  kill -0 "$P" 2>/dev/null || exit 0
  # Mark that THIS watchdog fired before killing, so only watchdog kills clamp to RC=124.
  # Without the marker, a harness that dies from its own signal (e.g. self-SIGTERM = 143)
  # would be mislabeled TIMEOUT instead of surfacing as a genuine error (issue #37 review).
  : > "$OUT.killed"
  kill -TERM -- "-$P" 2>/dev/null
  sleep 1
  kill -0 "$P" 2>/dev/null && kill -KILL -- "-$P" 2>/dev/null
) &
W=$!

wait "$P" 2>/dev/null; RC=$?
kill -9 "$W" 2>/dev/null; wait "$W" 2>/dev/null
set +m

# Clamp signal-terminated exits (128+signum) to the RC=124 timeout contract ONLY when this
# script's own watchdog issued the kill; a genuine signal death inside the harness passes
# through unclamped (matching the old timeout/gtimeout branches, which never clamped 143).
if [ "$RC" -gt 128 ] && [ -f "$OUT.killed" ]; then RC=124; fi
rm -f "$OUT.killed"

END=$(date +%s)
DUR=$((END - START))
echo "RC=$RC DUR=${DUR}s"
cat "$OUT"
rm -f "$OUT"
exit 0
