#!/bin/bash
# worktree-git-guardrail v1.0 — PreToolUse gate on matcher Bash.
# Denies a git invocation, from inside a dispatch-created worktree, whose target resolves outside
# that worktree (issue tracked as VCS-039; ADR-0068 defines the worktree isolation this backstops).
#
# WHY A HOOK. `coder`'s tool grant is unrestricted `Bash` — unlike `architect`/`reviewer`, which
# hold only read-only `Bash(git ...*)` patterns, `coder` has no frontmatter-level git restriction
# at all (ADR-0068 §D1/§D7 give it `isolation: worktree` instead: it is meant to be free to run
# git, scoped by the worktree, not by a git-verb denylist). Protection against a git command that
# steps OUTSIDE that worktree back onto the main checkout has, until now, been entirely the
# platform's: Claude Code's own worktree isolation (its escape-case bug was fixed in CC 2.1.222).
# This hook is an independent, versioned backstop against a platform regression of the same class —
# it was one that went unnoticed here for the life of that bug, by our own account.
#
# THREAT MODEL — do not mistake this for more than it is, the same disclosure
# agent-command-scope.sh and db-backup-guardrail.sh already carry for their own domains.
# A guardrail against an accidental or careless escape, NOT a sandbox against deliberate evasion.
# String inspection on the command text cannot be otherwise: a wrapped subprocess call, a script
# written to a temp file and executed, or deliberate shell obfuscation defeats it outright. Quoted
# paths containing spaces are also outside this hook's parsing (word-splitting is used to find
# arguments, the same accepted limit `db-backup-guardrail.sh` carries).
#
# DETECTION SIGNAL: `.cwd`, not `.agent_type`. Only `coder` declares `isolation: worktree` in its
# own frontmatter; `refactorer`/`debugger`/`tester` get it passed explicitly at DISPATCH time by
# `concept-to-code`'s SKILL.md (ADR-0068 §D6/§D7), so a static agent-type allowlist here would
# silently drift out of sync with a decision made in a different file. The actual invariant this
# hook cares about — "this Bash call is running inside a worktree this system created" — is
# directly observable instead: every worktree lives under `.claude/worktrees/` (ADR-0068, both the
# Agent-tool path `.claude/worktrees/agent-*/` and the Workflow path
# `.claude/worktrees/wf_<runid>-<n>`). The hook is inert unless `.cwd` matches that.
#
# SCOPE: escape only, not "any git mutation." coder.md states it never commits, which could argue
# for banning all mutating git the way agent-command-scope.sh bans it for architect/reviewer — that
# is a broader behavior change, out of scope here by design. If wanted later it is a one-line
# addition to agent-command-scope.sh's existing allowlist, not a reason to widen this hook.
#
# ESCAPE VECTORS INTERCEPTED, per git clause (command split on ; && || |, so a check never inspects
# an unrelated clause of a compound command):
#   - `-C <path>` / `--git-dir[=]<path>` / `--work-tree[=]<path>` resolving outside the worktree
#   - a preceding `cd <path>` clause in the same chain, landing outside the worktree, before git
#   - `git worktree remove <path>` naming a DIFFERENT worktree under `.claude/worktrees/`
#   - an absolute-path argument in the same clause that lies outside the worktree
# A relative-path target with no `..` segment is never flagged (it resolves under `.cwd` by
# construction); one containing `..` is treated conservatively as a possible escape.
#
# Contract: exit 0 + empty stdout = allow. exit 0 + {"hookSpecificOutput":{...,"deny"}} = deny.
# NEVER exits non-zero. Every failure mode allows. Bash 3.2 clean: no assoc arrays, no mapfile, no
# process substitution.

DIR="${WORKTREE_GIT_GUARDRAIL_DIR:-$HOME/.claude/state/worktree-git-guardrail}"
LOG="$DIR/audit.log"
mkdir -p "$DIR" 2>/dev/null || true

# Audit log: 5-field TAB-separated. Fields: timestamp, session_id, matched_vector, action, detail
log_audit() {
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${1:-?}" "${2:--}" "${3:-?}" "${4:-}" \
    >>"$LOG" 2>/dev/null || true
}

# Bypass: env var single-call override, same idiom as db-backup-guardrail.sh's DB_GUARDRAIL=off
if [ "$WORKTREE_GIT_GUARDRAIL" = "off" ]; then
  log_audit "?" "-" "bypass-env" "env WORKTREE_GIT_GUARDRAIL=off"
  exit 0
fi

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || { log_audit "?" "-" "fail-open" "jq missing"; exit 0; }

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && { log_audit "?" "-" "fail-open" "malformed or empty JSON (no session_id)"; exit 0; }

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

if [ "$TOOL" != "Bash" ] || [ -z "$CMD" ]; then
  log_audit "$SID" "-" "allow" "tool=$TOOL non-Bash or empty command"
  exit 0
fi

# Inert unless this Bash call is running inside a worktree this system created.
case "$CWD" in
  */.claude/worktrees/*) : ;;
  *)
    log_audit "$SID" "-" "allow" "cwd not under .claude/worktrees: $CWD"
    exit 0
    ;;
esac

# Normalize: collapse newlines and repeated spaces to single space.
NORM=$(printf '%s' "$CMD" | tr '\n' ' ' | tr -s ' ')

# Command-position anchor for an interpreter's -c, reused from agent-command-scope.sh (issue #127
# / #196's fix: qualified by interpreter NAME so it does not also match a search tool's -c COUNT
# flag).
INTERP_C="(bash|sh|zsh|ksh|dash|python|python3|perl|ruby|node|env)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-[A-Za-z]*c[[:space:]]*['\"]?"

# is_outside_worktree TARGET — 0 if TARGET plausibly resolves outside $CWD, 1 otherwise.
is_outside_worktree() {
  case "$1" in
    /*)
      case "$1" in
        "$CWD"|"$CWD"/*) return 1 ;;
        *) return 0 ;;
      esac
      ;;
    *..*)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

ESCAPE=""
DETAIL=""
PREV_CD=""

CLAUSES=$(printf '%s' "$NORM" | sed -E 's/(;|&&|\|\||\|)/\n/g')

while IFS= read -r CLAUSE; do
  CLAUSE=$(printf '%s' "$CLAUSE" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [ -z "$CLAUSE" ] && continue

  case "$CLAUSE" in
    cd\ *)
      PREV_CD=$(printf '%s' "$CLAUSE" | sed -E 's/^cd[[:space:]]+//')
      continue
      ;;
  esac

  # Is this clause a git invocation, directly or via an interpreter's -c?
  printf '%s' "$CLAUSE" | grep -Eq "^git[[:space:]]|${INTERP_C}git[[:space:]]" || { PREV_CD=""; continue; }

  # Vector: a prior `cd` in the same chain landed outside the worktree.
  if [ -n "$PREV_CD" ]; then
    if is_outside_worktree "$PREV_CD"; then
      ESCAPE=1
      DETAIL="cd $PREV_CD then: $CLAUSE"
      break
    fi
  fi

  # Vector: -C / --git-dir / --work-tree pointing outside the worktree.
  TARGET=$(printf '%s' "$CLAUSE" \
    | grep -oE -- '-C[[:space:]]+[^[:space:]]+|--git-dir[=[:space:]][^[:space:]]+|--work-tree[=[:space:]][^[:space:]]+' \
    | head -1 | sed -E 's/^(-C|--git-dir|--work-tree)[=[:space:]]//')
  if [ -n "$TARGET" ] && is_outside_worktree "$TARGET"; then
    ESCAPE=1
    DETAIL="target flag outside worktree in: $CLAUSE"
    break
  fi

  # Vector: `git worktree remove <path>` naming a DIFFERENT worktree.
  case "$CLAUSE" in
    *worktree*remove*)
      WT_TARGET=$(printf '%s' "$CLAUSE" | sed -E 's/^.*worktree[[:space:]]+remove[[:space:]]+//')
      case "$WT_TARGET" in
        "$CWD"|"$CWD"/) : ;;
        *.claude/worktrees/*)
          ESCAPE=1
          DETAIL="worktree remove targets a different worktree: $WT_TARGET"
          break
          ;;
      esac
      ;;
  esac
  [ -n "$ESCAPE" ] && break

  # Vector: an absolute-path argument in this clause that lies outside the worktree.
  for ARG in $CLAUSE; do
    case "$ARG" in
      /*)
        if is_outside_worktree "$ARG"; then
          ESCAPE=1
          DETAIL="absolute path outside worktree: $ARG in: $CLAUSE"
          break
        fi
        ;;
    esac
  done
  [ -n "$ESCAPE" ] && break

  PREV_CD=""
done <<EOF
$CLAUSES
EOF

if [ -z "$ESCAPE" ]; then
  log_audit "$SID" "-" "allow" "no escape vector matched"
  exit 0
fi

log_audit "$SID" "escape" "deny" "$DETAIL"

REASON="worktree-git-guardrail: this git invocation targets somewhere outside the worktree this dispatch was given ($CWD). $DETAIL. STOP: do not execute, do not retry with a different form, do not route around this. If your task genuinely requires touching a path outside this worktree, report that to the orchestrator and let it decide — a dispatched agent never reaches outside its own worktree on its own."

printf '%s' "$REASON" | jq -R -s \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"worktree-git-guardrail: this git invocation targets outside the assigned worktree"}}\n'
exit 0
