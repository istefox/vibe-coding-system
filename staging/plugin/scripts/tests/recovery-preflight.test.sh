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
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# RJ13 and RJ13b share a mutation SITE but not a mutation: RJ13's reintroduces the string-prefix
# strip (#344's actual defect), RJ13b's merely stops asking git, which exercises its third branch.
# plant: RJ13 | plugin/skills/concept-to-code/SKILL.md | printf '%s%s' "$(git -C "$_d" rev-parse --show-prefix 2>/dev/null)" "$(basename "$1")" | _p=$(cd "$_d" && pwd -P)/$(basename "$1"); case "$_p" in "$_top"/*) printf '%s' "${_p#$_top/}" ;; *) printf '%s' "$1" ;; esac
# plant: RJ13b | plugin/skills/concept-to-code/SKILL.md | rev-parse --show-prefix | rev-parse --show-cdup
# plant: RJ14 | plugin/skills/concept-to-code/SKILL.md | { [ -n "$_t2" ] && [ "$_t2" -ef "$_top" ]; } || { printf '%s' "$1"; return 0; } | :
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

# Floor raised 3 -> 4 by issue #237 (ADR-0097), which added the attended in-session branch. The
# floor must track the number of proceeding paths: left at 3 it would report "all three" while four
# exist, and would tolerate one of them silently losing its reference.
RH2_N=$(grep -c 'Run \*\*Gate 4.0\*\*' "$CC" 2>/dev/null || true)
[ "$RH2_N" -ge 4 ] \
  && ok "RH2: all four proceeding paths reference Gate 4.0 ($RH2_N references)" \
  || bad "RH2: only $RH2_N path(s) reference Gate 4.0 — autopilot bypass, both 'Implement now' branches and 'Confirmed' all need it"

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

# ==================================================================================================
# RJ. Issue #239 — Step 5.0.1 could never pass, because the chain dirties the manifest AFTER
# Gate 4.0 commits it, on both Gate 4 branches.
#
# `manifest-set-flag.sh <m> autopilot true` and `manifest-transition.sh <m>
# ready_for_implementation` both run between Gate 4.0's commit and this assertion; on the
# fresh-session branch Form B resume step 3 writes `session_boundary.resumed_at` unconditionally,
# so NO ordering avoids it. Then 5.0.3 writes `recovery_baseline_sha` into the same file on
# purpose, three assertions later. The pre-flight asserted a clean tree while the state machine
# wrote the manifest at every state change: incompatible requirements on one file.
#
# THE FENCE IS EXECUTED, NOT READ (rule 11). 5.0.1's classification used to be prose — "decide by
# intersecting `git status --porcelain` with … the manifest itself" — so there was nothing to run
# and nothing to declare. It is now a `fence-contract:` block, extracted here by its own marker
# (ADR-0083 §D3: a heading anchor rots, a marker moves with the fence).
#
# RJ1 IS THE RED EVIDENCE AND IT IS DERIVED, NOT HAND-WRITTEN. The pre-#239 rule is reconstructed
# from the shipped fence by sed — dropping the exclusion and putting the manifest back in the
# chain-artifact set — so it cannot drift into testing some other script. On the manifest-only
# fixture it must still produce the false `PREFLIGHT_CHAIN`, which is the exact message the
# Phase 7.1 shakedown saw with a clean tree and a successful Gate 4.0 behind it.
# ==================================================================================================
RJ_ID='c2c-step5-preflight-dirty-classify'
rj_extract() {
  awk '
    index($0, "fence-contract: c2c-step5-preflight-dirty-classify -->") { grab=1; next }
    grab && /^```bash/ { infence=1; next }
    grab && infence && /^```/ { exit }
    grab && infence { print }
  ' "$CC"
}
RJ_FENCE="$TMP/rj_fence.sh"
rj_extract >"$RJ_FENCE"

# RJ0 — an empty extraction is a FAILURE, never a quietly passing skip. Deleting the marker must
# break this section loudly; that is the whole reason the marker is the anchor.
if [ -s "$RJ_FENCE" ]; then
  ok "RJ0: the 5.0.1 classifier fence is extractable by its fence-contract marker"
else
  bad "RJ0: no fence-contract: $RJ_ID block in $CC — every RJ assertion below is meaningless"
fi

if bash -n "$RJ_FENCE" 2>/dev/null; then
  ok "RJ0b: the extracted 5.0.1 fence parses as bash"
else
  bad "RJ0b: the extracted 5.0.1 fence does not parse — a declared contract must at minimum parse (ADR-0083 F7)"
fi

# The pre-#239 variant, derived from the shipped fence.
RJ_PREFIX="$TMP/rj_fence_prefix.sh"
sed -e 's#^DIRTY=.*#DIRTY=$(git status --porcelain | sed "s/^...//")#' \
    -e 's#"\$SPEC_REL"|"\$ADR_REL"|"\$PLAN_REL"|CLAUDE.md)#"$SPEC_REL"|"$ADR_REL"|"$PLAN_REL"|"$(rel "$MANIFEST")"|CLAUDE.md)#' \
    "$RJ_FENCE" >"$RJ_PREFIX"

# rj_repo <dir> — a real throwaway git repo carrying the four chain artifacts plus one unrelated
# tracked file. Real, because the classifier reads `git status --porcelain` and nothing else.
rj_repo() {
  mkdir -p "$1/docs/manifests" "$1/docs/architecture" "$1/docs/superpowers/plans"
  ( cd "$1" || exit 1
    git init -q . >/dev/null 2>&1
    git config user.email t@example.invalid; git config user.name t
    printf 'current_step: "x"\n' >docs/manifests/m.yml
    printf 'spec\n' >SPEC.md; printf 'adr\n' >docs/architecture/A.md
    printf 'plan\n' >docs/superpowers/plans/p.md
    printf 'other\n' >unrelated.txt; printf 'cm\n' >CLAUDE.md
    git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1 )
}
# rj_run <fence> <repo> — execute with the four free variables bound, print "<rc> <stdout>".
rj_run() {
  _o=$( cd "$2" && MANIFEST="$2/docs/manifests/m.yml" SPEC="$2/SPEC.md" \
        ADR="$2/docs/architecture/A.md" PLAN="$2/docs/superpowers/plans/p.md" \
        bash "$1" 2>&1 ); _r=$?
  printf '%s %s' "$_r" "$_o"
}

RJ_REPO="$TMP/rj"; rj_repo "$RJ_REPO"

# RJ1 — RED EVIDENCE. Only the manifest is dirty: issue #239's exact observed state.
printf 'current_step: "y"\n' >>"$RJ_REPO/docs/manifests/m.yml"
RJ1_OUT=$(rj_run "$RJ_PREFIX" "$RJ_REPO")
case "$RJ1_OUT" in
  "1 PREFLIGHT_CHAIN"*) ok "RJ1 (red evidence): the pre-#239 rule refuses on a manifest-only dirty tree, naming the chain-artifact branch" ;;
  *) bad "RJ1: the pre-#239 rule did NOT reproduce the defect (got: $RJ1_OUT) — section RJ is not pinning the bug it claims to" ;;
esac

# RJ2 — THE FIX, same fixture, same moment in the chain.
RJ2_OUT=$(rj_run "$RJ_FENCE" "$RJ_REPO")
case "$RJ2_OUT" in
  "0 PREFLIGHT_CLEAN"*) ok "RJ2: a manifest-only dirty tree is CLEAN — Step 5.0.1 can now pass on both Gate 4 branches (#239)" ;;
  *) bad "RJ2: manifest-only dirty tree did not classify clean (got: $RJ2_OUT) — #239 is not fixed" ;;
esac
( cd "$RJ_REPO" && git checkout -q -- . )

# RJ3 — the exemption did NOT widen. Each of the three real artifacts still refuses, individually,
# so a future "simplification" that exempts the whole planning set fails here rather than in a run.
RJ3_BAD=""
for _a in SPEC.md docs/architecture/A.md docs/superpowers/plans/p.md CLAUDE.md; do
  printf 'x\n' >>"$RJ_REPO/$_a"
  _o=$(rj_run "$RJ_FENCE" "$RJ_REPO")
  case "$_o" in "1 PREFLIGHT_CHAIN"*) : ;; *) RJ3_BAD="$RJ3_BAD $_a(got:$_o)" ;; esac
  ( cd "$RJ_REPO" && git checkout -q -- . )
done
if [ -z "$RJ3_BAD" ]; then
  ok "RJ3: SPEC, ADR, plan and CLAUDE.md each still refuse individually — the exemption is the manifest and only the manifest"
else
  bad "RJ3: the manifest exemption leaked to other chain artifacts:$RJ3_BAD"
fi

# RJ4 — the unrelated-dirty branch ADR-0050 §D2 negative consequence 2 describes still exists.
printf 'x\n' >>"$RJ_REPO/unrelated.txt"
RJ4_OUT=$(rj_run "$RJ_FENCE" "$RJ_REPO")
case "$RJ4_OUT" in
  "1 PREFLIGHT_OTHER"*) ok "RJ4: an unrelated dirty file still refuses, on the OTHER branch" ;;
  *) bad "RJ4: unrelated dirty file misclassified (got: $RJ4_OUT)" ;;
esac
( cd "$RJ_REPO" && git checkout -q -- . )

# RJ5 — the BOTH branch, whose remediation ordering (commit, then stash) is the one ADR-0071 §D3
# fixed. A classifier that cannot reach it leaves that remediation unreachable prose.
printf 'x\n' >>"$RJ_REPO/SPEC.md"; printf 'x\n' >>"$RJ_REPO/unrelated.txt"
RJ5_OUT=$(rj_run "$RJ_FENCE" "$RJ_REPO")
case "$RJ5_OUT" in
  "1 PREFLIGHT_BOTH"*) ok "RJ5: a mixed dirty tree reaches the BOTH branch, so ADR-0071 §D3's ordering advice is reachable" ;;
  *) bad "RJ5: mixed dirty tree did not reach the BOTH branch (got: $RJ5_OUT)" ;;
esac
( cd "$RJ_REPO" && git checkout -q -- . )

# RJ6 — the manifest must not COLOUR the classification either: dirty manifest plus one unrelated
# file is OTHER, not BOTH. Otherwise every run would take the commit-then-stash advice for free.
printf 'x\n' >>"$RJ_REPO/docs/manifests/m.yml"; printf 'x\n' >>"$RJ_REPO/unrelated.txt"
RJ6_OUT=$(rj_run "$RJ_FENCE" "$RJ_REPO")
case "$RJ6_OUT" in
  "1 PREFLIGHT_OTHER"*) ok "RJ6: a dirty manifest does not colour the classification — manifest+unrelated is OTHER, not BOTH" ;;
  *) bad "RJ6: dirty manifest leaked into the classification (got: $RJ6_OUT)" ;;
esac
( cd "$RJ_REPO" && git checkout -q -- . )

# RJ7/RJ8 — "did not run" must be distinguishable from "found nothing" (ADR-0043's direction
# lesson, applied to the classifier itself). Exit 3, not 0 and not 1.
RJ7_OUT=$( cd "$TMP" && MANIFEST=x bash "$RJ_FENCE" 2>&1; printf ' rc=%s' "$?" )
case "$RJ7_OUT" in
  "PREFLIGHT_NOREPO"*rc=3) ok "RJ7: outside a git repo the classifier exits 3 and says so — not a clean tree" ;;
  *) bad "RJ7: no-repo case did not exit 3 with PREFLIGHT_NOREPO (got: $RJ7_OUT)" ;;
esac
RJ8_OUT=$( cd "$RJ_REPO" && unset MANIFEST; bash "$RJ_FENCE" 2>&1; printf ' rc=%s' "$?" )
case "$RJ8_OUT" in
  "PREFLIGHT_NOMANIFEST"*rc=3) ok "RJ8: an unbound MANIFEST exits 3 — the exemption cannot silently apply to nothing" ;;
  *) bad "RJ8: unbound MANIFEST did not exit 3 with PREFLIGHT_NOMANIFEST (got: $RJ8_OUT)" ;;
esac

# RJ9 — BOTH SIDES SYMLINK-RESOLVED. The first draft compared `git rev-parse --show-toplevel`
# (resolved) against the caller's path (not), so `rel()` shortened nothing and EVERY artifact
# classified as OTHER — including the manifest, which meant the exemption silently did nothing.
# Found by running the fence, not by reading it. Live on macOS: /tmp is a symlink to /private/tmp,
# and this machine reaches its own checkout through two differently-cased paths.
RJ9_LINK="$TMP/rj-link"
ln -sf "$RJ_REPO" "$RJ9_LINK" 2>/dev/null
printf 'current_step: "z"\n' >>"$RJ_REPO/docs/manifests/m.yml"
RJ9_OUT=$(rj_run "$RJ_FENCE" "$RJ9_LINK")
case "$RJ9_OUT" in
  "0 PREFLIGHT_CLEAN"*) ok "RJ9: the exemption survives a symlinked project path — rel() resolves rather than string-matches" ;;
  *) bad "RJ9: symlinked path broke the exemption (got: $RJ9_OUT) — rel() is comparing an unresolved path again"
esac
( cd "$RJ_REPO" && git checkout -q -- . )

# RJ13/RJ13b — THE CASE HALF (issue #344). RJ9's own comment above claims this machine "reaches its
# own checkout through two differently-cased paths", and until #344 no assertion exercised that:
# the symlink case was covered, the case case was asserted in prose only. `pwd -P` resolves
# symlinks and does NOT normalise case, so #239's fix left the exemption inert on every run whose
# CWD casing differed from git's recorded casing — the exact state the 2026-08-02 nightly hit.
#
# RJ13 is BEHAVIOURAL and can only run on a case-insensitive filesystem (APFS, and this bug's whole
# habitat). RJ13b is the always-runnable half, per ADR-0026's precedent for a platform-specific
# precondition: it pins the MECHANISM out of the source, so a CI run on ext4 still fails if the
# string-prefix form comes back. Neither alone is enough — read them as a pair.
RJ13_PROBE="$TMP/CaseProbe"; mkdir -p "$RJ13_PROBE"
if [ -d "$TMP/caseprobe" ]; then
  RJ13_CI=yes
else
  RJ13_CI=no
fi
if [ "$RJ13_CI" = yes ]; then
  RJ13_REPO="$TMP/RjCase"; rj_repo "$RJ13_REPO"
  printf 'current_step: "z"\n' >>"$RJ13_REPO/docs/manifests/m.yml"
  # Reached through a differently-cased spelling of the same directory — not a copy, not a symlink.
  RJ13_OUT=$(rj_run "$RJ_FENCE" "$TMP/rjcase")
  case "$RJ13_OUT" in
    "0 PREFLIGHT_CLEAN"*) ok "RJ13: the exemption survives a differently-cased CWD — rel() takes its prefix from git, not from a string compare (#344)" ;;
    *) bad "RJ13: a differently-cased CWD broke the manifest exemption (got: $RJ13_OUT) — #344 is back, and it reports PREFLIGHT_OTHER naming the file it is meant to exempt" ;;
  esac
else
  ok "RJ13: NOT EXERCISED — this filesystem is case-sensitive, so the #344 precondition cannot be built here. RJ13b carries the check on this platform."
fi

# RJ13b — the mechanism, asserted out of the fence source so the check survives a case-sensitive
# filesystem. The banned construct is the string-prefix strip, whichever variable it strips against.
if grep -qE '[$][{]_p#[$](ROOT|_top)/[}]' "$RJ_FENCE"; then
  bad "RJ13b: the fence strips a string prefix to derive the repo-relative path again — that form cannot normalise case, which is #344 (and #239 before it, for symlinks)"
elif grep -q 'rev-parse --show-prefix' "$RJ_FENCE"; then
  ok "RJ13b: rel() derives the repo-relative path from git, so there is no normalisation left for it to miss"
else
  bad "RJ13b: rel() no longer asks git for the prefix and does not use the banned string strip either — the mechanism changed to something unreviewed; re-read #344 before accepting it"
fi

# RJ14 — the -ef guard, which is what stops a foreign repository's prefix being applied to a path
# that merely LOOKS like it belongs. Without it, an artifact inside another checkout gets that
# checkout's prefix and can be silently exempted. Device+inode identity, not a string compare —
# reintroducing a string compare here is how #344 would come back through the side door.
# The fixture has to make the guard MATTER: the local repo is dirty at docs/manifests/m.yml, and
# MANIFEST points at the foreign repo's file of the SAME repo-relative shape. Drop the -ef guard
# and rel() hands back `docs/manifests/m.yml` from the foreign checkout's prefix, which then
# filters the LOCAL dirty entry and reports CLEAN. A clean local tree would report CLEAN either
# way — the first draft of this assertion did exactly that and pinned nothing.
RJ14_FOREIGN="$TMP/foreign"; rj_repo "$RJ14_FOREIGN"
printf 'current_step: "q"\n' >>"$RJ_REPO/docs/manifests/m.yml"
RJ14_OUT=$( cd "$RJ_REPO" && MANIFEST="$RJ14_FOREIGN/docs/manifests/m.yml" SPEC="$RJ_REPO/SPEC.md" \
            ADR="$RJ_REPO/docs/architecture/A.md" PLAN="$RJ_REPO/docs/superpowers/plans/p.md" \
            bash "$RJ_FENCE" 2>&1; printf ' rc=%s' "$?" )
case "$RJ14_OUT" in
  "PREFLIGHT_CLEAN"*)
    bad "RJ14: a manifest in a DIFFERENT repository exempted this repo's dirty file of the same relative path — the -ef identity guard is gone (got: $RJ14_OUT)" ;;
  *)
    ok "RJ14: a manifest path in a foreign repository does not exempt anything here — the -ef guard answers 'same directory' by identity, not by string" ;;
esac
( cd "$RJ_REPO" && git checkout -q -- . )

# RJ10 — the exemption is bounded by a validity check, not by trust. Excluding the file from the
# dirty set would otherwise let a hand-edited manifest through, and ADR-0075 measured hand-edits
# as real. What is exempt is the manifest's dirtiness, never its content.
if [ "$(ri_flat 'manifest-validate.sh' "$STEP5")" -ge 1 ]; then
  ok "RJ10: Step 5 bounds the manifest exemption by running manifest-validate.sh"
else
  bad "RJ10: nothing validates the manifest in Step 5 — the #239 exemption is unbounded (a hand-edited manifest would pass)"
fi

# RJ11 — the reason must travel with the exemption. An exemption whose argument is only in an ADR
# reads as carelessness to the next person, and this one looks exactly like a weakened check.
if [ "$(ri_flat 'the manifest is exempt' "$STEP5")" -ge 1 ] \
   && [ "$(ri_flat 'the most known thing in the repository' "$STEP5")" -ge 1 ]; then
  ok "RJ11: Step 5 states why the manifest is exempt and why the §D2 purpose survives"
else
  bad "RJ11: the manifest exemption carries no stated reason — the next reader will 'fix' it back (#239)"
fi

# RJ12 — the *.bak fact is load-bearing for TWO checks and was verified rather than assumed: if
# `*.bak` were not gitignored, 5.0.3's `sed -i.bak` would dirty the tree here AND trip ADR-0068
# §D11's merge-back escape check on every stage.
if [ "$(ri_flat '`*.bak` is gitignored' "$STEP5")" -ge 1 ]; then
  ok "RJ12: Step 5 records that 5.0.3's sed -i.bak debris is gitignored, for this fence and for the escape check"
else
  bad "RJ12: the *.bak fact is unrecorded — a change to .gitignore would break two checks with no warning"
fi

# Z1 — assertion-count floor (ADR-0083 §D3: six assertions vanished from a suite once and the
# suite still read as passing). A floor, not an exact count, so adding assertions needs no bump.
Z1_TOTAL=$((PASS + FAIL))
if [ "$Z1_TOTAL" -ge 60 ]; then
  ok "Z1: assertion-count floor met ($Z1_TOTAL executed)"
else
  bad "Z1: only $Z1_TOTAL assertions executed — expected >= 60; assertions have gone missing, not passed"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
