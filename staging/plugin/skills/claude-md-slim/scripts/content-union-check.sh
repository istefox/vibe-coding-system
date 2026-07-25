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
#     merge-dedup (SKILL.md Step 7.4) legitimately reduces occurrence counts by design.
#     See SKILL.md "Content-preservation exemptions" and ADR-0032 D2 for the full rationale.
#
# --global DUPLICATE sections (ADR-0044, issue #57):
#   Step 3/4 delete a section flagged DUPLICATE from the trimmed CLAUDE.md, on the reasoning that
#   its content already lives in ~/.claude/CLAUDE.md. Those lines are then in no output file, so
#   before these options existed the gate ABORTED every --global run that found a duplicate. (The
#   issue that filed this said it "passed by accident" — true only before ADR-0032 replaced
#   substring matching with whole-line matching.) --duplicate-lines names the removed lines,
#   --duplicate-source names the file they are claimed to survive in; a line is preserved if it is
#   in the local union OR (listed as removed AND present whole-line in the source).
#   The source file is deliberately NOT appended to the union: that would let ANY lost line be
#   excused by an identical line happening to sit in the global CLAUDE.md, turning a false abort
#   into a false pass on this project's own hard gate. See ADR-0044 Alternatives.
#
# Inputs:
#   [--duplicate-lines <file>] [--duplicate-source <path>]   optional; both together or neither
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

USAGE='usage: content-union-check.sh [--duplicate-lines <file> --duplicate-source <path>] <original> <output1> [<output2> ...]'

DUP_LINES=""
DUP_SOURCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --duplicate-lines)
      [ $# -ge 2 ] || { printf '%s\n' "$USAGE" >&2; exit 1; }
      DUP_LINES="$2"; shift 2 ;;
    --duplicate-source)
      [ $# -ge 2 ] || { printf '%s\n' "$USAGE" >&2; exit 1; }
      DUP_SOURCE="$2"; shift 2 ;;
    --) shift; break ;;
    -*) printf 'content-union-check: unknown option: %s\n%s\n' "$1" "$USAGE" >&2; exit 1 ;;
    *) break ;;
  esac
done

# Both or neither. One alone is a caller bug that would otherwise degrade into a silent
# half-check: the exemption would be declared and never verified, or verified against nothing.
if [ -n "$DUP_LINES" ] && [ -z "$DUP_SOURCE" ]; then
  printf 'content-union-check: --duplicate-lines requires --duplicate-source\n%s\n' "$USAGE" >&2
  exit 1
fi
if [ -n "$DUP_SOURCE" ] && [ -z "$DUP_LINES" ]; then
  printf 'content-union-check: --duplicate-source requires --duplicate-lines\n%s\n' "$USAGE" >&2
  exit 1
fi
if [ -n "$DUP_LINES" ] && [ ! -f "$DUP_LINES" ]; then
  printf 'content-union-check: duplicate-lines file not found: %s\n' "$DUP_LINES" >&2
  exit 1
fi
if [ -n "$DUP_SOURCE" ] && [ ! -f "$DUP_SOURCE" ]; then
  printf 'content-union-check: duplicate-source not found: %s\n' "$DUP_SOURCE" >&2
  exit 1
fi

if [ $# -lt 2 ]; then
  printf '%s\n' "$USAGE" >&2
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

# Trailing-whitespace-normalised copies of the two duplicate-exemption inputs, so the comparison
# below matches the union's own semantics rather than a stricter accidental one.
DUP_LINES_TMP=""
DUP_SOURCE_TMP=""
if [ -n "$DUP_LINES" ]; then
  DUP_LINES_TMP=$(mktemp /tmp/content-union-dup-lines.XXXXXX)
  DUP_SOURCE_TMP=$(mktemp /tmp/content-union-dup-src.XXXXXX)
  sed 's/[[:space:]]*$//' "$DUP_LINES" > "$DUP_LINES_TMP"
  sed 's/[[:space:]]*$//' "$DUP_SOURCE" > "$DUP_SOURCE_TMP"
fi

missing=0
in_global=0
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
  if grep -qxF -- "$trimmed_line" "$UNION_TMP" 2>/dev/null; then
    continue
  fi
  # Not in any local output. It is preserved only if the pipeline declared it removed as a
  # --global DUPLICATE *and* it is actually there in the source. Both conditions, in that order:
  # the declaration alone is a claim, not evidence.
  if [ -n "$DUP_LINES_TMP" ] \
     && grep -qxF -- "$trimmed_line" "$DUP_LINES_TMP" 2>/dev/null \
     && grep -qxF -- "$trimmed_line" "$DUP_SOURCE_TMP" 2>/dev/null; then
    in_global=$((in_global + 1))
    continue
  fi
  missing=$((missing + 1))
done < "$ORIGINAL"

rm -f "$UNION_TMP" "$DUP_LINES_TMP" "$DUP_SOURCE_TMP"

if [ "$in_global" -gt 0 ]; then
  printf '%d lines preserved in %s as --global duplicates (not in any local output)\n' \
    "$in_global" "$DUP_SOURCE" >&2
fi

if [ "$missing" -gt 0 ]; then
  printf '%d lines from original not found in any output file\n' "$missing" >&2
  exit 1
fi
exit 0
