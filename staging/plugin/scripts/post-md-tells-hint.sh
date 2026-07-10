#!/usr/bin/env bash
# humanize-en: post-md-tells-hint.sh — PostToolUse hook, bash 3.2-clean
# Scans .md files written/edited by Claude for AI tells. Prints a hint if >= 3 found.
# Never blocks (exit 0 always). Zero LLM calls.
set -u

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null || true)

[ -z "$FILE_PATH" ] && exit 0

# Only process .md files
case "$FILE_PATH" in
  *.md) ;;
  *) exit 0 ;;
esac

[ ! -f "$FILE_PATH" ] && exit 0

DETECT="$HOME/.claude/skills/humanize-en/scripts/detect-ai-tells.sh"
[ ! -f "$DETECT" ] && exit 0

HITS=$(bash "$DETECT" "$FILE_PATH" 2>/dev/null || echo 0)
HITS=$(printf '%s' "$HITS" | tr -d ' \n')

# Default to 0 if empty or non-numeric
case "$HITS" in
  ''|*[!0-9]*) HITS=0 ;;
esac

if [ "$HITS" -lt 3 ]; then
  exit 0
fi

printf '[humanize-en] %s AI tell(s) in %s — run /skill humanize-en to clean up.\n' \
  "$HITS" "$(basename "$FILE_PATH")"

exit 0
