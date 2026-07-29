#!/bin/bash
# agent-command-scope v1.0 — PreToolUse gate denying mutating git commands to the two agents whose
# grants are meant to be read-only (issue #58 gap 1; ADR-0045).
#
# Why a hook: architect and reviewer hold Bash(bash *) and Bash(python3 *) (reviewer also
# Bash(awk *)) for verification-by-execution, and those subsume every command their narrowed git
# grants exclude. ADR-0042 closed architect's DIRECT path and stated plainly that
# `bash -c "git commit …"` still reached git. This closes the wrapper.
#
# THREAT MODEL — do not mistake this for more than it is.
# A guardrail against an agent taking a shortcut, NOT a sandbox against an adversary. String
# inspection cannot be otherwise: subprocess.run(["git","push"]) splits the verb across list
# elements, and eval / base64 / variable splicing defeat it outright. Both bypasses are pinned as
# EXPECTED-ALLOW in agent-command-scope.test.sh section E so the limit is versioned with the code.
# Anyone who reads this as a security boundary will misuse it.
#
# WHY THE OBVIOUS DENYLIST WAS WRONG, AND WHAT REPLACED IT.
# Matching "git commit" as a substring blocks `rg "git commit" .`, a legitimate read-only search.
# That objection deferred this fix three separate times. It dissolves once the match is anchored to
# a COMMAND POSITION: start of string, or after ; && || | ` $( { } or an interpreter's -c and its
# opening quote. A verb inside quotes is data and never reaches a command position.
#
# TWO CORRECTIONS FROM ISSUE #127's SIBLING AUDIT (2026-07-29). The paragraph above says "an
# INTERPRETER's -c"; the regex said `-c`, unqualified, so it also matched every search tool's
# COUNT flag and denied `grep -c "git commit -m" f`. The prose was right and the code was not —
# the same class as #127 itself, a guard arming on text ABOUT the thing it guards, reached through
# the command string rather than through a transcript. In the other direction, R1's trailing
# boundary did not accept a closing quote, so `bash -c "git push"` — the form ADR-0042 and ADR-0045
# both name as THE case this hook closes — was ALLOWED. Section A never caught it because every
# case there carries an argument after the verb. Both pinned: test sections C12-C15 and H.
#
# Contract: exit 0 + empty stdout = allow. exit 0 + {"hookSpecificOutput":{...,"deny"}} = deny.
# NEVER exits non-zero. Every failure mode allows.
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution.

DIR="${AGENT_COMMAND_SCOPE_DIR:-$HOME/.claude/state/agent-command-scope}"
LOG="$DIR/audit.log"
mkdir -p "$DIR" 2>/dev/null || true

log_audit() {
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" >>"$LOG" 2>/dev/null || true
}

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || { log_audit "?" "allow" "jq missing"; exit 0; }

AGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)

# Inert for the orchestrator and every other agent. This is the common path.
case "$AGENT_TYPE" in
  architect|reviewer) : ;;
  *) log_audit "?" "allow" "agent_type=$AGENT_TYPE (not scoped)"; exit 0 ;;
esac

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$CMD" ] && { log_audit "$SID" "allow" "no tool_input.command"; exit 0; }

# The mutating half of git's verb set. Read-only verbs (log, diff, show, status, rev-parse,
# ls-files, blame, describe, cat-file) are deliberately absent — those are the grants ADR-0042
# left in place, and denying them here would contradict the frontmatter.
MUTATING='(commit|push|add|reset|checkout|merge|rebase|clean|stash|tag|branch|remote|filter-repo|am|apply|cherry-pick|revert|restore|rm|mv|switch|worktree|submodule|gc|prune|fetch|pull|init|clone)'

# The interpreter forms of a command position: `bash -c "…"`, `sh -c '…'`, `python3 -u -c "…"`,
# `bash -lc "…"`. Qualified by the interpreter NAME (issue #127 sibling audit) — an anchor written
# as a bare `-c` also matched every search tool's COUNT flag, so `grep -c "git commit -m" f` was
# denied. That is the same class as #127 itself: a guard arming on text ABOUT the thing it guards.
# `-[A-Za-z]*c` covers combined short flags (-lc); the intervening group is restricted to further
# FLAGS so it cannot swallow an unrelated command in a compound line.
INTERP_C="(bash|sh|zsh|ksh|dash|python|python3|perl|ruby|node|env)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-[A-Za-z]*c[[:space:]]*['\"]?"

# What may follow the verb. The closing quote belongs here: `bash -c "git push"` — the form ADR-0042
# and ADR-0045 both quote as THE case this hook exists to close — escaped a trailing class of
# ([[:space:]]|$) entirely, and section A stayed green because every case in it carries an argument
# after the verb. R2_GIT below already accepted a quote; R1 did not.
TRAIL="([[:space:]]|[\"')\`;&|]|\$)"

# R1 — command position. The anchor alternation is the whole design; see the header.
R1="(^|[;&|(){}]|&&|\\|\\||\`|\\\$\\(|${INTERP_C})[[:space:]]*git[[:space:]]+${MUTATING}${TRAIL}"

# R2 — an interpreter shelling out. Compound on purpose: the exec construct alone is fine
# (os.system("git log")), the verb alone is fine (print("git commit")), only both together deny.
R2_EXEC='(os\.system|subprocess\.(run|call|Popen|check_output|check_call)|commands\.getoutput|[^a-zA-Z_]system\(|popen|child_process|execSync|spawnSync|%x\{|IO\.popen)'
R2_GIT="git[[:space:]]+${MUTATING}([[:space:]]|[\"')]|\$)"

VERB=""
if printf '%s' "$CMD" | grep -Eq "$R1"; then
  VERB=$(printf '%s' "$CMD" | grep -Eo "git[[:space:]]+${MUTATING}" | head -1)
  RULE="R1 (command position)"
elif printf '%s' "$CMD" | grep -Eq "$R2_EXEC" && printf '%s' "$CMD" | grep -Eq "$R2_GIT"; then
  VERB=$(printf '%s' "$CMD" | grep -Eo "git[[:space:]]+${MUTATING}" | head -1)
  RULE="R2 (interpreter shell-out)"
fi

if [ -z "$VERB" ]; then
  log_audit "$SID" "allow" "$AGENT_TYPE: $CMD"
  exit 0
fi

log_audit "$SID" "deny" "$AGENT_TYPE $RULE [$VERB]: $CMD"

REASON="agent-command-scope: the $AGENT_TYPE agent may not run mutating git commands, directly or through an interpreter. This call matches \"$VERB\" at $RULE. Committing, pushing and staging are the human's decision at a HITL gate, never an agent's. Do NOT retry, do NOT wrap it differently, do NOT reach for another tool: report the change you believe is needed in your report and let the orchestrator act on it. Read-only git (log, diff, show, status, rev-parse) is unaffected and remains available to you."

printf '%s' "$REASON" | jq -R -s \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"agent-command-scope: mutating git is not available to this agent; report the needed change instead."}}\n'
exit 0
