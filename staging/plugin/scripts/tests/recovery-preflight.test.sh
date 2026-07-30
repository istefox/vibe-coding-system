#!/bin/bash
# recovery-preflight.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash recovery-preflight.test.sh
#
# Covers issue #104 / ADR-0050: a recovery-readiness pre-flight at the top of concept-to-code
# Step 5, before any dispatch — working tree clean, a feature branch (not the default) checked
# out, HEAD sha recorded once as recovery_baseline_sha.
#
# ADR-0050 §D4 IS THE POINT OF THIS FEATURE, NOT AN ASIDE: this pre-flight REFUSES on a dirty
# tree; ADR-0049's dirty-tree condition a few lines below in the same Step 5 TOLERATES one. They
# are sequential (this runs first, at Step 5 entry; ADR-0049's runs per coder dispatch, after the
# tester has deliberately dirtied the tree), never contradictory. Section RE exists so a future
# edit that tries to "reconcile" the two conditions into one fails CI instead of merging quietly.
#
# ASSERTION LABELS ARE R-PREFIXED (RA1, RD3, RG2, ...) — same convention as spec-coverage.test.sh.
# To stay distinguishable in the same CI shell-tests job: spec-coverage.test.sh already used the
# same prefix for issue #102; this file's section names (RA/RB/RC/RD/RE/RF/RG) do not collide with
# spec-coverage's finer RA1..RI6 labels because both are read by full assertion string, not prefix.
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL and NO PATH CONTAINING secret / credential /
# .env / .pem / .key — protect-files.sh denies such paths and secret-dep-gate.test.sh section D
# scans this repository's tracked files (via git ls-files) as its false-positive corpus.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
AB="$STAGING/plugin/skills/autopilot-build/SKILL.md"
INIT="$STAGING/plugin/skills/concept-to-code/scripts/manifest-init.sh"
VALIDATE="$STAGING/plugin/skills/concept-to-code/scripts/manifest-validate.sh"

# ==============================================================================================
# Anchor + extraction every RA-RF assertion below depends on.
# ==============================================================================================
if [ -f "$CC" ] && [ -r "$CC" ]; then
  ok "RA0: concept-to-code/SKILL.md exists and is readable"
else
  bad "RA0: $CC not found or unreadable — every RA/RB/RC/RE/RF assertion below is meaningless"
fi

STEP5="$TMP/c2c_step5.txt"
awk '/^### Step 5 —/{f=1} /^### Step 6 —/{f=0} f' "$CC" >"$STEP5" 2>/dev/null
if [ -s "$STEP5" ]; then
  ok "RA0b: Step 5 of concept-to-code/SKILL.md is extractable"
else
  bad "RA0b: could not extract Step 5 from $CC — every RA/RB/RC/RE/RF assertion below is meaningless"
fi

# ==============================================================================================
# RA. The three assertions exist in c2c Step 5 as prose anchors, at the very top of the step.
# ==============================================================================================
RA1_N=$(grep -c '^#### Recovery-readiness pre-flight (ADR-0050, before any dispatch)$' "$CC" 2>/dev/null || true)
case "$RA1_N" in ''|*[!0-9]*) RA1_N=0 ;; esac
if [ "$RA1_N" -eq 1 ]; then
  ok "RA1: exactly one occurrence of the Recovery-readiness pre-flight heading in the whole file"
else
  bad "RA1: expected exactly 1 occurrence of the heading, found $RA1_N"
fi

PREFLIGHT_LINE=$(grep -n '^#### Recovery-readiness pre-flight (ADR-0050, before any dispatch)$' "$CC" 2>/dev/null | head -1 | cut -d: -f1)
DISPATCH_LINE=$(grep -n '^\*\*Dispatch mode selection:\*\*$' "$CC" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$PREFLIGHT_LINE" ] && [ -n "$DISPATCH_LINE" ] && [ "$PREFLIGHT_LINE" -lt "$DISPATCH_LINE" ]; then
  ok "RA2: the pre-flight heading sits before dispatch-mode selection (top of Step 5, before any dispatch)"
else
  bad "RA2: pre-flight heading is missing or not positioned before dispatch-mode selection"
fi

if grep -qF 'git status --porcelain' "$STEP5"; then
  ok "RA3: Step 5 contains the working-tree-clean assertion (git status --porcelain)"
else
  bad "RA3: Step 5 is missing git status --porcelain"
fi

if grep -qF 'git symbolic-ref --short HEAD' "$STEP5"; then
  ok "RA4: Step 5 contains the feature-branch assertion (git symbolic-ref --short HEAD)"
else
  bad "RA4: Step 5 is missing git symbolic-ref --short HEAD"
fi

if grep -qF 'Record as `BASELINE_COMMIT`' "$STEP5" && grep -qF 'git rev-parse HEAD' "$STEP5"; then
  ok "RA5: Step 5 contains the HEAD-sha-recorded assertion (git rev-parse HEAD -> BASELINE_COMMIT)"
else
  bad "RA5: Step 5 is missing the BASELINE_COMMIT recording assertion"
fi

# ==============================================================================================
# RB. The refusal names a literal remediation command for each failure.
# ==============================================================================================
if grep -qF "git stash push -u -m 'c2c-step5-preflight'" "$STEP5"; then
  ok "RB1: the dirty-tree refusal names the literal remediation command (git stash push -u -m ...)"
else
  bad "RB1: dirty-tree refusal is missing the literal git stash push -u -m remediation command"
fi

if grep -qF 'git checkout -b feat/<slug>' "$STEP5"; then
  ok "RB2: the default-branch refusal names the literal remediation command (git checkout -b feat/<slug>)"
else
  bad "RB2: default-branch refusal is missing the literal git checkout -b feat/<slug> remediation command"
fi

RB3_N=$(grep -c 'refuse to dispatch' "$STEP5" 2>/dev/null || true)
case "$RB3_N" in ''|*[!0-9]*) RB3_N=0 ;; esac
if [ "$RB3_N" -ge 2 ]; then
  ok "RB3: 'refuse to dispatch' appears >= 2 times (one per failing assertion), found $RB3_N"
else
  bad "RB3: expected >= 2 occurrences of 'refuse to dispatch', found $RB3_N"
fi

# ==============================================================================================
# RC. The default-branch check resolves the remote default rather than hardcoding main. Static
# prose anchors plus EXECUTED assertions against real throwaway git repos (mktemp -d).
# ==============================================================================================
if grep -qF 'git symbolic-ref refs/remotes/origin/HEAD' "$STEP5"; then
  ok "RC1: Step 5 resolves the default branch via git symbolic-ref refs/remotes/origin/HEAD"
else
  bad "RC1: Step 5 does not resolve the default branch via git symbolic-ref refs/remotes/origin/HEAD"
fi

if grep -qF 'git remote show origin' "$STEP5"; then
  ok "RC2: Step 5 states a fallback via git remote show origin"
else
  bad "RC2: Step 5 is missing the git remote show origin fallback"
fi

if grep -qF 'fall back to the literal `main`' "$STEP5" && grep -qF 'never a silent hardcode' "$STEP5"; then
  ok "RC3: Step 5 documents the last-resort main fallback explicitly, never silently"
else
  bad "RC3: Step 5 does not explicitly document the main fallback as non-silent"
fi

# RC4/RC5: EXECUTED against a real throwaway repo whose default branch is NOT main, proving the
# documented resolution command actually works rather than merely being present as prose.
mkdir -p "$TMP/rc-bare"
git init -q --bare "$TMP/rc-bare" >/dev/null 2>&1
mkdir -p "$TMP/rc-src"
git -C "$TMP/rc-src" init -q >/dev/null 2>&1
git -C "$TMP/rc-src" symbolic-ref HEAD refs/heads/trunk >/dev/null 2>&1
git -C "$TMP/rc-src" config user.email "t@example.com" >/dev/null 2>&1
git -C "$TMP/rc-src" config user.name "t" >/dev/null 2>&1
: > "$TMP/rc-src/f.txt"
git -C "$TMP/rc-src" add f.txt >/dev/null 2>&1
git -C "$TMP/rc-src" commit -q -m init >/dev/null 2>&1
git -C "$TMP/rc-src" remote add origin "$TMP/rc-bare" >/dev/null 2>&1
git -C "$TMP/rc-src" push -q origin trunk >/dev/null 2>&1
git -C "$TMP/rc-bare" symbolic-ref HEAD refs/heads/trunk >/dev/null 2>&1
git clone -q "$TMP/rc-bare" "$TMP/rc-clone" >/dev/null 2>&1

RC4_RESOLVED=$(git -C "$TMP/rc-clone" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ "$RC4_RESOLVED" = "trunk" ]; then
  ok "RC4: git symbolic-ref refs/remotes/origin/HEAD resolves a real repo's non-main default (trunk), not a hardcoded main"
else
  bad "RC4: expected the primary resolution command to resolve 'trunk', got '$RC4_RESOLVED'"
fi

rm -f "$TMP/rc-clone/.git/refs/remotes/origin/HEAD"
RC5_PRIMARY=$(git -C "$TMP/rc-clone" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
RC5_FALLBACK=$(git -C "$TMP/rc-clone" remote show origin 2>/dev/null | sed -n 's/^ *HEAD branch: //p')
if [ -z "$RC5_PRIMARY" ] && [ "$RC5_FALLBACK" = "trunk" ]; then
  ok "RC5: with the local origin/HEAD ref removed, the fallback (git remote show origin) still resolves 'trunk'"
else
  bad "RC5: expected empty primary + fallback 'trunk', got primary='$RC5_PRIMARY' fallback='$RC5_FALLBACK'"
fi

# ==============================================================================================
# RD. recovery_baseline_sha is written once and is conditional-if-present in manifest-validate.sh.
# ==============================================================================================
if grep -qF 'recovery_baseline_sha: null' "$INIT"; then
  ok "RD1: manifest-init.sh writes recovery_baseline_sha: null"
else
  bad "RD1: manifest-init.sh does not write recovery_baseline_sha: null"
fi

mkdir -p "$TMP/proj"
bash "$INIT" "rp-topic" "RP Topic" "$TMP/proj" >/dev/null 2>&1
M1=$(ls "$TMP/proj/docs/manifests/"*-rp-topic.manifest.yml 2>/dev/null | head -1)
if [ -n "$M1" ] && bash "$VALIDATE" "$M1" >/dev/null 2>&1; then
  ok "RD2: a freshly generated manifest (recovery_baseline_sha: null) validates"
else
  bad "RD2: fresh manifest with recovery_baseline_sha: null failed validation (or manifest-init produced none)"
fi

if [ -n "$M1" ]; then
  sed 's/^recovery_baseline_sha: null$/recovery_baseline_sha: "abc1234"/' "$M1" > "$TMP/m-valid.yml"
  if bash "$VALIDATE" "$TMP/m-valid.yml" >/dev/null 2>&1; then
    ok "RD3: a manifest with a valid quoted hex sha validates"
  else
    bad "RD3: a valid quoted hex sha was rejected"
  fi

  sed 's/^recovery_baseline_sha: null$/recovery_baseline_sha: banana/' "$M1" > "$TMP/m-invalid.yml"
  OUT_RD4=$(bash "$VALIDATE" "$TMP/m-invalid.yml" 2>&1); RC_RD4=$?
  if [ "$RC_RD4" -ne 0 ] && printf '%s' "$OUT_RD4" | grep -q 'recovery_baseline_sha'; then
    ok "RD4: an invalid recovery_baseline_sha value is rejected, message names the field"
  else
    bad "RD4: invalid recovery_baseline_sha value was accepted or message unclear (rc=$RC_RD4)"
  fi

  grep -v '^recovery_baseline_sha:' "$M1" > "$TMP/m-absent.yml"
  if bash "$VALIDATE" "$TMP/m-absent.yml" >/dev/null 2>&1; then
    ok "RD5: a manifest with the field entirely absent still validates (pre-ADR-0050 retrocompat)"
  else
    bad "RD5: absent field rejected — the field is no longer additive"
  fi
else
  bad "RD3: skipped, no fresh manifest available"
  bad "RD4: skipped, no fresh manifest available"
  bad "RD5: skipped, no fresh manifest available"
fi

if grep -qF 'written once, at pre-flight, and never rewritten by a later step' "$STEP5"; then
  ok "RD6: Step 5 states the write-once rule for recovery_baseline_sha"
else
  bad "RD6: Step 5 is missing the write-once statement for recovery_baseline_sha"
fi

# ==============================================================================================
# RE. The ADR-0050 §D4 sequencing note is present and names both conditions, so a future reader
# cannot collapse them silently. THIS IS THE SECTION THAT MUST FAIL CI ON SILENT RECONCILIATION.
# ==============================================================================================
if grep -qF 'ADR-0050 §D4' "$STEP5"; then
  ok "RE1: Step 5 cites ADR-0050 §D4"
else
  bad "RE1: Step 5 does not cite ADR-0050 §D4"
fi

if grep -qF "ADR-0049 §D2's dirty-tree condition" "$STEP5"; then
  ok "RE2: Step 5 names ADR-0049 §D2's dirty-tree condition explicitly, next to the pre-flight block"
else
  bad "RE2: Step 5 does not name ADR-0049 §D2's dirty-tree condition next to the pre-flight block"
fi

if grep -qF 'sequential, not contradictory' "$STEP5"; then
  ok "RE3: Step 5 states the two conditions are sequential, not contradictory"
else
  bad "RE3: Step 5 is missing the 'sequential, not contradictory' framing"
fi

if grep -qF 'the tester stage ADR-0049 introduced' "$STEP5"; then
  ok "RE4: Step 5 names the tester stage ADR-0049 introduced, tying the pre-flight to what runs after it"
else
  bad "RE4: Step 5 does not name the tester stage ADR-0049 introduced"
fi

WORKTREE_LINE=$(grep -n '^\*\*Pre-dispatch: worktree isolation check' "$CC" 2>/dev/null | head -1 | cut -d: -f1)
if [ -n "$PREFLIGHT_LINE" ] && [ -n "$WORKTREE_LINE" ] && [ "$PREFLIGHT_LINE" -lt "$WORKTREE_LINE" ]; then
  ok "RE5: the pre-flight block (and its sequencing note) sits before the worktree isolation / dirty-tree check block"
else
  bad "RE5: pre-flight block is not positioned before the worktree isolation / dirty-tree check block"
fi

# ==============================================================================================
# RF. The autopilot path refuses identically (no leniency branch), in both c2c Step 5 and
# autopilot-build's own restatement of Step 5's entry conditions (ADR-0050 §D6).
# ==============================================================================================
if grep -qi 'autopilot' "$STEP5" && grep -qF 'no leniency branch' "$STEP5" && grep -qF 'ADR-0050 §D6' "$STEP5"; then
  ok "RF1: c2c Step 5 states the autopilot no-leniency policy, citing ADR-0050 §D6"
else
  bad "RF1: c2c Step 5 is missing the autopilot no-leniency / ADR-0050 §D6 statement"
fi

AB_STEP5="$TMP/ab_step5.txt"
awk '/^#### Step 5 —/{f=1} /^#### Step 6 —/{f=0} f' "$AB" >"$AB_STEP5" 2>/dev/null

RF2_NEEDLE="Recovery-readiness pre-flight (ADR-0050)"
if grep -qF "$RF2_NEEDLE" "$AB_STEP5"; then
  RF2_N=$(grep -c '^#### Recovery-readiness pre-flight (ADR-0050, before any dispatch)$' "$CC" 2>/dev/null || true)
  case "$RF2_N" in ''|*[!0-9]*) RF2_N=0 ;; esac
  if [ "$RF2_N" = "1" ]; then
    ok "RF2: autopilot-build names the c2c pre-flight block by heading, resolving to exactly one heading in concept-to-code"
  else
    bad "RF2: autopilot-build names the heading but it occurs $RF2_N times in concept-to-code (expected 1)"
  fi
else
  bad "RF2: autopilot-build/SKILL.md Step 5 does not name the c2c pre-flight heading '$RF2_NEEDLE'"
fi

if grep -qF 'no leniency branch' "$AB_STEP5" && grep -qF 'recorded in the report' "$AB_STEP5"; then
  ok "RF3: autopilot-build Step 5 states no-leniency and records-in-report (not prompted), matching §D6"
else
  bad "RF3: autopilot-build Step 5 is missing the no-leniency / recorded-in-report statement"
fi

# ==============================================================================================
# RG. Registration in both CI registries (ADR-0043's lesson: a check reporting nothing must be
# distinguishable from a check finding nothing — applied here to the CI wiring itself).
# ==============================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
CIYML="$REPO/.github/workflows/ci.yml"
SYNCSH="$STAGING/sync-to-claude.sh"

DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]recovery-preflight[[:space:];]'; then
  ok "RG1: docs-ci.yml's shell-tests loop list runs recovery-preflight"
else
  bad "RG1: recovery-preflight is not in docs-ci.yml's explicit harness list — append it after test-write-scope"
fi

if printf '%s' "$DOCSCI_LOOP" | grep -qE 'test-write-scope recovery-preflight[[:space:];]'; then
  ok "RG2: recovery-preflight is registered immediately after test-write-scope, per the plan's instruction"
else
  bad "RG2: recovery-preflight is not positioned immediately after test-write-scope in docs-ci.yml's list"
fi

if grep -qF 'staging/plugin/scripts/tests/*.test.sh' "$CIYML" 2>/dev/null; then
  ok "RG3: ci.yml still runs the automatic glob over staging/plugin/scripts/tests/*.test.sh (forward guard — no manual edit needed there)"
else
  bad "RG3: ci.yml no longer uses the automatic *.test.sh glob"
fi

awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" >"$TMP/pairs" 2>/dev/null
if grep -q 'recovery-preflight' "$TMP/pairs" 2>/dev/null; then
  bad "RG4: PAIRS gained an entry for this harness — test harnesses do not deploy"
else
  ok "RG4: no PAIRS entry for recovery-preflight.test.sh (harnesses do not deploy)"
fi

# ==================================================================================================
# RH. Issue #173 / ADR-0071 — the pre-flight had no producer.
#
# 5.0.1 and 5.0.2 assert a clean tree on a feature branch. Nothing in the chain created either:
# `git checkout -b` appeared in the file exactly once, inside 5.0.2's own error message. So EVERY
# first run failed the pre-flight — structurally, not situationally — and the remediation it printed
# would have stashed SPEC.md, the ADR and the plan, i.e. the coder's own inputs.
# ==================================================================================================
COMMIT_SKILL="$STAGING/plugin/skills/commit/SKILL.md"

# --- the producer exists, is named once, and is invoked by every proceeding path ---
RH1_N=$(grep -c '^#### Gate 4.0 — Commit the planning artifacts' "$CC" 2>/dev/null || true)
[ "$RH1_N" = "1" ] \
  && ok "RH1: Gate 4.0 is defined exactly once in concept-to-code/SKILL.md" \
  || bad "RH1: expected exactly one Gate 4.0 definition, found $RH1_N"

RH2_N=$(grep -c 'Run \*\*Gate 4.0\*\*' "$CC" 2>/dev/null || true)
[ "$RH2_N" -ge 3 ] \
  && ok "RH2: all three proceeding paths reference Gate 4.0 ($RH2_N references)" \
  || bad "RH2: only $RH2_N path(s) reference Gate 4.0 — autopilot bypass, 'Implement now' and 'Confirmed' all need it"

# The abort path must NOT commit. Asserted as absence within the abort block, which is the one
# place a well-meaning edit would add it "for consistency".
RH3_BLOCK=$(awk '/^\*\*After the user clicks "Abort chain":\*\*/{f=1} f{print} f&&/^STOP/{exit}' "$CC")
printf '%s\n' "$RH3_BLOCK" | grep -q 'Gate 4.0' \
  && bad "RH3: the Abort path references Gate 4.0 — an aborted chain must not leave a commit behind" \
  || ok "RH3 (forward guard, green before and after): the Abort path does not run Gate 4.0"

# --- the producer delegates, it does not hand-roll git ---
RH4_BLOCK=$(awk '/^#### Gate 4.0 — Commit the planning artifacts/{f=1; next} f&&/^\*\*\[Autopilot bypass/{exit} f{print}' "$CC")
printf '%s\n' "$RH4_BLOCK" | grep -q 'commit' \
  && ok "RH4: Gate 4.0 delegates to the commit skill" \
  || bad "RH4: Gate 4.0 does not mention the commit skill"
printf '%s\n' "$RH4_BLOCK" | grep -qE 'git (checkout -b|commit|add)' \
  && bad "RH4b: Gate 4.0 hand-rolls git — STAGING counts, not just committing: 'git add' here would put the file-scope decision in two places (commit Step 1 and the caller), which is what ADR-0071 §D2 exists to prevent. #234's fix belongs on the commit side, never here." \
  || ok "RH4b (forward guard, green before and after — the block did not exist to hand-roll git in): Gate 4.0 runs no raw git commands, staging included"
printf '%s\n' "$RH4_BLOCK" | grep -q -- '--no-pr' \
  && ok "RH5: Gate 4.0 passes --no-pr (nothing to publish at the session boundary)" \
  || bad "RH5: Gate 4.0 does not pass --no-pr — every chain run would be asked to open a PR"
printf '%s\n' "$RH4_BLOCK" | grep -q -- '--autopilot' \
  && ok "RH6: Gate 4.0 names the unattended form (--autopilot)" \
  || bad "RH6: Gate 4.0 does not name --autopilot — the unattended path would stall on the commit gate"

# --- the flag exists in the skill it is passed to, and suppresses only publication ---
if [ -f "$COMMIT_SKILL" ]; then
  grep -q -- '`--no-pr`' "$COMMIT_SKILL" \
    && ok "RH7: commit/SKILL.md documents --no-pr" \
    || bad "RH7: commit/SKILL.md has no --no-pr — Gate 4.0 passes a flag the skill does not know"
  # The distinction that matters: --no-pr must not become a second --autopilot.
  grep -q 'Step 4 HITL gate is \*\*unaffected\*\*' "$COMMIT_SKILL" \
    && ok "RH8: --no-pr is documented as leaving the Step 4 approval gate intact" \
    || bad "RH8: commit/SKILL.md does not state that --no-pr leaves the HITL gate intact — it must not become a second --autopilot"
  grep -q 'Skipped entirely when `--no-pr` is present' "$COMMIT_SKILL" \
    && ok "RH9: Step 6 states its own --no-pr skip condition at the step, not only in Arguments" \
    || bad "RH9: Step 6 does not state the --no-pr skip — a reader following the steps would run it anyway"
else
  bad "RH7: $COMMIT_SKILL not found — RH7..RH9 skipped"
fi

# --- 5.0.1's remediation no longer leads with stash on the chain-artifact case ---
RH10_BLOCK=$(awk '/^\*\*Step 5.0.1 — Working tree clean/{f=1; next} f&&/^\*\*Step 5.0.2/{exit} f{print}' "$CC")
printf '%s\n' "$RH10_BLOCK" | grep -q 'Never advise `git stash` here' \
  && ok "RH10: 5.0.1 forbids the stash advice on the chain-artifact case" \
  || bad "RH10: 5.0.1 does not forbid stashing the chain's own artifacts — the advice that would delete the coder's inputs"
printf '%s\n' "$RH10_BLOCK" | grep -q 'unrelated' \
  && ok "RH11: 5.0.1 still prescribes stash for the unrelated-dirty-tree case (ADR-0050 §D2 preserved)" \
  || bad "RH11: 5.0.1 lost the deliberate-dirty-resume case — the fix must not delete the behaviour it narrows"

# --- autopilot-build's entry contract agrees with the pre-flight it hands off to ---
grep -q 'committed, on a feature branch' "$AB" \
  && ok "RH12: autopilot-build's prerequisites require the artifacts to be committed on a feature branch" \
  || bad "RH12: autopilot-build still documents only 'exist on disk', contradicting the pre-flight it hands off to"


# ==================================================================================================
# RI. --include: the door Gate 4.0 needs, and the one it must not use (issue #234).
#
# ADR-0071 §D2's Clarification settles which side the fix belongs on: `RH4b` above forbids raw
# `git add` in the Gate 4.0 block, and a caller that stages first would put the file-scope decision
# in two places. So the mechanism is a `commit` flag, and these assertions pin both halves.
#
# Prose matched against a whitespace-FLATTENED copy — a prose assertion must not depend on where
# markdown wraps (ADR-0073, and ADR-0088's own first run reproducing it).
# ==================================================================================================
COMMITMD="$STAGING/plugin/skills/commit/SKILL.md"

ri_flat() {
  _n=$(tr '\n' ' ' <"$2" 2>/dev/null | tr -s ' ' | grep -oF -- "$1" 2>/dev/null | wc -l | tr -d ' ')
  [ -n "${_n:-}" ] || _n=0
  printf '%s' "$_n"
}

# Exactly 2: the synopsis line AND the description that follows it. `>= 1` was the first draft and
# a planted defect walked straight through it — removing one of the two left the other satisfying
# the check, so "documented" and "mentioned once" were indistinguishable.
_ri1=$(ri_flat '--include <path>[,<path>...]' "$COMMITMD")
if [ "$_ri1" -eq 2 ]; then
  ok "RI1: commit/SKILL.md carries --include in both the synopsis and its own description"
else
  bad "RI1: expected --include in the synopsis AND its description (2 occurrences), found $_ri1 — a flag named once is not documented (#234)"
fi

# RI2 — the ordering is the security property, not a style point: resolving --include before the
# secrets check would open the door the filename rule exists to keep shut.
if [ "$(ri_flat 'after the secrets check below, not before it' "$COMMITMD")" -ge 1 ]; then
  ok "RI2: commit/SKILL.md states that --include resolves AFTER the secrets check"
else
  bad "RI2: commit/SKILL.md does not pin --include's ordering against the secrets check (#234)"
fi

# RI3 — a missing path must abort. Committing the rest yields a half-done Gate 4.0 that looks whole.
if [ "$(ri_flat 'stop and report it, do not commit' "$COMMITMD")" -ge 1 ]; then
  ok "RI3: a non-existent --include path aborts the commit rather than being skipped"
else
  bad "RI3: commit/SKILL.md does not abort on a missing --include path (#234)"
fi

# RI4 — Gate 4.0 must actually pass it. A flag no caller passes is #238's shape one skill over.
RI_BLOCK=$(awk '/^#### Gate 4.0 — Commit the planning artifacts/{f=1; next} f&&/^\*\*\[Autopilot bypass/{exit} f{print}' "$CC")
printf '%s\n' "$RI_BLOCK" > "$TMP/ri_block.txt"
# The needle is the INVOCATION's argument form, not the bare word: this block also explains what
# --include is for, so a needle of '--include' counted the explanation and passed with the
# invocation deleted (rule 12, caught by planting rather than by reading).
if [ "$(ri_flat '--include <spec>,<manifest.artifacts.adr>,<manifest.artifacts.plan>,<manifest-path>' "$TMP/ri_block.txt")" -ge 1 ]; then
  ok "RI4: Gate 4.0 passes --include with the four artifact paths, so the flag has a caller"
else
  bad "RI4: Gate 4.0 does not pass --include with its artifact paths — the flag exists and nothing uses it (#234)"
fi

# RI5 — RH4b still holds with the fix in place. The point of #234's design is that the door is on
# the commit side; if this block ever grows a `git add`, the design was abandoned rather than fixed.
if printf '%s\n' "$RI_BLOCK" | grep -qE 'git (checkout -b|commit|add)'; then
  bad "RI5: Gate 4.0 gained a raw git command while implementing #234 — the fix belongs on the commit side (ADR-0071 §D2 Clarification)"
else
  ok "RI5 (forward guard, green before and after): #234's fix left Gate 4.0 free of raw git"
fi

# RI6 — CLAUDE.md is deliberately absent from the --include list: it is tracked-modified, so
# `git add -u` covers it. Asserted because a list that grows unexamined becomes a second scope rule.
if [ "$(ri_flat 'CLAUDE.md` is deliberately absent from the list' "$TMP/ri_block.txt")" -ge 1 ]; then
  ok "RI6: Gate 4.0 records why CLAUDE.md is NOT in the --include list"
else
  bad "RI6: Gate 4.0 does not say why CLAUDE.md is excluded from --include — the list will drift (#234)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
