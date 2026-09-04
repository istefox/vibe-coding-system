#!/bin/bash
# spec-coverage.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash spec-coverage.test.sh
#
# Covers issue #102 / ADR-0048: requirement IDs (R-NN) in a SPEC's success-criteria section, and a
# coverage checker (spec-coverage.sh) asserting no requirement is silently dropped between SPEC,
# plan and tests.
#
# ASSERTION LABELS ARE R-PREFIXED (RA1, RD3, RG2, ...) to stay distinguishable from the nine
# harnesses using bare A-G and from weakening-wiring.test.sh's W — all of them print into the same
# CI shell-tests job.
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL. secret-dep-gate.test.sh section D scans this
# repository's tracked files (via git ls-files) as its false-positive corpus, so a key-shaped
# string dropped into a fixture in this file would turn that harness red.
#
# THE SCRIPT UNDER TEST IS A CHECKER (exit-code contract): 0 = covered (or no IDs declared), 1 =
# uncovered, 2 = bad invocation, 3 = structural error. Its neighbour at the same Step 5 → Step 6
# gate, weakening-scan.sh, is a REPORTER (always exits 0, signals through stdout). Do not copy one
# harness's assertion idiom into the other file.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
TAB=$(printf '\t')
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCOV="$STAGING/plugin/skills/concept-to-code/scripts/spec-coverage.sh"

# ==============================================================================================
# RA0. The anchor every RA/RB/RC/RD/RE assertion below depends on.
# ==============================================================================================
if [ -f "$SCOV" ] && [ -r "$SCOV" ]; then
  ok "RA0: spec-coverage.sh exists and is readable at the expected path"
else
  bad "RA0: $SCOV not found or unreadable — every RA/RB/RC/RD/RE assertion below is meaningless"
fi

run_scov() { OUT=$(bash "$SCOV" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err" 2>/dev/null); }

# ==============================================================================================
# RG. Registration (ADR-0048 §D11). Both assertions are expected RED until Task 9 — nothing else
# in CI can catch a missing PAIRS entry for a skill-helper script (ADR-0024 scope excludes
# plugin/skills/*/scripts/ from pairs-completeness.test.sh's check_complete).
# ==============================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
SYNCSH="$STAGING/sync-to-claude.sh"

DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]spec-coverage[[:space:];]'; then
  ok "RG1: docs-ci.yml's shell-tests loop list runs spec-coverage"
else
  bad "RG1: spec-coverage is not in docs-ci.yml's explicit harness list — append it (Task 9)"
fi

awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" >"$TMP/pairs"
if grep -qxF 'plugin/skills/concept-to-code/scripts/spec-coverage.sh|skills/concept-to-code/scripts/spec-coverage.sh' "$TMP/pairs"; then
  ok "RG2: PAIRS deploys spec-coverage.sh to ~/.claude/skills/concept-to-code/scripts/"
else
  bad "RG2: the spec-coverage.sh PAIRS entry is missing (Task 9) — pairs-completeness.test.sh cannot catch this, its check_complete does not cover plugin/skills/*/scripts/"
fi

if grep -q 'spec-coverage.test' "$TMP/pairs"; then
  bad "RG3: PAIRS gained an entry for this harness — ADR-0048 §D11 says it does not deploy"
else
  ok "RG3: no PAIRS entry for spec-coverage.test.sh (ADR-0048 §D11, harnesses do not deploy)"
fi

# ==============================================================================================
# RT. Caller traps, EXECUTED (forward guards, green on arrival, never fix evidence). These exist
# so a future edit cannot re-spring traps this codebase has already paid for once each.
# ==============================================================================================
wrong=$(printf 'x\n' | grep -c 'nomatch' || echo 0)  # idiom-demo (plan-task-count.test.sh PTD)
right=$(printf 'x\n' | grep -c 'nomatch' || true)
wrong_lines=$(printf '%s\n' "$wrong" | grep -c .)
if [ "$wrong_lines" -eq 2 ] && [ "$right" = "0" ]; then
  ok "RT1: grep -c ... || echo 0 yields the two-line string [$wrong]; || true yields the single line 0"
else
  bad "RT1: expected two-line ||echo0 and single-line ||true — got wrong=[$wrong] right=[$right]"
fi

W="$STAGING/plugin/skills/review-triage-fix/scripts/weakening-scan.sh"
wsout=$(printf '' | bash "$W" 2>/dev/null); wsrc=$?
if [ "$wsout" = "CLEAN" ] && [ "$wsrc" -eq 0 ]; then
  ok "RT2: weakening-scan.sh on empty stdin still prints the sentinel CLEAN and exits 0 (the neighbouring gate's contract — the two blocks at the Step 5 exit must not share a caller idiom)"
else
  bad "RT2: expected CLEAN/exit 0 from weakening-scan.sh on empty stdin — got out=[$wsout] rc=$wsrc"
fi

# ==============================================================================================
# RA. ID extraction.
# ==============================================================================================
cat >"$TMP/ra1.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
- [ ] R-02 — second
EOF
cat >"$TMP/ra1-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
### Task 2 — do other (R-02)
EOF
mkdir -p "$TMP/ra1-tests"
cat >"$TMP/ra1-tests/test_a.sh" <<'EOF'
# covers R-01 and R-02
EOF
run_scov --spec "$TMP/ra1.spec.md" --plan "$TMP/ra1-plan.md" --tests-root "$TMP/ra1-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q '^COVERED	R-01$' \
   && printf '%s\n' "$OUT" | grep -q '^COVERED	R-02$' \
   && printf '%s\n' "$ERR" | grep -q '2 id(s) declared'; then
  ok "RA1: two declared IDs, both covered by plan+tests -> exit 0, COVERED lines, summary names 2 id(s) declared"
else
  bad "RA1: expected exit 0 + two COVERED lines + summary — got rc=$RC out=[$OUT] err=[$ERR]"
fi

cat >"$TMP/ra2.spec.md" <<'EOF'
## Success criteria
- [ ] Uses ADR-0047 pattern correctly.
- [ ] Consistent with ADR-0016 for dispatch.
- [ ] Not the same as PR-01 handling.
EOF
: >"$TMP/ra2-plan.md"
run_scov --spec "$TMP/ra2.spec.md" --plan "$TMP/ra2-plan.md"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  ok "RA2: the ADR-NNNN immunity — prose mentioning ADR-0047, ADR-0016, PR-01 declares zero IDs -> the silent path (boundary-anchored on both sides)"
else
  bad "RA2: expected the silent path for the ADR-NNNN corpus — got rc=$RC out=[$OUT] err=[$ERR]"
fi

cat >"$TMP/ra3.spec.md" <<'EOF'
## Success criteria
- [ ] A SPEC with `R-01` and `R-02` fails
EOF
run_scov --spec "$TMP/ra3.spec.md" --plan "$TMP/ra2-plan.md"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  ok "RA3: position matters — a mention mid-item (not at the start) declares zero IDs, the silent path"
else
  bad "RA3: expected the silent path for a mid-item mention — got rc=$RC out=[$OUT] err=[$ERR]"
fi

cat >"$TMP/ra4.spec.md" <<'EOF'
## Success criteria
- [x] R-03 — done
EOF
run_scov --spec "$TMP/ra4.spec.md" --plan "$TMP/ra2-plan.md"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q 'R-03'; then
  ok "RA4: a checked box [x] declares an ID exactly like [ ] — R-03 recognized (uncovered by the empty plan)"
else
  bad "RA4: expected R-03 to be recognized as declared — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/ra5.spec.md" <<'EOF'
## Acceptance criteria
- [ ] R-30 — a
## Definition of done
- [ ] R-31 — b
## Notes
- [ ] R-32 — c
EOF
cat >"$TMP/ra5-plan.md" <<'EOF'
- [ ] a (R-30)
- [ ] b (R-31)
EOF
run_scov --spec "$TMP/ra5.spec.md" --plan "$TMP/ra5-plan.md"
if [ "$RC" -eq 0 ] && printf '%s\n' "$ERR" | grep -q '2 id(s) declared' && ! printf '%s\n' "$OUT" | grep -q 'R-32'; then
  ok "RA5: Acceptance criteria and Definition of done are recognized; Notes is not (R-32 absent, 2 id(s) declared)"
else
  bad "RA5: expected 2 ids declared and no R-32 — got rc=$RC out=[$OUT] err=[$ERR]"
fi

cat >"$TMP/ra6.spec.md" <<'EOF'
## Success criteria
- [ ] R-40 — a
## Edge cases
- [ ] R-41 — b
EOF
cat >"$TMP/ra6-plan.md" <<'EOF'
- [ ] a (R-40)
EOF
run_scov --spec "$TMP/ra6.spec.md" --plan "$TMP/ra6-plan.md"
if [ "$RC" -eq 0 ] && printf '%s\n' "$ERR" | grep -q '1 id(s) declared' && ! printf '%s\n' "$OUT" | grep -q 'R-41'; then
  ok "RA6: section end — an R-NN item under Edge cases (following Success criteria) is not counted"
else
  bad "RA6: expected 1 id declared and no R-41 — got rc=$RC out=[$OUT] err=[$ERR]"
fi

run_scov --spec "$TMP/ra1.spec.md" --plan "$TMP/ra1-plan.md" --list
if [ "$RC" -eq 0 ] && [ "$OUT" = "R-01	first
R-02	second" ]; then
  ok "RA7: --list prints R-NN<TAB>text with the separator stripped, exit 0"
else
  bad "RA7: expected the stripped R-NN<TAB>text list — got rc=$RC out=[$OUT]"
fi
run_scov --spec "$TMP/ra2.spec.md" --plan "$TMP/ra2-plan.md" --list
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "RA7b: --list on a no-ID SPEC prints nothing and exits 0"
else
  bad "RA7b: expected empty output / exit 0 on a no-ID SPEC's --list — got rc=$RC out=[$OUT]"
fi

# ==============================================================================================
# RB. Structural errors, exit 3.
# ==============================================================================================
cat >"$TMP/rb1.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
- [ ] R-01 — dup
EOF
run_scov --spec "$TMP/rb1.spec.md" --plan "$TMP/ra2-plan.md"
if [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q 'DUPLICATE' && printf '%s\n' "$OUT" | grep -q 'R-01'; then
  ok "RB1: a duplicate R-01 -> exit 3, stdout contains DUPLICATE and R-01"
else
  bad "RB1: expected exit 3 + DUPLICATE + R-01 — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rb2a.spec.md" <<'EOF'
## Success criteria
- [ ] R-1 — bad
EOF
run_scov --spec "$TMP/rb2a.spec.md" --plan "$TMP/ra2-plan.md"
if [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q 'MALFORMED' && printf '%s\n' "$OUT" | grep -q 'R-1'; then
  ok "RB2a: R-1 (one digit) -> exit 3, MALFORMED + offending token"
else
  bad "RB2a: expected exit 3 + MALFORMED + R-1 — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rb2b.spec.md" <<'EOF'
## Success criteria
- [ ] R-001 — bad
EOF
run_scov --spec "$TMP/rb2b.spec.md" --plan "$TMP/ra2-plan.md"
if [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q 'MALFORMED' && printf '%s\n' "$OUT" | grep -q 'R-001'; then
  ok "RB2b: R-001 (three digits) -> exit 3, MALFORMED + offending token"
else
  bad "RB2b: expected exit 3 + MALFORMED + R-001 — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rb2c.spec.md" <<'EOF'
## Success criteria
- [ ] R-1a — bad
EOF
run_scov --spec "$TMP/rb2c.spec.md" --plan "$TMP/ra2-plan.md"
if [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q 'MALFORMED' && printf '%s\n' "$OUT" | grep -q 'R-1a'; then
  ok "RB2c: R-1a (mixed) -> exit 3, MALFORMED + offending token"
else
  bad "RB2c: expected exit 3 + MALFORMED + R-1a — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rb3.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rb3-plan.md" <<'EOF'
- [ ] implement the thing (R-09)
EOF
run_scov --spec "$TMP/rb3.spec.md" --plan "$TMP/rb3-plan.md"
if [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q 'ORPHAN' && printf '%s\n' "$OUT" | grep -q 'R-09'; then
  ok "RB3: a plan task cites R-09, which the SPEC does not declare -> exit 3, ORPHAN + R-09"
else
  bad "RB3: expected exit 3 + ORPHAN + R-09 — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rb4.spec.md" <<'EOF'
## Notes
- [ ] R-01 — x
EOF
run_scov --spec "$TMP/rb4.spec.md" --plan "$TMP/ra2-plan.md"
if [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q 'R-01' \
   && (printf '%s\n' "$ERR" | grep -qi 'success criteria'); then
  ok "RB4: the narrow inert-guard — a well-formed ID outside every recognized section -> exit 3, stderr names a recognized heading (a gate that is silently inert is the ADR-0043 failure shape)"
else
  bad "RB4: expected exit 3 + R-01 + a recognized-heading name in stderr — got rc=$RC out=[$OUT] err=[$ERR]"
fi

run_scov --plan "$TMP/ra2-plan.md"
rb5a_ok=0; [ "$RC" -eq 2 ] && [ -z "$OUT" ] && rb5a_ok=1
run_scov --spec "$TMP/ra1.spec.md"
rb5b_ok=0; [ "$RC" -eq 2 ] && [ -z "$OUT" ] && rb5b_ok=1
run_scov --spec "$TMP/ra1.spec.md" --plan "$TMP/ra2-plan.md" --bogus-flag
rb5c_ok=0; [ "$RC" -eq 2 ] && [ -z "$OUT" ] && rb5c_ok=1
run_scov --spec "$TMP/does-not-exist.spec.md" --plan "$TMP/ra2-plan.md"
rb5d_ok=0; [ "$RC" -eq 2 ] && [ -z "$OUT" ] && rb5d_ok=1
if [ "$rb5a_ok" -eq 1 ] && [ "$rb5b_ok" -eq 1 ] && [ "$rb5c_ok" -eq 1 ] && [ "$rb5d_ok" -eq 1 ]; then
  ok "RB5: exit 2 + empty stdout on missing --spec, missing --plan, unknown flag, unreadable --spec (four sub-assertions)"
else
  bad "RB5: expected exit 2 + empty stdout on all four invalid invocations — got a=$rb5a_ok b=$rb5b_ok c=$rb5c_ok d=$rb5d_ok"
fi

# ==============================================================================================
# RC. Plan coverage.
# ==============================================================================================
cat >"$TMP/rc.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
- [ ] R-02 — second
EOF
cat >"$TMP/rc-plan.md" <<'EOF'
- [ ] implement first (R-01)
EOF
mkdir -p "$TMP/rc-tests"
cat >"$TMP/rc-tests/test_rc.sh" <<'EOF'
# covers R-01 and R-02
EOF
run_scov --spec "$TMP/rc.spec.md" --plan "$TMP/rc-plan.md" --tests-root "$TMP/rc-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q 'UNCOVERED' && printf '%s\n' "$OUT" | grep -q 'R-02' \
   && ! printf '%s\n' "$OUT" | grep -q '^UNCOVERED	R-01'; then
  ok "RC1: plan cites only R-01 -> exit 1, UNCOVERED names R-02, not R-01"
else
  bad "RC1: expected exit 1 + UNCOVERED R-02 only — got rc=$RC out=[$OUT]"
fi

if printf '%s\n' "$OUT" | grep -q '^UNCOVERED	R-02	plan$'; then
  ok "RC2: the missing half is named — R-02's third field is exactly plan (tests already cover it)"
else
  bad "RC2: expected the UNCOVERED R-02 line's third field to be exactly plan — got out=[$OUT]"
fi

cat >"$TMP/rc3.spec.md" <<'EOF'
## Success criteria
- [ ] R-10 — a
- [ ] R-11 — b
EOF
cat >"$TMP/rc3-plan.md" <<'EOF'
### Task 3 — GREEN: thing (R-10, R-11)
EOF
run_scov --spec "$TMP/rc3.spec.md" --plan "$TMP/rc3-plan.md"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q '^COVERED	R-10$' && printf '%s\n' "$OUT" | grep -q '^COVERED	R-11$'; then
  ok "RC3: a task HEADING citation (Task 3 ... (R-10, R-11)) counts as plan coverage"
else
  bad "RC3: expected both R-10 and R-11 COVERED via the heading citation — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rc4.spec.md" <<'EOF'
## Success criteria
- [ ] R-12 — a
EOF
cat >"$TMP/rc4-plan.md" <<'EOF'
- [ ] implement the thing (R-12)
EOF
run_scov --spec "$TMP/rc4.spec.md" --plan "$TMP/rc4-plan.md"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q '^COVERED	R-12$'; then
  ok "RC4: a CHECKBOX citation (- [ ] ... (R-12)) counts as plan coverage"
else
  bad "RC4: expected R-12 COVERED via the checkbox citation — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rc5.spec.md" <<'EOF'
## Success criteria
- [ ] R-13 — a
EOF
cat >"$TMP/rc5-plan.md" <<'EOF'
This plan addresses R-13.
### Task 1 — do the thing
- [ ] no citation here
EOF
run_scov --spec "$TMP/rc5.spec.md" --plan "$TMP/rc5-plan.md"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q '^UNCOVERED	R-13	plan$'; then
  ok "RC5: a PREAMBLE mention (plain prose, not a task line, not a checkbox) does not count"
else
  bad "RC5: expected UNCOVERED R-13 plan (preamble mention ignored) — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rc6.spec.md" <<'EOF'
## Success criteria
- [ ] R-14 — a
EOF
mkdir -p "$TMP/rc6-tests"
: >"$TMP/rc6-tests/test_rc6.sh"
run_scov --spec "$TMP/rc6.spec.md" --plan "$TMP/ra2-plan.md" --tests-root "$TMP/rc6-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q '^UNCOVERED	R-14	plan,tests$'; then
  ok "RC6: both halves missing -> third field is exactly plan,tests"
else
  bad "RC6: expected UNCOVERED R-14 plan,tests — got rc=$RC out=[$OUT]"
fi

# ==============================================================================================
# RD. Test discovery.
# ==============================================================================================
cat >"$TMP/rd1.spec.md" <<'EOF'
## Success criteria
- [ ] R-15 — a
- [ ] R-16 — b
EOF
cat >"$TMP/rd1-plan.md" <<'EOF'
- [ ] a (R-15)
- [ ] b (R-16)
EOF
mkdir -p "$TMP/rd1-tests"
cat >"$TMP/rd1-tests/foo.test.sh" <<'EOF'
# covers R-15
EOF
cat >"$TMP/rd1-tests/notes.txt" <<'EOF'
# mentions R-16 but is not a test file
EOF
run_scov --spec "$TMP/rd1.spec.md" --plan "$TMP/rd1-plan.md" --tests-root "$TMP/rd1-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q '^COVERED	R-15$' \
   && printf '%s\n' "$OUT" | grep -q '^UNCOVERED	R-16	tests$'; then
  ok "RD1: a mention in foo.test.sh counts; the same mention in notes.txt does not"
else
  bad "RD1: expected R-15 COVERED and R-16 UNCOVERED tests — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rd2.spec.md" <<'EOF'
## Success criteria
- [ ] R-17 — a
EOF
cat >"$TMP/rd2-plan.md" <<'EOF'
- [ ] a (R-17)
EOF
mkdir -p "$TMP/rd2-tests/a/b/c"
cat >"$TMP/rd2-tests/a/b/c/x_test.py" <<'EOF'
# covers R-17
EOF
run_scov --spec "$TMP/rd2.spec.md" --plan "$TMP/rd2-plan.md" --tests-root "$TMP/rd2-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q '^COVERED	R-17$'; then
  ok "RD2: discovery reaches a nested path (a/b/c/x_test.py) under --tests-root"
else
  bad "RD2: expected R-17 COVERED via nested discovery — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rd3.spec.md" <<'EOF'
## Success criteria
- [ ] R-18 — a
EOF
cat >"$TMP/rd3-plan.md" <<'EOF'
- [ ] a (R-18)
EOF
mkdir -p "$TMP/rd3-tests/docs/specs"
cat >"$TMP/rd3-tests/docs/specs/x.spec.md" <<'EOF'
Mentions R-18 in prose.
EOF
run_scov --spec "$TMP/rd3.spec.md" --plan "$TMP/rd3-plan.md" --tests-root "$TMP/rd3-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q '^UNCOVERED	R-18	tests$'; then
  ok "RD3: .md is never a test file — a SPEC mentioning its own ID under --tests-root does not self-cover (a SPEC would otherwise discover itself as a test file, trivially self-covering every SPEC)"
else
  bad "RD3: expected UNCOVERED R-18 tests despite the .spec.md mention — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rd4.spec.md" <<'EOF'
## Success criteria
- [ ] R-19 — a
EOF
cat >"$TMP/rd4-plan.md" <<'EOF'
- [ ] a (R-19)
EOF
run_scov --spec "$TMP/rd4.spec.md" --plan "$TMP/rd4-plan.md"
if [ "$RC" -eq 0 ] && printf '%s\n' "$ERR" | grep -qF 'tests-root=not-checked'; then
  ok "RD4: --tests-root omitted -> the test half is not evaluated, exit 0, stderr names tests-root=not-checked"
else
  bad "RD4: expected exit 0 + tests-root=not-checked — got rc=$RC out=[$OUT] err=[$ERR]"
fi

cat >"$TMP/rd5.spec.md" <<'EOF'
## Success criteria
- [ ] R-20 — a
EOF
cat >"$TMP/rd5-plan.md" <<'EOF'
- [ ] a (R-20)
EOF
mkdir -p "$TMP/rd5-tests"
run_scov --spec "$TMP/rd5.spec.md" --plan "$TMP/rd5-plan.md" --tests-root "$TMP/rd5-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q '^UNCOVERED	R-20	tests$' \
   && printf '%s\n' "$ERR" | grep -qF '0 test file(s) discovered'; then
  ok "RD5: --tests-root at a directory with zero discovered test files -> exit 1, every ID UNCOVERED tests, discovery count named in the summary"
else
  bad "RD5: expected exit 1 + UNCOVERED tests + 0 test file(s) discovered — got rc=$RC out=[$OUT] err=[$ERR]"
fi

# ==============================================================================================
# RE. Backward compatibility (the hard gate).
# ==============================================================================================
cat >"$TMP/re1.spec.md" <<'EOF'
## Success criteria
- [ ] Some criterion with no id.
- [ ] Another one, still no id.
EOF
run_scov --spec "$TMP/re1.spec.md" --plan "$TMP/ra2-plan.md"
re1_rc_ok=0; re1_out_ok=0; re1_err_ok=0
[ "$RC" -eq 0 ] && re1_rc_ok=1
[ -z "$OUT" ] && re1_out_ok=1
[ -z "$ERR" ] && re1_err_ok=1
if [ "$re1_rc_ok" -eq 1 ] && [ "$re1_out_ok" -eq 1 ] && [ "$re1_err_ok" -eq 1 ]; then
  ok "RE1: a Success criteria section with no IDs -> exit 0, empty stdout, empty stderr (all three asserted separately)"
else
  bad "RE1: expected exit0/empty-stdout/empty-stderr — got rc_ok=$re1_rc_ok out_ok=$re1_out_ok err_ok=$re1_err_ok (rc=$RC out=[$OUT] err=[$ERR])"
fi

cat >"$TMP/re2.spec.md" <<'EOF'
# Just a title

Some text, no criteria section at all.
EOF
run_scov --spec "$TMP/re2.spec.md" --plan "$TMP/ra2-plan.md"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  ok "RE2: a SPEC with no success-criteria section at all -> the same silent pass"
else
  bad "RE2: expected the silent pass for a section-less SPEC — got rc=$RC out=[$OUT] err=[$ERR]"
fi

: >"$TMP/re3-plan.md"
# Corpus = the ARCHIVED specs only. `$REPO/SPEC.md` is deliberately NOT a member: it is the
# in-flight chain's spec, overwritten by every run, and by convention already a copy of a
# docs/specs/ file (concept-to-code Step 1 writes it, autopilot Phase P copies it from there), so it
# adds no coverage this glob does not already have. It was a member until 2026-07-28, when the
# first SPEC to actually declare R-NN ids in its success criteria — which is what ADR-0048 asked
# for — made this backward-compatibility loop fail on the correct use of the feature it protects.
# A backward-compatibility corpus must be a stable set; a work-in-flight file is not one.
#
# MEMBERSHIP IS BY PROPERTY, NOT BY LOCATION (issue #230, found by the Phase 7 shakedown run).
# RE asserts one thing: a SPEC that declares NO ids passes silently. A SPEC that DOES declare ids
# legitimately reports UNCOVERED against an empty plan — that is the feature working, and demanding
# the silent pass of it asks the wrong question of that file.
#
# The 2026-07-28 fix above removed the root file, which addressed WHERE the failing SPEC was and not
# WHAT made it fail. Archiving that same SPEC to its documented home — which the convention says to
# do, and which issue #228's proposed guard would do automatically — put it back in this corpus
# through the other door and failed this loop again. Every SPEC written since ADR-0048 declares ids,
# so under a location filter the archive step is blocked for all of them.
#
# The predicate reuses the checker's own `--list` rather than a second declaration parser: one place
# decides what an id is (the ADR-0069/ADR-0072 rule, applied here).
spec_declares_ids() { [ -n "$(bash "$SCOV" --spec "$1" --plan "$TMP/re3-plan.md" --list 2>/dev/null)" ]; }

re3_count=0; re3_bad=0; re3_skipped=0
for f in "$REPO"/docs/specs/*.spec.md; do
  if spec_declares_ids "$f"; then
    re3_skipped=$((re3_skipped + 1))
    continue
  fi
  re3_count=$((re3_count + 1))
  o=$(bash "$SCOV" --spec "$f" --plan "$TMP/re3-plan.md" 2>"$TMP/re3err")
  r=$?
  e=$(cat "$TMP/re3err" 2>/dev/null)
  if [ "$r" -eq 0 ] && [ -z "$o" ] && [ -z "$e" ]; then
    ok "RE3: $f passes silently (exit 0, empty stdout, empty stderr)"
  else
    re3_bad=$((re3_bad + 1))
    bad "RE3: $f did NOT pass silently — rc=$r out=[$(printf '%s' "$o" | head -1)] err=[$(printf '%s' "$e" | head -1)]"
  fi
done
if [ "$re3_count" -ge 30 ]; then
  ok "RE4: the RE3 corpus loop asserted $re3_count id-less SPECs (>= 30, $re3_skipped excluded by property) — not a vacuous pass. The >= 30 floor is deliberately a vacuity guard on this corpus sweep, not an exact count — the id-less corpus grows with every feature (CLAUDE.md rule 10's stated exception: a floor is permitted only when the site says so)."
else
  bad "RE4: the RE3 corpus loop asserted only $re3_count files (< 30, $re3_skipped excluded) — either the glob matches almost nothing, or the exclusion predicate is swallowing the corpus"
fi

# RE5/RE6: the exclusion predicate itself, on FIXTURES rather than on whatever is archived today.
# Asserting "at least one corpus member is excluded" would make this test depend on which SPECs
# happen to be in docs/specs/ at a given moment — the same location-coupling that produced #230.
# Both directions (rule 8: a negative-case assertion pins nothing without its positive twin).
cat >"$TMP/re5-with-ids.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — a criterion carrying a requirement id.
EOF
cat >"$TMP/re6-no-ids.spec.md" <<'EOF'
## Success criteria
- [ ] A criterion carrying no requirement id at all.
EOF
spec_declares_ids "$TMP/re5-with-ids.spec.md" \
  && ok "RE5: the exclusion predicate recognises a SPEC that declares ids (it would be excluded)" \
  || bad "RE5: a SPEC declaring R-01 was NOT recognised — the predicate excludes nothing and RE3 is back to asserting by location"
spec_declares_ids "$TMP/re6-no-ids.spec.md" \
  && bad "RE6: an id-less SPEC was excluded — the predicate over-matches and would empty the corpus silently" \
  || ok "RE6: an id-less SPEC is NOT excluded — it stays in the asserted set"

# ==============================================================================================
# RF. concept-to-code/SKILL.md Step 5 — the Requirement-ID coverage gate block (ADR-0048 §D5).
# EXPECTED RED until Task 6 (deferred to a later batch). Static prose anchors against the real
# Step 5 extract, deliberately: the file is instructions for a model, not runnable code.
# ==============================================================================================
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
STEP5_REF="$STAGING/plugin/skills/concept-to-code/references/step5-implementation.md"
STEP5="$TMP/c2c_step5.txt"
# The Step 5 range moved to references/step5-implementation.md (VCS-047, ADR-0174); the
# reference file's body IS the block, so no awk range is needed any more.
cp "$STEP5_REF" "$STEP5" 2>/dev/null

if [ -s "$STEP5" ]; then
  ok "RF0: Step 5 of concept-to-code/SKILL.md is extractable (the anchor every RF assertion reads)"
else
  bad "RF0: could not extract Step 5 from $CC — every RF assertion below is meaningless"
fi

# VCS-047/ADR-0174: the heading itself moved into references/step5-implementation.md — a
# whole-file uniqueness check must now count across both files, or a duplicate reintroduced in
# either one would go undetected.
RF1_N=$(cat "$CC" "$STEP5_REF" 2>/dev/null | grep -c '^#### Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)$' || true)
if [ "$RF1_N" = "1" ]; then
  ok "RF1: exactly one occurrence of the Requirement-ID coverage gate heading in the whole file"
else
  bad "RF1: expected exactly 1 occurrence of the gate heading, found $RF1_N (Task 6)"
fi

if grep -qF 'skills/concept-to-code/scripts/spec-coverage.sh' "$STEP5" && grep -qF 'CLAUDE_PLUGIN_ROOT' "$STEP5"; then
  ok "RF2: Step 5 resolves the script under skills/concept-to-code/scripts/ and mentions CLAUDE_PLUGIN_ROOT"
else
  bad "RF2: Step 5 does not name both skills/concept-to-code/scripts/ and CLAUDE_PLUGIN_ROOT (Task 6)"
fi

if grep -qF 'hooks/spec-coverage.sh' "$STEP5"; then
  bad "RF3: Step 5 contains hooks/spec-coverage.sh — the ~/.claude two-location trap (a block copied from #100's reporters resolves nothing and skips the gate forever)"
else
  ok "RF3: Step 5 does not contain hooks/spec-coverage.sh"
fi

if grep -qF '_rc=$?' "$STEP5" && grep -qF "Do not copy one block's branching into the other" "$STEP5"; then
  ok "RF4: Step 5 captures the exit code (_rc=\$?) and states the copy-branching warning verbatim"
else
  ok_rf4=0
  bad "RF4: Step 5 is missing _rc=\$? or the literal 'Do not copy one block's branching into the other' (Task 6)"
fi

if grep -qF 'weakening-scan.sh' "$STEP5" && (grep -qi 'checker' "$STEP5" && grep -qi 'reporter' "$STEP5"); then
  ok "RF5: Step 5 names weakening-scan.sh and distinguishes checker from reporter"
else
  bad "RF5: Step 5 does not name weakening-scan.sh alongside the checker/reporter distinction (Task 6)"
fi

if grep -qF 'do NOT transition to' "$STEP5" && grep -qF 'step_6_review' "$STEP5"; then
  ok "RF6: Step 5 states the attended policy — do NOT transition to step_6_review"
else
  bad "RF6: Step 5 is missing the attended do-NOT-transition policy for this gate (Task 6)"
fi

if grep -qi 'autopilot' "$STEP5" && grep -qi 'halt' "$STEP5"; then
  ok "RF7: Step 5 states the unattended policy — autopilot halts"
else
  bad "RF7: Step 5 is missing the autopilot/halt policy for this gate (Task 6)"
fi

if grep -qF 'unavailable' "$STEP5" && grep -qF '_scov=""' "$STEP5"; then
  ok "RF8: Step 5 states the fail-open path — unavailable / _scov=\"\" else-branch"
else
  bad "RF8: Step 5 is missing the unavailable / _scov=\"\" fail-open statement (Task 6)"
fi

if grep -qF 'once at the Step 5 exit, not at every batch checkpoint' "$STEP5"; then
  ok "RF9: Step 5 states the cadence — once at the Step 5 exit, not at every batch checkpoint (stops someone 'fixing' the asymmetry with ADR-0047's per-batch gate)"
else
  bad "RF9: Step 5 is missing the literal cadence phrase 'once at the Step 5 exit, not at every batch checkpoint' (Task 6)"
fi

RF10_N=$(grep -o 'Requirement-ID coverage gate' "$STEP5" | grep -c . || true)
if [ "$RF10_N" -ge 3 ]; then
  ok "RF10: both dispatch paths reach it — 'Requirement-ID coverage gate' occurs $RF10_N times (>= 3) in Step 5"
else
  bad "RF10: expected >= 3 occurrences of 'Requirement-ID coverage gate' in Step 5, found $RF10_N (Task 6)"
fi

if grep -qF 'test_cmd_placeholder' "$STEP5" && grep -qF 'test_cmd_provisional' "$STEP5"; then
  ok "RF11: Step 5 conditions --tests-root on test_cmd_placeholder and test_cmd_provisional"
else
  bad "RF11: Step 5 is missing the test_cmd_placeholder / test_cmd_provisional conditioning (Task 6)"
fi

# ==============================================================================================
# RH. step5-report.json schema + orchestrator read contract, and the Step 2 architect dispatch
# line (ADR-0048 §D6/§D9). EXPECTED RED until Task 6. Read from the same Step 5 extract, plus a
# separate Step 2 extract for RH6.
# ==============================================================================================
if grep -qF '"requirement_coverage"' "$STEP5"; then
  ok "RH1: the documented JSON schema block contains \"requirement_coverage\""
else
  bad "RH1: \"requirement_coverage\" missing from the documented schema block (Task 6)"
fi

if grep -F -A5 '"requirement_coverage"' "$STEP5" | grep -q '"ids_declared"' \
   && grep -F -A5 '"requirement_coverage"' "$STEP5" | grep -q '"uncovered"' \
   && grep -F -A5 '"requirement_coverage"' "$STEP5" | grep -q '"status"'; then
  ok "RH2: the schema shows ids_declared, uncovered and status within the requirement_coverage object"
else
  bad "RH2: the schema does not show ids_declared/uncovered/status near requirement_coverage (Task 6)"
fi

if grep -qF 'requirement_coverage' "$STEP5" && grep -qF 'failure signal' "$STEP5" \
   && grep -qF 'uncovered' "$STEP5"; then
  ok "RH3: the read contract states requirement_coverage.uncovered non-empty is a failure signal"
else
  bad "RH3: the read contract is missing the requirement_coverage / uncovered / failure signal statement (Task 6)"
fi

if grep -qF 'requirement_coverage' "$STEP5" && grep -qF 'absent' "$STEP5" && grep -qF 'not malformed' "$STEP5"; then
  ok "RH4: the read contract states the additive rule — absent means the gate did not write one and is not malformed"
else
  bad "RH4: the read contract is missing the requirement_coverage additive-absence rule (Task 6)"
fi

if grep -qF 'weakening_findings' "$STEP5" && grep -qF 'checkpoint_reviews' "$STEP5" \
   && grep -qF 'never a failure signal' "$STEP5"; then
  ok "RH5: forward guard — weakening_findings and checkpoint_reviews are still both in the schema block, and the checkpoint_reviews-never-a-failure-signal contrast survives (appending is safe, reflowing is not — #101's WD assertions read this same block)"
else
  bad "RH5: weakening_findings / checkpoint_reviews / never-a-failure-signal missing from the schema block — this is a forward guard, not fix evidence for this feature"
fi

STEP2="$TMP/c2c_step2.txt"
awk '/^### Step 2 —/{f=1} /^### Step 3 —/{f=0} f' "$CC" >"$STEP2"
if [ -s "$STEP2" ] && grep -qE 'R-[0-9][0-9]' "$STEP2" && grep -qi 'cite' "$STEP2"; then
  ok "RH6: the Step 2 architect dispatch prompt tells the architect to cite requirement IDs (R-NN + cite)"
else
  bad "RH6: the Step 2 architect dispatch prompt does not mention citing requirement IDs (Task 6)"
fi

# ==============================================================================================
# RI. The two SPEC generators and the architect's plan-citation contract (ADR-0048 §D6).
# EXPECTED RED until Task 8, except RI2/RI6 which are forward guards (green on arrival).
# ==============================================================================================
IVD="$STAGING/plugin/skills/interview-driver/SKILL.md"
SFI="$STAGING/plugin/skills/spec-from-issue/SKILL.md"
ARCH_AGENT="$STAGING/plugin/agents/architect.md"

if grep -qF 'R-01' "$IVD" && grep -qi 'success criteria' "$IVD"; then
  ok "RI1: interview-driver/SKILL.md requires enumerated R-01, R-02, ... success-criteria items"
else
  bad "RI1: interview-driver/SKILL.md does not mention R-01 alongside success criteria (Task 8)"
fi

# RI2 (inverted 2026-07-27, ADR-0067): this was a forward guard asserting the flag was PRESENT, on
# the issue-#56 /loop safety rationale. That rationale collided with concept-to-code Step 1, which
# dispatches this skill through the Skill tool — a flagged skill cannot be invoked that way, so the
# chain's greenfield entry point failed outright. The flag is now deliberately absent here and here
# only; fastapi-react-vibe / goal-loop / research-prompt keep theirs. The authoritative pair of
# assertions lives in skill-text-corrections.test.sh section F (F1 absence, F2 presence); this stays
# as a second site so a future restore fails in both harnesses rather than silently in one.
RI2_CLOSE=$(awk 'NR>1 && $0=="---"{print NR; exit}' "$IVD")
if [ -n "$RI2_CLOSE" ] && sed -n "2,${RI2_CLOSE}p" "$IVD" | grep -qx 'disable-model-invocation: true'; then
  bad "RI2: interview-driver/SKILL.md carries disable-model-invocation: true again — that breaks c2c Step 1 (ADR-0067); this is a forward guard, not fix evidence for this feature"
else
  ok "RI2: forward guard — interview-driver/SKILL.md frontmatter carries no disable-model-invocation (ADR-0067)"
fi

if grep -qF 'R-01' "$SFI" && grep -qi 'success criteria' "$SFI"; then
  ok "RI3: spec-from-issue/SKILL.md's Success criteria template requires R-NN-prefixed items starting at R-01"
else
  bad "RI3: spec-from-issue/SKILL.md does not require R-01-prefixed success-criteria items (Task 8)"
fi

if grep -qi 'id' "$SFI" && grep -qF 'never a reason to invent a criterion' "$SFI"; then
  ok "RI4: spec-from-issue/SKILL.md carries the no-fabrication guardrail for IDs"
else
  bad "RI4: spec-from-issue/SKILL.md is missing the ID no-fabrication guardrail — the instruction 'give every criterion an ID' is satisfiable by producing more criteria (Task 8)"
fi

if grep -qE 'R-[0-9][0-9]' "$ARCH_AGENT" && grep -qi 'cite' "$ARCH_AGENT" && grep -qF '(R-02, R-05)' "$ARCH_AGENT"; then
  ok "RI5: architect.md Output Format requires each plan task to cite requirement IDs, form (R-02, R-05)"
else
  bad "RI5: architect.md does not require requirement-ID citation on plan tasks (Task 8)"
fi

RI6_MISSING=""
for _e in 'Bash(git log*)' 'Bash(git diff*)' 'Bash(git show*)' 'Bash(git status*)' 'Bash(git rev-parse*)'; do
  sed -n '4p' "$ARCH_AGENT" | grep -qF "$_e" || RI6_MISSING="$RI6_MISSING $_e"
done
if [ -z "$RI6_MISSING" ] && ! sed -n '4p' "$ARCH_AGENT" | grep -qF 'Bash(git *)' \
   && grep -qF 'Command scope' "$ARCH_AGENT" && grep -qF 'Write scope' "$ARCH_AGENT"; then
  ok "RI6: forward guard — architect.md line 4 still carries the five read-only git entries, no Bash(git *), and the Command-scope/Write-scope bullets survive"
else
  bad "RI6: architect.md line 4 or its Command-scope/Write-scope bullets regressed — this is a forward guard duplicating agent-tool-scoping.test.sh A1/A12/A14, not fix evidence for this feature. Missing:$RI6_MISSING"
fi

# RI7 (R-08, ADR-0154 D6, D8 — RED until Task 3): the architect's Implementation-plan bullet states
# that a plan names the harness it creates, and that the harness names the plan or its ADR back, or
# spec-coverage.sh descopes it. Scoped to that ONE bullet (not the whole file) so the needle cannot
# be satisfied by the unrelated no-test: bullet, which already carries "instruction"/"enforcement"
# today for a different clause entirely (rule 1 — a needle must belong to the mechanism it asserts
# about, and to nothing else).
# plant: RI7 | plugin/agents/architect.md | A plan names the harness it creates, and that harness must name the plan's own basename or one of the ADRs the plan cites back — or `spec-coverage.sh` descopes it as a precedent citation and the feature's own ids report `UNSCOPED` (ADR-0154). This is an instruction, not an enforcement (rule 16): nothing here forces a plan to follow it; what is enforced is the consequence at the gate.
RI7_BULLET=$(awk 'BEGIN{g=0} /^- \*\*Implementation plan\*\*/{g=1} g{ if ($0 !~ /^- \*\*Implementation plan\*\*/ && $0 ~ /^- \*\*/) exit; print }' "$ARCH_AGENT" 2>/dev/null | tr -d '`*' | tr '\n' ' ' | tr -s ' ')
if printf '%s\n' "$RI7_BULLET" | grep -qi 'harness it creates' \
   && printf '%s\n' "$RI7_BULLET" | grep -qiE 'descope|unscoped' \
   && printf '%s\n' "$RI7_BULLET" | grep -qi 'instruction' \
   && printf '%s\n' "$RI7_BULLET" | grep -qi 'enforcement'; then
  ok "RI7 (R-08): architect.md's Implementation-plan bullet states that a plan names the harness it creates and that the harness names the plan or its ADR back or spec-coverage.sh descopes it, and discloses this is an instruction, not an enforcement (Task 3)"
else
  bad "RI7: architect.md's Implementation-plan bullet does not yet state the harness back-reference convention (Task 3) — bullet=[$RI7_BULLET]"
fi

# ==================================================================================================
# RN. Issue #171 / ADR-0072 — the near-miss, and the repair that heals it.
#
# A requirement declared as `- R-01 — …` inside a recognised section was examined by NOTHING: the
# parser only ever looked at checklist items, so the token reached neither the declared set nor the
# malformed set nor the out-of-section set, DECL_N stayed 0, and the SPEC took the silent no-IDs
# path. A SPEC with 17 requirements passed the gate.
#
# THE INVARIANT UNDER TEST IS THE ROUND TRIP, not detection alone (RN5): every line the checker
# flags as a near-miss must become a line it READS once the repair runs. A detection the repair
# cannot heal would report a problem, rewrite the file, and still fail — worse than no detection.
# ==================================================================================================
NORM="$STAGING/plugin/skills/concept-to-code/scripts/spec-normalize-ids.sh"
SPRED="$STAGING/plugin/skills/concept-to-code/scripts/spec-id-predicate.awk"

for _f in "$NORM" "$SPRED"; do
  [ -f "$_f" ] \
    && ok "RN0: $(basename "$_f") exists" \
    || bad "RN0: $_f not found — every RN assertion below is meaningless"
done

printf '# Plan\n\n## Task 1 — do it (R-01, R-02)\n' >"$TMP/rn-plan.md"
printf '# SPEC\n\n## Objectives\n\n- R-99 before the section, must not change\n\n## Success criteria\n\n- R-01 — does X\n- [ ] R-02 — already correct\n- a plain note with no id\n\n## Notes\n\n- R-98 after the section, must not change\n' >"$TMP/rn.spec.md"

RN1_OUT=$(bash "$SCOV" --spec "$TMP/rn.spec.md" --plan "$TMP/rn-plan.md" 2>"$TMP/rn.err"); RN1_RC=$?
RN1_ERR=$(cat "$TMP/rn.err")

# RN1 IS NOT FIX EVIDENCE ON ITS OWN. Verified against the pre-fix checker: this fixture already
# exited 3 there, for an unrelated reason (the plan cites R-01, which was declared nowhere, so it
# came out as ORPHAN). RN2 and RN3 are what distinguish the right exit code from the right exit
# code for the wrong cause. RN6-RN9 likewise pass pre-fix, because with no normaliser the file is
# never touched at all — they are guards on the repair's blast radius, not proof that it runs.
[ "$RN1_RC" -eq 3 ] \
  && ok "RN1: a plain-bullet declaration is a structural error (exit 3), not a silent pass" \
  || bad "RN1: expected exit 3 on a near-miss SPEC, got $RN1_RC — this is the #171 defect"

printf '%s\n' "$RN1_OUT" | grep -q "^MALFORMED${TAB}R-01" \
  && ok "RN2: the near-miss id is reported on stdout as MALFORMED" \
  || bad "RN2: R-01 not reported — got [$RN1_OUT]"

# The stderr sentence must name THIS cause, not the sibling guard's. Both write MALFORMED to stdout,
# so stderr is the only channel that distinguishes "right form, wrong place" from "right place,
# wrong form" — and it carries the repair command, which is the point of the whole design.
printf '%s\n' "$RN1_ERR" | grep -q 'declared as plain bullets' \
  && ok "RN3: stderr names the plain-bullet cause, distinct from the out-of-section guard" \
  || bad "RN3: stderr does not name the plain-bullet cause — got [$RN1_ERR]"
printf '%s\n' "$RN1_ERR" | grep -q 'spec-normalize-ids.sh' \
  && ok "RN4: stderr carries the exact repair command" \
  || bad "RN4: stderr does not name the repair command — a detection with no prescribed heal"

# --- RN5: the round trip. Detection is only worth having if the repair makes it readable. ---
bash "$NORM" --spec "$TMP/rn.spec.md" --apply >"$TMP/rn.diff" 2>&1; RN5_NRC=$?
RN5_OUT=$(bash "$SCOV" --spec "$TMP/rn.spec.md" --plan "$TMP/rn-plan.md" --list 2>/dev/null); RN5_RC=$?
{ [ "$RN5_NRC" -eq 0 ] && [ "$RN5_RC" -eq 0 ] && printf '%s\n' "$RN5_OUT" | grep -q "^R-01${TAB}does X"; } \
  && ok "RN5 (round trip): after --apply the same SPEC passes and R-01 is declared" \
  || bad "RN5: repair did not make the SPEC readable — nrc=$RN5_NRC rc=$RN5_RC out=[$RN5_OUT]"

# --- RN6-RN9: the repair touches only what it must. ---
grep -q '^- R-99 before the section, must not change$' "$TMP/rn.spec.md" \
  && ok "RN6: a bullet BEFORE the section is byte-identical after the repair" \
  || bad "RN6: the repair rewrote a bullet outside the recognised section"
grep -q '^- R-98 after the section, must not change$' "$TMP/rn.spec.md" \
  && ok "RN7: a bullet AFTER the section is byte-identical after the repair" \
  || bad "RN7: the repair rewrote a bullet after the section closed"
grep -q '^- a plain note with no id$' "$TMP/rn.spec.md" \
  && ok "RN8: a plain bullet with no id is untouched" \
  || bad "RN8: the repair rewrote a bullet carrying no requirement id"
RN9_N=$(grep -c '^- \[ \] R-02 — already correct$' "$TMP/rn.spec.md")
[ "$RN9_N" = "1" ] \
  && ok "RN9: an already-correct checklist item is not double-marked" \
  || bad "RN9: R-02 was rewritten ($RN9_N matches) — the repair is not idempotent on correct input"

RN10_OUT=$(bash "$NORM" --spec "$TMP/rn.spec.md")
[ "$RN10_OUT" = "CLEAN" ] \
  && ok "RN10: a second run reports CLEAN — the repair is idempotent" \
  || bad "RN10: second run still proposes changes: [$RN10_OUT]"

# --- RN11: the negative twin. Without it, RN1 is also satisfied by a checker that fails on
# everything (rule 8 of .claude/context.md). ---
printf '# SPEC\n\n## Success criteria\n\n- [ ] R-01 — does X\n- [ ] R-02 — does Y\n' >"$TMP/rn-ok.spec.md"
RN11_OUT=$(bash "$NORM" --spec "$TMP/rn-ok.spec.md")
[ "$RN11_OUT" = "CLEAN" ] \
  && ok "RN11 (negative twin of RN1): a correctly-written SPEC needs no repair" \
  || bad "RN11: the repair wants to rewrite a correct SPEC: [$RN11_OUT]"

# --- RN12: INVERTED IN KIND (2026-08-03, ADR-0122 §D8, issue #291). Was "the disclosed limit,
# pinned so the exclusion is a decision on record" — a bold-wrapped id was NOT detected, and the
# repair left it unreadable. It now asserts the OPPOSITE, on the SAME fixture: the round trip
# HOLDS for the bold plain-bullet form. This is not a relaxation of the check; it is the check for
# the contract this repository ships now (ADR-0122 D1/D2). See section RM below for the rest of
# the new-behaviour coverage.
# plant: RN12 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | t = strip_emphasis(t) | t = t
printf '# SPEC\n\n## Success criteria\n\n- **R-01** — bold id\n' >"$TMP/rn-bold.spec.md"
bash "$NORM" --spec "$TMP/rn-bold.spec.md" --apply >/dev/null 2>&1
printf '# Plan\n\n## Task 1 — noop (R-01)\n' >"$TMP/rn12-plan.md"
RN12_LIST=$(bash "$SCOV" --spec "$TMP/rn-bold.spec.md" --plan "$TMP/rn12-plan.md" --list 2>/dev/null)
{ grep -q -- '^- \[ \] \*\*R-01\*\* — bold id$' "$TMP/rn-bold.spec.md" \
    && printf '%s\n' "$RN12_LIST" | grep -q "^R-01${TAB}"; } \
  && ok "RN12 (inverted, ADR-0122 §D8): the round trip holds for the bold plain-bullet form — repaired into \`- [ ] **R-01** — bold id\` and then read as declared" \
  || bad "RN12: the round trip does not hold for a bold-wrapped id — repaired-file=[$(cat "$TMP/rn-bold.spec.md")] list=[$RN12_LIST]"

# --- RN13: the whole corpus stays silent, count-guarded. Same hard gate as section RE, re-asserted
# after adding a new way for the checker to fail. ---
RN13_TOTAL=0; RN13_NOISY=0
for _s in "$REPO"/docs/specs/*.spec.md "$REPO/SPEC.md"; do
  [ -f "$_s" ] || continue
  RN13_TOTAL=$((RN13_TOTAL + 1))
  _o=$(bash "$NORM" --spec "$_s" 2>&1)
  [ "$_o" = "CLEAN" ] || RN13_NOISY=$((RN13_NOISY + 1))
done
[ "$RN13_TOTAL" -ge 30 ] \
  && ok "RN13a (count guard): the corpus sweep ran over $RN13_TOTAL SPECs" \
  || bad "RN13a (count guard): only $RN13_TOTAL SPEC(s) swept — RN13b proves nothing"
[ "$RN13_NOISY" -eq 0 ] \
  && ok "RN13b: no existing SPEC needs repair — the near-miss rule costs the corpus nothing" \
  || bad "RN13b: $RN13_NOISY existing SPEC(s) would be rewritten — re-derive before shipping"

# --- RN14: PAIRS. Both new files are called from a SKILL.md by their DEPLOYED path. ---
SYNCSH2="$STAGING/sync-to-claude.sh"
for _need in spec-id-predicate.awk spec-normalize-ids.sh; do
  grep -q "concept-to-code/scripts/$_need|" "$SYNCSH2" 2>/dev/null \
    && ok "RN14: $_need has a PAIRS entry" \
    || bad "RN14: $_need has NO PAIRS entry — the gate would call a file that never deployed"
done

# --- RN15: both producers agree on the declaration form. Instance-level anchoring on one file is
# what let #171 through (rule 9). ---
ID_SKILL="$STAGING/plugin/skills/interview-driver/SKILL.md"
SFI_SKILL="$STAGING/plugin/skills/spec-from-issue/SKILL.md"
RN15_MISS=""
for _p in "$ID_SKILL" "$SFI_SKILL"; do
  [ -f "$_p" ] || { RN15_MISS="$RN15_MISS $(basename "$(dirname "$_p")")(absent)"; continue; }
  grep -q -- '- \[ \] R-01' "$_p" || RN15_MISS="$RN15_MISS $(basename "$(dirname "$_p")")"
done
[ -z "$RN15_MISS" ] \
  && ok "RN15: both SPEC producers show the literal '- [ ] R-01' form in their template" \
  || bad "RN15: producer(s) without the literal marker:$RN15_MISS — the drift #171 was filed about"

# ==================================================================================================
# RM. Issue #291 / ADR-0122 — a bold-wrapped requirement id is invisible to both the checker and
# the repairer. RN12 above is changed IN KIND to assert the new contract on ADR-0072's own fixture;
# this section covers the rest: the closing-run trim, the round trip, the mixed-SPEC damaging case
# (ADR-0122 M4), the position rule (unchanged, D5), decoration tolerance beyond bold (D3), and the
# corpus differential (R-03, D9).
#
# EXPECTED RED, in whole or in part, until the coder lands Tasks 2-3 (spec-id-predicate.awk's
# strip_emphasis() and spec-coverage.sh's three call sites). Before that, `strip_emphasis` is not
# called anywhere and a bold-wrapped id at the START of an item's text never matches the checker's
# `^R-` anchor in either the checklist-item or the near-miss branch, so every bold-carrying fixture
# below is currently invisible (the DECL_N=0 silent path) rather than declared or MALFORMED.
# RM11/RM12 are corpus facts independent of this fix (0 bold ids exist in the corpus today, ADR-0122
# M3) and may already pass — that is expected, not a defect in the assertion.
# ==================================================================================================
mkdir -p "$TMP/rm-tests"
RM_PLAN="$TMP/rm-tests/rm-plan.md"
printf '# Plan\n\n## Task 1 — noop\n' >"$RM_PLAN"

printf '# SPEC\n\n## Success criteria\n\n- [ ] **R-01** — bold checklist id\n' >"$TMP/rm-tests/rm-bold-item.spec.md"
printf '# SPEC\n\n## Success criteria\n\n- **R-01** — bold plain bullet\n' >"$TMP/rm-tests/rm-bold-bullet.spec.md"
printf '# SPEC\n\n## Success criteria\n\n- [ ] R-01 — plain\n- [ ] **R-02** — bold mixed\n' >"$TMP/rm-tests/rm-mixed.spec.md"
printf '# SPEC\n\n## Success criteria\n\n- [ ] **Note** R-01 is mentioned mid-sentence\n' >"$TMP/rm-tests/rm-mention.spec.md"
printf '# SPEC\n\n## Success criteria\n\n- [ ] __R-01__ — underscore\n- [ ] *R-01* — italic\n' >"$TMP/rm-tests/rm-underscore.spec.md"

# --- RM01/RM02: a bold-wrapped id inside a checklist item declares, and the closing run is trimmed
# from the --list text (not just the leading one — RM01 alone would not prove that, ADR-0122 D4.3). ---
# plant: RM01 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | txt = strip_emphasis(item_text(line)) | txt = item_text(line)
# plant: RM02 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | rest = strip_emphasis(rest) | rest = rest
RM01_OUT=$(bash "$SCOV" --spec "$TMP/rm-tests/rm-bold-item.spec.md" --plan "$RM_PLAN" --list 2>/dev/null); RM01_RC=$?
[ "$RM01_RC" -eq 0 ] && [ -n "$RM01_OUT" ] \
  && ok "RM01: a bold-wrapped id inside a checklist item declares (R-01)" \
  || bad "RM01: rm-bold-item did not declare — rc=$RM01_RC out=[$RM01_OUT]"
printf '%s\n' "$RM01_OUT" | grep -qx "R-01${TAB}bold checklist id" \
  && ok "RM02: --list text is exactly 'bold checklist id' — no leading or trailing ** (the closing-run trim)" \
  || bad "RM02: --list text carries leftover emphasis or is wrong — got [$RM01_OUT]"

# --- RM03/RM04: a bold-wrapped id as a plain BULLET is a near-miss — MALFORMED, exit 3, and the
# stderr sentence names the plain-bullet cause plus the repair command, never the word "bold"
# (ADR-0122 D6). ---
# plant: RM03 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | t = strip_emphasis(t) | t = t
# plant: RM04 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | nmt = strip_emphasis(nmt) | nmt = nmt
RM03_OUT=$(bash "$SCOV" --spec "$TMP/rm-tests/rm-bold-bullet.spec.md" --plan "$RM_PLAN" 2>"$TMP/rm-tests/rm03.err"); RM03_RC=$?
RM03_ERR=$(cat "$TMP/rm-tests/rm03.err" 2>/dev/null)
[ "$RM03_RC" -eq 3 ] && printf '%s\n' "$RM03_OUT" | grep -q "^MALFORMED${TAB}R-01" \
  && ok "RM03: a bold-wrapped id as a plain bullet is a near-miss (exit 3, MALFORMED R-01)" \
  || bad "RM03: expected exit 3 / MALFORMED R-01, got rc=$RM03_RC out=[$RM03_OUT]"
{ printf '%s\n' "$RM03_ERR" | grep -q 'declared as plain bullets'; } \
  && { printf '%s\n' "$RM03_ERR" | grep -q 'spec-normalize-ids.sh'; } \
  && ok "RM04: stderr names the plain-bullet cause and the repair command" \
  || bad "RM04: stderr does not name both the cause and the repair command — got [$RM03_ERR]"

# --- RM05/RM06/RM07: the round trip. Mutates rm-bold-bullet.spec.md IN PLACE, after RM03/RM04 have
# already read its pre-repair state — the same ordering RN's own round trip (RN1-RN4 then RN5) uses.
# ---
# plant: RM05 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | function strip_emphasis(s) { sub(/^[*_]+/, "", s) return s } | function strip_emphasis(s) { return s }
# plant: RM06 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | return indent "- [ ] " rest | sub(/^[*_]+/, "", rest); return indent "- [ ] " rest
# RM07 CARRIES NO PLANT, and that is the honest outcome rather than an oversight. It asserts a
# second --apply run reports CLEAN, i.e. the repair is idempotent. Measured: no single-line
# mutation of spec-id-predicate.awk breaks it. Neutering strip_emphasis() leaves the repaired
# line a checklist item, so is_near_miss_bullet() returns 0 at its first test and CLEAN still
# holds; disabling that first test lets the token fall through as `[`, which matches no id, so
# CLEAN holds again. The property is true regardless of the mechanism under it, which means
# RM07 pins nothing today. Recorded, not papered over with a plant that would fire for an
# unrelated reason — a plant that fires for the wrong cause is worse than a declared gap.
bash "$NORM" --spec "$TMP/rm-tests/rm-bold-bullet.spec.md" --apply >/dev/null 2>&1
RM05_OUT=$(bash "$SCOV" --spec "$TMP/rm-tests/rm-bold-bullet.spec.md" --plan "$RM_PLAN" --list 2>/dev/null); RM05_RC=$?
[ "$RM05_RC" -eq 0 ] && printf '%s\n' "$RM05_OUT" | grep -qx "R-01${TAB}bold plain bullet" \
  && ok "RM05 (round trip): after --apply, rm-bold-bullet passes and R-01 is declared" \
  || bad "RM05: repair did not make rm-bold-bullet readable — rc=$RM05_RC out=[$RM05_OUT]"
grep -qxF -- '- [ ] **R-01** — bold plain bullet' "$TMP/rm-tests/rm-bold-bullet.spec.md" \
  && ok "RM06: the repaired line is exactly '- [ ] **R-01** — bold plain bullet' — the ** survives, only the marker is added" \
  || bad "RM06: the repaired line lost or altered the emphasis — got [$(cat "$TMP/rm-tests/rm-bold-bullet.spec.md" 2>/dev/null)]"
RM07_OUT=$(bash "$NORM" --spec "$TMP/rm-tests/rm-bold-bullet.spec.md")
[ "$RM07_OUT" = "CLEAN" ] \
  && ok "RM07: a second normalise run on the repaired file reports CLEAN" \
  || bad "RM07: second run still proposes changes: [$RM07_OUT]"

# --- RM08: the mixed SPEC — ADR-0122 M4, the shape that passed the gate while losing a requirement.
# Both R-01 (plain) and R-02 (bold) must declare. ---
# plant: RM08 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | txt = strip_emphasis(item_text(line)) | txt = item_text(line)
RM08_OUT=$(bash "$SCOV" --spec "$TMP/rm-tests/rm-mixed.spec.md" --plan "$RM_PLAN" --list 2>/dev/null); RM08_RC=$?
{ [ "$RM08_RC" -eq 0 ] \
  && printf '%s\n' "$RM08_OUT" | grep -q "^R-01${TAB}" \
  && printf '%s\n' "$RM08_OUT" | grep -q "^R-02${TAB}"; } \
  && ok "RM08: the mixed SPEC declares BOTH R-01 (plain) and R-02 (bold) — M4's vanishing requirement is closed" \
  || bad "RM08: mixed SPEC does not declare both ids — rc=$RM08_RC out=[$RM08_OUT]"

# --- RM09: the negative twin. The widening changes decoration TOLERANCE, never the POSITION rule
# (ADR-0122 D5) — a mid-sentence mention still declares nothing. Without it RM01 would also be
# satisfied by a checker that declares everything. ---
# plant: RM09 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | function strip_emphasis(s) { sub(/^[*_]+/, "", s) return s } | function strip_emphasis(s) { sub(/^[^R]+/, "", s); return s }
RM09_OUT=$(bash "$SCOV" --spec "$TMP/rm-tests/rm-mention.spec.md" --plan "$RM_PLAN" --list 2>/dev/null); RM09_RC=$?
[ "$RM09_RC" -eq 0 ] && [ -z "$RM09_OUT" ] \
  && ok "RM09 (negative twin): a mid-sentence mention still declares nothing after the widening" \
  || bad "RM09: rm-mention wrongly declared something — rc=$RM09_RC out=[$RM09_OUT]"

# --- RM10: __R-01__ and *R-01* both strip to R-01 — proven by the DUPLICATE detector firing, which
# only happens if BOTH lines are independently recognised as declaring the same id (ADR-0122 D3: a
# character-class RUN, never a **-then-* ladder, or **R-01** would lose one asterisk). ---
# plant: RM10 | plugin/skills/concept-to-code/scripts/spec-id-predicate.awk | function strip_emphasis(s) { sub(/^[*_]+/, "", s) return s } | function strip_emphasis(s) { sub(/^\*\*/, "", s); return s }
RM10_OUT=$(bash "$SCOV" --spec "$TMP/rm-tests/rm-underscore.spec.md" --plan "$RM_PLAN" 2>/dev/null); RM10_RC=$?
[ "$RM10_RC" -eq 3 ] && printf '%s\n' "$RM10_OUT" | grep -q "^DUPLICATE${TAB}R-01" \
  && ok "RM10: __R-01__ and *R-01* both strip to R-01 — DUPLICATE R-01 confirms both decorations are recognised" \
  || bad "RM10: expected DUPLICATE R-01 (both forms recognised), got rc=$RM10_RC out=[$RM10_OUT]"

# --- RM11/RM12: R-03, proven at the mechanism level (ADR-0122 D9), never by a golden file. Both
# count-guarded — a sweep over zero SPECs would report no regressions and look identical to a clean
# run. Includes the root SPEC.md deliberately (it carries 3 backticked **R-01** occurrences in
# prose, the adversarial file, unlike RE3's exclusion of it — RE3 needs the silent pass this file
# legitimately fails on unrelated id-declaring grounds; neither RM11 nor RM12 does). ---
# plant: RM11 | ../docs/specs/287-rtf-s-gitignore-glob-and-this-repo-s-own.spec.md | - [ ] R-01 — one rule, covering | - [ ] **R-01** — one rule, covering
# plant: RM12 | ../docs/specs/287-rtf-s-gitignore-glob-and-this-repo-s-own.spec.md | - [ ] R-02 — an assertion that seeds | - **R-02** — an assertion that seeds
RM11_TOTAL=0; RM11_HITS=0
for _s in "$REPO"/docs/specs/*.spec.md "$REPO/SPEC.md"; do
  [ -f "$_s" ] || continue
  RM11_TOTAL=$((RM11_TOTAL + 1))
  _n=$(grep -cE '^[ \t]*[-*][ \t]+(\[[ xX]\][ \t]*)?[*_]+R-[0-9][0-9]' "$_s" 2>/dev/null || true)
  RM11_HITS=$((RM11_HITS + ${_n:-0}))
done
if [ "$RM11_TOTAL" -ge 50 ] && [ "$RM11_HITS" -eq 0 ]; then
  ok "RM11 (R-03): corpus differential — $RM11_TOTAL SPECs swept, zero emphasis-sensitive declaration lines — the parse is byte-identical to the pre-change parse"
else
  bad "RM11: corpus differential failed — swept=$RM11_TOTAL (need >=50), emphasis-sensitive hits=$RM11_HITS (need 0)"
fi

RM12_TOTAL=0; RM12_MALFORMED=0
for _s in "$REPO"/docs/specs/*.spec.md "$REPO/SPEC.md"; do
  [ -f "$_s" ] || continue
  RM12_TOTAL=$((RM12_TOTAL + 1))
  _o=$(bash "$SCOV" --spec "$_s" --plan "$RM_PLAN" --list 2>/dev/null)
  printf '%s\n' "$_o" | grep -q '^MALFORMED' && RM12_MALFORMED=$((RM12_MALFORMED + 1))
done
if [ "$RM12_TOTAL" -ge 50 ] && [ "$RM12_MALFORMED" -eq 0 ]; then
  ok "RM12 (R-03): corpus outcome — $RM12_TOTAL SPECs swept, no SPEC reports MALFORMED under the widened checker"
else
  bad "RM12: corpus outcome failed — swept=$RM12_TOTAL (need >=50), MALFORMED-reporting SPEC(s)=$RM12_MALFORMED (need 0)"
fi

# ==================================================================================================
# RS. Issue #312 / ADR-0138 D1-D3 — the test axis is scoped to the test files the PLAN names, not
# the whole discovered population, plus D2's SCOPE-EMPTY denominator guard.
#
# STATE ON ARRIVAL (Batch A of the #312 plan, pre-fix): RS1 and RS6 are RED — the scope filter and
# the SCOPE-EMPTY guard do not exist yet, so today's global scan reports COVERED for both and stderr
# never says SCOPE-EMPTY. RS2, RS3, RS4 and RS5 are GREEN ALREADY: each names a scenario whose
# verdict is unaffected by scoping (the id IS in the file the plan names, or is absent everywhere,
# or the .md exclusion already holds upstream of any scope filter) — they are the positive controls
# / already-true invariants that must stay true both before AND after Task 3 lands, not fresh red
# assertions. Every fixture below was executed against the unmodified checker before this comment
# was written (CLAUDE.md rule 2 — inspect what a check actually produces, never assume it).
# ==================================================================================================
# ADR-0154 plant widening (Batch F, rule 19 — a changed plant leaves a note explaining why): this
# plant used to force ONLY half 1 (the "named by the plan" grep) to `if :; then`, which was
# sufficient before this feature because half 1 was the WHOLE admission test. Half 2 (the
# back-reference conjunct) now drops beta.test.sh independently of half 1 — its own text never names
# the plan or an ADR — so the old mutation left the verdict at UNSCOPED unchanged (a measured NOFIRE)
# and pinned nothing. The replacement below now ALSO appends the current file to $TESTFILES_SCOPED
# unconditionally, ahead of both halves, defeating the whole conjunction in one mutation — the same
# outcome as deleting the scope filter outright. RS1's own predicate, expected exit code and message
# are untouched; only this line's REPLACEMENT field changed.
# plant: RS1 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if grep -qE "(^|[^A-Za-z0-9_])${_esc}([^A-Za-z0-9_]|\$)" "$PLAN" 2>/dev/null; then | printf '%s\n' "$_f" >>"$TESTFILES_SCOPED"; if :; then
cat >"$TMP/rs1.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rs1-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Test coverage lives in alpha.test.sh.
EOF
mkdir -p "$TMP/rs1-tests"
# ADR-0154 fixture amendment (Batch C Task 4, operator-authorised — see the plan's Work Item 1):
# alpha.test.sh now names the plan back (rs1-plan.md) so Task 2's half 2 admits it. RS1's own
# predicate and its expected UNSCOPED R-01 1 outcome below are UNCHANGED — only this fixture's
# input gained a back-reference. Before ADR-0154, half 1 alone scoped alpha.test.sh in; after it,
# alpha.test.sh (the file half 1 actually admits) must also name the feature back, or half 2 drops
# it, the scope collapses to zero, and the verdict flips to UNSCOPED R-01 0 (SCOPE-NO-BACKREF) —
# a defect in this fixture's fit to a new rule it predates, not in what RS1 was written to prove.
cat >"$TMP/rs1-tests/alpha.test.sh" <<'EOF'
# no id here
# names the plan back: rs1-plan.md
EOF
cat >"$TMP/rs1-tests/beta.test.sh" <<'EOF'
# covers R-01
EOF
run_scov --spec "$TMP/rs1.spec.md" --plan "$TMP/rs1-plan.md" --tests-root "$TMP/rs1-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RS1 (D1/D3): R-01 is mentioned only in beta.test.sh, which the plan never names — UNSCOPED	R-01	1, exit 1. Today (pre-fix, verified) this exact fixture is COVERED, exit 0 — the whole defect in one fixture."
else
  bad "RS1: expected exit 1 + UNSCOPED R-01 1 (an out-of-scope mention) — got rc=$RC out=[$OUT]"
fi

mkdir -p "$TMP/rs2-tests"
# ADR-0154 fixture amendment (Batch C Task 4, operator-authorised — see the plan's Work Item 1):
# alpha.test.sh now names the plan back (rs1-plan.md) so Task 2's half 2 admits it. RS2's own
# predicate and its expected COVERED R-01 / exit-0 / no-UNSCOPED-line outcome below are UNCHANGED
# — RS2's INTENT is the positive twin of RS1 (CLAUDE.md rule 8), and half 2 is incidental to that:
# without a back-reference this file is dropped by half 2, the scope collapses to zero, and R-01
# (mentioned nowhere else in this tree) flips to UNSCOPED R-01 0.
cat >"$TMP/rs2-tests/alpha.test.sh" <<'EOF'
# covers R-01
# names the plan back: rs1-plan.md
EOF
cat >"$TMP/rs2-tests/beta.test.sh" <<'EOF'
# no id here
EOF
run_scov --spec "$TMP/rs1.spec.md" --plan "$TMP/rs1-plan.md" --tests-root "$TMP/rs2-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$" \
   && ! printf '%s\n' "$OUT" | grep -q 'UNSCOPED'; then
  ok "RS2 (positive twin of RS1, CLAUDE.md rule 8): the same tree with R-01 moved into alpha.test.sh, the file the plan names -> COVERED, exit 0, no UNSCOPED line. Without this twin, RS1 is satisfiable by a checker that fails everything."
else
  bad "RS2: expected COVERED R-01 / exit 0 / no UNSCOPED line — got rc=$RC out=[$OUT]"
fi

mkdir -p "$TMP/rs3-tests"
cat >"$TMP/rs3-tests/alpha.test.sh" <<'EOF'
# nothing relevant
EOF
run_scov --spec "$TMP/rs1.spec.md" --plan "$TMP/rs1-plan.md" --tests-root "$TMP/rs3-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNCOVERED${TAB}R-01${TAB}tests\$" \
   && ! printf '%s\n' "$OUT" | grep -q 'UNSCOPED'; then
  ok "RS3: R-01 is absent from EVERY file in the tree -> UNCOVERED	R-01	tests, exit 1, never UNSCOPED — the two tokens carry different remedies and must stay distinguishable"
else
  bad "RS3: expected UNCOVERED R-01 tests, not UNSCOPED — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rs4-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Test coverage lives in staging/plugin/scripts/tests/alpha.test.sh, not just the bare name.
EOF
mkdir -p "$TMP/rs4-tests"
# ADR-0154 fixture amendment (Batch C Task 4, operator-authorised — see the plan's Work Item 1):
# alpha.test.sh now names the plan back (rs4-plan.md) so Task 2's half 2 admits it. RS4's own
# predicate and its expected COVERED R-01 outcome below are UNCHANGED — RS4's INTENT is to prove
# a full-path basename mention still satisfies half 1, and half 2 is incidental to that: without a
# back-reference this lone file is dropped by half 2, the scope collapses to zero, and R-01 (still
# mentioned in the full discovered population, just not in scope) flips to UNSCOPED R-01 0.
cat >"$TMP/rs4-tests/alpha.test.sh" <<'EOF'
# covers R-01
# names the plan back: rs4-plan.md
EOF
run_scov --spec "$TMP/rs1.spec.md" --plan "$TMP/rs4-plan.md" --tests-root "$TMP/rs4-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$"; then
  ok "RS4: the plan names the test file by FULL PATH (staging/plugin/scripts/tests/alpha.test.sh), not the bare basename — still in scope; the corpus uses both forms and the match is on basename"
else
  bad "RS4: expected COVERED R-01 via a full-path basename mention — got rc=$RC out=[$OUT]"
fi

mkdir -p "$TMP/rs5-tests/docs/specs"
cat >"$TMP/rs5-tests/docs/specs/x.spec.md" <<'EOF'
Mentions R-01 in prose.
EOF
cat >"$TMP/rs5-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Background: docs/specs/x.spec.md (also known as x.spec.md).
EOF
run_scov --spec "$TMP/rs1.spec.md" --plan "$TMP/rs5-plan.md" --tests-root "$TMP/rs5-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNCOVERED${TAB}R-01${TAB}tests\$"; then
  ok "RS5: the .md exclusion stays closed even when the plan names the .md file's own basename, bare AND full path — a SPEC cannot cover itself, because \$TESTFILES is already post-exclusion and no .md can enter scope through the new filter (asserted on the absence of self-coverage, not on the presence of a filter)"
else
  bad "RS5: expected UNCOVERED R-01 tests despite the plan naming the .md file — got rc=$RC out=[$OUT]"
fi

# plant: RS6 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if [ ! -s "$TESTFILES_SCOPED" ]; then | if false; then
cat >"$TMP/rs6-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
No test file is named anywhere in this plan's prose.
EOF
mkdir -p "$TMP/rs6-tests"
cat >"$TMP/rs6-tests/alpha.test.sh" <<'EOF'
# covers R-01
EOF
run_scov --spec "$TMP/rs1.spec.md" --plan "$TMP/rs6-plan.md" --tests-root "$TMP/rs6-tests"
rs6_no_unscoped=1
printf '%s\n' "$OUT" | grep -q 'UNSCOPED' && rs6_no_unscoped=0
if [ "$RC" -eq 0 ] && printf '%s\n' "$ERR" | grep -q 'SCOPE-EMPTY' \
   && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$" && [ "$rs6_no_unscoped" -eq 1 ]; then
  ok "RS6 (the denominator guard, CLAUDE.md rule 7 / D2): a plan naming no discovered test file at all, against a non-empty discovered population (1 file) — stderr names SCOPE-EMPTY, stdout falls back to the unscoped verdict (COVERED R-01), exit 0, and there is no wall of UNSCOPED lines. Zero candidates is a broken derivation, not a clean zero."
else
  bad "RS6: expected stderr SCOPE-EMPTY + stdout COVERED R-01 (fallback) + zero UNSCOPED lines + exit 0 — got rc=$RC out=[$OUT] err=[$ERR]"
fi

# ==================================================================================================
# RS7-RS10. Issue #312 / ADR-0138 D5 — R-03 proven by a frozen per-item baseline over the corpus,
# plus the derivation's own denominator guards (RS9) and the silent-path forward guard (RS10).
#
# Issue #460 / ADR-0166-460-spec-coverage-baseline-never-bumped.md /
# 2026-08-22-460-spec-coverage-baseline-never-bumped.md (Task 3) — the per-spec plan resolution
# (RS_PAIRS) and the per-pair verdict derivation (RS_LIVE) below now call
# spec-coverage-baseline-rows.sh's --pair and --rows instead of re-deriving the same two answers a
# second time (CLAUDE.md rule 6). Nothing else moved: the corpus sweep, spec_declares_ids, the
# RS_SELF_PLAN exclusion, and every assertion from RS7 through RS10 below (predicates, floors,
# message text) are byte-identical to before this task.
#
# The (spec, plan) population is derived by issue-number prefix: first try a plan filename naming
# the number, then fall back to the slug-only plan filename the corpus also uses for several Phase
# 11 issues (e.g. 2026-08-02-rtf-s-gitignore-glob-and-this-repo-s-own.md for issue #287 carries no
# "287" token in its filename at all — matching ONLY on <N>-*.md would silently under-derive).
#
# The current chain's OWN pair is excluded — this feature's SPEC (docs/specs/312-...spec.md) paired
# with THIS EXACT PLAN FILE, still being executed batch by batch. Same reasoning as RE3's exclusion
# of $REPO/SPEC.md: an in-flight chain is not a completed corpus member (D5: "their chains are
# complete and the checker will never run on them again"). Re-derive rather than trust this comment
# (CLAUDE.md rule 13) — measured 2026-08-14: including the in-flight pair gives 16 pairs / 120 ids;
# excluding it gives the ADR's own measured 15 pairs / 117 ids, confirmed empirically.
# ==================================================================================================
ROWS="$STAGING/plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh"
# RS0 has no plant: it is an EXISTENCE check (a path is a file and is readable), the same
# unplantable-by-class shape PT1/PT2 (prep.test.sh) and AIJ2 (accessibility-i18n.test.sh) already
# document — there is no text substitution that turns `[ -f "$ROWS" ] && [ -r "$ROWS" ]` false
# without literally deleting the file, which is outside what a plant declaration can express
# (issue #460, ADR-0166).
if [ -f "$ROWS" ] && [ -r "$ROWS" ]; then
  ok "RS0: spec-coverage-baseline-rows.sh exists and is readable — RS7/RS8a/RS8b/RS9 below read live rows through it"
else
  bad "RS0: spec-coverage-baseline-rows.sh not found at $ROWS — RS7/RS8a/RS8b/RS9 below assert nothing"
fi
# plant: RS7 | plugin/scripts/tests/spec-coverage-scope-baseline.tsv | 176-worktree-isolation-contract.spec.md R-01 COVERED | 176-worktree-isolation-contract.spec.md	R-01	UNSCOPED	testable	planted mismatch — proves RS7 compares each row exactly, not merely a count
BASELINE="$SCRIPTS/tests/spec-coverage-scope-baseline.tsv"
RS_SELF_PLAN="$REPO/docs/superpowers/plans/2026-08-14-spec-coverage-measures-citation-not-impl.md"

RS_PAIRS="$TMP/rs-pairs.tsv"; : >"$RS_PAIRS"
for _spec in "$REPO"/docs/specs/*.spec.md; do
  [ -f "$_spec" ] || continue
  _bn=$(basename "$_spec")
  spec_declares_ids "$_spec" || continue
  # issue #460 / ADR-0166 Task 3 (§D2): the two-glob (issue-number, then slug) plan resolution that
  # used to live inline here moved verbatim into spec-coverage-baseline-rows.sh's --pair — this loop
  # now calls it instead of re-deriving the same answer a second time (CLAUDE.md rule 6).
  _plan=$(bash "$ROWS" --pair --spec "$_spec" --plans-dir "$REPO/docs/superpowers/plans")
  [ -n "$_plan" ] && [ -f "$_plan" ] || continue
  [ "$_plan" = "$RS_SELF_PLAN" ] && continue
  printf '%s\t%s\t%s\n' "$_bn" "$_spec" "$_plan" >>"$RS_PAIRS"
done

# For every resolved pair, compute today's live verdict for every declared id (COVERED / UNCOVERED /
# UNSCOPED), read straight off the checker's own stdout — one source of truth for what "covered"
# means, the ADR-0069/ADR-0072 rule applied here too, never a second interpretation of the tokens.
#
# ADR-0154 Task 4 (R-06) additive extension, disclosed here per ADR-0073 §D1: the per-pair run's
# stderr — previously discarded via `2>/dev/null` — is now ALSO captured, into RS_SCOPE below,
# alongside the unchanged stdout capture RS7/RS8/RS9 already read into $RS_LIVE. Neither $RS_LIVE's
# contents, $RS_PAIRS, $_list nor $_run's derivation change: this is a second, parallel readout of
# the SAME per-pair invocation, feeding only the new RY10 corpus-denominator guard further below.
RS_LIVE="$TMP/rs-live.tsv"; : >"$RS_LIVE"
RS_SCOPE="$TMP/rs-scope.tsv"; : >"$RS_SCOPE"
while IFS="$TAB" read -r _bn _spec _plan; do
  [ -n "$_bn" ] || continue
  # issue #460 / ADR-0166 Task 3 (§D3): the --list + --tests-root pair of calls and the per-id
  # COVERED/UNSCOPED classification that used to live inline here moved into
  # spec-coverage-baseline-rows.sh's --rows. One call now produces the same rows, and
  # --tests-root's own stderr still reaches $TMP/rs-live-err.txt unredirected, so
  # _errtxt/_no_backref/_scope_n/RS_SCOPE below read the identical bytes they read before this moved
  # (CLAUDE.md rule 6: extract only when two copies giving different answers would be a defect).
  _rows=$(bash "$ROWS" --rows --spec "$_spec" --plan "$_plan" --tests-root "$REPO" 2>"$TMP/rs-live-err.txt")
  [ -n "$_rows" ] || continue
  _errtxt=$(cat "$TMP/rs-live-err.txt" 2>/dev/null)
  _no_backref=0
  printf '%s\n' "$_errtxt" | grep -q 'SCOPE-NO-BACKREF' && _no_backref=1
  _scope_n=$(printf '%s\n' "$_errtxt" | grep -oE '[0-9]+ in scope' | awk '{print $1}')
  [ -n "$_scope_n" ] || _scope_n=0
  printf '%s\t%s\t%s\n' "$_bn" "$_no_backref" "$_scope_n" >>"$RS_SCOPE"
  printf '%s\n' "$_rows" >>"$RS_LIVE"
done <"$RS_PAIRS"

RS_PAIR_N=$(wc -l <"$RS_PAIRS" 2>/dev/null | tr -d ' '); RS_PAIR_N=${RS_PAIR_N:-0}
RS_ID_N=$(wc -l <"$RS_LIVE" 2>/dev/null | tr -d ' '); RS_ID_N=${RS_ID_N:-0}

if [ -f "$BASELINE" ]; then
  RS7_DIFF=0
  while IFS="$TAB" read -r _bn _id _verdict; do
    [ -n "$_bn" ] || continue
    _base=$(awk -F"$TAB" -v s="$_bn" -v i="$_id" '$1==s && $2==i {print $3; exit}' "$BASELINE")
    [ "$_base" = "$_verdict" ] || RS7_DIFF=$((RS7_DIFF + 1))
  done <"$RS_LIVE"
  if [ "$RS7_DIFF" -eq 0 ] && [ "$RS_ID_N" -gt 0 ]; then
    ok "RS7 (R-03, an EXACT per-item comparison — the frozen baseline, never a floor, ADR-0124 / CLAUDE.md rule 10): all $RS_ID_N live (spec, id) verdicts match spec-coverage-scope-baseline.tsv exactly"
  else
    bad "RS7: $RS7_DIFF of $RS_ID_N live (spec, id) verdict(s) diverge from the frozen baseline — R-03's corpus proof failed on a specific row"
  fi
else
  bad "RS7: $BASELINE does not exist yet (Task 6) — R-03's corpus proof has nothing to compare the $RS_ID_N live verdicts against"
fi

RS8A_ORPHAN=0
if [ -f "$BASELINE" ]; then
  while IFS="$TAB" read -r _bn _id _verdict; do
    [ -n "$_bn" ] || continue
    grep -q "^${_bn}${TAB}${_id}${TAB}" "$BASELINE" 2>/dev/null || RS8A_ORPHAN=$((RS8A_ORPHAN + 1))
  done <"$RS_LIVE"
  if [ "$RS8A_ORPHAN" -eq 0 ]; then
    ok "RS8a (CLAUDE.md rule 8, direction 1 of 2): every live (spec, id) verdict has a baseline row — no orphan on the LIVE side"
  else
    bad "RS8a: $RS8A_ORPHAN live (spec, id) verdict(s) have NO baseline row — the baseline is short some rows"
  fi
else
  bad "RS8a: $BASELINE does not exist yet (Task 6) — the live-side direction of the reverse check has no baseline to read against ($RS_ID_N live verdicts unmatched)"
fi

if [ -f "$BASELINE" ]; then
  RS8B_ORPHAN=0
  while IFS="$TAB" read -r _bn _id _v _class _reason; do
    [ -n "$_bn" ] || continue
    case "$_bn" in \#*) continue ;; esac
    grep -q "^${_bn}${TAB}${_id}${TAB}" "$RS_LIVE" 2>/dev/null || RS8B_ORPHAN=$((RS8B_ORPHAN + 1))
  done <"$BASELINE"
  if [ "$RS8B_ORPHAN" -eq 0 ]; then
    ok "RS8b (CLAUDE.md rule 8, direction 2 of 2): every baseline row has a live (spec, id) counterpart — no orphan on the BASELINE side"
  else
    bad "RS8b: $RS8B_ORPHAN baseline row(s) have NO live counterpart — a check validating a list's entries is blind to what the list omits, run backwards too"
  fi
else
  bad "RS8b: $BASELINE does not exist yet (Task 6) — the baseline-side direction of the reverse check has nothing to read"
fi

if [ "$RS_PAIR_N" -ge 15 ]; then
  ok "RS9a (denominator guard on the DERIVATION, CLAUDE.md rule 7 — a vacuity guard only, NOT R-03's proof; RS7's exact per-item comparison is where a plant bites, rule 10 / ADR-0124): the pairing resolved $RS_PAIR_N (spec, plan) pairs (>= 15). Measured 2026-08-14: 15."
else
  bad "RS9a: the pairing resolved only $RS_PAIR_N (spec, plan) pairs (< 15) — the DERIVATION is broken, not just short of coverage"
fi
if [ "$RS_ID_N" -ge 100 ]; then
  ok "RS9b (denominator guard on the derivation, same vacuity caveat as RS9a): $RS_ID_N paired ids resolved (>= 100). Measured 2026-08-14: 117."
else
  bad "RS9b: only $RS_ID_N paired ids resolved (< 100) — the derivation is broken, not just short of coverage"
fi

# ==================================================================================================
# RY10 (R-06, ADR-0154 D4, Task 4) — the back-reference derivation's own corpus denominator guard.
# A bug that made half 2 fail for every candidate file would collapse the scope on every pair, and
# without a guard here that reads as 187 changed baseline rows rather than as a collapse (rule 7).
#
# DECLARED A VACUITY GUARD, NOT THE EVIDENCE (rule 10, ADR-0124): a floor absorbs its own plant —
# >= 15 against 16 resolved pairs still passes when Task 7's plant removes one. RS7's frozen
# per-row baseline comparison, regenerated by Task 5, is where a total-collapse plant actually
# bites. RY10 is GREEN ON ARRIVAL (declared, ADR-0101 batch table) and stays green after Task 2 —
# it does not become evidence at any point in this feature's own batches.
# ==================================================================================================
# plant: RY10 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if grep -qE "$BACKREF_RE" "$_f" 2>/dev/null; then | if false; then
RY10_N=$(awk -F"$TAB" '$2==0 && $3+0>0 {c++} END{print c+0}' "$RS_SCOPE" 2>/dev/null); RY10_N=${RY10_N:-0}
if [ "$RY10_N" -ge 15 ]; then
  ok "RY10 (R-06, vacuity guard — see the disclosure above, not the proof): $RY10_N of $RS_PAIR_N resolved (SPEC, plan) pairs run without SCOPE-NO-BACKREF and with a non-empty scope (>= 15). Measured 2026-08-18: 16 pairs resolve."
else
  bad "RY10: only $RY10_N of $RS_PAIR_N resolved pairs run without SCOPE-NO-BACKREF and with a non-empty scope (< 15) — the back-reference derivation has stopped resolving across the corpus"
fi

cat >"$TMP/rs10.spec.md" <<'EOF'
## Success criteria
- [ ] Some criterion with no id at all.
EOF
: >"$TMP/rs10-plan.md"
mkdir -p "$TMP/rs10-tests"
cat >"$TMP/rs10-tests/whatever.test.sh" <<'EOF'
# nothing relevant, and even mentions SCOPE-EMPTY and UNSCOPED as literal words to prove neither leaks
EOF
run_scov --spec "$TMP/rs10.spec.md" --plan "$TMP/rs10-plan.md" --tests-root "$TMP/rs10-tests"
rs10_rc_ok=0; rs10_out_ok=0; rs10_err_ok=0
[ "$RC" -eq 0 ] && rs10_rc_ok=1
[ -z "$OUT" ] && rs10_out_ok=1
[ -z "$ERR" ] && rs10_err_ok=1
if [ "$rs10_rc_ok" -eq 1 ] && [ "$rs10_out_ok" -eq 1 ] && [ "$rs10_err_ok" -eq 1 ]; then
  ok "RS10 (forward guard): a zero-id SPEC invoked WITH --tests-root still takes the silent path — exit 0, empty stdout, empty stderr, all three asserted separately — the scope filter and SCOPE-EMPTY are unreachable behind DECL_N==0 by construction"
else
  bad "RS10: expected the silent path even with --tests-root present — got rc_ok=$rs10_rc_ok out_ok=$rs10_out_ok err_ok=$rs10_err_ok (rc=$RC out=[$OUT] err=[$ERR])"
fi

# ==================================================================================================
# RX. Issue #312 / ADR-0138 D4 — the `no-test:` exemption (test axis ONLY, never the plan axis),
# its 20-character reason floor, and the stale-waiver reverse check (CLAUDE.md rule 9). Written here
# in Task 1's file BEFORE Task 5 implements the mechanism (the plan's own words) — every one of
# RX1-RX6 is expected RED until Task 5 lands in Batch C. Verified empirically below.
# ==================================================================================================
# plant: RX1 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if (match(low, /\(no-test:/)) { | if (match(low, /\(no-test-disabled-by-plant:/)) {
cat >"$TMP/rx1.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — a documentation obligation. (no-test: a documentation obligation, nothing executable to assert)
EOF
cat >"$TMP/rx1-plan.md" <<'EOF'
### Task 1 — record it (R-01)
EOF
mkdir -p "$TMP/rx1-tests"
cat >"$TMP/rx1-tests/whatever.test.sh" <<'EOF'
# no ids mentioned
EOF
run_scov --spec "$TMP/rx1.spec.md" --plan "$TMP/rx1-plan.md" --tests-root "$TMP/rx1-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$"; then
  ok "RX1 (D4): a (no-test: ...) marker exempts R-01 from the test axis ENTIRELY — COVERED, exit 0, even though zero discovered test files mention it"
else
  bad "RX1: expected exit 0 + COVERED R-01 for a no-test-exempt id with plan coverage and zero test mentions — got rc=$RC out=[$OUT]"
fi

: >"$TMP/rx2-plan.md"
run_scov --spec "$TMP/rx1.spec.md" --plan "$TMP/rx2-plan.md" --tests-root "$TMP/rx1-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNCOVERED${TAB}R-01${TAB}plan\$"; then
  ok "RX2: the no-test: exemption NEVER touches the plan axis — with no plan citation, R-01 is still UNCOVERED, third field exactly plan (never plan,tests), exit 1"
else
  bad "RX2: expected UNCOVERED R-01 plan / exit 1 even with the no-test: marker present — got rc=$RC out=[$OUT]"
fi

cat >"$TMP/rx3.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — a documentation obligation. **(NO-TEST: a documentation obligation, nothing to assert)**
EOF
run_scov --spec "$TMP/rx3.spec.md" --plan "$TMP/rx1-plan.md" --tests-root "$TMP/rx1-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$"; then
  ok "RX3 (CLAUDE.md rule 3): a BOLD, UPPERCASE (NO-TEST: ...) marker is recognised identically to the plain lowercase form — matched on a flattened, undecorated, case-insensitive copy"
else
  bad "RX3: expected exit 0 + COVERED R-01 for a bold/uppercase no-test: marker — got rc=$RC out=[$OUT]"
fi

# plant: RX4 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | notest_ok = (length(reason) >= 20) | notest_ok = 1
cat >"$TMP/rx4.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — too short. (no-test: short)
EOF
run_scov --spec "$TMP/rx4.spec.md" --plan "$TMP/rx1-plan.md"
if [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q "^MALFORMED${TAB}R-01\$"; then
  ok "RX4: a no-test: reason under the 20-character floor ('short', 5 chars) is MALFORMED, exit 3"
else
  bad "RX4: expected exit 3 + MALFORMED R-01 for a 5-char no-test: reason — got rc=$RC out=[$OUT]"
fi

# plant: RX5 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if [ -n "$TROOT" ] && grep -qxF "$id" "$COVERED_IDS" 2>/dev/null; then | if [ -n "$TROOT" ] && false && grep -qxF "$id" "$COVERED_IDS" 2>/dev/null; then
# plant: RH1 | plugin/skills/interview-driver/SKILL.md | ## Success criteria | ## Criteri di successo
cat >"$TMP/rx5.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — allegedly not testable. (no-test: a documentation obligation, nothing executable to assert)
EOF
cat >"$TMP/rx5-plan.md" <<'EOF'
### Task 1 — record it (R-01)
Test coverage lives in stale.test.sh.
EOF
mkdir -p "$TMP/rx5-tests"
# ADR-0154 fixture amendment (Batch C Task 4, operator-authorised — see the plan's Work Item 1):
# stale.test.sh now names the plan back (rx5-plan.md) so Task 2's half 2 admits it. RX5's own
# predicate and its expected STALE-WAIVER R-01 / exit-3 / stderr-naming-delete outcome below are
# UNCHANGED — RX5's INTENT is the reverse check on the (no-test: ...) waiver (CLAUDE.md rule 9),
# which requires R-01 to actually be found IN SCOPE; without a back-reference stale.test.sh is
# dropped by half 2, the scope collapses to zero, the waiver is never found stale, and the run
# silently reads COVERED R-01 / exit 0 instead.
cat >"$TMP/rx5-tests/stale.test.sh" <<'EOF'
# covers R-01
# names the plan back: rx5-plan.md
EOF
run_scov --spec "$TMP/rx5.spec.md" --plan "$TMP/rx5-plan.md" --tests-root "$TMP/rx5-tests"
if [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -q "^STALE-WAIVER${TAB}R-01\$" \
   && printf '%s\n' "$ERR" | grep -qi 'delete'; then
  ok "RX5 (CLAUDE.md rule 9, the reverse check): a no-test: id whose token IS found in the scoped test set is a stale waiver — STALE-WAIVER R-01, exit 3, stderr names the remedy (delete the clause); NOT auto-repaired (ADR-0072's self-repair does not extend here)"
else
  bad "RX5: expected exit 3 + STALE-WAIVER R-01 + stderr naming 'delete' when the exempted id IS covered by an in-scope test — got rc=$RC out=[$OUT] err=[$ERR]"
fi

# ADR-0154 fixture amendment note (Batch C Task 4, operator-authorised — see the plan's Work Item
# 1): RX6 reruns the RS1 tree (rs1.spec.md / rs1-plan.md / rs1-tests), whose alpha.test.sh was
# amended above (in the RS1 block) to add a back-reference to rs1-plan.md. RX6's own predicate and
# its expected UNSCOPED R-01 1 outcome below are UNCHANGED — the same repair that restores RS1
# restores this one, since both read the identical fixture tree; no separate edit was made here.
run_scov --spec "$TMP/rs1.spec.md" --plan "$TMP/rs1-plan.md" --tests-root "$TMP/rs1-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RX6 (negative twin of RX1-RX5, CLAUDE.md rule 8): the RS1 fixture, carrying NO (no-test: ...) marker at all, still reads UNSCOPED as normal — the no-test: code path does not swallow the ordinary scope verdict when no marker is present"
else
  bad "RX6: expected the plain UNSCOPED R-01 1 verdict from the marker-less RS1 fixture — got rc=$RC out=[$OUT]"
fi

# ==================================================================================================
# RY. ADR-0154 (plan: docs/superpowers/plans/2026-08-18-spec-coverage-scope-back-reference.md) — the
# test axis becomes a conjunction: a discovered test file enters scope only when the plan names it
# (half 1, unchanged) AND its own text names the plan's basename or one of the ADR-NNNN ids the plan
# cites (half 2, new). RY1-RY9 and RY12 are EXPECTED RED until Tasks 2/3/6 land (Batches B/D) — the
# conjunction does not exist yet, so today's checker still scopes on half 1 alone. RY7, RY8 and RY9
# are POSITIVE CONTROLS / already-true invariants (CLAUDE.md rule 8's negative-twin discipline
# applied to a state that does not change): verified empirically below against the pre-fix checker,
# each already reads the way this ADR requires, because it exercises a path half 2 does not touch —
# SCOPE-EMPTY is unchanged (D2), the .md exclusion runs upstream of both halves (D1), and half 1's
# own requirement ("the plan must name the file") was never in question. They stay in this section
# because R-01/R-04/R-05 name them as the guards that prove half 2 did not regress what half 1
# already guaranteed — the same reasoning RS2-RS5 documented for the first scope filter. RY11 is
# GREEN ON ARRIVAL: ADR-0154 already exists and already carries both measurements. Every fixture
# below was executed against the unmodified checker before this comment was written (rule 2).
#
# R-07 IS EVIDENCED IN THIS FILE BUT ITS SUBJECT IS NOT A TEST FILE, which is why the id is named
# here and nowhere else in scope. R-07 asserts that spec-coverage-scope-baseline.tsv is regenerated
# under the new rule and that every row whose verdict changes is accounted for. That .tsv is not a
# discovered test file by construction, so the citation has nowhere else to live. The evidence:
# the baseline was regenerated on 2026-08-18 (dated header block in that file, 0 of 130 rows
# changed verdict) and is compared row by row by RS7/RS8a/RS8b above, all green.
# Added by the orchestrator at the Step 5 exit gate, which reported UNSCOPED for R-07 — the id was
# mentioned only in three foreign harnesses, each carrying an unrelated R-07 of its own. Under the
# pre-ADR-0154 rule one of those would have reported COVERED. This feature caught its own citation
# gap with its own rule, one batch after shipping it.
# ==================================================================================================
# plant: RY1 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if grep -qE "$BACKREF_RE" "$_f" 2>/dev/null; then | if :; then
cat >"$TMP/ry1.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF

cat >"$TMP/ry1-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in alpha.test.sh and beta.test.sh.
EOF
mkdir -p "$TMP/ry1-tests"
cat >"$TMP/ry1-tests/alpha.test.sh" <<'EOF'
# names the plan back: ry1-plan.md
EOF
cat >"$TMP/ry1-tests/beta.test.sh" <<'EOF'
# covers R-01
EOF
run_scov --spec "$TMP/ry1.spec.md" --plan "$TMP/ry1-plan.md" --tests-root "$TMP/ry1-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RY1 (R-01, R-03, ADR-0154 D1): the plan names TWO discovered harnesses; alpha.test.sh names the plan back and carries no id, beta.test.sh carries R-01 and names nothing back — R-01's only mention is dropped by half 2, final scope is {alpha.test.sh} (1 file) -> UNSCOPED	R-01	1, exit 1. The two-file shape is load-bearing: a one-file tree would take the SCOPE-EMPTY path instead (RY7) and prove something else. Today (pre-fix, verified) this exact fixture is COVERED, exit 0."
else
  bad "RY1: expected exit 1 + UNSCOPED R-01 1 (beta dropped by half 2, alpha carries no id) — got rc=$RC out=[$OUT]"
fi

# plant: RY2 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | BACKREF_KEYS="$PLAN_BN_ESC" | BACKREF_KEYS="RY2_PLANT_NO_MATCH_ZZZ"
mkdir -p "$TMP/ry2-tests"
cat >"$TMP/ry2-tests/alpha.test.sh" <<'EOF'
# names the plan back: ry1-plan.md
EOF
cat >"$TMP/ry2-tests/beta.test.sh" <<'EOF'
# covers R-01
# names the plan back: ry1-plan.md
EOF
run_scov --spec "$TMP/ry1.spec.md" --plan "$TMP/ry1-plan.md" --tests-root "$TMP/ry2-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$" \
   && ! printf '%s\n' "$OUT" | grep -q 'UNSCOPED'; then
  ok "RY2 (R-01, R-02, positive twin of RY1, CLAUDE.md rule 8): the same tree with beta.test.sh ALSO naming the plan's basename (with its .md) back -> COVERED, exit 0, no UNSCOPED line. Without this twin, RY1 is satisfiable by a checker that fails every file regardless of what it names."
else
  bad "RY2: expected COVERED R-01 / exit 0 / no UNSCOPED line once beta names the plan back — got rc=$RC out=[$OUT]"
fi

# plant: RY3 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | BACKREF_KEYS="$PLAN_BN_ESC" if [ -s "$BACKREF_ADRS_UNIQ" ]; then | BACKREF_KEYS="$PLAN_BN_ESC"\nif false; then
cat >"$TMP/ry3-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in alpha.test.sh and beta.test.sh. See ADR-9001 for background.
EOF
mkdir -p "$TMP/ry3-tests"
cat >"$TMP/ry3-tests/alpha.test.sh" <<'EOF'
# names the plan back: ry3-plan.md
EOF
cat >"$TMP/ry3-tests/beta.test.sh" <<'EOF'
# covers R-01
# see ADR-9001
EOF
run_scov --spec "$TMP/ry1.spec.md" --plan "$TMP/ry3-plan.md" --tests-root "$TMP/ry3-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$"; then
  ok "RY3 (R-02, the OR's second branch, ADR-0154 D1): beta.test.sh names an ADR-NNNN the plan cites (ADR-9001) and NOT the plan's basename -> COVERED, exit 0. The back-reference key set is the plan basename OR any ADR id the plan cites, not the basename alone."
else
  bad "RY3: expected COVERED R-01 / exit 0 via the ADR branch of the OR — got rc=$RC out=[$OUT]"
fi

# plant: RY4 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | BACKREF_RE="(^|[^A-Za-z0-9_])(${BACKREF_KEYS})([^A-Za-z0-9_]|\$)" | BACKREF_RE="(^|[^A-Za-z0-9_])(${BACKREF_KEYS}|ADR-[0-9][0-9][0-9][0-9])([^A-Za-z0-9_]|\$)"
# Deviation from the Task 7 table (validated 2026-08-18, plant-check.sh --worker): the table paired
# RY3 and RY4 under one mutation ("drop the ADR ids from the key set"). That mutation reddens RY3
# but NOFIREs on RY4 — dropping the ADR branch entirely leaves ADR-9002 unmatched exactly as before
# (it was never in the cited set either way), so RY4's own verdict does not move. What RY4 actually
# pins is the OTHER failure mode its own comment names ("a rule that accepts any ADR id at all, not
# one this plan actually cites") — a promiscuous match, planted above by widening BACKREF_RE to
# accept any ADR-dddd token regardless of $BACKREF_ADRS_UNIQ.
mkdir -p "$TMP/ry4-tests"
cat >"$TMP/ry4-tests/alpha.test.sh" <<'EOF'
# names the plan back: ry3-plan.md
EOF
cat >"$TMP/ry4-tests/beta.test.sh" <<'EOF'
# covers R-01
# see ADR-9002
EOF
run_scov --spec "$TMP/ry1.spec.md" --plan "$TMP/ry3-plan.md" --tests-root "$TMP/ry4-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RY4 (R-02, negative twin of RY3): beta.test.sh names an ADR-NNNN the plan does NOT cite (ADR-9002, the plan cites only ADR-9001) -> dropped by half 2, final scope is {alpha.test.sh} -> UNSCOPED	R-01	1, exit 1. Without this twin, RY3 is satisfied by a rule that accepts any ADR id at all, not one this plan actually cites."
else
  bad "RY4: expected exit 1 + UNSCOPED R-01 1 (beta's ADR is not in this plan's key set) — got rc=$RC out=[$OUT]"
fi

# plant: RY5 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | PLAN_BN="${PLAN##*/}" | PLAN_BN="${PLAN##*/}"\nPLAN_BN="${PLAN_BN%.md}"
mkdir -p "$TMP/ry5-tests"
cat >"$TMP/ry5-tests/alpha.test.sh" <<'EOF'
# names the plan back: ry1-plan.md
EOF
cat >"$TMP/ry5-tests/beta.test.sh" <<'EOF'
# covers R-01
# see ry1-plan.manifest.yml
EOF
run_scov --spec "$TMP/ry1.spec.md" --plan "$TMP/ry1-plan.md" --tests-root "$TMP/ry5-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RY5 (R-02, whole-token, ADR-0154 SA3): beta.test.sh names only ry1-plan.manifest.yml, the plan's STEM plus a different extension, never the plan's own basename ry1-plan.md -> not a back-reference -> dropped by half 2 -> UNSCOPED	R-01	1, exit 1. Pins the escaping and the anchor pair, and pins the refusal of a stem-only match — the rejected A3 alternative would have let this fixture COVER (stem plus non-word boundary is not a token boundary under that anchor pair)."
else
  bad "RY5: expected exit 1 + UNSCOPED R-01 1 (stem-only mention does not back-reference) — got rc=$RC out=[$OUT]"
fi

# ==================================================================================================
# RY6/RY7. ADR-0154 D2 — an empty scope now has two causes, told apart. RY6 is the new
# SCOPE-NO-BACKREF state (half 1 non-empty, half 2 drops everything — a finding, no fallback). RY7
# is the unchanged SCOPE-EMPTY state (half 1 empty — a possibly-broken derivation, falls back). Both
# are asserted on the SAME kind of tree (one discovered file, one declared id) so only the plan's
# naming differs between them — that is what "told apart" means.
# ==================================================================================================
# RY6a/RY6b/RY6c/RY6d genuinely share one mutation (validated 2026-08-18, plant-check.sh --worker):
# forcing the HALF1_N>0 branch closed collapses the whole D2 split for this fixture at once — no
# SCOPE-NO-BACKREF, no named dropped file, SCOPE-EMPTY appears instead, and the fallback restores
# COVERED — so all four sub-assertions about that one state transition go red together. Declared
# once per id rather than de-duplicated (rule 2 is per-assertion).
# plant: RY6a | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if [ "$HALF1_N" -gt 0 ]; then | if false; then
# plant: RY6b | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if [ "$HALF1_N" -gt 0 ]; then | if false; then
# plant: RY6c | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if [ "$HALF1_N" -gt 0 ]; then | if false; then
# plant: RY6d | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if [ "$HALF1_N" -gt 0 ]; then | if false; then
cat >"$TMP/ry6-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in delta.test.sh.
EOF
mkdir -p "$TMP/ry6-tests"
cat >"$TMP/ry6-tests/delta.test.sh" <<'EOF'
# covers R-01
EOF
run_scov --spec "$TMP/ry1.spec.md" --plan "$TMP/ry6-plan.md" --tests-root "$TMP/ry6-tests"
printf '%s\n' "$ERR" | grep -q 'SCOPE-NO-BACKREF' \
  && ok "RY6a (R-05, ADR-0154 D2): stderr contains SCOPE-NO-BACKREF — the plan names exactly one discovered harness (delta.test.sh, half 1 count 1 > 0) and it names nothing back" \
  || bad "RY6a: stderr does not contain SCOPE-NO-BACKREF — err=[$ERR]"
printf '%s\n' "$ERR" | grep -q 'delta.test.sh' \
  && ok "RY6b: stderr names the dropped file's basename (delta.test.sh) — the remedy must say what to fix" \
  || bad "RY6b: stderr does not name delta.test.sh — err=[$ERR]"
printf '%s\n' "$ERR" | grep -q 'SCOPE-EMPTY' \
  && bad "RY6c: stderr contains SCOPE-EMPTY — the two empty-scope causes must not share a token, or a caller cannot branch on which one fired" \
  || ok "RY6c: stderr does NOT contain SCOPE-EMPTY — the two states are told apart on the wire"
[ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}0\$" \
  && ok "RY6d: stdout is UNSCOPED	R-01	0, exit 1 — no fallback, the id mentioned only in the dropped file reports the ordinary per-id verdict" \
  || bad "RY6d: expected UNSCOPED R-01 0 / exit 1 — got rc=$RC out=[$OUT]"

# plant: RY7 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if [ "$HALF1_N" -gt 0 ]; then | if :; then
cat >"$TMP/ry7-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
No test file is named anywhere in this plan's prose.
EOF
mkdir -p "$TMP/ry7-tests"
cat >"$TMP/ry7-tests/epsilon.test.sh" <<'EOF'
# covers R-01
EOF
run_scov --spec "$TMP/ry1.spec.md" --plan "$TMP/ry7-plan.md" --tests-root "$TMP/ry7-tests"
ry7_no_backref=1
printf '%s\n' "$ERR" | grep -q 'SCOPE-NO-BACKREF' && ry7_no_backref=0
if [ "$RC" -eq 0 ] && printf '%s\n' "$ERR" | grep -q 'SCOPE-EMPTY' \
   && [ "$ry7_no_backref" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$"; then
  ok "RY7 (R-05, the other direction, twin of RS6/D2, positive control — this state is UNCHANGED by ADR-0154 and already reads this way pre-fix): the plan names NO discovered test file at all -> stderr SCOPE-EMPTY, never SCOPE-NO-BACKREF, stdout falls back to COVERED	R-01, exit 0. Together with RY6 this is what 'told apart' means: same one-file/one-id shape, opposite plan-naming, opposite stderr token, opposite fallback behaviour."
else
  bad "RY7: expected stderr SCOPE-EMPTY (never SCOPE-NO-BACKREF) + stdout COVERED R-01 (fallback) + exit 0 — got rc=$RC out=[$OUT] err=[$ERR]"
fi

# forward guard, positive control (unaffected by ADR-0154 — the .md exclusion runs upstream of both
# scope halves, RS5's own point, extended here to prove half 2 cannot re-admit what the exclusion
# already dropped even when the .md file back-references the plan).
# Deviation from the Task 7 table (validated 2026-08-18, plant-check.sh --worker): the table named
# "neutralise the .md exclusion" (the second, explicit gate) as RY8's mutation. NOFIREs alone —
# x.spec.md never reaches that gate: it fails the FIRST gate (the CANDIDATES basename allowlist,
# which lists *.spec.js/.ts/.tsx/.jsx but no *.spec.md) and so is never a candidate the explicit
# .md filter has to reject. The honest plant widens the first gate to admit everything AND
# neutralises the second in the same mutation — the only combination that actually lets a .md
# candidate survive to $TESTFILES for this fixture.
# plant: RY8 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | *.test.*|test_*|*_test.*|*Test.*|*Tests.*|test-*.sh|run-tests.sh|*.spec.js|*.spec.ts|*.spec.tsx|*.spec.jsx) printf '%s\n' "$f" ;; esac done >"$CANDIDATES" # Explicit .md exclusion — a separate step on purpose, not folded into the pattern list above. while IFS= read -r f; do case "$f" in *.md) continue ;; | *) printf '%s\\n' "$f" ;; esac done >"$CANDIDATES" # Explicit .md exclusion — a separate step on purpose, not folded into the pattern list above. while IFS= read -r f; do case "$f" in *.md_RY8_NEVER_MATCH) continue ;;
mkdir -p "$TMP/ry8-tests/docs/specs"
cat >"$TMP/ry8-tests/docs/specs/x.spec.md" <<'EOF'
Mentions R-01 in prose, and names the plan back: ry8-plan.md
EOF
cat >"$TMP/ry8-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Background: docs/specs/x.spec.md (also known as x.spec.md).
EOF
run_scov --spec "$TMP/ry1.spec.md" --plan "$TMP/ry8-plan.md" --tests-root "$TMP/ry8-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNCOVERED${TAB}R-01${TAB}tests\$"; then
  ok "RY8 (R-04, forward guard): a .md file that names the plan back AND whose basename the plan names is still excluded -> UNCOVERED	R-01	tests. Half 2 cannot re-admit a .md; the exclusion is upstream of \$TESTFILES entirely (ADR-0154 D1). Already true pre-fix — a positive control, not new-behaviour evidence."
else
  bad "RY8: expected UNCOVERED R-01 tests despite the .md file naming the plan back — got rc=$RC out=[$OUT]"
fi

# forward guard, positive control: the other half of "either half alone is not enough" — a file
# cannot buy its way into scope purely by back-referencing when the plan never names it.
# Deviation from the Task 7 table (dispatch correction, confirmed 2026-08-18, plant-check.sh
# --worker): the table paired RY9 with RY1 under the half-2 mutation. RY9's own fixture never
# reaches half 2 — the plan never names zeta.test.sh's basename, so half 1 rejects it outright and
# a half-2 mutation is a NOFIRE by construction. RY9 needs half 1 itself neutralised instead.
# plant: RY9 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if grep -qE "(^|[^A-Za-z0-9_])${_esc}([^A-Za-z0-9_]|\$)" "$PLAN" 2>/dev/null; then | if :; then
mkdir -p "$TMP/ry9-tests"
cat >"$TMP/ry9-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in alpha.test.sh.
EOF
cat >"$TMP/ry9-tests/alpha.test.sh" <<'EOF'
# names the plan back: ry9-plan.md
EOF
cat >"$TMP/ry9-tests/zeta.test.sh" <<'EOF'
# covers R-01
# names the plan back: ry9-plan.md
EOF
run_scov --spec "$TMP/ry1.spec.md" --plan "$TMP/ry9-plan.md" --tests-root "$TMP/ry9-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RY9 (R-01, forward guard, the other half of 'either half alone is not enough'): zeta.test.sh names the plan back and carries R-01, but the plan never names zeta.test.sh's own basename -> half 1 rejects it outright, half 2 is never reached -> UNSCOPED	R-01	1, exit 1. Already true pre-fix (half 1 is unchanged) — a positive control proving back-reference alone cannot substitute for half 1."
else
  bad "RY9: expected exit 1 + UNSCOPED R-01 1 (zeta excluded by half 1 regardless of its back-reference) — got rc=$RC out=[$OUT]"
fi

# ==================================================================================================
# RY11. GREEN ON ARRIVAL, declared (ADR-0101 batch table) — not a defect. ADR-0154 already exists
# and already records both refused-design measurements and the instruction-vs-enforcement clause.
# Matched on a flattened, undecorated, case-insensitive copy (CLAUDE.md rule 3); the D6 window is
# scoped to that one section so the instruction/enforcement needle cannot be satisfied by unrelated
# prose elsewhere in the ADR (rule 1).
# ==================================================================================================
# Deviation from the Task 7 table (dispatch correction, confirmed 2026-08-18, plant-check.sh
# --worker): the table names one plant ("remove one of the two refused-design measurements") for
# the whole of RY11. RY11a/b/c each assert something different and one shared mutation cannot
# redden all three: RY11a is a bare existence check with no content-level failure mode at all — a
# plant can only mutate file CONTENT, never delete or rename a file, so it is planted here by
# SELF-TARGETING this harness's own $RY_ADR assignment instead (a supported class, ADR-0149's
# masking exists precisely so a declaration does not match itself). RY11b and RY11c each get their
# own mutation against the ADR: RY11b loses one of its two required measurements, RY11c loses the
# instruction-vs-enforcement phrase inside the D6 window RY11c actually reads.
# plant: RY11a | plugin/scripts/tests/spec-coverage.test.sh | RY_ADR="$REPO/docs/architecture/ADR-0154-spec-coverage-scope-back-reference.md" | RY_ADR="$REPO/docs/architecture/ADR-0154-DOES-NOT-EXIST-RY11a.md"
RY_ADR="$REPO/docs/architecture/ADR-0154-spec-coverage-scope-back-reference.md"
if [ -f "$RY_ADR" ]; then
  ok "RY11a: $RY_ADR exists and is readable — RY11b/RY11c are meaningful"
else
  bad "RY11a: $RY_ADR not found — RY11b/RY11c are vacuous"
fi
RY_D6=$(awk '/^### D6 /{grab=1} /^### D7 /{grab=0} grab' "$RY_ADR" 2>/dev/null | tr -d '`*' | tr '\n' ' ' | tr -s ' ')
# plant: RY11b | ../docs/architecture/ADR-0154-spec-coverage-scope-back-reference.md | 11 of 53 | ELEVEN-OF-FIFTY-THREE-REMOVED-RY11b
if grep -qi '11 of 53' "$RY_ADR" 2>/dev/null && grep -qi '87 of 893' "$RY_ADR" 2>/dev/null; then
  ok "RY11b (R-11): the ADR records both refused designs with the measurements that refused them — 11 of 53 plans name a test file in a Budget: line (A1), 87 of 893 R-NN mentions sit in an id-mapping comment header (A2)"
else
  bad "RY11b: the ADR is missing one or both refused-design measurements (11 of 53 / 87 of 893)"
fi
# plant: RY11c | ../docs/architecture/ADR-0154-spec-coverage-scope-back-reference.md | instruction, not an enforcement | a plain sentence with no special status
if printf '%s\n' "$RY_D6" | grep -qi 'architect.md' && printf '%s\n' "$RY_D6" | grep -qi 'instruction, not an enforcement'; then
  ok "RY11c (R-12): D6 states, in the same section naming architect.md's contract line, that it is an instruction and not an enforcement (rule 16) — what is enforced is the consequence at the gate"
else
  bad "RY11c: D6 does not name architect.md's contract line as an instruction rather than an enforcement — flat=[$RY_D6]"
fi

# ==================================================================================================
# RY12. RED until Task 6 (Batch D) — the record: a docs/chain-decisions.md heading naming ADR-0154,
# a docs/chain-decision-index.md line naming it, and a PROJECT.md row naming it. Verified
# 2026-08-18: the ADR-authoring step already wrote the first two; the PROJECT.md row is Task 6's own
# deliverable, so this assertion is red on that one leg alone until it lands.
# ==================================================================================================
# plant: RY12 | ../docs/chain-decision-index.md | - **ADR-0154**
# plant: RY12 | ../docs/chain-decisions.md | ## Decisions from the spec-coverage-scope-back-reference chain (ADR-0154) | ## Decisions from the spec-coverage-scope-back-reference chain (renamed, no ADR ref)
RY_CD="$REPO/docs/chain-decisions.md"
RY_CLMD="$REPO/docs/chain-decision-index.md"
RY_PROJ="$REPO/PROJECT.md"
ry12_cd=0; ry12_cl=0; ry12_pj=0
grep -qE '^## .*ADR-0154' "$RY_CD" 2>/dev/null && ry12_cd=1
grep -qE '^\- \*\*ADR-0154\*\*' "$RY_CLMD" 2>/dev/null && ry12_cl=1
grep -qF 'ADR-0154' "$RY_PROJ" 2>/dev/null && ry12_pj=1
if [ "$ry12_cd" -eq 1 ] && [ "$ry12_cl" -eq 1 ] && [ "$ry12_pj" -eq 1 ]; then
  ok "RY12 (R-10): the record is written — a docs/chain-decisions.md heading naming ADR-0154, a docs/chain-decision-index.md line naming it, and a PROJECT.md row naming it, all three present"
else
  bad "RY12: the record is incomplete (chain-decisions.md heading=$ry12_cd, chain-decision-index.md line=$ry12_cl, PROJECT.md row=$ry12_pj) — Task 6 has not landed yet"
fi

# ==================================================================================================
# RH. The two SPEC GENERATORS still emit a heading this checker recognises (issue #313, ADR-0144).
#
# Measured 2026-08-16 by instrumenting the checker and running it over all 78 `docs/specs/*.spec.md`:
# the population of ids sitting outside every recognised section is EMPTY, in both branches — the
# `DECL_N == 0` one that already reports MALFORMED and the mixed one that is dropped in silence by
# the deliberate ADR-0072 §D5 asymmetry. So the defect #313 describes has no instances.
#
# It has none for a reason that can stop being true in one edit: all 78 spell `## Success criteria`
# identically because two generator templates emit it, and 75 of the 78 are generator-produced.
# Closing that issue on "no instances" alone would leave an exemption whose subject nobody
# re-checks — rule 9 — so this is the reverse check.
#
# The recognised set is DERIVED by running the predicate itself, never restated here: a copy of the
# heading list in this file would pass while the checker's own rule drifted away from it, which is
# the failure this assertion exists to prevent, one level up.
# ==================================================================================================
# Both predicate files, in the order the checker itself loads them at spec-coverage.sh:229 —
# is_spec_section_heading() calls heading_level(), which lives in the other one. Loading only the
# spec predicate produces "calling undefined function", which this probe reports as unreadable
# rather than as a heading that is not recognised: rule 4, on the instrument.
RH_PRED0="$STAGING/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk"
RH_PRED="$STAGING/plugin/skills/concept-to-code/scripts/spec-id-predicate.awk"
cat >"$TMP/rh-probe.awk" <<'RHEOF'
{ if (is_spec_section_heading($0)) n++ }
END { print n + 0 }
RHEOF
RH_MISSING=""; RH_SEEN=0
for _rh in interview-driver spec-from-issue; do
  _rhf="$STAGING/plugin/skills/$_rh/SKILL.md"
  if [ ! -f "$_rhf" ]; then RH_MISSING="$RH_MISSING $_rh(absent)"; continue; fi
  _rhn=$(awk -f "$RH_PRED0" -f "$RH_PRED" -f "$TMP/rh-probe.awk" "$_rhf" 2>/dev/null)
  case "${_rhn:-x}" in
    ''|*[!0-9]*) RH_MISSING="$RH_MISSING $_rh(probe-unreadable)" ;;
    0)           RH_MISSING="$RH_MISSING $_rh(emits-no-recognised-heading)" ;;
    *)           RH_SEEN=$((RH_SEEN + 1)) ;;
  esac
done
if [ -z "$RH_MISSING" ] && [ "$RH_SEEN" -eq 2 ]; then
  ok "RH1: both SPEC generators emit a heading spec-id-predicate.awk recognises, so a generated SPEC cannot land its criteria outside the checker's reach"
else
  bad "RH1: a SPEC generator no longer emits a recognised heading —$RH_MISSING (probed $RH_SEEN of 2) — every id it writes would be silently unread (issue #313)"
fi

# ==================================================================================================
# RZ. ADR-0157 / issue #487 — the cross-feature id collision. Requirement ids restart at R-01 in every
# SPEC, so the question "is this id mentioned in the discovered test population?" is satisfied by a
# STRANGER'S file, and the answer arrives as UNSCOPED ("name the file in your plan") on an id that was
# never tested. Measured in the field on a Swift project; measured again on this repository's own
# corpus, where 12 of 24 UNSCOPED rows were foreign matches (see spec-coverage-scope-baseline.tsv's
# 2026-08-19 accounting block).
#
# Every fixture below was executed against the checker BEFORE the fix and produced the OLD verdict
# (CLAUDE.md rule 2). The plants pin the three predicates that make up the population.
# ==================================================================================================
mkdir -p "$TMP/rz1-tests"
cat >"$TMP/rz1.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rz1-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Test coverage lives in alpha.test.sh.
EOF
cat >"$TMP/rz1-tests/alpha.test.sh" <<'EOF'
# no id here
# names the plan back: rz1-plan.md
EOF
# The foreign harness: it carries R-01 and it says whose R-01 it is.
cat >"$TMP/rz1-tests/beta.test.sh" <<'EOF'
# covers R-01 (issue #999)
EOF
# plant: RZ1 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | elif grep -qE "(^|[^A-Za-z0-9_])#[0-9][0-9]*([^0-9]|\$)" "$_f" 2>/dev/null; then | elif false; then
run_scov --spec "$TMP/rz1.spec.md" --plan "$TMP/rz1-plan.md" --tests-root "$TMP/rz1-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNCOVERED${TAB}R-01${TAB}tests\$"; then
  ok "RZ1 (ADR-0157 D1): R-01's only mention is in beta.test.sh, which the plan does not name and which claims ANOTHER feature (#999) — UNCOVERED	R-01	tests, exit 1. Pre-fix this exact fixture reported UNSCOPED R-01 1, whose remedy tells the author to cite a stranger's harness from their plan."
else
  bad "RZ1: expected exit 1 + UNCOVERED R-01 tests (a foreign-claimed mention is not this feature's coverage) — got rc=$RC out=[$OUT]"
fi

# RZ2 — the positive twin (CLAUDE.md rule 8). Same tree, same non-named file, but now it claims THIS
# feature: the id is in the population again and the verdict returns to UNSCOPED. Without this twin,
# RZ1 is satisfiable by a checker that reports UNCOVERED for every out-of-scope mention.
mkdir -p "$TMP/rz2-tests"
cp "$TMP/rz1.spec.md" "$TMP/rz2.spec.md"
cp "$TMP/rz1-plan.md" "$TMP/rz2-plan.md"
cp "$TMP/rz1-tests/alpha.test.sh" "$TMP/rz2-tests/alpha.test.sh"
sed -i.bak 's/rz1-plan\.md/rz2-plan.md/' "$TMP/rz2-tests/alpha.test.sh" && rm -f "$TMP/rz2-tests/alpha.test.sh.bak"
# The foreign claim is deliberate: without it this file is merely UNCLAIMED, and an unclaimed file is
# in the population anyway — so the assertion would pass with the ownership test deleted, which is a
# plant that fires on nothing (measured: RZ2's first form was a registry NOFIRE). With #999 present,
# membership rests on ownership alone, and ownership BEATS a foreign claim in the same file.
cat >"$TMP/rz2-tests/beta.test.sh" <<'EOF'
# covers R-01 — carried over from issue #999, now this feature's own harness, see rz2-plan.md
EOF
# plant: RZ2 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if grep -qE "$OWN_RE" "$_f" 2>/dev/null; then | if false; then
run_scov --spec "$TMP/rz2.spec.md" --plan "$TMP/rz2-plan.md" --tests-root "$TMP/rz2-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RZ2 (positive twin of RZ1, CLAUDE.md rule 8): the same out-of-scope file, carrying BOTH a foreign #999 and this feature's plan basename -> UNSCOPED	R-01	1, exit 1. Ownership wins over a foreign claim in the same file, and the remedy is the one that fits an unlisted test of one's own"
else
  bad "RZ2: expected exit 1 + UNSCOPED R-01 1 (an owned but unlisted test is in the population) — got rc=$RC out=[$OUT]"
fi

# RZ3 — half 1 wins on its own. The plan NAMES beta.test.sh, half 2 drops it (it names no feature
# back), and it claims another feature. Membership by half 1 is unconditional, so the verdict is
# UNSCOPED: the author is told to fix the citation in a file their own plan points at, never to write
# a test that already exists two lines from there.
mkdir -p "$TMP/rz3-tests"
cat >"$TMP/rz3.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rz3-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Test coverage lives in alpha.test.sh and beta.test.sh.
EOF
cat >"$TMP/rz3-tests/alpha.test.sh" <<'EOF'
# no id here
# names the plan back: rz3-plan.md
EOF
cat >"$TMP/rz3-tests/beta.test.sh" <<'EOF'
# covers R-01 (issue #999)
EOF
# plant: RZ3 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | printf '%s\n' "$_f" >>"$HALF1_FILES" | :
run_scov --spec "$TMP/rz3.spec.md" --plan "$TMP/rz3-plan.md" --tests-root "$TMP/rz3-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RZ3 (ADR-0157 D1, the union's other half): a file the PLAN names is in the unscoped-question population unconditionally — even dropped by half 2 and claiming another feature, R-01 reads UNSCOPED	R-01	1, not UNCOVERED"
else
  bad "RZ3: expected exit 1 + UNSCOPED R-01 1 (half-1 membership is unconditional) — got rc=$RC out=[$OUT]"
fi

# RZ4 — the false green ADR-0157 closes, and the one nobody reported. The plan names NO discovered
# test file, so ADR-0138's SCOPE-EMPTY fallback applies; every discovered file claims another feature.
# Falling back to the whole population credits a stranger's R-01 as COVERED, exit 0.
mkdir -p "$TMP/rz4-tests"
cat >"$TMP/rz4.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rz4-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
No test file is named anywhere in this plan.
EOF
# VCS-035: the file-level claim (#999, for FOREIGN_CLAIMED classification) and the R-01 mention are
# on SEPARATE lines on purpose. If R-01's own line carried "#999" too, the VCS-035 line filter added
# below would independently discard it, making RZ4's own plant (which bypasses SCOPE-FOREIGN-ONLY,
# not the line filter) fire on nothing — a defense-in-depth interaction, not a bug, but it would
# silently stop pinning what RZ4 exists to pin (measured: this exact split was needed to keep RZ4's
# plant live once VCS-035 landed).
cat >"$TMP/rz4-tests/beta.test.sh" <<'EOF'
# issue #999
# covers R-01
EOF
# RZ4 and RZ4b pin two different mechanisms and their plants say which. RZ4's verdict rests on the
# refusal branch actually REFUSING to fall back — its plant leaves the branch's own detection and
# message intact and appends the pre-fix `cat "$TESTFILES"` inside it, so the message still names the
# refusal while the fallback happens anyway and the false green returns. Measured (rule 2, twice):
# a plant on the ELIF CONDITION alone was a registry NOFIRE, because disabling it routes execution
# into the SCOPE-EMPTY else branch, whose own fallback reads $UNSCOPED_POP — empty in this fixture by
# construction — so the verdict stays UNCOVERED regardless. A plant on the unrelated
# `cat "$UNSCOPED_POP"` line inside that else branch was a second NOFIRE for the same reason: this
# fixture's execution never reaches it. RZ4b's plant disables the elif condition itself, which IS the
# right mutation for "does this state get detected at all" — a different question from RZ4's.
# plant: RZ4 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | "$SELF" "$FOREIGN_CLAIMED_N" "$TROOT" >&2 | "$SELF" "$FOREIGN_CLAIMED_N" "$TROOT" >&2\n      cat "$TESTFILES" >"$TESTFILES_SCOPED"
run_scov --spec "$TMP/rz4.spec.md" --plan "$TMP/rz4-plan.md" --tests-root "$TMP/rz4-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNCOVERED${TAB}R-01${TAB}tests\$"; then
  ok "RZ4 (ADR-0157 D2): the plan names no discovered test file and every discovered file claims another feature -> the fallback REFUSES, R-01 is UNCOVERED, exit 1. Pre-fix this fixture reported COVERED, exit 0 — a false green on a stranger's requirement id."
else
  bad "RZ4: expected exit 1 + UNCOVERED R-01 tests (SCOPE-FOREIGN-ONLY must not fall back) — got rc=$RC out=[$OUT]"
fi
# plant: RZ4b | plugin/skills/concept-to-code/scripts/spec-coverage.sh | elif [ ! -s "$UNSCOPED_POP" ] && [ -s "$FOREIGN_CLAIMED" ]; then | elif false; then
if printf '%s\n' "$ERR" | grep -q 'SCOPE-FOREIGN-ONLY'; then
  ok "RZ4b: stderr names the refusal (SCOPE-FOREIGN-ONLY) — a guard that declines to fall back must say so (CLAUDE.md rule 4)"
else
  bad "RZ4b: expected SCOPE-FOREIGN-ONLY on stderr — got [$ERR]"
fi
if printf '%s\n' "$ERR" | grep -q 'SCOPE-EMPTY'; then
  bad "RZ4c: stderr says SCOPE-EMPTY as well — the refusal and the fallback are two states and every existing grep -q 'SCOPE-EMPTY' would read this one as the other"
else
  ok "RZ4c (ADR-0157 D2): the refusal token is NOT a SCOPE-EMPTY prefix — the two states stay tellable apart by the greps already written against the shorter token"
fi

# RZ5 — the fallback itself still works, on a population that could belong to this feature. Same shape
# as RZ4 with the discovered file claiming nobody: SCOPE-EMPTY, fallback, COVERED. This is ADR-0138's
# behaviour, and RY7 already pins it; what RZ5 adds is that the narrowed fallback did not break it.
mkdir -p "$TMP/rz5-tests"
cp "$TMP/rz4.spec.md" "$TMP/rz5.spec.md"
cp "$TMP/rz4-plan.md" "$TMP/rz5-plan.md"
cat >"$TMP/rz5-tests/beta.test.sh" <<'EOF'
# covers R-01
EOF
run_scov --spec "$TMP/rz5.spec.md" --plan "$TMP/rz5-plan.md" --tests-root "$TMP/rz5-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$" && printf '%s\n' "$ERR" | grep -q 'SCOPE-EMPTY'; then
  ok "RZ5 (forward guard): an unclaimed discovered file still reaches the SCOPE-EMPTY fallback and still reports COVERED, exit 0 — ADR-0157 narrows the fallback population without removing the fallback"
else
  bad "RZ5: expected exit 0 + COVERED R-01 + SCOPE-EMPTY on stderr — got rc=$RC out=[$OUT] err=[$ERR]"
fi

# ==================================================================================================
# RZ6-RZ10 — VCS-035, the LINE-granular gap the file-level classification above (RZ1-RZ5) does not
# close: a file legitimately IN SCOPE for this feature can still carry an isolated comment about a
# DIFFERENT feature, and the old checker read any R-NN token anywhere in an in-scope file as this
# feature's coverage. Measured on the real corpus (2026-08-24): 63% of discovered test files cite
# more than one feature's `#<n>`, so this is the norm, not an edge case.
# ==================================================================================================

# RZ6 — a matching line carries a FOREIGN claim token (#999) and no own-key on that same line, in a
# file otherwise in scope (it names the plan back). Pre-fix (verified against the unfixed checker):
# this exact fixture reported COVERED, exit 0 — a false green on a stranger's requirement id living
# two lines from this feature's own citation.
mkdir -p "$TMP/rz6-tests"
cat >"$TMP/rz6.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rz6-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Test coverage lives in alpha.test.sh.
EOF
cat >"$TMP/rz6-tests/alpha.test.sh" <<'EOF'
# names the plan back: rz6-plan.md
# covers R-01 — this belongs to issue #999, not this feature
EOF
# plant: RZ6 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | $0 ~ ENVIRON["OWN_LINE_RE"] | 1
run_scov --spec "$TMP/rz6.spec.md" --plan "$TMP/rz6-plan.md" --tests-root "$TMP/rz6-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RZ6 (VCS-035): a matching line carrying a foreign claim (#999) and no own-key on that line is not coverage -> UNSCOPED	R-01	1, exit 1. Pre-fix this exact fixture reported COVERED, exit 0."
else
  bad "RZ6: expected exit 1 + UNSCOPED R-01 1 (a foreign-claimed LINE inside an in-scope file is not this feature's coverage) — got rc=$RC out=[$OUT]"
fi

# RZ7 — positive twin (CLAUDE.md rule 8, same shape as RZ2 but at line granularity): the SAME foreign
# #999 claim, but the own-key (the plan's own basename) sits on the SAME line. Ownership wins over a
# foreign claim at line granularity exactly as it already does at file granularity (RZ2).
mkdir -p "$TMP/rz7-tests"
cat >"$TMP/rz7.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rz7-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Test coverage lives in alpha.test.sh.
EOF
cat >"$TMP/rz7-tests/alpha.test.sh" <<'EOF'
# covers R-01 — carried over from issue #999, now this feature's own harness, see rz7-plan.md
EOF
# plant: RZ7 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | $0 ~ ENVIRON["OWN_LINE_RE"] | $0 ~ "NEVERMATCH_RZ7"
run_scov --spec "$TMP/rz7.spec.md" --plan "$TMP/rz7-plan.md" --tests-root "$TMP/rz7-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$"; then
  ok "RZ7 (positive twin of RZ6, CLAUDE.md rule 8): a line carrying BOTH a foreign claim and this feature's own-key -> COVERED, exit 0. Without this twin, RZ6 is satisfiable by a filter that discards every claim-bearing line regardless of ownership."
else
  bad "RZ7: expected exit 0 + COVERED R-01 (own-key on the same line as the foreign claim beats it) — got rc=$RC out=[$OUT]"
fi

# RZ8 — non-regression guard: a matching line with NO claim token at all (the ordinary case, 864 of
# 972 R-NN mentions in this repo) is kept unconditionally. This is the assertion a same-line-STRICT
# design (require an own-key on every covering line) would have failed.
mkdir -p "$TMP/rz8-tests"
cat >"$TMP/rz8.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rz8-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Test coverage lives in alpha.test.sh.
EOF
cat >"$TMP/rz8-tests/alpha.test.sh" <<'EOF'
# names the plan back: rz8-plan.md
# covers R-01
EOF
run_scov --spec "$TMP/rz8.spec.md" --plan "$TMP/rz8-plan.md" --tests-root "$TMP/rz8-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$"; then
  ok "RZ8 (forward guard): a matching line with no claim token at all is kept unconditionally — the ordinary case a same-line-strict design would have broken"
else
  bad "RZ8: expected exit 0 + COVERED R-01 (an unclaimed line is always coverage) — got rc=$RC out=[$OUT]"
fi

# RZ9 — the case that actually motivated VCS-035: an issue-less feature has no "#<n>" to sign a line
# with, so its only possible signature in a comment is its own ADR. A matching line citing an ADR the
# PLAN UNDER TEST does not cite, and no own-key otherwise, is a foreign claim by another means. Pre-fix
# (verified): this exact fixture reported COVERED, exit 0.
mkdir -p "$TMP/rz9-tests"
cat >"$TMP/rz9.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rz9-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Test coverage lives in alpha.test.sh. See ADR-1001 for background.
EOF
cat >"$TMP/rz9-tests/alpha.test.sh" <<'EOF'
# names the plan back: rz9-plan.md
# covers R-01 — see ADR-2002 for the original design
EOF
# plant: RZ9 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | CLAIM_LINE_RE='(^|[^A-Za-z0-9_])(#[0-9][0-9]*|ADR-[0-9][0-9][0-9][0-9])([^0-9]|$)' | CLAIM_LINE_RE='(^|[^A-Za-z0-9_])(#[0-9][0-9]*)([^0-9]|$)'
run_scov --spec "$TMP/rz9.spec.md" --plan "$TMP/rz9-plan.md" --tests-root "$TMP/rz9-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RZ9 (VCS-035, the motivating case): a line citing an ADR the plan under test does NOT cite, and no own-key otherwise, is a foreign claim -> UNSCOPED	R-01	1, exit 1. Pre-fix this exact fixture reported COVERED, exit 0 — the false green an issue-less feature's stray ADR mention produces in another feature's coverage."
else
  bad "RZ9: expected exit 1 + UNSCOPED R-01 1 (a foreign ADR claim on the line is not this feature's coverage) — got rc=$RC out=[$OUT]"
fi

# RZ10 — positive twin of RZ9 (CLAUDE.md rule 8): the SAME ADR, but this feature's OWN plan cites it.
# Verifies the extension does not break a feature that legitimately cites its own ADR — the failure
# mode of the naive "any ADR-NNNN is a foreign claim" design that was measured and rejected (76 of 972
# R-NN mentions in the repo carry the file's own ADR with no other own-key on the line).
mkdir -p "$TMP/rz10-tests"
cat >"$TMP/rz10.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rz10-plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Test coverage lives in alpha.test.sh. See ADR-3003 for background.
EOF
cat >"$TMP/rz10-tests/alpha.test.sh" <<'EOF'
# names the plan back: rz10-plan.md
# covers R-01 — see ADR-3003 for the original design
EOF
# plant: RZ10 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | OWN_LINE_KEYS="${OWN_LINE_KEYS}|${_own_adr}" | :
run_scov --spec "$TMP/rz10.spec.md" --plan "$TMP/rz10-plan.md" --tests-root "$TMP/rz10-tests"
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "^COVERED${TAB}R-01\$"; then
  ok "RZ10 (positive twin of RZ9, CLAUDE.md rule 8): a line citing an ADR THIS feature's own plan also cites -> COVERED, exit 0. Without this twin, RZ9 is satisfiable by a filter that discards every ADR-bearing line regardless of ownership — the rejected naive design."
else
  bad "RZ10: expected exit 0 + COVERED R-01 (own-plan ADR citation on the line beats the generic ADR filter) — got rc=$RC out=[$OUT]"
fi

# RZ11 — VCS-035's own-key check must compare a LITERAL dot in the plan basename, not a wildcard.
# $OWN_LINE_RE is built from $PLAN_BN_ESC (a sed-escaped plan basename, so a real "." in the
# filename becomes the ERE escape "\."). The COVERED_IDS precompute (perf-final-books-slowdown)
# reads $OWN_LINE_RE inside an awk program; if that string ever reaches awk via `-v` instead of
# `ENVIRON[]`, POSIX `-v var=value` re-interprets the backslash the way a string literal would and
# "\." silently becomes an unescaped "." — a wildcard matching ANY character, not just a literal
# dot. Fixture: a plan named "rz11.own.plan.md" (two dots) and a test line carrying a foreign claim
# (#999) plus a NEAR-MISS of the plan's own basename with a stand-in character where each dot
# should be ("rz11Xown.planXmd") — same length, wrong characters. A correct literal-dot match must
# NOT recognise this as the plan's own-key, so the line stays a bare foreign claim -> UNSCOPED. A
# wildcarded "-v"-style match WOULD recognise it (any two characters "fill" the two "." wildcards)
# and misreport COVERED — reproduced and confirmed against this exact fixture before this test was
# written, both in isolation (`awk -v RE='a\.b'` matches "axb" on this machine's BWK awk) and
# end-to-end through this script.
mkdir -p "$TMP/rz11-tests"
cat >"$TMP/rz11.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/rz11.own.plan.md" <<'EOF'
### Task 1 — do thing (R-01)
Test coverage lives in alpha.test.sh.
EOF
cat >"$TMP/rz11-tests/alpha.test.sh" <<'EOF'
# names the plan back: rz11.own.plan.md
# covers R-01 — this belongs to issue #999, not this feature, see rz11Xown.planXmd
EOF
# plant: RZ11 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | is_claim = ($0 ~ ENVIRON["CLAIM_LINE_RE"]) if (!is_claim || (is_claim && ($0 ~ ENVIRON["OWN_LINE_RE"]))) extract_tokens($0) | is_claim = ($0 ~ CLAIM_RE)\nif (!is_claim || (is_claim && ($0 ~ OWN_RE))) extract_tokens($0)
run_scov --spec "$TMP/rz11.spec.md" --plan "$TMP/rz11.own.plan.md" --tests-root "$TMP/rz11-tests"
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "^UNSCOPED${TAB}R-01${TAB}1\$"; then
  ok "RZ11 (VCS-035, escaping): a near-miss of the plan's own basename (stand-in characters where its literal dots are) does not count as an own-key citation -> UNSCOPED	R-01	1, exit 1. A '-v'-passed \$OWN_LINE_RE would wildcard-match this and misreport COVERED."
else
  bad "RZ11: expected exit 1 + UNSCOPED R-01 1 (a near-miss of the plan basename, wrong chars where its dots are, must not match as an own-key) — got rc=$RC out=[$OUT]"
fi

# ==================================================================================================
# RW. Performance (issue perf-final-books-slowdown). grep_boundary_test()/grep_boundary_test_claimed()
# used to fork `xargs -0 grep -hE "<id-anchored-pattern>"` over the WHOLE scoped/unscoped test-file
# population ONCE PER DECLARED ID inside the main loop — O(ids x population) forks, measured as the
# dominant cost of a 3-15 minute Step 5 -> Step 6 gate on a real project. Both were replaced by a
# one-time, single-pass awk precompute (COVERED_IDS / CLAIMED_IDS). RW1 is the PRIMARY guard: an
# EXACT structural count (CLAUDE.md rule 10 — prefer a structural count over a timing floor), proven
# against a real regression by its own plant. RW2 is a SECONDARY, generous wall-clock ceiling,
# belt-and-suspenders only.
# ==================================================================================================

# RW0 — shared fixture for RW1: 24 declared ids (>= 20) and 32 discovered test files (>= 30). The
# plan cites every id on one task line but names no test file basename at all, so the SCOPE-EMPTY
# fallback (ADR-0138 §D2, unchanged by this fix) populates $TESTFILES_SCOPED from the whole
# discovered population — both boundary-coverage precompute branches (COVERED_IDS and CLAIMED_IDS)
# actually run, which is what RW1 measures.
{
  echo "## Success criteria"
  _rw_i=1
  while [ "$_rw_i" -le 24 ]; do
    printf -- '- [ ] R-%02d — item %d\n' "$_rw_i" "$_rw_i"
    _rw_i=$((_rw_i + 1))
  done
} >"$TMP/rw.spec.md"
{
  printf '### Task 1 — cover everything ('
  _rw_i=1
  while [ "$_rw_i" -le 24 ]; do
    printf 'R-%02d' "$_rw_i"
    [ "$_rw_i" -lt 24 ] && printf ', '
    _rw_i=$((_rw_i + 1))
  done
  printf ')\n'
} >"$TMP/rw-plan.md"
mkdir -p "$TMP/rw-tests"
_rw_i=1
while [ "$_rw_i" -le 32 ]; do
  _rw_mod=$(( (_rw_i % 24) + 1 ))
  printf '# covers R-%02d\n' "$_rw_mod" >"$TMP/rw-tests/file$_rw_i.test.sh"
  _rw_i=$((_rw_i + 1))
done

# plant: RW1 | plugin/skills/concept-to-code/scripts/spec-coverage.sh | if grep -qxF "$id" "$COVERED_IDS" 2>/dev/null; then | if tr '\n' '\0' <"$TESTFILES_SCOPED"| xargs -0 grep -qE "$id" 2>/dev/null; then
RW_TRACE="$TMP/rw-trace.txt"
bash -x "$SCOV" --spec "$TMP/rw.spec.md" --plan "$TMP/rw-plan.md" --tests-root "$TMP/rw-tests" \
  >"$TMP/rw-out.txt" 2>"$RW_TRACE"
RW_XARGS_N=$(grep -c 'xargs' "$RW_TRACE" 2>/dev/null); RW_XARGS_N=${RW_XARGS_N:-0}
if [ "$RW_XARGS_N" -le 5 ]; then
  ok "RW1 (structural fork-count guard, issue perf-final-books-slowdown): 24 declared ids x 32 discovered test files fork xargs only $RW_XARGS_N time(s) in the bash -x trace — bounded by a small constant, NOT scaling with id count. The removed grep_boundary_test()/grep_boundary_test_claimed() shape forked one xargs pipeline PER ID; this pins that the O(ids) fork pattern has not returned."
else
  bad "RW1: expected <= 5 xargs invocation(s) in the bash -x trace (a fork count independent of id count) — got $RW_XARGS_N. This is the O(ids) fork regression the perf fix removed."
fi

# RW2 — SECONDARY, generous wall-clock ceiling (CLAUDE.md rule 10: a floor/ceiling is kept only as a
# vacuity guard, stated as such here, never the primary pin — RW1 above is the primary pin). Fixture:
# 60 declared ids x 300 discovered test files, the scale the fix's plan named for a before/after
# measurement. Measured on the development machine 2026-09-03: this exact fixture ran in ~2.7s AFTER
# the fix (~3.4s before it, on the unmodified pre-fix script) — the ceiling below is a generous ~10x
# that measurement, on purpose: this assertion is a coarse, environment-sensitive smoke check, and a
# FAILURE here means "investigate" (a slow CI runner, a noisy neighbour), never "this is a confirmed
# regression" — RW1's exact fork count is what carries that claim.
{
  echo "## Success criteria"
  _rw2_i=1
  while [ "$_rw2_i" -le 60 ]; do
    printf -- '- [ ] R-%02d — item %d\n' "$_rw2_i" "$_rw2_i"
    _rw2_i=$((_rw2_i + 1))
  done
} >"$TMP/rw2.spec.md"
{
  printf '### Task 1 — cover everything ('
  _rw2_i=1
  while [ "$_rw2_i" -le 60 ]; do
    printf 'R-%02d' "$_rw2_i"
    [ "$_rw2_i" -lt 60 ] && printf ', '
    _rw2_i=$((_rw2_i + 1))
  done
  printf ')\n'
} >"$TMP/rw2-plan.md"
mkdir -p "$TMP/rw2-tests"
_rw2_i=1
while [ "$_rw2_i" -le 300 ]; do
  _rw2_mod=$(( (_rw2_i % 60) + 1 ))
  printf '# covers R-%02d\n' "$_rw2_mod" >"$TMP/rw2-tests/file$_rw2_i.test.sh"
  _rw2_i=$((_rw2_i + 1))
done

SECONDS=0
run_scov --spec "$TMP/rw2.spec.md" --plan "$TMP/rw2-plan.md" --tests-root "$TMP/rw2-tests"
RW2_ELAPSED=$SECONDS
if [ "$RC" -eq 0 ] && [ "$RW2_ELAPSED" -le 30 ]; then
  ok "RW2 (secondary wall-clock guard, generous, flaky-if-red — investigate, do not treat as an automatic regression): 60 ids x 300 files completed in ${RW2_ELAPSED}s (<= 30s ceiling)"
else
  bad "RW2: 60 ids x 300 files took ${RW2_ELAPSED}s (ceiling 30s) or exited non-zero (rc=$RC) — investigate before treating this as a confirmed regression (RW1 is the exact pin)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
