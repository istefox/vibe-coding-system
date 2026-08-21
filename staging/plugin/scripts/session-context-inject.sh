#!/bin/bash
# Inject .claude/context.md into session context at SessionStart.
# Output is captured by Claude Code and shown as a system reminder.
# Silent no-op if the file does not exist.
#
# At source=compact the file is NOT re-injected: only a pointer line is printed.
# Measured 2026-08-21: this session compacted 17 times in ~70 minutes, and the whole
# 3,087-byte payload was re-created in every one of them while ~50k of each
# post-compaction context was already fixed preamble. The same shape is what the
# `remember` plugin's MEMORY block ships: a pointer to the file, never the payload.
#
# `source` is read from the hook's stdin JSON and is one of
# startup | resume | clear | compact | fork. It is read in ONE direction only: an absent,
# unparseable or unexpected value falls through to injecting. Skipping is done only on an
# exact, positively-read `compact`, so a payload shape change can lose the saving but can
# never silently stop injecting the context.
HOOK_STDIN=""
[ -t 0 ] || HOOK_STDIN=$(cat 2>/dev/null || true)
SRC=$(printf '%s' "$HOOK_STDIN" | tr -d '\n' \
  | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

CTX_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/context.md"
if [ -f "$CTX_FILE" ]; then
  if [ "$SRC" = "compact" ]; then
    printf '\n=== PROJECT CONTEXT ===\n'
    printf -- '--- not re-injected at compact (delivered at session start); read %s on request ---\n' "$CTX_FILE"
    printf '=======================\n'
  else
    printf '\n=== PROJECT CONTEXT ===\n'
    cat "$CTX_FILE"
    printf '=======================\n'
  fi
fi
exit 0
