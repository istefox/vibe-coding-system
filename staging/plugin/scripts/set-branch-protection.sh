#!/bin/bash
# set-branch-protection v1.0 (ADR-0022 D8) — require the CI check and a PR on main.
#
# Idempotent: a PUT to the protection endpoint is repeatable, and this script never
# lowers an existing stricter approval count (it takes the max of current and desired).
# Never disables force-push/deletion protection that is already on; it only enforces.
#
# Usage:
#   set-branch-protection.sh [--repo owner/name] [--branch main] [--check ci] [--dry-run]
#
# Requires: gh authenticated with admin on the repo. Bash 3.2 clean.

set -u

REPO=""; BRANCH="main"; CHECK="ci"; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --check) CHECK="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) printf 'set-branch-protection: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

fail() { printf 'set-branch-protection: %s\n' "$1" >&2; exit 2; }

command -v gh >/dev/null 2>&1 || fail "gh CLI not found"

command -v jq >/dev/null 2>&1 || fail "jq required to merge branch protection without clobbering it"

if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
  [ -n "$REPO" ] || fail "could not resolve repo; pass --repo owner/name"
fi

# GitHub's protection PUT is a full replace, so preserve every stricter setting already in
# place (review finding #3): union the required checks, keep push restrictions, keep strict,
# never lower the approval count.
CUR=$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null)

CTX_JSON=$(printf '%s' "$CUR" | jq -c --arg c "$CHECK" \
  '((.required_status_checks.contexts // []) + [$c]) | unique' 2>/dev/null)
case "$CTX_JSON" in ''|null) CTX_JSON="[\"$CHECK\"]";; esac

STRICT=$(printf '%s' "$CUR" | jq -r '.required_status_checks.strict // true' 2>/dev/null)
case "$STRICT" in true|false) : ;; *) STRICT=true;; esac

RESTR_JSON=$(printf '%s' "$CUR" | jq -c \
  'if (.restrictions == null) then null else {users: [.restrictions.users[].login], teams: [.restrictions.teams[].slug], apps: [.restrictions.apps[].slug]} end' 2>/dev/null)
case "$RESTR_JSON" in '') RESTR_JSON=null;; esac

DESIRED_APPROVALS=$(printf '%s' "$CUR" | jq -r '.required_pull_request_reviews.required_approving_review_count // 0' 2>/dev/null)
case "$DESIRED_APPROVALS" in ''|*[!0-9]*) DESIRED_APPROVALS=0;; esac

BODY=$(cat <<JSON
{
  "required_status_checks": { "strict": $STRICT, "contexts": $CTX_JSON },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": $DESIRED_APPROVALS },
  "restrictions": $RESTR_JSON,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
)

if [ "$DRY" -eq 1 ]; then
  printf '[dry-run] PUT repos/%s/branches/%s/protection\n%s\n' "$REPO" "$BRANCH" "$BODY"
  exit 0
fi

printf '%s' "$BODY" | gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
  -H "Accept: application/vnd.github+json" --input - >/dev/null 2>&1 \
  || fail "failed to set branch protection on $REPO@$BRANCH (need admin?)"

printf 'branch protection set on %s@%s: require check "%s" + require PR (approvals=%s)\n' \
  "$REPO" "$BRANCH" "$CHECK" "$DESIRED_APPROVALS"
exit 0
