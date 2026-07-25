#!/bin/bash
# write-scope-enforce v1.0 — PreToolUse gate for parallel fix agents (issue #87, ADR-0016
# Addendum 2026-07-25d). Denies Edit/Write/MultiEdit outside the file the agent was assigned.
#
# Why it exists: concept-to-code Step 6 Phase 3 dispatches fix agents in parallel, one file each.
# Phase 2's by-file grouping bounds where the FINDINGS are, not where the EDITS land — an agent
# fixing an import can write a file that was nobody's assigned file, and two agents then collide
# on it. #86 forbade that in the prompt; ADR-0016 Addendum 2026-07-25c recorded that a prompt is
# an instruction, not an enforcement. This is the enforcement.
#
# Contract: exit 0 + empty stdout = allow. exit 0 + {"hookSpecificOutput":{...,"deny"}} = deny.
# NEVER exits non-zero. Every failure mode allows: a write-scope guard that breaks unrelated
# edits would be disabled within a day, which is strictly worse than no guard.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution.
#
# Mechanism, each link verified live on 2026-07-25 rather than assumed (issue #87):
#   - PreToolUse fires inside workflow subagents on the current build (three-arm smoke test).
#   - .agent_id is in the payload and discriminates parallel same-type agents; .agent_type
#     cannot, since Phase 3 can dispatch three `coder` agents at once with three different files.
#   - The dispatch prompt lands in the subagent's own transcript as exactly one `user` entry,
#     and is NOT echoed back by the assistant — so reading it is structural, not a bet on
#     model behaviour.
#
# INERTNESS IS STRUCTURAL. No "you may edit ONLY" line in the agent's transcript means the agent
# was never scoped, so the hook allows and exits. Step 5, the Agent-tool fallback path, and every
# other skill are untouched — no manifest flag, no skill detection, nothing to configure. That is
# what makes it safe to wire globally.
#
# The marker matched below deliberately omits the em-dash in "WRITE SCOPE — you may edit ONLY".
# An em-dash where a pipe was expected is what silently invalidated the #87 smoke test's control
# arm; matching the ASCII tail removes any dependence on how that dash survives encoding.
# If SKILL.md's Phase 3 prompt is reworded, this hook goes silently inert — pinned by
# write-scope-enforce.test.sh D1.

DIR="${WRITE_SCOPE_DIR:-$HOME/.claude/state/write-scope}"
LOG="$DIR/audit.log"
mkdir -p "$DIR" 2>/dev/null || true

log_audit() {
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >>"$LOG" 2>/dev/null || true
}

# Resolve a path to its physical form when the parent exists; otherwise leave it as-is.
# Never fails, never invents a path.
normalize() {
  _p="$1"
  [ -z "$_p" ] && return 0
  _d=$(dirname "$_p" 2>/dev/null)
  _b=$(basename "$_p" 2>/dev/null)
  if [ -n "$_d" ] && [ -d "$_d" ]; then
    _rd=$(cd "$_d" 2>/dev/null && pwd -P 2>/dev/null)
    [ -n "$_rd" ] && { printf '%s/%s' "$_rd" "$_b"; return 0; }
  fi
  printf '%s' "$_p"
}

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || { log_audit "?" "allow" "jq missing"; exit 0; }

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && { log_audit "?" "allow" "no session_id (malformed or empty JSON)"; exit 0; }

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)
TP=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Not a subagent, or nothing to decide about.
[ -z "$AGENT_ID" ] && { log_audit "$SID" "allow" "no agent_id (orchestrator, not a subagent)"; exit 0; }
[ -z "$FILE_PATH" ] && { log_audit "$SID" "allow" "no tool_input.file_path"; exit 0; }
[ -z "$TP" ] && { log_audit "$SID" "allow" "no transcript_path"; exit 0; }

# Locate the subagent's OWN transcript. Same two candidates as pre-flight-pattern-enforce.sh
# v1.3 — regular subagent, then the workflows/<wf_id>/ path CC introduced silently in v2.1.154.
PROJ_DIR=$(dirname "$TP")
TRANSCRIPT=""
CAND="$PROJ_DIR/$SID/subagents/agent-$AGENT_ID.jsonl"
[ -f "$CAND" ] && TRANSCRIPT="$CAND"

if [ -z "$TRANSCRIPT" ]; then
  WORKFLOWS_DIR="$PROJ_DIR/$SID/subagents/workflows"
  if [ -d "$WORKFLOWS_DIR" ]; then
    WF_CAND=$(find "$WORKFLOWS_DIR" -name "agent-$AGENT_ID.jsonl" 2>/dev/null | head -1)
    [ -n "$WF_CAND" ] && [ -f "$WF_CAND" ] && TRANSCRIPT="$WF_CAND"
  fi
fi

# DELIBERATELY NO main-session fallback, unlike pre-flight-pattern-enforce.sh. That hook falls
# back to the main jsonl because a missing marker there is merely a missed check. Here it would
# be actively wrong: an orchestrator turn that happens to quote a scope line would bind every
# subsequent edit in the session. Pinned by write-scope-enforce.test.sh B5.
[ -z "$TRANSCRIPT" ] && { log_audit "$SID" "allow" "no subagent transcript (agent_id=$AGENT_ID)"; exit 0; }

# The scope line lives in a `user` entry (the dispatch prompt). tostring rather than a structured
# read, because message.content is a string in some entries and an array in others.
SCOPE=$(jq -r 'select(.type=="user") | tostring' "$TRANSCRIPT" 2>/dev/null \
  | grep -o 'you may edit ONLY [^ "\\]*' 2>/dev/null | head -1 | sed 's/^you may edit ONLY //')
SCOPE="${SCOPE%.}"

# Not a scoped agent → allow. This is the inertness path, and it is the common case.
[ -z "$SCOPE" ] && { log_audit "$SID" "allow" "no write-scope line (agent not scoped)"; exit 0; }

WANT=$(normalize "$SCOPE")
GOT=$(normalize "$FILE_PATH")

# Allow on ambiguity: if either side would not resolve, do not guess.
[ -z "$WANT" ] && { log_audit "$SID" "allow" "scope path empty after normalize"; exit 0; }
[ -z "$GOT" ] && { log_audit "$SID" "allow" "target path empty after normalize"; exit 0; }

if [ "$WANT" = "$GOT" ]; then
  log_audit "$SID" "allow" "in scope: $GOT"
  exit 0
fi

log_audit "$SID" "deny" "$TOOL out of scope: wanted=$WANT got=$GOT"

REASON="write-scope-enforce: you may edit ONLY $SCOPE — this call targets $FILE_PATH. Other fix agents are editing other files in parallel and your write would risk losing their work. Do NOT retry and do NOT work around this: record the needed change in \"deferred\" (file + what change and why) and continue with your own file. A deferred entry is the correct outcome, not a failure."

printf '%s' "$REASON" | jq -R -s \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"write-scope-enforce: edit outside the assigned file; record it in deferred (see ADR-0016 Addendum 2026-07-25d)"}}\n'
exit 0
