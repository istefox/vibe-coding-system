#!/bin/bash
# licence-provenance.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash licence-provenance.test.sh
#
# Covers issue #119 / ADR-0065: an opt-in `licence-scan` job in the project CI template
# (pinned tool version, report-only, never `:latest`) and a documented human suspicious-output
# procedure added to `clean-public-repo`'s audit phase — deliberately NOT a detector script
# (ADR-0065 §D2).
#
# ASSERTION LABELS ARE PV-PREFIXED (PV0, PVA, PVB, ...). NOT "PA"-"PG": those are already taken by
# proportional-audit-depth.test.sh's own section labels, and both harnesses print into the same CI
# shell-tests job (docs-ci.yml), so a colliding prefix would make the two files' output
# indistinguishable at a glance. Grepped all 41 pre-existing files in this directory before
# picking "PV" (licence Provenance) — no PV-prefixed label exists anywhere in the suite.
#
# THIS IS THE SINGLE MOST IMPORTANT FILE-LEVEL WARNING IN THIS HARNESS (ADR-0065 §D4, plan risk
# flag 1): a green run of this test file, or of the licence-scan CI job it tests, is NOT a
# statement that any tree is clean or free of licence contamination. It asserts that specific
# text exists and specific scripts do not — nothing more. See section PVF.
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL and no fixture path contains "secret",
# "credential", ".env", ".pem", or ".key" — secret-dep-gate.test.sh section D scans this
# repository's tracked files as its false-positive corpus, and protect-files.sh denies any path
# containing "secrets" (plural) — every filename in this feature uses "licence-scan" or
# "licence-provenance" instead (ADR-0046 precedent).
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

CITPL="$STAGING/project-templates/ci/ci.yml"
SKILL="$STAGING/plugin/skills/clean-public-repo/SKILL.md"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
SYNCSH="$STAGING/sync-to-claude.sh"

if [ -f "$CITPL" ] && [ -r "$CITPL" ]; then
  ok "PV0a: $CITPL exists and is readable"
else
  bad "PV0a: $CITPL not found or unreadable — every PVA/PVB/PVC assertion below is meaningless"
fi
if [ -f "$SKILL" ] && [ -r "$SKILL" ]; then
  ok "PV0b: $SKILL exists and is readable"
else
  bad "PV0b: $SKILL not found or unreadable — every PVD/PVE/PVG assertion below is meaningless"
fi
if [ -f "$DOCSCI" ] && [ -r "$DOCSCI" ]; then
  ok "PV0c: $DOCSCI exists and is readable"
else
  bad "PV0c: $DOCSCI not found or unreadable — PVH assertions below are meaningless"
fi

# --- helper: extract a top-level (2-space-indented) job block from ci.yml, from its "  <name>:"
# line up to (not including) the next top-level job key. Mirrors sast-security-audit.test.sh's
# job_block idiom verbatim. -----------------------------------------------------------------------
job_block() { # job_block <job-key> -> prints to stdout
  awk -v key="  $1:" '
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      if ($0 == key) { f=1; print; next } else { f=0 }
    }
    f { print }
  ' "$CITPL"
}

LSBLOCK="$TMP/licence_scan_block.yml"
job_block licence-scan > "$LSBLOCK"
CIBLOCK="$TMP/ci_block.yml"
job_block ci > "$CIBLOCK"
CHECKSBLOCK="$TMP/checks_block.yml"
job_block checks > "$CHECKSBLOCK"
SABLOCK="$TMP/security_audit_block.yml"
job_block security-audit > "$SABLOCK"

# --- helper: extract the new SKILL.md section, from its "## Suspicious-output check" heading up
# to (not including) the next top-level "## " heading. -----------------------------------------
PROVSECTION="$TMP/provenance_section.md"
awk '/^## Suspicious-output check/{f=1} f && /^## / && !/^## Suspicious-output check/{exit} f' "$SKILL" > "$PROVSECTION"

# ==================================================================================================
# PVA. The licence-scan job exists in the CI template, is SEPARATE from ci/checks/security-audit,
# and is opt-in via a repo marker (ADR-0065 §D1, following ADR-0056's shape exactly).
# ==================================================================================================
if [ -s "$LSBLOCK" ]; then
  ok "PVA1: a top-level 'licence-scan:' job block is extractable from ci.yml"
else
  bad "PVA1: no 'licence-scan:' job block found in $CITPL"
fi

if grep -q '^  ci:$' "$CITPL" && grep -q '^  checks:$' "$CITPL" && grep -q '^  security-audit:$' "$CITPL" && grep -q '^  licence-scan:$' "$CITPL"; then
  ok "PVA2: four distinct top-level job keys exist — ci, checks, security-audit, licence-scan"
else
  bad "PVA2: expected four distinct top-level job keys (ci, checks, security-audit, licence-scan)"
fi

if [ -s "$LSBLOCK" ] && [ -s "$CIBLOCK" ] && ! diff -q "$LSBLOCK" "$CIBLOCK" >/dev/null 2>&1; then
  ok "PVA3: licence-scan's job block is not byte-identical to ci's (genuinely a separate job)"
else
  bad "PVA3: licence-scan's job block is identical to ci's, or one is empty"
fi

if [ -s "$LSBLOCK" ] && [ -s "$SABLOCK" ] && ! diff -q "$LSBLOCK" "$SABLOCK" >/dev/null 2>&1; then
  ok "PVA4: licence-scan's job block is not byte-identical to security-audit's — no invented second pattern reused verbatim"
else
  bad "PVA4: licence-scan's job block is identical to security-audit's, or one is empty"
fi

if grep -qF '.claude/licence-scan-enabled' "$LSBLOCK"; then
  ok "PVA5: licence-scan resolves an opt-in marker path (.claude/licence-scan-enabled)"
else
  bad "PVA5: no opt-in marker path found in the licence-scan job block"
fi

if grep -qF "enabled=false" "$LSBLOCK" && grep -qi "opt-in" "$LSBLOCK"; then
  ok "PVA6: the job states the inert-when-absent branch (enabled=false) and calls itself opt-in"
else
  bad "PVA6: the job does not clearly state its inert-when-absent / opt-in behaviour"
fi

PVA7_N=$(grep -c "if: steps.optin.outputs.enabled == 'true'" "$LSBLOCK" || true)
if [ "$PVA7_N" -ge 1 ]; then
  ok "PVA7: at least 1 step is gated on the opt-in output (found $PVA7_N) — real work only runs when opted in"
else
  bad "PVA7: expected >= 1 step gated on steps.optin.outputs.enabled, found $PVA7_N"
fi

# ==================================================================================================
# PVB. THE VERSION PIN (ADR-0065 §D1, ADR-0056 §D2's rule applied unchanged). No :latest anywhere.
# An explicit semantic version or digest is present, and it is a verifiable one (report says which).
# ==================================================================================================
IMGLINE=$(grep -E '^\s*image:\s*licensefinder/license_finder:' "$LSBLOCK" || true)
if [ -n "$IMGLINE" ]; then
  ok "PVB1: an 'image: licensefinder/license_finder:<tag>' line is present in the licence-scan job"
else
  bad "PVB1: no licensefinder/license_finder image line found in the licence-scan job block"
fi

if printf '%s\n' "$IMGLINE" | grep -qF ':latest'; then
  bad "PVB2: the licence-scan image tag is ':latest' — this reverses ADR-0039 §D4, see ADR-0056 §D2 / ADR-0065 §D1"
else
  ok "PVB2: the licence-scan image tag is not ':latest'"
fi

if printf '%s\n' "$IMGLINE" | grep -qE ':[0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$)|@sha256:[0-9a-f]{64}'; then
  ok "PVB3: an explicit semantic version (x.y.z) or a sha256 digest is present on the image line"
else
  bad "PVB3: the image line has neither a semantic version nor a sha256 digest — got: $IMGLINE"
fi

# Whole-file guard, not just this job: the floating tag must not appear ANYWHERE in ci.yml.
if grep -qF 'licensefinder/license_finder:latest' "$CITPL"; then
  bad "PVB4: the literal string 'licensefinder/license_finder:latest' appears somewhere in $CITPL"
else
  ok "PVB4: 'licensefinder/license_finder:latest' does not appear anywhere in ci.yml"
fi

# ==================================================================================================
# PVC. Findings report; they NEVER block (ADR-0065 §D3) — unlike security-audit's ERROR-blocks
# split, no branch in this job may exit non-zero on a finding.
# ==================================================================================================
if grep -qF 'exit 1' "$LSBLOCK"; then
  bad "PVC1: the licence-scan job block contains 'exit 1' — findings must never block (ADR-0065 §D3)"
else
  ok "PVC1: the licence-scan job block contains no 'exit 1' anywhere"
fi

if grep -qi 'never fail the build' "$LSBLOCK" || grep -qi 'report-only' "$LSBLOCK" || grep -qi 'never block' "$LSBLOCK"; then
  ok "PVC2: the job states in its own text that it never fails the build / is report-only"
else
  bad "PVC2: no never-fail-the-build / report-only statement found in the licence-scan job"
fi

if grep -qF 'ADR-0065' "$LSBLOCK"; then
  ok "PVC3: the licence-scan job cross-references ADR-0065"
else
  bad "PVC3: no cross-reference to ADR-0065 in the licence-scan job"
fi

# ==================================================================================================
# PVD. The suspicious-output procedure is added to clean-public-repo's audit phase as a
# DOCUMENTED HUMAN CHECK, not a script (ADR-0065 §D2).
# ==================================================================================================
if [ -s "$PROVSECTION" ]; then
  ok "PVD0: the '## Suspicious-output check' section is extractable from SKILL.md — the anchor every PVD/PVE/PVF(skill) assertion below reads"
else
  bad "PVD0: could not extract a '## Suspicious-output check' section from $SKILL — every PVD/PVE assertion below is meaningless"
fi

if grep -qi 'human procedure' "$PROVSECTION"; then
  ok "PVD1: the section states it is a human procedure"
else
  bad "PVD1: 'human procedure' not found in the suspicious-output section"
fi

if grep -qi 'not a script' "$PROVSECTION" || grep -qi 'not a detector' "$PROVSECTION"; then
  ok "PVD2: the section explicitly states it is not a script / not a detector"
else
  bad "PVD2: no 'not a script' / 'not a detector' statement found"
fi

if grep -qi 'distinctiveness' "$PROVSECTION"; then
  ok "PVD3: the section names the judgement-about-distinctiveness reasoning (ADR-0065 §D2)"
else
  bad "PVD3: 'distinctiveness' not found in the suspicious-output section"
fi

if grep -qi 'network search' "$PROVSECTION"; then
  ok "PVD4: the section names the network-search requirement (ADR-0065 §D2)"
else
  bad "PVD4: 'network search' not found in the suspicious-output section"
fi

if grep -qF 'ADR-0065' "$PROVSECTION"; then
  ok "PVD5: the section cross-references ADR-0065"
else
  bad "PVD5: no cross-reference to ADR-0065 in the suspicious-output section"
fi

if grep -qi 'unique string' "$PROVSECTION" && grep -qi 'search' "$PROVSECTION"; then
  ok "PVD6: the procedure names searching a unique string before keeping suspect output"
else
  bad "PVD6: the procedure does not describe searching a unique string"
fi

# ==================================================================================================
# PVE. NO verbatim-reproduction detector exists — assert the absence (ADR-0065 §D2, plan risk 2).
# ==================================================================================================
VERBATIM_FILES=$(find "$STAGING/plugin/skills/clean-public-repo" -iname '*verbatim*' 2>/dev/null || true)
if [ -z "$VERBATIM_FILES" ]; then
  ok "PVE1: no file with 'verbatim' in its name exists under clean-public-repo/"
else
  bad "PVE1: found a file suggesting a verbatim-reproduction detector: $VERBATIM_FILES"
fi

VERBATIM_ANY=$(find "$STAGING/plugin" -iname '*verbatim*' 2>/dev/null || true)
if [ -z "$VERBATIM_ANY" ]; then
  ok "PVE2: no file with 'verbatim' in its name exists anywhere under staging/plugin/"
else
  bad "PVE2: found a file suggesting a verbatim-reproduction detector: $VERBATIM_ANY"
fi

if grep -qi 'no detector script' "$PROVSECTION"; then
  ok "PVE3: the section states plainly that no detector script exists for this check"
else
  bad "PVE3: no 'no detector script' statement found in the suspicious-output section"
fi

# ==================================================================================================
# PVF. Nothing overclaims (ADR-0065 §D4, plan risk 1). The not-legal-advice statement is present
# in BOTH the licence-scan CI job and the clean-public-repo skill text, and nothing in either block
# says the tree is "clean" or "compliant" as an affirmative claim.
# ==================================================================================================
if grep -qi 'not legal advice' "$LSBLOCK"; then
  ok "PVF1: the licence-scan CI job states its not-legal-advice posture"
else
  bad "PVF1: 'not legal advice' not found in the licence-scan job block"
fi

if grep -qi 'not legal advice' "$PROVSECTION"; then
  ok "PVF2: the suspicious-output section states its not-legal-advice posture"
else
  bad "PVF2: 'not legal advice' not found in the suspicious-output section"
fi

# No line containing "clean" may lack a "not"/"never" qualifier on the SAME line — an affirmative
# "the tree is clean" claim would fail this; the required disclaimer ("does not mean ... clean")
# passes because "not" is on the same line.
OVERCLAIM_CLEAN=$(grep -i 'clean' "$LSBLOCK" "$PROVSECTION" 2>/dev/null | grep -viE 'not |never ' || true)
if [ -z "$OVERCLAIM_CLEAN" ]; then
  ok "PVF3: no unqualified 'clean' claim in the licence-scan job or suspicious-output section"
else
  bad "PVF3: found an unqualified 'clean' claim: $OVERCLAIM_CLEAN"
fi

OVERCLAIM_COMPLIANT=$(grep -i 'compliant' "$LSBLOCK" "$PROVSECTION" 2>/dev/null | grep -viE 'not |never ' || true)
if [ -z "$OVERCLAIM_COMPLIANT" ]; then
  ok "PVF4: no unqualified 'compliant' claim in the licence-scan job or suspicious-output section"
else
  bad "PVF4: found an unqualified 'compliant' claim: $OVERCLAIM_COMPLIANT"
fi

if grep -qi 'declared' "$LSBLOCK" && grep -qi 'cannot see' "$LSBLOCK"; then
  ok "PVF5: the licence-scan job states what the check does (declared metadata) and does not (cannot see verbatim reproduction)"
else
  bad "PVF5: the licence-scan job does not state both the declared-metadata scope and its verbatim-reproduction blind spot"
fi

# ==================================================================================================
# PVG. clean-public-repo's refusal to falsify authorship is UNTOUCHED (ADR-0065 §D5, ADR-0011,
# ADR-0026) — a regression guard, plus a check that the new procedure preserves rather than
# strips attribution.
# ==================================================================================================
if grep -qF 'NEVER falsify authorship' "$SKILL"; then
  ok "PVG1: the standing 'NEVER falsify authorship' invariant is still present in SKILL.md"
else
  bad "PVG1: 'NEVER falsify authorship' is missing from SKILL.md — the ADR-0011/ADR-0026 invariant has regressed"
fi

if grep -qF 'No falsification of authorship. Never falsify authorship.' "$SKILL"; then
  ok "PVG2: the doubled authorship-refusal sentence is still present verbatim"
else
  bad "PVG2: the doubled authorship-refusal sentence is missing or was altered"
fi

if grep -qi 'never delete' "$PROVSECTION"; then
  ok "PVG3: the new procedure states attribution is never deleted, only relocated"
else
  bad "PVG3: the new procedure does not state that attribution is preserved rather than deleted"
fi

if grep -qi 'preserve attribution' "$PROVSECTION"; then
  ok "PVG4: the new procedure explicitly says to preserve attribution rather than strip it (SPEC 119)"
else
  bad "PVG4: 'preserve attribution' not found in the new procedure"
fi

# ==================================================================================================
# PVH. Registration in BOTH CI registries, and clean-public-repo/SKILL.md's PAIRS coverage
# verified (not assumed — it already covers the file we are modifying, not adding).
# ==================================================================================================
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]licence-provenance[[:space:];]'; then
  ok "PVH1: docs-ci.yml's shell-tests loop list runs licence-provenance"
else
  bad "PVH1: licence-provenance is not in docs-ci.yml's explicit harness list — append it after agent-metrics (Task 5)"
fi

awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" > "$TMP/pairs"
if grep -qxF 'plugin/skills/clean-public-repo/SKILL.md|skills/clean-public-repo/SKILL.md' "$TMP/pairs"; then
  ok "PVH2: PAIRS already deploys clean-public-repo/SKILL.md to ~/.claude/skills/clean-public-repo/ — verified, not assumed"
else
  bad "PVH2: no PAIRS entry for plugin/skills/clean-public-repo/SKILL.md — edits here would never deploy"
fi

if grep -qxF 'project-templates/ci/ci.yml|templates/ci.yml' "$TMP/pairs"; then
  ok "PVH3: PAIRS already deploys project-templates/ci/ci.yml to ~/.claude/templates/ci.yml — verified, not assumed"
else
  bad "PVH3: no PAIRS entry for project-templates/ci/ci.yml — the licence-scan job would never deploy"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
