#!/usr/bin/env bash
# concept-to-code: ui-file-detect.sh — bash 3.2-clean (issue #478, ADR-0160)
# Usage: git diff --name-only HEAD | ui-file-detect.sh
# Reads candidate paths on stdin, one per line. Echoes the UI-BEARING subset, one per line.
# Exit 0 always: this is a REPORTER (ADR-0048 §D5's convention), not a checker — Gate 5.05 branches
# on whether the output is empty, exactly as it already branches on the old bare extension match.
#
# WHY THIS EXISTS. Gate 5.05's trigger was `grep -E '\.(swift|html|css|tsx|jsx|vue)$'` — a bare
# extension match. Reported in the field: a feature with no view and no `import SwiftUI` anywhere in
# its diff still ran `ui-layout-audit` and recorded a seven-item accessibility/i18n checklist about
# UI work that does not exist. `.swift` is the extension this breaks on: a model, a service, a
# parser, a network client are all `.swift` and none of them is a view.
#
# THE WEB EXTENSIONS STAY EXTENSION-ONLY, ON PURPOSE. `.html`/`.css`/`.tsx`/`.jsx`/`.vue` are not
# given the same content check: a file with one of these extensions is, in every measured case here,
# a UI file — there is no equivalent of "a non-UI .swift file" for them (a `.css` file that is not
# about layout is not a documented or observed shape). Narrowing them without a measured
# false-positive would be guessing, the opposite of what closes issue #478.
#
# THE SAME SHAPE AS detect-macos.sh (ADR-0093): a keyword counts only near what it is supposed to
# be evidence of. There, `macos`/`mac os` needed a UI noun within 60 characters; here, `.swift`
# needs one of two things in the FILE'S OWN CONTENT, not merely in its name:
#   1. an import of a UI framework — SwiftUI, AppKit or UIKit
#   2. a declaration of a UI type — `View` (SwiftUI protocol conformance, `struct Foo: View`),
#      `NSView`/`NSViewController` (AppKit) or `UIView`/`UIViewController` (UIKit)
# Either is sufficient; neither is required of the web extensions above.
#
# A DELETED .swift FILE has no current content to read — `[ -f "$f" ]` fails and it is treated as
# NOT UI-bearing, the same direction "no measured false-positive" already favors: a deleted file
# cannot be missing a view.
set -u

is_ui_swift() {
  _f="$1"
  [ -f "$_f" ] || return 1
  grep -qE 'import[ \t]+(SwiftUI|AppKit|UIKit)([^A-Za-z0-9_]|$)' "$_f" 2>/dev/null && return 0
  grep -qE '(^|[^A-Za-z0-9_])(struct|class|final[ \t]+class)[ \t]+[A-Za-z0-9_]+[ \t]*:[^{]*\b(View|NSView|NSViewController|UIView|UIViewController)\b' "$_f" 2>/dev/null && return 0
  grep -qE '(^|[^A-Za-z0-9_])(class|final[ \t]+class)[ \t]+[A-Za-z0-9_]+[ \t]*:[^{]*\b(NSViewController|UIViewController)\b' "$_f" 2>/dev/null && return 0
  return 1
}

while IFS= read -r f || [ -n "$f" ]; do
  [ -n "$f" ] || continue
  case "$f" in
    *.html|*.css|*.tsx|*.jsx|*.vue)
      printf '%s\n' "$f" ;;
    *.swift)
      is_ui_swift "$f" && printf '%s\n' "$f" ;;
  esac
done
exit 0
