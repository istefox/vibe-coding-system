#!/bin/bash
# enumerate-sources.sh — list source files for deep-refactor audit
# Usage: enumerate-sources.sh <root> [<path-override>]
#   <root>           path to the root of a git repository
#   <path-override>  optional glob/dir prefix; restricts output to matching files
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

# Apply optional path-override if provided
if [ -n "$PATH_OVERRIDE" ]; then
  TMP_SCOPED="$(mktemp)"
  # Match files that start with the path-override prefix or match it as a glob prefix
  # Strip trailing slash from path-override for consistent matching
  CLEAN_OVERRIDE="$(printf '%s' "$PATH_OVERRIDE" | sed 's|/$||')"
  grep -E "^${CLEAN_OVERRIDE}(/|$)" "$TMP_FILTERED" > "$TMP_SCOPED" 2>/dev/null || true
  # Also try exact prefix match for glob-style (e.g. "Sources/Foo")
  # If scoped file is empty, try an anchored prefix fallback (no suffix anchor)
  if [ ! -s "$TMP_SCOPED" ]; then
    grep -E "^${CLEAN_OVERRIDE}" "$TMP_FILTERED" > "$TMP_SCOPED" 2>/dev/null || true
  fi
  cat "$TMP_SCOPED"
  rm -f "$TMP_SCOPED"
else
  cat "$TMP_FILTERED"
fi

rm -f "$TMP_LIST" "$TMP_FILTERED"
