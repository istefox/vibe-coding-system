#!/bin/bash
# hook-verify-workflow test harness — offline, no network, no live session, no real audit log.
# Bash 3.2 clean. Run: bash hook-verify-workflow.test.sh
#
# Every case builds a fixture audit.log under a temp PATTERN_ENFORCE_DIR, which
# pre-flight-pattern-enforce.sh honours (its line 39) and this script honours too.

set -u

# Hermeticity: a live Claude Code session exports CLAUDE_CODE_SESSION_ID, which the
# script under test now reads (issue #33). Unset it so fixtures control the variable
# exclusively — cases that need it set pass it explicitly per invocation.
unset CLAUDE_CODE_SESSION_ID

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
V="$SCRIPTS/hook-verify-workflow.sh"
SKILL_MD=$(cd "$SCRIPTS/../skills/concept-to-code" && pwd)/SKILL.md
# VCS-047/ADR-0174: Step 5's exit-code documentation moved into references/step5-implementation.md.
STEP5_REF=$(cd "$SCRIPTS/../skills/concept-to-code" && pwd)/references/step5-implementation.md

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

# rowsid <ts> <session_id> <tool> <decision> <detail>  — like row(), but with an explicit
# session id instead of the hardcoded "sess" placeholder. Used only by the session-scoping
# section below (issue #33); every pre-existing fixture keeps using row()/"sess" untouched.
rowsid() { printf '%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5"; }

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

# --- session scoping: CLAUDE_CODE_SESSION_ID (issue #33) ------------------------------------------

# S1 (non-regression companion, already passing today): same-session rows only, with
# CLAUDE_CODE_SESSION_ID set to the matching id => VERIFIED. Already true today too, because the
# unfixed script is session-blind (an allow row alone already verifies regardless of session id or
# env var) -- this pins the happy path so the filtering logic added in Task 2 cannot silently break it.
D="$tmp/sid-same"; mklog "$D" "$(rowsid "$AFTER" sess-mine Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" CLAUDE_CODE_SESSION_ID=sess-mine bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "S1 same-session rows, CLAUDE_CODE_SESSION_ID set => exit 0 VERIFIED" \
  || no "S1 same-session rows => exit 0 (got $RC)"

# S2 (dynamic, genuine RED): foreign-session rows only, CLAUDE_CODE_SESSION_ID set to a DIFFERENT id
# => REFUTED, not VERIFIED. Expected now (RED): exit 0 VERIFIED -- the unfixed script ignores field 2
# entirely, so a foreign session's own allow row still flips hook_verified to true (empirically
# reproduced against the real script during planning -- ADR-0029 Context -- the exact false positive
# SPEC.md and ADR-0016 both name).
D="$tmp/sid-foreign"; mklog "$D" "$(rowsid "$AFTER" sess-other Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" CLAUDE_CODE_SESSION_ID=sess-mine bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "S2 foreign-session rows, CLAUDE_CODE_SESSION_ID set => exit 1 REFUTED" \
  || no "S2 foreign-session rows => exit 1 (got $RC)"
printf '%s' "$OUT" | grep -q 'other, concurrent Claude Code session' \
  && ok "S2 => reason names concurrent-session exclusion, not a hooks-disabled guess" \
  || no "S2 => reason should name concurrent-session exclusion"

# S3 (dynamic, genuine RED): mixed rows, CLAUDE_CODE_SESSION_ID set => verdict AND the count use ONLY
# the matching session. sess-mine alone would REFUTE (workflow-subagent bypass); sess-other's allow
# row must not rescue it. Expected now (RED): exit 0 VERIFIED and decisions_after_mark=2 (both rows
# counted unconditionally today).
D="$tmp/sid-mixed"; mklog "$D" \
  "$(rowsid "$AFTER" sess-mine  Edit bypass-noncoder 'agent_type=workflow-subagent')" \
  "$(rowsid "$AFTER" sess-other Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" CLAUDE_CODE_SESSION_ID=sess-mine bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 1 ] && ok "S3 mixed rows => foreign allow does not rescue this session's bypass" \
  || no "S3 mixed rows => exit 1 (got $RC)"
printf '%s' "$OUT" | grep -q 'decisions_after_mark=1' \
  && ok "S3 => count is scoped to this session (1, not 2)" \
  || no "S3 => decisions_after_mark should be scoped to 1"

# S4 (dynamic, genuine RED): no CLAUDE_CODE_SESSION_ID, rows from 2 different sessions after the
# marker => INCONCLUSIVE, not a guess in either direction. Expected now (RED): exit 0 VERIFIED (both
# rows' allow decisions are currently counted with no session awareness at all).
D="$tmp/sid-ambiguous"; mklog "$D" \
  "$(rowsid "$AFTER" sess-a Edit allow 'PATTERN found in window')" \
  "$(rowsid "$AFTER" sess-b Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 3 ] && ok "S4 ambiguous multi-session window, no CLAUDE_CODE_SESSION_ID => exit 3 INCONCLUSIVE" \
  || no "S4 ambiguous window => exit 3 (got $RC)"
printf '%s' "$OUT" | grep -q 'status=INCONCLUSIVE' && ok "S4 => status line says INCONCLUSIVE" || no "S4 => status line"
printf '%s' "$OUT" | grep -q 'hook_verified=unchanged' && ok "S4 => recommends nothing (same discipline as the missing-log case)" || no "S4 => recommends nothing"
printf '%s' "$OUT" | grep -q '2 different Claude Code sessions' && ok "S4 => reason names the session count" || no "S4 => reason should name the session count"

# S5 (non-regression companion, already passing both before AND after this fix -- disclosed residual
# gap, ADR-0029 Section 2.1/Section 4 Negative, not a bug): no CLAUDE_CODE_SESSION_ID, exactly ONE
# session id in the window (which happens not to be "ours," but there is nothing to compare it
# against) => falls through to legacy, session-blind behavior. Pinned deliberately so a future change
# cannot silently alter this documented limitation without this assertion failing first.
D="$tmp/sid-single-unscoped"; mklog "$D" "$(rowsid "$AFTER" sess-only-one Edit allow 'PATTERN found in window')"
OUT=$(PATTERN_ENFORCE_DIR="$D" bash "$V" --check "$MARK" 2>&1); RC=$?
[ "$RC" -eq 0 ] && ok "S5 single session id, no CLAUDE_CODE_SESSION_ID => exit 0 VERIFIED (disclosed residual gap, not a bug)" \
  || no "S5 single unscoped session => exit 0 (got $RC)"

# --- exit-code contract documentation stays in sync (issue #33) -------------------------------------

# S6 (static, genuine RED): the script's own header documents the second INCONCLUSIVE cause, not just
# the missing log.
grep -q 'CLAUDE_CODE_SESSION_ID is unset' "$V" \
  && ok "S6 header documents the session-ambiguity INCONCLUSIVE cause" \
  || no "S6 header should document the session-ambiguity INCONCLUSIVE cause"

# S7 (static, genuine RED): SKILL.md's exit-3 bullet no longer implies a missing audit log is the only
# INCONCLUSIVE cause.
grep -q 'CLAUDE_CODE_SESSION_ID` was unavailable and the post-marker window mixed rows' "$STEP5_REF" \
  && ok "S7 SKILL.md exit-3 bullet documents the second INCONCLUSIVE cause" \
  || no "S7 SKILL.md exit-3 bullet should document the second INCONCLUSIVE cause"

# S8 (static, genuine RED): SKILL.md's exit-1 bullet's failure enumeration also names the third
# REFUTED cause.
grep -q 'belongs to a different, concurrent Claude Code session' "$STEP5_REF" \
  && ok "S8 SKILL.md exit-1 bullet names the concurrent-session REFUTED cause" \
  || no "S8 SKILL.md exit-1 bullet should name the concurrent-session REFUTED cause"

# --- summary ----------------------------------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
