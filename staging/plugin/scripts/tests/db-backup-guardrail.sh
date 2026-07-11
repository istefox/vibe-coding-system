#!/bin/bash
# Dedicated test harness for db-backup-guardrail.sh — 16 test cases (16 required).
# Bash 3.2 clean. Fixtures via tempdir. Target: PASS=16 FAIL=0.
# ADR-0009 v1.1: hook emits hookSpecificOutput.permissionDecision (modern format, not legacy).
# Split: agent_id absent (orchestrator) → ask; agent_id present (sub-agent) → deny.

HOOK="$HOME/.claude/hooks/db-backup-guardrail.sh"
TMP=$(mktemp -d)
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# run_hook: pipe stdin to the hook with DB_GUARDRAIL_DIR isolated to TMP/state
run_hook() {
  env DB_GUARDRAIL_DIR="$TMP/state" bash "$HOOK" "$@"
}

# mk_payload_agent: build payload JSON for a sub-agent (agent_id present)
# Usage: mk_payload_agent <cmd> <cwd>
mk_payload_agent() {
  local cmd="$1" cwd="$2"
  jq -nc --arg cmd "$cmd" --arg cwd "$cwd" \
    '{"session_id":"t","agent_id":"a1","agent_type":"coder","tool_name":"Bash","cwd":$cwd,"tool_input":{"command":$cmd}}'
}

# mk_payload_orch: build payload JSON for orchestrator (agent_id absent)
# Usage: mk_payload_orch <cmd> <cwd>
mk_payload_orch() {
  local cmd="$1" cwd="$2"
  jq -nc --arg cmd "$cmd" --arg cwd "$cwd" \
    '{"session_id":"t","tool_name":"Bash","cwd":$cwd,"tool_input":{"command":$cmd}}'
}

# decision_is: assert that hook output has permissionDecision == $2 (or "allow" for empty stdout)
# Usage: decision_is <output_file> <expected_decision>
decision_is() {
  local f="$1" expected="$2"
  if [ "$expected" = "allow" ]; then
    [ ! -s "$f" ] && return 0 || return 1
  fi
  local got
  got=$(jq -r '.hookSpecificOutput.permissionDecision // empty' "$f" 2>/dev/null)
  [ "$got" = "$expected" ] && return 0 || return 1
}

# Create a project dir with .claude/ subdirectory
mk_project() {
  local d="$TMP/proj_$$_$1"
  mkdir -p "$d/.claude"
  printf '%s' "$d"
}

# -----------------------------------------------------------------------
# Test 1: DROP TABLE + sub-agent (agent_id present) + no backup → deny
D1=$(mk_project t1)
mk_payload_agent 'psql -c "DROP TABLE users"' "$D1" \
  | run_hook >"$TMP/o1" 2>&1
if decision_is "$TMP/o1" "deny"; then
  ok "1: DROP TABLE + sub-agent + no backup → deny"
else
  bad "1: DROP TABLE + sub-agent + no backup → deny (got=$(cat "$TMP/o1"))"
fi

# -----------------------------------------------------------------------
# Test 2: DROP TABLE + orchestrator (agent_id absent) + no backup → ask
D2=$(mk_project t2)
mk_payload_orch 'psql -c "DROP TABLE users"' "$D2" \
  | run_hook >"$TMP/o2" 2>&1
if decision_is "$TMP/o2" "ask"; then
  ok "2: DROP TABLE + orchestrator + no backup → ask (split key test)"
else
  bad "2: DROP TABLE + orchestrator + no backup → ask (got=$(cat "$TMP/o2"))"
fi

# -----------------------------------------------------------------------
# Test 3: DELETE FROM with WHERE → allow (A3 excluded by WHERE)
D3=$(mk_project t3)
mk_payload_agent 'psql -c "DELETE FROM users WHERE id=1"' "$D3" \
  | run_hook >"$TMP/o3" 2>&1
if decision_is "$TMP/o3" "allow"; then
  ok "3: DELETE FROM WHERE → allow (anti-FP)"
else
  bad "3: DELETE FROM WHERE → allow (got=$(cat "$TMP/o3"))"
fi

# -----------------------------------------------------------------------
# Test 4: SELECT with 'drop' not followed by table/database/schema → allow
D4=$(mk_project t4)
mk_payload_agent "psql -c \"SELECT 'drop' AS col\"" "$D4" \
  | run_hook >"$TMP/o4" 2>&1
if decision_is "$TMP/o4" "allow"; then
  ok "4: SELECT 'drop' (no keyword-pair) → allow (anti-FP)"
else
  bad "4: SELECT 'drop' → allow (got=$(cat "$TMP/o4"))"
fi

# -----------------------------------------------------------------------
# Test 5: fresh backup file → allow (even with sub-agent)
D5=$(mk_project t5); mkdir -p "$D5/.backups"
touch "$D5/.backups/db.sql"
mk_payload_agent 'psql -c "DROP TABLE x"' "$D5" \
  | run_hook >"$TMP/o5" 2>&1
if decision_is "$TMP/o5" "allow"; then
  ok "5: fresh backup file → allow (sub-agent, backup wins)"
else
  bad "5: fresh backup file → allow (got=$(cat "$TMP/o5"))"
fi

# -----------------------------------------------------------------------
# Test 6: fresh db-backup-confirmed marker → allow
D6=$(mk_project t6)
touch "$D6/.claude/db-backup-confirmed"
mk_payload_agent 'psql -c "TRUNCATE t"' "$D6" \
  | run_hook >"$TMP/o6" 2>&1
if decision_is "$TMP/o6" "allow"; then
  ok "6: db-backup-confirmed marker fresh → allow"
else
  bad "6: db-backup-confirmed fresh → allow (got=$(cat "$TMP/o6"))"
fi

# -----------------------------------------------------------------------
# Test 7: bypass env DB_GUARDRAIL=off → allow (even with agent_id + DROP DATABASE)
D7=$(mk_project t7)
mk_payload_agent 'psql -c "DROP DATABASE prod"' "$D7" \
  | env DB_GUARDRAIL=off DB_GUARDRAIL_DIR="$TMP/state" bash "$HOOK" >"$TMP/o7" 2>&1
if decision_is "$TMP/o7" "allow"; then
  ok "7: DB_GUARDRAIL=off → allow (bypass-env)"
else
  bad "7: DB_GUARDRAIL=off → allow (got=$(cat "$TMP/o7"))"
fi

# -----------------------------------------------------------------------
# Test 8: alembic downgrade + sub-agent + no backup → deny (Famiglia B split)
D8=$(mk_project t8)
mk_payload_agent 'alembic downgrade -1' "$D8" \
  | run_hook >"$TMP/o8" 2>&1
if decision_is "$TMP/o8" "deny"; then
  ok "8: alembic downgrade + sub-agent → deny (Famiglia B)"
else
  bad "8: alembic downgrade + sub-agent → deny (got=$(cat "$TMP/o8"))"
fi

# -----------------------------------------------------------------------
# Test 9: alembic downgrade + orchestrator + no backup → ask
D9=$(mk_project t9)
mk_payload_orch 'alembic downgrade -1' "$D9" \
  | run_hook >"$TMP/o9" 2>&1
if decision_is "$TMP/o9" "ask"; then
  ok "9: alembic downgrade + orchestrator → ask (Famiglia B split)"
else
  bad "9: alembic downgrade + orchestrator → ask (got=$(cat "$TMP/o9"))"
fi

# -----------------------------------------------------------------------
# Test 10: alembic upgrade head (forward migration) → allow (anti-FP B1 only matches downgrade)
D10=$(mk_project t10)
mk_payload_agent 'alembic upgrade head' "$D10" \
  | run_hook >"$TMP/o10" 2>&1
if decision_is "$TMP/o10" "allow"; then
  ok "10: alembic upgrade head → allow (anti-FP forward migration)"
else
  bad "10: alembic upgrade head → allow (got=$(cat "$TMP/o10"))"
fi

# -----------------------------------------------------------------------
# Test 11: non-Bash tool → allow (fail-open)
printf '{"session_id":"t11","agent_id":"a1","agent_type":"coder","tool_name":"Edit","cwd":"%s","tool_input":{"command":"DROP TABLE x"}}' "$TMP" \
  | run_hook >"$TMP/o11" 2>&1
if decision_is "$TMP/o11" "allow"; then
  ok "11: tool_name=Edit → allow (fail-open non-Bash)"
else
  bad "11: non-Bash tool → allow (got=$(cat "$TMP/o11"))"
fi

# -----------------------------------------------------------------------
# Test 12: malformed JSON → allow, rc 0 (fail-open)
printf 'not-json' \
  | run_hook >"$TMP/o12" 2>&1
RC=$?
if decision_is "$TMP/o12" "allow" && [ "$RC" -eq 0 ]; then
  ok "12: malformed JSON → allow + rc=0 (fail-open)"
else
  bad "12: malformed JSON fail-open (rc=$RC out=$(cat "$TMP/o12"))"
fi

# -----------------------------------------------------------------------
# Test 13: db-is-ephemeral marker → allow (even with sub-agent + DROP TABLE)
D13=$(mk_project t13)
touch "$D13/.claude/db-is-ephemeral"
mk_payload_agent 'psql -c "DROP TABLE x"' "$D13" \
  | run_hook >"$TMP/o13" 2>&1
if decision_is "$TMP/o13" "allow"; then
  ok "13: db-is-ephemeral marker → allow (bypass-ephemeral)"
else
  bad "13: db-is-ephemeral → allow (got=$(cat "$TMP/o13"))"
fi

# -----------------------------------------------------------------------
# Test 14: stale db-backup-confirmed (backdated) → gate (deny for sub-agent)
# Backdating via touch -t: 202001010000 = 2020-01-01 00:00 → mtime >> MAX_AGE_H ago
D14=$(mk_project t14)
touch -t 202001010000 "$D14/.claude/db-backup-confirmed"
mk_payload_agent 'psql -c "DROP TABLE stale"' "$D14" \
  | run_hook >"$TMP/o14" 2>&1
if decision_is "$TMP/o14" "deny"; then
  ok "14: stale db-backup-confirmed → deny (mtime constraint enforced)"
else
  bad "14: stale marker → deny (got=$(cat "$TMP/o14"))"
fi

# -----------------------------------------------------------------------
# Test 15 (optional): deny reason for sub-agent does NOT contain bypass instructions
D15=$(mk_project t15)
mk_payload_agent 'psql -c "DROP TABLE x"' "$D15" \
  | run_hook >"$TMP/o15" 2>&1
REASON15=$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' "$TMP/o15" 2>/dev/null)
if [ -n "$REASON15" ] && ! printf '%s' "$REASON15" | grep -iqE 'DB_GUARDRAIL=off|db-is-ephemeral|db-backup-confirmed|touch.*\.claude|attempt to bypass' 2>/dev/null; then
  ok "15: deny reason does NOT mention bypass instructions (never-bypass-guardrails)"
else
  bad "15: deny reason leaks bypass (reason=$REASON15)"
fi

# -----------------------------------------------------------------------
# Test 16 (optional): ask reason for orchestrator CONTAINS legitimate remedies
D16=$(mk_project t16)
mk_payload_orch 'psql -c "DROP TABLE x"' "$D16" \
  | run_hook >"$TMP/o16" 2>&1
REASON16=$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' "$TMP/o16" 2>/dev/null)
if printf '%s' "$REASON16" | grep -iq 'db-backup-confirmed' 2>/dev/null && \
   printf '%s' "$REASON16" | grep -iq '\.backups' 2>/dev/null; then
  ok "16: ask reason contains remedies (db-backup-confirmed + .backups)"
else
  bad "16: ask reason missing remedies (reason=$REASON16)"
fi

# -----------------------------------------------------------------------
echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$TMP"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
