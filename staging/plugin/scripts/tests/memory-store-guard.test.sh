#!/bin/bash
# memory-store-guard.test.sh — offline, hermetic, no network, no real $HOME dependency (a scratch
# HOME is created per run; nothing under the real ~/.claude is touched or read).
# Bash 3.2 clean. Run: bash memory-store-guard.test.sh
#
# Covers VCS-055 Phase 2.1 / ADR-0038 Correction 2026-08-30: the guard that must exist BEFORE any
# native `memory:` re-pilot, because ADR-0013's 2026-05-25 pilot failed exactly this way — a
# sub-agent given broad Write access by `memory:` edited a file outside its own memory directory,
# specifically the orchestrator's own curated auto-memory. Three invariants, both directions
# (rule 8): a sub-agent write INTO the store is denied, an orchestrator write to the SAME path is
# allowed, and a sub-agent write ANYWHERE ELSE is allowed (inertness is structural, not a
# path-specific carve-out).
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$SCRIPTS/memory-store-guard.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SCRATCH_HOME="$TMP/home"
STORE="$SCRATCH_HOME/.claude/projects/-some-project/memory"
OTHER_DIR="$TMP/agent-memory/coder"
mkdir -p "$STORE" "$OTHER_DIR"
STORE_FILE="$STORE/reference_something.md"
OTHER_FILE="$OTHER_DIR/MEMORY.md"
: > "$STORE_FILE"; : > "$OTHER_FILE"

# payload <agent_id-or-empty> <file_path>
payload() {
  if [ -n "$1" ]; then
    printf '{"session_id":"sess-1","tool_name":"Write","agent_id":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"
  else
    printf '{"session_id":"sess-1","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$2"
  fi
}
run() { printf '%s' "$1" | HOME="$SCRATCH_HOME" MEMORY_GUARD_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }

# =====================================================================================
# G1 -- a sub-agent writing into the curated auto-memory store is DENIED.
# plant: G1 | plugin/scripts/memory-store-guard.sh | "$STORE_ROOT"/*/memory/*) | "$STORE_ROOT"/*/memory-never-matches/*)
OUT=$(run "$(payload aaa "$STORE_FILE")")
if printf '%s' "$OUT" | grep -q '"permissionDecision":[[:space:]]*"deny"'; then
  ok "G1: sub-agent write into the curated auto-memory store is denied"
else
  bad "G1: sub-agent write into the store was NOT denied (got: $OUT)"
fi

# =====================================================================================
# G2 -- an orchestrator write (no agent_id) to the SAME path is ALLOWED.
# plant: G2 | plugin/scripts/memory-store-guard.sh | [ -z "$AGENT_ID" ] && { log_audit "$SID" "allow" "no agent_id (orchestrator, not a subagent)"; exit 0; } | [ -z "$AGENT_ID" ] && { log_audit "$SID" "allow" "no agent_id (orchestrator, not a subagent)"; }
OUT=$(run "$(payload "" "$STORE_FILE")")
if [ -z "$OUT" ]; then
  ok "G2: orchestrator write to the same store path is allowed (empty stdout)"
else
  bad "G2: orchestrator write to the store path was blocked or produced output (got: $OUT)"
fi

# =====================================================================================
# G3 -- a sub-agent write ANYWHERE ELSE (its own memory directory) is ALLOWED. Inertness must be
# structural, not a hardcoded carve-out for one path.
# plant: G3 | plugin/scripts/memory-store-guard.sh | case "$GOT" in "$STORE_ROOT"/*/memory/*) | case "$GOT" in *)
OUT=$(run "$(payload aaa "$OTHER_FILE")")
if [ -z "$OUT" ]; then
  ok "G3: sub-agent write to its own memory directory is allowed (empty stdout)"
else
  bad "G3: sub-agent write outside the store was blocked (got: $OUT)"
fi

# =====================================================================================
# G4 -- never exits non-zero (contract line shared with write-scope-enforce.sh): a broken guard
# must fail OPEN, never block the harness that dispatches it.
run "$(payload aaa "$STORE_FILE")" >/dev/null
RC=$?
[ "$RC" -eq 0 ] && ok "G4: hook always exits 0" || bad "G4: hook exited $RC (must be 0, contract violation)"

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
