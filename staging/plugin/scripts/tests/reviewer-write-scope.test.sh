#!/bin/bash
# reviewer-write-scope.test.sh — offline, hermetic, no network, no real $HOME dependency.
# Bash 3.2 clean. Run: bash reviewer-write-scope.test.sh
#
# Covers VCS-055 Phase 2.3 / ADR-0182: reviewer's `memory: project` grant carries broad,
# path-unscoped Edit/Write at the raw tool-schema level (confirmed live 2026-08-30) — exactly
# ADR-0013's 2026-05-25 failure mode. This hook confines reviewer to its own native memory
# directory; everything else, including source files and other agents' memory, is denied.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$SCRIPTS/reviewer-write-scope.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

PROJECT="$TMP/project"
OWN_DIR="$PROJECT/.claude/agent-memory/reviewer"
OTHER_AGENT_DIR="$PROJECT/.claude/agent-memory/coder"
mkdir -p "$OWN_DIR" "$OTHER_AGENT_DIR" "$PROJECT/src"
OWN_FILE="$OWN_DIR/MEMORY.md"
OTHER_AGENT_FILE="$OTHER_AGENT_DIR/MEMORY.md"
SOURCE_FILE="$PROJECT/src/app.js"
: > "$OWN_FILE"; : > "$OTHER_AGENT_FILE"; : > "$SOURCE_FILE"

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
# R1 -- reviewer writing inside its own memory directory is ALLOWED.
# plant: R1 | plugin/scripts/reviewer-write-scope.sh | "$ALLOWED_ROOT"/*|"$ALLOWED_ROOT") | "$ALLOWED_ROOT"/never-matches/*)
OUT=$(run "$(payload reviewer "$OWN_FILE" "$PROJECT")")
if [ -z "$OUT" ]; then
  ok "R1: reviewer write inside its own memory directory is allowed (empty stdout)"
else
  bad "R1: reviewer write inside its own memory directory was blocked (got: $OUT)"
fi

# =====================================================================================
# R2 -- reviewer writing to a SOURCE file is DENIED.
# plant: R2 | plugin/scripts/reviewer-write-scope.sh | [ "$AGENT_TYPE" = "reviewer" ] || { log_audit "?" "allow" "agent_type=$AGENT_TYPE (not scoped)"; exit 0; } | [ "$AGENT_TYPE" = "reviewer-never-matches" ] || { log_audit "?" "allow" "agent_type=$AGENT_TYPE (not scoped)"; exit 0; }
OUT=$(run "$(payload reviewer "$SOURCE_FILE" "$PROJECT")")
if printf '%s' "$OUT" | grep -q '"permissionDecision":[[:space:]]*"deny"'; then
  ok "R2: reviewer write to a source file is denied"
else
  bad "R2: reviewer write to a source file was NOT denied (got: $OUT)"
fi

# =====================================================================================
# R3 -- reviewer writing to ANOTHER agent's memory directory is DENIED.
OUT=$(run "$(payload reviewer "$OTHER_AGENT_FILE" "$PROJECT")")
if printf '%s' "$OUT" | grep -q '"permissionDecision":[[:space:]]*"deny"'; then
  ok "R3: reviewer write to another agent's memory directory is denied"
else
  bad "R3: reviewer write to another agent's memory directory was NOT denied (got: $OUT)"
fi

# =====================================================================================
# R4 -- a NON-reviewer agent (e.g. coder) writing anywhere is ALLOWED — inertness is structural,
# not a reviewer-specific carve-out that happens to also catch everyone else.
OUT=$(run "$(payload coder "$SOURCE_FILE" "$PROJECT")")
if [ -z "$OUT" ]; then
  ok "R4: a non-reviewer agent's write is allowed (empty stdout)"
else
  bad "R4: a non-reviewer agent's write was blocked (got: $OUT)"
fi

# =====================================================================================
# R5 -- the orchestrator (no agent_type) writing anywhere is ALLOWED.
OUT=$(run "$(payload "" "$SOURCE_FILE" "$PROJECT")")
if [ -z "$OUT" ]; then
  ok "R5: orchestrator write (no agent_type) is allowed (empty stdout)"
else
  bad "R5: orchestrator write was blocked (got: $OUT)"
fi

# =====================================================================================
# R6 -- never exits non-zero (shared contract with write-scope-enforce.sh / memory-store-guard.sh):
# a broken guard must fail OPEN, never block the harness that dispatches it.
run "$(payload reviewer "$SOURCE_FILE" "$PROJECT")" >/dev/null
RC=$?
[ "$RC" -eq 0 ] && ok "R6: hook always exits 0" || bad "R6: hook exited $RC (must be 0, contract violation)"

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
