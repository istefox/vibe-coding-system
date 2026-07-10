#!/usr/bin/env bash
# humanize-en: detect-ai-tells.sh — bash 3.2-clean
# Scans a file for AI writing tells. Returns hit count to stdout.
# Usage: detect-ai-tells.sh <file-path>
# Exit: 0 always (fail-open). Stdout: integer hit count.
set -u

FILE="${1:-}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "0"
  exit 0
fi

# Skip if under 100 words
WORDS=$(wc -w < "$FILE" 2>/dev/null | tr -d ' ')
if [ -z "$WORDS" ] || [ "$WORDS" -lt 100 ] 2>/dev/null; then
  echo "0"
  exit 0
fi

HITS=0
VOCAB=$(mktemp)
OPENERS=$(mktemp)
trap 'rm -f "$VOCAB" "$OPENERS"' EXIT

# Vocabulary tells (case-insensitive, extended regex, \b word boundary)
cat > "$VOCAB" <<'VOCAB_EOF'
\bdelving\b
\bdelve\b
\btapestry\b
\btestament\b
\bleverage\b
\bfostering\b
\bfoster\b
\bshowcasing\b
\bshowcase\b
\bunderscore\b
\bpivotal\b
\bgroundbreaking\b
\bvibrant\b
\bnestled\b
\bseamless\b
VOCAB_EOF

while IFS= read -r pattern; do
  # grep -c returns exit 1 on 0 matches but still writes "0" to stdout.
  # Using "; true" makes $() exit 0 without adding spurious output.
  c=$(grep -ciE "$pattern" "$FILE" 2>/dev/null; true)
  case "$c" in ''|*[!0-9]*) c=0 ;; esac
  HITS=$((HITS + c))
done < "$VOCAB"

# Opener tells (paragraph/line start)
cat > "$OPENERS" <<'OPEN_EOF'
^Additionally,
^Moreover,
^Furthermore,
^In conclusion,
^It is worth noting
^It should be noted
^Importantly,
^Notably,
OPEN_EOF

while IFS= read -r pattern; do
  c=$(grep -c "$pattern" "$FILE" 2>/dev/null; true)
  case "$c" in ''|*[!0-9]*) c=0 ;; esac
  HITS=$((HITS + c))
done < "$OPENERS"

# Em-dash overuse: more than 2 occurrences of " — " is a tell
EMDASH=$(grep -o ' — ' "$FILE" 2>/dev/null | wc -l | tr -d ' \t\n' || echo 0)
case "$EMDASH" in ''|*[!0-9]*) EMDASH=0 ;; esac
if [ "$EMDASH" -gt 2 ]; then
  HITS=$((HITS + EMDASH - 2))
fi

echo "$HITS"
exit 0
