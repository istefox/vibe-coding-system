#!/bin/bash
# plant-check.sh — offline, hermetic, no network, no $HOME dependency.
# Issue #284 / ADR-0108.
# Bash 3.2 clean. Run: bash plant-check.sh
#
# THE RULE — an assertion is not evidence until a defect has been planted and it has gone RED. This
# file makes that durable instead of momentary.
#
# Rule 12 — *a scan whose needle is a literal counts itself* — bit five times in one day (`SA10`,
# `N9`, `GR1`, `GR5`, `SP1`). Every one was an assertion whose needle was the NAME of the thing it
# asserted about, matching a file that legitimately names it while explaining it. Every one was
# caught by planting a defect and watching the assertion fail to fail. **The plants worked; nothing
# made them durable** — a plant is typed into a shell, watched, and thrown away, and the next reader
# cannot tell a pinned assertion from a decorative one.
#
# WHAT THE MEASUREMENT RULED OUT, before this was built:
#
#   - A static detector on multi-match needles flags 77 of 181 statically resolvable assertions
#     (43%), dominated by legitimate cross-references — and only 181 of 543 are resolvable at all.
#   - A code-only projection catches 4 of the 5; `N9` matched inside `ok`/`bad` MESSAGE STRINGS,
#     which is code, not commentary. It also collides with ADR-0086's refusal to share a helper
#     across 67 hermetic files.
#   - What actually distinguishes a rule-12 defect is BEHAVIOURAL: the assertion still passes when
#     the mechanism is removed. That is mutation testing and nothing else.
#
# DECLARATION — one line, in the test file, beside the assertion it proves. ADR-0077's principle:
# a waiver travels with the file it excuses, and so does a plant.
#
#   # plant: <assertion-id> | <path-relative-to-staging> | <needle> | <replacement>
#
# The needle is matched with its words joined on `\s+`, so a clause that WRAPS is still found. That
# is today's lesson put into the mechanism rather than left to the author's memory (ADR-0099).
# A ` | ` sequence cannot appear inside a field; that is the one syntax limit and it is deliberate.
#
# EXACTLY ONE MATCH IS REQUIRED. Zero means the needle rotted; more than one means the plant hits
# sites it did not intend. Both are defects in the PLANT, and both happened the day this was
# designed (ADR-0099 `P4`/`P5`, ADR-0104 `P2`). A plant nobody validated is worth as much as an
# assertion nobody planted.
#
# Each plant runs against an isolated `cp -R` of `staging/` and `docs/` — measured at 0.21s — so
# nothing here can touch the real tree. Tests resolve their root from `$(dirname "$0")`, so a copied
# tree redirects with no change to any test.
set -u

TESTS=$(cd "$(dirname "$0")" && pwd)
STAGING=$(cd "$TESTS/../../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- collect declarations -----------------------------------------------------------------------
DECLS="$WORK/decls"; : >"$DECLS"
for t in "$TESTS"/*.test.sh; do
  [ -f "$t" ] || continue
  grep -n '^# plant:' "$t" 2>/dev/null | while IFS= read -r line; do
    printf '%s\t%s\n' "$(basename "$t")" "${line#*:# plant:}"
  done >>"$DECLS"
done
DECL_N=$(grep -c . "$DECLS" 2>/dev/null || true)
DECL_N=${DECL_N:-0}

# PC0 — count guard on the DENOMINATOR (ADR-0085). A glob that stops resolving discovers no plants,
# reports nothing, and reads exactly like a corpus where every plant fired.
if [ "$DECL_N" -ge 10 ]; then
  ok "PC0 plant declarations discovered ($DECL_N)"
else
  bad "PC0 only $DECL_N plant declaration(s) found — expected >= 10; the collector is broken, not clean"
fi

# --- run each plant -----------------------------------------------------------------------------
NOFIRE=""; BADPLANT=""
RUN_N=0
while IFS="$(printf '\t')" read -r tfile payload; do
  [ -n "${tfile:-}" ] || continue
  RUN_N=$((RUN_N + 1))

  aid=$(printf '%s' "$payload"   | awk -F' \\| ' '{print $1}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  tgt=$(printf '%s' "$payload"   | awk -F' \\| ' '{print $2}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  ndl=$(printf '%s' "$payload"   | awk -F' \\| ' '{print $3}')
  rep=$(printf '%s' "$payload"   | awk -F' \\| ' '{print $4}')

  if [ -z "$aid" ] || [ -z "$tgt" ] || [ -z "$ndl" ]; then
    BADPLANT="$BADPLANT
    $tfile: malformed declaration (need 4 fields separated by ' | ')"
    continue
  fi

  SBX="$WORK/sbx$RUN_N"
  mkdir -p "$SBX"
  cp -R "$STAGING" "$SBX/staging" 2>/dev/null
  cp -R "$REPO/docs" "$SBX/docs" 2>/dev/null

  TARGET="$SBX/staging/$tgt"
  if [ ! -f "$TARGET" ]; then
    BADPLANT="$BADPLANT
    $tfile [$aid]: target not found under staging/ — $tgt"
    continue
  fi

  # Substitute. The needle's words are joined on \s+ so a wrapped clause is still matched, and the
  # replacement is applied through a lambda so backslashes in it are literal rather than group
  # references.
  MRES=$(python3 - "$TARGET" "$ndl" "$rep" <<'PY'
import re, sys
path, needle, repl = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path, errors='replace').read()
pat = re.compile(r'\s+'.join(re.escape(w) for w in needle.split()))
hits = pat.findall(src)
print(len(hits))
if len(hits) == 1:
    open(path, 'w').write(pat.sub(lambda _m: repl, src, count=1))
PY
)
  if [ "$MRES" != "1" ]; then
    BADPLANT="$BADPLANT
    $tfile [$aid]: needle matched $MRES times in $tgt (must be exactly 1)"
    continue
  fi

  OUT=$(bash "$SBX/staging/plugin/scripts/tests/$tfile" 2>&1)
  if printf '%s\n' "$OUT" | grep -q "^FAIL: $aid"; then
    ok "  plant $tfile [$aid] fired"
  else
    NOFIRE="$NOFIRE
    $tfile [$aid] — the assertion still passed with the mechanism removed"
  fi
done <"$DECLS"

# PC1 — every plant fired. A plant that does not fire names an assertion pinning nothing, which is
# the whole reason this file exists.
if [ -z "$NOFIRE" ]; then
  ok "PC1 every declared plant fired ($RUN_N run)"
else
  bad "PC1 plant(s) that did not fire — those assertions pin nothing:$NOFIRE"
fi

# PC2 — every plant is itself well-formed. A plant matching zero or many sites proves nothing about
# the assertion, and reads as coverage.
if [ -z "$BADPLANT" ]; then
  ok "PC2 every plant declaration resolved to exactly one site"
else
  bad "PC2 malformed plant(s):$BADPLANT"
fi

# PC3 — the plants are spread across files rather than concentrated in one. A registry proving one
# test file says nothing about the convention.
FILES_N=$(cut -f1 "$DECLS" 2>/dev/null | sort -u | grep -c . || true)
FILES_N=${FILES_N:-0}
if [ "$FILES_N" -ge 4 ]; then
  ok "PC3 plants span $FILES_N test files"
else
  bad "PC3 plants span only $FILES_N test file(s) — expected >= 4"
fi

_total=$((PASS + FAIL))
if [ "$_total" -ge 14 ]; then ok "Z1 assertion-count floor ($_total >= 14)"
else bad "Z1 assertion count fell to $_total (floor 14) — plants or assertions vanished"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
