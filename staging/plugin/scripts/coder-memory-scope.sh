#!/bin/bash
# coder-memory-scope v1.0 — PreToolUse gate confining coder's memory writes to per-dispatch shard
# files (VCS-057, ADR-0184).
#
# Why it exists, and why its logic is INVERTED relative to reviewer-write-scope.sh: reviewer has no
# Edit/Write at all in its `tools:` frontmatter, so ADR-0182's guard is a whitelist confining it
# entirely inside `.claude/agent-memory/reviewer/`. coder is the opposite case — writing source is
# its whole job (`tools: … Edit, Write …`), and `isolation: worktree` already bounds where that
# source-tree writing can land (ADR-0068). This guard answers a narrower, different question: given
# that coder now also carries `memory: project` (measured live, VCS-057/ADR-0184 — the write DOES
# persist onto the feature branch via Step 5's merge-back and IS re-injected on the next dispatch),
# how does a PARALLEL fan-out of several coder dispatches avoid two of them writing the same
# `MEMORY.md` and producing the merge conflict measured live as artifact C2? By denying coder any
# write to `MEMORY.md` itself, or to any file outside its own per-dispatch shard directory. The
# index is curated once, by the orchestrator, after the fan-out (Step 5's "Memory shard curation"
# sub-step) — never by a coder, and never inside the fan-out.
#
# This is a FOURTH mechanism, not a merge of the other three (rule 6: these answer different
# questions, so they stay different guards): `memory-store-guard.sh` protects the orchestrator's
# own curated auto-memory store from every sub-agent, regardless of memory mechanism.
# `reviewer-write-scope.sh` confines an agent with NO other Write/Edit entirely inside its memory
# dir. `test-write-scope.sh` confines architect's Write to three named documentation/memory roots.
# This one narrows an agent that legitimately writes everywhere else, only inside its own memory
# subtree, and only to a leaf pattern within it.
#
# Contract: exit 0 + empty stdout = allow. exit 0 + {"hookSpecificOutput":{...,"deny"}} = deny.
# NEVER exits non-zero — same contract as reviewer-write-scope.sh, write-scope-enforce.sh and
# memory-store-guard.sh: a guard that breaks unrelated edits gets disabled within a day, which is
# worse than no guard.
#
# INERTNESS IS STRUCTURAL: gated on `.agent_type == "coder"` — every other agent, and the
# orchestrator itself (no `.agent_type` in its own tool calls), is unaffected regardless of path.
# In particular this hook is a no-op for every ordinary source-file write coder makes: the decision
# tree below allows anything OUTSIDE `.claude/agent-memory/` unconditionally.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution.

DIR="${CODER_MEMORY_SCOPE_DIR:-$HOME/.claude/state/coder-memory-scope}"
LOG="$DIR/audit.log"
mkdir -p "$DIR" 2>/dev/null || true

log_audit() {
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >>"$LOG" 2>/dev/null || true
}

# Resolve a path to its physical form when the parent exists; otherwise leave it as-is.
# Never fails, never invents a path. Same helper as reviewer-write-scope.sh / memory-store-guard.sh.
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

# Inert for every agent except coder, and for the orchestrator (empty agent_type).
[ "$AGENT_TYPE" = "coder" ] || { log_audit "?" "allow" "agent_type=$AGENT_TYPE (not scoped)"; exit 0; }

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

[ -z "$FILE_PATH" ] && { log_audit "$SID" "allow" "no tool_input.file_path"; exit 0; }
[ -z "$CWD" ] && { log_audit "$SID" "allow" "no cwd"; exit 0; }

SHARD_ROOT=$(normalize "$CWD/.claude/agent-memory/coder/topics")
GOT=$(normalize "$FILE_PATH")

[ -z "$SHARD_ROOT" ] && { log_audit "$SID" "allow" "shard root empty after normalize"; exit 0; }
[ -z "$GOT" ] && { log_audit "$SID" "allow" "target path empty after normalize"; exit 0; }

# The gate is the RAW, syntactic path (before symlink resolution), not the resolved one: a write
# whose literal file_path already falls under .claude/agent-memory/ is a memory-write attempt by
# intent, and MUST resolve inside the shard — including when a symlink planted under agent-memory/
# would otherwise make the resolved target land outside it and slip through as "not my concern".
# Anything whose RAW path never mentioned agent-memory/ at all is coder's ordinary job, untouched.
case "$FILE_PATH" in
  "$CWD"/.claude/agent-memory/*|"$CWD"/.claude/agent-memory)
    case "$GOT" in
      "$SHARD_ROOT"/*)
        log_audit "$SID" "allow" "in scope (shard): $GOT"
        exit 0
        ;;
      *)
        log_audit "$SID" "deny" "target=$GOT shard_root=$SHARD_ROOT"
        REASON="coder-memory-scope: coder may write memory only under its own per-dispatch shard directory ($SHARD_ROOT) — this call targets $GOT. Writing MEMORY.md directly, or any other agent's memory directory, is denied: parallel coder dispatches sharing one index file merge-conflict (measured live, VCS-057). Write a uniquely-named file under topics/ instead — the index is curated once by the orchestrator after the batch, never by coder. Do NOT retry and do NOT work around this."
        printf '%s' "$REASON" | jq -R -s \
          '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}' 2>/dev/null \
          || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"coder-memory-scope: write to coder memory outside its own shard directory is denied (VCS-057, ADR-0184)"}}\n'
        exit 0
        ;;
    esac
    ;;
  *)
    # Raw path never mentioned .claude/agent-memory/ at all — coder's ordinary job. Not this
    # guard's concern, regardless of what any symlink along the way might resolve to.
    log_audit "$SID" "allow" "outside agent-memory, not scoped here: $FILE_PATH"
    exit 0
    ;;
esac
