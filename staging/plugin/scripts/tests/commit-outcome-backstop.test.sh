#!/bin/bash
# commit-outcome-backstop.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash commit-outcome-backstop.test.sh
#
# ADR-0168 — docs/architecture/ADR-0168-commit-outcome-backstop-hook.md
# Plan — docs/superpowers/plans/2026-08-23-commit-outcome-backstop-hook.md, Task 1.
# SPEC.md R-01 (archived to docs/specs/ at completion). Assertion prefix CO, verified free across
# staging/ on 2026-08-23 (ADR-0168 §D10).
#
# TASK 1 ONLY (ADR-0101 rule 1 — an assertion must not sit in the same batch as the task it depends
# on). This file exercises `commit-outcome-check.sh`
# (staging/plugin/skills/concept-to-code/scripts/commit-outcome-check.sh), which Task 2 creates and
# does not exist yet. CO1-CO6 are RED here, by construction: `run_checker` below shells out to a
# script that is not on disk, `bash "$CHECKER" ...` fails with "No such file or directory" (bash
# exit 127), and that output matches none of the expected tokens/exit codes asserted below. A red
# assertion at this checkpoint is the deliverable, not a defect (plan's Batching table, Batch A/B —
# CO1-CO6 go green after Task 2).
#
# CO18 is a different kind of assertion — a denominator guard (rule 7) on THIS FILE'S OWN fixture
# derivation: did the search for a real manifest under docs/manifests/ that passes
# manifest-validate.sh find at least one candidate. It does not touch commit-outcome-check.sh at
# all, so unlike CO1-CO6 it is expected GREEN today; its purpose is to fail loudly if that search
# ever regresses to zero candidates, which would make CO1-CO5 vacuously RED for the wrong reason
# (zero matches and zero candidates look identical from outside).
#
# FIXTURES: a REAL manifest from docs/manifests/, patched via sed (project_root, current_step,
# status) — never a hand-written minimal one — so the quoting is the quoting manifest-init.sh
# actually writes. Real `git init` trees, real commits. Same technique
# commit-transition-order.test.sh already uses for its CTO12 fixtures (ADR-0078's lesson).
#
# --- plants (plant-check.sh, ADR-0149 grammar) ------------------------------------------------
# An assertion whose plant does not fire pins nothing (ADR-0108, rule 2). CO1-CO5 target
# commit-outcome-check.sh — a file that does not exist until Task 2, so these declarations name the
# exact line Task 2's verbatim move of the SKILL.md fence body will produce (source verified against
# the live c2c-step7-commit-outcome fence, 2026-08-23); plant-check.sh's Task 8 run is what actually
# fires them, once the file exists.
#
# plant: CO1 | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh | if [ -z "$_gs" ]; then echo "COMMIT_OK"; exit 0; fi | if [ -n "$_gs" ]; then echo "COMMIT_OK"; exit 0; fi
# plant: CO2 | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh | *)     echo "COMMIT_UNCOMMITTED modified";  exit 1 ;; | *)     echo "COMMIT_UNCOMMITTED untracked";  exit 1 ;;
# plant: CO3 | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh | '??'*) echo "COMMIT_UNCOMMITTED untracked"; exit 1 ;; | '??'*) echo "COMMIT_UNCOMMITTED modified"; exit 1 ;;
# plant: CO4 | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh | if [ "$_cs" != "completed" ]; then echo "COMMIT_NONTERMINAL current_step"; exit 1; fi | if [ "$_cs" = "completed" ]; then echo "COMMIT_NONTERMINAL current_step"; exit 1; fi
# plant: CO5 | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh | [ -f "$_m" ] || { echo "COMMIT_OUTCOME_NORUN noManifest"; exit 3; } | [ -f "$_m" ] && { echo "COMMIT_OUTCOME_NORUN noManifest"; exit 3; }
#
# CO6 targets the PAIRS line itself (sync-to-claude.sh), once Task 2 adds it — a data line, not a
# comparison, so the plant corrupts the source-side path rather than inverting a condition.
#
# plant: CO6 | sync-to-claude.sh | plugin/skills/concept-to-code/scripts/commit-outcome-check.sh|skills/concept-to-code/scripts/commit-outcome-check.sh | plugin/skills/concept-to-code/scripts/commit-outcome-check-MISSING.sh|skills/concept-to-code/scripts/commit-outcome-check.sh
#
# CO18 self-targets: narrows this file's own base-manifest glob so nothing under docs/manifests/
# matches, so the search returns zero candidates instead of >=1 — proof the guard actually reads the
# search result and is not asserting a constant.
#
# plant: CO18 | plugin/scripts/tests/commit-outcome-backstop.test.sh | for _bm in "$REPO"/docs/manifests/*.manifest.yml; do | for _bm in "$REPO"/docs/manifests/NONEXISTENT-*.manifest.yml; do
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CHECKER="$STAGING/plugin/skills/concept-to-code/scripts/commit-outcome-check.sh"
SYNC="$STAGING/sync-to-claude.sh"
MANIFEST_VALIDATE="$STAGING/plugin/skills/concept-to-code/scripts/manifest-validate.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# BASE_MANIFEST: a REAL manifest, patched — same loop, same reason, as
# commit-transition-order.test.sh's identical search (ADR-0078's lesson: a hand-written manifest
# would not carry the exact quoting a real reader of current_step/status has to parse).
# ---------------------------------------------------------------------------
BASE_MANIFEST=""; BASE_ROOT=""
for _bm in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_bm" ] || continue
  if bash "$MANIFEST_VALIDATE" "$_bm" >/dev/null 2>&1; then
    BASE_MANIFEST="$_bm"
    BASE_ROOT=$(grep '^project_root:' "$_bm" | sed -e 's/^project_root:[[:space:]]*"//' -e 's/"[[:space:]]*$//')
    break
  fi
done
mkdir -p "$TMP/proj"

# mk_manifest <dest> <current_step> <status> — sed-level patch, quoting preserved.
mk_manifest() {
  [ -n "$BASE_MANIFEST" ] || return 1
  sed -e "s|$BASE_ROOT|$TMP/proj|g" \
      -e "s|^current_step:.*|current_step: \"$2\"|" \
      -e "s|^status:.*|status: \"$3\"|" "$BASE_MANIFEST" >"$1"
}

git_setup() {
  mkdir -p "$1"
  git -C "$1" init -q >/dev/null 2>&1
  git -C "$1" config user.email "test@example.com"
  git -C "$1" config user.name "Test"
  git -C "$1" config commit.gpgsign false
}

# run_checker <manifest-path> — the ONLY way CO1-CO5 talk to the file under test. Writes stdout to
# $TMP/co-out, exit code to $TMP/co-rc. stderr is captured for diagnostics only, never matched
# against.
run_checker() {
  bash "$CHECKER" "$1" >"$TMP/co-out" 2>"$TMP/co-err"
  echo "$?" >"$TMP/co-rc"
}

# ===========================================================================
# CO1 (R-01) — terminal, committed, clean -> stdout COMMIT_OK, exit 0.
# ===========================================================================
if [ -n "$BASE_MANIFEST" ]; then
  FXA="$TMP/fxA"; git_setup "$FXA"
  mk_manifest "$FXA/manifest.yml" completed completed
  git -C "$FXA" add manifest.yml >/dev/null 2>&1
  git -C "$FXA" commit -q -m init >/dev/null 2>&1
  run_checker "$FXA/manifest.yml"
  _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
  if [ "$_out" = "COMMIT_OK" ] && [ "$_rc" -eq 0 ]; then
    ok "CO1 (R-01) terminal/committed/clean -> COMMIT_OK, exit 0"
  else
    bad "CO1 (R-01) terminal/committed/clean: expected 'COMMIT_OK' exit 0, got '$_out' exit $_rc"
  fi
else
  bad "CO1 (R-01) no base manifest available — see CO18"
fi

# ===========================================================================
# CO2 (R-01) — terminal, tracked and modified after the commit -> COMMIT_UNCOMMITTED modified, exit
# 1. Exact qualifier, not a prefix (the plan's own bullet).
# ===========================================================================
if [ -n "$BASE_MANIFEST" ]; then
  FXB="$TMP/fxB"; git_setup "$FXB"
  mk_manifest "$FXB/manifest.yml" completed completed
  git -C "$FXB" add manifest.yml >/dev/null 2>&1
  git -C "$FXB" commit -q -m init >/dev/null 2>&1
  printf '\n# touched after commit\n' >>"$FXB/manifest.yml"
  run_checker "$FXB/manifest.yml"
  _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
  if [ "$_out" = "COMMIT_UNCOMMITTED modified" ] && [ "$_rc" -eq 1 ]; then
    ok "CO2 (R-01) terminal/tracked-modified -> COMMIT_UNCOMMITTED modified, exit 1"
  else
    bad "CO2 (R-01) terminal/tracked-modified: expected 'COMMIT_UNCOMMITTED modified' exit 1, got '$_out' exit $_rc"
  fi
else
  bad "CO2 (R-01) no base manifest available — see CO18"
fi

# ===========================================================================
# CO3 (R-01) — terminal, never added -> COMMIT_UNCOMMITTED untracked, exit 1. Exact qualifier.
# ===========================================================================
if [ -n "$BASE_MANIFEST" ]; then
  FXC="$TMP/fxC"; git_setup "$FXC"
  mk_manifest "$FXC/manifest.yml" completed completed
  run_checker "$FXC/manifest.yml"
  _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
  if [ "$_out" = "COMMIT_UNCOMMITTED untracked" ] && [ "$_rc" -eq 1 ]; then
    ok "CO3 (R-01) terminal/untracked -> COMMIT_UNCOMMITTED untracked, exit 1"
  else
    bad "CO3 (R-01) terminal/untracked: expected 'COMMIT_UNCOMMITTED untracked' exit 1, got '$_out' exit $_rc"
  fi
else
  bad "CO3 (R-01) no base manifest available — see CO18"
fi

# ===========================================================================
# CO4 (R-01) — current_step: step_7_commit, status: in_progress, committed and clean ->
# COMMIT_NONTERMINAL current_step, exit 1. Both fields are non-terminal; the checker's own check
# order (current_step read before status, per the live fence) is what makes "current_step" the
# exact, not merely the possible, qualifier here.
# ===========================================================================
if [ -n "$BASE_MANIFEST" ]; then
  FXD="$TMP/fxD"; git_setup "$FXD"
  mk_manifest "$FXD/manifest.yml" step_7_commit in_progress
  git -C "$FXD" add manifest.yml >/dev/null 2>&1
  git -C "$FXD" commit -q -m init >/dev/null 2>&1
  run_checker "$FXD/manifest.yml"
  _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
  if [ "$_out" = "COMMIT_NONTERMINAL current_step" ] && [ "$_rc" -eq 1 ]; then
    ok "CO4 (R-01) current_step=step_7_commit/status=in_progress, committed/clean -> COMMIT_NONTERMINAL current_step, exit 1"
  else
    bad "CO4 (R-01) expected 'COMMIT_NONTERMINAL current_step' exit 1, got '$_out' exit $_rc"
  fi
else
  bad "CO4 (R-01) no base manifest available — see CO18"
fi

# ===========================================================================
# CO5 (R-01) — manifest outside any git repository -> COMMIT_OUTCOME_NORUN, exit 3; AND a path that
# does not exist -> COMMIT_OUTCOME_NORUN noManifest, exit 3. Two sub-cases joined by the plan's own
# bullet into one assertion.
# ===========================================================================
CO5_FAIL=""
if [ -n "$BASE_MANIFEST" ]; then
  FXE="$TMP/fxE"; mkdir -p "$FXE"
  mk_manifest "$FXE/manifest.yml" completed completed
  if git -C "$FXE" rev-parse --show-toplevel >/dev/null 2>&1; then
    CO5_FAIL="$CO5_FAIL
  fixture invalid: $FXE is unexpectedly inside a git repository, cannot exercise the no-repo path"
  else
    run_checker "$FXE/manifest.yml"
    _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
    case "$_out" in
      "COMMIT_OUTCOME_NORUN"*) [ "$_rc" -eq 3 ] || CO5_FAIL="$CO5_FAIL
  outside-repo case: exit=$_rc (expected 3), out=$_out" ;;
      *) CO5_FAIL="$CO5_FAIL
  outside-repo case: expected 'COMMIT_OUTCOME_NORUN', got: $_out (exit $_rc)" ;;
    esac
  fi

  run_checker "$TMP/does-not-exist/manifest.yml"
  _rc=$(cat "$TMP/co-rc"); _out=$(cat "$TMP/co-out")
  if [ "$_out" = "COMMIT_OUTCOME_NORUN noManifest" ] && [ "$_rc" -eq 3 ]; then
    :
  else
    CO5_FAIL="$CO5_FAIL
  nonexistent-path case: expected 'COMMIT_OUTCOME_NORUN noManifest' exit 3, got '$_out' exit $_rc"
  fi
else
  CO5_FAIL="
  no base manifest available — see CO18"
fi

if [ -z "$CO5_FAIL" ]; then
  ok "CO5 (R-01) outside-git -> COMMIT_OUTCOME_NORUN exit 3; nonexistent path -> COMMIT_OUTCOME_NORUN noManifest exit 3"
else
  bad "CO5 (R-01) failed:$CO5_FAIL"
fi

# ===========================================================================
# CO6 (R-01) — sync-to-claude.sh's PAIRS block carries the commit-outcome-check.sh entry. Without it
# the script never reaches ~/.claude and both callers (SKILL.md Step 7.1, the backstop hook) resolve
# nothing on a real machine — pairs-completeness.test.sh does not require it (skills are vendored
# selectively), so nothing else would catch this (ADR-0168 §D1).
# ===========================================================================
CO6_NEEDLE='plugin/skills/concept-to-code/scripts/commit-outcome-check.sh|skills/concept-to-code/scripts/commit-outcome-check.sh'
if grep -qxF "$CO6_NEEDLE" "$SYNC"; then
  ok "CO6 (R-01) sync-to-claude.sh PAIRS carries the commit-outcome-check.sh entry"
else
  bad "CO6 (R-01) sync-to-claude.sh PAIRS is missing the entry: $CO6_NEEDLE"
fi

# ===========================================================================
# CO18 (rule 7) — denominator guard: the base-manifest search above found at least one manifest
# passing manifest-validate.sh. Zero candidates and zero failures are indistinguishable from
# outside, and CO1-CO5 derive every fixture from that one file — a search that silently returns
# nothing would make CO1-CO5 vacuously RED for the wrong reason. Expected GREEN today: unlike
# CO1-CO6 this does not depend on commit-outcome-check.sh existing at all.
# ===========================================================================
if [ -n "$BASE_MANIFEST" ]; then
  ok "CO18 base-manifest search found a candidate passing manifest-validate.sh ($BASE_MANIFEST)"
else
  bad "CO18 base-manifest search found ZERO candidates under docs/manifests/ passing manifest-validate.sh — CO1-CO5 have nothing to build fixtures from"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
