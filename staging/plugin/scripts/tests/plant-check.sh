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
# The path is staging-relative, with one exception: a literal `../docs/` prefix reaches the docs
# copy the sandbox already makes. Any other `..` is refused. See PATH RESOLUTION below for why that
# exception exists — a claim living in a RUNBOOK was unplantable by construction (issue #339).
# Declarations sit at COLUMN 1: the collector below anchors on `^# plant:`, so an indented one is
# silently skipped (`PC4`, issue #329).
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

# build_sandbox <dir> — ONE construction, used by both the baseline pass and every mutation run.
#
# ADR-0086's criterion applies exactly: the baseline and the mutation runs must answer the same
# question about the same environment, so two copies that could drift apart would be a defect. A
# baseline measured in a differently-populated sandbox would recreate issue #433 one level up —
# an assertion red in one sandbox and green in the other, with the runner unable to tell which.
#
# The four repo-root inputs below are the fix for #433's cause. Measured 2026-08-15: with only
# `staging/` and `docs/`, 26 harnesses fail and 58 (file, assertion-id) pairs are RED before any
# mutation, because every assertion whose subject is `docs-ci.yml`, `.gitignore`, `PROJECT.md` or
# `CLAUDE.md` cannot evaluate. Supplying them takes that to 2, and no new failure appeared.
#
# `.git` is deliberately NOT supplied. The remaining two reds need a real repository
# (`git ls-files`, `git check-ignore`), and at least one harness detects the absence of a checkout
# in order to SKIP an assertion it cannot evaluate — copying a `.git` in would change what
# isolation means here. Those two are covered by the baseline instead of by the environment.
build_sandbox() {
  _sb="$1"
  mkdir -p "$_sb"
  cp -R "$STAGING" "$_sb/staging" 2>/dev/null
  cp -R "$REPO/docs" "$_sb/docs" 2>/dev/null
  cp -R "$REPO/.github" "$_sb/.github" 2>/dev/null
  cp "$REPO/.gitignore" "$_sb/.gitignore" 2>/dev/null
  cp "$REPO/CLAUDE.md" "$_sb/CLAUDE.md" 2>/dev/null
  cp "$REPO/PROJECT.md" "$_sb/PROJECT.md" 2>/dev/null
}

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

# --- baseline: which assertions are ALREADY red before any mutation (issue #433) ------------------
#
# Without this, the fired-predicate below answers "does `FAIL: <aid>` appear after the mutation",
# never "did the mutation turn it red". An assertion the sandbox itself cannot satisfy is credited
# as a fired plant and counted in PC1, which is CLAUDE.md rule 2's exact failure mode reached
# through the verification environment rather than through the assertion.
#
# ONE sandbox and one run per DECLARING harness — 39 today against the 362 mutation runs below,
# about 11% — DERIVED from the run counts, not measured as a delta; no like-for-like
# before/after exists because every timed run already carried the baseline. Issue #350's cost
# complaint is the 362, not the 39.
BASE_SBX="$WORK/baseline"
build_sandbox "$BASE_SBX"
BASE_DIR="$WORK/base"; mkdir -p "$BASE_DIR"
BASE_MISSING=""; BASE_N=0
for tfile in $(cut -f1 "$DECLS" 2>/dev/null | sort -u); do
  _h="$BASE_SBX/staging/plugin/scripts/tests/$tfile"
  if [ ! -f "$_h" ]; then
    BASE_MISSING="$BASE_MISSING $tfile(absent)"
    continue
  fi
  _out=$(bash "$_h" 2>&1); _rc=$?
  _red=$(printf '%s\n' "$_out" | grep '^FAIL: ' 2>/dev/null || true)
  # An empty baseline from a harness that DID NOT RUN would make PC5 pass for every plant in it,
  # so emptiness must be corroborated before it is trusted (rule 7 — guard the denominator).
  #
  # The corroboration is the EXIT STATUS, not a success token. The failure idiom is uniform and
  # enforced — a declaring harness is refused above unless it emits the `FAIL: <id>` prefix — but
  # the success idiom is not: measured 2026-08-15 across all 39 declaring harnesses, 38 print
  # `PASS: <id>` and phase1.test.sh prints `ok   <label>`, 37 assertions, entirely green. A
  # predicate enumerating success tokens would have called that live harness dead, and would stay
  # blind to the next harness that invents a third form (rule 8 — a list is blind to what it omits).
  #
  # So: reds present, the baseline speaks for itself. No reds and exit 0 with output, the harness
  # ran and had nothing to report. Anything else — a nonzero exit with no attributable FAIL line, or
  # silence — is a reading this file refuses to call clean.
  if [ -n "$_red" ]; then
    printf '%s\n' "$_red" >"$BASE_DIR/$tfile"
  elif [ "$_rc" -eq 0 ] && [ -n "$_out" ]; then
    : >"$BASE_DIR/$tfile"
  else
    BASE_MISSING="$BASE_MISSING $tfile(rc=$_rc,unattributable)"
    continue
  fi
  BASE_N=$((BASE_N + 1))
done

# --- run each plant -----------------------------------------------------------------------------
NOFIRE=""; BADPLANT=""; VACUOUS=""
# RUN_N counts DECLARATIONS — it names the sandbox directory, so it must advance even for one that
# is rejected. RAN_N counts plants that actually executed. Reporting the first as the second is how
# "1 run" gets printed for a run in which nothing ran, which is the shape this file exists to catch.
RUN_N=0; RAN_N=0
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

  # VACUOUS is NOT folded into BADPLANT, and the difference is the repair. BADPLANT means the
  # registry COULD NOT RUN this plant — malformed fields, unattributable harness, unresolvable
  # target, a needle matching zero or many sites. VACUOUS means the plant would run and its firing
  # would prove NOTHING, because the assertion is already red without it. Two states, two repairs,
  # so two tokens (issue #433).
  #
  # The comparison uses the SAME predicate as the fired check below, deliberately, so the two halves
  # agree. That predicate is a PREFIX match (issue #355, still open), so this guard inherits the
  # looseness and may over-refuse a plant whose id is a prefix of an already-red one. Over-refusal
  # fails loud, which is the safe direction; under-refusal is the defect being fixed.
  if [ -f "$BASE_DIR/$tfile" ] && grep -q "^FAIL: $aid" "$BASE_DIR/$tfile"; then
    VACUOUS="$VACUOUS
    $tfile [$aid] — already RED in the unmutated sandbox; firing here would prove nothing"
    continue
  fi

  # Attribution depends on the declaring harness emitting `FAIL: <id>`, and five harnesses emit
  # `FAIL <label>` with no colon (external-dependency-gate, hook-probe, hook-verify-workflow,
  # phase1, prep — measured 2026-08-05, phase1 converted the same day). A plant declared in one of
  # those can never be seen to fire: the grep below finds nothing whether the assertion held or
  # collapsed, and the run would report "the assertion still passed with the mechanism removed" —
  # a definite verdict from a check that could not look. That is this file's own subject one level
  # up, so it is a BADPLANT (the registry could not run), never a NOFIRE (the assertion pins
  # nothing).
  #
  # Checked HERE, against the real file, before any sandbox is built or any mutation applied:
  # rejecting after the copy wastes the work and, worse, puts the decision downstream of the very
  # machinery it exists to declare unusable. The needle is the EMITTER, not the string, so a
  # comment mentioning the prefix cannot excuse a harness that does not print it.
  if ! grep -qE "(printf|echo)[^#]*FAIL: " "$TESTS/$tfile"; then
    BADPLANT="$BADPLANT
    $tfile [$aid]: harness does not emit the 'FAIL: <id>' prefix — a plant here is unattributable"
    continue
  fi

  SBX="$WORK/sbx$RUN_N"
  build_sandbox "$SBX"

  # PATH RESOLUTION. Staging-relative by default. `../docs/...` reaches the docs copy the sandbox
  # already makes two lines above — which existed only so tests could READ it, while no plant could
  # ever TARGET it, so a claim written in a RUNBOOK was unplantable by construction (issue #339,
  # found the same day as PC4 and the same shape: a boundary of this registry that looks like full
  # coverage from outside). The prefix is matched literally and any OTHER `..` is refused, so the
  # widening cannot walk out of the sandbox.
  case "$tgt" in
    ../docs/*)
      case "${tgt#../docs/}" in
        *..*) BADPLANT="$BADPLANT
    $tfile [$aid]: refused — '..' inside a ../docs/ target: $tgt"; continue ;;
      esac
      TARGET="$SBX/docs/${tgt#../docs/}" ;;
    *..*)
      BADPLANT="$BADPLANT
    $tfile [$aid]: refused — '..' is allowed only as the literal ../docs/ prefix: $tgt"
      continue ;;
    *) TARGET="$SBX/staging/$tgt" ;;
  esac
  if [ ! -f "$TARGET" ]; then
    BADPLANT="$BADPLANT
    $tfile [$aid]: target not found under staging/ (or ../docs/) — $tgt"
    continue
  fi

  # Substitute. The needle's words are joined on \s+ so a wrapped clause is still matched, and the
  # replacement is applied through a lambda so backslashes in it are literal rather than group
  # references.
  MRES=$(python3 - "$TARGET" "$ndl" "$rep" <<'PY'
import re, sys
path, needle, repl = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(path, errors='replace').read()
# A `# plant:` line CONTAINS its own needle verbatim, so a plant whose target is the very test
# file that declares it always matched twice and was rejected as malformed — the whole class of
# self-targeting plants was inexpressible. Mask the declaration lines out, then restore them
# verbatim. Same skip ADR-0082's xref extractor already makes, for the same reason: a
# declaration must not satisfy the check it declares.
NUL = '\x00'
lines = src.split('\n')
masked = [l for l in lines if l.startswith('# plant:')]
work = '\n'.join(NUL if l.startswith('# plant:') else l for l in lines)
pat = re.compile(r'\s+'.join(re.escape(w) for w in needle.split()))
hits = pat.findall(work)
print(len(hits))
if len(hits) == 1:
    work = pat.sub(lambda _m: repl, work, count=1)
    for l in masked:                      # restore in order; robust to a multi-line replacement
        work = work.replace(NUL, l, 1)
    open(path, 'w').write(work)
PY
)
  if [ "$MRES" != "1" ]; then
    BADPLANT="$BADPLANT
    $tfile [$aid]: needle matched $MRES times in $tgt (must be exactly 1)"
    continue
  fi

  RAN_N=$((RAN_N + 1))
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
  ok "PC1 every declared plant fired ($RAN_N of $RUN_N declarations run)"
else
  bad "PC1 plant(s) that did not fire — those assertions pin nothing:$NOFIRE"
fi

# PC2 — every plant is itself USABLE. Three ways it is not: the target does not exist, the needle
# matches zero or many sites, or the declaring harness cannot be attributed against. All three
# prove nothing about the assertion while reading as coverage. The pass label named only the
# middle one, which was already narrower than the check before the third was added.
if [ -z "$BADPLANT" ]; then
  ok "PC2 every plant declaration is usable (target, single match, attributable harness)"
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

# PC4 — no declaration may be INDENTED. The collector above anchors on `^# plant:`, so a
# declaration written inside an `if`/`for` block, beside the assertion it proves, is silently
# skipped: it does not run, it does not fail, and the only symptom is a file appearing to carry
# fewer plants than its author wrote. That is this registry's own failure mode — a plant nobody
# validated — reproduced one level up, and it cost eight plants on the day it was found (issue
# #329). Declarations sit at column 1; the assertion id is what ties them to their assertion,
# not their position.
INDENTED=""
for t in "$TESTS"/*.test.sh; do
  [ -f "$t" ] || continue
  grep -qE '^[[:space:]]+# plant:' "$t" 2>/dev/null && INDENTED="$INDENTED $(basename "$t")"
done
if [ -z "$INDENTED" ]; then
  ok "PC4 no plant declaration is indented (all collectable at column 1)"
else
  bad "PC4 indented plant declaration(s) — silently skipped by the collector:$INDENTED"
fi

# PC5 — no plant is declared on an assertion that is already RED before any mutation (issue #433).
#
# THIS PASSES ON THE DAY IT SHIPS, and that is not evidence of a repair. No declared plant is
# vacuous today: intersecting the 58 pre-mutation reds with the 362 declared ids yields four hits
# and all four are id-only collisions across DIFFERENT files, which the runner cannot confuse
# because it executes only the declaring harness. What repaired something is the sandbox now
# carrying the four repo-root inputs (58 reds down to 2). PC5 is the guard for the next declaration.
if [ -z "$VACUOUS" ]; then
  ok "PC5 no plant is declared on an assertion already RED in the unmutated sandbox"
else
  bad "PC5 vacuous plant(s) — the assertion is red before any mutation, so firing proves nothing:$VACUOUS"
fi

# PC5b — the baseline itself RAN. An empty baseline for a harness that did not run would make PC5
# pass for every plant declared in it, which is this file's own failure mode turned on its guard.
if [ -z "$BASE_MISSING" ]; then
  ok "PC5b the baseline ran for all $BASE_N declaring harness(es)"
else
  bad "PC5b the baseline DID NOT RUN for:$BASE_MISSING — PC5 says nothing about plants in those files"
fi

_total=$((PASS + FAIL))
if [ "$_total" -ge 14 ]; then ok "Z1 assertion-count floor ($_total >= 14)"
else bad "Z1 assertion count fell to $_total (floor 14) — plants or assertions vanished"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
