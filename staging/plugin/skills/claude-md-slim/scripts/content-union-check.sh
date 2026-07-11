#!/bin/bash
# content-union-check.sh — verify every non-empty, non-comment line of the original
# CLAUDE.md appears, as a WHOLE LINE, in the union of the proposed output files.
#
# Matching semantics (whole-line, set-based — ADR-0032):
#   - A line counts as PRESERVED if it appears, in full, as one line of at least one output
#     file, after trimming trailing whitespace from both sides. A text PREFIX match (e.g. the
#     original heading "## Git" appearing to "match" because an unrelated "## GitHub Actions"
#     heading survives in the union) does NOT count — see ADR-0032 for the reproduction.
#   - Per-line occurrence counts (multiplicity) between original and union are NOT compared.
#     This is a deliberate, documented exemption, not a gap: the invariant is a SET union
#     (ADR-0019 D6's own "union(output) ≥ union(input)" framing), and the pipeline's own
#     merge-dedup (SKILL.md Step 7.4) and --global duplicate-removal (Step 3/4) legitimately
#     reduce occurrence counts by design. See SKILL.md "Content-preservation exemptions" and
#     ADR-0032 D2 for the full rationale.
#
# Inputs:
#   $1     = path to the original CLAUDE.md
#   $2..$N = paths to output files (trimmed CLAUDE.md + rules files)
#
# Exit 0 if every original line is preserved (whole-line match) in at least one output file.
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

# Build the literal union: every output file, trailing-whitespace stripped per line,
# concatenated into one temp file. Whole-line matching then reduces to a single
# grep -qxF per original line against this one file.
UNION_TMP=$(mktemp /tmp/content-union-check.XXXXXX)
for outfile in "$@"; do
  sed 's/[[:space:]]*$//' "$outfile" >> "$UNION_TMP"
  # Force a file-boundary newline: BSD sed passes through a missing trailing newline,
  # which would merge this file's last line with the next file's first line and make
  # both spuriously fail the whole-line match. A blank extra line is harmless here.
  printf '\n' >> "$UNION_TMP"
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
  # Trim trailing whitespace before the whole-line comparison (tolerates trailing-space/tab
  # differences between the original and the output files).
  trimmed_line=$(printf '%s' "$line" | sed 's/[[:space:]]*$//')
  if ! grep -qxF -- "$trimmed_line" "$UNION_TMP" 2>/dev/null; then
    missing=$((missing + 1))
  fi
done < "$ORIGINAL"

rm -f "$UNION_TMP"

if [ "$missing" -gt 0 ]; then
  printf '%d lines from original not found in any output file\n' "$missing" >&2
  exit 1
fi
exit 0
