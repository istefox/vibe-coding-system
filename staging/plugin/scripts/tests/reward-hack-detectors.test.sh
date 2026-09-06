#!/bin/bash
# reward-hack-detectors.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash reward-hack-detectors.test.sh
#
# Covers issue #105 / ADR-0051: four new SUSPECT detectors (literal-assertion-added,
# zero-assertion-test, deleted-public-symbol, swallowed-error) added to the EXISTING
# weakening-scan.sh awk pipeline — no new script, no second source of truth (ADR-0051 §D6).
#
# ASSERTION LABELS ARE H-PREFIXED (HA1, HC3, HG2, ...) to stay distinguishable from
# weakening-wiring.test.sh's W-prefixed labels and spec-coverage.test.sh's R-prefixed labels —
# all three print into the same CI shell-tests job.
#
# THE REPORTER CONTRACT IS UNCHANGED AND THE THING MOST LIKELY TO BE BROKEN HERE (ADR-0047 §D4,
# reaffirmed by ADR-0051 §D4). weakening-scan.sh still always exits 0 and still prints CLEAN only
# when there is NEITHER a WEAKENED NOR a SUSPECT finding. Section HC pins this.
#
# SUSPECT IS DELIBERATELY INVISIBLE TO EVERY EXISTING `grep -q '^WEAKENED'` CALLER (ADR-0051 §D2).
# Section HD pins that SUSPECT never matches `^WEAKENED` — promoting it into that grep is the most
# likely future "fix" and it is exactly the wrong one; every caller wired by ADR-0047 would start
# halting unattended runs on a heuristic with no type information and no test execution.
#
# literal-assertion-added IS RETIRED (issue #314, ADR-0144), and with it the AWKGUARD interval
# probe that existed only to guard it. Sections HA4, HG1-HG5 and HC5 asserted their behaviour and
# are gone; section HG now holds the reverse guard that keeps the surface retired. Re-measured over
# all 383 non-merge commits reachable from `main`: 8 findings, 0 of them the behaviour the detector
# exists to catch.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: RET1 | plugin/skills/review-triage-fix/scripts/weakening-scan.sh | AWK="${WEAKENING_SCAN_AWK:-awk}" | AWK="${WEAKENING_SCAN_AWK:-awk}"; LIT_ENABLED=0
# plant: RET2 | plugin/skills/review-triage-fix/scripts/weakening-scan.sh | literal-assertion-added IS RETIRED (issue #314, ADR-0144). | this note was removed by a plant.
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL and no fixture path contains "secret",
# "credential", ".env", ".pem", or ".key" — secret-dep-gate.test.sh section D scans this
# repository's tracked files as its false-positive corpus, so a matching string dropped into a
# fixture in this file would turn that harness red, and a matching PATH would turn
# protect-files.sh's deny rules against this very file.
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

W="$STAGING/plugin/skills/review-triage-fix/scripts/weakening-scan.sh"

if [ -f "$W" ]; then
  ok "H0: weakening-scan.sh exists at the in-place path (the anchor every H assertion reads) — ADR-0051 §D6, no new script"
else
  bad "H0: $W not found — every assertion below is meaningless"
fi

# ==================================================================================================
# HA. Each of the four detectors fires on a minimal true-positive diff.
# ==================================================================================================
cat >"$TMP/ha1.diff" <<EOF
diff --git a/tests/test_z.py b/tests/test_z.py
--- a/tests/test_z.py
+++ b/tests/test_z.py
@@ -1,2 +1,5 @@
 def test_existing():
     assert True
+def test_new_thing():
+    x = compute()
+    y = x + 1
EOF
ha1_out=$(bash "$W" <"$TMP/ha1.diff")
if printf '%s\n' "$ha1_out" | grep -q "^SUSPECT${TAB}tests/test_z.py${TAB}zero-assertion-test"; then
  ok "HA1: zero-assertion-test fires on an added test function with no assertion token"
else
  bad "HA1: expected a SUSPECT/zero-assertion-test line — got: $ha1_out"
fi

cat >"$TMP/ha2.diff" <<EOF
diff --git a/src/api.js b/src/api.js
--- a/src/api.js
+++ b/src/api.js
@@ -1,3 +1,1 @@
-export function computeTotal(items) {
-  return items.reduce((a,b) => a+b, 0);
-}
+// removed
EOF
ha2_out=$(bash "$W" <"$TMP/ha2.diff")
if printf '%s\n' "$ha2_out" | grep -q "^SUSPECT${TAB}src/api.js${TAB}deleted-public-symbol"; then
  ok "HA2: deleted-public-symbol fires on a removed exported function with no matching re-add"
else
  bad "HA2: expected a SUSPECT/deleted-public-symbol line — got: $ha2_out"
fi

cat >"$TMP/ha3.diff" <<EOF
diff --git a/src/y.js b/src/y.js
--- a/src/y.js
+++ b/src/y.js
@@ -1,2 +1,6 @@
 function f() {
+  try {
+    risky();
+  } catch (e) {
+    return null;
+  }
 }
EOF
ha3_out=$(bash "$W" <"$TMP/ha3.diff")
if printf '%s\n' "$ha3_out" | grep -q "^SUSPECT${TAB}src/y.js${TAB}swallowed-error"; then
  ok "HA3: swallowed-error fires on a newly-added catch block with neither a log nor a rethrow"
else
  bad "HA3: expected a SUSPECT/swallowed-error line — got: $ha3_out"
fi

# ==================================================================================================
# HB. Each detector's declared exclusion (ADR-0051 §D5) suppresses the finding.
# ==================================================================================================
cat >"$TMP/hb1.diff" <<EOF
diff --git a/tests/test_table.py b/tests/test_table.py
--- a/tests/test_table.py
+++ b/tests/test_table.py
@@ -1,2 +1,3 @@
 def test_existing():
     assert True
+def test_new_case():
+    run_table_case(1, 2, 3)
EOF
hb1_out=$(bash "$W" <"$TMP/hb1.diff")
if [ "$hb1_out" = "CLEAN" ]; then
  ok "HB1: zero-assertion-test excluded when the body is a single call to a shared (presumably self-asserting) helper"
else
  bad "HB1: expected CLEAN (single-helper-call exclusion) — got: $hb1_out"
fi

# ==================================================================================================
# HI. issue #472 / ADR-0160 — `#` opens a macro in Swift, not a comment. Reported in the field: 32
# false zero-assertion-test findings against 12 real `#expect` calls in one Swift Testing file, all
# eleven-times-repeated on the one file that HAD assertions. HI1/HI2 are the true fix (a real
# `#expect`/`#require` call is no longer read as a comment and hidden from the state machine); HI3
# is the forward guard proving the detector still fires on a GENUINELY empty Swift test; HI4 is the
# regression guard proving Python's `#` is UNCHANGED — this fix narrows the languages `#` is a
# comment IN, it does not remove the comment leader from the ones that had it correctly.
# ==================================================================================================
cat >"$TMP/hi1.diff" <<EOF
diff --git a/Tests/WidgetTests.swift b/Tests/WidgetTests.swift
--- a/Tests/WidgetTests.swift
+++ b/Tests/WidgetTests.swift
@@ -1,2 +1,4 @@
 struct WidgetTests {}
+@Test func widgetName() {
+    #expect(Widget().name == "widget")
+}
EOF
hi1_out=$(bash "$W" <"$TMP/hi1.diff")
# plant: HI1 | plugin/skills/review-triage-fix/scripts/weakening-scan.sh | function is_hash_comment_lang(p){ return p ~ /\.(py|rb|sh|bash|zsh|pl|pm|yaml|yml|toml|tf|cmake|r|jl)$/ } | function is_hash_comment_lang(p){ return 1 }
if [ "$hi1_out" = "CLEAN" ]; then
  ok "HI1: an added Swift Testing #expect(...) call is recognised as the assertion it is, not skipped as a comment — no zero-assertion-test SUSPECT"
else
  bad "HI1: expected CLEAN — #expect(...) misread as a comment produced: $hi1_out"
fi

cat >"$TMP/hi2.diff" <<EOF
diff --git a/Tests/WidgetTests.swift b/Tests/WidgetTests.swift
--- a/Tests/WidgetTests.swift
+++ b/Tests/WidgetTests.swift
@@ -1,2 +1,4 @@
 struct WidgetTests {}
+@Test func widgetExists() {
+    #require(Widget() != nil)
+}
EOF
hi2_out=$(bash "$W" <"$TMP/hi2.diff")
# plant: HI2 | plugin/skills/review-triage-fix/scripts/weakening-scan.sh | function is_assert_tok(s){ return s ~ /assert|expect\(|#require\(|XCTAssert|EXPECT_|ASSERT_|require\.|should|t\.Error|t\.Fatal/ } | function is_assert_tok(s){ return s ~ /assert|expect\(|XCTAssert|EXPECT_|ASSERT_|require\.|should|t\.Error|t\.Fatal/ }
if [ "$hi2_out" = "CLEAN" ]; then
  ok "HI2: an added Swift Testing #require(...) call is recognised as an assertion token"
else
  bad "HI2: expected CLEAN — #require(...) not recognised as an assertion produced: $hi2_out"
fi

cat >"$TMP/hi3.diff" <<EOF
diff --git a/Tests/WidgetTests.swift b/Tests/WidgetTests.swift
--- a/Tests/WidgetTests.swift
+++ b/Tests/WidgetTests.swift
@@ -1,2 +1,4 @@
 struct WidgetTests {}
+@Test func widgetBuilds() {
+    let w = Widget()
+}
EOF
hi3_out=$(bash "$W" <"$TMP/hi3.diff")
if printf '%s\n' "$hi3_out" | grep -q "^SUSPECT${TAB}Tests/WidgetTests.swift${TAB}zero-assertion-test"; then
  ok "HI3 (forward guard): a genuinely empty Swift @Test still fires zero-assertion-test — the fix narrows what counts as a comment, it does not disable the detector for Swift"
else
  bad "HI3: expected a SUSPECT/zero-assertion-test line for a Swift test with no #expect/#require — got: $hi3_out"
fi

cat >"$TMP/hi4.diff" <<EOF
diff --git a/tests/test_hash_comment.py b/tests/test_hash_comment.py
--- a/tests/test_hash_comment.py
+++ b/tests/test_hash_comment.py
@@ -1,2 +1,4 @@
 def test_existing():
     assert True
+def test_new_case():
+    # TODO: no assertion here yet
EOF
hi4_out=$(bash "$W" <"$TMP/hi4.diff")
if printf '%s\n' "$hi4_out" | grep -q "^SUSPECT${TAB}tests/test_hash_comment.py${TAB}zero-assertion-test"; then
  ok "HI4 (regression guard): a Python test body containing only a # comment still reads as zero-assertion-test — # stays a comment leader in the languages it already was one in"
else
  bad "HI4: expected zero-assertion-test on a Python test with only a # comment body — got: $hi4_out — the Swift fix must not widen what counts as a body line elsewhere"
fi

cat >"$TMP/hb2.diff" <<EOF
diff --git a/src/api.js b/src/api.js
--- a/src/api.js
+++ b/src/api.js
@@ -1,6 +1,6 @@
-export function computeTotal(items) {
-  return items.reduce((a,b) => a+b, 0);
-}
 export function other() {}
+export function computeTotal(items) {
+  return items.reduce((a,b) => a+b, 0);
+}
EOF
hb2_out=$(bash "$W" <"$TMP/hb2.diff")
if [ "$hb2_out" = "CLEAN" ]; then
  ok "HB2: deleted-public-symbol excluded when the removal is a pure move — the identical signature reappears elsewhere in the same file"
else
  bad "HB2: expected CLEAN (pure-move exclusion) — got: $hb2_out"
fi

cat >"$TMP/hb3.diff" <<EOF
diff --git a/src/y2.js b/src/y2.js
--- a/src/y2.js
+++ b/src/y2.js
@@ -1,2 +1,6 @@
 function f() {
+  try {
+    risky();
+  } catch (e) {
+    // intentional no-op: risky() failures are expected and safe to ignore here
+  }
 }
EOF
hb3_out=$(bash "$W" <"$TMP/hb3.diff")
if [ "$hb3_out" = "CLEAN" ]; then
  ok "HB3: swallowed-error excluded when the catch body contains a comment explaining the intentional swallow"
else
  bad "HB3: expected CLEAN (explanatory-comment exclusion) — got: $hb3_out"
fi

cat >"$TMP/hb4.diff" <<EOF
diff --git a/tests/test_calc.py b/tests/test_calc.py
--- a/tests/test_calc.py
+++ b/tests/test_calc.py
@@ -1,2 +1,2 @@
-    assert add(1, 2) == 3
+    assert add(1, 2) == 42
EOF
hb4_out=$(WEAKENING_SCAN_LITERAL_ASSERTION=1 bash "$W" <"$TMP/hb4.diff")
if printf '%s\n' "$hb4_out" | grep -q '^SUSPECT.*literal-assertion-added'; then
  bad "HB4: literal-assertion-added fired on a TEST-ONLY diff (no impl file changed) even with opt-in — ADR-0051 §D1 requires both halves — got: $hb4_out"
else
  ok "HB4: literal-assertion-added requires both halves — a test-only diff never fires it, opt-in or not"
fi

# ==================================================================================================
# HC. The reporter contract (ADR-0047 §D4, ADR-0051 §D4): always exit 0; CLEAN only when there is
# neither a WEAKENED nor a SUSPECT finding; CLEAN never printed alongside a finding.
# ==================================================================================================
clean_out=$(printf '' | bash "$W"); clean_rc=$?
if [ "$clean_out" = "CLEAN" ] && [ "$clean_rc" -eq 0 ]; then
  ok "HC1: empty stdin -> output is exactly CLEAN, exit 0"
else
  bad "HC1: expected CLEAN/exit 0 on empty stdin — got out=[$clean_out] rc=$clean_rc"
fi

ha1_rc_out=$(bash "$W" <"$TMP/ha1.diff"); ha1_rc=$?
if [ "$ha1_rc" -eq 0 ] && ! printf '%s\n' "$ha1_rc_out" | grep -qx 'CLEAN'; then
  ok "HC2: a SUSPECT-only run exits 0 and never prints a bare CLEAN line alongside the finding"
else
  bad "HC2: expected exit 0 and no CLEAN line on a SUSPECT-only run — got rc=$ha1_rc out=$ha1_rc_out"
fi

cat >"$TMP/hc3.diff" <<EOF
diff --git a/tests/test_y.py b/tests/test_y.py
deleted file mode 100644
--- a/tests/test_y.py
+++ /dev/null
@@ -1,3 +0,0 @@
-def test_y():
-    assert True
-    pass
EOF
hc3_out=$(bash "$W" <"$TMP/hc3.diff"); hc3_rc=$?
if [ "$hc3_rc" -eq 0 ] && ! printf '%s\n' "$hc3_out" | grep -qx 'CLEAN'; then
  ok "HC3: a WEAKENED-only run exits 0 and never prints a bare CLEAN line alongside the finding"
else
  bad "HC3: expected exit 0 and no CLEAN line on a WEAKENED-only run — got rc=$hc3_rc out=$hc3_out"
fi

# A combined diff with both a WEAKENED and a SUSPECT finding — CLEAN must be absent, exit 0, and
# both sentinel families present.
cat "$TMP/hc3.diff" "$TMP/ha3.diff" >"$TMP/hc4.diff"
hc4_out=$(bash "$W" <"$TMP/hc4.diff"); hc4_rc=$?
if [ "$hc4_rc" -eq 0 ] \
   && printf '%s\n' "$hc4_out" | grep -q '^WEAKENED' \
   && printf '%s\n' "$hc4_out" | grep -q '^SUSPECT' \
   && ! printf '%s\n' "$hc4_out" | grep -qx 'CLEAN'; then
  ok "HC4: a run with both a WEAKENED and a SUSPECT finding carries both, no CLEAN, exit 0"
else
  bad "HC4: expected both sentinel families, no CLEAN, exit 0 — got rc=$hc4_rc out=$hc4_out"
fi

fake_awk="$TMP/fake-awk"
cat >"$fake_awk" <<'FAKEEOF'
#!/bin/bash
for a in "$@"; do
  case "$a" in
    '$0 ~ /^a{2,}$/ { print "y" }') echo "NOPE"; exit 0 ;;
  esac
done
exec /usr/bin/awk "$@"
FAKEEOF
chmod +x "$fake_awk"

# ==================================================================================================
# HD. SUSPECT does NOT match ^WEAKENED (ADR-0051 §D2) — pinned so a future edit cannot silently
# promote a heuristic finding into the halting gates every ADR-0047 caller greps for.
# ==================================================================================================
if printf '%s\n' "$ha1_out" | grep -q '^WEAKENED'; then
  bad "HD1: a SUSPECT-only run (zero-assertion-test) unexpectedly matched grep '^WEAKENED'"
else
  ok "HD1: printf '%s\\n' \"\$ha1_out\" | grep -q '^WEAKENED' is FALSE on a SUSPECT-only run"
fi
if printf '%s\n' "$ha2_out" | grep -q '^WEAKENED'; then
  bad "HD2: a SUSPECT-only run (deleted-public-symbol) unexpectedly matched grep '^WEAKENED'"
else
  ok "HD2: deleted-public-symbol output does not match ^WEAKENED"
fi
if printf '%s\n' "$ha3_out" | grep -q '^WEAKENED'; then
  bad "HD3: a SUSPECT-only run (swallowed-error) unexpectedly matched grep '^WEAKENED'"
else
  ok "HD3: swallowed-error output does not match ^WEAKENED"
fi
# HD4 covered literal-assertion-added and went with it (#314, ADR-0144). It is named here rather
# than deleted in silence because the gap in the sequence is otherwise the kind of thing a later
# reader restores from ADR-0051 without knowing why it left.
#
# Forward guard against a future edit re-spelling the sentinel: the three remaining detector names
# must only ever appear after a literal "SUSPECT" prefix in the script source, never after
# "WEAKENED". `literal-assertion-added` is deliberately NOT in this alternation any more: it would
# match the retirement note in the header, which is a comment explaining an absence — rule 12, on a
# guard whose subject no longer exists.
HD5_BAD=$(grep -nE 'WEAKENED.*(zero-assertion-test|deleted-public-symbol|swallowed-error)' "$W" || true)
if [ -z "$HD5_BAD" ]; then
  ok "HD5: none of the three SUSPECT detector names appear on a WEAKENED line in the script source"
else
  bad "HD5: a SUSPECT detector name appears on a WEAKENED-prefixed line — got: $HD5_BAD"
fi

# ==================================================================================================
# HE. The existing four WEAKENED detectors still fire unchanged (regression guard, ADR-0047).
# ==================================================================================================
he1_out=$(bash "$W" <"$TMP/hc3.diff")
if printf '%s\n' "$he1_out" | grep -q '^WEAKENED' && printf '%s\n' "$he1_out" | grep -q 'deleted-test-file'; then
  ok "HE1: deleted-test-file still fires (regression guard)"
else
  bad "HE1: expected WEAKENED/deleted-test-file — got: $he1_out"
fi

cat >"$TMP/he2.diff" <<EOF
diff --git a/tests/test_x.py b/tests/test_x.py
--- a/tests/test_x.py
+++ b/tests/test_x.py
@@ -1,3 +1,4 @@
+@pytest.mark.skip
 def test_x():
     assert True
EOF
he2_out=$(bash "$W" <"$TMP/he2.diff")
if printf '%s\n' "$he2_out" | grep -q '^WEAKENED' && printf '%s\n' "$he2_out" | grep -q 'skip/xfail-added'; then
  ok "HE2: skip/xfail-added still fires (regression guard)"
else
  bad "HE2: expected WEAKENED/skip-xfail-added — got: $he2_out"
fi

cat >"$TMP/he3.diff" <<EOF
diff --git a/tests/test_r.py b/tests/test_r.py
--- a/tests/test_r.py
+++ b/tests/test_r.py
@@ -1,3 +1,2 @@
 def test_r():
-    assert compute() == expected()
     pass
EOF
he3_out=$(bash "$W" <"$TMP/he3.diff")
if printf '%s\n' "$he3_out" | grep -q '^WEAKENED' && printf '%s\n' "$he3_out" | grep -q 'assert-removed'; then
  ok "HE3: assert-removed still fires (regression guard)"
else
  bad "HE3: expected WEAKENED/assert-removed — got: $he3_out"
fi

cat >"$TMP/he4.diff" <<EOF
diff --git a/tests/test_c.py b/tests/test_c.py
--- a/tests/test_c.py
+++ b/tests/test_c.py
@@ -1,3 +1,1 @@
-def test_c():
-    assert True
+# disabled, see JIRA-123
EOF
he4_out=$(bash "$W" <"$TMP/he4.diff")
if printf '%s\n' "$he4_out" | grep -q '^WEAKENED' && printf '%s\n' "$he4_out" | grep -q 'test-removed-or-commented'; then
  ok "HE4: test-removed-or-commented still fires (regression guard)"
else
  bad "HE4: expected WEAKENED/test-removed-or-commented — got: $he4_out"
fi

# ==================================================================================================
# HF. suspect_findings in the step5-report.json schema block and the Gate 5 summary text
# (ADR-0051 §D3). Static prose anchors, read ONLY from Step 5's schema block (concept-to-code
# SKILL.md lines ~808-983, well clear of Step 6) and the "## 5. HITL gates" section (line 1503+,
# also well clear of Step 6 Phase 3) — never the Step 6 Phase 3 dispatch block itself.
# ==================================================================================================
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
HITL_REF="$STAGING/plugin/skills/concept-to-code/references/hitl-gates.md"
STEP5_REF="$STAGING/plugin/skills/concept-to-code/references/step5-implementation.md"
STEP5="$TMP/cc_step5.txt"
# The Step 5 range moved to references/step5-implementation.md (VCS-047, ADR-0174); the
# reference file's body IS the block, so no awk range is needed any more.
cp "$STEP5_REF" "$STEP5" 2>/dev/null
GATES="$TMP/cc_gates.txt"
# VCS-048/ADR-0175: ## 5. HITL gates moved into references/hitl-gates.md; the reference file's
# body IS the block, so no awk range is needed any more.
cp "$HITL_REF" "$GATES" 2>/dev/null

if [ -s "$STEP5" ] && [ -s "$GATES" ]; then
  ok "HF0: both extraction anchors (Step 5, ## 5. HITL gates) are non-empty"
else
  bad "HF0: could not extract Step 5 and/or ## 5. HITL gates from $CC — HF assertions below are meaningless"
fi

if grep -qF '"suspect_findings"' "$STEP5"; then
  ok "HF1: the step5-report.json schema block in Step 5 contains \"suspect_findings\""
else
  bad "HF1: \"suspect_findings\" missing from the Step 5 schema block"
fi

if grep -F -A3 '"suspect_findings"' "$STEP5" | grep -q '"file"' \
   && grep -F -A3 '"suspect_findings"' "$STEP5" | grep -q '"detector"'; then
  ok "HF2: the schema shows the record shape — \"file\" and \"detector\" near suspect_findings"
else
  bad "HF2: the schema does not show both \"file\" and \"detector\" near suspect_findings"
fi

if grep -qF 'suspect_findings' "$STEP5" && grep -qF 'never a failure signal' "$STEP5" \
   && grep -qi 'advisory' "$STEP5"; then
  ok "HF3: Step 5 states suspect_findings is advisory and never a failure signal (contrast with weakening_findings)"
else
  bad "HF3: Step 5 is missing the suspect_findings advisory/never-a-failure-signal statement"
fi

if grep -qF 'suspect_findings' "$GATES" && grep -qi 'Gate 5' "$GATES"; then
  ok "HF4: the Gate 5 block in ## 5. HITL gates mentions suspect_findings"
else
  bad "HF4: Gate 5 does not mention suspect_findings"
fi

if grep -qF 'per-detector' "$GATES" || grep -qF 'breakdown' "$GATES"; then
  ok "HF5: the Gate 5 summary states a per-detector breakdown is shown"
else
  bad "HF5: Gate 5 does not mention a per-detector breakdown"
fi

# commit/SKILL.md Step 1 — SUSPECT is printed attended and never aborts, even under --autopilot.
COMMITMD="$STAGING/plugin/skills/commit/SKILL.md"
CSTEP1="$TMP/commit_step1.txt"
awk '/^### Step 1 —/{f=1} /^### Step 2 —/{f=0} f' "$COMMITMD" >"$CSTEP1"

if [ -s "$CSTEP1" ]; then
  ok "HF6: Step 1 of commit/SKILL.md is extractable"
else
  bad "HF6: could not extract Step 1 from $COMMITMD"
fi

if grep -qF 'SUSPECT' "$CSTEP1"; then
  ok "HF7: commit/SKILL.md Step 1 names SUSPECT"
else
  bad "HF7: SUSPECT missing from commit/SKILL.md Step 1"
fi

if grep -qF 'SUSPECT' "$CSTEP1" && grep -qi 'advisory' "$CSTEP1"; then
  ok "HF8: Step 1 states SUSPECT lines are advisory"
else
  bad "HF8: Step 1 is missing the SUSPECT/advisory statement"
fi

HF9_LINE=$(grep -F 'SUSPECT' "$CSTEP1" | grep -i 'autopilot' | grep -iv 'abort' || true)
if [ -n "$HF9_LINE" ]; then
  ok "HF9: Step 1 states SUSPECT does not abort even under --autopilot"
else
  bad "HF9: Step 1 is missing the SUSPECT/--autopilot/never-aborts statement"
fi

# ==================================================================================================
# HG. literal-assertion-added is RETIRED (#314, ADR-0144), and so is the AWKGUARD interval probe
# that existed only for it. What stood here — HG1..HG5, HA4a/HA4b, HC5 — asserted the behaviour of
# that detector and its probe. Five of the eight kept PASSING after the removal, because they
# asserted an ABSENCE that had become trivially true, which is precisely why they could not stay:
# an assertion satisfied by the deletion of its own subject reads as coverage and pins nothing.
#
# What replaces them is a reverse guard (rule 9): the retired surface must STAY retired, and a
# re-added copy must be caught rather than silently re-enabled by someone reading ADR-0051 without
# ADR-0144. The needle is the EXECUTION surface, not the name: the retirement note in the header
# names `literal-assertion-added` on purpose, and a guard that grepped for the string would be red
# on its own documentation (rule 12).
# ==================================================================================================
_ret_live=""
# The list is the retired surface in full: the env gate a caller would set, the shell variable it
# fed, the rule, the probe, and the buffer the rule wrote into. `LIT_ENABLED` was missing from the
# first version of this list and the plant on RET1 is what said so — it re-added exactly that
# variable and the assertion stayed green, which is a guard whose needle does not reach the
# mechanism it names.
for _tok in 'WEAKENING_SCAN_LITERAL_ASSERTION' 'LIT_ENABLED' 'is_literal_assert' 'AWKGUARD' 'lit_n'; do
  # Comment lines are stripped first: the header MUST be free to name what was retired and why.
  if grep -v '^[[:space:]]*#' "$W" | grep -qF "$_tok"; then _ret_live="$_ret_live $_tok"; fi
done
if [ -z "$_ret_live" ]; then
  ok "RET1: the retired detector's execution surface is absent (env gate, rule, probe and buffer)"
else
  bad "RET1: retired surface is live again in $W —$_ret_live — see ADR-0144 before re-enabling it"
fi

# The denominator for RET1: a grep over a file that moved or emptied would report the same clean
# result as a genuine retirement (rule 7).
_ret_lines=$(grep -c . "$W" || true)
if [ "${_ret_lines:-0}" -ge 100 ] && grep -q 'literal-assertion-added IS RETIRED' "$W"; then
  ok "RET2: RET1 read a live script ($_ret_lines lines) carrying the retirement note"
else
  bad "RET2: $W is $_ret_lines line(s) or carries no retirement note — RET1 proved nothing"
fi

# Forward guard: the probe itself is built by string concatenation, mirroring secret-scan.sh's
# discipline, so this file is never itself flagged by a future content scan.
if grep -qF 'WEAKENING_SCAN_AWK' "$W"; then
  ok "HG6: the interpreter override variable WEAKENING_SCAN_AWK is present in the script (testability, mirrors SECRET_SCAN_AWK)"
else
  bad "HG6: WEAKENING_SCAN_AWK override missing from $W"
fi

# ==================================================================================================
# HH. Registration in both CI registries (Task 6).
# ==================================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]reward-hack-detectors[[:space:];]'; then
  ok "HH1: docs-ci.yml's shell-tests loop list runs reward-hack-detectors"
else
  bad "HH1: reward-hack-detectors is not in docs-ci.yml's explicit harness list — append it after recovery-preflight"
fi

# HH2 removed (ADR-0193): ci.yml, the second registry this pinned, was deleted — docs-ci.yml's
# shell-tests list above (HH1) is now the only harness runner, and pairs-completeness.test.sh's
# CI3 asserts exactly one workflow executes the suite.

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
