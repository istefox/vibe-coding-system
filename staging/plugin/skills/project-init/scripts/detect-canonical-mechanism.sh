#!/bin/bash
# detect-canonical-mechanism.sh — dominant-mechanism detection for project-init (ADR-0063 §D2).
#
# Outputs ONE line "name<TAB>count" naming the dominant candidate in a category, or nothing at all
# when there is no clear winner. project-init reads this to PROPOSE a draft line for
# .claude/rules/canonical-mechanisms.md at its existing HITL gate (Step 4) — this script never
# writes that file itself, and never writes anything (ADR-0063 §D2: propose, never write silently,
# the same contract ADR-0053 §D6 and ADR-0055 §D5 use).
#
# Auto-derivation is sound HERE SPECIFICALLY because the property being detected (which mechanism
# is used most) and the property being declared ("this is the canonical mechanism") are the SAME
# property — canonical means the one already used most. That does not generalise: ADR-0055 §A4
# rejected path-based auto-derivation of `risk` for the opposite reason, because a file's location
# does not determine its risk.
#
# Usage: detect-canonical-mechanism.sh <project_root> <category>
#   category: http | logger | config
#
# "No dominant mechanism" (SPEC edge case) covers two cases, both silent (empty stdout, exit 0):
#   - a tie: the top two candidates have the same count
#   - a single usage: the winner appears in only one file — too thin a sample to call a convention
# A minimum of 2 files AND a strict majority over the runner-up are both required before a name is
# emitted. Silence is the correct output in both cases: no draft is safer than a wrong one.
#
# Bash 3.2 compatible (macOS default) — indexed arrays only, no associative arrays.
set -u

PROJECT_ROOT="${1:-.}"
CATEGORY="${2:-}"

if [ -z "$PROJECT_ROOT" ] || [ ! -d "$PROJECT_ROOT" ]; then
  exit 2
fi

# Each line: name|grep-ERE-pattern|comma-separated-name-globs
# One heredoc per category — deliberately not exhaustive (SPEC scope: HTTP client, logger, config
# module). A stack with no candidate list below (e.g. rust, generic) simply detects nothing, which
# is the correct "no dominant mechanism" outcome for that stack.
candidates() {
  case "$CATEGORY" in
    http)
      cat <<'EOF'
httpx|import httpx|*.py
requests|import requests|*.py
urllib|import urllib\.request|*.py
aiohttp|import aiohttp|*.py
axios|axios|*.ts,*.tsx,*.js,*.jsx
node-fetch|node-fetch|*.ts,*.tsx,*.js,*.jsx
undici|undici|*.ts,*.tsx,*.js,*.jsx
URLSession|URLSession|*.swift
Alamofire|Alamofire|*.swift
net/http|net/http|*.go
go-resty|go-resty|*.go
EOF
      ;;
    logger)
      cat <<'EOF'
structlog|import structlog|*.py
loguru|import loguru|*.py
logging|import logging|*.py
winston|winston|*.ts,*.tsx,*.js,*.jsx
pino|pino|*.ts,*.tsx,*.js,*.jsx
os.log|import os\.log|*.swift
zap|go\.uber\.org/zap|*.go
logrus|sirupsen/logrus|*.go
EOF
      ;;
    config)
      cat <<'EOF'
pydantic-settings|pydantic_settings|*.py
python-dotenv|import dotenv|*.py
os.environ|os\.environ|*.py
dotenv|dotenv|*.ts,*.tsx,*.js,*.jsx
process.env|process\.env|*.ts,*.tsx,*.js,*.jsx
UserDefaults|UserDefaults|*.swift
viper|spf13/viper|*.go
EOF
      ;;
    *)
      exit 2
      ;;
  esac
}

# count_files <pattern> <comma-separated-globs> — number of files under PROJECT_ROOT matching one
# of the globs whose content matches the ERE pattern. Excludes common vendor/build dirs so a
# vendored dependency copy cannot masquerade as project usage.
count_files() {
  _pattern="$1"
  _globs="$2"
  _old_ifs="$IFS"
  IFS=','
  set -- $_globs
  IFS="$_old_ifs"
  _find_args=()
  for _g in "$@"; do
    if [ ${#_find_args[@]} -gt 0 ]; then
      _find_args+=(-o)
    fi
    _find_args+=(-name "$_g")
  done
  find "$PROJECT_ROOT" -type f \( "${_find_args[@]}" \) \
    ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/.venv/*' \
    ! -path '*/venv/*' ! -path '*/vendor/*' ! -path '*/build/*' \
    -print0 2>/dev/null \
    | xargs -0 grep -lE "$_pattern" 2>/dev/null \
    | wc -l | tr -d ' '
}

case "$CATEGORY" in
  http|logger|config) ;;
  *) exit 2 ;;
esac

best_name=""
best_count=0
second_count=0

while IFS='|' read -r name pattern globs; do
  [ -z "$name" ] && continue
  n=$(count_files "$pattern" "$globs")
  n=${n:-0}
  if [ "$n" -gt "$best_count" ]; then
    second_count=$best_count
    best_count=$n
    best_name=$name
  elif [ "$n" -gt "$second_count" ]; then
    second_count=$n
  fi
done <<EOF
$(candidates)
EOF

# No dominant mechanism: fewer than 2 files, or a tie with the runner-up. Silent, exit 0.
if [ "$best_count" -lt 2 ] || [ "$best_count" -le "$second_count" ]; then
  exit 0
fi

printf '%s\t%s\n' "$best_name" "$best_count"
exit 0
