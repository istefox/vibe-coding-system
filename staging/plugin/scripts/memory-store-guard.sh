#!/bin/bash
# memory-store-guard v1.0 — PreToolUse gate protecting the orchestrator's curated auto-memory
# store from sub-agent writes (VCS-055 Phase 2, ADR-0038 Correction 2026-08-30).
#
# Why it exists: ADR-0013's 2026-05-25 pilot of native `memory:` on architect failed because the
# dispatched agent, given broad Write access by `memory:`, edited a file OUTSIDE its own memory
# directory — the orchestrator's own curated auto-memory
# (~/.claude/projects/<project>/memory/reference_cc-capabilities-research-2026-05.md). That is
# the exact failure this hook exists to make structurally impossible before any re-pilot of
# native memory (`reviewer`, `memory: project`, VCS-055 Phase 2.2) is run for real.
#
# Contract: exit 0 + empty stdout = allow. exit 0 + {"hookSpecificOutput":{...,"deny"}} = deny.
# NEVER exits non-zero — same contract as write-scope-enforce.sh (ADR-0016 Addendum 2026-07-25d):
# a guard that breaks unrelated edits gets disabled within a day, which is worse than no guard.
#
# Rule: if `.agent_id` is present (a sub-agent, not the orchestrator) AND the resolved target path
# is under `~/.claude/projects/*/memory/`, deny. Orchestrator writes to that same tree — the
# curated auto-memory this system actively relies on — are untouched: the `.agent_id` early bail
# is load-bearing, not an optimisation, exactly as in write-scope-enforce.sh.
#
# INERTNESS IS STRUCTURAL: no `.agent_id` in the payload, no gate, regardless of path. A sub-agent
# writing to ITS OWN memory directory (`.claude/agent-memory/<name>/` or
# `.claude/agent-memory-local/<name>/`, both project-relative, never under `~/.claude/projects/`)
# is unaffected — that is the mechanism this hook is meant to let run, not block.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution.

DIR="${MEMORY_GUARD_DIR:-$HOME/.claude/state/memory-store-guard}"
LOG="$DIR/audit.log"
mkdir -p "$DIR" 2>/dev/null || true

log_audit() {
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >>"$LOG" 2>/dev/null || true
}

# Resolve a path to its physical form when the parent exists; otherwise leave it as-is.
# Never fails, never invents a path. Same helper as write-scope-enforce.sh.
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

AGENT_ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)

# Not a sub-agent — the common case, and the one this hook must never touch: the orchestrator's
# own curated auto-memory writes go through here untouched.
[ -z "$AGENT_ID" ] && { log_audit "$SID" "allow" "no agent_id (orchestrator, not a subagent)"; exit 0; }

FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$FILE_PATH" ] && { log_audit "$SID" "allow" "no tool_input.file_path"; exit 0; }

# The store root. $HOME resolves once per process; a sub-agent's HOME is the same as the
# orchestrator's (no sandboxing changes it), so this is a stable, non-guessable anchor.
STORE_ROOT=$(normalize "$HOME/.claude/projects")
GOT=$(normalize "$FILE_PATH")

[ -z "$STORE_ROOT" ] && { log_audit "$SID" "allow" "store root empty after normalize"; exit 0; }
[ -z "$GOT" ] && { log_audit "$SID" "allow" "target path empty after normalize"; exit 0; }

# Match ~/.claude/projects/<anything>/memory/<anything> specifically — not the whole projects
# tree (which also holds transcripts, agent-notes written by write-scope-enforce's own ADR-0012
# mechanism target, etc.). Only the curated auto-memory subtree is protected.
case "$GOT" in
  "$STORE_ROOT"/*/memory/*)
    log_audit "$SID" "deny" "agent_id=$AGENT_ID target=$GOT"
    REASON="memory-store-guard: sub-agents may not write into the orchestrator's curated auto-memory store ($GOT). This is the failure mode ADR-0013's 2026-05-25 pilot hit — write to your OWN memory directory (.claude/agent-memory/<name>/ or .claude/agent-memory-local/<name>/) instead. Do NOT retry and do NOT work around this."
    printf '%s' "$REASON" | jq -R -s \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}' 2>/dev/null \
      || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"memory-store-guard: sub-agent write into the curated auto-memory store is denied (ADR-0038 Correction 2026-08-30, VCS-055 Phase 2)"}}\n'
    exit 0
    ;;
  *)
    log_audit "$SID" "allow" "outside store: $GOT"
    exit 0
    ;;
esac
