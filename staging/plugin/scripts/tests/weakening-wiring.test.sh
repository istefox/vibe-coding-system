#!/bin/bash
# weakening-wiring.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash weakening-wiring.test.sh
#
# Covers issue #101 / ADR-0047: wiring the existing anti-test-weakening detector
# (review-triage-fix/scripts/weakening-scan.sh) into every unattended path that can
# produce a commit — concept-to-code Step 5, autopilot-build, nightly-autopilot, commit
# Step 1.
#
# THE DETECTOR IS NOT MODIFIED BY THIS FEATURE. Not one byte of
# staging/plugin/skills/review-triage-fix/ changes (ADR-0047 §D1). What changes is who
# calls the script and what a caller does with a finding.
#
# ASSERTION LABELS ARE W-PREFIXED (WA1, WC3, WF2, ...) to stay distinguishable from
# secret-dep-gate.test.sh's bare F1-F6 in the same CI log — both files print into the
# same shell-tests job.
#
# THE FIXTURE DIFFS HERE CONTAIN NO KEY-SHAPED LITERAL. secret-dep-gate.test.sh section D
# scans this repository's tracked files (via git ls-files) as its false-positive corpus,
# so a key-shaped string dropped into a fixture in this file would turn that harness red.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ==============================================================================================
# WA. Detector contract (FORWARD GUARDS, green on arrival, never fix evidence). The detector is
# untouched by this feature — these assertions pin its existing behaviour so a later change to
# the script (issue #105) trips a red test here rather than silently changing what every caller
# in this feature relies on.
# ==============================================================================================
W="$STAGING/plugin/skills/review-triage-fix/scripts/weakening-scan.sh"

if [ -f "$W" ]; then
  ok "WA0: weakening-scan.sh exists at the in-place path (the anchor every WA/WB assertion reads)"
else
  bad "WA0: $W not found — every WA/WB assertion below is meaningless"
fi

clean_out=$(printf '' | bash "$W" 2>"$TMP/wa1err"); clean_rc=$?
if [ "$clean_out" = "CLEAN" ] && [ "$clean_rc" -eq 0 ]; then
  ok "WA1: empty stdin -> output is exactly CLEAN, exit 0"
else
  bad "WA1: expected CLEAN/exit 0 on empty stdin — got out=[$clean_out] rc=$clean_rc"
fi

cat >"$TMP/wa2.diff" <<'EOF'
diff --git a/src/app.py b/src/app.py
--- a/src/app.py
+++ b/src/app.py
@@ -1,2 +1,3 @@
 def f():
+    return 1
 pass
EOF
wa2_out=$(bash "$W" <"$TMP/wa2.diff" 2>"$TMP/wa2err")
if [ "$wa2_out" = "CLEAN" ]; then
  ok "WA2: a non-test diff (src/app.py) -> CLEAN"
else
  bad "WA2: expected CLEAN for a non-test diff — got: $wa2_out"
fi

cat >"$TMP/wa3.diff" <<'EOF'
diff --git a/tests/test_y.py b/tests/test_y.py
deleted file mode 100644
--- a/tests/test_y.py
+++ /dev/null
@@ -1,3 +0,0 @@
-def test_y():
-    assert True
-    pass
EOF
weak_out=$(bash "$W" <"$TMP/wa3.diff" 2>"$TMP/wa3err"); weak_rc=$?
if printf '%s\n' "$weak_out" | grep -q '^WEAKENED' \
   && printf '%s\n' "$weak_out" | grep -q 'deleted-test-file'; then
  ok "WA3: a deleted test file diff -> a WEAKENED line containing deleted-test-file"
else
  bad "WA3: expected a WEAKENED/deleted-test-file line — got: $weak_out"
fi

cat >"$TMP/wa4.diff" <<'EOF'
diff --git a/tests/test_x.py b/tests/test_x.py
--- a/tests/test_x.py
+++ b/tests/test_x.py
@@ -1,3 +1,4 @@
+@pytest.mark.skip
 def test_x():
     assert True
EOF
wa4_out=$(bash "$W" <"$TMP/wa4.diff" 2>"$TMP/wa4err"); wa4_rc=$?
if printf '%s\n' "$wa4_out" | grep -q '^WEAKENED' \
   && printf '%s\n' "$wa4_out" | grep -q 'skip/xfail-added'; then
  ok "WA4: a diff adding @pytest.mark.skip -> a WEAKENED line containing skip/xfail-added"
else
  bad "WA4: expected a WEAKENED/skip-xfail-added line — got: $wa4_out"
fi

if [ "$weak_rc" -eq 0 ] && [ "$wa4_rc" -eq 0 ]; then
  ok "WA5: exit code is 0 in the finding case as well as the clean case (reporter contract, §D3)"
else
  bad "WA5: expected exit 0 on both finding cases — got weak_rc=$weak_rc wa4_rc=$wa4_rc"
fi

# ------------------------------------------------------------------------------------------
# WA6-WA9. is_skip_add() unanchored-regex defect. The skip/xfail-added alternation
# (`xit\(`, `\.skip\(`, ...) has no word-boundary or line-start anchor, so it matches these
# tokens as a bare substring of unrelated code. Two of the alternatives are demonstrated here
# against realistic host-language idioms (not fixture-only strings): `xit\(` against Python's
# `sys.exit(`/`process.exit(` family, and `\.skip\(` against RxJS's `Observable.skip(n)`
# operator. Every positive twin below stays green before AND after the fix — proof the repair
# is an anchor, not a deletion of the alternative (which would silently drop real coverage of
# xit()/.skip() disabled-test directives).
#
# The other alternatives in the same regex (`\.only\(`, `xdescribe\(`, `t\.Skip\(`,
# `@Disabled`, `@Ignore`, `@unittest\.skip`, `@pytest\.mark\.(skip|xfail)`) were checked for a
# comparably realistic false positive and none was found: `.only(` has no common non-test
# method of that literal shape; `@Disabled`/`@Ignore`/`@unittest.skip` unanchored-match only
# variant *forms of the same skip mechanism* (`@DisabledOnOs`, `@unittest.skipIf`), which is
# still correct classification, not a false positive; `xdescribe(` and `t.Skip(` are specific
# enough tokens that no unrelated-code collision was found. No assertion added for these —
# not padding this section with unproven claims.
# ------------------------------------------------------------------------------------------

# WA6 — RED NOW (the pinned defect). A test file adding an ordinary `sys.exit(0)` call must NOT
# be classified as a disabled-test directive. It is today, because `xit\(` is unanchored and
# matches the tail of "sys.exit(0)" as a bare substring.
cat >"$TMP/wa6.diff" <<'EOF'
diff --git a/tests/test_backup.py b/tests/test_backup.py
--- a/tests/test_backup.py
+++ b/tests/test_backup.py
@@ -1,3 +1,4 @@
 def test_backup_exits_cleanly():
+    sys.exit(0)
     assert True
EOF
wa6_out=$(bash "$W" <"$TMP/wa6.diff" 2>"$TMP/wa6err")
if printf '%s\n' "$wa6_out" | grep -q '^WEAKENED' && printf '%s\n' "$wa6_out" | grep -q 'skip/xfail-added'; then
  bad "WA6: a test file adding sys.exit(0) is misclassified as WEAKENED/skip-xfail-added (xit( is unanchored) — got: $wa6_out"
else
  ok "WA6: a test file adding sys.exit(0) does NOT produce a WEAKENED/skip-xfail-added finding"
fi

# WA7 — positive twin for WA6, mandatory. A genuine Jasmine/Mocha xit() disabled-test directive
# must still be caught, both before and after the anchoring fix — otherwise "fixing" WA6 by
# simply deleting the xit( alternative would pass WA6 for the wrong reason.
cat >"$TMP/wa7.diff" <<'EOF'
diff --git a/foo.test.js b/foo.test.js
--- a/foo.test.js
+++ b/foo.test.js
@@ -1,2 +1,3 @@
 describe('suite', () => {
+  xit('should do the thing', () => { expect(1).toBe(1); });
 });
EOF
wa7_out=$(bash "$W" <"$TMP/wa7.diff" 2>"$TMP/wa7err")
if printf '%s\n' "$wa7_out" | grep -q '^WEAKENED' && printf '%s\n' "$wa7_out" | grep -q 'skip/xfail-added'; then
  ok "WA7: a genuine xit(...) disabled-test directive still produces WEAKENED/skip-xfail-added"
else
  bad "WA7: expected a WEAKENED/skip-xfail-added line for a real xit(...) directive — got: $wa7_out"
fi

# WA8 — RED NOW, same defect class, second alternative. `\.skip\(` is also unanchored and
# matches RxJS's `Observable.skip(n)` operator (skip the first n emissions), a real operator
# with no relation to disabling a test — realistic in any test file exercising an RxJS stream.
cat >"$TMP/wa8.diff" <<'EOF'
diff --git a/rx.test.ts b/rx.test.ts
--- a/rx.test.ts
+++ b/rx.test.ts
@@ -1,2 +1,3 @@
 it('drops the first values', () => {
+  source$.skip(2).subscribe(x => results.push(x));
 });
EOF
wa8_out=$(bash "$W" <"$TMP/wa8.diff" 2>"$TMP/wa8err")
if printf '%s\n' "$wa8_out" | grep -q '^WEAKENED' && printf '%s\n' "$wa8_out" | grep -q 'skip/xfail-added'; then
  bad "WA8: a test file adding the RxJS .skip(n) operator is misclassified as WEAKENED/skip-xfail-added (\\.skip\\( is unanchored) — got: $wa8_out"
else
  ok "WA8: a test file adding the RxJS .skip(n) operator does NOT produce a WEAKENED/skip-xfail-added finding"
fi

# WA9 — positive twin for WA8, mandatory. A genuine Jest/Jasmine `test.skip(...)` disabled-test
# directive must still be caught, both before and after the anchoring fix.
cat >"$TMP/wa9.diff" <<'EOF'
diff --git a/foo.test.js b/foo.test.js
--- a/foo.test.js
+++ b/foo.test.js
@@ -1,2 +1,3 @@
 describe('suite', () => {
+  test.skip('runs later', () => { expect(1).toBe(1); });
 });
EOF
wa9_out=$(bash "$W" <"$TMP/wa9.diff" 2>"$TMP/wa9err")
if printf '%s\n' "$wa9_out" | grep -q '^WEAKENED' && printf '%s\n' "$wa9_out" | grep -q 'skip/xfail-added'; then
  ok "WA9: a genuine test.skip(...) disabled-test directive still produces WEAKENED/skip-xfail-added"
else
  bad "WA9: expected a WEAKENED/skip-xfail-added line for a real test.skip(...) directive — got: $wa9_out"
fi

# ==============================================================================================
# WB. The caller idiom, EXECUTED against the real script (contract evidence, green on arrival).
# Uses the outputs captured in WA above. §D3 is the rule; this is the proof against the real
# binary rather than a description of it.
# ==============================================================================================
if printf '%s\n' "$clean_out" | grep -q '^WEAKENED'; then
  bad "WB1: grep -q '^WEAKENED' unexpectedly TRUE on CLEAN output"
else
  ok "WB1: printf '%s\\n' \"\$clean_out\" | grep -q '^WEAKENED' is FALSE on a clean scan"
fi

if printf '%s\n' "$weak_out" | grep -q '^WEAKENED'; then
  ok "WB2: printf '%s\\n' \"\$weak_out\" | grep -q '^WEAKENED' is TRUE on a finding"
else
  bad "WB2: expected grep -q '^WEAKENED' to be TRUE on a diff with a finding"
fi

# WB3 — the trap. [ -n "$out" ] is TRUE even on CLEAN output, so a caller written by analogy with
# ADR-0046's two reporters (non-empty stdout means a finding) blocks EVERY run of this detector.
if [ -n "$clean_out" ]; then
  ok "WB3: [ -n \"\$clean_out\" ] is TRUE on CLEAN output — emptiness-gating would block every run"
else
  bad "WB3: CLEAN output was empty — the sentinel trap did not reproduce, something is wrong upstream"
fi

# WB4 — the count trap. grep -c prints 0 AND exits 1 on no match, so "|| echo 0" appends a SECOND
# line and the result is the two-line string "0\n0"; "|| true" leaves the single line "0".
wb4_wrong=$(printf '%s\n' "$clean_out" | grep -c '^WEAKENED' || echo 0)  # idiom-demo (plan-task-count.test.sh PTD)
wb4_right=$(printf '%s\n' "$clean_out" | grep -c '^WEAKENED' || true)
wb4_wrong_lines=$(printf '%s\n' "$wb4_wrong" | grep -c .)
if [ "$wb4_wrong_lines" -eq 2 ] && [ "$wb4_right" = "0" ]; then
  ok "WB4: grep -c ... || echo 0 yields two lines ([$wb4_wrong]); || true yields the single line 0"
else
  bad "WB4: expected two-line ||echo0 and single-line ||true — got wrong=[$wb4_wrong] right=[$wb4_right]"
fi

# ==============================================================================================
# WH. review-triage-fix untouched. Behaviour + anchors, deliberately NOT a checksum: issue #105
# will legitimately change the detector, and a hash would make that feature fight this test.
# ==============================================================================================
RTF="$STAGING/plugin/skills/review-triage-fix/SKILL.md"

if grep -qF -e 'CIRCUIT BREAKER B — hard-fail anti-test-weakening.' "$RTF"; then
  ok "WH1: review-triage-fix/SKILL.md still contains CIRCUIT BREAKER B's hard-fail sentence"
else
  bad "WH1: CIRCUIT BREAKER B sentence missing from $RTF"
fi

if grep -qF 'scripts/weakening-scan.sh' "$RTF"; then
  ok "WH2: review-triage-fix/SKILL.md still contains scripts/weakening-scan.sh (its own harness anchor)"
else
  bad "WH2: scripts/weakening-scan.sh reference missing from $RTF"
fi

if grep -qF 'weakening_findings' "$RTF" || grep -qF 'ADR-0047' "$RTF"; then
  bad "WH3: this feature's wiring leaked into review-triage-fix/SKILL.md (weakening_findings or ADR-0047 found)"
else
  ok "WH3: review-triage-fix/SKILL.md contains neither weakening_findings nor ADR-0047"
fi

# ==============================================================================================
# WG. Registration (ADR-0047 §D10). No new script and no new PAIRS entry — the detector's PAIRS
# entry has existed since it was vendored, and this section just confirms it is still there.
# ==============================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
SYNCSH="$STAGING/sync-to-claude.sh"

DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]weakening-wiring[[:space:];]'; then
  ok "WG1: docs-ci.yml's shell-tests loop list runs weakening-wiring"
else
  bad "WG1: weakening-wiring is not in docs-ci.yml's explicit harness list — append it (Task 8)"
fi

awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" >"$TMP/pairs"
if grep -qxF 'plugin/skills/review-triage-fix/scripts/weakening-scan.sh|skills/review-triage-fix/scripts/weakening-scan.sh' "$TMP/pairs"; then
  ok "WG2: PAIRS still deploys weakening-scan.sh to ~/.claude/skills/review-triage-fix/scripts/ (three more skills now depend on this line)"
else
  bad "WG2: the weakening-scan.sh PAIRS entry is missing — edits to it would never deploy"
fi

if grep -q 'weakening-wiring' "$TMP/pairs"; then
  bad "WG3: PAIRS gained an entry for this harness — ADR-0047 §D10 says it does not deploy"
else
  ok "WG3: no PAIRS entry for weakening-wiring.test.sh (ADR-0047 §D10)"
fi

# ==============================================================================================
# WC. concept-to-code/SKILL.md Step 5 — the Anti-test-weakening gate block (ADR-0047 §D5).
# Static prose anchors, deliberately: the file is instructions for a model, not runnable code.
# ==============================================================================================
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
STEP5="$TMP/c2c_step5.txt"
awk '/^### Step 5 —/{f=1} /^### Step 6 —/{f=0} f' "$CC" >"$STEP5"

if [ -s "$STEP5" ]; then
  ok "WC0: Step 5 of concept-to-code/SKILL.md is extractable (the anchor every WC assertion reads)"
else
  bad "WC0: could not extract Step 5 from $CC — every WC assertion below is meaningless"
fi

WC1_N=$(grep -c '^#### Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)$' "$CC" || true)
if [ "$WC1_N" = "1" ]; then
  ok "WC1: exactly one occurrence of the Anti-test-weakening gate heading in the whole file"
else
  bad "WC1: expected exactly 1 occurrence of the gate heading, found $WC1_N"
fi

if grep -qF 'skills/review-triage-fix/scripts/weakening-scan.sh' "$STEP5" \
   && grep -qF 'CLAUDE_PLUGIN_ROOT' "$STEP5"; then
  ok "WC2: Step 5 resolves the script under skills/review-triage-fix/scripts/ and mentions CLAUDE_PLUGIN_ROOT"
else
  bad "WC2: Step 5 does not name both the skills/review-triage-fix/scripts/ path and CLAUDE_PLUGIN_ROOT"
fi

if grep -qF "grep -q '^WEAKENED'" "$STEP5"; then
  ok "WC3: Step 5 contains the anchored idiom grep -q '^WEAKENED'"
else
  bad "WC3: Step 5 does not contain grep -q '^WEAKENED'"
fi

if grep -qF 'CLEAN' "$STEP5" && grep -qF 'never gate on empty output' "$STEP5"; then
  ok "WC4: Step 5 warns about the CLEAN sentinel and forbids emptiness-gating"
else
  bad "WC4: Step 5 is missing the CLEAN sentinel warning or the phrase 'never gate on empty output'"
fi

if grep -qF '_pre5=$(git rev-parse HEAD' "$STEP5" && grep -qF 'git diff "$_pre5"' "$STEP5"; then
  ok "WC5: Step 5 captures the pre-dispatch mark and scans git diff \"\$_pre5\""
else
  bad "WC5: Step 5 is missing the _pre5 mark or the git diff \"\$_pre5\" scan input"
fi

if grep -qF 'do NOT transition to' "$STEP5" && grep -qF 'step_6_review' "$STEP5"; then
  ok "WC6: Step 5 states the attended policy — do NOT transition to step_6_review"
else
  bad "WC6: Step 5 is missing the attended do-NOT-transition policy"
fi

if grep -qi 'autopilot' "$STEP5" && grep -qi 'halt' "$STEP5"; then
  ok "WC7: Step 5 states the unattended policy — autopilot halts"
else
  bad "WC7: Step 5 is missing the autopilot/halt policy"
fi

if grep -qF "do not trust the agent's self-report" "$STEP5"; then
  ok "WC8: Step 5 states the trust rule — do not trust the agent's self-report"
else
  bad "WC8: Step 5 is missing the do-not-trust-the-agent's-self-report sentence"
fi

WC9_N=$(grep -o 'Anti-test-weakening gate' "$STEP5" | grep -c . || true)
if [ "$WC9_N" -ge 3 ]; then
  ok "WC9: both dispatch paths reach the gate — 'Anti-test-weakening gate' occurs $WC9_N times (>= 3) in Step 5"
else
  bad "WC9: expected >= 3 occurrences of 'Anti-test-weakening gate' in Step 5, found $WC9_N"
fi

if grep -qF 'at every batch checkpoint' "$STEP5"; then
  ok "WC10: the fallback path runs the gate at every batch checkpoint"
else
  bad "WC10: Step 5 is missing the literal phrase 'at every batch checkpoint'"
fi

if grep -qF 'weakening_scan' "$STEP5" && grep -qF 'unavailable' "$STEP5"; then
  ok "WC11: Step 5 records the unavailable state (weakening_scan / unavailable)"
else
  bad "WC11: Step 5 is missing the weakening_scan / unavailable unresolved-script state"
fi

# ==============================================================================================
# WD. step5-report.json schema + orchestrator read contract (ADR-0047 §D6), read from the same
# Step 5 extract — the schema block and read contract both live inside Step 5, before Step 6.
# ==============================================================================================
if grep -qF '"weakening_findings"' "$STEP5"; then
  ok "WD1: the documented JSON schema block contains \"weakening_findings\""
else
  bad "WD1: \"weakening_findings\" missing from the documented schema block"
fi

if grep -F -A5 '"weakening_findings"' "$STEP5" | grep -q '"file"' \
   && grep -F -A5 '"weakening_findings"' "$STEP5" | grep -q '"reason"'; then
  ok "WD2: the schema shows the record shape — \"file\" and \"reason\" near weakening_findings"
else
  bad "WD2: the schema does not show both \"file\" and \"reason\" near weakening_findings"
fi

if grep -qF 'weakening_findings' "$STEP5" && grep -qF 'failure signal' "$STEP5"; then
  ok "WD3: the read contract states weakening_findings non-empty is a failure signal"
else
  bad "WD3: the read contract is missing the weakening_findings / failure signal statement"
fi

WD4_LINE=$(grep -F 'weakening_findings' "$STEP5" | grep -F 'absent' || true)
if [ -n "$WD4_LINE" ]; then
  ok "WD4: the read contract states the additive rule — absent means none, not malformed"
else
  bad "WD4: no line combines weakening_findings and absent in the read contract"
fi

if grep -qF 'checkpoint_reviews' "$STEP5" && grep -qF 'never a failure signal' "$STEP5" \
   && grep -qF 'weakening_findings' "$STEP5" && grep -qF 'always' "$STEP5"; then
  ok "WD5: the contrast is stated — checkpoint_reviews never a failure signal, weakening_findings always is"
else
  bad "WD5: the checkpoint_reviews/weakening_findings contrast sentence is missing or incomplete"
fi

# ==============================================================================================
# WE. autopilot-build/SKILL.md and nightly-autopilot/SKILL.md — the inherited halt (ADR-0047
# §D7/§D8). autopilot-build gets its own circuit-breaker bullets; nightly-autopilot only
# documents an inherited halt and runs no scan of its own.
# ==============================================================================================
AB="$STAGING/plugin/skills/autopilot-build/SKILL.md"
AB_STEP5="$TMP/ab_step5.txt"
AB_STEP6="$TMP/ab_step6.txt"
awk '/^#### Step 5 —/{f=1} /^#### Step 6 —/{f=0} f' "$AB" >"$AB_STEP5"
awk '/^#### Step 6 —/{f=1} /^#### Step 7 —/{f=0} f' "$AB" >"$AB_STEP6"

# Not a same-line check: the bullet legitimately wraps onto a second physical line in the
# rendered prose (matching the plan's own example text), so this checks presence within the
# extracted Step 5 block rather than on one grep line.
if grep -qF 'weakening_findings' "$AB_STEP5" && grep -qF 'halt' "$AB_STEP5" \
   && grep -qF 'status=partial' "$AB_STEP5"; then
  ok "WE1: autopilot-build Step 5 circuit breaker has a weakening_findings -> halt/status=partial condition"
else
  bad "WE1: no weakening_findings/halt/status=partial condition in autopilot-build Step 5"
fi

if grep -qF 'test weakening detected in Step 5' "$AB_STEP5"; then
  ok "WE2: autopilot-build Step 5's abort_reason is the literal 'test weakening detected in Step 5'"
else
  bad "WE2: 'test weakening detected in Step 5' missing from autopilot-build Step 5"
fi

if grep -qF 'test weakening flagged by review-triage-fix in Step 6' "$AB_STEP6"; then
  ok "WE3: autopilot-build Step 6 halts on the literal 'test weakening flagged by review-triage-fix in Step 6'"
else
  bad "WE3: that literal abort_reason is missing from autopilot-build Step 6"
fi

if grep -qF '"weakening_findings"' "$AB"; then
  ok "WE4: autopilot-report.json's documented schema block contains weakening_findings"
else
  bad "WE4: weakening_findings missing from autopilot-report.json's schema block in $AB"
fi

WE5_NEEDLE="Anti-test-weakening gate — Step 5 → Step 6 (ADR-0047)"
if grep -qF "$WE5_NEEDLE" "$AB"; then
  WE5_N=$(grep -c "^#### $WE5_NEEDLE\$" "$CC" || true)
  if [ "$WE5_N" = "1" ]; then
    ok "WE5: autopilot-build names the c2c gate by heading, and it resolves to exactly one heading in concept-to-code"
  else
    bad "WE5: autopilot-build names the heading but it occurs $WE5_N times as a heading in concept-to-code (expected 1)"
  fi
else
  bad "WE5: autopilot-build/SKILL.md does not name the c2c gate heading '$WE5_NEEDLE'"
fi

NA="$STAGING/plugin/skills/nightly-autopilot/SKILL.md"
NA_PHASE1="$TMP/na_phase1.txt"
awk '/^## 3\. Phase 1 —/{f=1} /^## 4\. Phase 2 —/{f=0} f' "$NA" >"$NA_PHASE1"

if grep -qi 'weakening' "$NA_PHASE1" && grep -qF 'needs-human' "$NA_PHASE1" && grep -qF 'run-level' "$NA_PHASE1"; then
  ok "WE6: nightly-autopilot Phase 1 states the inherited-halt contract (weakening / needs-human / run-level)"
else
  bad "WE6: nightly-autopilot Phase 1 is missing weakening, needs-human, or run-level"
fi

if grep -qF 'weakening-scan.sh' "$NA"; then
  bad "WE7: nightly-autopilot/SKILL.md resolves or invokes weakening-scan.sh itself — ADR-0047 §D8 forbids a fourth call site"
else
  ok "WE7: nightly-autopilot/SKILL.md does not resolve or invoke weakening-scan.sh (no fourth call site, ADR-0047 §D8)"
fi

# ==============================================================================================
# WF. commit/SKILL.md Step 1 / Step 4 — the third reporter alongside SECRET/NEWDEP (ADR-0047 §D2).
# Same awk range secret-dep-gate.test.sh uses, so both harnesses read the same region.
# ==============================================================================================
COMMITMD="$STAGING/plugin/skills/commit/SKILL.md"
CSTEP1="$TMP/commit_step1.txt"
awk '/^### Step 1 —/{f=1} /^### Step 2 —/{f=0} f' "$COMMITMD" >"$CSTEP1"

if [ -s "$CSTEP1" ]; then
  ok "WF0: Step 1 of commit/SKILL.md is extractable (the anchor the WF section reads)"
else
  bad "WF0: could not extract Step 1 from $COMMITMD — every WF assertion below is meaningless"
fi

if grep -qF 'weakening-scan.sh' "$CSTEP1"; then
  ok "WF1: Step 1 names weakening-scan.sh"
else
  bad "WF1: weakening-scan.sh missing from Step 1"
fi

if grep -qF 'skills/review-triage-fix/scripts/' "$CSTEP1" && grep -qF 'CLAUDE_PLUGIN_ROOT' "$CSTEP1"; then
  ok "WF2: Step 1 resolves weakening-scan.sh under skills/review-triage-fix/scripts/ and mentions CLAUDE_PLUGIN_ROOT"
else
  bad "WF2: Step 1 does not name both skills/review-triage-fix/scripts/ and CLAUDE_PLUGIN_ROOT"
fi

if grep -qF 'git diff HEAD' "$CSTEP1"; then
  ok "WF3: Step 1 reuses git diff HEAD as the scan input"
else
  bad "WF3: Step 1 does not reuse git diff HEAD as the weakening-scan input"
fi

if grep -qF 'WEAKENED' "$CSTEP1" && grep -qi 'advisory' "$CSTEP1"; then
  ok "WF4: Step 1 states the attended policy — WEAKENED lines are advisory and stop nothing"
else
  bad "WF4: Step 1 is missing the WEAKENED/advisory statement"
fi

if grep -qF 'autopilot' "$CSTEP1" && grep -qF 'WEAKENED' "$CSTEP1" && grep -qi 'abort' "$CSTEP1"; then
  ok "WF5: Step 1 states the --autopilot policy — a WEAKENED finding aborts"
else
  bad "WF5: Step 1 is missing the autopilot/WEAKENED/abort policy"
fi

if grep -qF 'the SECRET, NEWDEP and WEAKENED lines from Step 1, verbatim' "$COMMITMD"; then
  ok "WF6: Step 4's rendering phrase names all three reporters"
else
  bad "WF6: Step 4 does not name SECRET, NEWDEP and WEAKENED in one rendering phrase"
fi

# WF7 — forward guard, never fix evidence. Duplicates secret-dep-gate F4 on purpose: this feature
# edits the same Step 1 region and the cheapest way to break #100 is to reflow the block.
WF7OK=1
grep -qF '`.env`'         "$CSTEP1" || WF7OK=0
grep -qF '`*secret*`'     "$CSTEP1" || WF7OK=0
grep -qF '`*credential*`' "$CSTEP1" || WF7OK=0
grep -qF '`*.pem`'        "$CSTEP1" || WF7OK=0
if [ "$WF7OK" -eq 1 ]; then
  ok "WF7: the four Step 1 filename patterns are intact (forward guard, duplicates secret-dep-gate F4)"
else
  bad "WF7: a Step 1 filename pattern was weakened — restore it, do not edit this assertion"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
