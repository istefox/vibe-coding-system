#!/bin/bash
# skill-extraction-preflight.sh — VCS-042/VCS-047/VCS-048 (issue: SKILL.md split).
#
# Before moving any block of a SKILL.md out into a references/*.md file, this reports what in
# the test suite is physically coupled to that block's text — so a split's blast radius is known
# BEFORE implementation, not discovered by a revert after (ADR-0172's pilot: Express+Hybrid,
# 203 lines, 3% of the file, still broke 3 tests no pre-research had found).
#
# Two coupling classes it reports (a third, population-glob coupling, is not this script's
# concern — ADR-0172 D3 already fixed it structurally in fence-contract-coverage.test.sh,
# skill-fence-positional-tokens.test.sh and pairs-completeness.test.sh):
#
#   1. PLANT — a `# plant:` declaration (plant-check.sh's own format) whose target field names
#      the file being audited, and whose needle physically resolves inside the given line range.
#      The needle is matched the SAME way plant-check.sh's worker matches it: words joined on
#      `\s+`, so a wrapped clause is still found. Reusing that exact matching logic (not a
#      close approximation) is what fixes this script's own predecessor: a hand-rolled grep in
#      the research pass that fed this tool's design failed to locate 13 of 80 needles.
#
#   2. AWK-RANGE — a `awk '/pat1/{f=1} .../pat2/{f=0|exit} f'` block-extraction idiom (copy-pasted
#      inline in ~10 test files, no shared helper — confirmed by exploration) whose start-anchor
#      pattern falls inside, or whose end-anchor pattern falls at/after, the given range. Reported
#      whether or not the site already has an emptiness guard (`[ -s "$BLOCK" ]`), because the
#      guard changes the FAILURE MODE (loud vs silent), not whether the site is coupled at all.
#
# Usage: skill-extraction-preflight.sh <skill-relative-path> <start-line> <end-line>
#   e.g.  skill-extraction-preflight.sh concept-to-code/SKILL.md 1018 2708
#
# Exit code: 0 always (this is a REPORTER, not a checker — rule 5). Read the printed counts.
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPTS="$SELF_DIR"
TESTS="$SCRIPTS/tests"
# Two levels up from scripts/ (scripts -> plugin -> staging), matching plant-check.sh's own
# STAGING derivation — plant declarations' target field is staging-relative, e.g.
# "plugin/skills/concept-to-code/SKILL.md", NOT "skills/concept-to-code/SKILL.md".
STAGING=$(cd "$SCRIPTS/../.." && pwd)

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <skill-relative-path> <start-line> <end-line>" >&2
  echo "  e.g.: $0 concept-to-code/SKILL.md 1018 2708" >&2
  exit 2
fi

TARGET_REL="plugin/skills/$1"
START="$2"
END="$3"
TARGET_ABS="$STAGING/$TARGET_REL"

if [ ! -f "$TARGET_ABS" ]; then
  echo "PREFLIGHT: target not found under staging/skills/ — $TARGET_REL" >&2
  exit 2
fi
case "$START$END" in *[!0-9]*)
  echo "PREFLIGHT: start/end must be plain line numbers (got start=$START end=$END)" >&2
  exit 2
esac
if [ "$START" -gt "$END" ]; then
  echo "PREFLIGHT: start ($START) must be <= end ($END)" >&2
  exit 2
fi

echo "=== skill-extraction-preflight: $TARGET_REL  lines $START-$END ==="
echo

# ---------------------------------------------------------------------------------------------
# PART 1 — PLANT declarations targeting this file, located by the SAME matcher plant-check.sh's
# worker uses (words joined on \s+), not a plain grep -F. This is what plant-check.sh's own
# `--worker` mode does internally to find a needle's match count; here we locate line numbers
# instead of substituting.
# ---------------------------------------------------------------------------------------------
PLANT_HITS="$(mktemp)"
PLANT_MISS="$(mktemp)"
trap 'rm -f "$PLANT_HITS" "$PLANT_MISS"' EXIT

DECLS="$(mktemp)"
: >"$DECLS"
for t in "$TESTS"/*.test.sh; do
  [ -f "$t" ] || continue
  grep -n '^# plant:' "$t" 2>/dev/null | while IFS=: read -r lineno rest; do
    payload="${rest#*plant:}"
    printf '%s\t%s\n' "$(basename "$t")" "$payload"
  done >>"$DECLS"
done

PLANT_TOTAL=0
PLANT_IN_RANGE=0
PLANT_UNRESOLVED=0

while IFS="$(printf '\t')" read -r tfile payload; do
  [ -n "${tfile:-}" ] || continue
  aid=$(printf '%s' "$payload" | awk -F' \\| ' '{print $1}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  tgt=$(printf '%s' "$payload" | awk -F' \\| ' '{print $2}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  ndl=$(printf '%s' "$payload" | awk -F' \\| ' '{print $3}')
  [ -n "$aid" ] && [ -n "$tgt" ] && [ -n "$ndl" ] || continue
  [ "$tgt" = "$TARGET_REL" ] || continue

  PLANT_TOTAL=$((PLANT_TOTAL + 1))

  # Locate the needle the way plant-check.sh's worker matches it: words joined on \s+, over the
  # REAL file (not a sandbox — this is read-only reconnaissance, nothing is mutated). Report the
  # 1-based line number of the match's start.
  ln=$(python3 - "$TARGET_ABS" "$ndl" <<'PY'
import re, sys
path, needle = sys.argv[1], sys.argv[2]
src = open(path, errors='replace').read()
lines_offsets = []
pos = 0
for line in src.split('\n'):
    lines_offsets.append(pos)
    pos += len(line) + 1
pat = re.compile(r'\s+'.join(re.escape(w) for w in needle.split()))
m = pat.search(src)
if not m:
    print(0)
else:
    import bisect
    idx = bisect.bisect_right(lines_offsets, m.start()) - 1
    print(idx + 1)
PY
)
  if [ -z "$ln" ] || [ "$ln" = "0" ]; then
    PLANT_UNRESOLVED=$((PLANT_UNRESOLVED + 1))
    printf '%s\n' "  UNRESOLVED  $tfile [$aid] — needle not found verbatim (may be masked/multi-line or already moved)" >>"$PLANT_MISS"
    continue
  fi
  if [ "$ln" -ge "$START" ] && [ "$ln" -le "$END" ]; then
    PLANT_IN_RANGE=$((PLANT_IN_RANGE + 1))
    printf '%s\n' "  IN-RANGE    $tfile [$aid] @line $ln" >>"$PLANT_HITS"
  fi
done <"$DECLS"

echo "--- PLANT declarations ---"
echo "total targeting $TARGET_REL: $PLANT_TOTAL"
echo "in range $START-$END:       $PLANT_IN_RANGE"
echo "unresolved (needle not located — investigate before trusting the count above):"
UNRES_N=$(grep -c . "$PLANT_MISS" 2>/dev/null || true); UNRES_N=${UNRES_N:-0}
echo "  $UNRES_N"
if [ -s "$PLANT_HITS" ]; then
  echo
  sort "$PLANT_HITS"
fi
if [ -s "$PLANT_MISS" ]; then
  echo
  echo "unresolved detail:"
  cat "$PLANT_MISS"
fi
echo

# ---------------------------------------------------------------------------------------------
# PART 2 — inline awk block-range extraction. This idiom has no shared helper (confirmed by
# exploration), so it is found by pattern rather than by call site: a line containing
# `awk '/PAT1/{f=1}` followed somewhere on the same logical awk program by a second `/PAT2/`
# anchor and an `f=0` or `exit`. We extract both anchor regexes, strip the awk/sed escaping,
# and locate each anchor as a literal search against the target file.
# ---------------------------------------------------------------------------------------------
echo "--- AWK-RANGE block extractions ---"
AWK_HITS=0
for t in "$TESTS"/*.test.sh; do
  [ -f "$t" ] || continue
  # Only test files that bind this exact skill path to a variable are candidates — cheap filter
  # before the more expensive per-line awk-anchor scan.
  grep -qF "$TARGET_REL" "$t" 2>/dev/null || continue

  grep -noE "awk '/\^[^/]+/\{f=1\}[^']*'" "$t" 2>/dev/null | while IFS=: read -r lineno prog; do
    p1=$(printf '%s' "$prog" | sed -n "s#.*'/\^\([^/]*\)/{f=1}.*#\1#p")
    p2=$(printf '%s' "$prog" | sed -n "s#.*/\^\([^/]*\)/{\(f=0\|exit\)}.*#\1#p")
    [ -n "$p1" ] || continue
    # De-escape the ERE-ish anchor back to a literal search string: drop backslash before
    # regex metacharacters this idiom actually uses (. * ^ $ and escaped literals like \.).
    lit1=$(printf '%s' "$p1" | sed 's/\\\././g')
    a1=$(grep -nF "$lit1" "$TARGET_ABS" 2>/dev/null | head -1 | cut -d: -f1)
    a2=""
    if [ -n "$p2" ]; then
      lit2=$(printf '%s' "$p2" | sed 's/\\\././g')
      a2=$(grep -nF "$lit2" "$TARGET_ABS" 2>/dev/null | head -1 | cut -d: -f1)
    fi
    if [ -n "$a1" ]; then
      overlap="no"
      if [ "$a1" -ge "$START" ] && [ "$a1" -le "$END" ]; then overlap="yes (start anchor inside range)"; fi
      if [ -n "$a2" ] && [ "$a2" -ge "$START" ] && [ "$a2" -le "$END" ]; then overlap="yes (end anchor inside range)"; fi
      if [ -n "$a2" ] && [ "$a1" -lt "$START" ] && [ "$a2" -gt "$END" ]; then overlap="yes (range fully spans extraction)"; fi
      if [ "$overlap" != "no" ]; then
        echo "  $(basename "$t"):$lineno — start-anchor '$lit1' @line ${a1:-?}, end-anchor '${lit2:-<none>}' @line ${a2:-?} — $overlap"
      fi
    fi
  done
done
echo
echo "(For an emptiness-guard audit per site, cross-reference against the VCS-047 research table"
echo " in TODO.md — this tool reports COUPLING, not whether the site is already guarded.)"
echo
echo "KNOWN LIMITATION: end-anchor detection only scans a single line (grep, no -z), so a"
echo "multi-line awk program (e.g. step6-effort-pin.test.sh's Form C) reports end-anchor <none>"
echo "even though one exists. This does not cause a false negative on the primary 'start anchor"
echo "inside range' condition — only on the 'range fully spans extraction' case, which needs"
echo "both anchors resolved. Treat any <none> end-anchor site as needing a manual look."
