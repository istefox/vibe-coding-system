#!/bin/bash
# Dedicated test harness for pre-flight-pattern-enforce.sh — 11 test cases.
# Bash 3.2 clean. Fixtures via tempdir (inline jsonl). Target: PASS=11 FAIL=0.
#
# v1.1 update (2026-05-21): fixtures updated to match real PreToolUse payload schema:
# - agent_type is passed in the JSON stdin payload (not .subagent_type in transcript).
# - coder subagent transcript lives in <proj>/<SID>/subagents/agent-<agent_id>.jsonl;
#   the harness simulates this by creating the subagent directory structure under TMP
#   and passing agent_id + cwd in the payload so the hook can locate the subagent jsonl.
#
# v1.2 update (2026-05-22): transcript_path now included in payload (v1.2 hook derives
# project dir from it, not by re-encoding cwd). mk_coder_payload updated accordingly.
# Added test 11: cwd with underscore + transcript_path with '-' encoding → must work.
HOOK="$HOME/.claude/hooks/pre-flight-pattern-enforce.sh"
TMP=$(mktemp -d)
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Fixed cwd and encoding used for all fixtures.
# v1.2: the hook derives project dir from transcript_path (not by re-encoding cwd).
# transcript_path in payload = $TMP/.claude/projects/$FIXTURE_ENC/$SID.jsonl
# dirname(transcript_path) = $TMP/.claude/projects/$FIXTURE_ENC  ← the project dir
# Subagent jsonl = $TMP/.claude/projects/$FIXTURE_ENC/$SID/subagents/agent-$AID.jsonl
FIXTURE_CWD="/test/project"
FIXTURE_ENC="-test-project"

# run_hook: pipe stdin to the hook with HOME and PATTERN_ENFORCE_DIR properly set.
# Uses "env" so that HOME is passed to the bash subprocess (inline VAR=val does NOT
# propagate to commands after the pipe: "HOME=$TMP func | bash hook" sets HOME for func
# but NOT for bash hook; "func | env HOME=$TMP bash hook" is correct).
run_hook() {
  env HOME="$TMP" PATTERN_ENFORCE_DIR="$TMP/state" bash "$HOOK" "$@"
}

# Fixture builder: mk_subagent_jsonl <session_id> <agent_id> <text>
# Creates $TMP/.claude/projects/<enc>/<SID>/subagents/agent-<agent_id>.jsonl
mk_subagent_jsonl() {
  local sid="$1"
  local aid="$2"
  local txt="$3"
  local dir="$TMP/.claude/projects/$FIXTURE_ENC/$sid/subagents"
  mkdir -p "$dir"
  local fpath="$dir/agent-$aid.jsonl"
  : >"$fpath"
  printf '{"type":"user","message":{"content":[{"text":"dummy"}]}}\n' >>"$fpath"
  printf '{"type":"assistant","attributionAgent":"coder","message":{"content":[{"text":"%s"}]}}\n' \
    "$txt" >>"$fpath"
}

# Helper: build payload JSON for a coder sub-agent invocation
# mk_coder_payload <sid> <tool> <agent_id>
# v1.2: includes transcript_path (main session jsonl) so the hook derives project dir
# from it instead of re-encoding cwd.
mk_coder_payload() {
  local sid="$1" tool="$2" aid="$3"
  local tp="$TMP/.claude/projects/$FIXTURE_ENC/$sid.jsonl"
  printf '{"session_id":"%s","tool_name":"%s","cwd":"%s","agent_type":"coder","agent_id":"%s","transcript_path":"%s"}' \
    "$sid" "$tool" "$FIXTURE_CWD" "$aid" "$tp"
}

# -----------------------------------------------------------------------
# Test 1: allow when PATTERN: ADD present + agent_type=coder
SID1="t1"; AID1="agent001"
mk_subagent_jsonl "$SID1" "$AID1" "PATTERN: ADD | tests/foo.py:1 add test"
mk_coder_payload "$SID1" "Edit" "$AID1" \
  | run_hook >"$TMP/o1" 2>&1
RC=$?
if [ "$RC" -eq 0 ] && [ ! -s "$TMP/o1" ]; then
  ok "1: allow PATTERN ADD coder"
else
  bad "1: allow PATTERN ADD coder (rc=$RC out=$(cat "$TMP/o1"))"
fi

# -----------------------------------------------------------------------
# Test 2: block when PATTERN missing + agent_type=coder
SID2="t2"; AID2="agent002"
mk_subagent_jsonl "$SID2" "$AID2" "no pattern here"
mk_coder_payload "$SID2" "Write" "$AID2" \
  | run_hook >"$TMP/o2" 2>&1
if grep -q '"permissionDecision":"deny"' "$TMP/o2"; then
  ok "2: deny PATTERN missing coder"
else
  bad "2: deny PATTERN missing coder (out=$(cat "$TMP/o2"))"
fi

# -----------------------------------------------------------------------
# Test 3: bypass on agent_type != coder (reviewer)
SID3="t3"
printf '{"session_id":"%s","tool_name":"Edit","cwd":"%s","agent_type":"reviewer","agent_id":"arev"}' \
  "$SID3" "$FIXTURE_CWD" \
  | run_hook >"$TMP/o3" 2>&1
if [ ! -s "$TMP/o3" ]; then
  ok "3: bypass non-coder reviewer"
else
  bad "3: bypass non-coder reviewer (out=$(cat "$TMP/o3"))"
fi

# -----------------------------------------------------------------------
# Test 4: bypass when agent_type absent (orchestrator session)
SID4="t4"
printf '{"session_id":"%s","tool_name":"Edit","cwd":"%s"}' \
  "$SID4" "$FIXTURE_CWD" \
  | run_hook >"$TMP/o4" 2>&1
if [ ! -s "$TMP/o4" ]; then
  ok "4: bypass orchestrator (no agent_type)"
else
  bad "4: bypass orchestrator (out=$(cat "$TMP/o4"))"
fi

# -----------------------------------------------------------------------
# Test 5: bypass via env PATTERN_ENFORCE=off
SID5="t5"; AID5="agent005"
mk_subagent_jsonl "$SID5" "$AID5" "no pattern here"
mk_coder_payload "$SID5" "Edit" "$AID5" \
  | env HOME="$TMP" PATTERN_ENFORCE=off PATTERN_ENFORCE_DIR="$TMP/state" bash "$HOOK" >"$TMP/o5" 2>&1
if [ ! -s "$TMP/o5" ]; then
  ok "5: bypass via env PATTERN_ENFORCE=off"
else
  bad "5: bypass via env (out=$(cat "$TMP/o5"))"
fi

# -----------------------------------------------------------------------
# Test 6: bypass via file flag
mkdir -p "$TMP/state"
touch "$TMP/state/disabled"
SID6="t6"; AID6="agent006"
mk_subagent_jsonl "$SID6" "$AID6" "no pattern here"
mk_coder_payload "$SID6" "Edit" "$AID6" \
  | run_hook >"$TMP/o6" 2>&1
rm -f "$TMP/state/disabled"
if [ ! -s "$TMP/o6" ]; then
  ok "6: bypass via file flag"
else
  bad "6: bypass via file flag (out=$(cat "$TMP/o6"))"
fi

# -----------------------------------------------------------------------
# Test 7: fail-open on transcript not found (coder with unknown agent_id)
SID7="t7"
printf '{"session_id":"%s","tool_name":"Edit","cwd":"%s","agent_type":"coder","agent_id":"nonexistent"}' \
  "$SID7" "$FIXTURE_CWD" \
  | run_hook >"$TMP/o7" 2>&1
if [ ! -s "$TMP/o7" ]; then
  ok "7: fail-open transcript not found"
else
  bad "7: fail-open transcript not found (out=$(cat "$TMP/o7"))"
fi

# -----------------------------------------------------------------------
# Test 8: fail-open on malformed JSON stdin
echo "not-json" | run_hook >"$TMP/o8" 2>&1
RC=$?
if [ ! -s "$TMP/o8" ] && [ "$RC" -eq 0 ]; then
  ok "8: fail-open malformed JSON stdin"
else
  bad "8: fail-open malformed JSON (rc=$RC out=$(cat "$TMP/o8"))"
fi

# -----------------------------------------------------------------------
# Test 9: PATTERN regex strict — lowercase pattern must block
SID9="t9"; AID9="agent009"
mk_subagent_jsonl "$SID9" "$AID9" "pattern: add | lowercase"
mk_coder_payload "$SID9" "Edit" "$AID9" \
  | run_hook >"$TMP/o9" 2>&1
if grep -q '"permissionDecision":"deny"' "$TMP/o9"; then
  ok "9: deny lowercase pattern (regex strict)"
else
  bad "9: deny lowercase pattern (out=$(cat "$TMP/o9"))"
fi

# -----------------------------------------------------------------------
# Test 10: performance smoke — must complete in <=2s
SID10="t10"; AID10="agent010"
mk_subagent_jsonl "$SID10" "$AID10" "PATTERN: MODIFY | path:1 smoke"
START=$(date +%s)
mk_coder_payload "$SID10" "Edit" "$AID10" \
  | run_hook >/dev/null 2>&1
END=$(date +%s)
DUR=$((END - START))
if [ "$DUR" -le 2 ]; then
  ok "10: perf <=2s (was ${DUR}s)"
else
  bad "10: perf too slow (${DUR}s)"
fi

# -----------------------------------------------------------------------
# Test 11: path-encoding bug — cwd with underscore, transcript_path already CC-encoded
# with '-' (as Claude Code actually does). Hook must derive project dir from
# transcript_path and find the subagent jsonl (PATTERN present → allow).
# Without the v1.2 fix, the old tr '/' '-' would produce ...-under_score (wrong dir)
# and the hook would fail-open (transcript not found). With v1.2 it must allow/block
# correctly based on PATTERN content, proving the path was found.
SID11="t11"; AID11="agent011"
UNDER_CWD="/test/under_score"
UNDER_ENC="-test-under-score"  # CC encoding: '/' and '_' → '-'
UNDER_DIR="$TMP/.claude/projects/$UNDER_ENC/$SID11/subagents"
mkdir -p "$UNDER_DIR"
UNDER_JSONL="$UNDER_DIR/agent-$AID11.jsonl"
: >"$UNDER_JSONL"
printf '{"type":"assistant","message":{"content":[{"text":"PATTERN: MODIFY | src/app.py:10 fix typo"}]}}\n' \
  >>"$UNDER_JSONL"
UNDER_TP="$TMP/.claude/projects/$UNDER_ENC/$SID11.jsonl"
touch "$UNDER_TP"  # main jsonl must exist for fallback path (not used here)
printf '{"session_id":"%s","tool_name":"Edit","cwd":"%s","agent_type":"coder","agent_id":"%s","transcript_path":"%s"}' \
  "$SID11" "$UNDER_CWD" "$AID11" "$UNDER_TP" \
  | run_hook >"$TMP/o11" 2>&1
RC=$?
# Should allow (PATTERN: MODIFY found), not fail-open silently
if [ "$RC" -eq 0 ] && [ ! -s "$TMP/o11" ]; then
  ok "11: allow coder with underscore-in-cwd via transcript_path encoding"
else
  bad "11: allow coder underscore path (rc=$RC out=$(cat "$TMP/o11"))"
fi

# -----------------------------------------------------------------------
# Test 12: CREATE tolerated as alias of ADD (model emits it for new files).
SID12="t12"; AID12="agent012"
mk_subagent_jsonl "$SID12" "$AID12" "PATTERN: CREATE | tests/test_new.py — Task 5 RED test"
mk_coder_payload "$SID12" "Edit" "$AID12" \
  | run_hook >"$TMP/o12" 2>&1
RC=$?
if [ "$RC" -eq 0 ] && [ ! -s "$TMP/o12" ]; then
  ok "12: allow PATTERN CREATE (alias of ADD)"
else
  bad "12: allow PATTERN CREATE (rc=$RC out=$(cat "$TMP/o12"))"
fi

# -----------------------------------------------------------------------
# Test 13: NEW tolerated as alias of ADD.
SID13="t13"; AID13="agent013"
mk_subagent_jsonl "$SID13" "$AID13" "PATTERN: NEW | foo.py new module"
mk_coder_payload "$SID13" "Edit" "$AID13" \
  | run_hook >"$TMP/o13" 2>&1
RC=$?
if [ "$RC" -eq 0 ] && [ ! -s "$TMP/o13" ]; then
  ok "13: allow PATTERN NEW (alias of ADD)"
else
  bad "13: allow PATTERN NEW (rc=$RC out=$(cat "$TMP/o13"))"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$TMP"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
