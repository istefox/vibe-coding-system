#!/bin/bash
# write-scope-enforce.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash write-scope-enforce.test.sh
#
# Covers issue #87: the PreToolUse hook that ENFORCES what ADR-0016 Addendum 2026-07-25c could
# only instruct. Step 6 Phase 3 fix agents run in parallel, one file each; the prompt tells them
# to edit only their assigned file, and this hook makes that true rather than hoped for.
#
# Every mechanism below was verified live on 2026-07-25 (issue #87), not assumed:
#   - PreToolUse fires inside workflow subagents on the current build;
#   - .agent_id discriminates parallel same-type agents (.agent_type cannot);
#   - the dispatch prompt lands in the subagent transcript as exactly one `user` entry,
#     not echoed by the assistant.
#
# The marker deliberately excludes the em-dash in "WRITE SCOPE — you may edit ONLY". An em-dash
# instead of a pipe is what silently invalidated the smoke test's control arm; matching on the
# ASCII tail removes any dependence on how the dash survives transcript encoding.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
HOOK="$SCRIPTS/write-scope-enforce.sh"
CC_SKILL="$STAGING/plugin/skills/concept-to-code/SKILL.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SID="sess-1"
PROJ="$TMP/proj"
ASSIGNED="$TMP/work/assigned.txt"
OTHER="$TMP/work/other.txt"
mkdir -p "$PROJ/$SID/subagents" "$PROJ/$SID/subagents/workflows/wf_x" "$TMP/work"
: > "$ASSIGNED"; : > "$OTHER"
TP="$PROJ/$SID.jsonl"
printf '{"type":"user","message":{"role":"user","content":"orchestrator turn"}}\n' > "$TP"

# A scoped prompt exactly as Step 6 Phase 3 emits it: the path, then a period, then more prose.
# Extraction has to survive that trailing punctuation.
scoped_line() {
  printf '{"type":"user","message":{"role":"user","content":"WRITE SCOPE - you may edit ONLY %s. Other agents are fixing other files in parallel right now."}}\n' "$1"
}
printf '%s' "$(scoped_line "$ASSIGNED")" > "$PROJ/$SID/subagents/agent-aaa.jsonl"
printf '\n{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]}}\n' >> "$PROJ/$SID/subagents/agent-aaa.jsonl"
printf '{"type":"user","message":{"role":"user","content":"no scope line here, just a task"}}\n' > "$PROJ/$SID/subagents/agent-bbb.jsonl"
printf '%s' "$(scoped_line "$ASSIGNED")" > "$PROJ/$SID/subagents/workflows/wf_x/agent-ccc.jsonl"

# payload <agent_id> <file_path>
payload() {
  printf '{"session_id":"%s","tool_name":"Edit","cwd":"%s","agent_type":"coder","agent_id":"%s","transcript_path":"%s","tool_input":{"file_path":"%s"}}' \
    "$SID" "$TMP" "$1" "$TP" "$2"
}
run() { printf '%s' "$1" | WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }

# =====================================================================================
# A. The two decisions that matter.
OUT=$(run "$(payload aaa "$ASSIGNED")")
if [ -z "$OUT" ]; then
  ok "A1: edit to the assigned file is allowed (empty stdout)"
else
  bad "A1: assigned file was not allowed — got: $OUT"
fi

OUT=$(run "$(payload aaa "$OTHER")")
# jq pretty-prints, so match on the parsed value rather than a substring.
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  ok "A2: edit outside the assigned file is denied"
else
  bad "A2: out-of-scope edit was not denied — got: $OUT"
fi

# A3: the deny must be valid JSON carrying the verified enum. ADR-0034 corrected "block" to
# "deny" precisely because an unrecognised value fails open — silently, and in the direction
# that defeats the guardrail.
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  ok "A3: deny payload is valid JSON with permissionDecision=deny"
else
  bad "A3: deny payload malformed or wrong enum value"
fi

# A4: the reason must route the agent to `deferred`, not leave it guessing. A denied write with
# no instruction is how an agent starts inventing workarounds.
if printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason' 2>/dev/null | grep -q 'deferred'; then
  ok "A4: deny reason tells the agent to record the change in deferred"
else
  bad "A4: deny reason does not mention deferred"
fi

# =====================================================================================
# B. Every failure mode allows. A write-scope guard that breaks unrelated edits is worse than
# no guard: it would be disabled within a day.
OUT=$(run "$(payload bbb "$OTHER")")
[ -z "$OUT" ] && ok "B1: no WRITE SCOPE line in the transcript -> allow (hook stays inert)" \
              || bad "B1: denied an agent that was never scoped — got: $OUT"

OUT=$(printf '{"session_id":"%s","tool_name":"Edit","transcript_path":"%s","tool_input":{"file_path":"%s"}}' "$SID" "$TP" "$OTHER" | WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "B2: no agent_id (orchestrator, not a subagent) -> allow" \
              || bad "B2: denied a call with no agent_id — got: $OUT"

OUT=$(run "$(payload zzz "$OTHER")")
[ -z "$OUT" ] && ok "B3: transcript not found -> allow (fail-open, as pattern-enforce does)" \
              || bad "B3: denied on a missing transcript — got: $OUT"

OUT=$(printf 'not json at all' | WRITE_SCOPE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null)
[ -z "$OUT" ] && ok "B4: malformed JSON on stdin -> allow" \
              || bad "B4: denied on malformed input — got: $OUT"

# B5: the main-session transcript must NOT be used as a fallback. pattern-enforce does fall back
# to it, but for this hook that would be actively wrong: an orchestrator turn quoting a scope
# line could then deny unrelated edits session-wide. Agent ddd has no subagent transcript, and
# the main one at $TP carries no scope line — so this also guards the fallback staying absent.
printf '{"type":"user","message":{"role":"user","content":"WRITE SCOPE - you may edit ONLY %s. quoted by the orchestrator"}}\n' "$ASSIGNED" >> "$TP"
OUT=$(run "$(payload ddd "$OTHER")")
[ -z "$OUT" ] && ok "B5: a scope line in the MAIN transcript never binds a subagent -> allow" \
              || bad "B5: main-session transcript leaked into the scope decision — got: $OUT"

# =====================================================================================
# C. Workflow subagents — the whole point. Their transcripts live at
# subagents/workflows/<wf_id>/agent-<id>.jsonl, a path CC introduced silently in v2.1.154 and
# re-confirmed on the current build in the #87 smoke test.
OUT=$(run "$(payload ccc "$OTHER")")
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  ok "C1: workflow-subagent transcript found via the find fallback, deny works there"
else
  bad "C1: workflow-path transcript not located — the find fallback is broken: $OUT"
fi

OUT=$(run "$(payload ccc "$ASSIGNED")")
[ -z "$OUT" ] && ok "C2: workflow subagent editing its assigned file is allowed" \
              || bad "C2: workflow subagent wrongly denied — got: $OUT"

# =====================================================================================
# D. Coupling. SKILL.md's prompt and this hook must agree on the marker; reword one and the hook
# goes silently inert while every test above still passes. Same class of hazard as the FIX_EFFORT
# table, which is why that one is pinned too.
if grep -q 'you may edit ONLY' "$HOOK" && grep -q 'you may edit ONLY' "$CC_SKILL"; then
  ok "D1: the marker string is identical in the hook and in SKILL.md's Phase 3 prompt"
else
  bad "D1: marker missing from the hook or from SKILL.md — the hook would be inert"
fi

# D2: the prompt must tell the agent what a denial means, or a blocked write leaves it somewhere
# its instructions never described.
if grep -q 'record it in `deferred`' "$CC_SKILL"; then
  ok "D2: SKILL.md tells the agent a write-scope denial means record it in deferred"
else
  bad "D2: SKILL.md does not explain what a write-scope denial means"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
