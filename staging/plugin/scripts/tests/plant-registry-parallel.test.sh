#!/bin/bash
# plant-registry-parallel.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash plant-registry-parallel.test.sh
#
# Issue #350 / ADR-0143. `plant-check.sh` runs each plant's mutation in its own sandbox and its own
# process, and until this change it ran them one at a time: measured 2026-08-15, 20m07s of a 23m
# `shell-tests` job that is a REQUIRED check on `main`, at 89% of a single core on an 18-core
# machine. The phase is now dispatched to `$JOBS` workers.
#
# WHY THIS FILE EXISTS AT ALL. The thing being changed is the thing that validates every other
# assertion in this repository, so "the tests still pass" is a circular answer: the registry is what
# decides whether they were ever pinned. Two separate pieces of evidence were required, and only one
# of them can live in CI:
#
#   OUTSIDE the registry — the full 381-plant run, sequential and parallel, diffed. Measured
#   2026-08-15: 30.9 min at one worker, 9.69 min at four, 7.59 min at eight, and 391 output lines
#   IDENTICAL BYTE FOR BYTE across all of them. That is the real evidence and it cannot be a test:
#   it costs half an hour.
#
#   INSIDE the registry — this file, on a FIXTURE. It builds a miniature staging tree with its own
#   harnesses and its own plants, runs the real `plant-check.sh` against it three times, and asserts
#   the properties that would break if concurrency were wrong. Seconds, not half an hour, and it
#   runs on every push.
#
# The fixture is not a smaller version of the corpus; it is a corpus chosen so the failure modes are
# REACHABLE. Its four harnesses sleep for DESCENDING intervals, so completion order is the reverse
# of declaration order — without that, an aggregation that reported in completion order would look
# correct here and be wrong in CI. One of its plants is deliberately built NOT to fire, because an
# equivalence check between two runs that both found nothing is satisfied by a registry that does
# nothing.
#
# A TRAP THIS FILE HAD TO AVOID, recorded because the next author will meet it: a literal `# plant:`
# at column 1 anywhere in this file is collected by the real registry as THIS file's own
# declaration, fixture or not — the collector greps `^# plant:` across `*.test.sh` and cannot know
# the line was meant for a fixture. The fixture's declarations are therefore written as `@PLANT@`
# and substituted in. Only the six lines below are this file's real plants.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: PP0 | plugin/scripts/tests/plant-registry-parallel.test.sh | for _h in alpha beta gamma delta | for _h in alpha
# plant: PP1 | plugin/scripts/tests/plant-check.sh | SBX="$WORK/sbx$IDX" | SBX="$WORK/sbx"
# plant: PP2 | plugin/scripts/tests/plant-check.sh | grep -q "^FAIL: $aid"; then | grep -q "^"; then
# plant: PP3 | plugin/scripts/tests/plant-check.sh | for _i in $(seq 1 "$DECL_N"); do | for _i in $(seq "$DECL_N" -1 1); do
# plant: PP4 | plugin/scripts/tests/plant-check.sh | rm -rf "$SBX"    # freed at verdict time, not at exit (issue #350) | : # sandbox deliberately kept
# plant: PP5 | plugin/scripts/tests/plant-check.sh | case "$JOBS" in ''|*[!0-9]*) JOBS=1 ;; esac | case "$JOBS" in ''|*[!0-9]*) : ;; esac
set -u

TESTS=$(cd "$(dirname "$0")" && pwd)
PC="$TESTS/plant-check.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$PC" ] || { echo "FATAL: missing $PC"; exit 1; }

# ==================================================================================================
# The fixture — a miniature staging tree the real registry can be pointed at.
# ==================================================================================================
FIX="$TMP/fix"
mkdir -p "$FIX/staging/plugin/scripts/tests"
cp "$PC" "$FIX/staging/plugin/scripts/tests/plant-check.sh"

# The subject: markers the fixture harnesses assert on. MARK-UNUSED is asserted on by NOTHING, and
# that is deliberate — it is what makes a non-firing plant expressible.
cat >"$FIX/staging/plugin/scripts/demo.sh" <<'DEMO'
#!/bin/bash
# MARK-A1 first mechanism
# MARK-A2 second mechanism
# MARK-A3 third mechanism
# MARK-B1 fourth mechanism
# MARK-B2 fifth mechanism
# MARK-B3 sixth mechanism
# MARK-C1 seventh mechanism
# MARK-C2 eighth mechanism
# MARK-C3 ninth mechanism
# MARK-D1 tenth mechanism
# MARK-D2 eleventh mechanism
# MARK-D9 twelfth mechanism
# MARK-UNUSED no assertion depends on this one, by design
DEMO

# Four harnesses, sleeping for DESCENDING intervals so that under concurrency the LAST declarations
# finish FIRST. An aggregation that reported in completion order would be caught by PP3 here and
# would otherwise only be caught in CI, on the corpus, months later.
_mk_harness() {   # <name> <sleep> <id1> <id2> <id3>
  _n="$1"; _s="$2"; _a="$3"; _b="$4"; _c="$5"
  cat >"$FIX/staging/plugin/scripts/tests/$_n.test.sh" <<HARNESS
#!/bin/bash
set -u
D=\$(cd "\$(dirname "\$0")/.." && pwd)/demo.sh
sleep $_s
for _m in $_a $_b $_c; do
  if grep -q "MARK-\$_m" "\$D"; then printf 'PASS: %s\n' "\$_m"; else printf 'FAIL: %s\n' "\$_m"; fi
done
exit 0
HARNESS
}

# PP0's own subject. Shrink this list and the fixture stops being able to prove anything, which is
# why PP0 asserts the population the other five assertions are measured against (rule 7).
for _h in alpha beta gamma delta; do
  case "$_h" in
    alpha) _mk_harness alpha 0.20 A1 A2 A3 ;;
    beta)  _mk_harness beta  0.15 B1 B2 B3 ;;
    gamma) _mk_harness gamma 0.10 C1 C2 C3 ;;
    delta) _mk_harness delta 0.05 D1 D2 D9 ;;
  esac
done

# The fixture's declarations. `@PLANT@` is substituted, never written literally — see the header.
#
# D9 is the one built NOT to fire, and the two halves have to be read together: the ASSERTION `D9`
# reads MARK-D9 and is green, while the PLANT declared on it mutates MARK-UNUSED, which no assertion
# reads. So the mutation lands, the harness stays green, and the registry must report an assertion
# that survived the removal of its mechanism. Pointing the assertion itself at a marker that does not
# exist would have produced something else entirely — an assertion RED before any mutation, which is
# ADR-0140's vacuous-plant class and not this one.
_decl() {   # <harness> <id> <needle-marker>
  printf '@PLANT@ %s %s plugin/scripts/demo.sh %s MARK-%s %s GONE-%s\n' \
    "$2" "|" "|" "$3" "|" "$3" \
    | sed 's/@PLANT@/# plant:/' >>"$FIX/staging/plugin/scripts/tests/$1.test.sh"
}
_decl alpha A1 A1; _decl alpha A2 A2; _decl alpha A3 A3
_decl beta  B1 B1; _decl beta  B2 B2; _decl beta  B3 B3
_decl gamma C1 C1; _decl gamma C2 C2; _decl gamma C3 C3
_decl delta D1 D1; _decl delta D2 D2; _decl delta D9 UNUSED

FIXPC="$FIX/staging/plugin/scripts/tests/plant-check.sh"
FIXN=$(grep -c '^# plant:' "$FIX/staging/plugin/scripts/tests"/*.test.sh 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
FIXF=$(ls "$FIX/staging/plugin/scripts/tests"/*.test.sh 2>/dev/null | grep -c . || true)

# ==================================================================================================
# Three runs of the real registry against the fixture.
#
# The one-worker run is sampled while it executes, because PP4's subject — a sandbox freed at
# verdict time — leaves no trace afterwards: the orchestrator's EXIT trap removes everything, so a
# check that looks after the run has finished cannot tell 12 retained sandboxes from none.
# ==================================================================================================
#
# The watched directory is named through `PLANT_WORKROOT` and NOT through `TMPDIR`, because BSD
# mktemp ignores TMPDIR (verified 2026-08-15 on macOS 26). A sampler written against TMPDIR observes
# nothing here and everything on the Linux runner: it would have shipped green in CI while pinning
# nothing on the machine it was written on.
SBXWATCH="$TMP/watch"; mkdir -p "$SBXWATCH"

PLANT_WORKROOT="$SBXWATCH" PLANT_JOBS=1 bash "$FIXPC" >"$TMP/out1" 2>&1 &
_pid=$!
MAXSBX=0
while kill -0 "$_pid" 2>/dev/null; do
  _n=$(find "$SBXWATCH" -maxdepth 2 -type d -name 'sbx*' 2>/dev/null | grep -c . || true)
  [ "${_n:-0}" -gt "$MAXSBX" ] && MAXSBX="$_n"
  sleep 0.02
done
wait "$_pid" 2>/dev/null

PLANT_JOBS=4   bash "$FIXPC" >"$TMP/out4"   2>&1
PLANT_JOBS=abc bash "$FIXPC" >"$TMP/outbad" 2>&1

# ==================================================================================================
# PP0 — the denominator. Every assertion below compares two runs of this fixture; a fixture that
# stopped declaring plants would make all of them compare nothing to nothing and read as clean.
# ==================================================================================================
# Counting the files is not enough, and the plant on this assertion is what proved it: the
# declarations are appended with `>>`, so a fixture builder that stops writing HARNESSES still
# leaves four files containing nothing but `# plant:` lines. Counted, that corpus is indisting-
# uishable from the real one. So PP0 asks the harnesses to RUN.
_fixran=0
for _q in alpha beta gamma delta; do
  _qf="$FIX/staging/plugin/scripts/tests/$_q.test.sh"
  [ -f "$_qf" ] && bash "$_qf" 2>/dev/null | grep -q '^PASS: ' && _fixran=$((_fixran + 1))
done
if [ "${FIXN:-0}" -eq 12 ] && [ "${FIXF:-0}" -eq 4 ] && [ "$_fixran" -eq 4 ] \
   && grep -q "^PASS: PC0 plant declarations discovered (12)$" "$TMP/out1"; then
  ok "PP0: the fixture is 12 plants over 4 harnesses that run, and the registry collected all 12"
else
  bad "PP0: fixture is $FIXN plant(s) over $FIXF file(s) of which $_fixran actually run (expected 12, 4 and 4), or the registry did not collect them — every assertion below would compare nothing to nothing"
fi

# ==================================================================================================
# PP1 — one worker and four workers produce the SAME output, byte for byte. This is the whole claim
# of ADR-0143: the mutation phase was already isolated, so spending that isolation concurrently
# cannot change a verdict. What could break it is shared mutable state between workers, which is
# why the plant collapses the per-declaration sandbox path to a single shared one.
# ==================================================================================================
if diff -q "$TMP/out1" "$TMP/out4" >/dev/null 2>&1; then
  ok "PP1: PLANT_JOBS=1 and PLANT_JOBS=4 produce identical output"
else
  bad "PP1: the four-worker run disagrees with the one-worker run — $(diff "$TMP/out1" "$TMP/out4" | grep -c '^[<>]') differing line(s); concurrency changed a verdict"
fi

# ==================================================================================================
# PP2 — the fixture's non-firing plant is REPORTED, in both runs. Without this, PP1 is satisfied by
# a registry that finds nothing twice: two empty results are identical results. D9 mutates a marker
# no assertion reads, so the harness stays green and the registry must say so.
# ==================================================================================================
_d9_1=$(grep -c "delta.test.sh \[D9\] — the assertion still passed with the mechanism removed" "$TMP/out1" || true)
_d9_4=$(grep -c "delta.test.sh \[D9\] — the assertion still passed with the mechanism removed" "$TMP/out4" || true)
if [ "${_d9_1:-0}" -eq 1 ] && [ "${_d9_4:-0}" -eq 1 ] && grep -q "^FAIL: PC1 " "$TMP/out1"; then
  ok "PP2: the plant that cannot fire is reported as not fired, in both runs"
else
  bad "PP2: the deliberately non-firing plant was reported $_d9_1 time(s) at one worker and $_d9_4 at four — a registry that credits it is the failure this file exists to catch"
fi

# ==================================================================================================
# PP3 — verdicts are reported in DECLARATION order, not completion order. The fixture's sleeps make
# the two orders opposite, so an aggregation keyed on whichever worker finished first is visible
# here rather than in a CI log nobody diffs.
# ==================================================================================================
_seen=$(grep '^PASS:   plant ' "$TMP/out4" | sed 's/.*\[\([A-Z0-9]*\)\].*/\1/' | tr '\n' ' ')
# Declaration order is the COLLECTOR's order, which is the glob's: alpha, beta, delta, gamma. Not
# the order the fixture was written in, and not the order the harnesses finish in — those are the
# two orders this assertion exists to tell apart.
_want="A1 A2 A3 B1 B2 B3 D1 D2 C1 C2 C3 "
if [ "$_seen" = "$_want" ]; then
  ok "PP3: verdicts are aggregated in declaration order under concurrency"
else
  bad "PP3: four-worker verdict order was [$_seen], declaration order is [$_want] — an output that reshuffles per run cannot be diffed against anything"
fi

# ==================================================================================================
# PP4 — a sandbox is freed when its verdict is written, not at exit. At 381 plants the retained
# copies were ~8.4 GB of peak disk that nothing reads back. Sampled DURING the one-worker run: at
# one worker at most one mutation sandbox may exist at a time.
#
# The lower bound is not decoration. A sampler that never observed a sandbox would report zero, and
# zero is indistinguishable from "freed immediately" — rule 4, applied to this file's own instrument.
# ==================================================================================================
if [ "$MAXSBX" -ge 1 ] && [ "$MAXSBX" -le 2 ]; then
  ok "PP4: at most $MAXSBX mutation sandbox existed at once under one worker (freed at verdict time)"
elif [ "$MAXSBX" -eq 0 ]; then
  bad "PP4: the sampler never observed a sandbox — it did not measure, which is not the same reading as 'none were retained'"
else
  bad "PP4: $MAXSBX mutation sandboxes coexisted under ONE worker — they are being retained until exit, which is the ~8.4 GB peak issue #350 measured"
fi

# ==================================================================================================
# PP5 — an unusable PLANT_JOBS resolves DOWNWARDS to one worker. Every failure in the resolution
# chain must land on the behaviour this file had before it was parallel; an unreadable core count
# must never become an unbounded fan-out on a runner nobody has measured.
# ==================================================================================================
if diff -q "$TMP/out1" "$TMP/outbad" >/dev/null 2>&1; then
  ok "PP5: PLANT_JOBS=abc resolves to one worker and reproduces the one-worker run exactly"
else
  bad "PP5: PLANT_JOBS=abc did not behave as one worker — $(diff "$TMP/out1" "$TMP/outbad" | grep -c '^[<>]') differing line(s)"
fi

# PPZ — assertion-count floor (ADR-0083's vanishing-assertion class). No plant is declared on it:
# a floor absorbs its own plant (rule 10), and it is here as a vacuity guard, not as a pinned claim.
_total=$((PASS + FAIL))
if [ "$_total" -ge 6 ]; then ok "PPZ assertion-count floor ($_total >= 6)"
else bad "PPZ assertion count fell to $_total (floor 6) — assertions vanished"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
