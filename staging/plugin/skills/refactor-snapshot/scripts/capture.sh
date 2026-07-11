#!/bin/bash
# refactor-snapshot capture.sh — bash 3.2-clean
# Captures stdout/stderr/exit-code of .claude/test-cmd into a snapshot file.
# Usage: capture.sh <PRE|POST>
# Exit: 0 = success, 1 = missing test-cmd, 2 = timeout, 3 = usage error
set -u

ARG="${1:-}"
case "$ARG" in
  PRE)  SNAP_FILE="$PWD/.claude/.refactor-snapshot.txt" ;;
  POST) SNAP_FILE="$PWD/.claude/.refactor-snapshot.txt.post" ;;
  *)    echo "Usage: capture.sh <PRE|POST>" >&2; exit 3 ;;
esac

TEST_CMD_FILE="$PWD/.claude/test-cmd"
if [ ! -f "$TEST_CMD_FILE" ]; then
  echo "ERROR: .claude/test-cmd not found in $PWD" >&2
  exit 1
fi

# Detect SHA256 tool (BSD/macOS: shasum -a 256; GNU/Linux: sha256sum)
if command -v shasum >/dev/null 2>&1; then
  SHA_CMD="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  SHA_CMD="sha256sum"
else
  echo "ERROR: no sha256 tool found (need shasum or sha256sum)" >&2
  exit 1
fi

# Read test-cmd (strip comment lines and blank lines; preserve rest)
CMD_CONTENT=""
while IFS= read -r line; do
  # strip leading whitespace
  trimmed="${line#"${line%%[! ]*}"}"
  case "$trimmed" in
    "#"*|"") continue ;;
    *) CMD_CONTENT="$CMD_CONTENT$line
" ;;
  esac
done < "$TEST_CMD_FILE"

if [ -z "$CMD_CONTENT" ]; then
  echo "ERROR: .claude/test-cmd is empty or comment-only" >&2
  exit 1
fi

# Build command: RFS_FULL=1 ignores RFS_FILTER; else append RFS_FILTER if set
RFS_FULL="${RFS_FULL:-0}"
RFS_FILTER="${RFS_FILTER:-}"
RFS_TIMEOUT="${RFS_TIMEOUT:-120}"

if [ "$RFS_FULL" = "1" ] || [ -z "$RFS_FILTER" ]; then
  EXEC_CMD="$CMD_CONTENT"
else
  EXEC_CMD="$CMD_CONTENT $RFS_FILTER"
fi

# Create tmp dir for capturing output
TMP="$(mktemp -d)"
STDOUT_FILE="$TMP/stdout"
STDERR_FILE="$TMP/stderr"
EXIT_CODE=0

# Execute with timeout if available
if command -v timeout >/dev/null 2>&1; then
  timeout "$RFS_TIMEOUT" bash -c "$EXEC_CMD" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  EC=$?
  if [ $EC -eq 124 ]; then
    rm -rf "$TMP"
    echo "ERROR: test-cmd timed out after ${RFS_TIMEOUT}s" >&2
    exit 2
  fi
  EXIT_CODE=$EC
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout "$RFS_TIMEOUT" bash -c "$EXEC_CMD" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  EC=$?
  if [ $EC -eq 124 ]; then
    rm -rf "$TMP"
    echo "ERROR: test-cmd timed out after ${RFS_TIMEOUT}s" >&2
    exit 2
  fi
  EXIT_CODE=$EC
else
  echo "WARNING: timeout command not available; running without time limit" >&2
  bash -c "$EXEC_CMD" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  EXIT_CODE=$?
fi

# Compute SHA256 (hex only, no filename)
STDOUT_SHA=$($SHA_CMD "$STDOUT_FILE" | awk '{print $1}')
STDERR_SHA=$($SHA_CMD "$STDERR_FILE" | awk '{print $1}')

# Ensure .claude dir exists in project
mkdir -p "$(dirname "$SNAP_FILE")"

# Write snapshot file
{
  printf 'EXIT=%s\n' "$EXIT_CODE"
  printf 'STDOUT-SHA256=%s\n' "$STDOUT_SHA"
  printf 'STDERR-SHA256=%s\n' "$STDERR_SHA"
  printf -- '---STDOUT---\n'
  cat "$STDOUT_FILE"
  printf -- '---STDERR---\n'
  cat "$STDERR_FILE"
} > "$SNAP_FILE"

rm -rf "$TMP"
exit 0
