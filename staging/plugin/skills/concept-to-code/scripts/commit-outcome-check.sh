#!/bin/bash
# concept-to-code: commit-outcome-check.sh — bash 3.2-clean
# Usage: commit-outcome-check.sh <manifest-path>
#
# This is a CHECKER, not a reporter (rule 5): callers branch on its exit code, never parse stdout
# as advisory. Exit 0 COMMIT_OK | exit 1 COMMIT_UNCOMMITTED|COMMIT_NONTERMINAL | exit 3
# COMMIT_OUTCOME_NORUN <reason>.
#
# Two callers, and both must move together (ADR-0168 §D1):
#   1. concept-to-code/SKILL.md Step 7.1 (the `c2c-step7-commit-outcome` fence).
#   2. commit-outcome-backstop.sh (PostToolUse hook, ADR-0168).
# The contract — four tokens, three exit codes — originates at ADR-0135 §D3 and must not change in
# one caller without changing in the other.
#
# Body below is the current Step 7.1 fence body moved verbatim (ADR-0168 §D1/§D2): same grep/sed
# field reads, same git status check, same case on '??'*, same tokens, same exit codes. Only the
# variable source (positional argument instead of the substituted placeholder) and the usage guard
# for a missing argument are new.
set -u

_m="${1:-}"
[ -n "$_m" ] || { echo "COMMIT_OUTCOME_NORUN noManifest"; exit 3; }
[ -f "$_m" ] || { echo "COMMIT_OUTCOME_NORUN noManifest"; exit 3; }
_d=$(dirname "$_m")
git -C "$_d" rev-parse --git-dir >/dev/null 2>&1 || { echo "COMMIT_OUTCOME_NORUN noRepo"; exit 3; }
_cs=$(grep '^current_step:' "$_m" | head -1 | sed -e 's/^current_step:[[:space:]]*//' -e 's/^"//' -e 's/"[[:space:]]*$//')
_st=$(grep '^status:' "$_m" | head -1 | sed -e 's/^status:[[:space:]]*//' -e 's/^"//' -e 's/"[[:space:]]*$//')
if [ "$_cs" != "completed" ]; then echo "COMMIT_NONTERMINAL current_step"; exit 1; fi
if [ "$_st" != "completed" ]; then echo "COMMIT_NONTERMINAL status"; exit 1; fi
_gs=$(git -C "$_d" status --porcelain -- "$(basename "$_m")")
if [ -z "$_gs" ]; then echo "COMMIT_OK"; exit 0; fi
case "$_gs" in
  '??'*) echo "COMMIT_UNCOMMITTED untracked"; exit 1 ;;
  *)     echo "COMMIT_UNCOMMITTED modified";  exit 1 ;;
esac
