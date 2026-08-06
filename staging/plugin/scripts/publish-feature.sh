#!/bin/bash
# publish-feature v1.0 (ADR-0022 D6) — idempotent branch/push/PR for unattended runs.
#
# Pushes a feature branch and opens a PR to the base branch. Never force-pushes, never
# merges, never enables auto-merge, never touches the base branch. Calls autopilot-guard
# first and aborts on HALT. Re-runs must not duplicate a branch or a PR.
#
# Usage:
#   publish-feature.sh --slug <slug> [--issue <N>] [--base main] --root <repo> [--dry-run]
#
# Bash 3.2 clean.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
GUARD="$SCRIPT_DIR/autopilot-guard.sh"

SLUG=""; BASE="main"; ROOT=""; DRY=0; ISSUE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) SLUG="$2"; shift 2 ;;
    --issue) ISSUE="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) printf 'publish-feature: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

fail() { printf 'publish-feature: %s\n' "$1" >&2; exit 2; }

[ -n "$SLUG" ] || fail "missing --slug"

# --issue is the ISSUE NUMBER this feature closes, and it is an ARGUMENT rather than something
# this script derives (issue #370, ADR-0128 §D1). The number is known upstream: roadmap-from-issues
# writes `- [ ] <title>  (issue #N)` into PROJECT.md, and project-conductor reads that very line to
# pick the feature. Re-deriving it here would mean matching $SLUG — the manifest topic, a slugified
# and truncated title — against docs/specs/_issue-map.tsv, whose own slug carries a `<N>-` prefix
# the manifest topic does not. That is a fuzzy match on two names that agree by convention, the
# exact shape ADR-0096 measured as wrong on 38 of 41 inputs while looking correct.
#
# Absent, the body is byte-identical to what it was before this flag existed: a roadmap not
# generated from issues legitimately has no number, and that case must stay silent, not warn.
#
# Malformed is a hard fail, not a warning, and the reasoning matters because a non-zero exit here
# STOPS the whole roadmap (project-conductor Step 5A treats it as run-level). The only caller
# passes this after extracting digits from a line it just read, so a malformed value cannot come
# from the intended path — it is a defect in that extraction, and a broken extraction breaks for
# EVERY feature. Halting on the first beats opening twelve PRs that all silently close nothing.
if [ -n "$ISSUE" ]; then
  printf '%s' "$ISSUE" | grep -qE '^[0-9]+$' \
    || fail "--issue must be digits only, got: $ISSUE"
fi
[ -n "$ROOT" ] || fail "missing --root"
[ -d "$ROOT" ] || fail "root is not a directory: $ROOT"

# BRANCH is not merely expected here — it is PRODUCED upstream under the same rule (issue #363,
# ADR-0127 §D3). concept-to-code Gate 4.0 invokes the `commit` skill with
# `--branch feat/<manifest.topic>`, and $SLUG below is that same manifest topic, so the branch this
# script pushes and the branch the feature was committed on agree by construction.
#
# Before #363 they never agreed: Gate 4.0 let `commit` derive the name from the commit SUBJECT,
# which for a planning-artifacts commit is type `docs` and therefore `chore/<subject-slug>`. The
# 2026-08-04 run published only because a human created feat/<slug> by hand first.
#
# If you change this construction, change Gate 4.0's `--branch` argument in the same edit; a
# mismatch here does not fail loudly, it pushes a branch nothing created.
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
MARKER="$ROOT/.claude/autopilot.yml"
[ -f "$MARKER" ] || fail "opt-in marker missing: $MARKER (publish disabled)"
grep -qE '^[[:space:]]*publish:[[:space:]]*true[[:space:]]*$' "$MARKER" \
  || fail "opt-in marker does not set publish: true — publish disabled"

# Guard gate (fail-safe). Abort on any HALT.
if [ -x "$GUARD" ]; then
  guard_out=$("$GUARD" --check "$ROOT" 2>&1) || {
    printf '%s\n' "$guard_out"
    fail "autopilot-guard HALT — not publishing"
  }
else
  fail "autopilot-guard not found or not executable: $GUARD"
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

# PR body. Built here rather than inline at the `gh pr create` call so the dry run can PRINT it —
# a dry run that hides the body verifies nothing about the body, which is how the missing closing
# reference survived every offline test this script has (issue #370, ADR-0128 §D3).
PR_BODY="Automated unattended run (ADR-0022 autopilot, repositioned by ADR-0127). Review and merge manually."
if [ -n "$ISSUE" ]; then
  # Own line, blank line before it: GitHub only honours a closing keyword outside a list item or
  # a code fence, and only when the PR merges into the DEFAULT branch — which is why $BASE stays
  # `main` for every feature PR (ADR-0127 §D4). A prep PR closes nothing and passes no --issue.
  PR_BODY="$PR_BODY

Closes #$ISSUE"
fi

# Open a PR only if none is open for this head branch (idempotent).
PR_URL=""
if command -v gh >/dev/null 2>&1; then
  if [ "$DRY" -eq 1 ]; then
    # stderr, never stdout: stdout carries the AUTOPILOT-PUBLISH status line the /goal evaluator
    # and the morning report parse, and polluting it would break both.
    printf 'publish-feature: [dry-run] PR body:\n%s\n' "$PR_BODY" >&2
    PR_URL="[dry-run-pr-url]"
  else
    PR_URL=$(gh pr list --head "$BRANCH" --state open --json url --jq '.[0].url // empty' 2>/dev/null)
    if [ -z "$PR_URL" ]; then
      gh pr create --base "$BASE" --head "$BRANCH" \
        --title "$SLUG" \
        --body "$PR_BODY" \
        >/dev/null 2>&1 || fail "gh pr create failed for $BRANCH"
      PR_URL=$(gh pr list --head "$BRANCH" --state open --json url --jq '.[0].url // empty' 2>/dev/null)
    fi
  fi
else
  fail "gh CLI not found — cannot open PR"
fi

# Status line for the /goal evaluator and the morning report.
printf 'AUTOPILOT-PUBLISH %s PR=%s CI=pending\n' "$SLUG" "${PR_URL:-none}"
exit 0
