#!/bin/bash
# temp-branch-reconcile.sh — registry + reconciliation for agent-created temp branches (ADR-0062
# §D3, issue #116). Git surfaces untracked FILES for free at the commit gate (commit/SKILL.md
# Step 1); it does not surface a stray BRANCH the same way — nobody notices until someone runs
# `git branch` and wonders what a leftover name was for. This script is the mechanical half of
# that gap: `register` appends a line when an agent creates a temp branch, `reconcile` reports
# every registered branch that still exists (i.e. was never cleaned up). Bash 3.2-clean: no assoc
# array, no mapfile, no ${v^^}, no <().
#
# RECONCILIATION REPORTS. IT NEVER DELETES, AND MUST NEVER GAIN A DELETE PATH.
# The spec's own case 3 (docs/specs/116-litter-and-debris-discipline-across-agen.spec.md) describes
# a repository lost to a branch cleanup. A script that auto-removes branches to enforce tidiness
# would reproduce the exact incident it exists to prevent. If you are reading this because
# reconciliation feels incomplete without a removal step — it is complete. Removing a branch stays
# a human decision, done directly with git's own branch commands, never through this script
# (ADR-0062 §D3; the standing rule is: never delete without explicit confirmation).
#
# Why reconciliation runs from vibe-status (ADR-0062 Task 4 location decision): a stray branch is
# a repo-wide housekeeping fact, not a property of the diff being committed — unlike the
# per-commit reporters in commit/SKILL.md Step 1 (secret/dependency/weakening scans, which read
# THIS commit's diff), a registered branch is only interesting on the same cadence vibe-status
# already reports ADRs, manifests and triage state on: periodic, read-only, cwd-local. Wiring it
# into every commit would add per-commit cost for a fact that rarely changes between commits on
# the same branch; vibe-status is the aggregate health report this system already has for exactly
# this shape of question, and it is read-only by construction, which matches "reports, never
# deletes" for free rather than requiring a new invariant.
#
# Registry format: one line per registration, "<branch>|<agent>|<context>|<ISO-8601 UTC>".
# Reconciliation treats "branch no longer exists in git" as reconciled — a human already removed
# it through the normal git flow — and never writes that conclusion back to the registry file.
set -u

REGISTRY="${TEMP_BRANCH_REGISTRY:-$(git rev-parse --show-toplevel 2>/dev/null)/.temp-branches.log}"

usage() {
  echo "usage: temp-branch-reconcile.sh register <branch> <agent> <context>" >&2
  echo "       temp-branch-reconcile.sh reconcile" >&2
}

cmd="${1:-}"
case "$cmd" in
  register)
    branch="${2:-}"; agent="${3:-}"; context="${4:-}"
    if [ -z "$branch" ] || [ -z "$agent" ]; then
      usage
      exit 2
    fi
    printf '%s|%s|%s|%s\n' "$branch" "$agent" "$context" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> "$REGISTRY"
    printf 'registered: %s (%s)\n' "$branch" "$agent"
    ;;
  reconcile)
    if [ ! -f "$REGISTRY" ]; then
      echo "(no temp-branch registry — nothing registered)"
      exit 0
    fi
    open_count=0
    while IFS='|' read -r branch agent context ts; do
      [ -z "$branch" ] && continue
      if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
        open_count=$((open_count + 1))
        printf 'STILL-OPEN: %s | registered-by=%s | context=%s | since=%s\n' "$branch" "$agent" "$context" "$ts"
      fi
      # A branch NOT found above is treated as reconciled. See the header: this script never
      # writes that conclusion back to the registry and never touches the branch itself.
    done < "$REGISTRY"
    if [ "$open_count" -eq 0 ]; then
      echo "(all registered temp branches reconciled)"
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
