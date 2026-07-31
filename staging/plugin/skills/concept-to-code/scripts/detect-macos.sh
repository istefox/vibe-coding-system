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
#
# TWO FALSE-POSITIVE CLASSES THE STRIP DOES NOT COVER (issue #232), both measured over the 36
# SPECs in this repository, where 6 tripped Gate 1c and NONE was a macOS UI target:
#
#   1. THE KEYWORD INSIDE A LONGER IDENTIFIER. `macos-ux` and `swiftui-pro` are SKILL NAMES, and
#      every meta-SPEC about this chain names them — so the gate fired on a whole CLASS of specs,
#      not on one unlucky sentence. The issue reported `macos-ux`; measuring found `swiftui-pro`
#      as well, and it survives the narrowing the issue proposed. Closed by word boundaries that
#      exclude `-` on BOTH sides: an identifier is not a word here.
#
#   2. THE KEYWORD NAMING THE HOST, NOT THE TARGET. `Bash 3.2 (macOS-portable, ...)` says which
#      shell, not which UI. Closed by requiring bare `macos`/`mac os` to sit within 60 characters
#      (either side, same sentence) of a UI noun. `swiftui`/`appkit`/`menu bar` need no such
#      company: naming one IS declaring a UI target.
#
# MEASURED IN BOTH DIRECTIONS before shipping. Corpus false positives 6 -> 0. Genuine macOS-UI
# specs still detected: a SwiftUI stack line, a menu bar utility, a "macOS app ... window,
# toolbar" objective, a "small macOS utility" with no framework named, an AppKit/NSWindow/HIG UI
# section. The ONE fixture deliberately NOT detected is a headless `macOS daemon that watches a
# directory` — Gate 1c offers window, navigation and menu design, which a daemon has no use for.
#
# KNOWN, and left: `mac app` never matches `macOS app` (only the literal "Mac app"), so it was
# already nearly dead before this change. `macOS app` is now caught by the proximity rule instead.
# Both are kept; neither is load-bearing on its own.
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

# The rule is built from NAMED parts rather than written as one wall: a regex nobody can read is
# a rule nobody can maintain, and both defects above lived inside an unreadable one-liner.
#   WB / WE   KEYWORD boundaries. `-` counts as part of a word here, so `macos-ux` and
#             `swiftui-pro` are single tokens and never match. This is class 1's fix.
#   NB / NE   NOUN boundaries. `-` is a SEPARATOR here, because `window-based` and `menu-driven`
#             are ordinary English and the noun inside them is still a noun. The two boundary
#             sets are deliberately different: using the keyword one for nouns lost
#             `A window-based macOS tool` — the two halves of this fix interfering, caught by
#             running the fixtures rather than by reading the regex.
#   STRONG    keywords that declare a UI target on their own
#   OSNAME    the bare platform name, which does NOT declare one on its own
#   UINOUN    the company OSNAME must keep, within one sentence, to count
WB='(^|[^[:alnum:]_-])'
WE='([^[:alnum:]_-]|$)'
NB='(^|[^[:alnum:]_])'
NE='([^[:alnum:]_]|$)'
STRONG='(swiftui|appkit|menu bar|mac app)'
OSNAME='mac ?os'
UINOUN='(app|window|menu|toolbar|interface|hig|settings|ui|utility)'
# NEAR absorbs the separator itself — either up to 60 non-sentence-ending chars finishing on a
# non-word char, or nothing at all. Two consuming boundaries cannot sit back to back: WE already
# ate the space in `macOS app`, so a following NB had none left and the match failed. Found by
# running the fixtures; the regex reads fine either way, which is the point.
# `(...)?`, never `(...|)`: BSD grep rejects an empty alternative outright with
# "empty (sub)expression", and the failure is silent in the direction that matters — every file
# then returns NOT_MACOS, so a corpus sweep reports zero false positives while the rule is not
# running at all. Seen live while building this. Same trap the exit-3 conventions exist for.
NEAR='([^.]{0,60}[^[:alnum:]_])?'
MACOS_RE="${WB}${STRONG}${WE}|${WB}${OSNAME}${WE}${NEAR}${UINOUN}${NE}|${NB}${UINOUN}${NE}${NEAR}${OSNAME}${WE}"

# Use printf to feed prose to grep (avoids here-strings <<< which are not
# bash 3.2-clean on all platforms).
if printf '%s\n' "$prose" \
     | grep -iEq "$MACOS_RE"; then
  echo "MACOS_DETECTED"
else
  echo "NOT_MACOS"
fi

exit 0
