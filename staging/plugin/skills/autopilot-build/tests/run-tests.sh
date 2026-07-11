#!/usr/bin/env bash
# Self-test harness for autopilot-build skill. Structural checks against SKILL.md —
# read-only, no dispatch, no git/file side effects. Covers the documented pre-flight
# aborts and safety invariants. It does NOT prove end-to-end dispatch: the happy path
# and circuit breaker need a live coder run (the smoke test), out of scope here.
set -u
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SKILL_DIR="$HOME/.claude/skills/autopilot-build"
SK="$SKILL_DIR/SKILL.md"

# --- 1: SKILL.md exists ---
[ -f "$SK" ] && ok "autopilot: SKILL.md exists" || { bad "autopilot: SKILL.md missing"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

# --- 2: name field ---
grep -q '^name: autopilot-build$' "$SK" 2>/dev/null \
  && ok "autopilot: name=autopilot-build in frontmatter" \
  || bad "autopilot: name field missing or wrong"

# --- 3: all eight pre-flight checks documented ---
checks_ok=1
for n in 1 2 3 4 5 6 7 8; do
  grep -Eq "Check $n( |—|:|\b)" "$SK" 2>/dev/null || checks_ok=0
done
[ "$checks_ok" = "1" ] && ok "autopilot: all 8 pre-flight checks documented" \
  || bad "autopilot: one or more pre-flight checks (1-8) missing"

# --- 4: scope guard is script-level (SCOPE ERROR + exit 1), not a prompt reminder ---
grep -q 'SCOPE ERROR' "$SK" 2>/dev/null \
  && ok "autopilot: script-level scope guard (SCOPE ERROR) present" \
  || bad "autopilot: scope guard SCOPE ERROR string missing"

# --- 5: TOFU trust is read-only, never auto-granted ---
grep -q 'TOFU trust is never auto-granted\|not TOFU-trusted' "$SK" 2>/dev/null \
  && ok "autopilot: TOFU trust never auto-granted" \
  || bad "autopilot: TOFU no-auto-grant invariant missing"

# --- 6: Check 7 requires hook_verified to be known (non-null) ---
grep -q 'hook_verified' "$SK" 2>/dev/null \
  && ok "autopilot: hook_verified known-state check present" \
  || bad "autopilot: hook_verified check missing"

# --- 7: no push / no PR / no remote mutation ---
grep -q 'No push, no PR\|no push\|never opens a PR\|never pushes' "$SK" 2>/dev/null \
  && ok "autopilot: no-push/no-PR invariant present" \
  || bad "autopilot: no-push/no-PR invariant missing"

# --- 8: safety hooks always active ---
grep -q 'stop-gate' "$SK" 2>/dev/null \
  && grep -q 'pattern-enforce' "$SK" 2>/dev/null \
  && grep -q 'db-backup' "$SK" 2>/dev/null \
  && ok "autopilot: safety hooks (stop-gate/pattern-enforce/db-backup) named" \
  || bad "autopilot: one or more safety hooks not named"

# --- 9: no test disabling on RED ---
grep -q 'No test disabling\|never modifies .*test-cmd\|halts' "$SK" 2>/dev/null \
  && ok "autopilot: no-test-disabling invariant present" \
  || bad "autopilot: no-test-disabling invariant missing"

# --- 10: morning report written on every exit path ---
grep -q 'autopilot-report.json' "$SK" 2>/dev/null \
  && grep -q 'every exit path\|aborted and\|status.*partial' "$SK" 2>/dev/null \
  && ok "autopilot: morning report on every exit path" \
  || bad "autopilot: morning-report-on-every-exit guarantee missing"

# --- 11: circuit breaker halts on RED / partial ---
grep -q 'Circuit breaker\|circuit breaker\|status=partial' "$SK" 2>/dev/null \
  && ok "autopilot: circuit breaker (partial on RED) documented" \
  || bad "autopilot: circuit breaker missing"

# --- 12: commit uses --autopilot (local only, no HITL) ---
grep -q '\-\-autopilot' "$SK" 2>/dev/null \
  && ok "autopilot: commit --autopilot flag wired" \
  || bad "autopilot: commit --autopilot flag missing"

# --- 13: CC 2.1.186/187 permission-posture note present (FIX 2 alignment) ---
grep -q 'Permission posture' "$SK" 2>/dev/null \
  && grep -q '2.1.186' "$SK" 2>/dev/null \
  && ok "autopilot: CC 2.1.186/187 permission-posture note present" \
  || bad "autopilot: permission-posture (allowlist hang) note missing"

# --- 14: retry-watchdog recommendation present (FIX 2 alignment) ---
grep -q 'CLAUDE_CODE_RETRY_WATCHDOG' "$SK" 2>/dev/null \
  && ok "autopilot: CLAUDE_CODE_RETRY_WATCHDOG recommendation present" \
  || bad "autopilot: retry-watchdog recommendation missing"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
