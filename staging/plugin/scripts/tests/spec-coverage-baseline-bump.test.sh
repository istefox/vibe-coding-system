#!/bin/bash
# spec-coverage-baseline-bump.test.sh — offline, hermetic, no network, no $HOME dependency (except
# NB16c, which deliberately overrides HOME for one invocation to prove the two-tier lookup's SECOND
# tier really fails when nothing is there — the same controlled exception spec-archive.test.sh's
# FHOME and gate2b-trust-probe.test.sh's FHOME already use).
# Bash 3.2 clean. Run: bash spec-coverage-baseline-bump.test.sh
#
# Covers issue #460 / ADR-0166
# (docs/architecture/ADR-0166-460-spec-coverage-baseline-never-bumped.md), plan
# docs/superpowers/plans/2026-08-22-460-spec-coverage-baseline-never-bumped.md: the standalone
# script that derives baseline rows for one (SPEC, plan) pair and appends the ones a completing
# chain introduces, so the chain that enrols a new corpus member ships its own baseline rows in the
# same commit (SPEC.md R-01 … R-08).
#
# ASSERTION LABELS ARE NB-PREFIXED (NB1, NB2, ...) — verified free 2026-08-22 across all 96
# harnesses (grep -rn '"NB[0-9]' finds no match) and distinct from spec-coverage.test.sh's own
# R-prefixed labels (RA/RB/.../RS/RY/RZ and the new RS0), which this file does not touch (Task 3
# edits that file, not this one).
#
# BATCH A (ADR-0101 batch table): the script under test,
# staging/plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh, does NOT exist yet
# — it is Task 2, a later batch, by a different agent. Every assertion below is expected to fail RED
# right now, including NB1, the existence anchor. This file is deliberately committed in that state
# (ADR-0101: an assertion must not land in the same batch as the task that greens it).
#
# THE SCRIPT UNDER TEST IS A "PRODUCER WITH A CHECKER'S EXIT-CODE CHANNEL" (ADR-0166 §D4): --rows
# and --pair behave like producers (stdout is the payload; empty/nothing is a valid answer);
# --bump's four exit codes are 0 success, 1 conflict/nothing written, 2 invalid invocation,
# 3 did-not-run. Do not copy spec-coverage.sh's own two-state checker/reporter split (its own
# header, see spec-coverage.test.sh's header) into this file without re-reading ADR-0166 §D4 first.
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL, no "secret", "credential", ".env", ".pem" or
# ".key" substring — secret-dep-gate.test.sh's section D scans this repository's tracked files as
# its false-positive corpus, the same discipline spec-coverage.test.sh's own header states.
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

ROWS="$STAGING/plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh"
SCOV="$STAGING/plugin/skills/concept-to-code/scripts/spec-coverage.sh"
CC_SKILL="$STAGING/plugin/skills/concept-to-code/SKILL.md"
SYNCSH="$STAGING/sync-to-claude.sh"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"

run_rows() { OUT=$(bash "$ROWS" "$@" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err" 2>/dev/null); }

# flatten() — same idiom claude-md-condensation.test.sh's flat() uses: collapse newlines, strip
# backtick/asterisk/underscore decoration, lowercase, squeeze spaces (rule 3: a clause is the same
# clause whether it wraps across lines, is backticked, or is bolded).
flatten() { tr '\n' ' ' <"$1" | tr -d '`*_' | tr 'A-Z' 'a-z' | sed 's/  */ /g'; }

# ==================================================================================================
# NB1. The anchor every NB2-NB21 assertion below depends on.
#
# UNPLANTABLE BY CLASS (Task 8, declared here so Task 8 does not go looking): this is an EXISTENCE
# check (a path is a file and is readable), the same class PT1/PT2 (prep.test.sh) and AIJ2
# (accessibility-i18n.test.sh) already document as unplantable — the registry's mechanism mutates
# TEXT inside a tracked file, never a file's presence, so there is no text substitution that makes
# `[ -f "$ROWS" ] && [ -r "$ROWS" ]` go false without literally deleting the file, which is outside
# what a plant declaration can express.
# ==================================================================================================
if [ -f "$ROWS" ] && [ -r "$ROWS" ]; then
  ok "NB1: $ROWS exists and is readable"
else
  bad "NB1: $ROWS not found or unreadable — every NB2-NB21 assertion below is meaningless (Task 2 creates this script; Batch A expects this red)"
fi

# ==================================================================================================
# NB2-NB6 (R-02) — --rows --spec <spec> --plan <plan> --tests-root <root>.
# ==================================================================================================

# NB2 — a fixture SPEC declaring two ids, a plan citing both and naming a discovered test file, and
# that test file naming the plan back: stdout is exactly two lines, <spec-basename><TAB><id><TAB>
# COVERED each. The exact-string comparison against a basename-keyed expectation IS the "assert the
# basename, not the path" check — a full tmp path anywhere in $OUT would fail the equality.
# plant: NB2 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | _cr_bn=$(basename "$_cr_spec") | _cr_bn=$(echo "$_cr_spec")
cat >"$TMP/nb2.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
- [ ] R-02 — second
EOF
cat >"$TMP/nb2-plan.md" <<'EOF'
### Task 1 -- do thing (R-01, R-02)
Test coverage lives in nb2.test.sh.
EOF
mkdir -p "$TMP/nb2-tests"
cat >"$TMP/nb2-tests/nb2.test.sh" <<'EOF'
# covers R-01 and R-02, names the plan back: nb2-plan.md
EOF
run_rows --rows --spec "$TMP/nb2.spec.md" --plan "$TMP/nb2-plan.md" --tests-root "$TMP/nb2-tests"
NB2_EXP="nb2.spec.md${TAB}R-01${TAB}COVERED
nb2.spec.md${TAB}R-02${TAB}COVERED"
if [ "$OUT" = "$NB2_EXP" ]; then
  ok "NB2 (--rows, R-02): stdout is exactly two rows, <basename><TAB><id><TAB>COVERED each — keyed on the basename nb2.spec.md, never the fixture's tmp path"
else
  bad "NB2: expected two COVERED rows keyed on the basename nb2.spec.md — got out=[$OUT]"
fi

# NB3 — the three verdicts are read off the checker's own stdout, never re-interpreted: one fixture
# producing COVERED (R-01, mentioned in the one scoped+backreffed test file), one UNSCOPED (R-02,
# mentioned only in a file the plan does not name), one UNCOVERED (R-03, mentioned nowhere) — each
# asserted on its own row, three independent checks combined in one gate.
# plant: NB3 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | grep -q "^UNSCOPED${TAB}${_cr_id}${TAB}" && _cr_verdict="UNSCOPED" | grep -q "^UNSCOPED_NB3_NEVER${TAB}${_cr_id}${TAB}" && _cr_verdict="UNSCOPED"
cat >"$TMP/nb3.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
- [ ] R-02 — second
- [ ] R-03 — third
EOF
cat >"$TMP/nb3-plan.md" <<'EOF'
### Task 1 -- do thing (R-01, R-02, R-03)
Test coverage lives in nb3.test.sh.
EOF
mkdir -p "$TMP/nb3-tests"
cat >"$TMP/nb3-tests/nb3.test.sh" <<'EOF'
# covers R-01, names the plan back: nb3-plan.md
EOF
cat >"$TMP/nb3-tests/unscoped.test.sh" <<'EOF'
# covers R-02, not named by the plan, claims nothing else
EOF
run_rows --rows --spec "$TMP/nb3.spec.md" --plan "$TMP/nb3-plan.md" --tests-root "$TMP/nb3-tests"
NB3_OK=1
printf '%s\n' "$OUT" | grep -qxF "nb3.spec.md${TAB}R-01${TAB}COVERED"   || NB3_OK=0
printf '%s\n' "$OUT" | grep -qxF "nb3.spec.md${TAB}R-02${TAB}UNSCOPED" || NB3_OK=0
printf '%s\n' "$OUT" | grep -qxF "nb3.spec.md${TAB}R-03${TAB}UNCOVERED" || NB3_OK=0
if [ "$NB3_OK" -eq 1 ]; then
  ok "NB3 (--rows): three verdicts read off the checker's own stdout, unreinterpreted — R-01 COVERED, R-02 UNSCOPED, R-03 UNCOVERED, each its own row"
else
  bad "NB3: expected COVERED/UNSCOPED/UNCOVERED rows for R-01/R-02/R-03 respectively — got out=[$OUT]"
fi

# NB4 — a SPEC declaring zero ids: empty stdout, exit 0. Not "0 rows", nothing (ADR-0048 §D7/§D8's
# silent no-ids path, read straight through this wrapper).
# plant: NB4 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | [ -n "$_cr_list" ] || return 0 | [ -n "$_cr_list" ] || return 1
cat >"$TMP/nb4.spec.md" <<'EOF'
## Success criteria
- [ ] Some criterion with no id at all.
EOF
: >"$TMP/nb4-plan.md"
mkdir -p "$TMP/nb4-tests"
run_rows --rows --spec "$TMP/nb4.spec.md" --plan "$TMP/nb4-plan.md" --tests-root "$TMP/nb4-tests"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "NB4 (--rows): a SPEC declaring zero ids — empty stdout, exit 0, not \"0 rows\""
else
  bad "NB4: expected empty stdout + exit 0 for a zero-id SPEC — got rc=$RC out=[$OUT]"
fi

# NB5 (also protects RY10) — stderr passthrough. A fixture whose plan names no discovered test
# file: the script's OWN stderr contains SCOPE-EMPTY, verbatim from the checker, and contains no
# line the script added itself. Assert both halves separately: SCOPE-EMPTY presence, AND
# byte-identity against spec-coverage.sh's own stderr for the identical invocation (a byte-identity
# check is a stronger, more direct way to prove "no line the wrapper added" than guessing the
# wrapper's own diagnostic prefix, which Task 2 does not fix in advance).
# plant: NB5 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | _cr_run=$(bash "$SCOV" --spec "$_cr_spec" --plan "$_cr_plan" --tests-root "$_cr_troot") | _cr_run=$(bash "$SCOV" --spec "$_cr_spec" --plan "$_cr_plan" --tests-root "$_cr_troot" 2>/dev/null)
cat >"$TMP/nb5.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/nb5-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
No test file is named anywhere in this plan's prose.
EOF
mkdir -p "$TMP/nb5-tests"
cat >"$TMP/nb5-tests/alpha.test.sh" <<'EOF'
# covers R-01
EOF
bash "$SCOV" --spec "$TMP/nb5.spec.md" --plan "$TMP/nb5-plan.md" --tests-root "$TMP/nb5-tests" \
  >"$TMP/nb5-checker-out.txt" 2>"$TMP/nb5-checker-err.txt"
NB5_CHECKER_ERR=$(cat "$TMP/nb5-checker-err.txt" 2>/dev/null)
run_rows --rows --spec "$TMP/nb5.spec.md" --plan "$TMP/nb5-plan.md" --tests-root "$TMP/nb5-tests"
NB5_SCOPE_EMPTY=0
printf '%s\n' "$ERR" | grep -q 'SCOPE-EMPTY' && NB5_SCOPE_EMPTY=1
NB5_VERBATIM=0
[ "$ERR" = "$NB5_CHECKER_ERR" ] && NB5_VERBATIM=1
if [ "$NB5_SCOPE_EMPTY" -eq 1 ] && [ "$NB5_VERBATIM" -eq 1 ]; then
  ok "NB5 (--rows, also protects RY10): stderr passthrough — a plan naming no discovered test file produces SCOPE-EMPTY on the script's own stderr, verbatim (byte-identical) against spec-coverage.sh's own stderr for the same invocation, no line added by the wrapper"
else
  bad "NB5: expected stderr to contain SCOPE-EMPTY and be byte-identical to spec-coverage.sh's own stderr — got scope_empty=$NB5_SCOPE_EMPTY verbatim=$NB5_VERBATIM rows_err=[$ERR] checker_err=[$NB5_CHECKER_ERR]"
fi

# NB6 (rule 4) — spec-coverage.sh unresolvable: --scov-override points at a path that does not
# exist. Exit 3, empty stdout, a stderr line naming the missing script. A bump that could not
# compute must not read as one with nothing to do.
# plant: NB6 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | printf '%s: spec-coverage.sh unresolvable: %s\n' "$SELF" "$SCOV_OVERRIDE" >&2 return 1 | printf '%s: spec-coverage.sh unresolvable: %s\\n' "$SELF" "$SCOV_OVERRIDE" >&2 return 0
cat >"$TMP/nb6.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/nb6-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in nb6.test.sh.
EOF
mkdir -p "$TMP/nb6-tests"
cat >"$TMP/nb6-tests/nb6.test.sh" <<'EOF'
# covers R-01, names the plan back: nb6-plan.md
EOF
NB6_MISSING="$TMP/does-not-exist-spec-coverage.sh"
run_rows --rows --spec "$TMP/nb6.spec.md" --plan "$TMP/nb6-plan.md" --tests-root "$TMP/nb6-tests" --scov-override "$NB6_MISSING"
if [ "$RC" -eq 3 ] && [ -z "$OUT" ] && printf '%s\n' "$ERR" | grep -qF "$NB6_MISSING"; then
  ok "NB6 (rule 4): spec-coverage.sh unresolvable (--scov-override pointed at a path that does not exist) — exit 3, empty stdout, stderr names the missing script; a bump that could not compute must not read as one with nothing to do"
else
  bad "NB6: expected exit 3 + empty stdout + stderr naming $NB6_MISSING — got rc=$RC out=[$OUT] err=[$ERR]"
fi

# ==================================================================================================
# NB7 (R-01, R-02) — --pair --spec <spec> --plans-dir <dir>. Three sub-cases, one assertion each.
# ==================================================================================================
touch "$TMP/460-foo.spec.md"

# plant: NB7a | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | "$_p_dir"/????-??-??-"${_p_n}"-*.md | "$_p_dir"/????-??-??-"${_p_n}"-NB7aNEVER-*.md
mkdir -p "$TMP/nb7a-plans"
touch "$TMP/nb7a-plans/2026-08-22-460-foo.md"
run_rows --pair --spec "$TMP/460-foo.spec.md" --plans-dir "$TMP/nb7a-plans"
if [ "$RC" -eq 0 ] && [ "$OUT" = "$TMP/nb7a-plans/2026-08-22-460-foo.md" ]; then
  ok "NB7a (--pair): a plans dir holding <date>-460-foo.md resolves to it by issue-number prefix"
else
  bad "NB7a: expected $TMP/nb7a-plans/2026-08-22-460-foo.md on stdout, exit 0 — got rc=$RC out=[$OUT]"
fi

# plant: NB7b | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | "$_p_dir"/????-??-??-"${_p_slug}".md | "$_p_dir"/????-??-??-"${_p_slug}"-NB7bNEVER.md
mkdir -p "$TMP/nb7b-plans"
touch "$TMP/nb7b-plans/2026-08-22-foo.md"
run_rows --pair --spec "$TMP/460-foo.spec.md" --plans-dir "$TMP/nb7b-plans"
if [ "$RC" -eq 0 ] && [ "$OUT" = "$TMP/nb7b-plans/2026-08-22-foo.md" ]; then
  ok "NB7b (--pair): a plans dir holding no issue-number match falls back to the slug-only form <date>-foo.md"
else
  bad "NB7b: expected $TMP/nb7b-plans/2026-08-22-foo.md on stdout, exit 0 — got rc=$RC out=[$OUT]"
fi

# plant: NB7c | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | "${_p_slug}".md | *.md
mkdir -p "$TMP/nb7c-plans"
touch "$TMP/nb7c-plans/2026-08-22-bar.md"
run_rows --pair --spec "$TMP/460-foo.spec.md" --plans-dir "$TMP/nb7c-plans"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "NB7c (--pair): a plans dir holding neither form prints nothing, exit 0"
else
  bad "NB7c: expected empty stdout, exit 0 — got rc=$RC out=[$OUT]"
fi

# NB7d (VCS-034) — an ISSUE-LESS SPEC (no numeric prefix at all) must resolve via the FULL
# basename as the fallback slug, not a mutilated one with the first hyphen segment stripped.
# Pre-fix (verified against the unfixed script before this line existed): the fallback stripped
# "sample" unconditionally, built the slug "issueless-thing", and the pair resolved to nothing —
# the SPEC left the RS_PAIRS corpus silently.
# plant: NB7d | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | _p_rest=$_p_bn | _p_rest=${_p_bn#*-}
touch "$TMP/sample-issueless-thing.spec.md"
mkdir -p "$TMP/nb7d-plans"
touch "$TMP/nb7d-plans/2026-08-24-sample-issueless-thing.md"
run_rows --pair --spec "$TMP/sample-issueless-thing.spec.md" --plans-dir "$TMP/nb7d-plans"
if [ "$RC" -eq 0 ] && [ "$OUT" = "$TMP/nb7d-plans/2026-08-24-sample-issueless-thing.md" ]; then
  ok "NB7d (--pair, VCS-034): an issue-less SPEC's basename is used WHOLE as the fallback slug, not mutilated by an unconditional first-segment strip"
else
  bad "NB7d: expected $TMP/nb7d-plans/2026-08-24-sample-issueless-thing.md on stdout, exit 0 — got rc=$RC out=[$OUT]"
fi

# ==================================================================================================
# NB8-NB14 (R-01, R-03, R-04, R-06) — --bump --baseline <file> --spec <spec> --plan <plan>
# --tests-root <root>.
# ==================================================================================================

# NB8 (R-01) — a baseline fixture missing both rows: after the bump, both rows are present, in
# three-column form, stdout is "BUMPED 2 row(s) for <spec-basename>", exit 0.
# plant: NB8 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | _b_n=$((_b_n + 1)) | _b_n=$((_b_n + 0))
cat >"$TMP/nb8.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
- [ ] R-02 — second
EOF
cat >"$TMP/nb8-plan.md" <<'EOF'
### Task 1 -- do thing (R-01, R-02)
Test coverage lives in nb8.test.sh.
EOF
mkdir -p "$TMP/nb8-tests"
cat >"$TMP/nb8-tests/nb8.test.sh" <<'EOF'
# covers R-01 and R-02, names the plan back: nb8-plan.md
EOF
cat >"$TMP/nb8-baseline.tsv" <<'EOF'
# a hermetic baseline fixture, no pre-existing row for this pair
EOF
run_rows --bump --baseline "$TMP/nb8-baseline.tsv" --spec "$TMP/nb8.spec.md" --plan "$TMP/nb8-plan.md" --tests-root "$TMP/nb8-tests"
NB8_ROWS_OK=1
grep -qxF "nb8.spec.md${TAB}R-01${TAB}COVERED" "$TMP/nb8-baseline.tsv" || NB8_ROWS_OK=0
grep -qxF "nb8.spec.md${TAB}R-02${TAB}COVERED" "$TMP/nb8-baseline.tsv" || NB8_ROWS_OK=0
if [ "$RC" -eq 0 ] && [ "$OUT" = "BUMPED 2 row(s) for nb8.spec.md" ] && [ "$NB8_ROWS_OK" -eq 1 ]; then
  ok "NB8 (--bump, R-01): a baseline fixture missing both rows — after the bump both rows are present in three-column form, stdout is BUMPED 2 row(s) for nb8.spec.md, exit 0"
else
  bad "NB8: expected exit 0 + stdout 'BUMPED 2 row(s) for nb8.spec.md' + both rows present three-column — got rc=$RC out=[$OUT] rows_ok=$NB8_ROWS_OK"
fi

# NB9 (R-03) — the fixture baseline ALSO carries rows for a DIFFERENT spec: one sharing this bump's
# own id (nb9.spec.md's R-01), one in five-column form (the ADR-0157 historical-drift shape). After
# the bump those two pre-existing rows are byte-identical — diffed against the pre-bump copy, not
# spot-checked.
# plant: NB9 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | _b_existing=$(awk -F"$TAB" -v s="$_b_bn" -v i="$_b_id" '$1==s && $2==i {print $3; exit}' "$BASELINE") if [ -z "$_b_existing" ]; then | _b_existing=$(awk -F"$TAB" -v s="$_b_bn" -v i="$_b_id" '$2==i {print $3; exit}' "$BASELINE") if [ -z "$_b_existing" ]; then
cat >"$TMP/nb9.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/nb9-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in nb9.test.sh.
EOF
mkdir -p "$TMP/nb9-tests"
cat >"$TMP/nb9-tests/nb9.test.sh" <<'EOF'
# covers R-01, names the plan back: nb9-plan.md
EOF
printf 'other.spec.md%sR-01%sCOVERED\n' "$TAB" "$TAB" >"$TMP/nb9-baseline.tsv"
printf 'other2.spec.md%sR-05%sUNSCOPED%stestable%ssome pre-existing explanation text\n' "$TAB" "$TAB" "$TAB" "$TAB" >>"$TMP/nb9-baseline.tsv"
cp "$TMP/nb9-baseline.tsv" "$TMP/nb9-baseline-pre.tsv"
run_rows --bump --baseline "$TMP/nb9-baseline.tsv" --spec "$TMP/nb9.spec.md" --plan "$TMP/nb9-plan.md" --tests-root "$TMP/nb9-tests"
head -2 "$TMP/nb9-baseline.tsv" >"$TMP/nb9-post-head.txt" 2>/dev/null
# The byte-identical-region check alone is satisfiable by NOTHING RUNNING AT ALL (a script that
# does not exist never touches the file either) — a false green in Batch A. NB9_APPENDED and the
# rc check make it require a REAL bump to have happened, not merely a file left untouched.
NB9_PREEXISTING_OK=0; cmp -s "$TMP/nb9-baseline-pre.tsv" "$TMP/nb9-post-head.txt" && NB9_PREEXISTING_OK=1
NB9_APPENDED=0; grep -qxF "nb9.spec.md${TAB}R-01${TAB}COVERED" "$TMP/nb9-baseline.tsv" 2>/dev/null && NB9_APPENDED=1
if [ "$RC" -eq 0 ] && [ "$NB9_APPENDED" -eq 1 ] && [ "$NB9_PREEXISTING_OK" -eq 1 ]; then
  ok "NB9 (--bump, R-03): a baseline also carrying rows for a DIFFERENT spec — one sharing this bump's own id, one in five-column form — is byte-identical in that pre-existing region after a REAL bump that did append this pair's own row (diffed, not spot-checked)"
else
  bad "NB9: expected exit 0 + this pair's own row appended + the pre-existing two rows for the other spec byte-identical — got rc=$RC appended=$NB9_APPENDED preexisting_ok=$NB9_PREEXISTING_OK"
fi

# NB10 (R-06) — a second identical bump exits 0, prints "BUMP-NOOP: already present", and leaves
# the whole file byte-identical (cmp against a copy taken before the SECOND call). Idempotent.
# plant: NB10 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | if [ "$_b_n" -eq 0 ]; then printf 'BUMP-NOOP: already present\n' return 0 fi | if [ "$_b_n" -eq 999 ]; then printf 'BUMP-NOOP: already present\\n' return 0 fi
cat >"$TMP/nb10.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/nb10-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in nb10.test.sh.
EOF
mkdir -p "$TMP/nb10-tests"
cat >"$TMP/nb10-tests/nb10.test.sh" <<'EOF'
# covers R-01, names the plan back: nb10-plan.md
EOF
: >"$TMP/nb10-baseline.tsv"
run_rows --bump --baseline "$TMP/nb10-baseline.tsv" --spec "$TMP/nb10.spec.md" --plan "$TMP/nb10-plan.md" --tests-root "$TMP/nb10-tests"
cp "$TMP/nb10-baseline.tsv" "$TMP/nb10-baseline-after-first.tsv"
run_rows --bump --baseline "$TMP/nb10-baseline.tsv" --spec "$TMP/nb10.spec.md" --plan "$TMP/nb10-plan.md" --tests-root "$TMP/nb10-tests"
if [ "$RC" -eq 0 ] && [ "$OUT" = "BUMP-NOOP: already present" ] && cmp -s "$TMP/nb10-baseline-after-first.tsv" "$TMP/nb10-baseline.tsv"; then
  ok "NB10 (--bump, R-06): a second identical bump exits 0, prints BUMP-NOOP: already present, and leaves the whole file byte-identical — idempotent"
else
  bad "NB10: expected the second bump to be a byte-identical no-op printing BUMP-NOOP: already present — got rc=$RC out=[$OUT]"
fi

# NB11 (R-04) — a baseline row for this pair says UNSCOPED while the computed verdict is COVERED:
# exit non-zero, the file byte-identical, output naming the id AND both verdicts. Four SEPARATE
# checks; a single combined if here would hide which half broke.
# plant: NB11 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | _b_conflict=1 fi done <"$_b_rowsfile" | _b_conflict=1 fi done </dev/null
cat >"$TMP/nb11.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/nb11-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in nb11.test.sh.
EOF
mkdir -p "$TMP/nb11-tests"
cat >"$TMP/nb11-tests/nb11.test.sh" <<'EOF'
# covers R-01, names the plan back: nb11-plan.md
EOF
printf 'nb11.spec.md%sR-01%sUNSCOPED\n' "$TAB" "$TAB" >"$TMP/nb11-baseline.tsv"
cp "$TMP/nb11-baseline.tsv" "$TMP/nb11-baseline-pre.tsv"
run_rows --bump --baseline "$TMP/nb11-baseline.tsv" --spec "$TMP/nb11.spec.md" --plan "$TMP/nb11-plan.md" --tests-root "$TMP/nb11-tests"
NB11_RC_OK=0; [ "$RC" -ne 0 ] && NB11_RC_OK=1
NB11_FILE_OK=0; cmp -s "$TMP/nb11-baseline-pre.tsv" "$TMP/nb11-baseline.tsv" && NB11_FILE_OK=1
NB11_COMBINED="$OUT $ERR"
NB11_ID_OK=0; printf '%s\n' "$NB11_COMBINED" | grep -q 'R-01' && NB11_ID_OK=1
NB11_VERDICTS_OK=0
if printf '%s\n' "$NB11_COMBINED" | grep -q 'UNSCOPED' && printf '%s\n' "$NB11_COMBINED" | grep -q 'COVERED'; then
  NB11_VERDICTS_OK=1
fi
if [ "$NB11_RC_OK" -eq 1 ] && [ "$NB11_FILE_OK" -eq 1 ] && [ "$NB11_ID_OK" -eq 1 ] && [ "$NB11_VERDICTS_OK" -eq 1 ]; then
  ok "NB11 (--bump, R-04): a baseline row saying UNSCOPED for a pair the checker now computes as COVERED — exit non-zero, file byte-identical, output names the id and both verdicts (four checks, not one combined)"
else
  bad "NB11: expected non-zero exit + byte-identical file + id R-01 named + both UNSCOPED and COVERED named — got rc=$RC rc_ok=$NB11_RC_OK file_ok=$NB11_FILE_OK id_ok=$NB11_ID_OK verdicts_ok=$NB11_VERDICTS_OK out=[$OUT] err=[$ERR]"
fi

# NB12 (R-01) — a SPEC declaring no ids: "BUMP-NOOP: SPEC declares no ids", exit 0, file
# byte-identical.
# plant: NB12 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | if [ ! -s "$_b_rowsfile" ]; then printf 'BUMP-NOOP: SPEC declares no ids\n' return 0 fi | if [ -s "$_b_rowsfile" ]; then printf 'BUMP-NOOP: SPEC declares no ids\\n' return 0 fi
cat >"$TMP/nb12.spec.md" <<'EOF'
## Success criteria
- [ ] Some criterion with no id at all.
EOF
: >"$TMP/nb12-plan.md"
mkdir -p "$TMP/nb12-tests"
printf 'other.spec.md%sR-09%sCOVERED\n' "$TAB" "$TAB" >"$TMP/nb12-baseline.tsv"
cp "$TMP/nb12-baseline.tsv" "$TMP/nb12-baseline-pre.tsv"
run_rows --bump --baseline "$TMP/nb12-baseline.tsv" --spec "$TMP/nb12.spec.md" --plan "$TMP/nb12-plan.md" --tests-root "$TMP/nb12-tests"
if [ "$RC" -eq 0 ] && [ "$OUT" = "BUMP-NOOP: SPEC declares no ids" ] && cmp -s "$TMP/nb12-baseline-pre.tsv" "$TMP/nb12-baseline.tsv"; then
  ok "NB12 (--bump, R-01): a SPEC declaring no ids — BUMP-NOOP: SPEC declares no ids, exit 0, file byte-identical"
else
  bad "NB12: expected exit 0 + stdout 'BUMP-NOOP: SPEC declares no ids' + byte-identical file — got rc=$RC out=[$OUT]"
fi

# NB13 (R-03, ADR-0166 §D6) — --baseline names a path that does not exist: "BUMP-NOOP: no baseline
# at <path>", exit 0, and the path STILL does not exist afterwards. A foreign project has no corpus
# baseline and must not acquire one.
# plant: NB13 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | if [ ! -f "$BASELINE" ]; then printf 'BUMP-NOOP: no baseline at %s\n' "$BASELINE" return 0 fi | if [ -f "$BASELINE" ]; then printf 'BUMP-NOOP: no baseline at %s\\n' "$BASELINE" return 0 fi
cat >"$TMP/nb13.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/nb13-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in nb13.test.sh.
EOF
mkdir -p "$TMP/nb13-tests"
cat >"$TMP/nb13-tests/nb13.test.sh" <<'EOF'
# covers R-01, names the plan back: nb13-plan.md
EOF
NB13_BASELINE="$TMP/nb13-no-such-baseline.tsv"
run_rows --bump --baseline "$NB13_BASELINE" --spec "$TMP/nb13.spec.md" --plan "$TMP/nb13-plan.md" --tests-root "$TMP/nb13-tests"
NB13_STILL_ABSENT=0; [ ! -e "$NB13_BASELINE" ] && NB13_STILL_ABSENT=1
if [ "$RC" -eq 0 ] && [ "$OUT" = "BUMP-NOOP: no baseline at $NB13_BASELINE" ] && [ "$NB13_STILL_ABSENT" -eq 1 ]; then
  ok "NB13 (--bump, R-03, ADR-0166 §D6): --baseline names a path that does not exist — BUMP-NOOP: no baseline at <path>, exit 0, and the path still does not exist afterwards"
else
  bad "NB13: expected exit 0 + 'BUMP-NOOP: no baseline at $NB13_BASELINE' + no file created — got rc=$RC out=[$OUT] still_absent=$NB13_STILL_ABSENT"
fi

# NB14 (R-03) — a baseline fixture whose last line carries NO trailing newline: after the bump the
# previously-last row is still its own line, not merged into the appended one (the append bug that
# corrupts two rows into one). Built with printf, no final \n.
# plant: NB14 | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | if [ -n "$_b_lastbyte" ]; then | if false; then
cat >"$TMP/nb14.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/nb14-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in nb14.test.sh.
EOF
mkdir -p "$TMP/nb14-tests"
cat >"$TMP/nb14-tests/nb14.test.sh" <<'EOF'
# covers R-01, names the plan back: nb14-plan.md
EOF
printf 'other.spec.md%sR-09%sCOVERED' "$TAB" "$TAB" >"$TMP/nb14-baseline.tsv"
run_rows --bump --baseline "$TMP/nb14-baseline.tsv" --spec "$TMP/nb14.spec.md" --plan "$TMP/nb14-plan.md" --tests-root "$TMP/nb14-tests"
NB14_OK=1
grep -qxF "other.spec.md${TAB}R-09${TAB}COVERED" "$TMP/nb14-baseline.tsv" || NB14_OK=0
grep -qxF "nb14.spec.md${TAB}R-01${TAB}COVERED" "$TMP/nb14-baseline.tsv" || NB14_OK=0
if [ "$RC" -eq 0 ] && [ "$NB14_OK" -eq 1 ]; then
  ok "NB14 (--bump, R-03): a baseline fixture whose last line carries no trailing newline — after the bump the previously-last row is still its own line, not merged into the appended one"
else
  bad "NB14: expected the pre-existing no-newline-terminated row and the new row to both be intact, separate lines — got rc=$RC file=[$(cat "$TMP/nb14-baseline.tsv" 2>/dev/null)]"
fi

# ==================================================================================================
# NB15-NB19 (R-01, R-05) — the SKILL.md wiring at Step 7.0b. Scoped extraction, not a whole-file
# grep: STEP70B is Step 7.0b's heading through (not including) Step 7.1's; BUMPBLOCK is the
# NARROWER range Task 5 actually inserts — Step 7.0b's heading through (not including) Step 7.0c's
# — used where a needle would otherwise also be satisfied by Step 7.0c's OWN, pre-existing and
# UNRELATED halt sentence ("...report and stop — do not invoke commit"), which already lives inside
# STEP70B today (rule 1: a needle must belong to the mechanism it asserts about, and to nothing
# else).
# ==================================================================================================
STEP70B="$TMP/step70b-block.txt"
awk '/^\*\*Step 7\.0b /{f=1} f && /^\*\*Step 7\.1 /{exit} f' "$CC_SKILL" >"$STEP70B" 2>/dev/null
BUMPBLOCK="$TMP/bump-block.txt"
awk '/^\*\*Step 7\.0b /{f=1} f && /^\*\*Step 7\.0c /{exit} f' "$CC_SKILL" >"$BUMPBLOCK" 2>/dev/null
STEP70B_FLAT=$(flatten "$STEP70B")
BUMPBLOCK_FLAT=$(flatten "$BUMPBLOCK")

# NB15 (R-05) — the fence-contract: c2c-step7-baseline-bump marker sits after the spec-archive.sh
# invocation and before the Step 7.0c heading, ORDERED BY LINE NUMBER (within the extracted
# Step 7.0b block), not merely by the three anchors' presence.
# plant: NB15 | plugin/skills/concept-to-code/SKILL.md | **Step 7.0c | **Step 7.9c
NB15_ARCHIVE_LN=$(grep -n 'skills/concept-to-code/scripts/spec-archive.sh "<project-root>"' "$STEP70B" 2>/dev/null | head -1 | cut -d: -f1)
NB15_FENCE_LN=$(grep -n 'fence-contract: c2c-step7-baseline-bump' "$STEP70B" 2>/dev/null | head -1 | cut -d: -f1)
NB15_STEP70C_LN=$(grep -n '^\*\*Step 7\.0c ' "$STEP70B" 2>/dev/null | head -1 | cut -d: -f1)
NB15_ARCHIVE_LN=${NB15_ARCHIVE_LN:-0}
NB15_FENCE_LN=${NB15_FENCE_LN:-0}
NB15_STEP70C_LN=${NB15_STEP70C_LN:-0}
if [ "$NB15_ARCHIVE_LN" -gt 0 ] && [ "$NB15_FENCE_LN" -gt "$NB15_ARCHIVE_LN" ] \
   && [ "$NB15_STEP70C_LN" -gt "$NB15_FENCE_LN" ]; then
  ok "NB15 (R-05): inside Step 7.0b, the fence-contract: c2c-step7-baseline-bump marker sits after the spec-archive.sh invocation and before the Step 7.0c heading, ordered by line number"
else
  bad "NB15: expected spec-archive.sh line < fence-contract line < Step 7.0c line inside the Step 7.0b block — got archive=$NB15_ARCHIVE_LN fence=$NB15_FENCE_LN step70c=$NB15_STEP70C_LN"
fi

# plant: NB16 | plugin/skills/concept-to-code/SKILL.md | <!-- fence-contract: c2c-step7-baseline-bump -->
# NB16 — THE EXECUTED PROOF. Extract the fence by its marker literal (own small extractor anchored
# on the marker, ADR-0086: never import a helper from another harness) and run it three times
# against fixture trees, with the caller-bound free variables Task 5 names in the invocation line
# (ARCHIVED_SPEC, PLAN, ROOT) exported, plus CLAUDE_PLUGIN_ROOT for the two-tier script lookup:
#   (a) a bumpable baseline               -> exit 0
#   (b) a conflicting baseline            -> non-zero
#   (c) CLAUDE_PLUGIN_ROOT at an empty tree, AND HOME overridden to a tree with no ~/.claude copy
#       either (the ONLY place in this file HOME is not the ambient one, declared in the file
#       header) -> non-zero
extract_fence() {
  # $1 = file to read, $2 = marker literal (verbatim, including the closing "-->"), $3 = output path.
  awk -v marker="$2" '
    index($0, marker) { armed=1; next }
    armed && /^```bash/ { infence=1; armed=0; next }
    infence && /^```/ { exit }
    infence { print }
  ' "$1" >"$3" 2>/dev/null
}
FENCE_MARKER='fence-contract: c2c-step7-baseline-bump -->'
FENCE_NB="$TMP/nb16-fence.sh"
extract_fence "$CC_SKILL" "$FENCE_MARKER" "$FENCE_NB"

mkdir -p "$TMP/nb16a-root/staging/plugin/scripts/tests" "$TMP/nb16a-root/nb16-tests"
: >"$TMP/nb16a-root/staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv"
cat >"$TMP/nb16a.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/nb16a-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in nb16a.test.sh.
EOF
cat >"$TMP/nb16a-root/nb16-tests/nb16a.test.sh" <<'EOF'
# covers R-01, names the plan back: nb16a-plan.md
EOF
( export ARCHIVED_SPEC="$TMP/nb16a.spec.md" PLAN="$TMP/nb16a-plan.md" ROOT="$TMP/nb16a-root" CLAUDE_PLUGIN_ROOT="$STAGING/plugin"
  bash "$FENCE_NB" >"$TMP/nb16a-out.txt" 2>"$TMP/nb16a-err.txt" )
NB16A_RC=$?
NB16A_OK=0; [ "$NB16A_RC" -eq 0 ] && NB16A_OK=1

mkdir -p "$TMP/nb16b-root/staging/plugin/scripts/tests" "$TMP/nb16b-root/nb16-tests"
printf 'nb16b.spec.md%sR-01%sUNSCOPED\n' "$TAB" "$TAB" >"$TMP/nb16b-root/staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv"
cat >"$TMP/nb16b.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
cat >"$TMP/nb16b-plan.md" <<'EOF'
### Task 1 -- do thing (R-01)
Test coverage lives in nb16b.test.sh.
EOF
cat >"$TMP/nb16b-root/nb16-tests/nb16b.test.sh" <<'EOF'
# covers R-01, names the plan back: nb16b-plan.md
EOF
( export ARCHIVED_SPEC="$TMP/nb16b.spec.md" PLAN="$TMP/nb16b-plan.md" ROOT="$TMP/nb16b-root" CLAUDE_PLUGIN_ROOT="$STAGING/plugin"
  bash "$FENCE_NB" >"$TMP/nb16b-out.txt" 2>"$TMP/nb16b-err.txt" )
NB16B_RC=$?
NB16B_OK=0; [ "$NB16B_RC" -ne 0 ] && NB16B_OK=1

mkdir -p "$TMP/nb16c-root/staging/plugin/scripts/tests" "$TMP/nb16c-empty-plugin" "$TMP/nb16c-empty-home"
: >"$TMP/nb16c-root/staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv"
cat >"$TMP/nb16c.spec.md" <<'EOF'
## Success criteria
- [ ] R-01 — first
EOF
: >"$TMP/nb16c-plan.md"
( export ARCHIVED_SPEC="$TMP/nb16c.spec.md" PLAN="$TMP/nb16c-plan.md" ROOT="$TMP/nb16c-root" CLAUDE_PLUGIN_ROOT="$TMP/nb16c-empty-plugin" HOME="$TMP/nb16c-empty-home"
  bash "$FENCE_NB" >"$TMP/nb16c-out.txt" 2>"$TMP/nb16c-err.txt" )
NB16C_RC=$?
NB16C_OK=0; [ "$NB16C_RC" -ne 0 ] && NB16C_OK=1

if [ "$NB16A_OK" -eq 1 ] && [ "$NB16B_OK" -eq 1 ] && [ "$NB16C_OK" -eq 1 ]; then
  ok "NB16 (the executed proof): the Step 7.0b fence, extracted by its fence-contract: c2c-step7-baseline-bump --> marker and run for real — (a) bumpable baseline exit 0, (b) conflicting baseline exit non-zero, (c) CLAUDE_PLUGIN_ROOT at an empty tree with no \$HOME/.claude copy either, exit non-zero"
else
  bad "NB16: expected (a) exit 0, (b) non-zero, (c) non-zero from the extracted fence — got a_rc=$NB16A_RC(ok=$NB16A_OK) b_rc=$NB16B_RC(ok=$NB16B_OK) c_rc=$NB16C_RC(ok=$NB16C_OK)"
fi

# NB17 (R-05, rule 3) — Step 7.0b's OWN bump prose (BUMPBLOCK, which excludes Step 7.0c's unrelated
# halt sentence) states that a non-zero bump halts before the commit invocation and prints the
# script's stderr verbatim. Flattened, undecorated, case-insensitive match; the needle is the
# co-occurrence of both phrases, which rule 1 requires so Step 7.0c's own, differently-worded halt
# sentence ("report and stop — do not invoke commit", no stderr-verbatim mention) cannot satisfy it
# even if it leaked into scope.
# plant: NB17 | plugin/skills/concept-to-code/SKILL.md | Print the script's stderr verbatim and name the file a human must look at.
if printf '%s' "$BUMPBLOCK_FLAT" | grep -qF 'do not invoke commit' \
   && printf '%s' "$BUMPBLOCK_FLAT" | grep -qF "the script's stderr verbatim"; then
  ok "NB17 (R-05, rule 3): Step 7.0b's own bump paragraph states, in a flattened/undecorated/case-insensitive match confined to the bump's own block, that a non-zero bump halts before the commit invocation and prints the script's stderr verbatim"
else
  bad "NB17: expected the bump block (Step 7.0b, before the Step 7.0c heading) to state 'do not invoke commit' and \"the script's stderr verbatim\" — got flat=[$BUMPBLOCK_FLAT]"
fi

# NB18 (R-01, rule 3) — Step 7.0b's commit invocation --include list names the baseline path
# alongside the archived SPEC and the manifest. Same flattened match, over the wider STEP70B range
# (the commit invocation sits after Step 7.0c's own subsection, not inside BUMPBLOCK).
# plant: NB18 | plugin/skills/concept-to-code/SKILL.md | <manifest-path>[,<baseline-path>
if printf '%s' "$STEP70B_FLAT" | grep -qF -- '--include' \
   && printf '%s' "$STEP70B_FLAT" | grep -qF 'archived-spec-path' \
   && printf '%s' "$STEP70B_FLAT" | grep -qF 'baseline-path'; then
  ok "NB18 (R-01, rule 3): Step 7.0b's commit invocation --include list names the baseline path alongside the archived SPEC and the manifest (flattened, undecorated match)"
else
  bad "NB18: expected the commit invocation's --include list to name a baseline-path placeholder alongside archived-spec-path — got flat=[$STEP70B_FLAT]"
fi

# NB19 (R-01, rule 17) — THE PRODUCER AND THE CONSUMER MEET. The baseline path the Step 7.0b fence
# passes to --baseline, resolved against the repo root, is EXACTLY
# staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv, AND that file exists. Stops
# ADR-0166 §D6's absent-baseline no-op from swallowing a typo in this repository's own SKILL.md.
# plant: NB19 | plugin/skills/concept-to-code/SKILL.md | _baseline="$ROOT/staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv" | _baseline="$ROOT/staging/plugin/scripts/tests/plan-shape-baseline.tsv"
NB19_PATH='staging/plugin/scripts/tests/spec-coverage-scope-baseline.tsv'
NB19_NAMED=0
grep -qF "$NB19_PATH" "$BUMPBLOCK" 2>/dev/null && NB19_NAMED=1
NB19_EXISTS=0
[ -f "$REPO/$NB19_PATH" ] && NB19_EXISTS=1
if [ "$NB19_NAMED" -eq 1 ] && [ "$NB19_EXISTS" -eq 1 ]; then
  ok "NB19 (R-01, rule 17): the Step 7.0b fence's --baseline path resolves, against the repo root, to exactly $NB19_PATH, and that file exists — the producer and the consumer meet"
else
  bad "NB19: expected $NB19_PATH to be named inside the bump block AND to exist at \$REPO/$NB19_PATH — named=$NB19_NAMED exists=$NB19_EXISTS"
fi

# ==================================================================================================
# NB20-NB21 (R-01) — deployment and CI. Nothing else in CI can catch a missing PAIRS entry for a
# plugin/skills/*/scripts/ helper (ADR-0024 scope excludes it from pairs-completeness.test.sh's
# check_complete), the same gap RG2 already documents for spec-coverage.sh itself.
# ==================================================================================================

# NB20 — sync-to-claude.sh's PAIRS block contains the exact spec-coverage-baseline-rows.sh entry.
# Same extraction + exact-line-match idiom RG2 already uses.
# plant: NB20 | sync-to-claude.sh | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh|skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh | plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh|skills/concept-to-code/scripts/spec-coverage-baseline-rows-WRONG.sh
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" >"$TMP/nb20-pairs.txt" 2>/dev/null
NB20_NEEDLE='plugin/skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh|skills/concept-to-code/scripts/spec-coverage-baseline-rows.sh'
if grep -qxF "$NB20_NEEDLE" "$TMP/nb20-pairs.txt"; then
  ok "NB20: sync-to-claude.sh's PAIRS block contains the exact spec-coverage-baseline-rows.sh entry"
else
  bad "NB20: PAIRS is missing the exact line $NB20_NEEDLE"
fi

# NB21 — docs-ci.yml's shell-tests loop contains spec-coverage-baseline-bump as a WHOLE token.
# Same anchored form RG1 already uses — an unanchored match would be satisfied by "spec-coverage"
# alone.
#
# NB21 has no plant: UNPLANTABLE BY CLASS, but a different class than NB1/RS0's existence-check
# shape. `.github/workflows/docs-ci.yml` is copied into plant-check.sh's sandbox for tests to READ
# (build_sandbox copies `$REPO/.github`) but is explicitly refused as a plant TARGET — verified by
# reading plant-check.sh itself (its `--require-legs` block, issue #447/ADR-0151 §D7): "`.github/`
# is copied into the sandbox for tests to READ but is not a legal plant TARGET: logic that lives
# only in yaml can be asserted to exist and never to work (rule 16)." Its TARGET-resolution `case`
# only accepts a staging-relative path or a literal `../docs/` prefix (issue #339); `.github/...` is
# neither, and would be refused as `'..' is allowed only as the literal ../docs/ prefix`. RG1 in
# recovery-preflight.test.sh, the precedent this assertion's anchored form is copied from, is
# likewise unplanted for the same reason — confirmed 2026-08-23 by grep, no `# plant: RG1` exists
# anywhere in the corpus. This is CLAUDE.md rule 16's "instruction, not enforcement" territory: NB21
# is enforced BY EXECUTION (docs-ci.yml really does or does not run this harness), just not provable
# via a mutation plant-check.sh is able to run.
NB21_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$NB21_LOOP" | grep -qE '[[:space:]]spec-coverage-baseline-bump[[:space:];]'; then
  ok "NB21: docs-ci.yml's shell-tests loop list runs spec-coverage-baseline-bump"
else
  bad "NB21: spec-coverage-baseline-bump is not in docs-ci.yml's explicit harness list"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
