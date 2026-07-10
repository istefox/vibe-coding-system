#!/bin/bash
# refactor-snapshot diff.sh — bash 3.2-clean
# Compares PRE and POST snapshot files. Checks SHA256 + EXIT match.
# Reads optional override file .claude/refactor-snapshot-override.
# Usage: diff.sh [--baseline <file>] [--candidate <file>]
# Exit: 0 = PASS, 1 = FAIL, 2 = UNVERIFIED
# Stdout: STATUS= EXIT-MATCH= STDOUT-MATCH= STDERR-MATCH= OVERRIDE=
set -u

BASELINE="$PWD/.claude/.refactor-snapshot.txt"
CANDIDATE="$PWD/.claude/.refactor-snapshot.txt.post"
OVERRIDE_FILE="$PWD/.claude/refactor-snapshot-override"

# Parse optional args
while [ $# -gt 0 ]; do
  case "$1" in
    --baseline)  BASELINE="$2";  shift 2 ;;
    --candidate) CANDIDATE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Verify files exist
if [ ! -f "$BASELINE" ] || [ ! -f "$CANDIDATE" ]; then
  echo "STATUS=UNVERIFIED"
  echo "EXIT-MATCH=no"
  echo "STDOUT-MATCH=no"
  echo "STDERR-MATCH=no"
  echo "OVERRIDE=no"
  exit 2
fi

# Extract fields from a snapshot file
# Usage: extract_field <file> <field-prefix>
extract_field() {
  grep "^${2}=" "$1" | head -1 | cut -d= -f2-
}

B_EXIT=$(extract_field "$BASELINE"  "EXIT")
B_STDOUT=$(extract_field "$BASELINE" "STDOUT-SHA256")
B_STDERR=$(extract_field "$BASELINE" "STDERR-SHA256")

C_EXIT=$(extract_field "$CANDIDATE"  "EXIT")
C_STDOUT=$(extract_field "$CANDIDATE" "STDOUT-SHA256")
C_STDERR=$(extract_field "$CANDIDATE" "STDERR-SHA256")

# Validate format: EXIT must be integer, SHA256 must be 64 hex chars
validate_exit() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

validate_sha() {
  echo "$1" | grep -q '^[0-9a-f]\{64\}$'
}

if ! validate_exit "$B_EXIT" || ! validate_exit "$C_EXIT" \
   || ! validate_sha "$B_STDOUT" || ! validate_sha "$C_STDOUT" \
   || ! validate_sha "$B_STDERR" || ! validate_sha "$C_STDERR"; then
  echo "STATUS=UNVERIFIED"
  echo "EXIT-MATCH=no"
  echo "STDOUT-MATCH=no"
  echo "STDERR-MATCH=no"
  echo "OVERRIDE=no"
  exit 2
fi

# Compute per-channel match
if [ "$B_EXIT" = "$C_EXIT" ]; then EXIT_MATCH="yes"; else EXIT_MATCH="no"; fi
if [ "$B_STDOUT" = "$C_STDOUT" ]; then STDOUT_MATCH="yes"; else STDOUT_MATCH="no"; fi
if [ "$B_STDERR" = "$C_STDERR" ]; then STDERR_MATCH="yes"; else STDERR_MATCH="no"; fi

# Parse override file if present
OVERRIDE_SCOPE=""
OVERRIDE_REASON=""
OVERRIDE_ACTIVE="no"

if [ -f "$OVERRIDE_FILE" ]; then
  OV_REASON=""
  OV_SCOPE=""
  OV_EXPIRES=""

  while IFS= read -r ov_line; do
    # strip leading whitespace
    trimmed="${ov_line#"${ov_line%%[! ]*}"}"
    case "$trimmed" in
      "#"*|"") continue ;;
    esac
    case "$trimmed" in
      REASON:*) OV_REASON="${trimmed#REASON:}"; OV_REASON="${OV_REASON# }" ;;
      SCOPE:*)  OV_SCOPE="${trimmed#SCOPE:}";   OV_SCOPE="${OV_SCOPE# }" ;;
      EXPIRES:*) OV_EXPIRES="${trimmed#EXPIRES:}"; OV_EXPIRES="${OV_EXPIRES# }" ;;
    esac
  done < "$OVERRIDE_FILE"

  # Validate SCOPE
  SCOPE_VALID="no"
  case "$OV_SCOPE" in
    stdout|stderr|exit|all) SCOPE_VALID="yes" ;;
  esac

  # Validate EXPIRES (must be present and >= today)
  EXPIRES_VALID="no"
  if [ -n "$OV_EXPIRES" ]; then
    TODAY="$(date +%Y-%m-%d)"
    if [ "$TODAY" \< "$OV_EXPIRES" ] || [ "$TODAY" = "$OV_EXPIRES" ]; then
      EXPIRES_VALID="yes"
    fi
  fi

  if [ "$SCOPE_VALID" = "yes" ] && [ "$EXPIRES_VALID" = "yes" ] && [ -n "$OV_REASON" ]; then
    OVERRIDE_SCOPE="$OV_SCOPE"
    OVERRIDE_REASON="$OV_REASON"

    # Apply override: mark channels as matching if covered by scope
    case "$OVERRIDE_SCOPE" in
      all)
        EXIT_MATCH="yes"; STDOUT_MATCH="yes"; STDERR_MATCH="yes"
        OVERRIDE_ACTIVE="yes:${OVERRIDE_REASON}"
        ;;
      stdout)
        STDOUT_MATCH="yes"
        OVERRIDE_ACTIVE="yes:${OVERRIDE_REASON}"
        ;;
      stderr)
        STDERR_MATCH="yes"
        OVERRIDE_ACTIVE="yes:${OVERRIDE_REASON}"
        ;;
      exit)
        EXIT_MATCH="yes"
        OVERRIDE_ACTIVE="yes:${OVERRIDE_REASON}"
        ;;
    esac
  fi
fi

# Compute final STATUS
if [ "$EXIT_MATCH" = "yes" ] && [ "$STDOUT_MATCH" = "yes" ] && [ "$STDERR_MATCH" = "yes" ]; then
  STATUS="PASS"
  FINAL_EXIT=0
else
  STATUS="FAIL"
  FINAL_EXIT=1
fi

echo "STATUS=$STATUS"
echo "EXIT-MATCH=$EXIT_MATCH"
echo "STDOUT-MATCH=$STDOUT_MATCH"
echo "STDERR-MATCH=$STDERR_MATCH"
echo "OVERRIDE=$OVERRIDE_ACTIVE"
exit $FINAL_EXIT
