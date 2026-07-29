#!/bin/bash
# validate-frontmatter.sh — validate the YAML frontmatter of a path-scoped rules file.
#
# Inputs:
#   $1 = path to a rules file (or a temp file with planned content)
#
# Exits 0 if all checks pass; exits 1 with stderr diagnostic on first failure.
#
# Checks:
#   1. First line is exactly "---".
#   2. A line starting with "paths:" exists.
#   3. At least one quoted glob entry under paths: (matches '^  - "').
#   4. A closing "---" line exists (a second "---" before any non-frontmatter content).
#
# Bash 3.2-clean.
set -u

if [ $# -lt 1 ]; then
  echo "usage: validate-frontmatter.sh <rules-file>" >&2
  exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  printf 'validate-frontmatter: file not found: %s\n' "$FILE" >&2
  exit 1
fi

# xref-exempt: line 1 — a position inside the rules file being validated at run time, printed in
# this script's own error message. Not a reference into another file in this repository.
first=$(sed -n '1p' "$FILE")
if [ "$first" != "---" ]; then
  printf 'validate-frontmatter: missing opening --- at line 1\n' >&2
  exit 1
fi

if ! grep -q '^paths:' "$FILE"; then
  printf 'validate-frontmatter: missing paths: key\n' >&2
  exit 1
fi

if ! grep -q '^  - "' "$FILE"; then
  printf 'validate-frontmatter: no glob entry under paths:\n' >&2
  exit 1
fi

# Second "---" line — the frontmatter closer.
closing=$(grep -n '^---' "$FILE" | awk -F: 'NR==2{print $1}')
if [ -z "$closing" ]; then
  printf 'validate-frontmatter: no closing --- found\n' >&2
  exit 1
fi

exit 0
