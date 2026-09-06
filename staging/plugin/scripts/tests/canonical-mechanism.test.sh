#!/bin/bash
# canonical-mechanism.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash canonical-mechanism.test.sh
#
# Covers issue #117 / ADR-0063: a `.claude/rules/canonical-mechanisms.md` convention (flat list,
# one line per mechanism, `paths:` frontmatter — §D1), a `project-init` drafting step that detects
# the dominant mechanism and PROPOSES rather than writes silently (§D2), a MINOR (never higher)
# reviewer finding for a hand-rolled equivalent (§D3), the deliberate ABSENCE of a conformance
# detector script (§D4, the same conclusion ADR-0062 §D4 and ADR-0051 reached), and the "absent
# file means nobody declared, not none exist" reading (§D5).
#
# ASSERTION LABELS ARE M-PREFIXED (MA1, MB3, MC2, ...) — grepped across the other 39 files at HEAD
# before this file was written (`grep -rnE '"M[A-F][0-9]'`), the prefix was unused.
#
# NO FIXTURE PATH IN THIS FILE CONTAINS "secret", "credential", ".env", ".pem", or ".key" —
# protect-files.sh denies any path containing "secrets" (plural) and secret-dep-gate.test.sh
# section D scans this repository's tracked files as its false-positive corpus.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

BLUEPRINT="$REPO/docs/vibe-coding-system.md"
REVIEWER="$STAGING/plugin/agents/reviewer.md"
PROJECT_INIT="$STAGING/plugin/skills/project-init/SKILL.md"
DETECTOR="$STAGING/plugin/skills/project-init/scripts/detect-canonical-mechanism.sh"
ADR="$REPO/docs/architecture/ADR-0063-117-canonical-mechanism-conformance.md"
SYNCSH="$STAGING/sync-to-claude.sh"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"

awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" > "$TMP/pairs"

# ==============================================================================================
# M0. Anchors every other section depends on.
# ==============================================================================================
[ -f "$ADR" ]          && ok "M0a: ADR-0063 exists"          || bad "M0a: $ADR not found"
[ -f "$BLUEPRINT" ]    && ok "M0b: vibe-coding-system.md exists" || bad "M0b: $BLUEPRINT not found"
[ -f "$REVIEWER" ]     && ok "M0c: reviewer.md exists"        || bad "M0c: $REVIEWER not found"
[ -f "$PROJECT_INIT" ] && ok "M0d: project-init/SKILL.md exists" || bad "M0d: $PROJECT_INIT not found"

# ==============================================================================================
# MA. The .claude/rules/canonical-mechanisms.md convention is documented where the other rules
# conventions already are (docs/vibe-coding-system.md §5, alongside api-conventions.md) — flat
# list, one line per mechanism, `paths:` frontmatter (§D1). Not a new numbered section.
# ==============================================================================================
if grep -qF 'canonical-mechanisms.md' "$BLUEPRINT" 2>/dev/null; then
  ok "MA1: vibe-coding-system.md documents canonical-mechanisms.md"
else
  bad "MA1: vibe-coding-system.md does not mention canonical-mechanisms.md"
fi

if grep -qF 'name → import path or symbol' "$BLUEPRINT" 2>/dev/null; then
  ok "MA2: the one-line-per-mechanism form (name → import path or symbol) is documented"
else
  bad "MA2: vibe-coding-system.md does not state the 'name → import path or symbol' form"
fi

if grep -A 15 -F 'canonical-mechanisms.md' "$BLUEPRINT" 2>/dev/null | grep -qF 'paths:'; then
  ok "MA3: the canonical-mechanisms.md example carries paths: frontmatter"
else
  bad "MA3: no paths: frontmatter found near the canonical-mechanisms.md example"
fi

if grep -qF 'ADR-0063' "$BLUEPRINT" 2>/dev/null; then
  ok "MA4: vibe-coding-system.md cites ADR-0063"
else
  bad "MA4: vibe-coding-system.md does not cite ADR-0063"
fi

if grep -c '^## 5\.' "$BLUEPRINT" 2>/dev/null | grep -qx 1; then
  ok "MA5: no new numbered '## 5.N' section was introduced — the addition joined an existing one"
else
  bad "MA5: an unexpected number of '## 5.N' headings were found — check no stray section was added"
fi

# ==============================================================================================
# MB. project-init detects the dominant mechanism and PROPOSES a draft — never writes silently
# (§D2). The D2 reasoning (detected property == declared property, contrast ADR-0055 §A4) is
# preserved as a comment. Functional assertions run the actual detection script against fixtures.
# ==============================================================================================
if [ -f "$DETECTOR" ]; then
  ok "MB1: detect-canonical-mechanism.sh exists"
else
  bad "MB1: $DETECTOR not found"
fi

if grep -qF 'detect-canonical-mechanism.sh' "$PROJECT_INIT" 2>/dev/null; then
  ok "MB2: project-init/SKILL.md invokes detect-canonical-mechanism.sh"
else
  bad "MB2: project-init/SKILL.md does not reference detect-canonical-mechanism.sh"
fi

if grep -qiE 'propose|draft' "$PROJECT_INIT" 2>/dev/null && grep -qF 'ADR-0063' "$PROJECT_INIT" 2>/dev/null; then
  ok "MB3: project-init/SKILL.md frames the canonical-mechanisms draft as a proposal, citing ADR-0063"
else
  bad "MB3: project-init/SKILL.md does not both propose the draft and cite ADR-0063"
fi

if grep -qF 'ADR-0055' "$PROJECT_INIT" 2>/dev/null; then
  ok "MB4: project-init/SKILL.md preserves the ADR-0055 §A4 contrast (auto-derivation does not generalise)"
else
  bad "MB4: project-init/SKILL.md does not reference ADR-0055 (the contrast the plan asks to preserve)"
fi

if grep -A 20 -F 'detect-canonical-mechanism.sh' "$PROJECT_INIT" 2>/dev/null | grep -qiE 'never write|without approval'; then
  ok "MB5: project-init/SKILL.md states the draft is never written without approval, near the detection step"
else
  bad "MB5: project-init/SKILL.md does not state a write-without-approval guard near the detection step"
fi

# MB6-MB8: functional — a clear dominant mechanism, a tie, and a too-thin single usage.
mkdir -p "$TMP/dom"
i=1
while [ "$i" -le 4 ]; do
  printf 'import httpx\n' > "$TMP/dom/h$i.py"
  i=$((i+1))
done
printf 'import requests\n' > "$TMP/dom/r1.py"
dom_out=$(bash "$DETECTOR" "$TMP/dom" http 2>/dev/null)
if printf '%s\n' "$dom_out" | grep -qE '^httpx	4$'; then
  ok "MB6: a clearly dominant mechanism (4 files httpx vs 1 requests) is named with its count"
else
  bad "MB6: expected 'httpx<TAB>4', got: $dom_out"
fi

mkdir -p "$TMP/tie"
i=1
while [ "$i" -le 3 ]; do
  printf 'import httpx\n' > "$TMP/tie/h$i.py"
  printf 'import requests\n' > "$TMP/tie/r$i.py"
  i=$((i+1))
done
tie_out=$(bash "$DETECTOR" "$TMP/tie" http 2>/dev/null)
if [ -z "$tie_out" ]; then
  ok "MB7: a tie (3 httpx vs 3 requests) produces no draft"
else
  bad "MB7: expected no output on a tie, got: $tie_out"
fi

mkdir -p "$TMP/single"
printf 'import httpx\n' > "$TMP/single/h1.py"
single_out=$(bash "$DETECTOR" "$TMP/single" http 2>/dev/null)
if [ -z "$single_out" ]; then
  ok "MB8: a single usage (1 file) is too thin a sample and produces no draft"
else
  bad "MB8: expected no output on a single usage, got: $single_out"
fi

if grep -qxF 'plugin/skills/project-init/scripts/detect-canonical-mechanism.sh|skills/project-init/scripts/detect-canonical-mechanism.sh' "$TMP/pairs"; then
  ok "MB9: PAIRS deploys detect-canonical-mechanism.sh to ~/.claude/skills/project-init/scripts/ (pairs-completeness.test.sh does not cover plugin/skills/*/scripts/, ADR-0048)"
else
  bad "MB9: the detect-canonical-mechanism.sh PAIRS entry is missing — it would never deploy"
fi

# ==============================================================================================
# MC. reviewer.md's Consistency checklist carries the conformance question at MINOR severity,
# never higher (§D3) — a later "promotion" to blocking is the likely wrong turn.
# ==============================================================================================
if grep -qF 'canonical-mechanisms.md' "$REVIEWER" 2>/dev/null; then
  ok "MC1: reviewer.md's checklist references canonical-mechanisms.md"
else
  bad "MC1: reviewer.md does not mention canonical-mechanisms.md"
fi

awk '/canonical-mechanisms\.md/{print; f=1; next} f && /^- \*\*/{exit} f{print}' "$REVIEWER" > "$TMP/mc-clause.txt" 2>/dev/null
if grep -qF 'MINOR' "$TMP/mc-clause.txt" 2>/dev/null; then
  ok "MC2: the conformance clause is pinned at MINOR severity"
else
  bad "MC2: the conformance clause does not state MINOR severity"
fi

if grep -qE 'BLOCKER|MAJOR|gate|block' "$TMP/mc-clause.txt" 2>/dev/null; then
  bad "MC3: the conformance clause mentions a higher/blocking severity — MC pins MINOR only"
else
  ok "MC3: the conformance clause does not escalate above MINOR"
fi

if grep -qF 'ADR-0063' "$TMP/mc-clause.txt" 2>/dev/null; then
  ok "MC4: the conformance clause cites ADR-0063"
else
  bad "MC4: the conformance clause does not cite ADR-0063"
fi

# ==============================================================================================
# MD. NO DETECTOR SCRIPT EXISTS (§D4) — the check lives in the reviewer's judgement. Same
# conclusion as ADR-0062 §D4 (debug-log statements) and the same one ADR-0051 reached by
# measurement (25% precision on a comparable heuristic). Assert the absence; it is the decision.
# ==============================================================================================
if [ -f "$ADR" ] && grep -qF 'No detector script' "$ADR" 2>/dev/null; then
  ok "MD1: ADR-0063 states plainly that no detector script is added (§D4)"
else
  bad "MD1: ADR-0063 is missing a 'No detector script' statement"
fi

if find "$STAGING" -iname '*conform*' 2>/dev/null | grep -q .; then
  bad "MD2: a file matching *conform* exists under staging — the absence this feature asserts no longer holds"
else
  ok "MD2: no file matching *conform* exists under staging (no conformance-detector script)"
fi

other_refs=$(grep -rlF 'canonical-mechanisms.md' "$STAGING/plugin/scripts" "$STAGING/plugin/skills"/*/scripts 2>/dev/null | grep -vF '/tests/' | grep -vF 'detect-canonical-mechanism.sh')
if [ -z "$other_refs" ]; then
  ok "MD3: no script other than the project-init drafter references canonical-mechanisms.md — no reviewer-side detector exists"
else
  bad "MD3: unexpected script(s) reference canonical-mechanisms.md: $other_refs"
fi

if grep -qF '.sh' "$TMP/mc-clause.txt" 2>/dev/null; then
  bad "MD4: reviewer.md's conformance clause invokes a script — the check must stay pure judgement (§D4)"
else
  ok "MD4: reviewer.md's conformance clause invokes no script — pure judgement"
fi

# ==============================================================================================
# ME. Absent file is inert; the text says absent means "nobody declared", not "none exist" (§D5).
# ==============================================================================================
if grep -qF 'nobody declared' "$BLUEPRINT" 2>/dev/null; then
  ok "ME1: vibe-coding-system.md states absence means nobody declared a mechanism"
else
  bad "ME1: vibe-coding-system.md does not state the 'nobody declared' reading"
fi

if grep -qiE 'not that the project has none|does not mean the project has no' "$BLUEPRINT" 2>/dev/null; then
  ok "ME2: vibe-coding-system.md explicitly distinguishes 'nobody declared' from 'none exist'"
else
  bad "ME2: vibe-coding-system.md does not distinguish 'nobody declared' from 'none exist'"
fi

if grep -qiE 'nobody declared|absence' "$TMP/mc-clause.txt" 2>/dev/null; then
  ok "ME3: reviewer.md's conformance clause also states the absent-file reading at the point of use"
else
  bad "ME3: reviewer.md's conformance clause does not restate the absent-file reading"
fi

# ==============================================================================================
# MF. Registration in docs-ci.yml (plan Task 5), now the only CI registry (ADR-0193).
# ==============================================================================================
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE 'litter-discipline[[:space:]]+canonical-mechanism[[:space:];]'; then
  ok "MF1: docs-ci.yml's shell-tests loop runs canonical-mechanism, appended right after litter-discipline"
else
  bad "MF1: canonical-mechanism is not appended after litter-discipline in docs-ci.yml's shell-tests loop"
fi

# MF2 removed (ADR-0193): ci.yml, the second registry this pinned, was deleted — docs-ci.yml's
# shell-tests list above (MF1) is now the only harness runner, and pairs-completeness.test.sh's
# CI3 asserts exactly one workflow executes the suite.

pairs_ok=1
grep -qxF 'plugin/agents/reviewer.md|agents/reviewer.md' "$TMP/pairs" || pairs_ok=0
grep -qxF 'plugin/skills/project-init/SKILL.md|skills/project-init/SKILL.md' "$TMP/pairs" || pairs_ok=0
if [ "$pairs_ok" -eq 1 ]; then
  ok "MF3: PAIRS already deploys the changed reviewer.md and project-init/SKILL.md — verified, not assumed"
else
  bad "MF3: reviewer.md or project-init/SKILL.md is missing its PAIRS entry"
fi

stray=$(grep 'canonical-mechanism' "$TMP/pairs" 2>/dev/null | grep -v 'detect-canonical-mechanism.sh')
if [ -z "$stray" ]; then
  ok "MF4: no stray PAIRS entry for this feature beyond the detector script"
else
  bad "MF4: unexpected PAIRS entries mentioning canonical-mechanism: $stray"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
