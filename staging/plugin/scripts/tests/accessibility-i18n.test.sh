#!/bin/bash
# accessibility-i18n.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Covers ADR-0066 (issue #120): Gate 5.05 records an accessibility/i18n
# checklist RESULT (not merely that ui-layout-audit ran), narrow i18n scope, records-not-blocks,
# conditional on UI-bearing chains, no detector. Targets staging/ directly, never the deployed
# $HOME/.claude/ copy.
#
# Label prefix: AI (Accessibility/I18n) — grepped across all other *.test.sh files in this
# directory before picking it; none use it (the common collision is bare "A1"-style single-letter
# prefixes, e.g. A/B/C/... in several files, and AI is not among them).
# Run: bash accessibility-i18n.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CC_SKILL="$STAGING/plugin/skills/concept-to-code/SKILL.md"
ADR="$REPO/docs/architecture/ADR-0066-120-accessibility-i18n.md"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
CIYML="$REPO/.github/workflows/ci.yml"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

if [ -f "$CC_SKILL" ] && [ -r "$CC_SKILL" ]; then
  ok "AI0a: $CC_SKILL exists and is readable"
else
  bad "AI0a: $CC_SKILL not found or unreadable — every AI assertion below is meaningless"
fi

if [ -f "$ADR" ] && [ -r "$ADR" ]; then
  ok "AI0b: $ADR exists and is readable"
else
  bad "AI0b: $ADR not found or unreadable — AID assertions below are meaningless"
fi

# Extract the Gate 5.05 block (start marker through, but not including, Gate 5.06's start
# marker) — the same range-extraction idiom licence-provenance.test.sh uses for its
# "## Suspicious-output check" section, so assertions can't be satisfied by unrelated text
# living elsewhere in this ~2900-line file.
G505="$TMP/gate505.txt"
awk '/^\*\*Gate 5\.05 /{f=1} f && /^\*\*Gate 5\.06 /{exit} f' "$CC_SKILL" > "$G505" 2>/dev/null

if [ -s "$G505" ]; then
  ok "AI0c: Gate 5.05 block extracted from $CC_SKILL — every AIB/AIC/AID/AIE/AIF assertion below reads this range"
else
  bad "AI0c: could not extract a Gate 5.05 block — every AIB/AIC/AID/AIE/AIF assertion below is meaningless"
fi

# ==================================================================================================
# AIB. Gate 5.05 records a checklist RESULT (§D1), not merely that the audit ran. Named items:
# labels, contrast, dynamic-type/scaling, keyboard or assistive-tech reachability. A step that
# always completes is indistinguishable from a step that always passes (ADR-0043, ADR-0046).
# ==================================================================================================
if grep -q 'labels' "$G505"; then
  ok "AIB1: Gate 5.05 names 'labels' as a checklist item"
else
  bad "AIB1: 'labels' not found in the Gate 5.05 block"
fi

if grep -q 'contrast' "$G505"; then
  ok "AIB2: Gate 5.05 names 'contrast' as a checklist item"
else
  bad "AIB2: 'contrast' not found in the Gate 5.05 block"
fi

if grep -qi 'dynamic.type' "$G505" && grep -qi 'scaling' "$G505"; then
  ok "AIB3: Gate 5.05 names dynamic-type/scaling as a checklist item"
else
  bad "AIB3: dynamic-type/scaling not found in the Gate 5.05 block"
fi

if grep -qi 'keyboard' "$G505" && grep -qiE 'assistive|reachab' "$G505"; then
  ok "AIB4: Gate 5.05 names keyboard/assistive-tech reachability as a checklist item"
else
  bad "AIB4: keyboard-or-assistive-tech reachability not found in the Gate 5.05 block"
fi

# AIB5: a result is WRITTEN, not merely that the audit ran — step5-report.json must be named
# inside the Gate 5.05 block itself (before this feature, Gate 5.05 only invoked ui-layout-audit
# and touched no report file at all).
if grep -q 'step5-report.json' "$G505"; then
  ok "AIB5: Gate 5.05 block writes a result to step5-report.json (not merely 'ran the audit')"
else
  bad "AIB5: Gate 5.05 block does not mention step5-report.json — nothing is recorded, only run"
fi

# AIB6: the schema itself carries the array (outside the extracted Gate 5.05 range — this reads
# the whole file on purpose, since the schema block sits earlier, near task_metrics).
if grep -q '"accessibility_i18n_findings"' "$CC_SKILL"; then
  ok "AIB6: step5-report.json schema documents accessibility_i18n_findings"
else
  bad "AIB6: accessibility_i18n_findings missing from the documented schema"
fi

# ==================================================================================================
# AIC. i18n items present and NARROW (§D3): Unicode/multibyte handling, no English-centric
# assumptions in examples/fixtures, no locale-dependent formatting assumed. No framework, no
# string-catalogue convention, no locale strategy imposed.
# ==================================================================================================
if grep -qi 'unicode' "$G505" && grep -qi 'multibyte' "$G505"; then
  ok "AIC1: Gate 5.05 names Unicode/multibyte handling as an i18n item"
else
  bad "AIC1: Unicode/multibyte handling not found in the Gate 5.05 block"
fi

if grep -qi 'english-centric' "$G505"; then
  ok "AIC2: Gate 5.05 names 'no English-centric assumptions' as an i18n item"
else
  bad "AIC2: English-centric assumptions item not found in the Gate 5.05 block"
fi

if grep -qi 'locale' "$G505" && grep -qi 'formatting' "$G505"; then
  ok "AIC3: Gate 5.05 names locale-dependent formatting as an i18n item"
else
  bad "AIC3: locale-dependent formatting item not found in the Gate 5.05 block"
fi

# AIC4: the narrowness constraint itself must be asserted, not just satisfied by omission — a
# future edit could silently add a framework recommendation without this failing unless the
# refusal is itself pinned in text.
if grep -qi 'framework' "$G505" && grep -qi 'catalogue' "$G505" && grep -qi 'locale strategy' "$G505"; then
  ok "AIC4: Gate 5.05 explicitly refuses to impose an i18n framework, catalogue convention, or locale strategy"
else
  bad "AIC4: no explicit refusal of an i18n framework/catalogue/locale-strategy found in the Gate 5.05 block"
fi

if grep -qiE 'do not.{0,20}introduce' "$G505"; then
  ok "AIC5: the refusal is phrased as a prohibition ('do not introduce'), not just background prose"
else
  bad "AIC5: no explicit 'do not introduce' prohibition found in the Gate 5.05 block"
fi

# ==================================================================================================
# AID. Records and does not block (§D2). The ADR's divergence-from-spec note must be present so
# it cannot be silently resolved in either direction (made blocking, or the note quietly dropped).
# ==================================================================================================
if grep -qi 'does not block\|do not block\|never block' "$G505"; then
  ok "AID1: Gate 5.05 states the checklist records an answer and does not block"
else
  bad "AID1: no 'does not block' statement found in the Gate 5.05 block"
fi

if grep -qi 'gate, not an aspiration\|gate, not aspiration' "$G505"; then
  ok "AID2: Gate 5.05 cites the SPEC's own 'gate, not an aspiration' wording — the divergence is named, not silently avoided"
else
  bad "AID2: the SPEC's 'gate, not an aspiration' wording is not cited in the Gate 5.05 block"
fi

if grep -qi 'diverg' "$G505"; then
  ok "AID3: Gate 5.05 explicitly labels this a divergence, rather than presenting it as agreement with the SPEC"
else
  bad "AID3: no explicit 'divergence' language found in the Gate 5.05 block"
fi

# AID4: the divergence note must also live in the ADR itself (D2), independent of SKILL.md
# wording — this is the ADR's own record, not something this feature's coder could accidentally
# lose by paraphrasing the ADR's language during the SKILL.md edit.
if grep -q '### D2' "$ADR" && grep -qi 'does not honour the spec' "$ADR"; then
  ok "AID5: ADR-0066 §D2 itself records the divergence in its own text"
else
  bad "AID5: ADR-0066 does not record the spec divergence in §D2"
fi

# ==================================================================================================
# AIE. Conditional on UI-bearing chains, inert otherwise (§D4) — inherits Gate 5.05's existing
# UI-file condition. A CLI-only or docs-only chain records nothing.
# ==================================================================================================
if grep -q 'no UI files changed' "$G505" && grep -q 'accessibility_i18n_findings' "$G505"; then
  ok "AIE1: the empty-diff branch of Gate 5.05 explicitly states no accessibility_i18n_findings entry is written"
else
  bad "AIE1: the empty-diff branch does not name accessibility_i18n_findings at all"
fi

if grep -qi 'inherit' "$G505" || grep -qi 'same UI-file condition\|same UI condition\|one condition' "$G505"; then
  ok "AIE2: Gate 5.05 states the checklist reuses the existing UI-file condition rather than adding a second one"
else
  bad "AIE2: no statement that the checklist inherits Gate 5.05's UI-file condition"
fi

# ==================================================================================================
# AIF. No detector exists (§D5) — assert the absence. Contrast ratios need rendering, label
# meaningfulness needs judgement, "English-centric example" is not a grep pattern.
# ==================================================================================================
if grep -qi 'no detector' "$G505"; then
  ok "AIF1: Gate 5.05 states plainly that no detector backs this checklist"
else
  bad "AIF1: 'no detector' statement missing from the Gate 5.05 block"
fi

# AIF2: no new detector script was added anywhere in the plugin tree for this feature — a script
# named after this feature would contradict the "no detector" claim outright.
N_A11Y_SCRIPTS=$(find "$STAGING/plugin" -iname '*accessibility*' -o -iname '*a11y*' 2>/dev/null | grep -v '/tests/accessibility-i18n.test.sh$' | wc -l | tr -d ' ')
if [ "$N_A11Y_SCRIPTS" -eq 0 ]; then
  ok "AIF2: no accessibility/a11y-named script exists under staging/plugin (only this test file references the feature by name)"
else
  bad "AIF2: found $N_A11Y_SCRIPTS accessibility/a11y-named file(s) under staging/plugin besides this test — a detector script may have been added"
fi

# AIF3: the ADR itself states the no-detector conclusion (§D5), matching the same pattern
# ADR-0062 §D4, ADR-0063 §D4, ADR-0065 §D2 already established.
if grep -q '### D5' "$ADR" && grep -qi 'no detector' "$ADR"; then
  ok "AIF3: ADR-0066 §D5 states the no-detector conclusion"
else
  bad "AIF3: ADR-0066 does not state a no-detector conclusion in §D5"
fi

# ==================================================================================================
# AIG. The finding-vs-metric decision (Task 4): accessibility_i18n_findings carries a claim about
# the work, so it is a FINDING, not a metric (contrast with task_metrics, ADR-0064 §D2). The
# roll-up arithmetic must be consistent: the "stays six arrays, not seven" sentence about
# task_metrics cannot survive verbatim once a real seventh finding array exists.
# ==================================================================================================
if grep -q 'accessibility_i18n_findings.*IS a findings array\|IS a findings array.*accessibility_i18n_findings' "$CC_SKILL"; then
  ok "AIG1: SKILL.md explicitly classifies accessibility_i18n_findings as a findings array, not a metric"
else
  bad "AIG1: no explicit finding-vs-metric classification found for accessibility_i18n_findings"
fi

if grep -q 'stays six arrays, not seven' "$CC_SKILL"; then
  bad "AIG2: the stale 'stays six arrays, not seven' sentence is still present verbatim — it no longer holds now that a seventh finding array exists"
else
  ok "AIG2: the stale 'stays six arrays, not seven' sentence was updated, not left behind"
fi

if grep -q 'seventh advisory-schema finding array' "$CC_SKILL"; then
  ok "AIG3: the Gate 5 roll-up block acknowledges the seventh advisory-schema finding array"
else
  bad "AIG3: the Gate 5 roll-up block does not acknowledge a seventh advisory-schema finding array"
fi

# AIG4: the exclusion from the six-array Gate 5 roll-up must be explained as structural (Gate
# 5.05 runs after Gate 5's AskUserQuestion already rendered), not semantic like task_metrics's —
# these are different reasons and conflating them would misrepresent both.
if grep -qi 'structural, not semantic' "$CC_SKILL"; then
  ok "AIG4: SKILL.md distinguishes accessibility_i18n_findings' structural exclusion from task_metrics' semantic one"
else
  bad "AIG4: no structural-vs-semantic distinction found for the roll-up exclusion"
fi

# ==================================================================================================
# AIH. Registration in both CI registries (ci.yml glob automatic; docs-ci.yml explicit named
# list needs a manual append after licence-provenance).
# ==================================================================================================
if [ -f "$DOCSCI" ]; then
  ok "AIH0: docs-ci.yml is where this harness expects it"
else
  bad "AIH0: $DOCSCI not found — AIH1/AIH1b below are meaningless"
fi

DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]accessibility-i18n[[:space:];]'; then
  ok "AIH1: docs-ci.yml's shell-tests loop list runs accessibility-i18n"
else
  bad "AIH1: accessibility-i18n is not in docs-ci.yml's explicit harness list — append it after licence-provenance"
fi

if printf '%s' "$DOCSCI_LOOP" | grep -qE 'licence-provenance[[:space:]]+accessibility-i18n[[:space:];]'; then
  ok "AIH1b: accessibility-i18n is positioned immediately after licence-provenance, as instructed"
else
  bad "AIH1b: accessibility-i18n is present but not positioned immediately after licence-provenance"
fi

# AIH2: ci.yml's glob is automatic and untouched by this feature — verify it still globs the
# tests directory rather than naming files explicitly (a regression here would mean every prior
# feature's "ci.yml glob automatic" note was quietly falsified).
if [ -f "$CIYML" ] && grep -qF 'staging/plugin/scripts/tests/*.test.sh' "$CIYML"; then
  ok "AIH2: ci.yml still globs staging/plugin/scripts/tests/*.test.sh (no manual registration needed there)"
else
  bad "AIH2: ci.yml no longer globs the tests directory — this feature's test may not run there"
fi

# AIH3: no fixture path this test writes under $TMP targets a denied secrets-shaped substring
# (protect-files.sh denies any path containing 'secrets', plural). This test creates exactly one
# file, "$TMP/gate505.txt" — extract only quoted "$TMP/..." path literals (grep -oE), never a
# whole-file word grep, which would self-trigger on this very comment (it names the forbidden
# substrings in prose, in a line that constructs no such path).
SELF="$SCRIPTS/tests/accessibility-i18n.test.sh"
TMP_PATH_LITERALS=$(grep -oE '"\$TMP/[^"]*"' "$SELF" 2>/dev/null)
if printf '%s\n' "$TMP_PATH_LITERALS" | grep -qiE 'secrets|credential|\.env|\.pem|\.key'; then
  bad "AIH3: a \$TMP-rooted fixture path literal in this test file targets a denied-path-shaped substring"
else
  ok "AIH3: no \$TMP-rooted fixture path literal in this test file targets a secrets/credential/.env/.pem/.key-shaped path"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
