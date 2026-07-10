#!/bin/bash
# refactor-snapshot pre-runs.sh — bash 3.2-clean
# Runs capture.sh PRE N times and verifies SHA256 determinism across runs.
# Usage: bash pre-runs.sh  (cwd must be project root, same contract as capture.sh)
# Env:   RFS_RUNS (default 3, range [1,10])
#        RFS_TIMEOUT, RFS_FILTER, RFS_FULL — passed through to each capture.sh invocation
# Exit:  0 = PASS (all runs identical, or N=1)
#        1 = invalid RFS_RUNS (non-numeric, <1, >10)
#        2 = UNVERIFIED (N>=2 and SHA256 differs across runs)
#        3 = capture.sh internal failure (missing test-cmd, timeout, etc.)
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Validate RFS_RUNS
N="${RFS_RUNS:-3}"

# Numeric check — bash 3.2 portable (no regex =~, use case)
case "$N" in
  ''|*[!0-9]*)
    echo "ERROR: RFS_RUNS=${N} invalid, must be integer in [1,10]" >&2
    exit 1
    ;;
esac

# Range check [1,10]
if [ "$N" -lt 1 ] || [ "$N" -gt 10 ]; then
  echo "ERROR: RFS_RUNS=${N} invalid, must be integer in [1,10]" >&2
  exit 1
fi

# Detect SHA256 tool (same logic as capture.sh)
if command -v shasum >/dev/null 2>&1; then
  SHA_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD="sha256sum"
else
  echo "ERROR: no sha256 tool found (need shasum or sha256sum)" >&2
  exit 1
fi

SNAP_FILE="$PWD/.claude/.refactor-snapshot.txt"

# Work dir for intermediate snapshots; cleaned on exit
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Run capture.sh PRE N times
i=1
while [ "$i" -le "$N" ]; do
  bash "$SCRIPT_DIR/capture.sh" PRE >"$TMP/capture.out" 2>"$TMP/capture.err"
  CAPTURE_EXIT=$?
  if [ "$CAPTURE_EXIT" -ne 0 ]; then
    echo "ERROR: capture.sh PRE failed" >&2
    echo "FAILED_RUN=$i CAPTURE_EXIT=$CAPTURE_EXIT" >&2
    cat "$TMP/capture.err" >&2
    exit 3
  fi
  # Copy snapshot produced by this run
  cp "$SNAP_FILE" "$TMP/run-${i}.snapshot"
  # Compute SHA256 of full snapshot file
  $SHA_CMD "$TMP/run-${i}.snapshot" | awk '{print $1}' > "$TMP/run-${i}.sha"
  i=$((i+1))
done

# N=1: no determinism check possible
if [ "$N" -eq 1 ]; then
  printf 'RUNS=1\n'
  printf 'STATUS=PASS\n'
  printf 'NOTE=determinism-check-skipped\n'
  exit 0
fi

# N>=2: compare all runs against run-1 SHA
SHA_1="$(cat "$TMP/run-1.sha")"

i=2
while [ "$i" -le "$N" ]; do
  SHA_I="$(cat "$TMP/run-${i}.sha")"
  if [ "$SHA_I" != "$SHA_1" ]; then
    printf 'RUNS=%s\n' "$N"
    printf 'STATUS=UNVERIFIED\n'
    printf 'DIVERGENT_RUN=%s\n' "$i"
    printf 'EXPECTED_SHA=%s\n' "$SHA_1"
    printf 'ACTUAL_SHA=%s\n' "$SHA_I"
    exit 2
  fi
  i=$((i+1))
done

# All runs identical
printf 'RUNS=%s\n' "$N"
printf 'STATUS=PASS\n'
printf 'FIRST_RUN_SHA=%s\n' "$SHA_1"
exit 0
