#!/bin/bash
# content-union-check.sh — verify every non-empty, non-comment line of the original
# CLAUDE.md appears in the union of the proposed output files.
#
# Inputs:
#   $1     = path to the original CLAUDE.md
#   $2..$N = paths to output files (trimmed CLAUDE.md + rules files)
#
# Exit 0 if every original line is preserved in at least one output file.
# Exit 1 with a stderr summary line: "<N> lines from original not found in any output file".
#
# Lines skipped from the check:
#   - empty / whitespace-only lines
#   - delegation-note comment lines starting with "<!--"
#
# Bash 3.2-clean.
set -u

if [ $# -lt 2 ]; then
  echo "usage: content-union-check.sh <original> <output1> [<output2> ...]" >&2
  exit 1
fi

ORIGINAL="$1"
shift

if [ ! -f "$ORIGINAL" ]; then
  printf 'content-union-check: original not found: %s\n' "$ORIGINAL" >&2
  exit 1
fi

# Pre-check that every output file exists; non-existent files are silently skipped
# in the inner loop, but a missing path is a likely caller bug worth flagging up.
for outfile in "$@"; do
  if [ ! -f "$outfile" ]; then
    printf 'content-union-check: output file not found: %s\n' "$outfile" >&2
    exit 1
  fi
done

missing=0
while IFS= read -r line || [ -n "$line" ]; do
  # Skip empty / whitespace-only lines.
  case "$line" in
    "" ) continue ;;
    *[!\ \	]*) : ;;
    *) continue ;;
  esac
  # Skip delegation-note comment lines.
  case "$line" in
    "<!--"*) continue ;;
  esac
  found=0
  for outfile in "$@"; do
    if grep -qF -- "$line" "$outfile" 2>/dev/null; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    missing=$((missing + 1))
  fi
done < "$ORIGINAL"

if [ "$missing" -gt 0 ]; then
  printf '%d lines from original not found in any output file\n' "$missing" >&2
  exit 1
fi
exit 0
