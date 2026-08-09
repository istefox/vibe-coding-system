#!/bin/bash
# human-gate-coverage.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash human-gate-coverage.test.sh
#
# Covers issue #115 / ADR-0061: H4 (the commit gate shows the test diff, not a file-list line and
# not a summary) and H16 (a direction check that fires on accumulated evidence, never on a fixed
# cadence).
#
# `HI`-PREFIXED SECTION LABELS. reward-hack-detectors.test.sh already claims HA-HH (its own header
# says so explicitly); grepping all 37 pre-existing harnesses for `\bHI[0-9]` and bare `\bH[0-9]`
# turned up nothing but unrelated hash-length variable names (secret-dep-gate.test.sh's H40/H60/
# H64) and one unrelated assertion-label collision candidate that turned out to be a different
# shape (`H0`/`H1` are ordinary section markers inside reward-hack-detectors.test.sh's OWN `HA`
# section, not a bare-`H` prefix family) — `HI` is free and used here.
#
# NO FIXTURE PATH IN THIS FILE CONTAINS "secret", "credential", ".env", ".pem", or ".key" —
# protect-files.sh denies any path containing "secrets" (plural); this file uses the singular only
# in prose, never in a path.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)

COMMIT_SKILL="$STAGING/plugin/skills/commit/SKILL.md"
CONDUCTOR_SKILL="$STAGING/plugin/skills/project-conductor/SKILL.md"
H16_SCRIPT="$STAGING/plugin/skills/project-conductor/scripts/h16-direction-check.sh"
SYNCSH="$STAGING/sync-to-claude.sh"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
CI_YML="$REPO/.github/workflows/ci.yml"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
TAB=$(printf '\t')

# ====================================================================================
# HI0. Anchors every later section depends on.
# ====================================================================================
if [ -f "$COMMIT_SKILL" ]; then ok "HI0a: commit/SKILL.md exists"; else bad "HI0a: $COMMIT_SKILL not found — HIA/HIB below are meaningless"; fi
if [ -f "$CONDUCTOR_SKILL" ]; then ok "HI0b: project-conductor/SKILL.md exists"; else bad "HI0b: $CONDUCTOR_SKILL not found — HIC below is meaningless"; fi
if [ -f "$H16_SCRIPT" ]; then ok "HI0c: h16-direction-check.sh exists"; else bad "HI0c: $H16_SCRIPT not found — HID below is meaningless"; fi
if [ -x "$H16_SCRIPT" ]; then ok "HI0d: h16-direction-check.sh is executable"; else bad "HI0d: h16-direction-check.sh is not executable"; fi

# ====================================================================================
# HIA. H4 static prose pins in commit/SKILL.md (ADR-0061 §D1/§D4).
# ====================================================================================

# HIA1: the Test diff section is its OWN labelled block, distinct from Pre-commit findings and
# from Files included — not folded into either (§D1's point: a test file as one line in a list is
# the gap being closed).
if grep -q 'Test diff' "$COMMIT_SKILL"; then
  ok "HIA1: a distinct 'Test diff' label exists in commit/SKILL.md"
else
  bad "HIA1: no 'Test diff' label found in commit/SKILL.md"
fi

# HIA2: omitted entirely when empty, not shown empty (§D1, alternative A5 explicitly rejected).
if grep -qi 'omitted entirely' "$COMMIT_SKILL" && grep -qi 'never rendered empty\|not rendered empty' "$COMMIT_SKILL"; then
  ok "HIA2: 'omitted entirely'/'never rendered empty' language present for the Test diff section"
else
  bad "HIA2: no explicit omit-when-empty language for the Test diff section"
fi

# HIA3: shown, not summarised (§D4) — the actual diff, with the word 'verbatim' and an explicit
# 'never a summary' (or equivalent) disclaimer, not merely the word 'diff'.
if grep -qi 'verbatim' "$COMMIT_SKILL" && grep -qiE 'never a (model.s )?summary|not a summary' "$COMMIT_SKILL"; then
  ok "HIA3: 'verbatim' + explicit 'never a summary' language present"
else
  bad "HIA3: no explicit shown-not-summarised language for the test diff"
fi

# HIA4: no LLM-summary step stands between the diff and the human — the block computing test_diff
# must assign it directly from git diff output, never pipe it through anything resembling a
# summarisation call. Scoped to the H4 section only (anchor to the next '###' heading) — the word
# "summarize" legitimately appears elsewhere in this file (Step 6c's CI-failure diagnosis), and a
# whole-file grep would be a false positive on unrelated prose.
H4_SECTION=$(awk '/Test diff \(H4, issue #115/{f=1} f{print} f && /^### /{if(!first){first=1;next} exit}' "$COMMIT_SKILL")
if grep -qE 'test_diff=.*git diff|_one_diff=\$\(git diff' "$COMMIT_SKILL"; then
  ok "HIA4a: test_diff is built directly from git diff output"
else
  bad "HIA4a: test_diff does not appear to be built directly from git diff output"
fi
if printf '%s' "$H4_SECTION" | grep -qiE 'summarize|summarise|Skill\(.*summary'; then
  bad "HIA4b: the H4 section contains summarisation language — ADR-0061 §D4 forbids an LLM-summary step here"
else
  ok "HIA4b: no summarisation step is described for the test diff"
fi

# HIA5: truncation is labelled with the command to see the rest (§D4) — silent truncation must be
# impossible: the truncation branch must both set a flag AND the rendered text must carry the
# git diff command a human can run to see everything.
if grep -q 'test_diff_truncated' "$COMMIT_SKILL" && grep -qE 'git diff HEAD -- <test_files' "$COMMIT_SKILL"; then
  ok "HIA5: truncation sets a flag and the rendered text names the exact command to see the rest"
else
  bad "HIA5: truncation is not labelled with a command to see the rest"
fi

# HIA6: predicate-choice comment — cites the ADR-0048 §D3 divergence (discovery must not
# over-match, denial must not under-match) and states the reused predicate is the BROADER one
# (weakening-scan.sh's is_test()), not spec-coverage.sh's narrower basename-only predicate.
if grep -qF 'ADR-0048' "$COMMIT_SKILL" && grep -qi 'over-match' "$COMMIT_SKILL" && grep -qi 'under-match' "$COMMIT_SKILL"; then
  ok "HIA6a: the ADR-0048 §D3 divergence (over-match / under-match) is cited"
else
  bad "HIA6a: predicate-choice rationale missing the ADR-0048 divergence language"
fi
if grep -qF "weakening-scan.sh" "$COMMIT_SKILL" && grep -qi 'broader predicate' "$COMMIT_SKILL"; then
  ok "HIA6b: commit/SKILL.md names weakening-scan.sh's broader predicate as the one reused"
else
  bad "HIA6b: commit/SKILL.md does not name weakening-scan.sh's predicate as the chosen one"
fi
# HIA6c (RE-ANCHORED — ADR-0132 §D3, issue #385). This assertion used to grep for the IDENTIFIER
# of the classification helper anywhere in commit/SKILL.md — a name that could survive in a stray
# comment on a mechanism-less file just as easily as on a correct one. Task 7 eliminates that
# function outright and inlines its grep -qE at the single call site inside the classification
# loop, so a name-grep would go red on a CORRECT file. Re-pointed at the MECHANISM instead: a
# grep -qE call, applying the classification ERE, co-located with $_f inside the
# `for _f in $staged $tracked_modified $untracked` loop itself — not merely present somewhere in
# the file.
# PLANT DECLARED HERE, NOT AT ITS ORIGINAL RE-ANCHORING (same reason as SFP4 in
# skill-fence-positional-tokens.test.sh): HIA6c was EXPECTED RED before Task 7 inlined the call, so
# a plant declared then would have been worthless — plant-check.sh cannot tell a plant firing from
# an assertion that was already red. Now that Task 7 has landed and HIA6c is green, the deferred
# plant is declared and re-verified from scratch against an isolated copy (not trusted from the
# comment that deferred it): needle "grep -qE" matches exactly once in commit/SKILL.md — the single
# inlined call site inside the classification loop — and mutating it to "grep -q -E" (functionally
# identical, textually distinct) makes HIA6c fail, printing the exact "no grep -qE ... was found"
# message, while HIA7a/HIA7b (which assert the unrelated ERE pattern string, not the command name)
# stay unaffected in both directions.
# plant: HIA6c | plugin/skills/commit/SKILL.md | grep -qE | grep -q -E
LOOP_HDR='for _f in $staged $tracked_modified $untracked; do'
LOOP_BLOCK=$(awk -v hdr="$LOOP_HDR" '$0==hdr{f=1} f{print} f && /^done$/{exit}' "$COMMIT_SKILL")
FLAT_LOOP=$(printf '%s' "$LOOP_BLOCK" | tr '\n' ' ')
if [ -n "$LOOP_BLOCK" ] && printf '%s' "$FLAT_LOOP" | grep -q 'grep -qE' && printf '%s' "$FLAT_LOOP" | grep -qF '$_f'; then
  ok "HIA6c: the classification grep -qE is applied to \$_f inside the classification for-loop (mechanism, not a helper's former name)"
else
  bad "HIA6c: no grep -qE applying the classification ERE to \$_f was found inside the for _f in \$staged \$tracked_modified \$untracked loop"
fi

# HIA7: no third predicate — the regex used must be the SAME shape as weakening-scan.sh's is_test()
# (directory match on tests?/ or spec/, plus the basename patterns), not a hand-rolled narrower one.
WSCAN="$STAGING/plugin/skills/review-triage-fix/scripts/weakening-scan.sh"
# weakening-scan.sh's fragment is awk-literal syntax (backslash-escaped slashes inside /.../);
# commit/SKILL.md's inlined classification grep -qE (ADR-0132 §D3 — the is_test_path() function it
# used to live in was eliminated, not relocated) uses plain grep -E syntax (unescaped slashes) for
# the same semantic pattern — the two representations differ in escaping by construction, not by
# drift.
if [ -f "$WSCAN" ] && grep -qE '\(\^\|\\/\)tests\?\\/' "$WSCAN"; then
  ok "HIA7a: anchor — weakening-scan.sh's is_test() directory-match fragment found (the pattern HIA7b compares against)"
else
  bad "HIA7a: could not find weakening-scan.sh's is_test() directory-match fragment — HIA7b is meaningless"
fi
if grep -qE '\(\^\|/\)tests\?/' "$COMMIT_SKILL" && grep -qE '\(\^\|/\)spec/' "$COMMIT_SKILL"; then
  ok "HIA7b: commit/SKILL.md's inlined classification grep -qE uses the same directory-match fragments as weakening-scan.sh's is_test()"
else
  bad "HIA7b: commit/SKILL.md's predicate does not reuse weakening-scan.sh's directory-match fragments — looks like a third predicate was written"
fi

# ====================================================================================
# HIB. Dynamic extract-and-execute of commit/SKILL.md's H4 block against a real fixture git repo.
# Same technique concept-to-code-bsd-autopilot-gates.test.sh uses for the slug-stamp command:
# pull the fenced bash block by a unique heading anchor, wire in real staged/tracked_modified/
# untracked values computed by real git commands (the exact Step 1 idiom), execute, read results.
# ====================================================================================
extract_h4_block() {
  awk '
    /Test diff \(H4, issue #115/ { grab=1 }
    grab && /```bash/ { infence=1; next }
    grab && infence && /```/ { exit }
    grab && infence { print }
  ' "$COMMIT_SKILL"
}

H4_BLOCK="$TMP/h4-block.sh"
extract_h4_block > "$H4_BLOCK"
if [ -s "$H4_BLOCK" ]; then
  ok "HIB0: the H4 fenced bash block was extracted from commit/SKILL.md (non-empty)"
else
  bad "HIB0: extraction produced an empty block — every HIB assertion below is meaningless"
fi

mk_fixture() {
  _r="$TMP/repo_$1"; rm -rf "$_r"; mkdir -p "$_r/tests"
  ( cd "$_r" && git init -q \
      && printf 'def impl(): pass\n' > impl.py \
      && printf 'def test_impl(): assert True\n' > tests/test_foo.py \
      && git add -A >/dev/null 2>&1 \
      && git -c user.name=t -c user.email=t@t.com -c commit.gpgsign=false commit -q -m baseline )
  printf '%s' "$_r"
}

run_h4() {
  # $1 = fixture repo dir
  _repo="$1"
  _run="$TMP/h4-run-$$-$RANDOM.sh"
  {
    echo '#!/bin/bash'
    echo 'set -u'
    printf 'cd %s || exit 1\n' "$_repo"
    echo 'staged=$(git diff --name-only --staged)'
    echo 'tracked_modified=$(git diff --name-only HEAD --diff-filter=ACMRD)'
    echo 'untracked=$(git ls-files --others --exclude-standard)'
    cat "$H4_BLOCK"
    echo 'printf "TEST_FILES_START\n%s\nTEST_FILES_END\n" "$test_files"'
    echo 'printf "TEST_DIFF_START\n%s\nTEST_DIFF_END\n" "$test_diff"'
    echo 'printf "TRUNCATED=%s\n" "$test_diff_truncated"'
    echo 'printf "TOTAL_LINES=%s\n" "$test_diff_total_lines"'
  } > "$_run"
  bash "$_run" 2>"$TMP/h4-run-err"
}

extract_field() {
  # $1 = full output, $2 = START marker, $3 = END marker
  printf '%s\n' "$1" | awk -v s="$2" -v e="$3" 'BEGIN{f=0} $0==s{f=1;next} $0==e{f=0} f{print}'
}

# HIB1: a tracked test-file change (only) -> test_files non-empty, contains tests/test_foo.py,
# test_diff carries the actual hunk content.
F1=$(mk_fixture b1)
( cd "$F1" && printf 'def test_impl(): assert True\ndef test_more(): assert 1 == 1\n' > tests/test_foo.py )
OUT1=$(run_h4 "$F1")
TF1=$(extract_field "$OUT1" TEST_FILES_START TEST_FILES_END)
TD1=$(extract_field "$OUT1" TEST_DIFF_START TEST_DIFF_END)
if printf '%s\n' "$TF1" | grep -qF 'tests/test_foo.py'; then
  ok "HIB1a: a tracked test-file-only change is discovered in test_files"
else
  bad "HIB1a: tests/test_foo.py not discovered — got test_files=[$TF1]"
fi
if printf '%s\n' "$TD1" | grep -qF 'test_more'; then
  ok "HIB1b: test_diff carries the actual added line (not a summary, not empty)"
else
  bad "HIB1b: test_diff does not carry the expected added content — got: $TD1"
fi

# HIB2: an impl-only change (no test files touched) -> test_files empty, test_diff empty. This is
# the case the Step 4 template must OMIT the section for, per §D1.
F2=$(mk_fixture b2)
( cd "$F2" && printf 'def impl(): return 1\n' > impl.py )
OUT2=$(run_h4 "$F2")
TF2=$(extract_field "$OUT2" TEST_FILES_START TEST_FILES_END)
TD2=$(extract_field "$OUT2" TEST_DIFF_START TEST_DIFF_END)
if [ -z "$(printf '%s' "$TF2" | tr -d '[:space:]')" ]; then
  ok "HIB2a: an impl-only change leaves test_files empty"
else
  bad "HIB2a: test_files should be empty on an impl-only change — got: $TF2"
fi
if [ -z "$(printf '%s' "$TD2" | tr -d '[:space:]')" ]; then
  ok "HIB2b: an impl-only change leaves test_diff empty"
else
  bad "HIB2b: test_diff should be empty on an impl-only change — got: $TD2"
fi

# HIB3: a brand-new, still-UNTRACKED test file must still be discovered and diffed (the same
# tracked-only asymmetry the dependency gate accepts must not repeat here for H4's own purpose).
F3=$(mk_fixture b3)
( cd "$F3" && mkdir -p tests && printf 'def test_new(): assert True\n' > tests/test_new_thing.py )
OUT3=$(run_h4 "$F3")
TF3=$(extract_field "$OUT3" TEST_FILES_START TEST_FILES_END)
TD3=$(extract_field "$OUT3" TEST_DIFF_START TEST_DIFF_END)
if printf '%s\n' "$TF3" | grep -qF 'tests/test_new_thing.py'; then
  ok "HIB3a: a brand-new untracked test file is discovered in test_files"
else
  bad "HIB3a: untracked new test file not discovered — got: $TF3"
fi
if printf '%s\n' "$TD3" | grep -qF 'test_new'; then
  ok "HIB3b: the untracked new test file's content appears in test_diff"
else
  bad "HIB3b: untracked new test file content missing from test_diff — got: $TD3"
fi

# HIB4: truncation. A test-file diff well over TEST_DIFF_MAX_LINES (400) must set
# test_diff_truncated=1 and cap the rendered diff at 400 lines — never silently show a partial
# diff with no flag.
F4=$(mk_fixture b4)
( cd "$F4" && awk 'BEGIN{for(i=0;i<600;i++) printf "def test_%d(): assert True\n", i}' > tests/test_foo.py )
OUT4=$(run_h4 "$F4")
TRUNC4=$(printf '%s\n' "$OUT4" | sed -n 's/^TRUNCATED=//p')
TOTAL4=$(printf '%s\n' "$OUT4" | sed -n 's/^TOTAL_LINES=//p')
TD4=$(extract_field "$OUT4" TEST_DIFF_START TEST_DIFF_END)
TD4_LINES=$(printf '%s\n' "$TD4" | wc -l | tr -d ' ')
if [ "${TRUNC4:-0}" = "1" ]; then
  ok "HIB4a: a 600+ line test diff sets test_diff_truncated=1"
else
  bad "HIB4a: a 600+ line test diff did not set test_diff_truncated=1 (got TRUNCATED=$TRUNC4, TOTAL_LINES=$TOTAL4)"
fi
if [ -n "$TD4_LINES" ] && [ "$TD4_LINES" -le 400 ]; then
  ok "HIB4b: the rendered test_diff is capped at 400 lines when truncated (got $TD4_LINES)"
else
  bad "HIB4b: the rendered test_diff was not capped — got $TD4_LINES lines"
fi

# HIB5: silent truncation is impossible — assert commit/SKILL.md's Step 4 template renders the
# truncation label CONDITIONALLY on test_diff_truncated, not as separate, disconnected prose that
# could be true even when nothing was actually truncated.
if grep -qE 'test_diff_truncated=1.*(truncated to|see the rest)|if.*test_diff_truncated' "$COMMIT_SKILL"; then
  ok "HIB5: the truncation label is conditioned on test_diff_truncated, not unconditional prose"
else
  bad "HIB5: no conditional wiring found between test_diff_truncated and the rendered label"
fi

# ====================================================================================
# HIC. H16 static prose pins in project-conductor/SKILL.md (ADR-0061 §D2/§D3).
# ====================================================================================

# HIC1: H16 lives at the Step 5 "current_step = completed" seam, right where a feature finishes.
if grep -q 'H16' "$CONDUCTOR_SKILL"; then
  ok "HIC1a: H16 is named in project-conductor/SKILL.md"
else
  bad "HIC1a: H16 not found in project-conductor/SKILL.md"
fi
if grep -qF 'h16-direction-check.sh' "$CONDUCTOR_SKILL"; then
  ok "HIC1b: h16-direction-check.sh is invoked from project-conductor/SKILL.md"
else
  bad "HIC1b: h16-direction-check.sh is not referenced from project-conductor/SKILL.md"
fi

# HIC2: attended-mode-only gating — autopilot has no human to ask (ADR-0022), so H16 must be
# explicitly skipped when _autopilot=true.
if grep -qF '_autopilot=false' "$CONDUCTOR_SKILL" | head -1; then :; fi
H16_BLOCK=$(awk '/H16 — direction check/{f=1} f{print} f && /^- On success, return to Step 2\./{exit}' "$CONDUCTOR_SKILL")
if printf '%s' "$H16_BLOCK" | grep -qF '_autopilot=false' && printf '%s' "$H16_BLOCK" | grep -qi 'skipped when'; then
  ok "HIC2: H16 is explicitly gated to attended mode only (_autopilot=false)"
else
  bad "HIC2: H16 does not explicitly condition itself on attended mode"
fi

# HIC3: H16 asks, does not block (§D3) — must use AskUserQuestion-shaped prose and must NOT use
# halt/abort language for its own trigger.
if printf '%s' "$H16_BLOCK" | grep -qi 'question:' && printf '%s' "$H16_BLOCK" | grep -qi 'never halts'; then
  ok "HIC3a: H16 is phrased as a question, and explicitly states it never halts on its own"
else
  bad "HIC3a: H16 is missing either the question framing or the never-halts statement"
fi
if printf '%s' "$H16_BLOCK" | grep -qiE '\babort\b|\bhalt the roadmap\b'; then
  bad "HIC3b: H16's own block uses abort/halt language — §D3 requires it to ask, not block"
else
  ok "HIC3b: H16's block contains no abort/halt-the-roadmap language of its own"
fi

# HIC4 — THE MOST IMPORTANT ASSERTION IN THIS FILE (ADR-0061 §D2's guard). H16 must trigger on
# accumulated EVIDENCE, never on a fixed cadence (every N features, every N commits, a modulo
# counter). Assert the absence of every shape that pattern would take, in BOTH the prose (project-
# conductor/SKILL.md) and the script (h16-direction-check.sh) — a cadence counter hiding in either
# place defeats the whole point.
# CADENCE_RE deliberately excludes the bare word "cadence" on its own — this file's own header
# and h16-direction-check.sh's header both legitimately use it INSIDE a disclaimer ("this is not a
# fixed-cadence counter"), and a bare-word match would flag the disclaimer that proves the point.
# What must never appear is an actual cadence PATTERN: a fixed period, a modulo, a running
# feature/commit counter used as a trigger condition.
CADENCE_RE='every [0-9]+ feature|every [0-9]+ commit|every third|every other feature|feature_count|features_since|% *[0-9]+ *==|%[0-9]+==|mod +[0-9]+|fixed[- ]cadence (counter|trigger|schedule)'
# Strip disclaimer lines (the ones that legitimately say "not a fixed-cadence ...") before
# matching, in both the prose block and the script, so the disclaimer itself is never mistaken
# for a violation.
H16_BLOCK_NO_DISCLAIMER=$(printf '%s' "$H16_BLOCK" | grep -viE 'not a fixed-cadence|never a fixed-cadence')
if printf '%s' "$H16_BLOCK_NO_DISCLAIMER" | grep -qiE "$CADENCE_RE"; then
  bad "HIC4a: project-conductor/SKILL.md's H16 block contains fixed-cadence language — this is exactly what ADR-0061 §D2 rejects"
else
  ok "HIC4a: no fixed-cadence language in project-conductor/SKILL.md's H16 block"
fi
if [ -f "$H16_SCRIPT" ] && grep -viE 'not a fixed-cadence|never a fixed-cadence' "$H16_SCRIPT" | grep -qiE "$CADENCE_RE"; then
  bad "HIC4b: h16-direction-check.sh contains fixed-cadence language"
else
  ok "HIC4b: h16-direction-check.sh contains no fixed-cadence language"
fi
# No persisted invocation counter either — the script must not write ANY file (a counter file
# would be a fixed-cadence mechanism in disguise, and also a new persisted store Task 3 forbids).
# Excludes stderr redirects (2>/dev/null, 2>&1) and jq's own >/>= comparison operators (which are
# never followed by a quote-and-dollar or a second '>'), matching only real shell output
# redirection: '>>' (append) or '> "$...' (write into a quoted path/variable).
if [ -f "$H16_SCRIPT" ] && grep -v '2>/dev/null\|2>&1' "$H16_SCRIPT" | grep -qE '>>|> *"\$'; then
  bad "HIC4c: h16-direction-check.sh appears to write to a file — a persisted counter/store would defeat the evidence-based design and Task 3's 'no new advisory array' constraint"
else
  ok "HIC4c: h16-direction-check.sh writes nothing to disk (stdout only, reporter contract)"
fi

# HIC5: H16 reads the four named signal families (tracer, budget, out-of-scope, suspect) and no
# others invented for this feature.
if grep -qF 'tracer_bullet_verdict' "$H16_SCRIPT" 2>/dev/null \
   && grep -qF 'budget_findings' "$H16_SCRIPT" 2>/dev/null \
   && grep -qF 'out_of_scope' "$H16_SCRIPT" 2>/dev/null \
   && grep -qF 'suspect_findings' "$H16_SCRIPT" 2>/dev/null; then
  ok "HIC5: h16-direction-check.sh reads all four named signal families"
else
  bad "HIC5: h16-direction-check.sh is missing one or more of the four named signal families"
fi

# HIC6: Task 4's reachability finding is disclosed in the script, not silently assumed — the
# header must state that budget/out-of-scope/suspect are NOT accumulated across features, and
# must state WHY (step5-report.json is a single overwritten path).
if grep -qi 'not.*accumulate.*across features\|same-feature evidence only' "$H16_SCRIPT" 2>/dev/null \
   && grep -qF 'step5-report.json' "$H16_SCRIPT" 2>/dev/null \
   && grep -qi 'overwrit' "$H16_SCRIPT" 2>/dev/null; then
  ok "HIC6: the script discloses which signals are NOT cross-feature-accumulated, and why"
else
  bad "HIC6: the script does not disclose the reachability gap for budget/out-of-scope/suspect findings"
fi

# ====================================================================================
# HID. Dynamic behaviour of h16-direction-check.sh (reporter contract, ADR-0061 §D2/§D3).
# ====================================================================================

mk_h16_root() {
  _r="$TMP/h16root_$1"; rm -rf "$_r"; mkdir -p "$_r/docs/manifests" "$_r/.claude"
  printf '%s' "$_r"
}

# HID1: reporter fail-open — a missing --root still exits 0 and prints CLEAN, never a checker-style
# non-zero exit (same BT1 contract diff-budget-scope.test.sh already pins for its neighbour).
H16_OUT=$(bash "$H16_SCRIPT" --root "$TMP/does-not-exist-$$" --this-manifest "/dev/null" 2>/dev/null); H16_RC=$?
if [ "$H16_OUT" = "CLEAN" ] && [ "$H16_RC" -eq 0 ]; then
  ok "HID1: a missing --root still prints CLEAN and exits 0 (fail-open, reporter contract)"
else
  bad "HID1: expected CLEAN/exit 0 on a missing --root — got out=[$H16_OUT] rc=$H16_RC"
fi

# HID2: no manifests, no step5-report -> CLEAN.
R2=$(mk_h16_root d2)
OUT2=$(bash "$H16_SCRIPT" --root "$R2" --this-manifest "$R2/docs/manifests/none.manifest.yml" 2>/dev/null); RC2=$?
if [ "$OUT2" = "CLEAN" ] && [ "$RC2" -eq 0 ]; then
  ok "HID2: an empty roadmap (no manifests, no report) is CLEAN"
else
  bad "HID2: expected CLEAN — got out=[$OUT2] rc=$RC2"
fi

# HID3: a single amber manifest triggers the tracer signal, exit still 0 (never blocks, §D3).
R3=$(mk_h16_root d3)
printf 'topic: "a"\ntracer_bullet_verdict: "amber"\n' > "$R3/docs/manifests/2026-01-01-a.manifest.yml"
OUT3=$(bash "$H16_SCRIPT" --root "$R3" --this-manifest "$R3/docs/manifests/2026-01-01-a.manifest.yml" 2>/dev/null); RC3=$?
if printf '%s\n' "$OUT3" | grep -q '^TRIGGER	tracer-amber-red' && [ "$RC3" -eq 0 ]; then
  ok "HID3: a single amber tracer verdict triggers tracer-amber-red, exit 0"
else
  bad "HID3: expected a TRIGGER tracer-amber-red line, exit 0 — got out=[$OUT3] rc=$RC3"
fi

# HID4: a green-only manifest set never triggers the tracer signal.
R4=$(mk_h16_root d4)
printf 'topic: "b"\ntracer_bullet_verdict: "green"\n' > "$R4/docs/manifests/2026-01-01-b.manifest.yml"
OUT4=$(bash "$H16_SCRIPT" --root "$R4" --this-manifest "$R4/docs/manifests/2026-01-01-b.manifest.yml" 2>/dev/null)
if [ "$OUT4" = "CLEAN" ]; then
  ok "HID4: an all-green manifest set is CLEAN"
else
  bad "HID4: expected CLEAN on all-green manifests — got: $OUT4"
fi

# HID5: budget overshoot — 2+ budget_findings entries in the just-finished feature's
# step5-report.json triggers budget-overshoot; 1 entry does not (guards against a trivial
# threshold that would fire on every feature that used a budget at all).
R5=$(mk_h16_root d5)
printf '{"budget_findings":[{"task":"1","out_of_scope":[]},{"task":"2","out_of_scope":[]}],"suspect_findings":[]}' > "$R5/.claude/step5-report.json"
OUT5=$(bash "$H16_SCRIPT" --root "$R5" --this-manifest "$R5/docs/manifests/none.manifest.yml" 2>/dev/null)
if printf '%s\n' "$OUT5" | grep -q '^TRIGGER	budget-overshoot'; then
  ok "HID5a: 2 budget_findings entries trigger budget-overshoot"
else
  bad "HID5a: expected TRIGGER budget-overshoot — got: $OUT5"
fi
R5b=$(mk_h16_root d5b)
printf '{"budget_findings":[{"task":"1","out_of_scope":[]}],"suspect_findings":[]}' > "$R5b/.claude/step5-report.json"
OUT5b=$(bash "$H16_SCRIPT" --root "$R5b" --this-manifest "$R5b/docs/manifests/none.manifest.yml" 2>/dev/null)
if [ "$OUT5b" = "CLEAN" ]; then
  ok "HID5b: a single budget_findings entry alone is CLEAN (not every budgeted task is evidence)"
else
  bad "HID5b: expected CLEAN on a single budget_findings entry — got: $OUT5b"
fi

# HID6: out-of-scope — 2+ budget_findings entries with a non-empty out_of_scope list trigger
# out-of-scope.
R6=$(mk_h16_root d6)
printf '{"budget_findings":[{"task":"1","out_of_scope":["a.py"]},{"task":"2","out_of_scope":["b.py"]}],"suspect_findings":[]}' > "$R6/.claude/step5-report.json"
OUT6=$(bash "$H16_SCRIPT" --root "$R6" --this-manifest "$R6/docs/manifests/none.manifest.yml" 2>/dev/null)
if printf '%s\n' "$OUT6" | grep -q '^TRIGGER	out-of-scope'; then
  ok "HID6: 2 out-of-scope findings trigger out-of-scope"
else
  bad "HID6: expected TRIGGER out-of-scope — got: $OUT6"
fi

# HID7: suspect_findings recurring by detector, and by file, both trigger suspect-recurring;
# two DIFFERENT single findings (no repeat of either dimension) do not.
R7=$(mk_h16_root d7)
printf '{"budget_findings":[],"suspect_findings":[{"file":"a.py","detector":"zero-assertion-test"},{"file":"a.py","detector":"zero-assertion-test"}]}' > "$R7/.claude/step5-report.json"
OUT7=$(bash "$H16_SCRIPT" --root "$R7" --this-manifest "$R7/docs/manifests/none.manifest.yml" 2>/dev/null)
if printf '%s\n' "$OUT7" | grep -q '^TRIGGER	suspect-recurring'; then
  ok "HID7a: two suspect_findings sharing file AND detector trigger suspect-recurring"
else
  bad "HID7a: expected TRIGGER suspect-recurring — got: $OUT7"
fi
R7b=$(mk_h16_root d7b)
printf '{"budget_findings":[],"suspect_findings":[{"file":"a.py","detector":"zero-assertion-test"},{"file":"b.py","detector":"swallowed-error"}]}' > "$R7b/.claude/step5-report.json"
OUT7b=$(bash "$H16_SCRIPT" --root "$R7b" --this-manifest "$R7b/docs/manifests/none.manifest.yml" 2>/dev/null)
if [ "$OUT7b" = "CLEAN" ]; then
  ok "HID7b: two suspect_findings sharing neither file nor detector do not trigger"
else
  bad "HID7b: expected CLEAN on two unrelated suspect_findings — got: $OUT7b"
fi

# HID8: reporter trap restated at the call site (ADR-0048 §D7 precedent) — never exits non-zero,
# even on a completely malformed step5-report.json (jq failure must degrade silently, not crash).
R8=$(mk_h16_root d8)
printf 'not valid json{{{' > "$R8/.claude/step5-report.json"
OUT8=$(bash "$H16_SCRIPT" --root "$R8" --this-manifest "$R8/docs/manifests/none.manifest.yml" 2>/dev/null); RC8=$?
if [ "$RC8" -eq 0 ]; then
  ok "HID8: malformed step5-report.json still exits 0 (degrades, never fails)"
else
  bad "HID8: malformed step5-report.json produced a non-zero exit ($RC8) — reporter contract broken"
fi

# HID9: running the SAME clean fixture N times in a row never trigers on the Nth run merely
# because it is the Nth run — the direct behavioural proof that this is not a disguised counter.
R9=$(mk_h16_root d9)
printf 'topic: "c"\ntracer_bullet_verdict: "green"\n' > "$R9/docs/manifests/2026-01-01-c.manifest.yml"
N9=0; ALL_CLEAN=1
while [ "$N9" -lt 5 ]; do
  O9=$(bash "$H16_SCRIPT" --root "$R9" --this-manifest "$R9/docs/manifests/2026-01-01-c.manifest.yml" 2>/dev/null)
  [ "$O9" = "CLEAN" ] || ALL_CLEAN=0
  N9=$((N9 + 1))
done
if [ "$ALL_CLEAN" -eq 1 ]; then
  ok "HID9: five consecutive runs against unchanged clean evidence all stay CLEAN — no invocation-count state"
else
  bad "HID9: repeated runs against unchanged clean evidence eventually triggered — looks like hidden counter state"
fi

# ====================================================================================
# HIE. Registration in both CI registries (ci.yml glob automatic; docs-ci.yml explicit named
# list needs a manual append after external-dependency-gate) plus PAIRS for the new script.
# ====================================================================================
if [ -f "$DOCSCI" ]; then
  ok "HIE0a: docs-ci.yml is where this harness expects it"
else
  bad "HIE0a: $DOCSCI not found — HIE1 below is meaningless"
fi
if [ -f "$SYNCSH" ]; then
  ok "HIE0b: sync-to-claude.sh is where this harness expects it"
else
  bad "HIE0b: $SYNCSH not found — HIE3 below is meaningless"
fi

DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]human-gate-coverage[[:space:];]'; then
  ok "HIE1: docs-ci.yml's shell-tests loop list runs human-gate-coverage"
else
  bad "HIE1: human-gate-coverage is not in docs-ci.yml's explicit harness list — append it after external-dependency-gate"
fi
if printf '%s' "$DOCSCI_LOOP" | grep -qE 'external-dependency-gate human-gate-coverage'; then
  ok "HIE1b: human-gate-coverage is positioned immediately after external-dependency-gate in docs-ci.yml's list"
else
  bad "HIE1b: human-gate-coverage is not positioned right after external-dependency-gate in docs-ci.yml's list"
fi

if grep -q 'staging/plugin/scripts/tests/\*\.test\.sh' "$CI_YML" 2>/dev/null; then
  ok "HIE2: ci.yml discovers *.test.sh via a glob (automatic registration, no per-file edit needed)"
else
  bad "HIE2: ci.yml does not appear to glob staging/plugin/scripts/tests/*.test.sh — check the workflow"
fi

awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" > "$TMP/pairs"
if grep -qxF 'plugin/skills/project-conductor/scripts/h16-direction-check.sh|skills/project-conductor/scripts/h16-direction-check.sh' "$TMP/pairs"; then
  ok "HIE3: PAIRS deploys h16-direction-check.sh to ~/.claude/skills/project-conductor/scripts/"
else
  bad "HIE3: no PAIRS entry for h16-direction-check.sh — edits will never deploy"
fi
if grep -q 'human-gate-coverage' "$TMP/pairs"; then
  bad "HIE4: PAIRS gained an entry for the harness itself — it validates staging/ and runs in this repo's CI, no deploy"
else
  ok "HIE4: no PAIRS entry for the harness itself (matches every harness added since ADR-0041)"
fi

# ====================================================================================
# HIF. Repo-root SPEC.md pin check (plan Task 5's explicit instruction). This harness itself must
# not pin the repo-root SPEC.md's content anywhere above (it does not — it never reads SPEC.md at
# all), stated here as a forward guard so a future edit that adds one trips this assertion.
# ====================================================================================
if grep -qE '\$REPO/SPEC\.md|\breads? .*root SPEC\.md' "$0" 2>/dev/null; then
  bad "HIF1: this harness itself appears to read/pin the repo-root SPEC.md — that file rotates per feature in flight (see #114's fix to #113's harness)"
else
  ok "HIF1: this harness does not pin the repo-root SPEC.md (forward guard)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
