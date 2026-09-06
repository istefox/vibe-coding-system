#!/bin/bash
# litter-discipline.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash litter-discipline.test.sh
#
# Covers issue #116 / ADR-0062: a cleanup clause in the Output Format of coder/debugger/refactorer
# (§D1), the disposition list named as a RECORD not evidence with commit's untracked-file list
# named authoritative (§D2), a temp-branch registry + report-only reconciliation (§D3), and the
# deliberate ABSENCE of two detectors this feature does not build: a stray-file detector (§D2) and
# a debug-log detector (§D4). LD and LF assert those absences — the absence IS the decision here,
# so a passing LD/LF is not a weaker guard than a positive assertion elsewhere in this suite.
#
# ASSERTION LABELS ARE L-PREFIXED (LA, LB, LC, LD, LE, LF, LG) — grepped across the other 38 files
# at HEAD before this file was written; the prefix was unused.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

CODER="$STAGING/plugin/agents/coder.md"
DEBUGGER="$STAGING/plugin/agents/debugger.md"
REFACTORER="$STAGING/plugin/agents/refactorer.md"
COMMITMD="$STAGING/plugin/skills/commit/SKILL.md"
ADR="$REPO/docs/architecture/ADR-0062-116-litter-debris-discipline.md"
TBR="$STAGING/plugin/skills/vibe-status/scripts/temp-branch-reconcile.sh"
AGG="$STAGING/plugin/skills/vibe-status/scripts/aggregate.sh"
SYNCSH="$STAGING/sync-to-claude.sh"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"

awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" > "$TMP/pairs"

# ==============================================================================================
# LA. The cleanup clause lives INSIDE the Output Format section (§D1) — not merely somewhere in
# the file. Extracting the section and grepping inside it, rather than grepping the whole file,
# is the point: Output Format is what an agent actually fills in (ADR-0035's finding).
# ==============================================================================================
for name in coder debugger refactorer; do
  case "$name" in
    coder) f="$CODER" ;;
    debugger) f="$DEBUGGER" ;;
    refactorer) f="$REFACTORER" ;;
  esac
  out="$TMP/${name}_of.txt"
  awk '/^## Output Format$/{f=1; next} /^## /{f=0} f' "$f" > "$out"
  if [ -s "$out" ] && grep -qF '**Cleanup**' "$out"; then
    ok "LA-$name: cleanup clause found inside ## Output Format"
  else
    bad "LA-$name: no cleanup clause inside ## Output Format of $f"
  fi
done

# ==============================================================================================
# LB. The clause names all four classes: temporary files, scratch scripts, debug log statements,
# temp branches (§D1). Checked inside the same extracted section as LA.
# ==============================================================================================
for name in coder debugger refactorer; do
  out="$TMP/${name}_of.txt"
  ok4=1
  grep -qF 'temporary file'      "$out" || ok4=0
  grep -qF 'scratch script'      "$out" || ok4=0
  grep -qF 'debug log statement' "$out" || ok4=0
  grep -qF 'temp branch'         "$out" || ok4=0
  if [ "$ok4" -eq 1 ]; then
    ok "LB-$name: all four debris classes named in the Output Format clause"
  else
    bad "LB-$name: at least one of the four debris classes is missing from the Output Format clause"
  fi
done

# ==============================================================================================
# LC. The disposition list is a RECORD, not evidence — and commit's untracked-file list is named
# as the authoritative, mechanical check (§D2). Stated both in each agent's clause AND wherever
# the list is consumed, i.e. commit/SKILL.md Step 1 (plan Task 3).
# ==============================================================================================
for name in coder debugger refactorer; do
  out="$TMP/${name}_of.txt"
  if grep -qF 'record for the human, not evidence' "$out" \
     && grep -qF 'untracked-file list is the authoritative' "$out"; then
    ok "LC-$name: clause states record-not-evidence and names commit's untracked list authoritative"
  else
    bad "LC-$name: clause is missing the record-not-evidence or authoritative-check statement"
  fi
done

CSTEP1="$TMP/commit_step1.txt"
awk '/^### Step 1 —/{f=1; next} /^### Step 2 —/{f=0} f' "$COMMITMD" > "$CSTEP1"
if grep -qF 'authoritative, mechanical signal for debris' "$CSTEP1" \
   && grep -qF 'ADR-0062' "$CSTEP1"; then
  ok "LC-commit: commit/SKILL.md Step 1 names its untracked list as the authoritative debris signal, citing ADR-0062"
else
  bad "LC-commit: commit/SKILL.md Step 1 is missing the authoritative-signal statement or the ADR-0062 citation"
fi

if grep -qF 'self-report by the party being audited' "$CSTEP1"; then
  ok "LC-commit2: Step 1 states the disposition list is a self-report by the party being audited"
else
  bad "LC-commit2: Step 1 is missing the self-report-by-the-audited-party framing"
fi

# ==============================================================================================
# LD. No new stray-file detector exists (§D2). This is a FORWARD GUARD, not fix evidence — the
# absence already held before this feature touched anything, and the point of this section is to
# make sure it still holds after. Do not "fix" a FAIL here by adding a detector.
# ==============================================================================================
if grep -qiE 'scratch-looking|interim_|_just_in_case' "$COMMITMD"; then
  bad "LD1: commit/SKILL.md contains stray-file-detector vocabulary from the rejected SPEC scope (A1) — a detector was added"
else
  ok "LD1: commit/SKILL.md contains none of the rejected stray-file-detector vocabulary (scratch-looking / interim_ / _just_in_case)"
fi

if [ -f "$ADR" ] && grep -qF 'A1 — A stray-file detector' "$ADR" && grep -qiF 'rejected' "$ADR"; then
  ok "LD2: ADR-0062 records the stray-file detector as rejected (A1)"
else
  bad "LD2: ADR-0062 is missing the A1 stray-file-detector rejection anchor"
fi

if find "$STAGING/plugin/scripts" -maxdepth 1 -iname '*stray*' -o -iname '*scratch-detect*' 2>/dev/null | grep -q .; then
  bad "LD3: a script matching *stray*/*scratch-detect* exists under plugin/scripts — the absence this feature asserts no longer holds"
else
  ok "LD3: no *stray*/*scratch-detect* script exists under plugin/scripts"
fi

# ==============================================================================================
# LE. Temp-branch registry records; reconciliation REPORTS, never deletes (§D3). The spec's case 3
# — a repository lost to a branch cleanup — is the reason, and it must be readable next to the
# reconciliation code itself, not only in the ADR (plan Task 4).
# ==============================================================================================
if [ -f "$TBR" ]; then
  ok "LE1: temp-branch-reconcile.sh exists"
else
  bad "LE1: temp-branch-reconcile.sh not found at $TBR — every LE assertion below is meaningless"
fi

if grep -qF 'register)' "$TBR" 2>/dev/null; then
  ok "LE2: temp-branch-reconcile.sh implements a register subcommand"
else
  bad "LE2: no register subcommand found in temp-branch-reconcile.sh"
fi

if grep -qF 'reconcile)' "$TBR" 2>/dev/null && grep -qF 'STILL-OPEN' "$TBR" 2>/dev/null; then
  ok "LE3: temp-branch-reconcile.sh implements a reconcile subcommand that reports STILL-OPEN entries"
else
  bad "LE3: no reconcile subcommand / STILL-OPEN report marker found in temp-branch-reconcile.sh"
fi

if grep -qE 'git branch (-d|-D|--delete)|push[^\n]*--delete' "$TBR" 2>/dev/null; then
  bad "LE4: temp-branch-reconcile.sh contains a branch-delete command — reconciliation must never delete (§D3)"
else
  ok "LE4: temp-branch-reconcile.sh contains no branch-delete command"
fi

if grep -qF 'a repository lost to a branch cleanup' "$TBR" 2>/dev/null; then
  ok "LE5: the spec's case-3 reasoning is written next to the reconciliation code itself"
else
  bad "LE5: temp-branch-reconcile.sh does not state the case-3 reasoning (repository lost to a branch cleanup)"
fi

if grep -qF 'temp-branch-reconcile.sh' "$AGG" 2>/dev/null; then
  ok "LE6: aggregate.sh (vibe-status) wires in temp-branch-reconcile.sh"
else
  bad "LE6: aggregate.sh does not invoke temp-branch-reconcile.sh"
fi

if grep -qxF 'plugin/skills/vibe-status/scripts/temp-branch-reconcile.sh|skills/vibe-status/scripts/temp-branch-reconcile.sh' "$TMP/pairs"; then
  ok "LE7: PAIRS deploys temp-branch-reconcile.sh to ~/.claude/skills/vibe-status/scripts/"
else
  bad "LE7: temp-branch-reconcile.sh has no PAIRS entry — it would never deploy"
fi

# ==============================================================================================
# LF. No debug-log detector exists (§D4) — named in the instruction, absent from the machinery.
# Forward guards, same posture as LD.
# ==============================================================================================
if [ -f "$ADR" ] && grep -qF 'No detector is added.' "$ADR"; then
  ok "LF1: ADR-0062 states plainly that no debug-log detector is added (§D4)"
else
  bad "LF1: ADR-0062 is missing the 'No detector is added.' sentence"
fi

if grep -qE "print\(|console\.log" "$TBR" 2>/dev/null; then
  bad "LF2: temp-branch-reconcile.sh contains debug-log pattern matching — no such detector should exist"
else
  ok "LF2: temp-branch-reconcile.sh contains no debug-log pattern matching"
fi

for name in coder debugger refactorer; do
  out="$TMP/${name}_of.txt"
  if grep -qF 'no tool in this system detects a leftover debug log statement' "$out"; then
    ok "LF3-$name: clause states plainly that the debug-log class is unenforced"
  else
    bad "LF3-$name: clause does not state that no tool detects a leftover debug log statement"
  fi
done

# ==============================================================================================
# LG. Registration in docs-ci.yml (plan Task 5), now the only CI registry (ADR-0193). PAIRS
# verification for the three agent files (already added by ADR-0043, checked here rather than
# assumed) plus the new script's own entry; no PAIRS entry for the test file itself.
# ==============================================================================================
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE 'human-gate-coverage[[:space:]]+litter-discipline[[:space:];]'; then
  ok "LG1: docs-ci.yml's shell-tests loop runs litter-discipline, appended right after human-gate-coverage"
else
  bad "LG1: litter-discipline is not appended after human-gate-coverage in docs-ci.yml's shell-tests loop"
fi

# LG2 removed (ADR-0193): ci.yml, the second registry this pinned, was deleted — docs-ci.yml's
# shell-tests list above (LG1) is now the only harness runner, and pairs-completeness.test.sh's
# CI3 asserts exactly one workflow executes the suite.

pairs_ok=1
grep -qxF 'plugin/agents/coder.md|agents/coder.md'           "$TMP/pairs" || pairs_ok=0
grep -qxF 'plugin/agents/debugger.md|agents/debugger.md'     "$TMP/pairs" || pairs_ok=0
grep -qxF 'plugin/agents/refactorer.md|agents/refactorer.md' "$TMP/pairs" || pairs_ok=0
if [ "$pairs_ok" -eq 1 ]; then
  ok "LG3: PAIRS already deploys all three changed agent files (coder/debugger/refactorer) — verified, not assumed"
else
  bad "LG3: at least one of coder.md/debugger.md/refactorer.md is missing its PAIRS entry"
fi

if grep -q 'litter-discipline' "$TMP/pairs"; then
  bad "LG4: PAIRS gained an entry for litter-discipline.test.sh — test harnesses do not deploy"
else
  ok "LG4: no PAIRS entry for litter-discipline.test.sh (test files are not deployed)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
