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
# docs/specs/ file (concept-to-code Step 1 writes it, nightly Phase P copies it from there), so it
# adds no coverage this glob does not already have. It was a member until 2026-07-28, when the
# first SPEC to actually declare R-NN ids in its success criteria — which is what ADR-0048 asked
# for — made this backward-compatibility loop fail on the correct use of the feature it protects.
# A backward-compatibility corpus must be a stable set; a work-in-flight file is not one.
re3_count=0; re3_bad=0
for f in "$REPO"/docs/specs/*.spec.md; do
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
  ok "RE4: the RE3 corpus loop visited $re3_count files (>= 30) — not a vacuous pass"
else
  bad "RE4: the RE3 corpus loop visited only $re3_count files (< 30) — a glob matching almost nothing would read as full coverage"
fi

# ==============================================================================================
# RF. concept-to-code/SKILL.md Step 5 — the Requirement-ID coverage gate block (ADR-0048 §D5).
# EXPECTED RED until Task 6 (deferred to a later batch). Static prose anchors against the real
# Step 5 extract, deliberately: the file is instructions for a model, not runnable code.
# ==============================================================================================
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
STEP5="$TMP/c2c_step5.txt"
awk '/^### Step 5 —/{f=1} /^### Step 6 —/{f=0} f' "$CC" >"$STEP5"

if [ -s "$STEP5" ]; then
  ok "RF0: Step 5 of concept-to-code/SKILL.md is extractable (the anchor every RF assertion reads)"
else
  bad "RF0: could not extract Step 5 from $CC — every RF assertion below is meaningless"
fi

RF1_N=$(grep -c '^#### Requirement-ID coverage gate — Step 5 → Step 6 (ADR-0048)$' "$CC" || true)
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

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
