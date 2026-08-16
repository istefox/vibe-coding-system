#!/bin/bash
# plant-check.sh — offline, hermetic, no network, no $HOME dependency.
# Issue #284 / ADR-0108. Parallel mutation phase: issue #350 / ADR-0143.
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
# Each plant runs against an isolated `cp -R` of `staging/` and `docs/` — measured at 0.50s — so
# nothing here can touch the real tree. Tests resolve their root from `$(dirname "$0")`, so a copied
# tree redirects with no change to any test.
#
# COST AND CONCURRENCY (issue #350, ADR-0143). Every plant costs one full run of the file it lives
# in, so the registry's total is dominated by the TARGET FILE'S RUNTIME and not by the plant count:
# measured 2026-08-15, `autopilot-run-scope` carries 58 plants and costs less than
# `worktree-isolation-contract`'s 11. Two files are 45% of the total. Trimming plants off the slow
# ones is the remedy the issue rules out, because a plant removed is evidence removed.
#
# What the measurement DID leave open is that every mutation run is already isolated — its own
# sandbox, its own process — and was nonetheless executed one at a time, at 89% of a single core on
# an 18-core machine, with more time spent in the kernel copying trees than in the tests themselves.
# So the phase is run by $JOBS workers. Isolation is what makes that legitimate; nothing about the
# verdicts changes, and the acceptance test for the change was exactly that: the full output, diffed
# against the sequential run, byte for byte identical across 391 lines.
#
# The aggregation below therefore reports in DECLARATION order, never completion order. An output
# that reshuffles per run cannot be diffed against anything, and the diff is the only evidence that
# parallelising a validator did not change what it validates.
set -u

TESTS=$(cd "$(dirname "$0")" && pwd)
STAGING=$(cd "$TESTS/../../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
SELF="$TESTS/$(basename "$0")"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# build_sandbox <dir> — ONE construction, used by the baseline pass and every mutation run.
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

# ==================================================================================================
# WORKER MODE — one declaration, start to verdict. Re-entered as `plant-check.sh --worker N DIR`.
#
# This is the mutation loop's body and there is no second copy of it: the sequential path IS this
# path with one worker. ADR-0086's criterion again — a parallel implementation kept beside a
# sequential one is two copies answering the same question, and the day they disagree the runner
# cannot say which verdict is the registry's.
#
# The verdict leaves as two files rather than one delimited line. A message here can contain any
# character a plant declaration can contain, and a delimiter that a payload can also contain is how
# a parser starts reporting a state nobody produced.
# ==================================================================================================
if [ "${1:-}" = "--worker" ]; then
  IDX="${2:?worker index}"; WORK="${3:?worker workdir}"
  RES="$WORK/res/$IDX"
  emit() { printf '%s\n' "$1" >"$RES.kind"; printf '%s\n' "$2" >"$RES.msg"; }

  line=$(sed -n "${IDX}p" "$WORK/decls")
  tfile=$(printf '%s' "$line" | cut -f1)
  payload=$(printf '%s' "$line" | cut -f2-)
  [ -n "${tfile:-}" ] || exit 0

  aid=$(printf '%s' "$payload"   | awk -F' \\| ' '{print $1}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  tgt=$(printf '%s' "$payload"   | awk -F' \\| ' '{print $2}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  ndl=$(printf '%s' "$payload"   | awk -F' \\| ' '{print $3}')
  rep=$(printf '%s' "$payload"   | awk -F' \\| ' '{print $4}')

  if [ -z "$aid" ] || [ -z "$tgt" ] || [ -z "$ndl" ]; then
    emit BADPLANT "    $tfile: malformed declaration (need 4 fields separated by ' | ')"
    exit 0
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
  if [ -f "$WORK/base/$tfile" ] && grep -q "^FAIL: $aid" "$WORK/base/$tfile"; then
    emit VACUOUS "    $tfile [$aid] — already RED in the unmutated sandbox; firing here would prove nothing"
    exit 0
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
    emit BADPLANT "    $tfile [$aid]: harness does not emit the 'FAIL: <id>' prefix — a plant here is unattributable"
    exit 0
  fi

  SBX="$WORK/sbx$IDX"
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
        *..*) emit BADPLANT "    $tfile [$aid]: refused — '..' inside a ../docs/ target: $tgt"
              rm -rf "$SBX"; exit 0 ;;
      esac
      TARGET="$SBX/docs/${tgt#../docs/}" ;;
    *..*)
      emit BADPLANT "    $tfile [$aid]: refused — '..' is allowed only as the literal ../docs/ prefix: $tgt"
      rm -rf "$SBX"; exit 0 ;;
    *) TARGET="$SBX/staging/$tgt" ;;
  esac
  if [ ! -f "$TARGET" ]; then
    emit BADPLANT "    $tfile [$aid]: target not found under staging/ (or ../docs/) — $tgt"
    rm -rf "$SBX"; exit 0
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
    emit BADPLANT "    $tfile [$aid]: needle matched $MRES times in $tgt (must be exactly 1)"
    rm -rf "$SBX"; exit 0
  fi

  OUT=$(bash "$SBX/staging/plugin/scripts/tests/$tfile" 2>&1)
  # The harness output reaches grep through a HERE-DOCUMENT and not a pipe. `printf … | grep -q`
  # races: grep exits at the first match and closes the pipe while printf is still writing, and the
  # loser prints `write error: Broken pipe`. Measured on the runner 2026-08-15 — bash 5 reports it,
  # bash 3.2 on macOS swallows it, so it is invisible where this file is written and visible where
  # it runs. One stray line whose presence depends on timing is enough to make the one-worker /
  # many-worker diff differ, and that diff is the only evidence that concurrency changed nothing.
  if grep -q "^FAIL: $aid" <<PLANT_HARNESS_OUTPUT
$OUT
PLANT_HARNESS_OUTPUT
  then
    emit FIRED "  plant $tfile [$aid] fired"
  else
    emit NOFIRE "    $tfile [$aid] — the assertion still passed with the mechanism removed"
  fi

  # Holding every sandbox until the orchestrator's trap fires cost ~8.4 GB of peak disk at 381
  # plants — 22 MB apiece that nothing ever reads back.
  rm -rf "$SBX"    # freed at verdict time, not at exit (issue #350)
  exit 0
fi

# ==================================================================================================
# BASELINE BUILDER — one declaring harness, in its own sandbox. Re-entered as `--baseline NAME DIR`.
# ==================================================================================================
if [ "${1:-}" = "--baseline" ]; then
  tfile="${2:?harness name}"; WORK="${3:?workdir}"
  # A sandbox PER harness, where the sequential file shared one. Sharing was safe while the runs
  # were serial; run concurrently, a harness that writes anywhere inside the tree it was given
  # would be corrupting another harness's baseline, and the symptom would be a vacuous-plant
  # verdict nobody could reproduce. 41 copies cost ~20s of `cp` spread across the workers, which
  # is the cheapest guarantee on offer.
  SBX="$WORK/base-sbx-$tfile"
  build_sandbox "$SBX"
  _h="$SBX/staging/plugin/scripts/tests/$tfile"
  if [ ! -f "$_h" ]; then
    printf 'absent\n' >"$WORK/basemiss/$tfile"; rm -rf "$SBX"; exit 0
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
    printf '%s\n' "$_red" >"$WORK/base/$tfile"
  elif [ "$_rc" -eq 0 ] && [ -n "$_out" ]; then
    : >"$WORK/base/$tfile"
  else
    printf 'rc=%s,unattributable\n' "$_rc" >"$WORK/basemiss/$tfile"
  fi
  rm -rf "$SBX"
  exit 0
fi

# ==================================================================================================
# ORCHESTRATOR
# ==================================================================================================
# WORK ROOT — where the sandboxes are built. `mktemp -d` on its own cannot be pointed anywhere on
# this platform: BSD mktemp IGNORES `TMPDIR` (verified 2026-08-15 on macOS 26; GNU coreutils honours
# it, so a check written against TMPDIR passes on the Linux runner and is inert on the machine the
# author is sitting at). `PLANT_WORKROOT` is the portable way to say it — for an operator who wants
# the copies on a particular volume, and for `plant-registry-parallel.test.sh`, which has to WATCH
# the sandboxes appear and disappear and cannot do that in a directory it did not choose.
if [ -n "${PLANT_WORKROOT:-}" ] && [ -d "${PLANT_WORKROOT:-}" ]; then
  WORK=$(mktemp -d "$PLANT_WORKROOT/plant.XXXXXX")
else
  WORK=$(mktemp -d)
fi
trap 'rm -rf "$WORK"' EXIT

# JOBS — how many mutation runs are in flight at once.
#
# Resolution order: `PLANT_JOBS`, then the machine's own count, then 1. Every failure resolves
# DOWNWARDS to 1, which is the behaviour this file had before it was parallel: an unreadable core
# count must not become an unbounded fan-out on a runner nobody has measured.
#
# The ceiling is 8 because 8 is what was MEASURED (2026-08-15, 18-core machine, 381 plants). Above
# it the copies contend for I/O and no number exists, so the file does not invent one; a runner with
# more cores and a reason can say `PLANT_JOBS=16` and record what it got.
_detect_jobs() {
  _j=$(nproc 2>/dev/null) || _j=""
  [ -n "$_j" ] || _j=$(sysctl -n hw.ncpu 2>/dev/null) || _j=""
  [ -n "$_j" ] || _j=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || _j=""
  printf '%s' "$_j"
}
JOBS="${PLANT_JOBS:-$(_detect_jobs)}"
case "$JOBS" in ''|*[!0-9]*) JOBS=1 ;; esac
[ "$JOBS" -ge 1 ] || JOBS=1
if [ -z "${PLANT_JOBS:-}" ] && [ "$JOBS" -gt 8 ]; then JOBS=8; fi

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
# ONE run per DECLARING harness — 41 today against the 381 mutation runs below, about 11%. Issue
# #350's cost complaint is the 381, not the 41.
mkdir -p "$WORK/base" "$WORK/basemiss" "$WORK/res"
cut -f1 "$DECLS" 2>/dev/null | sort -u \
  | xargs -P "$JOBS" -I{} bash "$SELF" --baseline {} "$WORK"

BASE_N=$(ls "$WORK/base" 2>/dev/null | grep -c . || true); BASE_N=${BASE_N:-0}
BASE_MISSING=""
for f in "$WORK/basemiss"/*; do
  [ -e "$f" ] || continue
  BASE_MISSING="$BASE_MISSING $(basename "$f")($(cat "$f"))"
done

# --- run each plant -------------------------------------------------------------------------------
seq 1 "$DECL_N" | xargs -P "$JOBS" -I{} bash "$SELF" --worker {} "$WORK"

# --- aggregate, IN DECLARATION ORDER ---------------------------------------------------------------
# RUN_N counts DECLARATIONS — every one is accounted for here, including the ones a worker refused.
# RAN_N counts plants that actually executed. Reporting the first as the second is how "1 run" gets
# printed for a run in which nothing ran, which is the shape this file exists to catch.
NOFIRE=""; BADPLANT=""; VACUOUS=""
RUN_N=0; RAN_N=0
for _i in $(seq 1 "$DECL_N"); do
  RUN_N=$((RUN_N + 1))
  if [ -f "$WORK/res/$_i.kind" ]; then
    _kind=$(cat "$WORK/res/$_i.kind")
    _msg=$(cat "$WORK/res/$_i.msg" 2>/dev/null)
    case "$_kind" in
      FIRED)    RAN_N=$((RAN_N + 1)); ok "$_msg" ;;
      NOFIRE)   RAN_N=$((RAN_N + 1)); NOFIRE="$NOFIRE
$_msg" ;;
      BADPLANT) BADPLANT="$BADPLANT
$_msg" ;;
      VACUOUS)  VACUOUS="$VACUOUS
$_msg" ;;
      *)        BADPLANT="$BADPLANT
    declaration $_i returned the unknown verdict '$_kind' — the registry cannot classify its own output" ;;
    esac
  else
    # Rule 4, applied to this file's own workers: a declaration with no verdict DID NOT RUN, and
    # that is not the same reading as a plant that ran and found nothing. Silence here would be
    # counted as a clean registry by every consumer downstream.
    BADPLANT="$BADPLANT
    declaration $_i produced no verdict — the worker did not run"
  fi
done

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
