#!/usr/bin/env bash
# concept-to-code: manifest-set-artifact.sh — bash 3.2-clean
# Atomically set an artifacts.<key> field in a manifest, avoiding the
# "file modified since read" error caused by mixing bash writes + Edit-tool writes.
# Usage: manifest-set-artifact.sh <manifest-path> <key> <value>
#   key in {spec, brainstorm, ux_blueprint, design_prompt, design, adr, arch, plan, project_claude_md}
# Exit: 0 ok | 1 usage | 2 not found | 3 key not present | 4 write failed
set -u

if [ "$#" != "3" ]; then
  echo "usage: manifest-set-artifact.sh <manifest-path> <key> <value>" >&2
  exit 1
fi

MANIFEST="$1"
KEY="$2"
VAL="$3"

if [ ! -f "$MANIFEST" ]; then
  echo "manifest-set-artifact: not found: $MANIFEST" >&2
  exit 2
fi

# Verify the key line exists (artifacts keys are indented 2 spaces).
if ! grep -q "^  ${KEY}: " "$MANIFEST"; then
  echo "manifest-set-artifact: key '${KEY}' not present under artifacts" >&2
  exit 3
fi

TMP=""
TMP2=""
trap 'rm -f "${TMP:-}" "${TMP2:-}"' EXIT
TMP="$(mktemp)"
# Replace the single artifacts line. awk -v keeps VAL literal (no regex interpolation).
awk -v k="$KEY" -v v="$VAL" '
  $0 ~ "^  " k ": " { print "  " k ": \"" v "\""; next }
  { print }
' "$MANIFEST" > "$TMP" && mv "$TMP" "$MANIFEST" \
  || { echo "manifest-set-artifact: write failed for $MANIFEST" >&2; exit 4; }

# Bump last_updated_at atomically in the same pass would need a second awk; keep simple:
NOW="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"
TMP2="$(mktemp)"
awk -v ts="$NOW" '
  /^last_updated_at: / { print "last_updated_at: \"" ts "\""; next }
  { print }
' "$MANIFEST" > "$TMP2" && mv "$TMP2" "$MANIFEST" \
  || { echo "manifest-set-artifact: write failed for $MANIFEST" >&2; exit 4; }

exit 0
