#!/usr/bin/env bash
# concept-to-code: detect-macos.sh — bash 3.2-clean
# Usage: detect-macos.sh <spec-path>
# Echoes MACOS_DETECTED or NOT_MACOS (exit 0 either way).
# Missing/empty file → NOT_MACOS.
#
# Strips markdown non-prose context BEFORE keyword-grepping to avoid false
# positives when SPEC.md mentions Swift/SwiftUI as keyword patterns inside
# tables or backtick code spans rather than as an actual macOS UI target.
# Stripped contexts:
#   1. fenced code blocks (lines between ``` or ~~~ fences)
#   2. table rows (first non-space char is '|')
#   3. inline backtick spans (text between backticks removed from surviving lines)
# Then greps surviving prose for macOS keywords (identical list to the prior
# inline grep, so detection parity on genuine prose is preserved).
set -u

if [ "$#" -ne "1" ]; then
  echo "usage: detect-macos.sh <spec-path>" >&2
  exit 1
fi

spec="$1"

if [ ! -f "$spec" ]; then
  echo "NOT_MACOS"
  exit 0
fi

# Pipeline (all bash 3.2-clean):
#  awk  — drop fenced-code lines via an in_fence toggle; drop table rows.
#  sed  — remove inline backtick spans on surviving lines.
#  grep — keyword scan on surviving prose.
prose="$(awk '
  {
    line = $0
    # Toggle on any line whose first non-whitespace run is a ``` or ~~~ fence
    # (optionally followed by an info string, e.g. ```swift).
    if (line ~ /^[[:space:]]*(```|~~~)/) {
      in_fence = !in_fence
      next            # drop the fence line itself (info string never leaks)
    }
    if (in_fence) { next }   # drop everything inside a fence

    # Drop markdown table rows: first non-space char is "|".
    stripped = line
    sub(/^[[:space:]]+/, "", stripped)
    if (substr(stripped, 1, 1) == "|") { next }

    print line
  }
' "$spec" \
  | sed -E 's/`[^`]*`//g')"

# Use printf to feed prose to grep (avoids here-strings <<< which are not
# bash 3.2-clean on all platforms).
if printf '%s\n' "$prose" \
     | grep -iEq 'macos|mac os|swiftui|appkit|mac app|menu bar'; then
  echo "MACOS_DETECTED"
else
  echo "NOT_MACOS"
fi

exit 0
