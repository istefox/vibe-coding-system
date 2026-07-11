#!/usr/bin/env bash
# concept-to-code: manifest-set-gate.sh — bash 3.2-clean
# Atomically set a hitl_gate's status/approved_at/notes in a manifest, avoiding the
# "file modified since read" error from mixing bash writes + Edit-tool writes.
# Usage: manifest-set-gate.sh <manifest-path> <gate-num> <status> [<notes>]
#   status e.g. approved | rejected | ran_review ; notes optional (empty -> null)
# Exit: 0 ok | 1 usage | 2 not found | 3 gate not present
set -u

if [ "$#" -lt "3" ] || [ "$#" -gt "4" ]; then
  echo "usage: manifest-set-gate.sh <manifest-path> <gate-num> <status> [notes]" >&2
  exit 1
fi

MANIFEST="$1"
GATE="$2"
STATUS="$3"
NOTES="${4:-}"

if [ ! -f "$MANIFEST" ]; then
  echo "manifest-set-gate: not found: $MANIFEST" >&2
  exit 2
fi

if ! grep -q "^  - gate: ${GATE}$" "$MANIFEST"; then
  echo "manifest-set-gate: gate '${GATE}' not present" >&2
  exit 3
fi

NOW="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"
TMP="$(mktemp)"

# Walk the hitl_gates list. While inside the target gate block, rewrite its
# status/approved_at/notes lines. The block ends at the next "  - gate:" line.
awk -v g="$GATE" -v st="$STATUS" -v ts="$NOW" -v notes="$NOTES" '
  $0 ~ "^  - gate: " g "$" { ingate=1; print; next }
  /^  - gate: / && ingate==1 { ingate=0 }
  ingate==1 && /^    status: / { print "    status: \"" st "\""; next }
  ingate==1 && /^    approved_at: / { print "    approved_at: \"" ts "\""; next }
  ingate==1 && /^    notes: / {
    if (notes == "") { print "    notes: null" }
    else { print "    notes: \"" notes "\"" }
    next
  }
  { print }
' "$MANIFEST" > "$TMP" && mv "$TMP" "$MANIFEST"

# Bump last_updated_at
TMP2="$(mktemp)"
awk -v ts="$NOW" '
  /^last_updated_at: / { print "last_updated_at: \"" ts "\""; next }
  { print }
' "$MANIFEST" > "$TMP2" && mv "$TMP2" "$MANIFEST"

exit 0
