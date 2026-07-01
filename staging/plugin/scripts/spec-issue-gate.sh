#!/usr/bin/env bash
# spec-issue-gate v1.0 (ADR-0023 D5). Deterministic quality gate: decides whether a GitHub
# issue body carries enough substance to synthesize a SPEC, or is too thin to design from.
# spec-from-issue calls this BEFORE generating; on THIN it skips the feature instead of
# fabricating requirements.
#
# Input: issue body on stdin, or --body-file <f>.
# Output: "OK" (exit 0) or "THIN: <reason>" (exit 3). Any usage error is exit 2.
# Bash 3.2 clean.
set -euo pipefail

BODY_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --body-file) BODY_FILE="$2"; shift 2 ;;
    *) echo "spec-issue-gate: unknown arg $1" >&2; exit 2 ;;
  esac
done

if [ -n "$BODY_FILE" ]; then
  [ -f "$BODY_FILE" ] || { echo "spec-issue-gate: no such file: $BODY_FILE" >&2; exit 2; }
  BODY=$(cat "$BODY_FILE")
else
  BODY=$(cat)
fi

# Non-whitespace character count.
nchars=$(printf '%s' "$BODY" | tr -d '[:space:]' | wc -c | tr -d ' ')

# Substance signal: acceptance-criteria language or a checklist.
signal=0
printf '%s' "$BODY" | grep -qiE 'accept|criteri|requirement|should|must|expected|behavi|given|when|then|- \[' && signal=1

MIN_CHARS=120        # below this a body is thin regardless of anything else
SUBSTANTIAL=400      # a signal-free body must be at least this long to design from

if [ "$nchars" -lt "$MIN_CHARS" ]; then
  echo "THIN: body too short ($nchars < $MIN_CHARS non-space chars)"; exit 3
fi
# A body with no acceptance-criteria signal must be genuinely substantial. A short-but-padded
# few lines with no requirements language is skipped, not fabricated (ADR-0023 D5).
if [ "$signal" -eq 0 ] && [ "$nchars" -lt "$SUBSTANTIAL" ]; then
  echo "THIN: no acceptance-criteria signal and not substantial ($nchars < $SUBSTANTIAL chars)"; exit 3
fi
echo "OK"
