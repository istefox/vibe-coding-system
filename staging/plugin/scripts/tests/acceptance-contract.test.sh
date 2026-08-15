#!/bin/bash
# acceptance-contract.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash acceptance-contract.test.sh
#
# Issue #439 Wave 1 / ADR-0141. The chain's gates check that tests are green, that requirement ids
# are CITED, and that the diff fits a budget. ADR-0138 established that the id check measured
# citation and not implementation. `acceptance-run.sh` + `acceptance-adapter-swift.sh` are the layer
# where an `R-NN` passes only by being EXECUTED and observed.
#
# THE FIXTURES ARE DERIVED FROM A REAL BUNDLE, not from the schema. On 2026-08-15 a throwaway Swift
# package with a passing, a failing and a skipped test was built with `xcodebuild test
# -resultBundlePath` under Xcode 26.6, and `xcrun xcresulttool get test-results tests
# --schema-version 0.1.0` was read. Three things that only the real output shows, each of which
# would have produced a wrong adapter:
#   1. XCTest names arrive as `testR01_greetReturnsHello()` — the id follows the mandatory `test`
#      prefix, so a plain word-boundary rule REJECTS the actual convention.
#   2. `testERROR6_boundaryProbe()` contains `R6`, so a rule without a left boundary binds a
#      stranger. Both traps are live in the fixtures below (A7/A8).
#   3. A Skipped case still carries a `Failure Message` child ("Test skipped - ..."). Any heuristic
#      keyed on that child reads a skip as a failure. `result` is the only authority (A3).
#   `tags` was emitted on zero nodes, so name is the only binding channel available in XCTest.
#
# WHAT IS ENFORCEMENT AND WHAT IS NOT (rule 16). A1-A25 execute the adapter and are mechanical.
# A26-A31 execute the runner. A33-A35 are STRUCTURAL: they pin that a contract sentence is present,
# which is not evidence that a caller obeys it, and no assertion here claims otherwise.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line removes ONE mechanism and names the assertion that must go RED for it.
# plant: A3 | plugin/scripts/acceptance-adapter-swift.sh | elif . == "Skipped" then "SKIP" | elif . == "never" then "SKIP"
# plant: A8 | plugin/scripts/acceptance-adapter-swift.sh | IDRE='(^|[^A-Za-z0-9]|test)R-?([0-9]{1,3})(?![0-9])' | IDRE='()R-?([0-9]{1,3})(?![0-9])'
# plant: A15 | plugin/scripts/acceptance-adapter-swift.sh | no-bound-cases — $NCASES test case(s) ran | no-cases-at-all — $NCASES test case(s) ran
# plant: A22 | plugin/scripts/acceptance-adapter-swift.sh | if [ "$DECL_N" -eq 0 ]; then | if false; then
# plant: A25 | plugin/scripts/acceptance-adapter-swift.sh | P=$(awk -F'\t' '$2=="PASS"' "$TMP/verdicts.tsv" | wc -l | tr -d ' ') | P=0
# plant: A27 | plugin/scripts/acceptance-run.sh | [ "$CMD" = "NONE" ] && halt "opted-out | [ "$CMD" = "__never__" ] && halt "opted-out
# plant: A29 | plugin/scripts/acceptance-run.sh | if ! { [ -f "$TRUST" ] && grep -F -x -q -- "$LINE" "$TRUST" 2>/dev/null; }; then | if false; then
# plant: A34 | plugin/scripts/acceptance-run.sh | --schema-version 0.1.0 \ | \
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
ADAPTER="$SCRIPTS/acceptance-adapter-swift.sh"
RUNNER="$SCRIPTS/acceptance-run.sh"
APPROVE_ACC="$SCRIPTS/approve-acceptance-cmd.sh"
APPROVE_TEST="$SCRIPTS/approve-test-cmd.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# node <name> <result-json-fragment> — one Test Case node. `-` means the result key is ABSENT,
# which the schema permits (only nodeType and name are required) and which must map to FAIL.
node() {
  if [ "$2" = "-" ]; then printf '{"nodeType":"Test Case","name":"%s"}' "$1"
  else printf '{"nodeType":"Test Case","name":"%s","result":"%s"}' "$1" "$2"; fi
}
bundle() { printf '{"testPlanConfigurations":[],"devices":[],"testNodes":[{"nodeType":"Test Plan","name":"P","children":[%s]}]}' "$1"; }

run_adapter() { bash "$ADAPTER" "$@" 2>/dev/null; }
verdict() { printf '%s\n' "$1" | awk -v id="$2" '$1=="ACCEPTANCE-CASE" && $2==id {print $3}'; }
field()   { printf '%s\n' "$1" | awk -v k="$2" '$1=="ACCEPTANCE-RESULT"{for(i=2;i<=NF;i++){split($i,a,"=");if(a[1]==k)print a[2]}}'; }

# ================================================================================================
# The adapter: result mapping. Apple's TestResult enum has five values and the mapping is a
# JUDGEMENT, so each arm is pinned separately rather than as one "not Passed" lump.
# ================================================================================================
if [ "$HAVE_JQ" -eq 0 ]; then
  bad "A0: jq is absent, so every adapter assertion below DID NOT RUN — this is not a clean result"
else
  ok "A0: jq present, adapter assertions can execute"

  OUT=$(run_adapter --json-file /dev/stdin <<EOF
$(bundle "$(node 'testR01_a()' 'Passed'),$(node 'testR02_b()' 'Failed'),$(node 'testR03_c()' 'Skipped')")
EOF
)
  [ "$(verdict "$OUT" R-01)" = "PASS" ] && ok "A1: Passed maps to PASS" || bad "A1: Passed did not map to PASS — got [$(verdict "$OUT" R-01)]"
  [ "$(verdict "$OUT" R-02)" = "FAIL" ] && ok "A2: Failed maps to FAIL" || bad "A2: Failed did not map to FAIL"
  [ "$(verdict "$OUT" R-03)" = "SKIP" ] && ok "A3: Skipped maps to SKIP, not to PASS" || bad "A3: Skipped did not map to SKIP — got [$(verdict "$OUT" R-03)]"

  OUT=$(run_adapter --json-file /dev/stdin <<EOF
$(bundle "$(node 'testR04_a()' 'Expected Failure'),$(node 'testR05_b()' 'unknown'),$(node 'testR06_c()' '-')")
EOF
)
  [ "$(verdict "$OUT" R-04)" = "FAIL" ] && ok "A4: Expected Failure maps to FAIL — an acceptance criterion expected to fail is not met" || bad "A4: Expected Failure did not map to FAIL"
  [ "$(verdict "$OUT" R-05)" = "FAIL" ] && ok "A5: unknown maps to FAIL, never to PASS" || bad "A5: unknown did not map to FAIL"
  [ "$(verdict "$OUT" R-06)" = "FAIL" ] && ok "A6: an ABSENT result maps to FAIL (the schema does not require the key)" || bad "A6: absent result did not map to FAIL"

  # ==============================================================================================
  # Binding. A7 and A8 are the pair the real fixture forced: the same rule must accept the XCTest
  # convention and reject the stranger, and a rule that gets one right by dropping the other is the
  # failure this pair exists to catch.
  # ==============================================================================================
  OUT=$(run_adapter --json-file /dev/stdin <<EOF
$(bundle "$(node 'testR01_greetReturnsHello()' 'Passed'),$(node 'testERROR6_boundaryProbe()' 'Passed'),$(node 'testUnboundHelper()' 'Passed')")
EOF
)
  [ "$(verdict "$OUT" R-01)" = "PASS" ] && ok "A7: testR01_...() binds R-01 — the id may follow the mandatory test prefix" || bad "A7: the real XCTest naming convention did not bind"
  # A8 asserts an ABSENCE, so it must first establish that there was an output to be absent FROM.
  # Its own plant taught this: a mutated pattern made jq error out, the adapter halted, every
  # `verdict` lookup returned empty, and "bound nothing" read TRUE because nothing was produced at
  # all. An assertion of absence over an empty result is rule 7 one level down.
  case "$OUT" in
    *'ACCEPTANCE-RESULT'*)
      if [ -z "$(verdict "$OUT" R-6)" ] && [ -z "$(verdict "$OUT" R-06)" ]; then
        ok "A8: testERROR6_...() binds NOTHING — a left boundary is required, not optional"
      else
        bad "A8: testERROR6 bound a criterion; the boundary rule is missing"
      fi ;;
    *) bad "A8: the adapter produced no result at all, so 'it bound nothing' proves nothing — [$OUT]" ;;
  esac
  [ "$(field "$OUT" unbound)" = "2" ] && ok "A9: unbound counts CASES that carry no id (2 of 3)" || bad "A9: unbound=$(field "$OUT" unbound), expected 2"

  OUT=$(run_adapter --json-file /dev/stdin <<EOF
$(bundle "$(node 'R-06: the user can archive a note' 'Passed'),$(node 'R-7 short form' 'Passed'),$(node 'testR07_dup()' 'Failed')")
EOF
)
  [ "$(verdict "$OUT" R-06)" = "PASS" ] && ok "A10: a Swift Testing display name binds at the string start" || bad "A10: Swift Testing display name did not bind"
  [ "$(verdict "$OUT" R-07)" = "FAIL" ] && ok "A11: R-7 and R-07 normalise to ONE criterion, and FAIL wins over PASS" || bad "A11: R-7/R-07 did not normalise together, or FAIL did not win — got [$(verdict "$OUT" R-07)]"

  OUT=$(run_adapter --json-file /dev/stdin <<EOF
$(bundle "$(node 'testR08_and_R09_both()' 'Passed')")
EOF
)
  { [ "$(verdict "$OUT" R-08)" = "PASS" ] && [ "$(verdict "$OUT" R-09)" = "PASS" ]; } \
    && ok "A12: one case bound to two ids produces two criteria" || bad "A12: a multi-id case did not produce both criteria"
  [ "$(field "$OUT" unbound)" = "0" ] && ok "A13: a case bound twice is counted ONCE in the case population, not twice" || bad "A13: unbound=$(field "$OUT" unbound) — the binding population leaked into the case count"

  OUT=$(run_adapter --json-file /dev/stdin <<EOF
$(bundle "$(node 'testR10_a()' 'Skipped'),$(node 'testR10_b()' 'Passed'),$(node 'testR11_a()' 'Skipped'),$(node 'testR11_b()' 'Failed')")
EOF
)
  [ "$(verdict "$OUT" R-10)" = "SKIP" ] && ok "A14: SKIP wins over PASS when a criterion has both" || bad "A14: SKIP did not win over PASS"
  [ "$(verdict "$OUT" R-11)" = "FAIL" ] && ok "A15b: FAIL wins over SKIP" || bad "A15b: FAIL did not win over SKIP"

  # ==============================================================================================
  # Denominators (rule 7). Zero is never a clean result, and the TWO ways of reaching zero have
  # DIFFERENT repairs, so they must be distinguishable from the outside.
  # ==============================================================================================
  OUT=$(run_adapter --json-file /dev/stdin <<EOF
{"testPlanConfigurations":[],"devices":[],"testNodes":[]}
EOF
)
  case "$OUT" in
    *'ACCEPTANCE-HALT no-cases-at-all'*) ok "A16: zero Test Case nodes halts as no-cases-at-all" ;;
    *) bad "A16: an empty bundle did not halt as no-cases-at-all — got [$OUT]" ;;
  esac
  case "$OUT" in *'ACCEPTANCE-RESULT'*) bad "A17: a halt still emitted an ACCEPTANCE-RESULT line, so a caller reading only RESULT sees a clean run" ;; *) ok "A17: no ACCEPTANCE-RESULT is emitted alongside a halt" ;; esac

  OUT2=$(run_adapter --json-file /dev/stdin <<EOF
$(bundle "$(node 'testUnboundHelper()' 'Passed'),$(node 'testAlsoUnbound()' 'Passed')")
EOF
)
  case "$OUT2" in
    *'ACCEPTANCE-HALT no-bound-cases'*) ok "A15: cases that ran with no id halts as no-bound-cases" ;;
    *) bad "A15: an unbound-only bundle did not halt as no-bound-cases — got [$OUT2]" ;;
  esac
  [ "$OUT" != "$OUT2" ] && ok "A18: the two zero-halts are DISTINCT — 'nothing ran' and 'nothing is bound' need different repairs" || bad "A18: both zero paths produced the same halt, so the repair is unguessable"

  OUT=$(printf 'not json at all' | run_adapter)
  case "$OUT" in *'ACCEPTANCE-HALT json-unparseable'*) ok "A19: unparseable input halts rather than reporting zero" ;; *) bad "A19: unparseable input did not halt — got [$OUT]" ;; esac

  # ==============================================================================================
  # The reverse direction (rule 8): what the executed set OMITS.
  # ==============================================================================================
  printf '%s\n' '# Acceptance' '- R-01 a' '- R-02 b' '- R-40 never written' '- R-41 also never' > "$T/ACC.md"
  OUT=$(run_adapter --json-file /dev/stdin --declared "$T/ACC.md" <<EOF
$(bundle "$(node 'testR01_a()' 'Passed'),$(node 'testR02_b()' 'Failed')")
EOF
)
  { [ "$(verdict "$OUT" R-40)" = "MISSING" ] && [ "$(verdict "$OUT" R-41)" = "MISSING" ]; } \
    && ok "A20: a declared criterion that never executed is reported MISSING" || bad "A20: a declared-but-unexecuted criterion was not reported MISSING"
  [ "$(field "$OUT" missing)" = "2" ] && [ "$(field "$OUT" declared)" = "4" ] \
    && ok "A21: declared and missing carry the reverse-direction counts" || bad "A21: declared=$(field "$OUT" declared) missing=$(field "$OUT" missing), expected 4 and 2"
  [ "$(field "$OUT" total)" = "2" ] \
    && ok "A24: MISSING stays OUT of total — total counts criteria that were executed, and one count must answer one question" || bad "A24: total=$(field "$OUT" total) absorbed the MISSING criteria"

  OUT=$(run_adapter --json-file /dev/stdin <<EOF
$(bundle "$(node 'testR01_a()' 'Passed')")
EOF
)
  { [ "$(field "$OUT" declared)" = "-" ] && [ "$(field "$OUT" missing)" = "-" ]; } \
    && ok "A23: with no declaration the reverse check reports '-', so 'it did not run' is VISIBLE rather than absent" || bad "A23: a missing reverse check reported a number instead of '-'"

  printf 'no identifiers in this file at all\n' > "$T/EMPTY.md"
  OUT=$(run_adapter --json-file /dev/stdin --declared "$T/EMPTY.md" <<EOF
$(bundle "$(node 'testR01_a()' 'Passed')")
EOF
)
  case "$OUT" in *'ACCEPTANCE-HALT declared-empty'*) ok "A22: a declaration yielding zero ids halts — a cross-check with no subject reads as clean (rule 9)" ;; *) bad "A22: an empty declaration did not halt — got [$OUT]" ;; esac

  OUT=$(run_adapter --json-file /dev/stdin --declared "$T/does-not-exist.md" <<EOF
$(bundle "$(node 'testR01_a()' 'Passed')")
EOF
)
  case "$OUT" in *'ACCEPTANCE-HALT declared-file-unreadable'*) ok "A26b: an unreadable declaration halts rather than silently skipping the reverse check" ;; *) bad "A26b: an unreadable declaration did not halt" ;; esac

  # A25 — the arithmetic identity holds on a mixed population. Its plant breaks the self-check.
  OUT=$(run_adapter --json-file /dev/stdin <<EOF
$(bundle "$(node 'testR01_a()' 'Passed'),$(node 'testR02_b()' 'Failed'),$(node 'testR03_c()' 'Skipped'),$(node 'testR04_d()' 'Passed')")
EOF
)
  _p=$(field "$OUT" pass); _f=$(field "$OUT" fail); _s=$(field "$OUT" skip); _t=$(field "$OUT" total)
  { [ -n "$_t" ] && [ $((_p + _f + _s)) -eq "$_t" ] && [ "$_t" -eq 4 ]; } \
    && ok "A25: pass+fail+skip == total, self-checked, so a dropped verdict cannot report a clean total" || bad "A25: identity broken — pass=$_p fail=$_f skip=$_s total=$_t"
fi

# jq absent must HALT and say so, not return an empty clean line. Driven with a PATH that has no jq.
# bash is invoked by ABSOLUTE PATH: emptying PATH also makes `bash` itself unresolvable, so the
# first version of this assertion measured a process that never started and read the empty output
# as a missing halt. The probe has to remove the tool under test and nothing else.
BASH_ABS=$(command -v bash)
mkdir -p "$T/nobin"
OUT=$(PATH="$T/nobin" "$BASH_ABS" "$ADAPTER" --json-file /dev/null 2>/dev/null)
case "$OUT" in *'ACCEPTANCE-HALT jq-absent'*) ok "A28: jq absent halts explicitly — a tool that cannot look must not report nothing found" ;; *) bad "A28: with no jq the adapter produced [$OUT]" ;; esac

bash "$ADAPTER" --nonsense >/dev/null 2>&1
[ $? -eq 2 ] && ok "A29b: a bad invocation exits 2 — distinct from a halt, which exits 0" || bad "A29b: a bad invocation did not exit 2"

# ================================================================================================
# The runner. Resolution, opt-out and trust. No Xcode is needed for any of these: every one of them
# must decide BEFORE the acceptance command would run.
# ================================================================================================
mkdir -p "$T/proj/.claude" "$T/proj/sub"
export STOP_GATE_TRUST_FILE="$T/trust"
: > "$T/trust"

OUT=$(bash "$RUNNER" --root "$T/proj/sub" 2>/dev/null)
case "$OUT" in *'ACCEPTANCE-HALT no-acceptance-cmd'*) ok "A26: no .claude/acceptance-cmd halts rather than reporting an empty pass" ;; *) bad "A26: a missing acceptance-cmd produced [$OUT]" ;; esac

printf 'NONE\n' > "$T/proj/.claude/acceptance-cmd"
OUT=$(bash "$RUNNER" --root "$T/proj" 2>/dev/null)
case "$OUT" in *'ACCEPTANCE-HALT opted-out'*) ok "A27: NONE is an opt-out that HALTS — unlike test-cmd, a silent acceptance opt-out would read as every criterion passing" ;; *) bad "A27: NONE did not halt as opted-out — got [$OUT]" ;; esac
case "$OUT" in *'ACCEPTANCE-RESULT'*) bad "A27b: the opt-out still emitted an ACCEPTANCE-RESULT line" ;; *) ok "A27b: the opt-out emits no ACCEPTANCE-RESULT" ;; esac

printf '# a comment\n\n' > "$T/proj/.claude/acceptance-cmd"
OUT=$(bash "$RUNNER" --root "$T/proj" 2>/dev/null)
case "$OUT" in *'ACCEPTANCE-HALT acceptance-cmd-empty'*) ok "A30: a comment-only file is EMPTY, which is a different state from an opt-out" ;; *) bad "A30: a comment-only acceptance-cmd produced [$OUT]" ;; esac

# The untrusted path must decide before running anything. Proven by a side effect, not by reading.
printf 'touch "%s/SIDE-EFFECT"\n' "$T" > "$T/proj/.claude/acceptance-cmd"
OUT=$(bash "$RUNNER" --root "$T/proj" 2>/dev/null)
case "$OUT" in *'ACCEPTANCE-HALT untrusted'*) ok "A29: an unapproved acceptance-cmd halts as untrusted" ;; *) bad "A29: an unapproved command produced [$OUT]" ;; esac
[ -e "$T/SIDE-EFFECT" ] && bad "A31: the untrusted command RAN — the gate reports but does not gate" || ok "A31: the untrusted command did not run, proven by an absent side effect"

# ================================================================================================
# The trust-line conformance guard (ADR-0086's precedent: copies kept, divergence guarded).
# Two approvers, one line format. If they ever disagree the trust check silently matches nothing.
# ================================================================================================
mkdir -p "$T/conf/.claude"
printf 'swift test\n' > "$T/conf/.claude/test-cmd"
printf 'swift test\n' > "$T/conf/.claude/acceptance-cmd"
: > "$T/trust-a"; : > "$T/trust-b"
STOP_GATE_TRUST_FILE="$T/trust-a" bash "$APPROVE_TEST" "$T/conf" >/dev/null 2>&1
STOP_GATE_TRUST_FILE="$T/trust-b" bash "$APPROVE_ACC"  "$T/conf" >/dev/null 2>&1
LA=$(cat "$T/trust-a" 2>/dev/null); LB=$(cat "$T/trust-b" 2>/dev/null)
if [ -z "$LA" ] || [ -z "$LB" ]; then
  bad "A32: one of the approvers wrote NOTHING, so the conformance comparison DID NOT RUN (test=[$LA] acc=[$LB])"
elif [ "$LA" = "$LB" ]; then
  ok "A32: identical content yields a byte-identical trust line from both approvers"
else
  bad "A32: the two approvers disagree on the trust line — test=[$LA] acc=[$LB]; the trust check would match nothing"
fi

# ================================================================================================
# Structural pins. These assert a contract sentence EXISTS. That is not evidence a caller obeys it,
# and none of them claims to be (rule 16).
# ================================================================================================
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
for f in "$ADAPTER" "$RUNNER"; do
  n=$(basename "$f")
  case "$(flat "$f")" in
    *'NEVER `[ -n "$out" ]`'*) ok "A33: $n forbids the [ -n \"\$out\" ] caller idiom at the site" ;;
    *) bad "A33: $n does not warn against [ -n \"\$out\" ], the idiom that is true on a clean run too" ;;
  esac
done
grep -q -- '--schema-version 0.1.0' "$RUNNER" && ok "A34: the xcresulttool schema version is pinned at the call site" || bad "A34: the schema version is not pinned, so an Xcode default bump would be absorbed silently"

# A35 — the id pattern is ONE question with three consumers (rule 6): the binding pass, the
# bound-case count, and the reverse check. Three literals that drifted would make the reverse check
# match nothing and report a clean missing=0. The adapter satisfies this BY CONSTRUCTION — one
# `IDRE=` definition, read through `--arg` — so the assertion checks the construction, not a
# coincidence between copies.
#
# COMMENT LINES ARE STRIPPED FIRST, and that is rule 12 rather than tidiness. The adapter documents
# the same regex in its header; the first version of this assertion matched that PROSE and reported
# a second "distinct form" that does not exist in the code at all.
CODEONLY="$T/adapter-code-only.txt"
grep -v '^[[:space:]]*#' "$ADAPTER" > "$CODEONLY" 2>/dev/null
NRE=$(grep -c 'R-?(\[0-9\]{1,3})(?!\[0-9\])' "$CODEONLY" 2>/dev/null || true)
case "${NRE:-}" in ''|*[!0-9]*) NRE=0 ;; esac
NUSE=$(grep -c 'IDRE\|match(\$re\|test(\$re' "$CODEONLY" 2>/dev/null || true)
case "${NUSE:-}" in ''|*[!0-9]*) NUSE=0 ;; esac
if [ "$NRE" -eq 1 ] && [ "$NUSE" -ge 4 ]; then
  ok "A35: the id pattern is ONE literal read by $NUSE sites — the consumers cannot drift apart"
elif [ "$NRE" -ne 1 ]; then
  bad "A35: $NRE literal copies of the id pattern in code, expected exactly 1 — copies answering one question can drift"
else
  bad "A35: only $NUSE reference(s) to the shared pattern, expected >= 4 — a consumer stopped reading it, so the check DID NOT RUN over all of them"
fi

# --- Z1: assertion-count floor (ADR-0083 D3), a vacuity guard only. The per-assertion evidence is
# the plant registry above; this exists so a harness gutted to two lines cannot read as green.
Z1_TOTAL=$((PASS + FAIL))
if [ "$Z1_TOTAL" -ge 30 ]; then
  ok "Z1: assertion-count floor ($Z1_TOTAL >= 30)"
else
  bad "Z1: only $Z1_TOTAL assertions ran, expected >= 30 — assertions were lost, not fixed"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
