#!/usr/bin/env bash
# chain-memory-section.sh — read-only "Active chains" section for vibe-status.
# Reads STATE OF FACT headers from the native store's chain-history/ files
# (written by chain-memory-capture.sh, ADR-0021) and renders a Markdown list of
# non-terminal chains. Mirrors the ADR-0012 agent-notes read-only watch.
#
# Read-only, fail-graceful: prints nothing on any error, never non-zero in a way
# that would break aggregate.sh (callers should `|| true`).
#
# Encoded-cwd derivation matches vibe-status's existing "Memory head" convention
# (SKILL.md Discovery: ~/.claude/projects/<encoded-cwd>/memory/). When invoked
# from aggregate.sh that already resolves the memory dir, pass it as $1 instead.
set -uo pipefail

MEM_DIR="${1:-}"
if [ -z "$MEM_DIR" ]; then
  ENCODED=$(printf '%s' "$PWD" | tr '/' '-')
  MEM_DIR="$HOME/.claude/projects/$ENCODED/memory"
fi
HIST_DIR="$MEM_DIR/chain-history"
[ -d "$HIST_DIR" ] || exit 0

# yval: extract a STATE OF FACT bullet value (lines like "- key: value").
hval() { grep -E "^- $1:" "$2" 2>/dev/null | head -1 | sed -E "s/^- $1:[[:space:]]*//"; }

ACTIVE=""
for f in "$HIST_DIR"/*.md; do
  [ -f "$f" ] || continue
  status=$(hval status "$f")
  case "$status" in
    completed|aborted|failed|"") continue ;;   # terminal or unknown → not active
  esac
  topic=$(hval topic "$f"); [ -z "$topic" ] && topic=$(basename "$f" .md)
  step=$(hval current_step "$f")
  next=$(hval next_action "$f" | cut -c1-60)
  ACTIVE="${ACTIVE}- ${topic} — step=${step:-?}, status=${status}, next: ${next:-(none)}
"
done

if [ -n "$ACTIVE" ]; then
  printf '## Active chains (concept-to-code)\n\n%s\n' "$ACTIVE"
fi
exit 0
