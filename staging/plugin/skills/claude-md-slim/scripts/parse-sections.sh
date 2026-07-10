#!/bin/bash
# parse-sections.sh — parse H2 sections from a CLAUDE.md file.
#
# Inputs:
#   $1 = absolute path to CLAUDE.md
#
# Output (stdout): TSV, one row per section. Columns:
#   heading<TAB>line_start<TAB>line_end
# Line numbers are 1-indexed. PREAMBLE is emitted for content before the first H2,
# or as the sole row if the file has no H2 headings.
#
# Bash 3.2-clean: no assoc arrays, no mapfile, no <<<, no process substitution.
set -u

if [ $# -lt 1 ]; then
  echo "usage: parse-sections.sh <claude-md-path>" >&2
  exit 1
fi

CLAUDE_MD="$1"

if [ ! -f "$CLAUDE_MD" ]; then
  echo "parse-sections.sh: file not found: $CLAUDE_MD" >&2
  exit 1
fi

# Edge: empty file → exit 0 with no output.
total=$(wc -l < "$CLAUDE_MD" | tr -d ' ')
if [ "$total" -eq 0 ]; then
  exit 0
fi

# Pass 1 — collect H2 headings (lines starting with "## ") and their line numbers.
HEADINGS_TMP=$(mktemp /tmp/psh-headings.XXXXXX)
lineno=0
while IFS= read -r rawline || [ -n "$rawline" ]; do
  lineno=$((lineno + 1))
  case "$rawline" in
    "## "*)
      heading=$(printf '%s' "$rawline" | sed 's/^## //' | sed 's/[[:space:]]*$//')
      printf '%s\t%d\n' "$heading" "$lineno" >> "$HEADINGS_TMP"
      ;;
  esac
done < "$CLAUDE_MD"

# Edge: no H2 headings at all → emit PREAMBLE row for the whole file.
if [ ! -s "$HEADINGS_TMP" ]; then
  printf 'PREAMBLE\t1\t%d\n' "$total"
  rm -f "$HEADINGS_TMP"
  exit 0
fi

# Pass 2 — emit rows. For each heading, end = next heading start - 1; the last heading
# ends at EOF (total). Emit a PREAMBLE row if first H2 is past line 1.
prev_heading=""
prev_start=0
while IFS=$'\t' read -r heading start; do
  if [ -n "$prev_heading" ]; then
    end=$((start - 1))
    printf '%s\t%d\t%d\n' "$prev_heading" "$prev_start" "$end"
  else
    if [ "$start" -gt 1 ]; then
      printf 'PREAMBLE\t1\t%d\n' "$((start - 1))"
    fi
  fi
  prev_heading="$heading"
  prev_start="$start"
done < "$HEADINGS_TMP"

# Emit the last section.
if [ -n "$prev_heading" ]; then
  printf '%s\t%d\t%d\n' "$prev_heading" "$prev_start" "$total"
fi

rm -f "$HEADINGS_TMP"
exit 0
