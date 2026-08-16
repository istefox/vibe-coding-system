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
# REACHABLE. Its five harnesses sleep for DESCENDING intervals, so completion order is the reverse
# of declaration order — without that, an aggregation that reported in completion order would look
# correct here and be wrong in CI. One of its plants is deliberately built NOT to fire, because an
# equivalence check between two runs that both found nothing is satisfied by a registry that does
# nothing.
#
# A TRAP THIS FILE HAD TO AVOID, recorded because the next author will meet it: a literal `# plant:`
# at column 1 anywhere in this file is collected by the real registry as THIS file's own
# declaration, fixture or not — the collector greps `^# plant:` across `*.test.sh` and cannot know
# the line was meant for a fixture. The fixture's declarations are therefore written as `@PLANT@`
# and substituted in. Only the seven lines below are this file's real plants.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: PP0 | plugin/scripts/tests/plant-registry-parallel.test.sh | for _h in alpha beta gamma delta epsilon | for _h in alpha
# plant: PP1 | plugin/scripts/tests/plant-check.sh | SBX="$WORK/sbx$IDX" | SBX="$WORK/sbx"
# plant: PP2 | plugin/scripts/tests/plant-check.sh | grep -qE "$(red_re "$aid")" <<PLANT_HARNESS_OUTPUT | grep -qE "" <<PLANT_HARNESS_OUTPUT
# plant: PP3 | plugin/scripts/tests/plant-check.sh | for _i in $(seq 1 "$DECL_N"); do | for _i in $(seq "$DECL_N" -1 1); do
# plant: PP4 | plugin/scripts/tests/plant-check.sh | rm -rf "$SBX"    # freed at verdict time, not at exit (issue #350) | : # sandbox deliberately kept
# plant: PP5 | plugin/scripts/tests/plant-check.sh | case "$JOBS" in ''|*[!0-9]*) JOBS=1 ;; esac | case "$JOBS" in ''|*[!0-9]*) : ;; esac
# plant: PP6 | plugin/scripts/tests/plant-check.sh | printf '^FAIL: %s:?([[:space:]]|$)' | printf '^FAIL: %s'
# plant: PP7 | plugin/scripts/tests/plant-check.sh | [ "$nfd" -lt 3 ] || [ "$nfd" -gt 4 ] | false
# plant: PP8 | plugin/scripts/tests/plant-check.sh | out.append('\n'); i += 2; continue | pass
# plant: PP9 | plugin/scripts/tests/plant-check.sh | out.append('\\'); i += 2; continue | pass
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
# MARK-E1 thirteenth mechanism
# MARK-E1b fourteenth mechanism — E1 is a PREFIX of E1b, which is the whole point
# MARK-UNUSED no assertion depends on this one, by design
DEMO

# Five harnesses, sleeping for DESCENDING intervals so that under concurrency the LAST declarations
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
  if grep -q "MARK-\$_m " "\$D"; then printf 'PASS: %s\n' "\$_m"; else printf 'FAIL: %s\n' "\$_m"; fi
done
exit 0
HARNESS
}

# PP0's own subject. Shrink this list and the fixture stops being able to prove anything, which is
# why PP0 asserts the population the other six assertions are measured against (rule 7).
for _h in alpha beta gamma delta epsilon; do
  case "$_h" in
    alpha) _mk_harness alpha 0.20 A1 A2 A3 ;;
    beta)  _mk_harness beta  0.15 B1 B2 B3 ;;
    gamma) _mk_harness gamma 0.10 C1 C2 C3 ;;
    delta) _mk_harness delta 0.05 D1 D2 D9 ;;
    epsilon) _mk_harness epsilon 0.12 E1 E1b E1b ;;
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
_decl epsilon E1 E1b

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
for _q in alpha beta gamma delta epsilon; do
  _qf="$FIX/staging/plugin/scripts/tests/$_q.test.sh"
  [ -f "$_qf" ] && bash "$_qf" 2>/dev/null | grep -q '^PASS: ' && _fixran=$((_fixran + 1))
done
if [ "${FIXN:-0}" -eq 13 ] && [ "${FIXF:-0}" -eq 5 ] && [ "$_fixran" -eq 5 ] \
   && grep -q "^PASS: PC0 plant declarations discovered (13)$" "$TMP/out1"; then
  ok "PP0: the fixture is 13 plants over 5 harnesses that run, and the registry collected all 13"
else
  bad "PP0: fixture is $FIXN plant(s) over $FIXF file(s) of which $_fixran actually run (expected 13, 5 and 5), or the registry did not collect them — every assertion below would compare nothing to nothing"
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
# ==================================================================================================
# PP6 — a SIBLING's failure does not credit the plant (issue #355, ADR-0145).
#
# The predicate used to be `^FAIL: <aid>` with no right anchor, so a plant declared for `E1` was
# credited when `E1b` failed instead — an entirely different assertion, in the direction that reads
# as coverage. Measured across the real corpus before the change: 33 of 387 plants are exposed to
# such a collision and 0 are mis-credited, which is why the anchor was a no-op there and why this
# fixture has to MANUFACTURE the case the corpus does not currently contain.
#
# `epsilon`'s plant names `E1` and mutates the marker only `E1b` reads. So `E1b` goes red, `E1`
# stays green, and the registry must report that the plant did not fire. Under the old predicate
# this same fixture reported it as fired.
# ==================================================================================================
_pp6=$(grep -c "epsilon.test.sh \[E1\] — the assertion still passed with the mechanism removed" "$TMP/out1" || true)
_pp6_wrong=$(grep -c "plant epsilon.test.sh \[E1\] fired" "$TMP/out1" || true)
if [ "${_pp6:-0}" -eq 1 ] && [ "${_pp6_wrong:-0}" -eq 0 ]; then
  ok "PP6: a sibling's failure (E1b) does not credit the plant declared on E1"
else
  bad "PP6: E1 was credited to E1b's failure — reported not-fired $_pp6 time(s), fired $_pp6_wrong time(s); the fired predicate has lost its right anchor (issue #355)"
fi

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

# ==================================================================================================
# THE DECLARATION GRAMMAR — issue #305, ADR-0149. A SECOND fixture, because the first one's plant
# and file counts are PP0's subject and every assertion above is measured against them.
#
# Four properties, one registry run:
#
#   PP7  a declaration with more than four fields is BADPLANT. Until #305 nothing checked the count
#        while the error message had claimed "need 4 fields" since the registry was written, and one
#        six-field declaration had shipped — `A25`, silently mutating something nobody wrote.
#   PP8  `\n` in the replacement produces a REAL newline, which is what makes an insertion
#        expressible. A `\n` left literal keeps the added text on the existing line, `grep -c` still
#        counts one row, and the plant would report NOFIRE — so this assertion distinguishes.
#   PP9  `\\` produces exactly ONE backslash. G3 says "no double backslash anywhere" and is GREEN
#        after a correct mutation, so the registry must report it NOT fired; a `\\` left as two
#        characters turns it red. G4 carries the same mutation and MUST fire, which is what stops
#        PP9 from being satisfied by a mutation that never landed.
#   PP10 the exactly-one-match rule is unchanged by the new form (R-02): the match is on the NEEDLE,
#        and an insertion whose needle hits twice is BADPLANT like any other.
# ==================================================================================================
FIX2="$TMP/fix2"
mkdir -p "$FIX2/staging/plugin/scripts/tests"
cp "$PC" "$FIX2/staging/plugin/scripts/tests/plant-check.sh"

cat >"$FIX2/staging/plugin/scripts/demo2.sh" <<'DEMO2'
#!/bin/bash
# MARK-G1 a mechanism the three-field form deletes outright
# TABLE-ROW alpha
# BSLASH-HERE none
# TWICE here
# TWICE here
DEMO2

cat >"$FIX2/staging/plugin/scripts/tests/zeta.test.sh" <<'HARNESS2'
#!/bin/bash
set -u
D=$(cd "$(dirname "$0")/.." && pwd)/demo2.sh
if grep -q 'MARK-G1 a mechanism' "$D"; then printf 'PASS: G1\n'; else printf 'FAIL: G1 the marker is gone\n'; fi
_r=$(grep -c 'TABLE-ROW' "$D")
if [ "$_r" -eq 1 ]; then printf 'PASS: G2\n'; else printf 'FAIL: G2 rows=%s\n' "$_r"; fi
if grep -q '\\\\' "$D"; then printf 'FAIL: G3 a double backslash reached the file\n'; else printf 'PASS: G3\n'; fi
if grep -q 'BSLASH-HERE none' "$D"; then printf 'PASS: G4\n'; else printf 'FAIL: G4 the mutation landed\n'; fi
exit 0
HARNESS2

# `@PLANT@` is substituted rather than written literally, for the reason the first fixture gives:
# a literal `# plant:` at column 1 in THIS file would be collected by the real registry.
_decl2() {   # <payload-after-the-marker>
  printf '@PLANT@ %s\n' "$1" | sed 's/@PLANT@/# plant:/' \
    >>"$FIX2/staging/plugin/scripts/tests/zeta.test.sh"
}
_decl2 'G1 | plugin/scripts/demo2.sh | # MARK-G1 a mechanism the three-field form deletes outright'
_decl2 'G2 | plugin/scripts/demo2.sh | # TABLE-ROW alpha | # TABLE-ROW alpha\n# TABLE-ROW beta'
_decl2 'G3 | plugin/scripts/demo2.sh | BSLASH-HERE none | BSLASH-HERE \\x'
_decl2 'G4 | plugin/scripts/demo2.sh | BSLASH-HERE none | BSLASH-HERE \\x'
_decl2 'G5 | plugin/scripts/demo2.sh | echo a | b | c | d'
_decl2 'G6 | plugin/scripts/demo2.sh | # TWICE here | # TWICE here\n# TWICE again'

FIX2PC="$FIX2/staging/plugin/scripts/tests/plant-check.sh"
PLANT_JOBS=2 bash "$FIX2PC" >"$TMP/out2" 2>&1

# The denominator, same lesson as PP0: six declarations over one harness that RUNS, and a verdict
# reported for each. A fixture that stopped being collected would make all four assertions below
# compare nothing to nothing.
#
# The check is on the SIX VERDICTS, not on PC0's line: this fixture is deliberately below PC0's
# own >= 10 floor, so PC0 is red here by construction and says nothing about collection. Reading a
# per-declaration verdict is the stronger denominator anyway — it survives a change to that floor.
_g_ran=0
bash "$FIX2/staging/plugin/scripts/tests/zeta.test.sh" 2>/dev/null | grep -q '^PASS: G1$' && _g_ran=1
_g_decls=$(grep -c '^# plant:' "$FIX2/staging/plugin/scripts/tests/zeta.test.sh" || true)
_g_verdicts=0
for _i in G1 G2 G3 G4 G5 G6; do
  grep -q "zeta.test.sh \[$_i\]" "$TMP/out2" && _g_verdicts=$((_g_verdicts + 1))
done
if [ "$_g_ran" -eq 1 ] && [ "${_g_decls:-0}" -eq 6 ] && [ "$_g_verdicts" -eq 6 ]; then
  ok "PP6b: the grammar fixture is 6 declarations over a harness that runs, and the registry reported a verdict for all 6"
else
  bad "PP6b: fixture ran=$_g_ran, declared=$_g_decls, verdicts=$_g_verdicts (want 1, 6, 6) — PP7 to PP10 assert nothing without it"
fi

if grep -q 'zeta.test.sh \[G5\]: malformed declaration (6 field(s)' "$TMP/out2"; then
  ok "PP7: a six-field declaration is BADPLANT — the ' | '-inside-a-field limit is enforced, not just stated (#305)"
else
  bad "PP7: a six-field declaration was accepted; the needle is being truncated at the first inner ' | ' and the plant mutates something nobody wrote"
fi

_g1=$(grep -c 'plant zeta.test.sh \[G1\] fired' "$TMP/out2" || true)
_g2=$(grep -c 'plant zeta.test.sh \[G2\] fired' "$TMP/out2" || true)
if [ "${_g1:-0}" -eq 1 ] && [ "${_g2:-0}" -eq 1 ]; then
  ok "PP8: the three-field deletion form and the \\n insertion form both fired"
else
  bad "PP8: deletion fired $_g1 time(s) and insertion $_g2 time(s), want 1 each — a literal \\n keeps the added text on one line and grep -c still counts one row"
fi

_g3fired=$(grep -c 'plant zeta.test.sh \[G3\] fired' "$TMP/out2" || true)
_g3quiet=$(grep -c 'zeta.test.sh \[G3\] — the assertion still passed' "$TMP/out2" || true)
_g4=$(grep -c 'plant zeta.test.sh \[G4\] fired' "$TMP/out2" || true)
if [ "${_g3fired:-1}" -eq 0 ] && [ "${_g3quiet:-0}" -eq 1 ] && [ "${_g4:-0}" -eq 1 ]; then
  ok "PP9: \\\\ collapses to exactly one backslash (G3 stays green under the same mutation that fires G4)"
else
  bad "PP9: G3 fired $_g3fired / stayed-green $_g3quiet, G4 fired $_g4 (want 0, 1, 1) — either \\\\ left two backslashes or the mutation never landed"
fi

if grep -q 'zeta.test.sh \[G6\]: needle matched 2 times' "$TMP/out2"; then
  ok "PP10 (R-02): the exactly-one-match rule is unchanged by the insertion form — the match is on the needle"
else
  bad "PP10 (R-02): an insertion whose needle matches twice was not refused; a plant hitting sites it did not intend is a defect in the plant"
fi

# PPZ — assertion-count floor (ADR-0083's vanishing-assertion class). No plant is declared on it:
# a floor absorbs its own plant (rule 10), and it is here as a vacuity guard, not as a pinned claim.
_total=$((PASS + FAIL))
if [ "$_total" -ge 12 ]; then ok "PPZ assertion-count floor ($_total >= 12)"
else bad "PPZ assertion count fell to $_total (floor 12) — assertions vanished"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
