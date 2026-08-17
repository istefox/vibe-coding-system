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
# plant: PP3 | plugin/scripts/tests/plant-check.sh | for _i in $(seq "$SHARD" "$SHARDS" "$DECL_N"); do | for _i in $(seq "$DECL_N" -1 1); do
# plant: PP4 | plugin/scripts/tests/plant-check.sh | rm -rf "$SBX"    # freed at verdict time, not at exit (issue #350) | : # sandbox deliberately kept
# plant: PP5 | plugin/scripts/tests/plant-check.sh | case "$JOBS" in ''|*[!0-9]*) JOBS=1 ;; esac | case "$JOBS" in ''|*[!0-9]*) : ;; esac
# plant: PP6 | plugin/scripts/tests/plant-check.sh | printf '^FAIL: %s:?([[:space:]]|$)' | printf '^FAIL: %s'
# plant: PP7 | plugin/scripts/tests/plant-check.sh | [ "$nfd" -lt 3 ] || [ "$nfd" -gt 4 ] | false
# plant: PP8 | plugin/scripts/tests/plant-check.sh | out.append('\n'); i += 2; continue | pass
# plant: PP9 | plugin/scripts/tests/plant-check.sh | out.append('\\'); i += 2; continue | pass
#
# TASK 6 (issue #447, ADR-0151) — the twelve plants for PS0-PS10 (PS3b included). Each needle was
# chosen against the actual mechanism in plant-check.sh, not against the plan's looser sketch —
# PS2 in particular anchors on the unique "(D3, R-05)" comment immediately above the dispatch line,
# because the bare stride `seq "$SHARD" "$SHARDS" "$DECL_N"` occurs twice (dispatch and aggregation)
# and a needle ending before the dispatch line's own ` | ` avoids a five-field BADPLANT declaration.
# PS11 carries no plant (declared inline at its assertion, Task 2): `.github/` is not a legal plant
# target.
#
# R-11 — "every new assertion is seen RED against a declared plant, with the declaration beside it
# in the registry" — is answered by THIS block and by nothing else. The id is cited here rather than
# left to be matched repo-wide: seven other harnesses declare an `R-11` of their own, so without
# this line the coverage gate resolves it against a stranger's file and reads as covered while this
# feature's own proof goes unnamed (CLAUDE.md rule 18, ADR-0138).
# plant: PS0  | plugin/scripts/tests/plant-check.sh | write_artifact "$PLANT_ARTIFACT" | :
# plant: PS1  | plugin/scripts/tests/plant-check.sh | SHARDS="${PLANT_SHARDS:-1}" | SHARDS="${PLANT_SHARDS:-2}"
# plant: PS2  | plugin/scripts/tests/plant-check.sh | unchanged (D3, R-05). seq "$SHARD" | unchanged (D3, R-05).\nseq "1"
# plant: PS3  | plugin/scripts/tests/plant-check.sh | printf 'PC-DEFERRED shard %s/%s | printf 'PC-QUIET shard %s/%s
# plant: PS3b | plugin/scripts/tests/plant-check.sh | [ "$SHARDS" -gt 1 ] && SHARDED=1 | [ "$SHARDS" -gt 99 ] && SHARDED=1
# plant: PS4  | plugin/scripts/tests/plant-check.sh | printf 'PC-REFUSED %s\n' "$1" >&2 exit 2 | :
# plant: PS5  | plugin/scripts/tests/plant-check.sh | _cov_missing="$_cov_missing $_i" | :
# plant: PS6  | plugin/scripts/tests/plant-check.sh | printf 'PC-UNION-NORUN %s\n' "$1" >&2 exit 3 | printf 'PC-UNION-NORUN %s\n' "$1" >&2 exit 0
# plant: PS7  | plugin/scripts/tests/plant-check.sh | assert_pc3 "$U_FILES_N" | :
# plant: PS8  | plugin/scripts/tests/plant-check.sh | [ "${2:-}" = "success" ] | [ "${2:-}" != "nonesuch" ]
# plant: PS9  | plugin/scripts/tests/plant-check.sh | [ "$_sum" -eq "$U_DECL_N" ] | true
# plant: PS10 | plugin/scripts/tests/plant-check.sh | _cov_dup="$_cov_dup $_i" | :
#
# PS12 (issue #447, ADR-0151 correction — the registry must not leak its own PLANT_ARTIFACT /
# PLANT_SHARD / PLANT_SHARDS into the harness it runs, worker mode's own invocation line).
# plant: PS12 | plugin/scripts/tests/plant-check.sh | unset PLANT_ARTIFACT PLANT_SHARD PLANT_SHARDS; bash "$SBX/staging/plugin/scripts/tests/$tfile" 2>&1 | bash "$SBX/staging/plugin/scripts/tests/$tfile" 2>&1
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

# ART/SEQ — issue #447, ADR-0151 (Task 2). The one-worker run below is re-used as the SEQUENTIAL arm
# of the shard equivalence proof by adding PLANT_ARTIFACT to it, rather than paying for a sixth
# registry invocation just to get a sequential artifact. ART holds the four SHARD artifacts built
# later in this file; SEQ is the one sequential artifact.
ART="$TMP/artifacts"; mkdir -p "$ART"
SEQ="$TMP/plant-seq.tsv"

PLANT_WORKROOT="$SBXWATCH" PLANT_JOBS=1 PLANT_ARTIFACT="$SEQ" bash "$FIXPC" >"$TMP/out1" 2>&1 &
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

# ==================================================================================================
# TASK 1 — shard-mode, default-equivalence and refusal assertions (issue #447, ADR-0151, plan
# 2026-08-17-447-shard-the-plant-registry). PS1/PS3/PS3b/PS4 pin the shard-selection mode
# `plant-check.sh` does not have yet — no PLANT_SHARDS, no PLANT_SHARD. EXPECTED RED ON ARRIVAL
# (Batch A). Plants are declared later, in Task 6: declaring one now against a mechanism that does
# not exist would be a BADPLANT, not a plant.
#
# Re-uses the FIX fixture already built above (13 plants, 5 harnesses) — no third fixture.
# ==================================================================================================

# ---- PS1 (R-05) ----------------------------------------------------------------------------------
# With PLANT_SHARD/PLANT_SHARDS unset, plant-check.sh must behave EXACTLY as PLANT_SHARDS=1
# PLANT_SHARD=1 — byte for byte (ADR-0151 D3). The equivalence is asserted, never assumed.
PLANT_JOBS=1 bash "$FIXPC" >"$TMP/ps1_unset" 2>&1
PLANT_JOBS=1 PLANT_SHARDS=1 PLANT_SHARD=1 bash "$FIXPC" >"$TMP/ps1_explicit" 2>&1
if diff -q "$TMP/ps1_unset" "$TMP/ps1_explicit" >/dev/null 2>&1 \
   && grep -q '^PASS: PC0' "$TMP/ps1_unset" && grep -q '^PASS: PC0' "$TMP/ps1_explicit"; then
  ok "PS1 (R-05): PLANT_SHARDS/PLANT_SHARD unset behaves exactly as PLANT_SHARDS=1 PLANT_SHARD=1, byte for byte"
else
  bad "PS1 (R-05): unset and explicit-1 runs disagree — $(diff "$TMP/ps1_unset" "$TMP/ps1_explicit" 2>/dev/null | grep -c '^[<>]') differing line(s), or PC0 is missing from one/both run(s) (two crashed runs would otherwise satisfy an empty diff)"
fi

# ---- PS3 (R-06) ------------------------------------------------------------------------------------
# In shard mode the script must say, once, that it deferred the population assertions, and NAME all
# four of them — a token that stops naming what it defers is a token that stopped being a report.
PLANT_JOBS=1 PLANT_SHARDS=4 PLANT_SHARD=2 bash "$FIXPC" >"$TMP/ps3_shard2" 2>&1
_ps3_n=$(grep -c 'PC-DEFERRED shard 2/4' "$TMP/ps3_shard2" 2>/dev/null || true)
_ps3_line=$(grep 'PC-DEFERRED shard 2/4' "$TMP/ps3_shard2" 2>/dev/null | head -1)
if [ "${_ps3_n:-0}" -eq 1 ] \
   && printf '%s' "$_ps3_line" | grep -q 'PC0' \
   && printf '%s' "$_ps3_line" | grep -q 'PC3' \
   && printf '%s' "$_ps3_line" | grep -q 'PC5b' \
   && printf '%s' "$_ps3_line" | grep -q 'Z1'; then
  ok "PS3 (R-06): PLANT_SHARDS=4 PLANT_SHARD=2 prints exactly one PC-DEFERRED shard 2/4 line naming PC0, PC3, PC5b and Z1"
else
  bad "PS3 (R-06): PC-DEFERRED line(s) matching 'PC-DEFERRED shard 2/4' = ${_ps3_n:-0} (want 1), content [$_ps3_line] — the deferral token is missing or stopped naming what it defers"
fi

# ---- PS3b (R-02, R-06) -----------------------------------------------------------------------------
# The negative and the positive twin, together (rule 8): the four population assertions must NOT run
# inside a shard (re-using PS3's shard-2 run), and must ALL run — with no PC-DEFERRED — at
# PLANT_SHARDS=1 (re-using PS1's explicit-1 run). Without both halves this is satisfied by a
# registry that prints nothing at all.
_ps3b_shard_leak=0
for _tok in PC0 PC3 PC5b Z1; do
  grep -qE "^(PASS|FAIL): ${_tok}[: ]" "$TMP/ps3_shard2" 2>/dev/null && _ps3b_shard_leak=1
done
_ps3b_s1_ok=1
for _tok in PC0 PC3 PC5b Z1; do
  grep -qE "^(PASS|FAIL): ${_tok}[: ]" "$TMP/ps1_explicit" 2>/dev/null || _ps3b_s1_ok=0
done
grep -q 'PC-DEFERRED' "$TMP/ps1_explicit" 2>/dev/null && _ps3b_s1_ok=0
if [ "$_ps3b_shard_leak" -eq 0 ] && [ "$_ps3b_s1_ok" -eq 1 ]; then
  ok "PS3b (R-02, R-06): PC0/PC3/PC5b/Z1 do not run under PLANT_SHARDS=4 PLANT_SHARD=2, and all four run — with no PC-DEFERRED — at PLANT_SHARDS=1"
else
  bad "PS3b (R-02, R-06): shard-mode leaked a population assertion (leak=$_ps3b_shard_leak) or PLANT_SHARDS=1 failed to run all four cleanly (ok=$_ps3b_s1_ok)"
fi

# ---- PS4 (R-08) --------------------------------------------------------------------------------------
# Five malformed slice specifications must each REFUSE — exit 2, a PC-REFUSED line on stderr, and no
# "plant .* fired" line — never selecting the whole population or none of it silently (ADR-0151 D4).
# Exit code, the stderr token and the fired-line absence are each checked SEPARATELY, never combined
# into one condition that could pass for the wrong reason.
_ps4_fail=""

PLANT_JOBS=1 PLANT_SHARDS=0 bash "$FIXPC" >"$TMP/ps4_shards0.out" 2>"$TMP/ps4_shards0.err"; _ps4_rc=$?
[ "$_ps4_rc" -eq 2 ] || _ps4_fail="$_ps4_fail shards0:exit=$_ps4_rc"
grep -q '^PC-REFUSED' "$TMP/ps4_shards0.err" 2>/dev/null || _ps4_fail="$_ps4_fail shards0:no-PC-REFUSED-on-stderr"
grep -qE 'plant .* fired' "$TMP/ps4_shards0.out" "$TMP/ps4_shards0.err" 2>/dev/null && _ps4_fail="$_ps4_fail shards0:a-plant-fired"

PLANT_JOBS=1 PLANT_SHARDS=abc bash "$FIXPC" >"$TMP/ps4_shardsAbc.out" 2>"$TMP/ps4_shardsAbc.err"; _ps4_rc=$?
[ "$_ps4_rc" -eq 2 ] || _ps4_fail="$_ps4_fail shardsAbc:exit=$_ps4_rc"
grep -q '^PC-REFUSED' "$TMP/ps4_shardsAbc.err" 2>/dev/null || _ps4_fail="$_ps4_fail shardsAbc:no-PC-REFUSED-on-stderr"
grep -qE 'plant .* fired' "$TMP/ps4_shardsAbc.out" "$TMP/ps4_shardsAbc.err" 2>/dev/null && _ps4_fail="$_ps4_fail shardsAbc:a-plant-fired"

PLANT_JOBS=1 PLANT_SHARD=0 bash "$FIXPC" >"$TMP/ps4_shard0.out" 2>"$TMP/ps4_shard0.err"; _ps4_rc=$?
[ "$_ps4_rc" -eq 2 ] || _ps4_fail="$_ps4_fail shard0:exit=$_ps4_rc"
grep -q '^PC-REFUSED' "$TMP/ps4_shard0.err" 2>/dev/null || _ps4_fail="$_ps4_fail shard0:no-PC-REFUSED-on-stderr"
grep -qE 'plant .* fired' "$TMP/ps4_shard0.out" "$TMP/ps4_shard0.err" 2>/dev/null && _ps4_fail="$_ps4_fail shard0:a-plant-fired"

PLANT_JOBS=1 PLANT_SHARD=5 PLANT_SHARDS=4 bash "$FIXPC" >"$TMP/ps4_shardOOR.out" 2>"$TMP/ps4_shardOOR.err"; _ps4_rc=$?
[ "$_ps4_rc" -eq 2 ] || _ps4_fail="$_ps4_fail shardOOR:exit=$_ps4_rc"
grep -q '^PC-REFUSED' "$TMP/ps4_shardOOR.err" 2>/dev/null || _ps4_fail="$_ps4_fail shardOOR:no-PC-REFUSED-on-stderr"
grep -qE 'plant .* fired' "$TMP/ps4_shardOOR.out" "$TMP/ps4_shardOOR.err" 2>/dev/null && _ps4_fail="$_ps4_fail shardOOR:a-plant-fired"

PLANT_JOBS=1 PLANT_SHARD=abc bash "$FIXPC" >"$TMP/ps4_shardAbc.out" 2>"$TMP/ps4_shardAbc.err"; _ps4_rc=$?
[ "$_ps4_rc" -eq 2 ] || _ps4_fail="$_ps4_fail shardAbc:exit=$_ps4_rc"
grep -q '^PC-REFUSED' "$TMP/ps4_shardAbc.err" 2>/dev/null || _ps4_fail="$_ps4_fail shardAbc:no-PC-REFUSED-on-stderr"
grep -qE 'plant .* fired' "$TMP/ps4_shardAbc.out" "$TMP/ps4_shardAbc.err" 2>/dev/null && _ps4_fail="$_ps4_fail shardAbc:a-plant-fired"

if [ -z "$_ps4_fail" ]; then
  ok "PS4 (R-08): five malformed slice specs (SHARDS=0, SHARDS=abc, SHARD=0, SHARD=5/SHARDS=4, SHARD=abc) each exit 2 with PC-REFUSED on stderr and run no plant"
else
  bad "PS4 (R-08): malformed slice spec(s) not refused correctly:$_ps4_fail"
fi

# ==================================================================================================
# TASK 2 — the artifact, union and leg-gate assertions (issue #447, ADR-0151). Still RED: --union and
# --require-legs do not exist in plant-check.sh yet, so an unrecognised argument is silently ignored
# and the fixture's full (unsharded) registry runs instead — which is EXACTLY the trap rule 7 warns
# about: two runs that both did nothing can look identical to two runs that agree. Several checks
# below therefore guard the DENOMINATOR explicitly (a V record actually found, a non-empty artifact,
# an exact population count) rather than trust a coincidental exit code alone.
#
# The four shard artifacts are built ONCE here and every negative case below derives from editing
# COPIES of them — the union builds no sandboxes, so each extra case costs milliseconds.
# ==================================================================================================
for _k in 1 2 3 4; do
  PLANT_JOBS=1 PLANT_SHARDS=4 PLANT_SHARD="$_k" PLANT_ARTIFACT="$ART/plant-shard-$_k.tsv" \
    bash "$FIXPC" >"$TMP/ps0_shard$_k.out" 2>&1
done

# ---- PS0 — the denominator for everything below (rule 7). ------------------------------------------
_ps0_files=0
for _k in 1 2 3 4; do [ -f "$ART/plant-shard-$_k.tsv" ] && _ps0_files=$((_ps0_files + 1)); done
_ps0_m_ok=1
for _k in 1 2 3 4; do
  _ps0_mn=$(awk -F'\t' -v kk="$_k" '$1=="M" && $2=="shard" && $3==kk' "$ART/plant-shard-$_k.tsv" 2>/dev/null | grep -c . || true)
  [ "${_ps0_mn:-0}" -eq 1 ] || _ps0_m_ok=0
done
_ps0_v_total=0
for _k in 1 2 3 4; do
  _ps0_vn=$(awk -F'\t' '$1=="V"' "$ART/plant-shard-$_k.tsv" 2>/dev/null | grep -c . || true)
  _ps0_v_total=$((_ps0_v_total + ${_ps0_vn:-0}))
done
_ps0_seq_v=$(awk -F'\t' '$1=="V"' "$SEQ" 2>/dev/null | grep -c . || true)
if [ "$_ps0_files" -eq 4 ] && [ "$_ps0_m_ok" -eq 1 ] \
   && [ "$_ps0_v_total" -eq 13 ] && [ "${_ps0_seq_v:-0}" -eq 13 ]; then
  ok "PS0: four shard artifacts exist, each carries exactly one M shard k record, the V records total 13 across shards, and the sequential artifact carries 13"
else
  bad "PS0: files=$_ps0_files/4, M-records-ok=$_ps0_m_ok, shard-V-total=$_ps0_v_total (want 13), sequential-V=${_ps0_seq_v:-0} (want 13) — every assertion below compares nothing to nothing without this"
fi

# ---- PS2 (R-05, and R-12's in-CI counterpart) --------------------------------------------------------
awk -F'\t' '$1=="V"' "$ART/plant-shard-1.tsv" "$ART/plant-shard-2.tsv" "$ART/plant-shard-3.tsv" "$ART/plant-shard-4.tsv" 2>/dev/null \
  | sort -t "$(printf '\t')" -k2,2n >"$TMP/ps2_union_v"
awk -F'\t' '$1=="V"' "$SEQ" 2>/dev/null >"$TMP/ps2_seq_v"
_ps2_seq_n=$(grep -c . "$TMP/ps2_seq_v" 2>/dev/null || true)
if [ "${_ps2_seq_n:-0}" -eq 13 ] && diff -q "$TMP/ps2_union_v" "$TMP/ps2_seq_v" >/dev/null 2>&1; then
  ok "PS2 (R-05, R-12): the four shards' V records, sorted by declaration index, equal the sequential artifact's V records byte for byte"
else
  bad "PS2 (R-05, R-12): sequential V-record count=${_ps2_seq_n:-0} (want 13), or sharded/sequential V streams disagree — $(diff "$TMP/ps2_union_v" "$TMP/ps2_seq_v" 2>/dev/null | grep -c '^[<>]') differing line(s)"
fi

# ---- PS5 (R-09, R-10) ----------------------------------------------------------------------------------
_ps5_dir="$TMP/ps5"; rm -rf "$_ps5_dir"; cp -R "$ART" "$_ps5_dir" 2>/dev/null
_ps5_removed_idx=$(awk -F'\t' '$1=="V"{print $2; exit}' "$ART/plant-shard-1.tsv" 2>/dev/null)
if [ -f "$_ps5_dir/plant-shard-1.tsv" ]; then
  awk -F'\t' 'BEGIN{done=0} $1=="V" && done==0 {done=1; next} {print}' "$_ps5_dir/plant-shard-1.tsv" >"$_ps5_dir/plant-shard-1.tsv.tmp" 2>/dev/null \
    && mv "$_ps5_dir/plant-shard-1.tsv.tmp" "$_ps5_dir/plant-shard-1.tsv"
fi
bash "$FIXPC" --union "$_ps5_dir" >"$TMP/ps5.out" 2>"$TMP/ps5.err"; _ps5_rc=$?
if [ "$_ps5_rc" -eq 1 ] && [ -n "${_ps5_removed_idx:-}" ] \
   && grep -q "$_ps5_removed_idx" "$TMP/ps5.out" "$TMP/ps5.err" 2>/dev/null; then
  ok "PS5 (R-09, R-10): a deleted V record (index $_ps5_removed_idx) with all four artifacts present makes --union exit 1 and name the missing index"
else
  bad "PS5 (R-09, R-10): --union exited $_ps5_rc (want 1) and did not clearly name the missing index '${_ps5_removed_idx:-<none: no V record available to remove — the artifact mechanism does not exist yet>}' — a needs-only design cannot see this case"
fi

# ---- PS6 (R-02, R-10) ----------------------------------------------------------------------------------
_ps6a_dir="$TMP/ps6a"; rm -rf "$_ps6a_dir"; cp -R "$ART" "$_ps6a_dir" 2>/dev/null
rm -f "$_ps6a_dir/plant-shard-3.tsv"
bash "$FIXPC" --union "$_ps6a_dir" >"$TMP/ps6a.out" 2>"$TMP/ps6a.err"; _ps6a_rc=$?
_ps6a_line=$(grep '^PC-UNION-NORUN' "$TMP/ps6a.out" "$TMP/ps6a.err" 2>/dev/null | head -1)
_ps6a_ok=0
[ "$_ps6a_rc" -eq 3 ] && [ -n "$_ps6a_line" ] && printf '%s' "$_ps6a_line" | grep -q '3' && _ps6a_ok=1

_ps6b_dir="$TMP/ps6b"; rm -rf "$_ps6b_dir"; cp -R "$ART" "$_ps6b_dir" 2>/dev/null
if [ -f "$_ps6b_dir/plant-shard-3.tsv" ]; then
  awk -F'\t' '$1=="M"' "$_ps6b_dir/plant-shard-3.tsv" >"$_ps6b_dir/plant-shard-3.tsv.tmp" 2>/dev/null \
    && mv "$_ps6b_dir/plant-shard-3.tsv.tmp" "$_ps6b_dir/plant-shard-3.tsv"
fi
bash "$FIXPC" --union "$_ps6b_dir" >"$TMP/ps6b.out" 2>"$TMP/ps6b.err"; _ps6b_rc=$?
_ps6b_ok=0
[ "$_ps6b_rc" -eq 1 ] && grep -qE '^FAIL: PC6' "$TMP/ps6b.out" "$TMP/ps6b.err" 2>/dev/null && _ps6b_ok=1

if [ "$_ps6a_ok" -eq 1 ] && [ "$_ps6b_ok" -eq 1 ]; then
  ok "PS6 (R-02, R-10): a wholly missing artifact is exit 3 with PC-UNION-NORUN naming shard 3; an artifact with zero V records is exit 1 via PC6's coverage check — neither reads as clean"
else
  bad "PS6 (R-02, R-10): missing-artifact case exit=$_ps6a_rc ok=$_ps6a_ok, zero-V-records case exit=$_ps6b_rc ok=$_ps6b_ok — want 3/PC-UNION-NORUN naming shard 3, and 1/FAIL: PC6"
fi

# ---- PS7 (R-02) -----------------------------------------------------------------------------------------
bash "$FIXPC" --union "$ART" >"$TMP/ps7.out" 2>"$TMP/ps7.err"; _ps7_rc=$?
_ps7_counts_ok=1
for _tok in PC0 PC3 PC5b Z1; do
  _ps7_c=$(grep -cE "^(PASS|FAIL): ${_tok}[: ]" "$TMP/ps7.out" 2>/dev/null || true)
  [ "${_ps7_c:-0}" -eq 1 ] || _ps7_counts_ok=0
done
_ps7_shards_clean=1
for _k in 1 2 3 4; do
  for _tok in PC0 PC3 PC5b Z1; do
    grep -qE "^(PASS|FAIL): ${_tok}[: ]" "$TMP/ps0_shard$_k.out" 2>/dev/null && _ps7_shards_clean=0
  done
done
if [ "$_ps7_rc" -eq 0 ] && [ "$_ps7_counts_ok" -eq 1 ] && [ "$_ps7_shards_clean" -eq 1 ]; then
  ok "PS7 (R-02): --union over the four unmodified artifacts exits 0 with PC0/PC3/PC5b/Z1 each appearing exactly once, and no shard's own run reports any of them"
else
  bad "PS7 (R-02): union exit=$_ps7_rc (want 0), each-token-exactly-once=$_ps7_counts_ok, shards-silent-on-population-checks=$_ps7_shards_clean — PC0/PC3/PC5b/Z1 must be evaluated exactly once, in the union and nowhere else"
fi

# ---- PS8 (R-07) ------------------------------------------------------------------------------------------
bash "$FIXPC" --require-legs success >"$TMP/ps8_success.out" 2>"$TMP/ps8_success.err"; _ps8_ok_rc=$?
_ps8_bad=""

bash "$FIXPC" --require-legs failure >"$TMP/ps8_failure.out" 2>"$TMP/ps8_failure.err"; _ps8_rc=$?
[ "$_ps8_rc" -eq 1 ] || _ps8_bad="$_ps8_bad failure:exit=$_ps8_rc"
grep -q 'failure' "$TMP/ps8_failure.out" "$TMP/ps8_failure.err" 2>/dev/null || _ps8_bad="$_ps8_bad failure:state-not-printed"

bash "$FIXPC" --require-legs cancelled >"$TMP/ps8_cancelled.out" 2>"$TMP/ps8_cancelled.err"; _ps8_rc=$?
[ "$_ps8_rc" -eq 1 ] || _ps8_bad="$_ps8_bad cancelled:exit=$_ps8_rc"
grep -q 'cancelled' "$TMP/ps8_cancelled.out" "$TMP/ps8_cancelled.err" 2>/dev/null || _ps8_bad="$_ps8_bad cancelled:state-not-printed"

bash "$FIXPC" --require-legs skipped >"$TMP/ps8_skipped.out" 2>"$TMP/ps8_skipped.err"; _ps8_rc=$?
[ "$_ps8_rc" -eq 1 ] || _ps8_bad="$_ps8_bad skipped:exit=$_ps8_rc"
grep -q 'skipped' "$TMP/ps8_skipped.out" "$TMP/ps8_skipped.err" 2>/dev/null || _ps8_bad="$_ps8_bad skipped:state-not-printed"

bash "$FIXPC" --require-legs "" >"$TMP/ps8_empty.out" 2>"$TMP/ps8_empty.err"; _ps8_rc=$?
[ "$_ps8_rc" -eq 1 ] || _ps8_bad="$_ps8_bad empty:exit=$_ps8_rc"
{ [ -s "$TMP/ps8_empty.out" ] || [ -s "$TMP/ps8_empty.err" ]; } || _ps8_bad="$_ps8_bad empty:no-output"

bash "$FIXPC" --require-legs Success >"$TMP/ps8_wrongcase.out" 2>"$TMP/ps8_wrongcase.err"; _ps8_rc=$?
[ "$_ps8_rc" -eq 1 ] || _ps8_bad="$_ps8_bad wrongcase:exit=$_ps8_rc"
grep -q 'Success' "$TMP/ps8_wrongcase.out" "$TMP/ps8_wrongcase.err" 2>/dev/null || _ps8_bad="$_ps8_bad wrongcase:state-not-printed"

if [ "$_ps8_ok_rc" -eq 0 ] && [ -z "$_ps8_bad" ]; then
  ok "PS8 (R-07): --require-legs success exits 0; failure/cancelled/skipped/empty/Success each exit 1 with the observed state printed"
else
  bad "PS8 (R-07): success-arm exit=$_ps8_ok_rc (want 0), reject-arm failure(s):$_ps8_bad"
fi

# ---- PS9 (R-01) -------------------------------------------------------------------------------------------
_ps9_imbalance_n=$(grep -c '^PC-IMBALANCE' "$TMP/ps7.out" 2>/dev/null || true)
_ps9_dir="$TMP/ps9"; rm -rf "$_ps9_dir"; cp -R "$ART" "$_ps9_dir" 2>/dev/null
if [ -f "$_ps9_dir/plant-shard-2.tsv" ]; then
  awk -F'\t' 'BEGIN{OFS="\t"} $1=="M" && $2=="slice" {$3=$3+1} {print}' "$_ps9_dir/plant-shard-2.tsv" >"$_ps9_dir/plant-shard-2.tsv.tmp" 2>/dev/null \
    && mv "$_ps9_dir/plant-shard-2.tsv.tmp" "$_ps9_dir/plant-shard-2.tsv"
fi
bash "$FIXPC" --union "$_ps9_dir" >"$TMP/ps9.out" 2>"$TMP/ps9.err"
_ps9_pc7_red=$(grep -cE '^FAIL: PC7' "$TMP/ps9.out" 2>/dev/null || true)
if [ "${_ps9_imbalance_n:-0}" -eq 1 ] && [ "${_ps9_pc7_red:-0}" -ge 1 ]; then
  ok "PS9 (R-01): the clean union prints exactly one PC-IMBALANCE line, and PC7 goes RED when a shard's M slice disagrees with its actual V-record count"
else
  bad "PS9 (R-01): PC-IMBALANCE line(s) on the clean run=${_ps9_imbalance_n:-0} (want 1), PC7-red after doctoring M slice=${_ps9_pc7_red:-0} (want >=1)"
fi

# ---- PS10 (R-09, R-10) -------------------------------------------------------------------------------------
_ps10_dir="$TMP/ps10"; rm -rf "$_ps10_dir"; cp -R "$ART" "$_ps10_dir" 2>/dev/null
_ps10_row=$(awk -F'\t' '$1=="V"{print; exit}' "$ART/plant-shard-3.tsv" 2>/dev/null)
_ps10_dup_idx=$(printf '%s' "$_ps10_row" | awk -F'\t' '{print $2}')
if [ -n "$_ps10_row" ] && [ -f "$_ps10_dir/plant-shard-2.tsv" ]; then
  printf '%s\n' "$_ps10_row" >>"$_ps10_dir/plant-shard-2.tsv"
fi
bash "$FIXPC" --union "$_ps10_dir" >"$TMP/ps10.out" 2>"$TMP/ps10.err"; _ps10_rc=$?
if [ "$_ps10_rc" -eq 1 ] && [ -n "${_ps10_dup_idx:-}" ] \
   && grep -q "$_ps10_dup_idx" "$TMP/ps10.out" "$TMP/ps10.err" 2>/dev/null; then
  ok "PS10 (R-09, R-10): a V record duplicated across two artifacts (index $_ps10_dup_idx) makes --union exit 1 and name the duplicated index — distinct from PS5's missing-index case"
else
  bad "PS10 (R-09, R-10): --union exited $_ps10_rc (want 1) and did not clearly name the duplicated index '${_ps10_dup_idx:-<none: no V record available to duplicate — the artifact mechanism does not exist yet>}'"
fi

# ---- PS11 (R-03, R-07) -------------------------------------------------------------------------------------
# NO PLANT. `.github/` is copied into the sandbox for tests to read but is not a legal plant target,
# and widening the plant target grammar to reach it is out of scope for this change (ADR-0151 §D11)
# — the same exemption pairs-completeness.test.sh's CI1 already declares for the same file. Its live
# evidence is that it stays RED until Task 7 lands the workflow.
CIY="$TESTS/../../../../.github/workflows/docs-ci.yml"
if [ -f "$CIY" ]; then
  _yaml_job_body() {   # <job-key, e.g. "plant-shard">
    awk -v job="  $1:" '
      $0 == job {f=1; next}
      f && /^  [A-Za-z0-9_-]+:$/ {f=0}
      f {print}
    ' "$CIY"
  }
  _ps11_shard_body=$(_yaml_job_body "plant-shard")
  _ps11_union_body=$(_yaml_job_body "shell-tests")
  _ps11_shard_flat=$(printf '%s' "$_ps11_shard_body" | tr '\n' ' ' | tr -s ' ')
  _ps11_union_flat=$(printf '%s' "$_ps11_union_body" | tr '\n' ' ' | tr -s ' ')
  _ps11_ok=1
  grep -q '^  plant-shard:$' "$CIY" || _ps11_ok=0
  printf '%s' "$_ps11_shard_flat" | grep -qi 'fail-fast: false' || _ps11_ok=0
  printf '%s' "$_ps11_shard_flat" | grep -qiE 'shard: \[1, ?2, ?3, ?4\]' || _ps11_ok=0
  printf '%s' "$_ps11_shard_flat" | grep -qi 'install zsh' || _ps11_ok=0
  grep -q '^  shell-tests:$' "$CIY" || _ps11_ok=0
  printf '%s' "$_ps11_union_flat" | grep -qi 'needs: \[plant-shard\]' || _ps11_ok=0
  printf '%s' "$_ps11_union_flat" | grep -qi 'if: always()' || _ps11_ok=0
  grep -qE '^ +for t in ' "$CIY" || _ps11_ok=0
  printf '%s' "$_ps11_union_flat" | grep -qi -- '--require-legs' || _ps11_ok=0
  printf '%s' "$_ps11_union_flat" | grep -qi -- '--union' || _ps11_ok=0
  if [ "$_ps11_ok" -eq 1 ]; then
    ok "PS11 (R-03, R-07): docs-ci.yml carries a plant-shard job (fail-fast:false, a four-value matrix, a zsh install) and shell-tests carries needs:[plant-shard], if:always(), the unchanged harness-loop line, --require-legs and --union"
  else
    bad "PS11 (R-03, R-07): docs-ci.yml does not yet carry the sharded topology (plant-shard job / matrix / zsh / needs / if:always() / --require-legs / --union) — RED until Task 7 lands the workflow"
  fi
else
  bad "PS11 (R-03, R-07): $CIY not found — cannot evaluate the docs-ci.yml topology"
fi

# ==================================================================================================
# PS12 (issue #447, ADR-0151 correction) — the WORKER-MODE mutation-run invocation must not leak this
# registry's own PLANT_ARTIFACT/PLANT_SHARD/PLANT_SHARDS into the harness it runs. Measured
# 2026-08-17: without the `unset` this plant reverts, a nested invocation of THIS SAME registry (which
# is exactly what every `$FIXPC` call above is) inherits the outer three — one nested run silently
# overwrites the real, outer artifact path with its own fixture verdict stream, and a nested call
# meaning "knobs UNSET" (PS1's and PS3b's own subject) is corrupted into running sharded instead.
#
# A dedicated probe harness (`leakprobe.test.sh`) reports whether it can see the three variables. It
# lives in a THIRD, throwaway fixture built fresh here — never registered in `docs-ci.yml`'s harness
# loop, so this is not a fourth real `*.test.sh` file, the same constraint Task 2 already honoured for
# PS0-PS11. The "reverted" copy of `plant-check.sh` is produced by literally UNDOING the fix's own
# substitution with `sed`, not by a second hand-written mechanism (rule 6): if the fix's wording ever
# changes, this `sed` stops matching, the reverted copy is byte-identical to the clean one, and every
# "must leak" case below goes NOFIRE instead of silently passing — a rotted rewrite fails LOUD, not
# quiet.
#
# Both directions, and each of the three named separately (rule 7 — an assertion satisfied by "both
# runs produced nothing" pins nothing): the CLEAN copy must show no leak with all three set in the
# calling shell; the REVERTED copy must show a leak with all three set, and ALSO with each set alone.
# ==================================================================================================
FIX3="$TMP/fix3"; FIX3B="$TMP/fix3bad"
mkdir -p "$FIX3/staging/plugin/scripts/tests" "$FIX3B/staging/plugin/scripts/tests"
cp "$PC" "$FIX3/staging/plugin/scripts/tests/plant-check.sh"
sed 's#OUT=$(unset PLANT_ARTIFACT PLANT_SHARD PLANT_SHARDS; bash#OUT=$(bash#' "$PC" \
  >"$FIX3B/staging/plugin/scripts/tests/plant-check.sh"

cat >"$FIX3/staging/plugin/scripts/tests/leakprobe.test.sh" <<'LEAKPROBE'
#!/bin/bash
set -u
if [ -z "${PLANT_ARTIFACT:-}" ] && [ -z "${PLANT_SHARD:-}" ] && [ -z "${PLANT_SHARDS:-}" ]; then
  printf 'PASS: LEAK clean\n'
else
  printf 'FAIL: LEAK PLANT_ARTIFACT=%s PLANT_SHARD=%s PLANT_SHARDS=%s\n' "${PLANT_ARTIFACT:-<unset>}" "${PLANT_SHARD:-<unset>}" "${PLANT_SHARDS:-<unset>}"
fi
exit 0
LEAKPROBE
cp "$FIX3/staging/plugin/scripts/tests/leakprobe.test.sh" "$FIX3B/staging/plugin/scripts/tests/leakprobe.test.sh"

FIX3PC="$FIX3/staging/plugin/scripts/tests/plant-check.sh"
FIX3BPC="$FIX3B/staging/plugin/scripts/tests/plant-check.sh"

# leakprobe.test.sh carries no `# plant:` line of its own — it is never mutation-tested for its own
# sake, only run through WORKER MODE directly (rule 6: reusing the real entry point rather than
# re-implementing what it does). The decls file worker mode reads is hand-built accordingly: one
# line, tab-separated, harness name then the same four-field payload collect_decls would have
# produced from a real declaration.
_ps12_mkwork() {   # <workdir>
  mkdir -p "$1/res" "$1/base" "$1/basemiss"
  printf 'leakprobe.test.sh\tLEAK | plugin/scripts/tests/leakprobe.test.sh | exit 0 | exit 0\n' >"$1/decls"
}

_ps12_fail=""

# ---- clean copy, all three set in the calling shell — must NOT leak ------------------------------
_w1="$TMP/ps12w1"; _ps12_mkwork "$_w1"
PLANT_ARTIFACT="$TMP/ps12_leak1.tsv" PLANT_SHARD=2 PLANT_SHARDS=4 \
  bash "$FIX3PC" --worker 1 "$_w1" >/dev/null 2>&1
_k1=$(cat "$_w1/res/1.kind" 2>/dev/null || true)
[ "$_k1" = "NOFIRE" ] || _ps12_fail="$_ps12_fail clean-all-three:kind=${_k1:-<none>}(want NOFIRE)"

# ---- reverted copy, all three set — must leak -----------------------------------------------------
_w2="$TMP/ps12w2"; _ps12_mkwork "$_w2"
PLANT_ARTIFACT="$TMP/ps12_leak2.tsv" PLANT_SHARD=2 PLANT_SHARDS=4 \
  bash "$FIX3BPC" --worker 1 "$_w2" >/dev/null 2>&1
_k2=$(cat "$_w2/res/1.kind" 2>/dev/null || true)
[ "$_k2" = "FIRED" ] || _ps12_fail="$_ps12_fail reverted-all-three:kind=${_k2:-<none>}(want FIRED)"

# ---- reverted copy, ONLY PLANT_ARTIFACT set — must leak on its own --------------------------------
_w3="$TMP/ps12w3"; _ps12_mkwork "$_w3"
PLANT_ARTIFACT="$TMP/ps12_leak3.tsv" \
  bash "$FIX3BPC" --worker 1 "$_w3" >/dev/null 2>&1
_k3=$(cat "$_w3/res/1.kind" 2>/dev/null || true)
[ "$_k3" = "FIRED" ] || _ps12_fail="$_ps12_fail reverted-artifact-only:kind=${_k3:-<none>}(want FIRED)"

# ---- reverted copy, ONLY PLANT_SHARD set — must leak on its own -----------------------------------
_w4="$TMP/ps12w4"; _ps12_mkwork "$_w4"
PLANT_SHARD=2 \
  bash "$FIX3BPC" --worker 1 "$_w4" >/dev/null 2>&1
_k4=$(cat "$_w4/res/1.kind" 2>/dev/null || true)
[ "$_k4" = "FIRED" ] || _ps12_fail="$_ps12_fail reverted-shard-only:kind=${_k4:-<none>}(want FIRED)"

# ---- reverted copy, ONLY PLANT_SHARDS set — must leak on its own ----------------------------------
_w5="$TMP/ps12w5"; _ps12_mkwork "$_w5"
PLANT_SHARDS=4 \
  bash "$FIX3BPC" --worker 1 "$_w5" >/dev/null 2>&1
_k5=$(cat "$_w5/res/1.kind" 2>/dev/null || true)
[ "$_k5" = "FIRED" ] || _ps12_fail="$_ps12_fail reverted-shards-only:kind=${_k5:-<none>}(want FIRED)"

if [ -z "$_ps12_fail" ]; then
  ok "PS12: the mutation-run invocation clears PLANT_ARTIFACT/PLANT_SHARD/PLANT_SHARDS before running the harness — no leak with the fix in place, a leak (individually for each of the three, and combined) with it reverted"
else
  bad "PS12: leak-detection mismatch(es):$_ps12_fail — either the fix leaks or the check pinning it is broken"
fi

# PPZ — assertion-count floor (ADR-0083's vanishing-assertion class). No plant is declared on it:
# a floor absorbs its own plant (rule 10), and it is here as a vacuity guard, not as a pinned claim.
_total=$((PASS + FAIL))
if [ "$_total" -ge 12 ]; then ok "PPZ assertion-count floor ($_total >= 12)"
else bad "PPZ assertion count fell to $_total (floor 12) — assertions vanished"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
