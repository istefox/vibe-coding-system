#!/bin/bash
# hook-probe-sandbox v1.0 — build a throwaway repo wired with the observational hook-probe.
#
# Usage: hook-probe-sandbox.sh [<target-dir>]
#        default target: ${TMPDIR:-/tmp}/hook-probe-sandbox
#
# What it does:
#   - creates a git repo at <target-dir> with one editable file
#   - writes a PROJECT-LEVEL .claude/settings.json registering hook-probe.sh on
#     PreToolUse, PostToolUse, SubagentStart, SubagentStop and Stop
#   - seeds .claude/hook-probe-context with C1
#   - prints the four prompts to run
#
# It never touches ~/.claude. Nothing on the real machine changes: the probe is registered only in
# the sandbox's own project settings, and it is observational anyway (see hook-probe.sh).
#
# Guardrail: refuses to run if <target-dir> is inside an existing git work tree that is not the
# sandbox itself. Writing a hooks config into a real project is exactly the accident worth
# preventing.
#
# Bash 3.2 clean.
#
# transcript-scan-exempt: probe-only, never registered. A harness around hook-probe.sh; touches
#   only the probe's own log.

set -u

HERE=$(cd "$(dirname "$0")" && pwd)
PROBE="$HERE/hook-probe.sh"
TARGET="${1:-${TMPDIR:-/tmp}/hook-probe-sandbox}"

die() { printf 'hook-probe-sandbox: %s\n' "$1" >&2; exit 1; }

[ -f "$PROBE" ] || die "cannot find hook-probe.sh next to this script ($PROBE)"
command -v git >/dev/null 2>&1 || die "git is required"
command -v jq  >/dev/null 2>&1 || printf 'WARN jq not found — the probe will record raw payloads and the verifier will not read them\n' >&2

# --- guardrail: never scribble into an existing repo ---------------------------------------------
if [ -e "$TARGET" ]; then
  EXISTING_ROOT=$(cd "$TARGET" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || EXISTING_ROOT=""
  if [ -n "$EXISTING_ROOT" ] && [ ! -f "$TARGET/.claude/hook-probe-context" ]; then
    die "refusing: $TARGET is inside the git work tree $EXISTING_ROOT and is not a probe sandbox"
  fi
else
  PARENT=$(dirname "$TARGET")
  PARENT_ROOT=$(cd "$PARENT" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || PARENT_ROOT=""
  [ -n "$PARENT_ROOT" ] && die "refusing: $PARENT is inside the git work tree $PARENT_ROOT — pick a target outside any repo"
fi

# --- build ---------------------------------------------------------------------------------------
mkdir -p "$TARGET/.claude" || die "cannot create $TARGET"
cd "$TARGET" || die "cannot enter $TARGET"

[ -d .git ] || { git init -q . || die "git init failed"; }

cat > probe-target.txt <<'EOF'
line one
line two
line three
EOF

cp "$PROBE" .claude/hook-probe.sh
chmod +x .claude/hook-probe.sh

# stop-gate.sh is a USER-level hook, so it fires inside this sandbox too. With a dirty tree and no
# declared test command it blocks at the end of every turn, three times per context before its
# anti-loop counter relents. There is no code here to test, so NONE is the honest declaration.
# Found the hard way on the 2026-07-10 live run.
printf 'NONE\n' > .claude/test-cmd

# The probe's log path is pinned to an absolute path. Do NOT let it fall back to the payload's cwd:
# a worktree-isolated subagent runs with a different cwd AND carries its own copy of .claude/, so its
# events would land in a second log inside the worktree. On the 2026-07-10 run that split the data and
# very nearly produced the conclusion "PreToolUse never fires inside a subagent", which is false.
LOG_ABS="$TARGET/.claude/hook-probe.jsonl"
# The quotes must survive into the JSON string, so they are backslash-escaped here. A bare `"` would
# terminate the JSON value and produce a settings.json that Claude Code silently ignores.
CMD="HOOK_PROBE_LOG=\\\"$LOG_ABS\\\" bash \\\"$TARGET/.claude/hook-probe.sh\\\""

cat > .claude/settings.json <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "matcher": ".*", "hooks": [ { "type": "command", "command": "$CMD" } ] }
    ],
    "PostToolUse": [
      { "matcher": ".*", "hooks": [ { "type": "command", "command": "$CMD" } ] }
    ],
    "SubagentStart": [
      { "hooks": [ { "type": "command", "command": "$CMD" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "$CMD" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "$CMD" } ] }
    ]
  }
}
EOF

printf 'C1\n' > .claude/hook-probe-context
: > .claude/hook-probe.jsonl

# An agent with `isolation: worktree` in its frontmatter (the `coder` agent has it) cannot be
# dispatched against an unborn HEAD: the harness resolves a base branch first and `git rev-parse HEAD`
# fails on a repo with no commits. `git init` alone therefore breaks context C2. Seed a root commit.
git add -A >/dev/null 2>&1
git -c user.email=probe@localhost -c user.name=hook-probe \
    commit -q -m "hook-probe sandbox root commit" >/dev/null 2>&1 \
  || printf 'WARN could not create the root commit; the coder agent (isolation: worktree) will fail to launch\n' >&2

printf 'Sandbox ready: %s\n\n' "$TARGET"
cat <<EOF
Run the probe by hand. Hooks load at session start, so this needs its OWN claude session:

  cd "$TARGET" && claude

Accept the workspace trust dialog (the hook system, and therefore /goal, requires it).
Then run the four contexts, bumping the context file between each one:

  C1  baseline, main loop
      > add a fourth line to probe-target.txt

  C2  Agent-tool subagent
      ! echo C2 > .claude/hook-probe-context
      > use the coder agent to add a fifth line to probe-target.txt

  C3  workflow subagent  <-- this is the ADR-0016 blocker
      ! echo C3 > .claude/hook-probe-context
      > ultracode: add a sixth line to probe-target.txt

  C4  /goal + Stop hook
      ! echo C4 > .claude/hook-probe-context
      > /goal probe-target.txt has at least six lines, or stop after 2 turns

Then, from anywhere:

  bash "$HERE/hook-probe-verify.sh" "$TARGET/.claude/hook-probe.jsonl"

Read RUNBOOK-hook-probe.md for what each outcome means. An empty log is INCONCLUSIVE, not a "no".
EOF
