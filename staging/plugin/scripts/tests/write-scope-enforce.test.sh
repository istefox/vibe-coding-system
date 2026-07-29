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

# =====================================================================================
# E. SELF-ARMING (issue #127). The marker is both an instruction and a trigger, so any transcript
# that QUOTES it looks exactly like a transcript that was SCOPED by it.
#
# Hit live on 2026-07-26: the architect on issue #103 was briefed to read this hook's own source,
# the literal grep pattern landed in its transcript as a tool result, and the extraction bound the
# agent to the scope `[^`. Writes before the read were allowed; every write after was denied. The
# audit log recorded `wanted=/users/.../[^`. The same arming happens for any agent that reads
# concept-to-code's Phase 3 prompt, which carries the marker verbatim.
#
# Tool results are `user` entries. That is the whole mechanism: a full scan of `user` entries
# cannot tell the dispatch prompt from a file the agent read. The fix is structural rather than a
# smarter pattern — the dispatch prompt is the FIRST `user` entry and a tool result never is.
SELF_ARM="$PROJ/$SID/subagents/agent-eee.jsonl"
printf '{"type":"user","message":{"role":"user","content":"Audit the hook and report. You are not scoped."}}\n' > "$SELF_ARM"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"reading it"}]}}\n' >> "$SELF_ARM"
# The tool result, verbatim as the incident produced it: the hook's own extraction line.
printf '{"type":"user","message":{"role":"user","content":"[tool_result] SCOPE=$(jq -r ... | grep -o '"'"'you may edit ONLY [^ \\"\\\\]*'"'"' | head -1)"}}\n' >> "$SELF_ARM"

# E0: the fixture has to actually exercise the bug, or E1 proves nothing (rule 6 of
# .claude/context.md — an assertion that passes is not evidence until it has been seen RED).
# This runs the PRE-FIX extraction — the same pipeline without `head -1` — and requires it to
# come back armed. If a future edit to the fixture stops arming it, this fails and says so.
PREFIX_SCOPE=$(jq -r 'select(.type=="user") | tostring' "$SELF_ARM" 2>/dev/null \
  | grep -o 'you may edit ONLY [^ "\\]*' 2>/dev/null | head -1 | sed 's/^you may edit ONLY //')
if [ -n "$PREFIX_SCOPE" ]; then
  ok "E0: the fixture DOES arm the pre-fix full-scan extraction (scope='$PREFIX_SCOPE') — discriminating"
else
  bad "E0: the fixture no longer reproduces the self-arming bug — E1 below would pass vacuously"
fi

# E1: the acceptance criterion. A tool result carrying the marker must not arm the hook.
OUT=$(run "$(payload eee "$OTHER")")
[ -z "$OUT" ] && ok "E1: a marker inside a TOOL RESULT does not arm the hook -> allow" \
              || bad "E1: self-armed on a tool result — this is issue #127 — got: $OUT"

# E2: the positive twin (rule 8). A guard that reads only the first entry could equally be a hook
# that reads nothing; E1 alone cannot tell those apart. The dispatch prompt must still bind, and
# it must still bind to ITS path when a later tool result names a different one.
DECOY="$TMP/work/decoy.txt"
: > "$DECOY"
BOTH="$PROJ/$SID/subagents/agent-fff.jsonl"
printf '%s' "$(scoped_line "$ASSIGNED")" > "$BOTH"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"reading SKILL.md"}]}}\n' >> "$BOTH"
printf '{"type":"user","message":{"role":"user","content":"[tool_result] WRITE SCOPE - you may edit ONLY %s. (quoted from the skill file)"}}\n' "$DECOY" >> "$BOTH"

OUT=$(run "$(payload fff "$ASSIGNED")")
[ -z "$OUT" ] && ok "E2: the FIRST user entry still arms the hook — its own file stays allowed" \
              || bad "E2: the dispatch prompt stopped binding — the fix broke the feature: $OUT"

OUT=$(run "$(payload fff "$DECOY")")
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  ok "E3: a path named in a later tool result does NOT become the scope — still denied"
else
  bad "E3: a quoted path overrode the dispatch prompt's scope — got: $OUT"
fi

# E4: coupling, the same hazard D1 covers for the marker. The `head -1` IMMEDIATELY AFTER the jq
# and BEFORE the grep is the fix. The pipeline ends with a second `head -1` that has nothing to do
# with it, so this must anchor on position, not on the string — a first draft that merely grepped
# the neighbourhood passed against a reconstructed pre-fix hook and would have pinned nothing.
# The line ITSELF must be the head -1 stage, not merely contain the string: the grep stage that
# follows ends in `| head -1 | sed ...`, so a substring test matches a pre-fix hook too. A first
# draft did exactly that and passed against a reconstructed pre-fix copy — pinning nothing.
_after_jq=$(grep -A1 'select(.type=="user") | tostring' "$HOOK" | tail -1 | sed 's/^[[:space:]]*//')
case "$_after_jq" in
  "| head -1"*) ok "E4: the first-entry guard (head -1) is the stage directly after the jq read" ;;
  *) bad "E4: no head -1 between the jq and the grep — the hook can self-arm again (#127)" ;;
esac

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
