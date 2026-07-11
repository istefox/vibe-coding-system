#!/usr/bin/env bash
# concept-to-code: gate0-detect.sh — bash 3.2-clean
# Detects Gate 0 criteria for a given project root.
# Usage: gate0-detect.sh <project-root> [<topic-full-title>] [<topic-slug>]
#
# Output (stdout, one key=value per line):
#   spec_adr_exist=true|false   (SPEC.md + >=1 ADR exist, not slug-disowned)
#   mode=greenfield|brownfield  (brownfield iff SPEC.md exists and not slug-mismatched)
#   file_estimate=<N>           (tracked file count, excluding build dirs)
#   file_vote=express|hybrid|standard  (<10 → express, 10-19 → hybrid, >=20 → standard)
#   keyword_vote=express|hybrid|standard  (derived from topic title, if provided)
#   spec_topic_match=true|false|unknown  (ONLY when <topic-slug> arg given)
#   skill_exists=true|false              (ONLY when <topic-slug> arg given)
#
# Exit: 0 always (detector, not validator); 1 on bad args.
set -u

if [ "$#" -lt "1" ] || [ "$#" -gt "3" ]; then
  echo "usage: gate0-detect.sh <project-root> [<topic-full-title>] [<topic-slug>]" >&2
  exit 1
fi

root="$1"
title="${2:-}"
slug_arg="${3:-}"

# Did the caller pass arg 3 at all? ($# is the reliable signal; an explicit empty
# string arg 3 still counts as "opted in" and produces the new fields.)
have_slug_arg="no"
if [ "$#" -ge "3" ]; then
  have_slug_arg="yes"
fi

spec="no"
if [ -f "$root/SPEC.md" ]; then
  spec="yes"
fi

# --- Bug 1 fix: SPEC.md topic-slug match ----------------------------------------
# spec_topic_match is computed only when the caller opted in (arg 3 present)
# AND a SPEC.md exists. Values: true | false | unknown.
spec_topic_match="unknown"
if [ "$have_slug_arg" = "yes" ] && [ "$spec" = "yes" ]; then
  # Extract the first matching marker line: "**Topic slug:** <value>"
  # Label is case-insensitive; first match wins (-m 1).
  marker_raw="$(grep -i -m 1 -E '^\*\*[[:space:]]*topic[[:space:]]+slug[[:space:]]*:\*\*' \
                  "$root/SPEC.md" 2>/dev/null)"
  if [ -n "$marker_raw" ]; then
    # Strip the "**...:**" label, trim whitespace + surrounding backticks, lowercase.
    marker_val="$(printf '%s\n' "$marker_raw" \
      | sed -E 's/^\*\*[^*]*\*\*[[:space:]]*//')"
    marker_norm="$(printf '%s' "$marker_val" \
      | sed -E 's/^[[:space:]]*`?//; s/`?[[:space:]]*$//' \
      | tr '[:upper:]' '[:lower:]')"
    slug_norm="$(printf '%s' "$slug_arg" \
      | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//' \
      | tr '[:upper:]' '[:lower:]')"
    if [ "$marker_norm" = "$slug_norm" ]; then
      spec_topic_match="true"
    else
      spec_topic_match="false"
    fi
  else
    spec_topic_match="unknown"  # legacy SPEC without slug marker
  fi
fi

# A slug mismatch disowns the SPEC: treat as if no SPEC belongs to this chain.
spec_owned="$spec"
if [ "$spec_topic_match" = "false" ]; then
  spec_owned="no"
fi

adr="no"
if ls "$root"/docs/architecture/ADR-*.md >/dev/null 2>&1; then
  adr="yes"
fi

# spec_adr_exist gated on the OWNED spec, not raw file-presence.
if [ "$spec_owned" = "yes" ] && [ "$adr" = "yes" ]; then
  echo "spec_adr_exist=true"
else
  echo "spec_adr_exist=false"
fi

if [ "$spec_owned" = "yes" ]; then
  echo "mode=brownfield"
else
  echo "mode=greenfield"
fi

# File estimate: count tracked files, excluding build/dependency dirs.
# grep -v is bash 3.2-clean (no find -not pattern issues on macOS).
file_count="$(find "$root" -type f \
  | grep -v '/.git/' \
  | grep -v '/node_modules/' \
  | grep -v '/.venv/' \
  | grep -v '/build/' \
  | grep -v '/DerivedData/' \
  | grep -v '/\.build/' \
  | wc -l | tr -d ' ')"

echo "file_estimate=$file_count"

if [ "$file_count" -lt 10 ]; then
  echo "file_vote=express"
elif [ "$file_count" -lt 20 ]; then
  echo "file_vote=hybrid"
else
  echo "file_vote=standard"
fi

# Keyword vote: scan topic title if provided.
keyword_vote="express"
if [ -n "$title" ]; then
  if echo "$title" | grep -iEq 'architecture|migration|multi.layer|multi.service|api.design|adr'; then
    keyword_vote="standard"
  elif echo "$title" | grep -iEq 'app|feature|module|screen|endpoint|view|component'; then
    keyword_vote="hybrid"
  fi
fi
echo "keyword_vote=$keyword_vote"

# Feature 4 + Bug 1 detection: emitted ONLY when arg 3 was passed.
if [ "$have_slug_arg" = "yes" ]; then
  echo "spec_topic_match=$spec_topic_match"

  # Informational skill-exists flag. Does not affect mode/spec_adr_exist.
  if [ -f "$HOME/.claude/skills/$slug_arg/SKILL.md" ]; then
    echo "skill_exists=true"
  else
    echo "skill_exists=false"
  fi
fi

exit 0
