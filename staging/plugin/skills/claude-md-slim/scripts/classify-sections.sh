#!/bin/bash
# classify-sections.sh — classify CLAUDE.md H2 sections by file-type-keyword heuristic.
#
# Inputs:
#   $1 = path to TSV produced by parse-sections.sh (columns: heading<TAB>start<TAB>end)
#   $2 = path to the original CLAUDE.md (for body extraction by line range)
#
# Output (stdout): TSV, one row per input row. Columns:
#   heading<TAB>domain<TAB>glob<TAB>classification
# classification in: extractable | mixed | non-extractable
#
# Tie-breaking when multiple domains match: first domain in the table order
# (shell > python > swift > typescript > javascript > migrations > markdown > sql).
# JavaScript is suppressed if any TypeScript keyword also matched.
# PREAMBLE sections are always non-extractable.
#
# Bash 3.2-clean: no assoc arrays, no mapfile, no <<<, no process substitution.
set -u

if [ $# -lt 2 ]; then
  echo "usage: classify-sections.sh <parse-tsv> <claude-md-path>" >&2
  exit 1
fi

TSV_FILE="$1"
CLAUDE_MD="$2"

if [ ! -f "$TSV_FILE" ]; then
  echo "classify-sections.sh: TSV file not found: $TSV_FILE" >&2
  exit 1
fi
if [ ! -f "$CLAUDE_MD" ]; then
  echo "classify-sections.sh: CLAUDE.md not found: $CLAUDE_MD" >&2
  exit 1
fi

# Domain table: one line per domain, format: domain|glob|keyword1 keyword2 ...
# Order is significant: first match wins for tie-breaking.
DOMAINS_TMP=$(mktemp /tmp/csh-domains.XXXXXX)
cat > "$DOMAINS_TMP" << 'DOMAINS'
shell|**/*.{sh,bash}|sh bash zsh shell AppleScript osascript shebang
python|**/*.py|Python python3 venv pip .py requirements
swift|**/*.swift|Swift SwiftUI SwiftData Xcode xcodebuild AppKit .swift
typescript|**/*.{ts,tsx}|TypeScript Node npm .ts .tsx
javascript|**/*.{js,jsx}|JavaScript .js .jsx
migrations|**/migrations/**|migrations migration schema change
markdown|**/*.md|Markdown .md documentation
sql|**/*.sql|SQL database .sql
DOMAINS

# Global behavioral keywords: presence makes a section non-extractable
# unless it also matches a domain (→ mixed).
GLOBAL_KWDS_TMP=$(mktemp /tmp/csh-global.XXXXXX)
cat > "$GLOBAL_KWDS_TMP" << 'GLOBAL'
git
commit
push
pull
merge
rebase
branch
convention
workflow
tone
identity
security
guardrail
HITL
always
never
must
should
Conventional Commits
plan mode
feature branch
language
trust
GLOBAL

while IFS=$'\t' read -r heading line_start line_end; do
  # PREAMBLE is never extractable.
  if [ "$heading" = "PREAMBLE" ]; then
    printf '%s\tgeneral\t*\tnon-extractable\n' "$heading"
    continue
  fi

  # Build a temp file with the section body + heading line for grep scans.
  BODY_TMP=$(mktemp /tmp/csh-body.XXXXXX)
  sed -n "${line_start},${line_end}p" "$CLAUDE_MD" > "$BODY_TMP"
  # Also include the heading text itself (parse-sections strips the "## " prefix).
  printf '%s\n' "$heading" >> "$BODY_TMP"

  # First pass: detect TypeScript so we can suppress JavaScript later.
  has_ts=0
  TS_KWDS_TMP=$(mktemp /tmp/csh-ts.XXXXXX)
  cat > "$TS_KWDS_TMP" << 'TS'
TypeScript
Node
npm
.ts
.tsx
TS
  if grep -qiwFf "$TS_KWDS_TMP" "$BODY_TMP"; then
    has_ts=1
  fi
  rm -f "$TS_KWDS_TMP"

  matched_domain=""
  matched_glob=""

  # Iterate domains in declared order; first match wins.
  while IFS='|' read -r domain glob keywords; do
    # Skip empty/comment lines defensively.
    [ -z "$domain" ] && continue
    # JavaScript suppression when TS already matched.
    if [ "$domain" = "javascript" ] && [ "$has_ts" -eq 1 ]; then
      continue
    fi
    # Build a per-domain keyword pattern file (one keyword per line).
    KW_TMP=$(mktemp /tmp/csh-kw.XXXXXX)
    # tr space → newline; keywords are single tokens (no embedded spaces).
    printf '%s\n' "$keywords" | tr ' ' '\n' | sed '/^$/d' > "$KW_TMP"
    if grep -qiwFf "$KW_TMP" "$BODY_TMP"; then
      if [ -z "$matched_domain" ]; then
        matched_domain="$domain"
        matched_glob="$glob"
      fi
    fi
    rm -f "$KW_TMP"
  done < "$DOMAINS_TMP"

  # Global behavioral scan.
  has_global=0
  if grep -qiwFf "$GLOBAL_KWDS_TMP" "$BODY_TMP"; then
    has_global=1
  fi

  if [ -n "$matched_domain" ] && [ "$has_global" -eq 0 ]; then
    printf '%s\t%s\t%s\textractable\n' "$heading" "$matched_domain" "$matched_glob"
  elif [ -n "$matched_domain" ] && [ "$has_global" -eq 1 ]; then
    printf '%s\t%s\t%s\tmixed\n' "$heading" "$matched_domain" "$matched_glob"
  else
    printf '%s\tgeneral\t*\tnon-extractable\n' "$heading"
  fi

  rm -f "$BODY_TMP"
done < "$TSV_FILE"

rm -f "$DOMAINS_TMP" "$GLOBAL_KWDS_TMP"
exit 0
