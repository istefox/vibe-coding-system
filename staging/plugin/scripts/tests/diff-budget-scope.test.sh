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
if [ "$bb2_skipped" -ge 1 ] && [ "$bb2_skipped" -le 5 ]; then
  ok "BB2b: the budget-declaring exclusion covers $bb2_skipped plan(s) — small and live"
else
  bad "BB2b: $bb2_skipped plan(s) excluded from BB2 — re-derive the exclusion, it no longer bounds anything"
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
STEP5="$TMP/cc_step5.txt"
awk '/^### Step 5 —/{f=1} /^### Step 6 —/{f=0} f' "$CC" >"$STEP5"
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

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
