#!/bin/bash
# coder-memory-scope.test.sh — offline, hermetic, no network, no real $HOME dependency.
# Bash 3.2 clean. Run: bash coder-memory-scope.test.sh
#
# Covers VCS-057/ADR-0184: coder's `memory: project` write DOES persist across dispatches via
# Step 5's merge-back (measured live in a throwaway scratch repo — artifacts A/B), but a parallel
# fan-out of coder dispatches sharing one `MEMORY.md` produces a real merge conflict (measured
# live, artifact C2). This hook confines coder's memory writes to its own per-dispatch shard
# directory; everything else coder does (ordinary source writes) is unaffected — that asymmetry
# with reviewer-write-scope.sh's whitelist is exactly what CM4 exists to catch.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$SCRIPTS/coder-memory-scope.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

PROJECT="$TMP/project"
SHARD_DIR="$PROJECT/.claude/agent-memory/coder/topics"
CODER_MEM_DIR="$PROJECT/.claude/agent-memory/coder"
OTHER_AGENT_DIR="$PROJECT/.claude/agent-memory/reviewer"
mkdir -p "$SHARD_DIR" "$OTHER_AGENT_DIR" "$PROJECT/src"
SHARD_FILE="$SHARD_DIR/task1-fact.md"
INDEX_FILE="$CODER_MEM_DIR/MEMORY.md"
OTHER_AGENT_FILE="$OTHER_AGENT_DIR/MEMORY.md"
SOURCE_FILE="$PROJECT/src/app.js"
: > "$SHARD_FILE"; : > "$INDEX_FILE"; : > "$OTHER_AGENT_FILE"; : > "$SOURCE_FILE"

# payload <agent_type-or-empty> <file_path> <cwd>
payload() {
  if [ -n "$1" ]; then
    printf '{"session_id":"sess-1","tool_name":"Write","agent_type":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$3" "$2"
  else
    printf '{"session_id":"sess-1","tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s"}}' "$3" "$2"
  fi
}
run() { printf '%s' "$1" | bash "$HOOK" 2>/dev/null; }

# =====================================================================================
# CM1 -- coder writing inside its own shard directory is ALLOWED.
# plant: CM1 | plugin/scripts/coder-memory-scope.sh | "$SHARD_ROOT"/*) | "$SHARD_ROOT"/never-matches/*)
OUT=$(run "$(payload coder "$SHARD_FILE" "$PROJECT")")
if [ -z "$OUT" ]; then
  ok "CM1: coder write inside its own shard directory is allowed (empty stdout)"
else
  bad "CM1: coder write inside its own shard directory was blocked (got: $OUT)"
fi

# =====================================================================================
# CM2 -- coder writing to its own MEMORY.md (the index, outside topics/) is DENIED.
# plant: CM2 | plugin/scripts/coder-memory-scope.sh | SHARD_ROOT=$(normalize "$CWD/.claude/agent-memory/coder/topics") | SHARD_ROOT=$(normalize "$CWD/.claude/agent-memory/coder")
OUT=$(run "$(payload coder "$INDEX_FILE" "$PROJECT")")
if printf '%s' "$OUT" | grep -q '"permissionDecision":[[:space:]]*"deny"'; then
  ok "CM2: coder write to its own MEMORY.md index is denied"
else
  bad "CM2: coder write to its own MEMORY.md index was NOT denied (got: $OUT)"
fi

# =====================================================================================
# CM3 -- coder writing to ANOTHER agent's memory directory is DENIED.
# plant: CM3 | plugin/scripts/coder-memory-scope.sh | "$CWD"/.claude/agent-memory/*|"$CWD"/.claude/agent-memory) | "$CWD"/.claude/agent-memory/coder/*|"$CWD"/.claude/agent-memory/coder)
OUT=$(run "$(payload coder "$OTHER_AGENT_FILE" "$PROJECT")")
if printf '%s' "$OUT" | grep -q '"permissionDecision":[[:space:]]*"deny"'; then
  ok "CM3: coder write to another agent's memory directory is denied"
else
  bad "CM3: coder write to another agent's memory directory was NOT denied (got: $OUT)"
fi

# =====================================================================================
# CM4 -- coder writing an ORDINARY SOURCE FILE is ALLOWED. This is the assertion that stops a
# copy-paste of reviewer's whitelist-shaped guard from shipping here: coder's job is to write
# source, and this hook must be a no-op for anything outside .claude/agent-memory/.
# plant: CM4 | plugin/scripts/coder-memory-scope.sh | log_audit "$SID" "allow" "outside agent-memory, not scoped here: $FILE_PATH" | log_audit "$SID" "deny" "outside agent-memory, not scoped here: $FILE_PATH"; printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"CM4-plant"}}'
OUT=$(run "$(payload coder "$SOURCE_FILE" "$PROJECT")")
if [ -z "$OUT" ]; then
  ok "CM4: coder write to an ordinary source file is allowed (empty stdout)"
else
  bad "CM4: coder write to an ordinary source file was blocked (got: $OUT) -- this would break every real implementation task"
fi

# =====================================================================================
# CM5 -- inertness is structural: a NON-coder agent (reviewer) and the orchestrator (no
# agent_type) writing anywhere, including a path that would be denied for coder, are ALLOWED.
# plant: CM5 | plugin/scripts/coder-memory-scope.sh | [ "$AGENT_TYPE" = "coder" ] || { log_audit "?" "allow" "agent_type=$AGENT_TYPE (not scoped)"; exit 0; } | [ -n "$AGENT_TYPE" ] || { log_audit "?" "allow" "agent_type=$AGENT_TYPE (not scoped)"; exit 0; }
OUT1=$(run "$(payload reviewer "$INDEX_FILE" "$PROJECT")")
OUT2=$(run "$(payload "" "$INDEX_FILE" "$PROJECT")")
if [ -z "$OUT1" ] && [ -z "$OUT2" ]; then
  ok "CM5: a non-coder agent and the orchestrator are unaffected by this guard"
else
  bad "CM5: non-coder/orchestrator write was blocked (reviewer: $OUT1, orchestrator: $OUT2)"
fi

# =====================================================================================
# CM6 -- fail-open on empty tool_input.file_path / empty cwd (malformed payload never blocks).
# plant: CM6 | plugin/scripts/coder-memory-scope.sh | [ -z "$FILE_PATH" ] && { log_audit "$SID" "allow" "no tool_input.file_path"; exit 0; } | [ -z "$FILE_PATH" ] && { log_audit "$SID" "deny" "no tool_input.file_path"; printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"CM6-plant"}}'; exit 0; }
OUT=$(printf '{"session_id":"sess-1","tool_name":"Write","agent_type":"coder","cwd":"%s","tool_input":{}}' "$PROJECT" | bash "$HOOK" 2>/dev/null)
if [ -z "$OUT" ]; then
  ok "CM6: fail-open on empty tool_input.file_path"
else
  bad "CM6: empty tool_input.file_path was blocked instead of failing open (got: $OUT)"
fi

# =====================================================================================
# CM7 -- the escape only a resolving normalize() catches: a symlink planted INSIDE the real shard
# directory pointing OUTSIDE it. The raw path syntactically matches "$SHARD_ROOT"/* (it IS lexically
# under topics/), so a check that trusted the raw string would wrongly allow it; only resolving the
# symlink (pwd -P) reveals the real target escapes SHARD_ROOT and must be denied.
# plant: CM7 | plugin/scripts/coder-memory-scope.sh | _rd=$(cd "$_d" 2>/dev/null && pwd -P 2>/dev/null) | _rd=$(cd "$_d" 2>/dev/null && pwd 2>/dev/null)
LINKDIR="$TMP/linked-elsewhere"
mkdir -p "$LINKDIR"
LINK="$SHARD_DIR/escape-link"
ln -s "$LINKDIR" "$LINK"
OUTSIDE_VIA_LINK="$LINK/escaped.md"
: > "$OUTSIDE_VIA_LINK"
OUT=$(run "$(payload coder "$OUTSIDE_VIA_LINK" "$PROJECT")")
if printf '%s' "$OUT" | grep -q '"permissionDecision":[[:space:]]*"deny"'; then
  ok "CM7: a symlink planted inside the shard pointing outside it is still denied (resolved, not raw)"
else
  bad "CM7: symlink-inside-shard escape was NOT denied (got: $OUT)"
fi

# =====================================================================================
# CM8 -- never exits non-zero (shared contract with reviewer-write-scope.sh / memory-store-guard.sh).
run "$(payload coder "$SOURCE_FILE" "$PROJECT")" >/dev/null
RC=$?
[ "$RC" -eq 0 ] && ok "CM8: hook always exits 0" || bad "CM8: hook exited $RC (must be 0, contract violation)"

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
