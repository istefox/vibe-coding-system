#!/bin/bash
# agent-metrics.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash agent-metrics.test.sh
#
# Covers issue #118 / ADR-0064: four cheap per-task instrumentation metrics (test-count delta,
# deleted lines, iteration count, elapsed wall time), additive into step5-report.json and
# autopilot-report.json, as INPUTS for future rut detection / trust scoring — not a detector itself.
#
# ASSERTION LABELS ARE G-PREFIXED (GA1, GB3, GG2, ...) — grepped as unused across the other 40
# harnesses in this directory before this file was written (no GA/GB/.../GG collision).
#
# THE SCRIPT UNDER TEST (agent-metrics.sh) MEASURES, IT DOES NOT REPORT A FINDING. It always
# exits 0 and always prints two TAB-separated lines (DELETED_LINES, TEST_COUNT_DELTA) — there is
# no CLEAN sentinel here (unlike diff-budget-check.sh / weakening-scan.sh at the same checkpoint):
# a genuinely empty diff legitimately produces two real zeros. The absent-vs-zero distinction
# (ADR-0064 §D3) is enforced at the CALLER (SKILL.md), which omits both fields from
# step5-report.json when the script does not resolve — never invokes it and defaults to 0. This
# file's GB section pins that the SKILL.md text says so explicitly.
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

AM="$STAGING/plugin/skills/concept-to-code/scripts/agent-metrics.sh"
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
STEP5_REF="$STAGING/plugin/skills/concept-to-code/references/step5-implementation.md"
NA="$STAGING/plugin/skills/autopilot/SKILL.md"
ADR22="$REPO/docs/architecture/ADR-0022-morning-report-schema.md"
TWS="$STAGING/plugin/scripts/test-write-scope.sh"
USAGE="$STAGING/plugin/scripts/usage-report.py"

# ==================================================================================================
# G0. The anchor every G assertion below depends on.
# ==================================================================================================
if [ -f "$AM" ] && [ -r "$AM" ]; then
  ok "G0: agent-metrics.sh exists and is readable at the expected path"
else
  bad "G0: $AM not found or unreadable — every script-behavior G assertion below is meaningless"
fi

STEP5="$TMP/cc_step5.txt"
# The Step 5 range moved to references/step5-implementation.md (VCS-047, ADR-0174); the
# reference file's body IS the block, so no awk range is needed any more.
cp "$STEP5_REF" "$STEP5" 2>/dev/null
GATES="$TMP/cc_gates.txt"
awk '/^## 5\. HITL gates/{f=1} /^## 6\. Coexistence invariants/{f=0} f' "$CC" >"$GATES"

if [ -s "$STEP5" ] && [ -s "$GATES" ]; then
  ok "G0b: both extraction anchors (Step 5, ## 5. HITL gates) are non-empty"
else
  bad "G0b: could not extract Step 5 and/or ## 5. HITL gates from $CC — GA/GD assertions below are meaningless"
fi

# Flattened (newlines -> single spaces) variants, so a phrase this file's own markdown line-wraps
# across two source lines is still matched by a plain grep -F. Used only for prose-phrase checks
# below (GB/GC/GD/GF); the line-based files above are still used for per-line JSON structure checks.
flatten() { tr '\n' ' ' < "$1" | tr -s ' '; }
STEP5_FLAT="$TMP/step5_flat.txt"; flatten "$STEP5" > "$STEP5_FLAT"
GATES_FLAT="$TMP/gates_flat.txt"; flatten "$GATES" > "$GATES_FLAT"

# --- fixture helper: build a throwaway git repo under $TMP/<name>, baseline-commit the given
# "<path>:<linecount>" files, then apply the given mutations ("<path>:<linecount>" = overwrite,
# "rm:<path>" = delete), stage, and print the full unified diff `git diff --cached HEAD`. ---
mk_repo() {
  _name="$1"; shift
  _repo="$TMP/repo_$_name"
  rm -rf "$_repo"; mkdir -p "$_repo"
  ( cd "$_repo" && git init -q \
      && git -c user.name=t -c user.email=t@t.com -c commit.gpgsign=false commit -q -m baseline --allow-empty )
  for _spec in "$@"; do
    _f="${_spec%%:*}"; _n="${_spec#*:}"
    mkdir -p "$(dirname "$_repo/$_f")"
    : > "$_repo/$_f"
    _i=0
    while [ "$_i" -lt "$_n" ]; do printf 'line %s\n' "$_i" >> "$_repo/$_f"; _i=$((_i+1)); done
  done
  ( cd "$_repo" && git add -A >/dev/null 2>&1 \
      && git -c user.name=t -c user.email=t@t.com -c commit.gpgsign=false commit -q -m t1 )
  printf '%s\n' "$_repo"
}

mutate_diff() {
  _repo="$1"; shift
  for _spec in "$@"; do
    case "$_spec" in
      rm:*)
        _f="${_spec#rm:}"
        ( cd "$_repo" && git rm -q "$_f" )
        ;;
      *)
        _f="${_spec%%:*}"; _n="${_spec#*:}"
        mkdir -p "$(dirname "$_repo/$_f")"
        : > "$_repo/$_f"
        _i=0
        while [ "$_i" -lt "$_n" ]; do printf 'line %s\n' "$_i" >> "$_repo/$_f"; _i=$((_i+1)); done
        ;;
    esac
  done
  ( cd "$_repo" && git add -A >/dev/null 2>&1 && git diff --cached HEAD )
}

run_am() { OUT=$(printf '%s' "$1" | bash "$AM" 2>"$TMP/err"); RC=$?; ERR=$(cat "$TMP/err" 2>/dev/null); }

# ==================================================================================================
# GM. agent-metrics.sh script behavior — the mechanics GA/GC below depend on being real.
# ==================================================================================================
if [ -f "$AM" ]; then
  R1=$(mk_repo gm1 "src.py:3")
  D1=$(mutate_diff "$R1" "src.py:1")
  run_am "$D1"
  if printf '%s\n' "$OUT" | grep -q "^DELETED_LINES${TAB}2$"; then
    ok "GM1: 3 lines -> 1 line reports DELETED_LINES=2"
  else
    bad "GM1: expected DELETED_LINES=2 — got out=[$OUT]"
  fi
  if printf '%s\n' "$OUT" | grep -q "^TEST_COUNT_DELTA${TAB}0$"; then
    ok "GM2: no test file touched -> TEST_COUNT_DELTA=0"
  else
    bad "GM2: expected TEST_COUNT_DELTA=0 — got out=[$OUT]"
  fi
  if [ "$RC" -eq 0 ]; then
    ok "GM3: exits 0 on a normal diff"
  else
    bad "GM3: expected exit 0 — got rc=$RC"
  fi

  R2=$(mk_repo gm2 "tests/test_foo.py:2" "src.py:3")
  D2=$(mutate_diff "$R2" "rm:tests/test_foo.py" "src.py:1")
  run_am "$D2"
  if printf '%s\n' "$OUT" | grep -q "^TEST_COUNT_DELTA${TAB}-1$"; then
    ok "GM4: deleting a test file reports TEST_COUNT_DELTA=-1"
  else
    bad "GM4: expected TEST_COUNT_DELTA=-1 — got out=[$OUT]"
  fi
  if printf '%s\n' "$OUT" | grep -q "^DELETED_LINES${TAB}4$"; then
    ok "GM5: 2 deleted src.py lines + 2 deleted test file lines -> DELETED_LINES=4"
  else
    bad "GM5: expected DELETED_LINES=4 — got out=[$OUT]"
  fi

  R3=$(mk_repo gm3 "test_new.py:1")
  D3=$(mutate_diff "$R3" "test_new.py:1" "tests/test_added.py:2")
  run_am "$D3"
  if printf '%s\n' "$OUT" | grep -q "^TEST_COUNT_DELTA${TAB}1$"; then
    ok "GM6: adding one new test file (tests/test_added.py) -> TEST_COUNT_DELTA=1"
  else
    bad "GM6: expected TEST_COUNT_DELTA=1 — got out=[$OUT]"
  fi

  R4=$(mk_repo gm4 "SPEC.md:3" ".claude/step5-report.json:2" "docs/manifests/x.manifest.yml:2")
  D4=$(mutate_diff "$R4" "SPEC.md:1" ".claude/step5-report.json:1" "docs/manifests/x.manifest.yml:1")
  run_am "$D4"
  if printf '%s\n' "$OUT" | grep -q "^DELETED_LINES${TAB}0$"; then
    ok "GM7: chain-owned files (SPEC.md, step5-report.json, *.manifest.yml) losing lines are excluded from DELETED_LINES"
  else
    bad "GM7: expected DELETED_LINES=0 (chain-owned exclusion) — got out=[$OUT]"
  fi

  run_am ""
  if printf '%s\n' "$OUT" | grep -q "^DELETED_LINES${TAB}0$" \
     && printf '%s\n' "$OUT" | grep -q "^TEST_COUNT_DELTA${TAB}0$" && [ "$RC" -eq 0 ]; then
    ok "GM8: an empty diff is a REAL, computed zero on both fields, exit 0 — not an error case"
  else
    bad "GM8: expected two real zero lines and exit 0 on empty input — got out=[$OUT] rc=$RC"
  fi
fi

# ==================================================================================================
# GA. All four metrics appear in both schema blocks (step5-report.json, autopilot-report.json),
# additive and conditional-if-present.
# ==================================================================================================
if grep -qF '"task_metrics"' "$STEP5"; then
  ok "GA1: the step5-report.json schema block contains \"task_metrics\""
else
  bad "GA1: \"task_metrics\" missing from the Step 5 schema block"
fi

if grep -F -A5 '"task_metrics"' "$STEP5" | grep -q '"test_count_delta"' \
   && grep -F -A5 '"task_metrics"' "$STEP5" | grep -q '"deleted_lines"' \
   && grep -F -A5 '"task_metrics"' "$STEP5" | grep -q '"iteration_count"' \
   && grep -F -A5 '"task_metrics"' "$STEP5" | grep -q '"elapsed_wall_seconds"'; then
  ok "GA2: all four ADR-0064 metric field names appear near task_metrics in the step5-report.json schema"
else
  bad "GA2: one or more of test_count_delta/deleted_lines/iteration_count/elapsed_wall_seconds missing near task_metrics"
fi

if [ -f "$NA" ] && [ -f "$ADR22" ]; then
  ok "GA3a: autopilot/SKILL.md and ADR-0022-morning-report-schema.md both exist"
else
  bad "GA3a: autopilot/SKILL.md or ADR-0022-morning-report-schema.md missing"
fi

NA_ALL="$TMP/na_all.txt"
cat "$NA" > "$NA_ALL" 2>/dev/null
ADR22_ALL="$TMP/adr22_all.txt"
cat "$ADR22" > "$ADR22_ALL" 2>/dev/null

for _f in test_count_delta deleted_lines iteration_count elapsed_wall_seconds; do
  if grep -qF "$_f" "$ADR22_ALL" 2>/dev/null; then
    ok "GA4-$_f: ADR-0022's autopilot-report.json schema mentions $_f"
  else
    bad "GA4-$_f: ADR-0022's autopilot-report.json schema does not mention $_f"
  fi
done

if grep -qF 'task_metrics' "$NA_ALL" 2>/dev/null && grep -qF 'ADR-0064' "$NA_ALL" 2>/dev/null; then
  ok "GA5: autopilot/SKILL.md references task_metrics and ADR-0064 for its Phase 2 report write"
else
  bad "GA5: autopilot/SKILL.md is missing the task_metrics/ADR-0064 wiring in Phase 2"
fi

if grep -qi 'schema bump' "$ADR22_ALL" 2>/dev/null && grep -qF 'ADR-0064' "$ADR22_ALL" 2>/dev/null; then
  ok "GA6: ADR-0022 states the four new fields are additive with no schema bump"
else
  bad "GA6: ADR-0022 is missing the no-schema-bump statement for the ADR-0064 fields"
fi

# ==================================================================================================
# GB. Absent is distinguishable from zero (§D3) — the read contract says so explicitly, and no
# default-to-zero exists anywhere in the new text.
# ==================================================================================================
TM_BLOCK="$TMP/tm_block.txt"
# The Step 5 range moved to references/step5-implementation.md (VCS-047, ADR-0174); this
# sub-block lives inside it now.
awk '/^#### Task-level metrics —/{f=1} /^#### Fallback —/{f=0} f' "$STEP5_REF" >"$TM_BLOCK"
if [ -s "$TM_BLOCK" ]; then
  ok "GB0: the Task-level metrics block was extracted from Step 5 (non-empty)"
else
  bad "GB0: could not extract the Task-level metrics block from $CC — GB/GC/GF assertions below may be meaningless"
fi
TM_BLOCK_FLAT="$TMP/tm_block_flat.txt"; flatten "$TM_BLOCK" > "$TM_BLOCK_FLAT"

if grep -qF 'task_metrics' "$STEP5" && grep -qF 'absent' "$STEP5" \
   && (grep -qF 'never' "$STEP5" && grep -qF '`0`' "$STEP5"); then
  ok "GB1: the step5-report.json contract states task_metrics/fields absent must never be read as 0"
else
  bad "GB1: the absent-means-not-recorded-never-zero statement for task_metrics is missing from the schema block"
fi

if grep -qF 'OMIT' "$TM_BLOCK" && grep -qF 'never write' "$TM_BLOCK"; then
  ok "GB2: the Task-level metrics block instructs OMIT-not-default-to-0 for unresolved/unparseable fields"
else
  bad "GB2: the Task-level metrics block does not explicitly instruct omitting an unmeasured field instead of writing 0"
fi

if grep -qF '_ametrics=""' "$TM_BLOCK"; then
  ok "GB3: the resolution block uses the same empty-string-on-failure idiom as _wscan/_scov/_dbudget (never invoke-and-default)"
else
  bad "GB3: the agent-metrics.sh resolution block does not follow the _ametrics=\"\" fail-open idiom"
fi

if grep -qF 'real, computed zero' "$TM_BLOCK"; then
  ok "GB4: the block distinguishes a real computed zero (script ran, measured 0) from an absent field (script did not run)"
else
  bad "GB4: the real-zero vs absent distinction is not spelled out in the Task-level metrics block"
fi

if grep -qF 'Never read an absent field as `0`' "$STEP5" 2>/dev/null; then
  ok "GB5: the read contract carries an explicit never-read-absent-as-0 instruction for task_metrics"
else
  bad "GB5: no explicit never-read-absent-as-0 instruction found for task_metrics in the read contract"
fi

# ==================================================================================================
# GC. Every metric is computed, not self-reported (§D4) — none is sourced from an agent's report.
# ==================================================================================================
if grep -qF 'computed, never self-reported' "$TM_BLOCK" || grep -qF 'computed, not self-reported' "$TM_BLOCK"; then
  ok "GC1: the Task-level metrics block states the computed-not-self-reported rule"
else
  bad "GC1: the computed-not-self-reported statement is missing from the Task-level metrics block"
fi

if grep -qF 'ADR-0064' "$TM_BLOCK" && grep -qF '§D4' "$TM_BLOCK"; then
  ok "GC2: the block cites ADR-0064 §D4"
else
  bad "GC2: the block does not cite ADR-0064 §D4"
fi

# The tester/coder dispatch prompt templates must never ask an agent to report these four metrics.
# Scan the whole Step 5 section's ``` prompt blocks broadly, since this is the cheapest
# reliable proxy without a fenced-block parser (matches the codebase's own extraction idiom).
GC3_HIT=0
for _term in "report your iteration count" "report your elapsed time" "report the deleted line count" "report the test count"; do
  grep -qi "$_term" "$STEP5" && GC3_HIT=1
done
if [ "$GC3_HIT" -eq 0 ]; then
  ok "GC3: no dispatch prompt text in Step 5 asks an agent to self-report iteration count, elapsed time, deleted lines, or test count"
else
  bad "GC3: Step 5 dispatch prompt text asks an agent to self-report one of the four ADR-0064 metrics"
fi

if grep -qF 'requested in any tester or coder dispatch prompt' "$TM_BLOCK_FLAT"; then
  ok "GC4: the block states explicitly that none of the four fields is requested in a dispatch prompt"
else
  bad "GC4: the block is missing the explicit not-requested-in-a-dispatch-prompt statement"
fi

if grep -qF 'from `git`' "$TM_BLOCK_FLAT" && grep -qF 'dispatch bookkeeping' "$TM_BLOCK_FLAT"; then
  ok "GC5: the block names git and orchestrator dispatch bookkeeping as the two sources — no third (agent) source"
else
  bad "GC5: the block does not clearly name git + dispatch bookkeeping as the exhaustive metric sources"
fi

# ==================================================================================================
# GD. task_metrics is not surfaced at Gate 5 and not counted in the ADR-0052 §D5 advisory roll-up.
# ==================================================================================================
if grep -qF 'not part of this roll-up' "$GATES" && grep -qF 'not rendered at Gate 5' "$GATES"; then
  ok "GD1: Gate 5 explicitly states task_metrics is excluded from the roll-up and not rendered"
else
  bad "GD1: Gate 5 is missing the explicit task_metrics exclusion statement"
fi

# GD2 originally pinned the literal phrase "six arrays ... not seven", which held only while
# task_metrics was the sole candidate for a seventh array. ADR-0066 (#120) added a real, disclosed
# seventh advisory-schema finding array (accessibility_i18n_findings) elsewhere in this same
# schema, so that literal count is no longer true and the phrase correctly moved. What this
# assertion actually guards — task_metrics itself never inflates the roll-up, because it carries
# no claim — is unchanged and is what is checked here instead (ADR-0066 SKILL.md changelog note).
if grep -qF 'task_metrics' "$GATES" && grep -qiE 'carries no claim' "$GATES"; then
  ok "GD2: Gate 5 states task_metrics's exclusion is semantic (carries no claim), not merely a stale count"
else
  bad "GD2: Gate 5 does not state task_metrics carries no claim — the semantic-exclusion guard is missing"
fi

# Forward guard: the six named advisory arrays are still exactly the six from ADR-0052, task_metrics
# is not among them.
GD3_MISSING=""
for _arr in weakening_findings requirement_coverage checkpoint_reviews tests_written_by suspect_findings budget_findings; do
  grep -qF "$_arr" "$GATES" 2>/dev/null || GD3_MISSING="$GD3_MISSING $_arr"
done
if [ -z "$GD3_MISSING" ]; then
  ok "GD3: all six pre-existing advisory array names are still named in the Gate 5 roll-up block"
else
  bad "GD3: missing from the Gate 5 roll-up block:$GD3_MISSING"
fi

ROLLUP_LIST_LINE=$(grep -F 'render exactly ONE line' -A2 "$GATES" | grep -F 'Advisory findings: none' || true)
if printf '%s' "$ROLLUP_LIST_LINE" | grep -qF 'task_metrics'; then
  bad "GD4: task_metrics leaked into the all-six-empty roll-up summary line"
else
  ok "GD4: task_metrics does not appear in the all-six-empty roll-up summary line"
fi

if grep -qF '"task_metrics"' "$GATES"; then
  bad "GD5: task_metrics is quoted as a JSON key inside the Gate 5 / HITL gates section — it must stay out of the rendered advisory content"
else
  ok "GD5: no task_metrics JSON-key mention inside the Gate 5 / HITL gates section (only prose exclusion language, checked above)"
fi

if grep -qF 'metrics, not findings' "$STEP5" || grep -qF 'METRICS, not findings' "$STEP5"; then
  ok "GD6: Step 5 states the metrics-not-findings distinction (ADR-0064 §D2) at the point task_metrics is introduced"
else
  bad "GD6: the metrics-not-findings statement is missing from Step 5"
fi

# ==================================================================================================
# GE. No estimated sub-agent token cost is introduced; usage-report.py's existing
# not-locally-observable note is intact.
# ==================================================================================================
if [ -f "$USAGE" ] && grep -qF 'not locally observable' "$USAGE"; then
  ok "GE1: usage-report.py still states sub-agent token cost is not locally observable"
else
  bad "GE1: usage-report.py's not-locally-observable note is missing or the file is gone"
fi

if [ -f "$USAGE" ] && grep -qF 'DISPATCH COUNT only, not a token cost' "$USAGE"; then
  ok "GE2: usage-report.py's DISPATCH COUNT (not token cost) framing is unchanged"
else
  bad "GE2: usage-report.py's DISPATCH COUNT framing sentence is missing"
fi

GE3_HIT=0
for _term in "estimated_token" "token_estimate" "estimated token cost" "modelled token" "token cost estimate"; do
  grep -qi "$_term" "$TM_BLOCK" 2>/dev/null && GE3_HIT=1
  grep -qi "$_term" "$STEP5" 2>/dev/null && GE3_HIT=1
done
if [ "$GE3_HIT" -eq 0 ]; then
  ok "GE3: no estimated/modelled token-cost field or figure appears anywhere in the new Step 5 text"
else
  bad "GE3: an estimated/modelled token-cost term was found in the new Step 5 text (ADR-0064 §D5 violation)"
fi

if grep -qi 'token' "$AM" 2>/dev/null; then
  bad "GE4: agent-metrics.sh mentions tokens — it must compute only test_count_delta/deleted_lines from git"
else
  ok "GE4: agent-metrics.sh contains no token-related computation"
fi

# ==================================================================================================
# GF. No rut detector and no threshold exists (§A5) — the absence is asserted, not just unmentioned.
# ==================================================================================================
GF1_HIT=0
for _term in "rut_threshold" "RUT_THRESHOLD" "if.*iteration_count.*>" "if.*elapsed_wall_seconds.*>"; do
  grep -Eqi "$_term" "$TM_BLOCK" 2>/dev/null && GF1_HIT=1
done
if [ "$GF1_HIT" -eq 0 ]; then
  ok "GF1: no numeric threshold comparison on any ADR-0064 metric exists in the Task-level metrics block"
else
  bad "GF1: a threshold-shaped comparison was found on an ADR-0064 metric — no detector is supposed to exist yet"
fi

if grep -qi 'no such detector' "$TM_BLOCK" || grep -qi 'no.*rut detect' "$TM_BLOCK" || grep -qi 'no.*detector.*exists' "$TM_BLOCK"; then
  ok "GF2: the block explicitly states no rut detector exists yet (ADR-0064 §A5)"
else
  bad "GF2: the block does not explicitly disclaim a rut detector"
fi

if grep -Eqi 'rut.?detect' "$AM" 2>/dev/null; then
  bad "GF3: agent-metrics.sh itself contains rut-detection language — it must be a pure measurement script"
else
  ok "GF3: agent-metrics.sh contains no rut-detection language"
fi

# ==================================================================================================
# GG. Registration in both CI registries, plus the PAIRS deployment entry.
# ==================================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]agent-metrics[[:space:];]'; then
  ok "GG1: docs-ci.yml's shell-tests loop list runs agent-metrics"
else
  bad "GG1: agent-metrics is not in docs-ci.yml's explicit harness list — append it after canonical-mechanism"
fi

if printf '%s' "$DOCSCI_LOOP" | grep -qE 'canonical-mechanism agent-metrics[[:space:];]'; then
  ok "GG1b: agent-metrics is appended immediately after canonical-mechanism, as instructed"
else
  bad "GG1b: agent-metrics is present but not positioned immediately after canonical-mechanism"
fi

CI_YML="$REPO/.github/workflows/ci.yml"
if [ -f "$CI_YML" ] && grep -qE 'tests/\*\.test\.sh|scripts/tests' "$CI_YML"; then
  ok "GG2: ci.yml discovers *.test.sh via a glob (automatic registration, no per-file edit needed)"
else
  bad "GG2: ci.yml does not appear to glob staging/plugin/scripts/tests/*.test.sh — check the workflow"
fi

SYNCSH="$STAGING/sync-to-claude.sh"
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" >"$TMP/pairs"
if grep -qxF 'plugin/skills/concept-to-code/scripts/agent-metrics.sh|skills/concept-to-code/scripts/agent-metrics.sh' "$TMP/pairs"; then
  ok "GG3: PAIRS deploys agent-metrics.sh to ~/.claude/skills/concept-to-code/scripts/, following diff-budget-check.sh's exact registration"
else
  bad "GG3: the agent-metrics.sh PAIRS entry is missing"
fi

if grep -q 'agent-metrics.test' "$TMP/pairs"; then
  bad "GG4: PAIRS gained an entry for this harness — test files do not deploy (diff-budget-scope.test.sh precedent, ADR-0048 §D11)"
else
  ok "GG4: no PAIRS entry for agent-metrics.test.sh (harnesses do not deploy)"
fi

# ==================================================================================================
# GT. The predicate-choice rationale (Task 2's own decision point): reused verbatim from
# test-write-scope.sh (ADR-0049 §D4 denial predicate), not spec-coverage.sh's discovery predicate.
# ==================================================================================================
if [ -f "$TWS" ]; then
  # The exact case-pattern lines this script's predicate must match (order-independent substrings).
  if grep -qF '*.test.*|*.spec.*|test_*|*_test.*|*Test.*|*Tests.*|test-*.sh|run-tests.sh' "$TWS"; then
    ok "GT0: test-write-scope.sh's denial predicate basename pattern is present as expected (anchor for GT1)"
  else
    bad "GT0: could not find test-write-scope.sh's expected basename pattern — GT1 may be meaningless"
  fi
fi

if [ -f "$AM" ] && grep -qF 'test_' "$AM" && grep -qF 'Test\.' "$AM" && grep -qF 'Tests\.' "$AM" \
   && grep -qF 'run-tests.sh' "$AM"; then
  ok "GT1: agent-metrics.sh's predicate carries the same basename shapes as test-write-scope.sh's denial predicate"
else
  bad "GT1: agent-metrics.sh's predicate does not match test-write-scope.sh's denial predicate shape"
fi

if grep -qF 'ADR-0049' "$AM" && grep -qF 'denial' "$AM" && grep -qi 'must not under-match' "$AM"; then
  ok "GT2: agent-metrics.sh documents WHY the denial predicate (not the discovery one) was chosen"
else
  bad "GT2: agent-metrics.sh is missing the predicate-choice rationale citing ADR-0049 and under-matching"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
