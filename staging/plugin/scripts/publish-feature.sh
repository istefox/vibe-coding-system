#!/bin/bash
# publish-feature v1.0 (ADR-0022 D6) — idempotent branch/push/PR for overnight runs.
#
# Pushes a feature branch and opens a PR to the base branch. Never force-pushes, never
# merges, never enables auto-merge, never touches the base branch. Calls nightly-guard
# first and aborts on HALT. Re-runs must not duplicate a branch or a PR.
#
# Usage:
#   publish-feature.sh --slug <slug> [--base main] --root <repo> [--dry-run]
#
# Bash 3.2 clean.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
GUARD="$SCRIPT_DIR/nightly-guard.sh"

SLUG=""; BASE="main"; ROOT=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) SLUG="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) printf 'publish-feature: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

fail() { printf 'publish-feature: %s\n' "$1" >&2; exit 2; }

[ -n "$SLUG" ] || fail "missing --slug"
[ -n "$ROOT" ] || fail "missing --root"
[ -d "$ROOT" ] || fail "root is not a directory: $ROOT"

BRANCH="feat/$SLUG"

# Hard safety: never operate on the base branch itself.
[ "$BRANCH" = "$BASE" ] && fail "refusing: feature branch equals base ($BASE)"
if [ "$SLUG" = "main" ] || [ "$SLUG" = "master" ]; then
  fail "refusing: slug resolves to a protected branch"
fi

cd "$ROOT" || fail "cannot cd into root: $ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || fail "root is not a git repository: $ROOT"
git remote get-url origin >/dev/null 2>&1 || fail "no 'origin' remote configured"

# Per-repo opt-in marker (ADR-0022 D3).
MARKER="$ROOT/.claude/nightly-autopilot.yml"
[ -f "$MARKER" ] || fail "opt-in marker missing: $MARKER (publish disabled)"
grep -qE '^[[:space:]]*publish:[[:space:]]*true[[:space:]]*$' "$MARKER" \
  || fail "opt-in marker does not set publish: true — publish disabled"

# Guard gate (fail-safe). Abort on any HALT.
if [ -x "$GUARD" ]; then
  guard_out=$("$GUARD" --check "$ROOT" 2>&1) || {
    printf '%s\n' "$guard_out"
    fail "nightly-guard HALT — not publishing"
  }
else
  fail "nightly-guard not found or not executable: $GUARD"
fi

run() {
  if [ "$DRY" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# Branch: reuse if it exists, else create from current HEAD (idempotent).
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  run git checkout "$BRANCH"
else
  run git checkout -b "$BRANCH"
fi

# Push the feature branch only. Never --force. A failed push must abort, not fall through to
# reporting an old PR as if the new commits shipped (review finding #2).
run git push -u origin "$BRANCH" || fail "git push failed for $BRANCH"

# After a real push, the remote head must match local HEAD, else something republished stale
# commits. Skip in dry-run (nothing was pushed).
if [ "$DRY" -eq 0 ]; then
  local_head=$(git rev-parse HEAD 2>/dev/null)
  remote_head=$(git rev-parse "origin/$BRANCH" 2>/dev/null)
  [ "$local_head" = "$remote_head" ] || fail "remote $BRANCH head ($remote_head) != local HEAD ($local_head)"
fi

# Open a PR only if none is open for this head branch (idempotent).
PR_URL=""
if command -v gh >/dev/null 2>&1; then
  if [ "$DRY" -eq 1 ]; then
    PR_URL="[dry-run-pr-url]"
  else
    PR_URL=$(gh pr list --head "$BRANCH" --state open --json url --jq '.[0].url // empty' 2>/dev/null)
    if [ -z "$PR_URL" ]; then
      gh pr create --base "$BASE" --head "$BRANCH" \
        --title "$SLUG" \
        --body "Automated overnight run (ADR-0022 nightly-autopilot). Review and merge manually." \
        >/dev/null 2>&1 || fail "gh pr create failed for $BRANCH"
      PR_URL=$(gh pr list --head "$BRANCH" --state open --json url --jq '.[0].url // empty' 2>/dev/null)
    fi
  fi
else
  fail "gh CLI not found — cannot open PR"
fi

# Status line for the /goal evaluator and the morning report.
printf 'NIGHTLY-PUBLISH %s PR=%s CI=pending\n' "$SLUG" "${PR_URL:-none}"
exit 0
