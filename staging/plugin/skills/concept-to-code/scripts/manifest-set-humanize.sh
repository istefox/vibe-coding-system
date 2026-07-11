#!/usr/bin/env bash
# concept-to-code: manifest-set-humanize.sh — bash 3.2-clean
# Set the humanize flag in a manifest, inserting it if absent.
# Usage: manifest-set-humanize.sh <manifest-path> <true|false>
# Exit: 0 ok | 1 usage/bad-value | 2 not found | 4 write failed
set -u

if [ "$#" != "2" ]; then
  echo "usage: manifest-set-humanize.sh <manifest-path> <true|false>" >&2
  exit 1
fi

MANIFEST="$1"
VAL="$2"

if [ "$VAL" != "true" ] && [ "$VAL" != "false" ]; then
  echo "manifest-set-humanize: value must be 'true' or 'false', got '$VAL'" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "manifest-set-humanize: not found: $MANIFEST" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SET_FLAG="$SCRIPT_DIR/manifest-set-flag.sh"

# Insert 'humanize: false' into the manifest if the key is absent.
# Anchors: try after 'anonymize:', then after 'topic_full_title:' (always present).
if ! grep -q "^humanize: " "$MANIFEST"; then
  TMP=$(mktemp)
  trap 'rm -f "$TMP"' EXIT
  if grep -q "^anonymize: " "$MANIFEST"; then
    awk '/^anonymize: / { print; print "humanize: false"; next } { print }' \
      "$MANIFEST" > "$TMP" && mv "$TMP" "$MANIFEST" \
      || { echo "manifest-set-humanize: insert failed" >&2; exit 4; }
  else
    awk '/^topic_full_title: / { print; print "humanize: false"; next } { print }' \
      "$MANIFEST" > "$TMP" && mv "$TMP" "$MANIFEST" \
      || { echo "manifest-set-humanize: insert failed" >&2; exit 4; }
  fi
fi

# Now set the value via the shared helper
bash "$SET_FLAG" "$MANIFEST" "humanize" "$VAL"
