#!/bin/bash
# diff-budget-scope.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash diff-budget-scope.test.sh
#
# Covers issue #106 / ADR-0052: a per-task diff budget (expected files + an approximate line
# ceiling) declared optionally on a plan task line, checked at the existing Step 5 checkpoints
# against `git diff --stat`, plus a whole-plan out-of-scope file check.
#
# ASSERTION LABELS ARE B-PREFIXED (BA1, BD3, BG2, ...) to stay distinguishable from every other
# harness printing into the same CI shell-tests job (R-, H-, W-, ...).
#
# THE SCRIPT UNDER TEST IS A REPORTER (ADR-0052, matching weakening-scan.sh at the same Step 5
# checkpoint), NOT spec-coverage.sh in the same directory (a CHECKER with an exit-code contract).
# Always exits 0. Signals through stdout only, CLEAN sentinel when there is nothing. Do not copy
# spec-coverage.sh's branch-on-exit-code idiom into this file's assertions — ADR-0048 §D7 already
# had to write that sentence once (see BT section below, which restates the trap explicitly).
#
# BACKWARD COMPATIBILITY IS THE HARD GATE (ADR-0052 §D1, plan risk flag 2). Section BB runs
# against the REAL corpus in docs/superpowers/plans/ (42 files at the time this was written,
# none of which carry a budget) with a >= 5 count guard against a vacuous loop — the
# pairs-completeness.test.sh self-test-2 lesson, reapplied.
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL and no fixture path contains "secret",
# "credential", ".env", ".pem", or ".key" — secret-dep-gate.test.sh section D scans this
# repository's tracked files as its false-positive corpus.
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

DBC="$STAGING/plugin/skills/concept-to-code/scripts/diff-budget-check.sh"

# ==================================================================================================
# B0. The anchor every B assertion below depends on.
# ==================================================================================================
if [ -f "$DBC" ] && [ -r "$DBC" ]; then
  ok "B0: diff-budget-check.sh exists and is readable at the expected path"
else
  bad "B0: $DBC not found or unreadable — every B assertion below is meaningless"
fi

# --- fixture helper: build a throwaway git repo under $TMP/<name>, baseline-commit, then create
# the given "<path>:<linecount>" files as new (uncommitted) additions, and print `git diff --stat
# HEAD`. A fresh repo per call — no state bleed between assertions. ---
mk_diffstat() {
  _name="$1"; shift
  _repo="$TMP/repo_$_name"
  rm -rf "$_repo"; mkdir -p "$_repo"
  ( cd "$_repo" && git init -q \
      && git -c user.name=t -c user.email=t@t.com -c commit.gpgsign=false commit -q -m baseline --allow-empty )
  for _spec in "$@"; do
    _f="${_spec%%:*}"; _n="${_spec#*:}"
    _fdir=$(dirname "$_repo/$_f")
    mkdir -p "$_fdir"
    : > "$_repo/$_f"
    _i=0
    while [ "$_i" -lt "$_n" ]; do printf 'line %s\n' "$_i" >> "$_repo/$_f"; _i=$((_i+1)); done
  done
  ( cd "$_repo" && git add -A >/dev/null 2>&1 && git diff --stat HEAD )
}

run_dbc() { OUT=$(bash "$DBC" "$@" 2>"$TMP/err" <"$TMP/stat_in"); RC=$?; ERR=$(cat "$TMP/err" 2>/dev/null); }

# ==================================================================================================
# BT. Reporter trap, restated at the call site (ADR-0052 hard constraint, ADR-0048 §D7 precedent).
# Never `[ -n "$out" ]` — true even on CLEAN. Never `grep -c ... || echo 0` — the two-line 0\n0 bug.
# ==================================================================================================
if [ -f "$DBC" ]; then
  bt_out=$(printf '' | bash "$DBC" --plan "$TMP/does-not-exist.md" --tasks 1 2>/dev/null); bt_rc=$?
  if [ "$bt_out" = "CLEAN" ] && [ "$bt_rc" -eq 0 ]; then
    ok "BT1: a missing --plan file still prints the sentinel CLEAN and exits 0 (fail-open, reporter contract)"
  else
    bad "BT1: expected CLEAN/exit 0 on a missing --plan — got out=[$bt_out] rc=$bt_rc"
  fi
  if [ -n "$bt_out" ]; then
    ok "BT2: [ -n \"\$out\" ] is TRUE even on a bare CLEAN — a caller must never use it to decide whether something was found"
  else
    bad "BT2: expected \$bt_out to be non-empty (it is the literal string CLEAN)"
  fi
fi

# ==================================================================================================
# BA. Budget parsing + the over/under verdict, correct at the boundary.
# ==================================================================================================
cat >"$TMP/ba1-plan.md" <<'EOF'
# Plan

- [ ] **Task 1 — thing.** Budget: a.py (~10 lines)
EOF
mk_diffstat ba1 "a.py:10" >"$TMP/stat_in"
run_dbc --plan "$TMP/ba1-plan.md" --tasks 1
if [ "$OUT" = "CLEAN" ] && [ "$RC" -eq 0 ]; then
  ok "BA1: actual lines == budgeted lines (10 == 10) -> CLEAN, no overshoot at the exact boundary"
else
  bad "BA1: expected CLEAN at the exact boundary — got out=[$OUT] rc=$RC"
fi

mk_diffstat ba2 "a.py:11" >"$TMP/stat_in"
run_dbc --plan "$TMP/ba1-plan.md" --tasks 1
if printf '%s\n' "$OUT" | grep -q "^BUDGET${TAB}1${TAB}"; then
  ok "BA2: actual lines == budget + 1 (11 vs 10) -> a BUDGET line fires, one line past the boundary"
else
  bad "BA2: expected a BUDGET line one line past the boundary — got out=[$OUT]"
fi

if printf '%s\n' "$OUT" | grep -qE "^BUDGET${TAB}1${TAB}files=1/1${TAB}lines=10/11${TAB}margin=1$"; then
  ok "BA3: the BUDGET line names files=<expected>/<actual>, lines=<expected>/<actual>, and margin=1"
else
  bad "BA3: the BUDGET line does not show the expected files=1/1 lines=10/11 margin=1 shape — got out=[$OUT]"
fi

cat >"$TMP/ba4-plan.md" <<'EOF'
# Plan

- [ ] **Task 1 — thing.** Budget: a.py (~100 lines)
- [ ] **Task 2 — other.** Budget: b.py (~50 lines)
EOF
mk_diffstat ba4 "a.py:5" "b.py:2" >"$TMP/stat_in"
run_dbc --plan "$TMP/ba4-plan.md" --tasks 1
if printf '%s\n' "$OUT" | grep -q "^BUDGET${TAB}1${TAB}"; then
  ok "BA4: files_actual (2, both globally in-scope) exceeds files_expected (1, Task 1's own declared count) even though lines are far under budget — a files-only overshoot still fires, and b.py is legitimately in-scope (declared by Task 2) so this is NOT the SCOPE case BD tests"
else
  bad "BA4: expected a BUDGET line for a files-only overshoot — got out=[$OUT]"
fi

mk_diffstat ba5 "a.py:5" >"$TMP/stat_in"
run_dbc --plan "$TMP/ba4-plan.md" --tasks 1
if [ "$OUT" = "CLEAN" ]; then
  ok "BA5: files_actual == files_expected (1 == 1) and lines well under -> CLEAN, the files boundary is exact too"
else
  bad "BA5: expected CLEAN at the exact files boundary — got out=[$OUT]"
fi

# ==================================================================================================
# BB. Absent budget is fully inert (the backward-compatibility hard gate, ADR-0052 §D1).
# ==================================================================================================
cat >"$TMP/bb1-plan.md" <<'EOF'
# Plan

- [ ] **Task 1 — thing.** No budget declared here at all.
EOF
mk_diffstat bb1 "z.py:500" "w.py:9" >"$TMP/stat_in"
run_dbc --plan "$TMP/bb1-plan.md" --tasks 1
if [ "$OUT" = "CLEAN" ] && [ "$RC" -eq 0 ]; then
  ok "BB1: a plan with no Budget: line anywhere -> CLEAN regardless of diff size (no BUDGET, no SCOPE)"
else
  bad "BB1: expected CLEAN on a fully budget-less plan — got out=[$OUT] rc=$RC"
fi

# AMENDED for issue #184 / ADR-0070. This loop used to include EVERY plan, and passed — because the
# check was inert. A plan that declares a budget is not "legacy" and must NOT stay silent when a
# diff touches a file outside its declared set; asserting otherwise pinned the defect as the
# contract and would have blocked the fix. BB2's intent (a plan declaring nothing stays silent) is
# unchanged; its population is corrected. BJ1/BJ2 below assert the excluded plan DOES respond, so
# the exclusion cannot quietly become a hole.
bb2_count=0; bb2_bad=0; bb2_skipped=0
for f in "$REPO"/docs/superpowers/plans/*.md; do
  if grep -q '[Bb]udget:' "$f" 2>/dev/null; then bb2_skipped=$((bb2_skipped + 1)); continue; fi
  bb2_count=$((bb2_count + 1))
  mk_diffstat "bb2_$bb2_count" "some/random/touched/file_$bb2_count.py:37" >"$TMP/stat_in"
  o=$(bash "$DBC" --plan "$f" --tasks 1 2>"$TMP/bb2err" <"$TMP/stat_in")
  r=$?
  e=$(cat "$TMP/bb2err" 2>/dev/null)
  if [ "$r" -eq 0 ] && [ "$o" = "CLEAN" ] && [ -z "$e" ]; then
    :
  else
    bb2_bad=$((bb2_bad + 1))
    bad "BB2: $f did NOT pass silently — rc=$r out=[$o] err=[$e]"
  fi
done
if [ "$bb2_bad" -eq 0 ]; then
  ok "BB2: every budget-free plan in the real corpus stays genuinely silent (CLEAN, exit 0, empty stderr); $bb2_skipped budget-declaring plan(s) excluded and covered by BJ1/BJ2"
fi
# The exclusion must stay small and must actually have a subject — if it ever covers most of the
# corpus, or none of it, BB2 has stopped measuring what it claims.
# RAISED 5 -> 6 on 2026-08-03, and this is that decision. Issue #289's plan declares seven
# per-task budgets, making it the fifth plan with a real declaration; the sixth match is
# `2026-05-20-vibe-status-skill.md`, which ADR-0091 already records as a known false positive of
# this loose substring predicate (`# Performance budget: <10s typical…`, a comment inside a fenced
# code block, not a declaration). 6 of 61 plans is still ~10% — the exclusion is small and BB2
# still measures what it claims.
#
# RAISED 7 -> 8, the THIRD firing in one session. Three consecutive healthy features have each
# hand-raised this ceiling (5->6->7->8) purely for declaring budgets — the behaviour the budget
# feature exists to encourage. Three data points is no longer 'evidence against the choice', it is
# a mechanism that costs a red test per feature and prompts nobody to look at anything. A
# proportional bound needs its own issue; a fourth hand-edit is not the answer.
#
# RAISED 6 -> 7 the same day, and the repetition is the finding. Issue #290's plan declared budgets
# too, so this ceiling fired TWICE in one session, on two consecutive healthy features. An absolute
# ceiling makes every plan that declares a budget — the behaviour the budget feature exists to
# encourage — a red test that a human must hand-edit. The comment below called a proportional bound
# "the alternative, deliberately not taken"; two firings in a day is evidence against that choice,
# recorded here so the next reader has the data rather than the reasoning alone.
#
# Still absolute, because changing the mechanism is a design decision and not something to slip into
# a red-fixing edit. What the bound is FOR is unchanged: catching an exclusion that has grown to
# cover most of the corpus, or shrunk to cover none. 7 of 62 is ~11%.
#
# RAISED 8 -> 9 on 2026-08-04 by the #292 chain, and this is the FOURTH hand-raise. It fired for the
# same reason as the previous three: #292's own plan declares budgets, so a healthy feature turned
# this red simply by being planned the way ADR-0052 asks. 9 of 64 is ~14%.
#
# The mechanism is deliberately NOT changed here, for the reason the paragraph above already gives.
# What HAS changed since ADR-0122 wrote "a fourth hand-edit is not the answer" is that the issue it
# asked for now exists and is scheduled: #358, with its SPEC written and committed. That is the fix;
# this line is an interim unblock and should be deleted by it, not raised a fifth time.
#
# RESOLVED by issue #358 on 2026-08-06, and the five hand-raises above are kept as the evidence
# that produced this shape rather than deleted (#358 R-06). The ceiling fired a FIFTH time, on
# #365's plan, for the same reason as the four before it: a healthy feature declared budgets, which
# is the behaviour ADR-0052 exists to encourage. Five consecutive false positives on five healthy
# features is not a bound, it is a tax with a red light attached.
#
# THE SHAPE, and why it is not another number (#358 R-01/R-05). Every paragraph above states what
# the bound is FOR in the same words: catching an exclusion that has grown to cover MOST of the
# corpus, or shrunk to cover NONE. That is a property, and the absolute count was only ever a proxy
# for it — a proxy that had to be re-fitted by hand every time the corpus grew. The property is now
# asserted directly: non-empty, and a strict minority of the corpus. It needs no maintenance and
# introduces no new literal, because there is nothing left to tune.
#
# The cost, stated rather than discovered later: this accepts strictly more inputs than the
# ceiling did — an exclusion may now drift from 15% to 49% with nothing going red. That looseness
# is bounded by evidence rather than by trust: `bb2b_in_band` is extracted precisely so BB2c/BB2d
# can exercise the REJECTING half with synthetic values, and BB2e pins the accepting half beside
# them, because a negative assertion pins nothing without its positive twin. A percentage band
# (<= 33%) was rejected for re-introducing exactly the unexplained literal this removes, and a
# committed baseline file for relocating the per-feature hand-edit rather than removing it — the
# SPEC's own R-05 names its silent-rot risk.
bb2b_in_band() {
  [ "${1:-0}" -ge 1 ] || return 1
  [ $(( ${1:-0} * 2 )) -lt "${2:-0}" ] || return 1
  return 0
}
bb2_corpus=$(( bb2_count + bb2_skipped ))
# plant: BB2b | plugin/scripts/tests/diff-budget-scope.test.sh | bb2b_in_band "$bb2_skipped" "$bb2_corpus" | bb2b_in_band 0 "$bb2_corpus"
if bb2b_in_band "$bb2_skipped" "$bb2_corpus"; then
  ok "BB2b: the budget-declaring exclusion covers $bb2_skipped of $bb2_corpus plan(s) — non-empty and a strict minority"
else
  bad "BB2b: $bb2_skipped of $bb2_corpus plan(s) excluded from BB2 — the exclusion covers none, or most, so BB2 no longer measures what it claims"
fi
# plant: BB2c | plugin/scripts/tests/diff-budget-scope.test.sh | [ "${1:-0}" -ge 1 ] || return 1 | [ "${1:-0}" -ge 0 ] || return 1
if bb2b_in_band 0 65; then
  bad "BB2c: the bound accepted an exclusion covering NONE of the corpus (0 of 65) — #358 R-03"
else
  ok "BB2c: the bound rejects an exclusion covering none of the corpus (0 of 65)"
fi
# plant: BB2d | plugin/scripts/tests/diff-budget-scope.test.sh | [ $(( ${1:-0} * 2 )) -lt "${2:-0}" ] || return 1 | [ $(( ${1:-0} * 1 )) -lt "${2:-0}" ] || return 1
if bb2b_in_band 33 65; then
  bad "BB2d: the bound accepted an exclusion covering MOST of the corpus (33 of 65) — #358 R-02"
else
  ok "BB2d: the bound rejects an exclusion covering most of the corpus (33 of 65)"
fi
# BB2e is BB2d's positive twin. Without it, a bound that rejects EVERYTHING satisfies BB2c and BB2d
# and pins nothing — the rule ADR-0039 earned and this file must not relearn.
# plant: BB2e | plugin/scripts/tests/diff-budget-scope.test.sh | [ $(( ${1:-0} * 2 )) -lt "${2:-0}" ] || return 1 | [ $(( ${1:-0} * 3 )) -lt "${2:-0}" ] || return 1
if bb2b_in_band 32 65; then
  ok "BB2e: the bound still accepts a large-but-minority exclusion (32 of 65) — it bounds 'most', not 'many'"
else
  bad "BB2e: the bound rejected 32 of 65, a strict minority — the band is tighter than the property it claims"
fi
if [ "$bb2_count" -ge 5 ]; then
  ok "BB3: the BB2 corpus loop visited $bb2_count files (>= 5) — not a vacuous pass"
else
  bad "BB3: the BB2 corpus loop visited only $bb2_count files (< 5) — a glob matching almost nothing would read as full coverage"
fi

# ==================================================================================================
# BC. An unparseable budget is treated as absent, never as zero.
# ==================================================================================================
cat >"$TMP/bc1-plan.md" <<'EOF'
# Plan

- [ ] **Task 1 — thing.** Budget: x.py (no number here)
- [ ] **Task 2 — other.** Budget: y.py (~10 lines)
EOF
mk_diffstat bc1 "x.py:500" >"$TMP/stat_in"
run_dbc --plan "$TMP/bc1-plan.md" --tasks 1
if ! printf '%s\n' "$OUT" | grep -q '^BUDGET'; then
  ok "BC1: a malformed Budget: line (no parseable line ceiling) never produces a BUDGET finding, even on a 500-line diff — a naive zero-default would have fired here"
else
  bad "BC1: a malformed budget produced a BUDGET line — it must be treated as absent, never as zero (got out=[$OUT])"
fi

# ==================================================================================================
# BD. Out-of-scope files are their own finding type, distinct from an overshoot.
# ==================================================================================================
cat >"$TMP/bd1-plan.md" <<'EOF'
# Plan

- [ ] **Task 1 — thing.** Budget: a.py (~1000 lines)
EOF
mk_diffstat bd1 "a.py:3" "b.py:3" >"$TMP/stat_in"
run_dbc --plan "$TMP/bd1-plan.md" --tasks 1
if printf '%s\n' "$OUT" | grep -q "^SCOPE${TAB}b.py$"; then
  ok "BD1: b.py, touched but declared by no task in the plan, produces a SCOPE finding"
else
  bad "BD1: expected a SCOPE finding for the undeclared file b.py — got out=[$OUT]"
fi
if printf '%s\n' "$OUT" | grep -q '^BUDGET'; then
  bad "BD2: an out-of-scope file must not also be folded into a BUDGET overshoot line (ADR-0052 §D4) — got out=[$OUT]"
else
  ok "BD2: no BUDGET line accompanies the SCOPE finding (well under the 1000-line budget) — the two finding types stay separate"
fi
if printf '%s\n' "$OUT" | grep -q "^SCOPE${TAB}a.py$"; then
  bad "BD3: a.py IS declared by Task 1 and must never be reported as out-of-scope"
else
  ok "BD3: a.py (declared) produces no SCOPE finding"
fi

# ==================================================================================================
# BE. The §D4 exclusions: manifest, step5-report.json, SPEC.md, an explicit plan-level scope:.
# ==================================================================================================
cat >"$TMP/be1-plan.md" <<'EOF'
# Plan

Scope: cross/cutting/*.md

- [ ] **Task 1 — thing.** Budget: a.py (~1000 lines)
EOF
mk_diffstat be1 "a.py:3" "SPEC.md:3" "step5-report.json:3" "docs/manifests/2026-01-01-x.manifest.yml:3" "cross/cutting/note.md:3" >"$TMP/stat_in"
run_dbc --plan "$TMP/be1-plan.md" --tasks 1
if printf '%s\n' "$OUT" | grep -q '^SCOPE'; then
  bad "BE1: SPEC.md, step5-report.json, a *.manifest.yml, and a Scope:-matched file must ALL be excluded — got a SCOPE line: out=[$OUT]"
else
  ok "BE1: SPEC.md, step5-report.json, the manifest, and the Scope:-declared cross-cutting file are all excluded from the out-of-scope check"
fi

# ==================================================================================================
# BF. budget_findings in the step5-report.json schema block (concept-to-code/SKILL.md, Step 5).
# ==================================================================================================
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
STEP5_REF="$STAGING/plugin/skills/concept-to-code/references/step5-implementation.md"
STEP5="$TMP/cc_step5.txt"
# The Step 5 range moved to references/step5-implementation.md (VCS-047, ADR-0174); the
# reference file's body IS the block, so no awk range is needed any more.
cp "$STEP5_REF" "$STEP5" 2>/dev/null
GATES="$TMP/cc_gates.txt"
awk '/^## 5\. HITL gates/{f=1} /^## 6\. Coexistence invariants/{f=0} f' "$CC" >"$GATES"

if [ -s "$STEP5" ] && [ -s "$GATES" ]; then
  ok "BF0: both extraction anchors (Step 5, ## 5. HITL gates) are non-empty"
else
  bad "BF0: could not extract Step 5 and/or ## 5. HITL gates from $CC — BF/BG assertions below are meaningless"
fi

if grep -qF '"budget_findings"' "$STEP5"; then
  ok "BF1: the step5-report.json schema block in Step 5 contains \"budget_findings\""
else
  bad "BF1: \"budget_findings\" missing from the Step 5 schema block"
fi

if grep -F -A6 '"budget_findings"' "$STEP5" | grep -q '"task"' \
   && grep -F -A6 '"budget_findings"' "$STEP5" | grep -q '"files_expected"' \
   && grep -F -A6 '"budget_findings"' "$STEP5" | grep -q '"lines_expected"' \
   && grep -F -A6 '"budget_findings"' "$STEP5" | grep -q '"out_of_scope"'; then
  ok "BF2: the schema shows task, files_expected, lines_expected and out_of_scope near budget_findings"
else
  bad "BF2: the schema does not show the expected record shape near budget_findings"
fi

if grep -qF 'budget_findings' "$STEP5" && grep -qi 'advisory' "$STEP5" \
   && grep -qF 'never a failure signal' "$STEP5"; then
  ok "BF3: Step 5 states budget_findings is advisory and never a failure signal"
else
  bad "BF3: Step 5 is missing the budget_findings advisory/never-a-failure-signal statement"
fi

# ==================================================================================================
# BG. The §D5 roll-up: a single line when all six advisory arrays are empty, and a top-N cap with a
# remainder count on budget_findings. This is the point of the feature (plan risk flag 1).
# ==================================================================================================
if grep -qi 'all six' "$GATES" || grep -qi 'six advisory' "$GATES"; then
  ok "BG1: the Gate 5 block names the six-array roll-up explicitly (not a silent count)"
else
  bad "BG1: Gate 5 does not name the six-array roll-up (ADR-0052 §D5)"
fi

if grep -qi 'roll-up' "$GATES" || grep -qi 'rollup' "$GATES"; then
  ok "BG2: Gate 5 uses the term roll-up for the collapsed all-clear line"
else
  bad "BG2: Gate 5 does not mention a roll-up line for the all-clear case"
fi

if grep -qi 'top' "$GATES" && grep -qi 'remainder' "$GATES" && grep -qF 'budget_findings' "$GATES"; then
  ok "BG3: Gate 5 states budget_findings is capped at the top N by margin with a remainder count"
else
  bad "BG3: Gate 5 is missing the top-N-by-margin / remainder-count statement for budget_findings"
fi

# Six named arrays must all still be readable from the schema block — a forward guard proving this
# feature did not silently drop one of the five pre-existing arrays while adding its own.
BG4_MISSING=""
for _arr in weakening_findings requirement_coverage checkpoint_reviews tests_written_by suspect_findings budget_findings; do
  grep -qF "\"$_arr\"" "$STEP5" 2>/dev/null || grep -qF "$_arr" "$STEP5" 2>/dev/null || BG4_MISSING="$BG4_MISSING $_arr"
done
if [ -z "$BG4_MISSING" ]; then
  ok "BG4: all six advisory-schema names are present in the Step 5 schema block (weakening_findings, requirement_coverage, checkpoint_reviews, tests_written_by, suspect_findings, budget_findings)"
else
  bad "BG4: missing from the Step 5 schema block:$BG4_MISSING"
fi

# ==================================================================================================
# BH. Registration in both CI registries, plus the PAIRS deployment entry (Task 6).
# ==================================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]diff-budget-scope[[:space:];]'; then
  ok "BH1: docs-ci.yml's shell-tests loop list runs diff-budget-scope"
else
  bad "BH1: diff-budget-scope is not in docs-ci.yml's explicit harness list — append it after reward-hack-detectors"
fi

CI_YML="$REPO/.github/workflows/ci.yml"
if [ -f "$CI_YML" ] && grep -qE 'tests/\*\.test\.sh|scripts/tests' "$CI_YML"; then
  ok "BH2: ci.yml discovers *.test.sh via a glob (automatic registration, no per-file edit needed)"
else
  bad "BH2: ci.yml does not appear to glob staging/plugin/scripts/tests/*.test.sh — check the workflow"
fi

SYNCSH="$STAGING/sync-to-claude.sh"
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" >"$TMP/pairs"
if grep -qxF 'plugin/skills/concept-to-code/scripts/diff-budget-check.sh|skills/concept-to-code/scripts/diff-budget-check.sh' "$TMP/pairs"; then
  ok "BH3: PAIRS deploys diff-budget-check.sh to ~/.claude/skills/concept-to-code/scripts/, following spec-coverage.sh's exact registration"
else
  bad "BH3: the diff-budget-check.sh PAIRS entry is missing — pairs-completeness.test.sh cannot catch this, its check_complete does not cover plugin/skills/*/scripts/"
fi

if grep -q 'diff-budget-scope.test' "$TMP/pairs"; then
  bad "BH4: PAIRS gained an entry for this harness — test files do not deploy (spec-coverage.test.sh precedent, ADR-0048 §D11)"
else
  ok "BH4: no PAIRS entry for diff-budget-scope.test.sh (harnesses do not deploy)"
fi

# ==================================================================================================
# BJ. Issue #184 / ADR-0070 — the check had NEVER fired on a real plan.
#
# Its private predicate needed `- [ ] **Task N` (18 of 57 plans), and the one plan in the corpus
# that declares a Budget: is heading-form, so it produced no task block and no attribution. Two
# defects, both required: the predicate, and a paren group demanded at strict end-of-line while the
# real plan wraps the whole declaration in markdown italics.
#
# THESE ASSERTIONS RUN AGAINST THE REAL CORPUS, not a fixture, because a fixture written by the
# same hand that wrote the parser is what let this survive: every existing BA-BE fixture below uses
# the strict form, so the harness was green while the feature was inert.
# ==================================================================================================
BJ_PLAN="$REPO/docs/superpowers/plans/2026-07-28-176-worktree-isolation-contract.md"
if [ ! -f "$BJ_PLAN" ]; then
  bad "BJ0: $BJ_PLAN not found — BJ1..BJ3 are meaningless (if the plan was renamed, repoint them)"
else
  ok "BJ0: the real heading-form, budget-declaring plan is present"

  # Within the declared budget and scope: still CLEAN. NEITHER of BJ1/BJ2 is evidence on its own,
  # in either direction: verified against the pre-fix script, BJ1 passes there too — an inert
  # parser prints CLEAN for everything — while a parser that fired on everything would satisfy BJ2.
  # Only the pair distinguishes a working check from a broken one in both directions.
  mk_diffstat bj1 "staging/plugin/scripts/tests/worktree-isolation-contract.test.sh:100" ".github/workflows/docs-ci.yml:2" >"$TMP/stat_in"
  BJ1_OUT=$(bash "$DBC" --plan "$BJ_PLAN" --tasks 2 <"$TMP/stat_in")
  [ "$BJ1_OUT" = "CLEAN" ] \
    && ok "BJ1: a diff inside task 2's declared budget and scope is CLEAN" \
    || bad "BJ1: expected CLEAN on an in-budget diff, got [$BJ1_OUT]"

  # Over the line ceiling and outside the declared file set: both signals fire.
  mk_diffstat bj2 "staging/plugin/scripts/tests/worktree-isolation-contract.test.sh:900" "src/unrelated.py:40" >"$TMP/stat_in"
  BJ2_OUT=$(bash "$DBC" --plan "$BJ_PLAN" --tasks 2 <"$TMP/stat_in")
  { printf '%s\n' "$BJ2_OUT" | grep -q '^BUDGET' && printf '%s\n' "$BJ2_OUT" | grep -q '^SCOPE'; } \
    && ok "BJ2: an over-budget, out-of-scope diff on a HEADING-form plan reports BUDGET and SCOPE" \
    || bad "BJ2: expected BUDGET and SCOPE on a heading-form plan, got [$BJ2_OUT] — the check is still inert"

  # The italic tolerance, isolated. Without it BJ2 cannot fire even with the right predicate.
  BJ3_N=$(awk '/[Bb]udget:/ && /\)[ \t]*[*_`]/ {n++} END{print n+0}' "$BJ_PLAN")
  [ "$BJ3_N" -ge 1 ] \
    && ok "BJ3: the real plan does write its Budget: in trailing markdown emphasis ($BJ3_N line(s)) — the tolerance is load-bearing, not cosmetic" \
    || bad "BJ3: no emphasis-wrapped Budget: line found — re-derive the tolerance before keeping it"
fi

# Backward compatibility over the WHOLE corpus (ADR-0052 §D1's hard gate, re-asserted after
# widening). A plan declaring no budget must be genuinely silent — and before this change that was
# satisfied accidentally, by a parser silent on almost everything.
BJ_DIR="$REPO/docs/superpowers/plans"
if [ -d "$BJ_DIR" ]; then
  #
  # MEMBERSHIP IS BY PROPERTY, NOT BY IDENTITY (issue #235, found by the Phase 7 shakedown run).
  # This loop asserts one thing: a plan declaring NO budget stays completely silent. A plan that
  # DOES declare one legitimately reports SCOPE against a diff touching a file it never names —
  # that is the feature working, and demanding silence of it asks the wrong question of that file.
  #
  # It used to exempt a single plan by path — `[ "$_p" = "$BJ_PLAN" ] && continue`, commented "the
  # one plan that legitimately has budgets". That was a statement about the corpus at a moment in
  # time, encoded as a permanent exception: exactly one plan declared budgets. The SECOND plan to
  # declare them, written by the chain itself and doing what ADR-0052 asks, failed here. Identity
  # is the waiver shape ADR-0069 §PTD refused by name; the property is what the assertion means.
  #
  # Same class as issue #230 (`spec-coverage.test.sh` RE3), found in the same run on a different
  # corpus: intent expressed as a population, coinciding with the property only while the corpus
  # had a single member exercising the feature.
  #
  # The predicate mirrors the budget SYNTAX diff-budget-check.sh documents in its own header —
  # `Budget: <file>[, <file>...] (<~|±><N> line[s])` — rather than re-implementing its parser. It
  # is deliberately independent of the checker's output on THIS diff: excluding "whatever the
  # checker reports something for" would make the assertion below vacuously true.
  # Measured over the corpus at the time of writing: 2 excluded, 56 asserted, 0 mismatches. The
  # prose "Performance budget: <10s typical" in 2026-05-20-vibe-status-skill.md is correctly NOT
  # excluded — it carries no parenthesised line count, declares no budget, and stays silent.
  plan_declares_budget() {
    grep -qE '[Bb]udget:.*\([^)]*[0-9]+[^)]*[Ll]ines?[^)]*\)' "$1" 2>/dev/null
  }

  mk_diffstat bj4 "a.txt:1" >"$TMP/stat_in"
  bj_total=0; bj_asserted=0; bj_excluded=0; bj_noisy=0; : >"$TMP/bj-noisy"
  for _p in "$BJ_DIR"/*.md; do
    [ -f "$_p" ] || continue
    bj_total=$((bj_total+1))
    if plan_declares_budget "$_p"; then bj_excluded=$((bj_excluded+1)); continue; fi
    bj_asserted=$((bj_asserted+1))
    _o=$(bash "$DBC" --plan "$_p" --tasks 1-99 <"$TMP/stat_in" 2>&1)
    [ "$_o" = "CLEAN" ] || { bj_noisy=$((bj_noisy+1)); printf '%s: %s\n' "$(basename "$_p")" "$_o" >>"$TMP/bj-noisy"; }
  done
  [ "$bj_asserted" -ge 30 ] \
    && ok "BJ4 (count guard): the corpus sweep asserted $bj_asserted budget-free plans of $bj_total ($bj_excluded excluded by property)" \
    || bad "BJ4 (count guard): only $bj_asserted plan(s) asserted of $bj_total ($bj_excluded excluded) — either the glob matches almost nothing, or the predicate is swallowing the corpus"
  [ "$bj_noisy" -eq 0 ] \
    && ok "BJ5: every budget-free plan in the corpus stays completely silent" \
    || bad "BJ5: $bj_noisy plan(s) became noisy: $(head -3 "$TMP/bj-noisy" | tr '\n' ' ')"

  # BJ5b/BJ5c — the exclusion predicate itself, on FIXTURES rather than on whatever the corpus
  # holds today. Asserting "at least one corpus plan is excluded" would rebuild the coupling this
  # removes. Both directions (rule 8: a negative-case assertion pins nothing without its positive
  # twin), and BJ5c is the real 2026-05-20 case generalised rather than pinned by filename.
  cat >"$TMP/bj5b-plan.md" <<'EOF'
# Plan

## Task 1 — Something (R-01)
Budget: src/thing.py (~40 lines)
EOF
  cat >"$TMP/bj5c-plan.md" <<'EOF'
# Plan

## Task 1 — Something (R-01)
Performance budget: under 10s typical, 8s per-harness timeout.
EOF
  plan_declares_budget "$TMP/bj5b-plan.md" \
    && ok "BJ5b: the predicate recognises a plan declaring a real task budget (it would be excluded)" \
    || bad "BJ5b: a plan declaring 'Budget: src/thing.py (~40 lines)' was NOT recognised — the exclusion excludes nothing and BJ5 is back to asserting by identity"
  plan_declares_budget "$TMP/bj5c-plan.md" \
    && bad "BJ5c: prose mentioning a budget with no parenthesised line count was excluded — the predicate over-matches and quietly shrinks the asserted set" \
    || ok "BJ5c: prose mentioning a budget with no parenthesised line count is NOT excluded — it stays in the asserted set"
else
  bad "BJ4: plan corpus not found at $BJ_DIR"
fi

# BJ6 — the right-aligned count column (ADR-0070 §D6), pinned on its own because it is the
# subtlest of the four defects and the only one that survives a correct predicate, a correct
# budget parse and an untruncated path. git pads narrower counts with leading spaces; the parser
# required a digit immediately after " | ", so any file smaller than the widest one in the diff
# vanished from the candidate set — no SCOPE finding, and its lines absent from the BUDGET total.
cat >"$TMP/bj6-plan.md" <<'EOF'
# Plan

## Task 1 — Something (R-01)

*Budget: `big.py` (~10 lines)*
EOF
# Handcrafted, not mk_diffstat: the alignment is the subject of the assertion, so it must be
# written explicitly rather than left to whatever width git picks for a fixture.
printf ' small.py |   7 +\n big.py   | 400 ++++\n 2 files changed, 407 insertions(+)\n' >"$TMP/stat_in"
BJ6_OUT=$(bash "$DBC" --plan "$TMP/bj6-plan.md" --tasks 1 <"$TMP/stat_in")
printf '%s\n' "$BJ6_OUT" | grep -q '^SCOPE.*small\.py' \
  && ok "BJ6: a file with a narrower, right-aligned count is still seen (SCOPE reported for small.py)" \
  || bad "BJ6: small.py vanished from the candidate set — got [$BJ6_OUT]"

printf '%s\n' "$BJ6_OUT" | grep -q 'lines=10/400' \
  && ok "BJ6b: the wider file's lines still reach the BUDGET total unchanged" \
  || bad "BJ6b: expected lines=10/400 in [$BJ6_OUT]"


# ==================================================================================================
# BK. Issue #246 — a per-file Budget: line was half-parsed into a false SCOPE and a false BUDGET.
#
# The parser matched ONE paren group anchored at end of line, so
#   Budget: a/SKILL.md (~165 lines, new), b/sync.sh (~1 line)
# kept only the LAST ceiling (1 instead of 166) and left the first file plus the fragments
# `(~165 lines` and `new)` in the file list. Three corruptions at once: a false SCOPE on a file the
# plan declares explicitly, an inflated file count, and NO BUDGET line at all.
#
# THE POPULATION IS THE SECOND BUDGET-DECLARING PLAN, and it is asserted by NOTHING today: BJ5
# excludes it by property (correctly — it declares budgets), and BJ1/BJ2 read the FIRST such plan.
# So the corpus grew a form the harness had no eyes on, which is the same shape as #235.
#
# SEEN RED against the restored pre-#246 call site: BK1, BK2, BK3, BK4, BK5, BK8. BK6/BK7 are
# forward guards (no MALFORMED token existed to misfire), BK9a/b/c compare the functions and are
# blind to the call site by construction — see the note above BK9.
#
# THE MALFORMED TOKEN'S DISCRIMINATOR IS MEASURED, NOT CHOSEN. `Budget:` is matched as a
# case-insensitive SUBSTRING, so the corpus contains `# Performance budget: <10s typical, 8s
# per-harness timeout.` — a comment inside a fenced code block — and a prose escape,
# `Budget: none (verification only, ...)`. A token firing on either would be this issue's own
# defect one level up: a detector reporting on text that was never a declaration. BK6/BK7 pin both.
# ==================================================================================================
BK_PLAN="$REPO/docs/superpowers/plans/2026-07-30-222-vendor-deployed-only-skills.md"
if [ ! -f "$BK_PLAN" ]; then
  bad "BK0: $BK_PLAN not found — BK1..BK3 are meaningless (if the plan was renamed, repoint them)"
else
  ok "BK0: the real per-file-budget plan is present"

  # BK1 — RED EVIDENCE. Task 2 declares BOTH files and the diff matches its ceilings exactly.
  # Against the pre-#246 parser this printed `SCOPE <the first declared file>` and no BUDGET line.
  printf ' staging/plugin/skills/ui-layout-audit/SKILL.md | 165 ++\n staging/sync-to-claude.sh |   1 +\n' >"$TMP/stat_in"
  BK1_OUT=$(bash "$DBC" --plan "$BK_PLAN" --tasks 2 <"$TMP/stat_in")
  [ "$BK1_OUT" = "CLEAN" ] \
    && ok "BK1 (red evidence): a per-file Budget: no longer produces a false SCOPE on a file the plan declares" \
    || bad "BK1: the per-file form still misparses — got [$BK1_OUT]"

  # BK2 — the ceilings are SUMMED. 165 + 1 = 166; the old parser reported 1, so an overshoot was
  # fabricated by two orders of magnitude.
  printf ' staging/plugin/skills/ui-layout-audit/SKILL.md | 499 ++\n staging/sync-to-claude.sh |   1 +\n' >"$TMP/stat_in"
  BK2_OUT=$(bash "$DBC" --plan "$BK_PLAN" --tasks 2 <"$TMP/stat_in")
  printf '%s\n' "$BK2_OUT" | grep -q 'lines=166/500' \
    && ok "BK2: per-file ceilings are summed (165+1=166), not replaced by the last one" \
    || bad "BK2: expected lines=166/500 — got [$BK2_OUT]"

  # BK3 — the same, on a different task, so BK2 is not a single lucky line. Task 6: 25 + 45 = 70.
  printf ' staging/sync-to-claude.sh | 25 ++\n staging/plugin/scripts/tests/sync-manual-steps.test.sh | 400 ++\n' >"$TMP/stat_in"
  BK3_OUT=$(bash "$DBC" --plan "$BK_PLAN" --tasks 6 <"$TMP/stat_in")
  printf '%s\n' "$BK3_OUT" | grep -q 'lines=70/425' \
    && ok "BK3: a second per-file declaration sums correctly too (25+45=70)" \
    || bad "BK3: expected lines=70/425 — got [$BK3_OUT]"
fi

# BK4 — a MIXED declaration: one group whose preceding text is itself a comma list sharing that
# ceiling, followed by a per-file group. The walk must handle both in one line: 50 + 10 = 60 over
# three files. This is the form neither the old parser nor a naive comma-split can read.
cat >"$TMP/bk4-plan.md" <<'PLANEOF'
# Plan

## Task 1 — Mixed (R-01)

Budget: a.md, b.md (~50 lines), c.md (~10 lines)
PLANEOF
printf ' a.md | 30 ++\n b.md | 20 ++\n c.md | 11 ++\n' >"$TMP/stat_in"
BK4_OUT=$(bash "$DBC" --plan "$TMP/bk4-plan.md" --tasks 1 <"$TMP/stat_in")
printf '%s\n' "$BK4_OUT" | grep -q 'files=3/3' && printf '%s\n' "$BK4_OUT" | grep -q 'lines=60/61' \
  && ok "BK4: a mixed shared-then-per-file declaration reads as 3 files and 50+10=60 lines" \
  || bad "BK4: expected files=3/3 lines=60/61 — got [$BK4_OUT]"

# BK5 — MALFORMED fires on a recognisable ATTEMPT that does not fully parse: a trailing file with
# no ceiling. Silently dropping it is the half-read this issue is about.
cat >"$TMP/bk5-plan.md" <<'PLANEOF'
# Plan

## Task 1 — Broken (R-01)

Budget: a.md (~50 lines), b.md
PLANEOF
printf ' a.md | 10 ++\n' >"$TMP/stat_in"
BK5_OUT=$(bash "$DBC" --plan "$TMP/bk5-plan.md" --tasks 1 <"$TMP/stat_in")
printf '%s\n' "$BK5_OUT" | grep -q '^MALFORMED' \
  && ok "BK5: a declaration with a trailing file and no ceiling reports MALFORMED instead of being half-read" \
  || bad "BK5: expected a MALFORMED line — got [$BK5_OUT]"

# BK6 — and it must NOT fire on prose. This is the real corpus line, verbatim, from
# 2026-05-20-vibe-status-skill.md: a comment inside a fenced code block, never a declaration.
cat >"$TMP/bk6-plan.md" <<'PLANEOF'
# Plan

## Task 1 — Thing (R-01)

# Performance budget: <10s typical, 8s per-harness timeout.
PLANEOF
printf ' a.md | 10 ++\n' >"$TMP/stat_in"
BK6_OUT=$(bash "$DBC" --plan "$TMP/bk6-plan.md" --tasks 1 <"$TMP/stat_in")
[ "$BK6_OUT" = "CLEAN" ] \
  && ok "BK6 (forward guard, green before and after): prose containing the substring 'budget:' with no parenthesised line count stays CLEAN" \
  || bad "BK6: MALFORMED fired on prose that was never a declaration — got [$BK6_OUT]"

# BK7 — nor on the deliberate prose escape, also a real corpus line: a task that touches no files.
# It carries digits ('Tasks 1-6') but no 'line' inside the parens, so it is not an attempt.
cat >"$TMP/bk7-plan.md" <<'PLANEOF'
# Plan

## Task 1 — Verification only (R-01)

Budget: none (verification only, no source files touched beyond what Tasks 1-6 already changed)
PLANEOF
printf ' a.md | 10 ++\n' >"$TMP/stat_in"
BK7_OUT=$(bash "$DBC" --plan "$TMP/bk7-plan.md" --tasks 1 <"$TMP/stat_in")
[ "$BK7_OUT" = "CLEAN" ] \
  && ok "BK7 (forward guard, green before and after): the no-files prose escape stays CLEAN — digits alone are not an attempt, 'line' must be there too" \
  || bad "BK7: MALFORMED fired on the legitimate no-files prose escape — got [$BK7_OUT]"

# BK8 — a plan whose ONLY declaration is malformed must still REPORT. The whole-plan inert check
# returns CLEAN on an empty budget set, and CLEAN is the common, documented, legitimate case — so
# without this the operator reads "nothing to report" for a plan the checker could not read. That
# is precisely the invisibility ADR-0070 spent months inside.
cat >"$TMP/bk8-plan.md" <<'PLANEOF'
# Plan

## Task 1 — Only broken (R-01)

Budget: a.md (~50 lines), b.md
PLANEOF
printf ' zzz.md | 900 ++\n' >"$TMP/stat_in"
BK8_OUT=$(bash "$DBC" --plan "$TMP/bk8-plan.md" --tasks 1 <"$TMP/stat_in")
{ [ "$BK8_OUT" != "CLEAN" ] && printf '%s\n' "$BK8_OUT" | grep -q '^MALFORMED'; } \
  && ok "BK8: a plan whose only Budget: is malformed reports MALFORMED rather than the inert CLEAN" \
  || bad "BK8: a wholly-malformed plan reported [$BK8_OUT] — an unreadable declaration must not look like nothing to report"

# BK9 — BACKWARD COMPATIBILITY, DERIVED AGAINST THE PRE-#246 PARSER ITSELF.
#
# The old parser is embedded below as the SPECIFICATION of what must not change, and every
# single-ceiling declaration in the real corpus must parse to the same (files, ceiling) pair under
# both. Only the per-file declarations may differ, and BK9b pins WHICH ones do — otherwise "the
# corpus agrees" could be satisfied by a parser that rejects everything.
#
# BK9b CHECKS A CLASS, NOT A COUNT, and the reason is this file's own history. It used to assert
# `1 <= bk9_diff <= 5`, an absolute ceiling fixed when the corpus held three per-file declarations.
# ADR-0117 added a fourth; the ADR-0132 plan added eight more, and the assertion went red on a
# feature that had done nothing wrong. That is `BB2b`'s disease one assertion over in the same
# file — CLAUDE.md already records it firing three times on three consecutive healthy features,
# with the note that a fourth hand-edit is the wrong remedy. A count cannot distinguish "the
# rewrite moved the single-ceiling population" from "the corpus grew"; set equality can, and it
# has no threshold to maintain. The property asserted is exact and two-directional: a declaration
# parses differently IF AND ONLY IF it is a per-file (multi-group) form.
#
# ITS BOUNDARY, STATED: BK9 extracts and compares the parse_budget FUNCTION, so it is blind to a
# script that defines the function correctly and does not call it. Verified rather than assumed —
# restoring the pre-#246 CALL SITE while leaving the function in place leaves BK9a/b/c green.
# BK1/BK2/BK3 are what fail there, which is why the two must be read as a pair.
cat >"$TMP/bk9-old.awk" <<'AWKEOF'
function trim(s){gsub(/^[ \t]+/,"",s);gsub(/[ \t]+$/,"",s);return s}
/[Bb]udget:/ {
  rest=trim(substr($0, index($0,"udget:")+6))
  if (match(rest, /\([^()]*\)[ \t]*[*_`]*[ \t]*$/)) {
    parenraw=substr(rest,RSTART,RLENGTH); filespart=trim(substr(rest,1,RSTART-1))
    sub(/,[ \t]*$/,"",filespart); gsub(/`/,"",filespart)
    inner=parenraw; gsub(/[()]/,"",inner); low=tolower(inner)
    if (filespart!="" && match(inner,/[0-9]+/) && index(low,"line")>0) {
      printf "%s|%s\n", filespart, substr(inner,RSTART,RLENGTH); next
    }
  }
  print "<none>|-"
}
AWKEOF
sed -n '/^function parse_budget/,/^}$/p' "$DBC" >"$TMP/bk9-new.awk"
cat >>"$TMP/bk9-new.awk" <<'AWKEOF'
function trim(s){gsub(/^[ \t]+/,"",s);gsub(/[ \t]+$/,"",s);return s}
/[Bb]udget:/ {
  rest=trim(substr($0, index($0,"udget:")+6))
  r=parse_budget(rest)
  if (r=="") { print "<none>|-" } else { sub(/\t/,"|",r); print r }
}
AWKEOF
awk -f "$TMP/bk9-old.awk" "$REPO"/docs/superpowers/plans/*.md >"$TMP/bk9-old.out" 2>/dev/null
awk -f "$TMP/bk9-new.awk" "$REPO"/docs/superpowers/plans/*.md >"$TMP/bk9-new.out" 2>/dev/null
bk9_n=$(grep -c . "$TMP/bk9-old.out" 2>/dev/null || true); [ -n "$bk9_n" ] || bk9_n=0
bk9_same=0; bk9_diff=0
if [ "$bk9_n" -gt 0 ] && [ "$bk9_n" = "$(grep -c . "$TMP/bk9-new.out" 2>/dev/null || true)" ]; then
  bk9_same=$(paste "$TMP/bk9-old.out" "$TMP/bk9-new.out" | awk -F'\t' '$1==$2' | grep -c . || true)
  bk9_diff=$((bk9_n - bk9_same))
fi
if [ "$bk9_n" -ge 10 ]; then
  ok "BK9a (count guard): the corpus carries $bk9_n Budget: lines to compare — the sweep is not vacuous"
else
  bad "BK9a (count guard): only $bk9_n Budget: line(s) found — the derivation is broken, not the corpus clean"
fi
# Per-Budget-line CLASS, emitted in the same order and count as the two parser outputs above, so
# the three files line up index by index. MULTI = more than one paren group carrying both a digit
# and the word "line", i.e. the per-file form ADR-0091 introduced. The qualifying-group test is
# parse_budget's own recognisable-attempt rule, restated here rather than borrowed, because this
# file must be able to disagree with the script it is checking.
cat >"$TMP/bk9-class.awk" <<'AWKEOF'
function trim(s){gsub(/^[ \t]+/,"",s);gsub(/[ \t]+$/,"",s);return s}
/[Bb]udget:/ {
  rest=trim(substr($0, index($0,"udget:")+6)); q=0; s=rest
  while (match(s, /\([^()]*\)/)) {
    # st/ln are captured BEFORE the digit test below, and that is not defensive style: match()
    # writes RSTART/RLENGTH globally, so the inner match() overwrites the outer one's position
    # and `substr(s, RSTART+RLENGTH)` would advance the cursor by the DIGIT's offset instead of
    # the group's. Measured, not reasoned: on `Budget: a.md (~50 lines)` the cursor moved back
    # into the same parenthesis and counted it twice, reporting a single-ceiling line as MULTI.
    st=RSTART; ln=RLENGTH
    inner=substr(s,st+1,ln-2); low=tolower(inner)
    if (match(inner,/[0-9]+/) && index(low,"line")>0) q++
    s=substr(s,st+ln)
  }
  print (q>1 ? "MULTI" : "SINGLE")
}
AWKEOF
awk -f "$TMP/bk9-class.awk" "$REPO"/docs/superpowers/plans/*.md >"$TMP/bk9-class.out" 2>/dev/null
bk9_multi=$(grep -cx MULTI "$TMP/bk9-class.out" 2>/dev/null || true); [ -n "$bk9_multi" ] || bk9_multi=0
# Set equality, both directions at once: a MULTI line that did NOT change and a SINGLE line that
# DID are both violations, and both are counted here.
bk9_mismatch=0
if [ "$bk9_n" -gt 0 ] && [ "$bk9_n" = "$(grep -c . "$TMP/bk9-class.out" 2>/dev/null || true)" ]; then
  bk9_mismatch=$(paste "$TMP/bk9-old.out" "$TMP/bk9-new.out" "$TMP/bk9-class.out" \
    | awk -F'\t' '{ differs = ($1 != $2); multi = ($3 == "MULTI"); if (differs != multi) print }' \
    | grep -c . || true)
else
  bk9_mismatch=-1   # the three derivations disagree on line count: broken, not clean
fi
# Two plants, from opposite ends, because the iff has two ways to be hollow. The first widens the
# CLASS (every line with one qualifying group becomes MULTI), so single-ceiling declarations are
# called per-file while parsing identically. The second inverts the COMPARISON, so conforming
# lines are counted as violations. A check that survived either would be asserting nothing.
# plant: BK9b | plugin/scripts/tests/diff-budget-scope.test.sh | q>1 ? "MULTI" : "SINGLE" | q>0 ? "MULTI" : "SINGLE"
# plant: BK9b | plugin/scripts/tests/diff-budget-scope.test.sh | if (differs != multi) print | if (differs == multi) print
if [ "$bk9_mismatch" -eq 0 ] && [ "$bk9_diff" -ge 1 ]; then
  ok "BK9b: a declaration parses differently iff it is a per-file form ($bk9_diff of $bk9_n differ, $bk9_multi are multi-group) — the single-ceiling population is untouched"
elif [ "$bk9_diff" -lt 1 ]; then
  bad "BK9b: no declaration parses differently at all — the per-file parse is gone, so #246's fix is not in this parser"
elif [ "$bk9_mismatch" -lt 0 ]; then
  bad "BK9b: the class derivation produced a different line count than the parsers — the sweep is broken, not the corpus clean"
else
  bad "BK9b: $bk9_mismatch declaration(s) break the iff — a multi-group form that parses identically, or a single-ceiling form that moved ($bk9_diff differ, $bk9_multi multi-group, of $bk9_n)"
fi
bk9_regress=$(paste "$TMP/bk9-old.out" "$TMP/bk9-new.out" \
  | awk -F'\t' '$1!=$2 && $2=="<none>|-"' | grep -c . || true)
if [ "${bk9_regress:-0}" -eq 0 ]; then
  ok "BK9c: no declaration the OLD parser could read has become unreadable — the widening never narrowed"
else
  bad "BK9c: $bk9_regress declaration(s) parsed by the old parser now yield nothing — the rewrite is a regression, not a widening"
fi

# BK10 — the token must have a CONSUMER. A reporter emitting a line no caller reads is a producer
# with no consumer, the defect class #238 records — and inventing one while the roadmap is closing
# that class would be a poor trade. Asserted against the Step 5 call site, on a flattened copy so
# the assertion does not depend on where markdown wraps (ADR-0073).
# TWO DISTINCTIVE NEEDLES, not a count of the bare token. Two drafts were wrong here and both are
# worth recording. First: a bare `grep -qF 'MALFORMED'`, which the token satisfies from either of
# its two sites, so deleting one let the plant walk through — `recovery-preflight.test.sh` RI1's
# defect exactly. Second: an exact count of 2, which failed on the real file because
# `spec-coverage.sh` — a DIFFERENT checker, twenty lines up in the same step — emits a `MALFORMED`
# token of its own. Counting a bare word across a whole step conflates two checkers that happen to
# share it. Each needle below belongs to one block and to nothing else — verified by planting all
# four: a bare 'not measured' was the third draft and did NOT fire, because the phrase appears
# twice more in Step 5 for the absent-field rule (ADR-0064 §D3). Scoped to its sentence.
BK10_FLAT=$(tr '\n' ' ' <"$STEP5" 2>/dev/null | tr -s ' ')
bk10_has() { printf '%s' "$BK10_FLAT" | grep -qF "$1"; }
if bk10_has 'MALFORMED<TAB>task <N><TAB><declaration text>' \
   && bk10_has 'Record every `MALFORMED` line as its own entry' \
   && bk10_has "this task's budget was **not measured**" \
   && bk10_has '{task, malformed}'; then
  ok "BK10: Step 5 reads the MALFORMED token, says the budget was not measured, and records it in budget_findings"
else
  bad "BK10: the Step 5 call site no longer reads the MALFORMED token (caller-idiom bullet, recording bullet, not-measured wording, or {task, malformed} shape is missing) — a reporter line nobody reads is #238's shape"
fi

# Z1 — assertion-count floor (ADR-0083 §D3). A floor, not an exact count.
Z1_TOTAL=$((PASS + FAIL))
if [ "$Z1_TOTAL" -ge 55 ]; then
  ok "Z1: assertion-count floor met ($Z1_TOTAL executed)"
else
  bad "Z1: only $Z1_TOTAL assertions executed — expected >= 55; assertions have gone missing, not passed"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
