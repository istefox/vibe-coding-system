#!/bin/bash
# enumerate-sources.sh — list source files for deep-refactor audit
# Usage: enumerate-sources.sh <root> [<path-override>]
#   <root>           path to the root of a git repository
#   <path-override>  optional scope restriction, two supported forms:
#                       - directory/path literal (no *, ?, [ characters): restricts to that
#                         exact path or anything nested below it, e.g. "Sources" or "Sources/Foo"
#                       - shell glob (contains *, ?, or [): matched against the full relative
#                         path via bash case-pattern matching, e.g. "*.swift", "Sources/*.swift"
#                         (matches across "/" -- case matching operates on the literal string,
#                         not filesystem pathname expansion)
#
# Excludes: *.xcarchive, DerivedData/, Pods/, .build/, *.generated.swift
# Output: one path per line (relative to <root>); empty output if no files match
# Exit 1 if <root> is not a git repository
#
# Bash 3.2-clean: no assoc arrays, no mapfile, no process substitution, no <<<, no ${v^^}
set -u

if [ $# -lt 1 ]; then
  printf 'usage: enumerate-sources.sh <root> [<path-override>]\n' >&2
  exit 1
fi

SCRIPT_ROOT="$1"
PATH_OVERRIDE="${2:-}"
TMP_SCOPED=""

# Validate <root> is a git repository
if ! git -C "$SCRIPT_ROOT" rev-parse --git-dir > /dev/null 2>&1; then
  printf 'error: %s is not a git repository\n' "$SCRIPT_ROOT" >&2
  exit 1
fi

# Use a temp file to hold the raw listing
TMP_LIST="$(mktemp)"

# Get all tracked files from git
git -C "$SCRIPT_ROOT" ls-files > "$TMP_LIST" 2>/dev/null

# Apply exclude globs via grep -v, write filtered result to another temp file
TMP_FILTERED="$(mktemp)"
trap 'rm -f "$TMP_LIST" "$TMP_FILTERED"; [ -n "$TMP_SCOPED" ] && rm -f "$TMP_SCOPED"' EXIT

grep -v -E \
  '(^|/)DerivedData/|^DerivedData$|(^|/)Pods/|^Pods$|(^|/)\.build/|^\.build$|\.xcarchive(/|$)|\.generated\.swift$' \
  "$TMP_LIST" > "$TMP_FILTERED"

# Apply optional path-override if provided. Two supported forms, both matched via bash's
# native `case` pattern engine (no external regex dialect, no ERE-injection surface):
#   1. Directory/path-literal prefix (no glob metacharacters, e.g. "Sources", "Sources/Foo"):
#      restricts to that exact path or anything nested below it.
#   2. Shell glob (contains *, ?, or [ -- e.g. "*.swift", "Sources/*.swift"): matched against
#      the full relative path. `case` pattern matching operates on a literal string (it does
#      not do filesystem pathname expansion), so `*` matches across `/` boundaries -- verified
#      directly against this repository's own bash: `case "Sources/App/x.swift" in *.swift)`
#      matches.
if [ -n "$PATH_OVERRIDE" ]; then
  TMP_SCOPED="$(mktemp)"
  # Strip a single trailing slash so "Sources/" and "Sources" behave identically.
  CLEAN_OVERRIDE="$(printf '%s' "$PATH_OVERRIDE" | sed 's|/$||')"
  case "$CLEAN_OVERRIDE" in
    *[\*\?\[]*)
      # Glob form: match every candidate path against the override pattern as-is.
      GLOB_PAT="$CLEAN_OVERRIDE"
      while IFS= read -r _f; do
        case "$_f" in
          $GLOB_PAT) printf '%s\n' "$_f" >> "$TMP_SCOPED" ;;
        esac
      done < "$TMP_FILTERED"
      ;;
    *)
      # Directory/path-literal form: match the override itself, or anything nested under it.
      DIR_PAT="$CLEAN_OVERRIDE"
      while IFS= read -r _f; do
        case "$_f" in
          "$DIR_PAT"|"$DIR_PAT"/*) printf '%s\n' "$_f" >> "$TMP_SCOPED" ;;
        esac
      done < "$TMP_FILTERED"
      ;;
  esac
  cat "$TMP_SCOPED"
  rm -f "$TMP_SCOPED"
else
  cat "$TMP_FILTERED"
fi

rm -f "$TMP_LIST" "$TMP_FILTERED"
