#!/bin/bash
# reviewer-write-scope v1.0 — PreToolUse gate confining reviewer's Edit/Write to its own native
# memory directory (VCS-055 Phase 2.3, ADR-0182).
#
# Why it exists: reviewer.md's declared `tools:` frontmatter carries no Edit/Write at all — the
# agent is meant to report findings, never apply them (issue #58, ADR-0045). Adding `memory:
# project` to run native memory (ADR-0182) grants Edit/Write at the raw tool-schema level with NO
# path restriction (confirmed live 2026-08-30: a diagnostic reviewer dispatch under `memory:
# project` reported both tools present, file_path unconstrained). That is exactly ADR-0013's
# 2026-05-25 failure mode — a `memory:`-granted agent using broad Write access to edit outside its
# intended directory — now reachable through reviewer specifically. This hook makes it impossible:
# reviewer may write only under its own `.claude/agent-memory/reviewer/` tree; everything else is
# denied, including source files, the orchestrator's curated store (already covered by
# `memory-store-guard.sh`, but reviewer never had legitimate business there either), and any other
# agent's memory directory.
#
# Contract: exit 0 + empty stdout = allow. exit 0 + {"hookSpecificOutput":{...,"deny"}} = deny.
# NEVER exits non-zero — same contract as write-scope-enforce.sh and memory-store-guard.sh: a
# guard that breaks unrelated edits gets disabled within a day, which is worse than no guard.
#
# INERTNESS IS STRUCTURAL: gated on `.agent_type == "reviewer"` (the same field
# agent-command-scope.sh already uses to scope architect/reviewer) — every other agent, and the
# orchestrator itself (no `.agent_type` in its own tool calls), is unaffected regardless of path.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution.

DIR="${REVIEWER_WRITE_SCOPE_DIR:-$HOME/.claude/state/reviewer-write-scope}"
LOG="$DIR/audit.log"
mkdir -p "$DIR" 2>/dev/null || true

log_audit() {
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >>"$LOG" 2>/dev/null || true
}

# Resolve a path to its physical form when the parent exists; otherwise leave it as-is.
# Never fails, never invents a path. Same helper as write-scope-enforce.sh / memory-store-guard.sh.
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

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)

# Inert for every agent except reviewer, and for the orchestrator (empty agent_type).
[ "$AGENT_TYPE" = "reviewer" ] || { log_audit "?" "allow" "agent_type=$AGENT_TYPE (not scoped)"; exit 0; }

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

[ -z "$FILE_PATH" ] && { log_audit "$SID" "allow" "no tool_input.file_path"; exit 0; }
[ -z "$CWD" ] && { log_audit "$SID" "allow" "no cwd"; exit 0; }

ALLOWED_ROOT=$(normalize "$CWD/.claude/agent-memory/reviewer")
GOT=$(normalize "$FILE_PATH")

[ -z "$ALLOWED_ROOT" ] && { log_audit "$SID" "allow" "allowed root empty after normalize"; exit 0; }
[ -z "$GOT" ] && { log_audit "$SID" "allow" "target path empty after normalize"; exit 0; }

case "$GOT" in
  "$ALLOWED_ROOT"/*|"$ALLOWED_ROOT")
    log_audit "$SID" "allow" "in scope: $GOT"
    exit 0
    ;;
  *)
    log_audit "$SID" "deny" "target=$GOT allowed_root=$ALLOWED_ROOT"
    REASON="reviewer-write-scope: reviewer may write only inside its own memory directory ($ALLOWED_ROOT) — this call targets $GOT. Reviewer reports findings, it does not apply changes (ADR-0045) or write anywhere else. Do NOT retry and do NOT work around this: put the change in your report and let the orchestrator act on it."
    printf '%s' "$REASON" | jq -R -s \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}' 2>/dev/null \
      || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"reviewer-write-scope: write outside reviewer'"'"'s own memory directory is denied (VCS-055 Phase 2.3, ADR-0182)"}}\n'
    exit 0
    ;;
esac
