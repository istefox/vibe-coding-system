#!/bin/bash
# sast-security-audit.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash sast-security-audit.test.sh
#
# Covers issue #110 / ADR-0056: an opt-in `security-audit` job in the project CI template
# (pinned Semgrep, ERROR-blocks/WARNING-INFO-prints), and a report-only `security-audit` skill
# implementing the spec's ten-step protocol.
#
# ASSERTION LABELS ARE S-PREFIXED (SA1, SB2, SD3, ...) to stay distinguishable from every other
# harness printing into the same CI shell-tests job (B-, R-, H-, W-, I-, P-, C-, ...).
#
# SECTION SB IS THE SINGLE MOST IMPORTANT ASSERTION IN THIS FILE (ADR-0056 §D2, plan risk flag
# 1). ADR-0039 §D4 removed linters from the write path on the rule that a verdict depending on
# which tools are installed is not a verdict. Semgrep is that class of tool, and the ONLY thing
# that keeps this CI job from reversing that decision is the version pin: no `:latest`, an
# explicit version or digest present. If SB ever goes green against a `:latest` tag, the guard
# has failed at its one job.
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL and no fixture path contains "secret",
# "credential", ".env", ".pem", or ".key" — secret-dep-gate.test.sh section D scans this
# repository's tracked files as its false-positive corpus, and protect-files.sh denies any path
# containing "secrets" (plural) — every filename in this feature uses "security-audit" instead
# (ADR-0046).
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
SKILL="$STAGING/plugin/skills/security-audit/SKILL.md"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
SYNCSH="$STAGING/sync-to-claude.sh"
CR="$SCRIPTS/codex-reviewer.sh"

# flat_regex_text is the same normalising helper codex-review-dispatch-gate.test.sh's G-series
# uses (rule 6: same question — does this prose contain X, ignoring markdown decoration and line
# wrapping — so the identical function is copied rather than reinvented).
flat_regex_text() {
  python3 -c '
import re, sys
text = re.sub(r"[`*_]", "", sys.argv[1])
text = re.sub(r"\s+", " ", text).lower()
print(1 if re.search(sys.argv[2], text) else 0)
' "$1" "$2"
}

if [ -f "$CR" ] && [ -r "$CR" ]; then
  ok "S0b: $CR exists and is readable"
else
  bad "S0b: $CR not found or unreadable — SG10-SG13 below are meaningless"
fi

if [ -f "$CITPL" ] && [ -r "$CITPL" ]; then
  ok "S0a: $CITPL exists and is readable"
else
  bad "S0a: $CITPL not found or unreadable — every SA/SB/SC assertion below is meaningless"
fi
if [ -f "$SKILL" ] && [ -r "$SKILL" ]; then
  ok "S0b: $SKILL exists and is readable"
else
  bad "S0b: $SKILL not found or unreadable — every SD/SE/SF/SG assertion below is meaningless"
fi

# --- helper: extract a top-level (2-space-indented) job block from ci.yml, from its "  <name>:"
# line up to (not including) the next top-level job key. Mirrors project-ci-checks.test.sh's
# job_block idiom. -----------------------------------------------------------------------------
job_block() { # job_block <job-key> -> prints to stdout
  awk -v key="  $1:" '
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      if ($0 == key) { f=1; print; next } else { f=0 }
    }
    f { print }
  ' "$CITPL"
}

SABLOCK="$TMP/security_audit_block.yml"
job_block security-audit > "$SABLOCK"
CIBLOCK="$TMP/ci_block.yml"
job_block ci > "$CIBLOCK"
CHECKSBLOCK="$TMP/checks_block.yml"
job_block checks > "$CHECKSBLOCK"

# ==================================================================================================
# SA. The security-audit job exists, is SEPARATE from ci and checks, and is opt-in via a marker.
# ==================================================================================================
if [ -s "$SABLOCK" ]; then
  ok "SA1: a top-level 'security-audit:' job block is extractable from ci.yml"
else
  bad "SA1: no 'security-audit:' job block found in $CITPL"
fi

if grep -q '^  ci:$' "$CITPL" && grep -q '^  checks:$' "$CITPL" && grep -q '^  security-audit:$' "$CITPL"; then
  ok "SA2: three distinct top-level job keys exist — ci, checks, security-audit"
else
  bad "SA2: expected three distinct top-level job keys (ci, checks, security-audit)"
fi

if [ -s "$SABLOCK" ] && [ -s "$CIBLOCK" ] && ! diff -q "$SABLOCK" "$CIBLOCK" >/dev/null 2>&1; then
  ok "SA3: security-audit's job block is not byte-identical to ci's (genuinely separate jobs)"
else
  bad "SA3: security-audit's job block is identical to ci's, or one is empty"
fi

if [ -s "$SABLOCK" ] && [ -s "$CHECKSBLOCK" ] && ! diff -q "$SABLOCK" "$CHECKSBLOCK" >/dev/null 2>&1; then
  ok "SA4: security-audit's job block is not byte-identical to checks's (genuinely separate jobs)"
else
  bad "SA4: security-audit's job block is identical to checks's, or one is empty"
fi

if grep -qF '.claude/security-audit-enabled' "$SABLOCK"; then
  ok "SA5: security-audit resolves an opt-in marker path (.claude/security-audit-enabled)"
else
  bad "SA5: no opt-in marker path found in the security-audit job block"
fi

if grep -qF "enabled=false" "$SABLOCK" && grep -qi "opt-in" "$SABLOCK"; then
  ok "SA6: the job states the inert-when-absent branch (enabled=false) and calls itself opt-in"
else
  bad "SA6: the job does not clearly state its inert-when-absent / opt-in behaviour"
fi

SA7_N=$(grep -c "if: steps.optin.outputs.enabled == 'true'" "$SABLOCK" || true)
if [ "$SA7_N" -ge 2 ]; then
  ok "SA7: at least 2 steps are gated on the opt-in output (found $SA7_N) — real work only runs when opted in"
else
  bad "SA7: expected >= 2 steps gated on steps.optin.outputs.enabled, found $SA7_N"
fi

# ==================================================================================================
# SB. THE VERSION PIN (ADR-0056 §D2). No :latest, anywhere in this job. An explicit version or
# digest is present on the Semgrep image line. This is the load-bearing assertion in this file.
# ==================================================================================================
IMGLINE=$(grep -E '^\s*image:\s*semgrep/semgrep:' "$SABLOCK" || true)
if [ -n "$IMGLINE" ]; then
  ok "SB1: an 'image: semgrep/semgrep:<tag>' line is present in the security-audit job"
else
  bad "SB1: no semgrep/semgrep image line found in the security-audit job block"
fi

if printf '%s\n' "$IMGLINE" | grep -qF ':latest'; then
  bad "SB2: the Semgrep image tag is ':latest' — this reverses ADR-0039 §D4, see ADR-0056 §D2"
else
  ok "SB2: the Semgrep image tag is not ':latest'"
fi

if printf '%s\n' "$IMGLINE" | grep -qE ':[0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$)|@sha256:[0-9a-f]{64}'; then
  ok "SB3: an explicit semantic version (x.y.z) or a sha256 digest is present on the image line"
else
  bad "SB3: the image line has neither a semantic version nor a sha256 digest — got: $IMGLINE"
fi

# Whole-file guard, not just this job: 'semgrep/semgrep:latest' must not appear ANYWHERE in
# ci.yml, so a second, differently-named job could not quietly reintroduce it either.
if grep -qF 'semgrep/semgrep:latest' "$CITPL"; then
  bad "SB4: the literal string 'semgrep/semgrep:latest' appears somewhere in $CITPL"
else
  ok "SB4: 'semgrep/semgrep:latest' does not appear anywhere in ci.yml"
fi

if grep -qF -- '--config=auto' "$SABLOCK"; then
  bad "SB5: the ruleset is '--config=auto' (dynamic, unpinned) rather than a named pack"
else
  ok "SB5: the security-audit job does not use --config=auto"
fi

if grep -qE -- '--config=p/[A-Za-z0-9_-]+' "$SABLOCK"; then
  ok "SB6: a named, explicit Semgrep ruleset pack is configured (--config=p/<name>)"
else
  bad "SB6: no named --config=p/<name> ruleset found in the security-audit job"
fi

# ==================================================================================================
# SC. ERROR blocks; WARNING and INFO print (ADR-0056 §D3).
# ==================================================================================================
if grep -qF '"ERROR"' "$SABLOCK" && grep -qF 'exit 1' "$SABLOCK"; then
  ok "SC1: the job filters for ERROR severity and has an exit 1 path"
else
  bad "SC1: missing an ERROR-severity filter or an exit 1 path"
fi

# The exit 1 must be conditioned on the errors count, not unconditional.
if grep -qE '\$errors" -gt 0.*\n?' "$SABLOCK" 2>/dev/null || grep -qF '"$errors" -gt 0' "$SABLOCK"; then
  ok "SC2: exit 1 is gated on an errors-count condition, not unconditional"
else
  bad "SC2: no errors-count condition found guarding the exit"
fi

if grep -qF '"WARNING"' "$SABLOCK" && grep -qF '"INFO"' "$SABLOCK"; then
  ok "SC3: the job distinguishes WARNING and INFO severities from ERROR"
else
  bad "SC3: WARNING/INFO severities are not both referenced in the security-audit job"
fi

if grep -qF 'never block the build' "$SABLOCK" || grep -qF 'print-only' "$SABLOCK" || grep -qi 'printed, never' "$SABLOCK"; then
  ok "SC4: the job states in its own text that WARNING/INFO never fail the build"
else
  bad "SC4: no statement that WARNING/INFO findings are print-only"
fi

# WARNING/INFO handling must not itself exit 1 — the notice branch has no exit statement between
# it and the next top-level condition.
WISECTION=$(awk '/warnings" -gt 0/{f=1} f{print} /^          fi$/{if(f==1){exit}}' "$SABLOCK")
if ! printf '%s\n' "$WISECTION" | grep -qF 'exit 1'; then
  ok "SC5: the WARNING/INFO print branch contains no exit 1 (mirrors the print-only contract)"
else
  bad "SC5: the WARNING/INFO branch appears to exit 1 — that would fail the build on a heuristic"
fi

if grep -qF 'ADR-0054 §D5' "$SABLOCK"; then
  ok "SC6: the job cross-references ADR-0054 §D5's evidence-quality split, matching the house convention"
else
  bad "SC6: no cross-reference to ADR-0054 §D5 in the security-audit job"
fi

# ==================================================================================================
# SD. The skill exists, with all ten protocol steps present and individually identifiable.
# ==================================================================================================
EXPECTED_STEPS="Automated scanners|Separate-AI review|Human checklist|Fuzz and pen-test notes|Security-focused unit tests|Training-cutoff compensation|Logging hygiene|Updated tooling|Warnings in context|Slow down on security-sensitive work"

_n=1
IFS='|'
for _title in $EXPECTED_STEPS; do
  if grep -qF "### Step $_n — $_title" "$SKILL"; then
    ok "SD$_n: heading '### Step $_n — $_title' is present"
  else
    bad "SD$_n: heading '### Step $_n — $_title' not found in $SKILL"
  fi
  _n=$((_n+1))
done
unset IFS

SD11_N=$(grep -cE '^### Step [0-9]+ — ' "$SKILL" || true)
if [ "$SD11_N" -eq 10 ]; then
  ok "SD11: exactly 10 '### Step N —' headings exist (no duplicate, no missing)"
else
  bad "SD11: expected exactly 10 '### Step N —' headings, found $SD11_N"
fi

# ==================================================================================================
# SE. The skill reports; it does not fix (ADR-0056 §D4).
# ==================================================================================================
if grep -qi 'report-only' "$SKILL" || grep -qi 'never fix' "$SKILL" || grep -qi 'never edits' "$SKILL"; then
  ok "SE1: the skill states its report-only posture in its own text"
else
  bad "SE1: no report-only / never-fix statement found in the skill"
fi

if grep -qF 'never dispatches a fixing agent' "$SKILL"; then
  ok "SE2: the skill explicitly states it never dispatches a fixing agent"
else
  bad "SE2: 'never dispatches a fixing agent' not found in the skill"
fi

# Positive dispatch language only — lines that also contain "never" are the negation this skill
# is required to state (SE2), not a real dispatch, so they are excluded rather than mis-flagged.
FIXVERBS='dispatch.*(the )?`?coder`?|dispatch.*(the )?`?refactorer`?|dispatch.*(the )?`?debugger`?'
FIXHITS=$(grep -Ei "$FIXVERBS" "$SKILL" | grep -vi 'never' || true)
if [ -n "$FIXHITS" ]; then
  bad "SE3: the skill's text appears to dispatch a fixing agent (coder/refactorer/debugger) somewhere: $FIXHITS"
else
  ok "SE3: the skill never dispatches coder, refactorer, or debugger anywhere in its text"
fi

if grep -qF 'deep-refactor' "$SKILL" && grep -qF 'review-triage-fix' "$SKILL"; then
  ok "SE4: the skill cross-references both existing report-only security paths (deep-refactor, review-triage-fix)"
else
  bad "SE4: the skill is missing a cross-reference to deep-refactor and/or review-triage-fix"
fi

# ==================================================================================================
# SF. OWASP Top 10 named with an explicit year (ADR-0056 §D5); maintenance obligation stated.
# ==================================================================================================
if grep -qE 'OWASP Top 10[: ]?2[0-9]{3}' "$SKILL"; then
  ok "SF1: an OWASP Top 10 edition with a 4-digit year is named in the skill"
else
  bad "SF1: no OWASP Top 10 edition with an explicit year found in the skill"
fi

if grep -qi 'the current OWASP Top 10' "$SKILL"; then
  bad "SF2: the skill contains the forbidden phrase 'the current OWASP Top 10' (unresolved, invites stale memory)"
else
  ok "SF2: the skill does not contain the bare phrase 'the current OWASP Top 10'"
fi

if grep -qi 'maintenance obligation' "$SKILL"; then
  ok "SF3: the skill states the named year is a maintenance obligation"
else
  bad "SF3: 'maintenance obligation' not found in the skill"
fi

if grep -qi 'stale year is worse than no year' "$SKILL"; then
  ok "SF4: the skill states a stale year is worse than no year (reads as current)"
else
  bad "SF4: the 'stale year is worse than no year' statement is missing"
fi

# ==================================================================================================
# SG. The separate-AI review step pins a DIFFERENT model; same-model self-review does not satisfy.
# ==================================================================================================
STEP2="$TMP/step2.txt"
awk '/^### Step 2 — Separate-AI review$/{f=1} /^### Step 3 — /{f=0} f' "$SKILL" > "$STEP2"

if [ -s "$STEP2" ]; then
  ok "SG0: Step 2 of the skill is extractable (the anchor every SG assertion below reads)"
else
  bad "SG0: could not extract Step 2 from $SKILL — every SG assertion below is meaningless"
fi

if grep -qF 'model: opus' "$STEP2" || grep -qF 'model: sonnet' "$STEP2"; then
  ok "SG1: Step 2 names an explicit model pin (opus or sonnet) for the dispatched review"
else
  bad "SG1: Step 2 does not name an explicit model pin"
fi

if grep -qi 'differ' "$STEP2" || grep -qi 'DIFFERS from' "$STEP2"; then
  ok "SG2: Step 2 states the dispatched model must differ from the orchestrator's own session model"
else
  bad "SG2: Step 2 does not state the model must differ from the session's own model"
fi

if grep -qF 'does not satisfy this step' "$STEP2"; then
  ok "SG3: Step 2 states plainly that same-model self-review does not satisfy the step"
else
  bad "SG3: 'does not satisfy this step' not found in Step 2"
fi

if grep -qF 'security-only' "$STEP2"; then
  ok "SG4: Step 2 specifies a security-only brief for the dispatched review"
else
  bad "SG4: Step 2 does not specify a security-only brief"
fi

if grep -qF 'ADR-0049' "$STEP2"; then
  ok "SG5: Step 2 cross-references ADR-0049 (the generator/verifier separation precedent)"
else
  bad "SG5: Step 2 does not cross-reference ADR-0049"
fi

# plant: SG6 | plugin/skills/security-audit/SKILL.md | ADR-0195 D2 | ADR REMOVED
if grep -qF 'ADR-0195 D2' "$STEP2"; then
  ok "SG6: Step 2 offers a Codex-vs-Claude backend ask, cross-referencing ADR-0195 D2"
else
  bad "SG6: Step 2 does not offer a Codex-vs-Claude backend ask (ADR-0195 D2)"
fi

# plant: SG7 | plugin/skills/security-audit/SKILL.md | --focus security | --focus none
if grep -qF -- '--focus security' "$STEP2"; then
  ok "SG7: Step 2's Codex dispatch uses the --focus security flag (ADR-0195 D3)"
else
  bad "SG7: Step 2's Codex dispatch does not pass --focus security"
fi

# plant: SG8 | plugin/skills/security-audit/SKILL.md | invisible to Codex on this scope | visible to Codex on this scope
if grep -qF 'invisible to Codex on this scope' "$STEP2"; then
  ok "SG8: Step 2 surfaces the untracked-file blind spot before the backend ask (ADR-0195 D4)"
else
  bad "SG8: Step 2 does not surface the untracked-file blind spot"
fi

# plant: SG9 | plugin/skills/security-audit/SKILL.md | never silently fall back to Claude | may silently fall back to Claude
if grep -qF 'never silently fall back to Claude' "$STEP2"; then
  ok "SG9: Step 2's Codex-unavailable path never silently falls back to Claude"
else
  bad "SG9: Step 2 does not state the never-silent-fallback convention"
fi

# ==================================================================================================
# SG10-SG13. ADR-0199: live Codex model/effort choice at the Step 2 [codex] dispatch, defaulting
# sol/high (NOT RTF's/Step 5's sol/medium, ADR-0198) — this is the system's lowest-volume,
# highest-miss-cost review site (ADR-0195 M6) and the live choice must not silently downgrade it.
# ==================================================================================================

# plant: SG10 | plugin/skills/security-audit/SKILL.md | (gpt-5.6-sol) (default — today's pin) (Recommended) | (gpt-5.6-sol) (Recommended)REMOVED_HIGH_DEFAULT
# Needles are anchored to the literal option-list text (not a loose proximity window) because the
# same STEP2 slice also contains SG11's divergence-note sentence, which itself pairs the words
# "sol" and "default" a few dozen characters apart — a loose window is satisfied by that unrelated
# sentence even with the option-list default marker deleted (rule 1: caught live while planting).
STEP2_TEXT=$(cat "$STEP2")
SG10_SOL=$(flat_regex_text "$STEP2_TEXT" '\[sol\]')
SG10_ASTRA=$(flat_regex_text "$STEP2_TEXT" '\[astra\]')
SG10_TERRA=$(flat_regex_text "$STEP2_TEXT" '\[terra\]')
SG10_MODEL_DEFAULT=$(flat_regex_text "$STEP2_TEXT" '\[sol\] "sol \(gpt-5\.6-sol\) \(default')
SG10_EFFORT_DEFAULT=$(flat_regex_text "$STEP2_TEXT" '\[high\] "\(default')
SG10_ALL_EFFORTS=1
for _v in low medium high xhigh max ultra; do
  [ "$(flat_regex_text "$STEP2_TEXT" "\\b$_v\\b")" -eq 1 ] || SG10_ALL_EFFORTS=0
done
if [ "$SG10_SOL" -eq 1 ] && [ "$SG10_ASTRA" -eq 1 ] && [ "$SG10_TERRA" -eq 1 ] \
   && [ "$SG10_MODEL_DEFAULT" -eq 1 ] && [ "$SG10_EFFORT_DEFAULT" -eq 1 ] \
   && [ "$SG10_ALL_EFFORTS" -eq 1 ]; then
  ok "SG10: Step 2's Codex sub-ask offers sol/astra/terra and all six efforts, defaulting sol/high"
else
  bad "SG10: sub-ask incomplete — sol=$SG10_SOL astra=$SG10_ASTRA terra=$SG10_TERRA model-default=$SG10_MODEL_DEFAULT effort-default=$SG10_EFFORT_DEFAULT all-efforts=$SG10_ALL_EFFORTS"
fi

# plant: SG11 | plugin/skills/security-audit/SKILL.md | sol/medium default (ADR-0198), this sub-ask defaults to `sol`/`high` | sol/medium default (ADR-0198), this sub-ask defaults to REMOVED_DIVERGENCE_NOTE
if [ "$(flat_regex_text "$STEP2_TEXT" 'sol.{0,40}medium.{0,80}sub-ask defaults to.{0,20}sol.{0,20}high')" -eq 1 ]; then
  ok "SG11: Step 2 states its sol/high default diverges from RTF's/Step 5's sol/medium default"
else
  bad "SG11: Step 2 does not distinguish its sol/high default from RTF's/Step 5's sol/medium default"
fi

# plant: SG12 | plugin/skills/security-audit/SKILL.md | --model <chosen-model> --effort <chosen-effort> | --model <chosen-model>REMOVED_EFFORT
# There is only one invocation site in this file (unlike RTF's three), and the invocation line
# wraps across physical lines in the markdown source, so the count is taken over the whole Step 2
# slice rather than requiring --model/--effort to share a physical line with codex-reviewer.sh.
SG12_MODEL_COUNT=$(grep -oF -- '--model <chosen-model>' "$STEP2" | wc -l | tr -d ' ')
SG12_EFFORT_COUNT=$(grep -oF -- '--effort <chosen-effort>' "$STEP2" | wc -l | tr -d ' ')
if [ "$SG12_MODEL_COUNT" -eq 1 ] && [ "$SG12_EFFORT_COUNT" -eq 1 ]; then
  ok "SG12: Step 2's invocation line carries exactly one --model and one --effort"
else
  bad "SG12: expected exactly 1/1 --model/--effort on the Step 2 invocation, found $SG12_MODEL_COUNT/$SG12_EFFORT_COUNT"
fi

# SG13: anti-drift (rule 6/17) — the model tokens Step 2 offers must be exactly the closed set
# codex-reviewer.sh's own case arms accept (astra,sol,terra). Cross-checked against the script
# rather than re-declaring a second independent literal list — a value added to one side and not
# the other would silently reject or omit a choice this gate just offered.
SG13_SCRIPT_MODELS=$(python3 -c '
import re, sys
text = open(sys.argv[1]).read()
print(",".join(sorted(re.findall(r"^\s*(\w+)\) CODEX_MODEL=", text, re.M))))
' "$CR")
if [ "$SG13_SCRIPT_MODELS" = "astra,sol,terra" ]; then
  ok "SG13: codex-reviewer.sh's closed model set matches Step 2's sol/astra/terra offer (astra,sol,terra)"
else
  bad "SG13: codex-reviewer.sh's model set drifted from Step 2's offer, found '$SG13_SCRIPT_MODELS'"
fi

# ==================================================================================================
# SH. Registration in both CI registries, and a PAIRS entry for the skill.
# ==================================================================================================
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]sast-security-audit[[:space:];]'; then
  ok "SH1: docs-ci.yml's shell-tests loop list runs sast-security-audit"
else
  bad "SH1: sast-security-audit is not in docs-ci.yml's explicit harness list — append it (Task 6)"
fi

awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" > "$TMP/pairs"
if grep -qxF 'plugin/skills/security-audit/SKILL.md|skills/security-audit/SKILL.md' "$TMP/pairs"; then
  ok "SH2: PAIRS deploys the new skill's SKILL.md to ~/.claude/skills/security-audit/"
else
  bad "SH2: no PAIRS entry for plugin/skills/security-audit/SKILL.md — it would never deploy"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
