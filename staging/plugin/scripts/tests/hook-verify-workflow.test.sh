#!/bin/bash
# hook-verify-workflow test harness — offline, no network, no live session, no real audit log.
# Bash 3.2 clean. Run: bash hook-verify-workflow.test.sh
#
# Every case builds a fixture audit.log under a temp PATTERN_ENFORCE_DIR, which
# pre-flight-pattern-enforce.sh honours (its line 39) and this script honours too.

set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
V="$SCRIPTS/hook-verify-workflow.sh"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

MARK='2026-07-10T12:00:00Z'
BEFORE='2026-07-10T11:59:59Z'
AFTER='2026-07-10T12:00:01Z'

# mklog <dir> <lines...>  — writes a tab-separated audit.log
mklog() {
  d="$1"; shift
  mkdir -p "$d"
  : > "$d/audit.log"
  for line in "$@"; do
    printf '%s\n' "$line" >> "$d/audit.log"
  done
}

row() { printf '%s\t%s\t%s\t%s\t%s' "$1" "sess" "$2" "$3" "$4"; }

# --- --mark ---------------------------------------------------------------------------------------
M=$(bash "$V" --mark); RC=$?
[ "$RC" -eq 0 ] && ok "mark: exits 0" || no "mark: exits 0"
case "$M" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z)
    ok "mark: emits ISO-8601 UTC" ;;
  *) no "mark: emits ISO-8601 UTC (got: $M)" ;;
esac

# --- usage ----------------------------------------------------------------------------------------
bash "$V" >/dev/null 2>&1;                [ $? -eq 2 ] && ok "usage: no args => exit 2"        || no "usage: no args => exit 2"
bash "$V" --check >/dev/null 2>&1;        [ $? -eq 2 ] && ok "usage: --check without marker => 2" || no "usage: --check without marker => 2"
bash "$V" --check "not-a-date" >/dev/null 2>&1; [ $? -eq 2 ] && ok "usage: malformed marker => 2" || no "usage: malformed marker => 2"
bash "$V" --bogus >/dev/null 2>&1;        [ $? -eq 2 ] && ok "usage: unknown flag => exit 2"   || no "usage: unknown flag => exit 2"

# --- INCONCLUSIVE: missing audit log. MUST NOT be reported as refuted. -----------------------------
D="$tmp/nolog"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 3 ] && ok "missing log => exit 3 (not 1)" || no "missing log => exit 3 (got $RC)"
printf '%s' "$OUT" | grep -q 'status=INCONCLUSIVE'            && ok "missing log => INCONCLUSIVE"          || no "missing log => INCONCLUSIVE"
printf '%s' "$OUT" | grep -q 'hook_verified=unchanged'        && ok "missing log => recommends nothing"    || no "missing log => recommends nothing"
printf '%s' "$OUT" | grep -q 'NOT evidence that hooks fail'   && ok "missing log => reason warns against misreading" || no "missing log => reason warns against misreading"

# --- VERIFIED via `allow` -------------------------------------------------------------------------
# The detail strings below are the REAL ones the guard writes. An earlier draft of this harness used
# 'agent_type=coder' on the allow row, which no real row ever carries; the fixtures agreed with the
# script and both were wrong. Only the live audit log exposed it.
D="$tmp/allow"; mklog "$D" "$(row "$AFTER" Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "allow => exit 0 VERIFIED" || no "allow => exit 0 (got $RC)"
printf '%s' "$OUT" | grep -q 'RECOMMEND hook_verified=true' && ok "allow => recommend true" || no "allow => recommend true"

# --- VERIFIED via `block`: a block proves enforcement just as an allow does ------------------------
D="$tmp/block"; mklog "$D" "$(row "$AFTER" Edit block 'PATTERN missing in window=20')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "block => exit 0 VERIFIED (a block proves enforcement)" || no "block => exit 0 (got $RC)"

# --- REFUTED: the silent bypass, hooks fired but the guard stood down ------------------------------
D="$tmp/bypass"; mklog "$D" "$(row "$AFTER" Edit bypass-noncoder 'agent_type=workflow-subagent')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "workflow-subagent bypass => exit 1 REFUTED" || no "workflow-subagent bypass => exit 1 (got $RC)"
printf '%s' "$OUT" | grep -q "did not pass agentType: 'coder'" && ok "bypass => reason names the real fix" || no "bypass => reason names the real fix"
printf '%s' "$OUT" | grep -q 'not a platform limitation'        && ok "bypass => reason rules out the platform" || no "bypass => reason rules out the platform"

# --- REFUTED: no decisions at all after the marker --------------------------------------------------
D="$tmp/nolines"; mklog "$D" "$(row "$BEFORE" Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "only pre-marker lines => exit 1 REFUTED" || no "only pre-marker lines => exit 1 (got $RC)"
printf '%s' "$OUT" | grep -q 'never saw an Edit/Write' && ok "no post-marker rows => reason mentions disableAllHooks/trust" || no "no post-marker rows => reason"

# --- the marker really excludes earlier evidence ----------------------------------------------------
D="$tmp/mixed"; mklog "$D" \
  "$(row "$BEFORE" Edit allow 'PATTERN found in window')" \
  "$(row "$AFTER"  Edit bypass-noncoder 'agent_type=workflow-subagent')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "pre-marker allow does not rescue a post-marker bypass" || no "pre-marker allow does not rescue a post-marker bypass"
printf '%s' "$OUT" | grep -q 'enforced_on_coder=0' && ok "counts exclude pre-marker rows" || no "counts exclude pre-marker rows"

# --- REFUTED: decisions exist but none from a subagent ----------------------------------------------
D="$tmp/mainloop"; mklog "$D" "$(row "$AFTER" Edit bypass-noncoder 'agent_type=')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "main-loop-only rows => exit 1 REFUTED" || no "main-loop-only rows => exit 1 (got $RC)"
printf '%s' "$OUT" | grep -q 'ran in the main loop' && ok "main-loop-only => reason says the workflow never dispatched" || no "main-loop-only => reason"

# --- other agent types bypass too, and must not be read as a WORKFLOW bypass -------------------------
# The real log carries bypass rows for agent_type=architect and agent_type=general-purpose. Only
# workflow-subagent indicates the dispatch failed to pass agentType.
D="$tmp/architect"; mklog "$D" \
  "$(row "$AFTER" Edit bypass-noncoder 'agent_type=architect')" \
  "$(row "$AFTER" Edit bypass-noncoder 'agent_type=general-purpose')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "architect/general-purpose bypasses => exit 1 REFUTED" || no "architect bypass => exit 1 (got $RC)"
printf '%s' "$OUT" | grep -q 'bypassed_workflow_subagent=0' && ok "non-workflow bypasses are not counted as workflow bypasses" || no "non-workflow bypasses miscounted"
printf '%s' "$OUT" | grep -q 'ran in the main loop' && ok "architect-only => reason does not blame the dispatch" || no "architect-only => wrong reason"

# --- a workflow bypass AND an enforcement in the same window: enforcement wins -----------------------
D="$tmp/both"; mklog "$D" \
  "$(row "$AFTER" Edit bypass-noncoder 'agent_type=workflow-subagent')" \
  "$(row "$AFTER" Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "one enforcement outweighs a co-occurring bypass" || no "enforcement must win (got $RC)"

# --- summary ----------------------------------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
