#!/bin/bash
# Inject .claude/context.md into session context at SessionStart.
# Output is captured by Claude Code and shown as a system reminder.
# Silent no-op if the file does not exist.
CTX_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/context.md"
if [ -f "$CTX_FILE" ]; then
  printf '\n=== PROJECT CONTEXT ===\n'
  cat "$CTX_FILE"
  printf '=======================\n'
fi
exit 0
