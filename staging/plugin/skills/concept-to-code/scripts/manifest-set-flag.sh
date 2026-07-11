#!/usr/bin/env bash
# concept-to-code: manifest-set-flag.sh — bash 3.2-clean
# Atomically set a top-level boolean flag in a manifest (unquoted, no indent).
# Usage: manifest-set-flag.sh <manifest-path> <key> <true|false>
#   key: top-level flag, e.g. anonymize
# Exit: 0 ok | 1 usage/bad-value | 2 not found | 3 key not present | 4 write failed
set -u

if [ "$#" != "3" ]; then
  echo "usage: manifest-set-flag.sh <manifest-path> <key> <true|false>" >&2
  exit 1
fi

MANIFEST="$1"
KEY="$2"
VAL="$3"

# Validate value is exactly true or false (no quotes, no other strings).
if [ "$VAL" != "true" ] && [ "$VAL" != "false" ]; then
  echo "manifest-set-flag: value must be 'true' or 'false', got '$VAL'" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "manifest-set-flag: not found: $MANIFEST" >&2
  exit 2
fi

# Verify the top-level key line exists (zero indent, no leading spaces).
if ! grep -q "^${KEY}: " "$MANIFEST"; then
  echo "manifest-set-flag: key '${KEY}' not present at top level" >&2
  exit 3
fi

# Atomic replace: awk -v keeps KEY and VAL literal (no regex interpolation).
TMP=""
TMP2=""
trap 'rm -f "${TMP:-}" "${TMP2:-}"' EXIT
TMP="$(mktemp)"
awk -v k="$KEY" -v v="$VAL" '
  $0 ~ "^" k ": " { print k ": " v; next }
  { print }
' "$MANIFEST" > "$TMP" && mv "$TMP" "$MANIFEST" \
  || { echo "manifest-set-flag: write failed for $MANIFEST" >&2; exit 4; }

# Bump last_updated_at atomically.
NOW="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"
TMP2="$(mktemp)"
awk -v ts="$NOW" '
  /^last_updated_at: / { print "last_updated_at: \"" ts "\""; next }
  { print }
' "$MANIFEST" > "$TMP2" && mv "$TMP2" "$MANIFEST" \
  || { echo "manifest-set-flag: write failed for $MANIFEST" >&2; exit 4; }

exit 0
