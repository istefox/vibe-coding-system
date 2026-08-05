#!/usr/bin/env bash
# roadmap-from-issues v1.0 (ADR-0023 D6). Builds PROJECT.md and docs/specs/_issue-map.tsv from
# open GitHub issues carrying a label. One issue becomes one roadmap feature. Idempotent: a
# feature already listed (matched by "(issue #N)") is not duplicated on re-run.
#
# Untrusted-input hardening (ADR-0059 / issue #113): the issue TITLE is the only field this
# script reads, and it is written verbatim into PROJECT.md, a file every downstream chain step
# reads as roadmap content. Each title is scanned before it is written; a shape-matched title is
# SKIPPED (not added to PROJECT.md or the issue-map) with a per-feature skip note — the same SKIP
# mechanism spec-from-issue uses for a thin or injection-shaped body (§D3), applied here to the
# other entry point that reads the same untrusted source. This is a mitigation, not a boundary
# (§D1) and runs unconditionally regardless of repo visibility (§D5).
#
# The skip note target is `.claude/autopilot-state/skipped-features`, a per-feature note distinct
# from the run-level halt marker autopilot-guard.sh reads (ADR-0060 §D3, issue #114): before that
# fix this script wrote to the run-level marker directly, so one injection-suspect issue title
# silently halted every other feature in the roadmap. See autopilot-guard.sh's own header comment
# for the full split.
#
# Usage: roadmap-from-issues.sh --root <dir> --label <label> [--dry-run]
#        [--issues-json <file>]   # test hook: read gh JSON from a file instead of calling gh
# Bash 3.2 clean.
set -euo pipefail

ROOT="."; LABEL=""; DRY=0; JSON_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --issues-json) JSON_FILE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "roadmap-from-issues: unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -d "$ROOT" ] || { echo "roadmap-from-issues: not a dir: $ROOT" >&2; exit 2; }
[ -n "$LABEL" ] || { echo "roadmap-from-issues: --label required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "roadmap-from-issues: jq required" >&2; exit 2; }

# Sibling script, same directory in both the staging tree and the deployed ~/.claude/hooks/ tree
# (ADR-0059). Resolved before cd "$ROOT" so it works regardless of $0's relativity to the target.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCAN="$SCRIPT_DIR/untrusted-input-scan.sh"

cd "$ROOT"

# slugify: lowercase, non-alnum -> '-', squeeze, trim, max 40 chars.
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//'
}

# Source issues as TSV: number<TAB>title
if [ -n "$JSON_FILE" ]; then
  TSV=$(jq -r '.[] | [.number, .title] | @tsv' "$JSON_FILE")
else
  command -v gh >/dev/null 2>&1 || { echo "roadmap-from-issues: gh required" >&2; exit 2; }
  TSV=$(gh issue list --label "$LABEL" --state open --limit 200 --json number,title --jq '.[] | [.number, .title] | @tsv')
fi

REPO_NAME=$(basename "$(pwd -P)")
PMD="PROJECT.md"
MAP="docs/specs/_issue-map.tsv"

if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] issues for label '$LABEL':"
  printf '%s\n' "$TSV" | sed 's/^/  /'
  exit 0
fi
mkdir -p docs/specs

# Create PROJECT.md skeleton if absent.
if [ ! -f "$PMD" ]; then
  {
    printf '# Project: %s\n\n' "$REPO_NAME"
    printf '## Overview\nAuto-generated roadmap from issues labeled `%s` (ADR-0023).\n\n' "$LABEL"
    printf '## Phases\n\n### Phase 1 — %s\n' "$LABEL"
  } > "$PMD"
fi

added=0
skipped=0
# read TSV lines
while IFS=$(printf '\t') read -r num title; do
  [ -z "$num" ] && continue
  # skip if this issue is already a feature line
  if grep -q "(issue #$num)" "$PMD" 2>/dev/null; then continue; fi

  # Untrusted-input scan on the title (ADR-0059 §D3/§D5). Always exits 0 (reporter contract); the
  # caller idiom is grep -q '^INJECTION', never [ -n "$out" ] and never grep -c ... || echo 0.
  _scan_out="CLEAN"
  if [ -f "$SCAN" ]; then
    _scan_out=$(printf '%s\n' "$title" | bash "$SCAN" 2>/dev/null || true)
  fi
  if printf '%s\n' "$_scan_out" | grep -q '^INJECTION'; then
    _rule=$(printf '%s\n' "$_scan_out" | head -1 | cut -f2)
    mkdir -p .claude/autopilot-state
    printf 'issue #%s "%s" skipped: injection-shaped content detected in title (%s)\n' \
      "$num" "$title" "$_rule" >> .claude/autopilot-state/skipped-features
    skipped=$((skipped+1))
    continue
  fi

  printf -- '- [ ] %s  (issue #%s)\n' "$title" "$num" >> "$PMD"
  # Slug is prefixed with the issue number so it is unique (two titles can slugify the same)
  # and resolvable by number: project-conductor globs docs/specs/<num>-*.spec.md.
  slug="$num-$(slugify "$title")"
  printf '%s\t%s\t%s\n' "$slug" "$num" "$title" >> "$MAP"
  added=$((added+1))
done <<EOF
$TSV
EOF

echo "roadmap-from-issues: $added feature(s) added to $PMD (label $LABEL); map: $MAP; $skipped skipped (injection-shaped title)"
