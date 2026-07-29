#!/bin/bash
# detect-public-remote.sh — D1: detect if repo root has a public GitHub remote.
# Fail-safe cascade toward "silent": every uncertain or non-github case outputs "silent".
# xref-exempt: line 1|line 2 — stdout positions in this script's own output contract, not a
# reference into another file. Callers parse by position, so the numbers are the contract itself.
# Stdout: "public" (line 1) + "repo=<owner/repo>" (line 2) when public GitHub detected.
#         "silent" (line 1 only) in all other cases.
# Exit 0 always (classification is in stdout, not exit code).
#
# Bash 3.2-clean: no assoc arrays, no mapfile, no ${v^^}, no <(), no <<<
set -u

ROOT="${1:-$PWD}"

# Step 1: must be inside a git work tree
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "silent"
  exit 0
fi

# Step 2: get the remote URL (prefer origin, fallback to first remote)
REMOTE_URL=""
REMOTE_URL=$(git -C "$ROOT" remote get-url origin 2>/dev/null)
if [ -z "$REMOTE_URL" ]; then
  # try first remote listed
  FIRST_REMOTE=$(git -C "$ROOT" remote 2>/dev/null | head -1)
  if [ -z "$FIRST_REMOTE" ]; then
    echo "silent"
    exit 0
  fi
  REMOTE_URL=$(git -C "$ROOT" remote get-url "$FIRST_REMOTE" 2>/dev/null)
fi

if [ -z "$REMOTE_URL" ]; then
  echo "silent"
  exit 0
fi

# Step 3: host must be github.com (scope per SPEC R1)
echo "$REMOTE_URL" | grep -Eq 'github\.com'
if [ $? -ne 0 ]; then
  echo "silent"
  exit 0
fi

# Step 4: extract owner/repo from URL
# Handles both HTTPS (https://github.com/owner/repo.git) and SSH (git@github.com:owner/repo.git)
OWNER_REPO=""
# SSH pattern: git@github.com:owner/repo.git
OWNER_REPO=$(echo "$REMOTE_URL" | sed -n 's|.*github\.com[:/]\([^/]*/[^/]*\)\.git$|\1|p')
if [ -z "$OWNER_REPO" ]; then
  # SSH without .git or HTTPS without .git
  OWNER_REPO=$(echo "$REMOTE_URL" | sed -n 's|.*github\.com[:/]\([^/]*/[^/]*\)$|\1|p')
fi
if [ -z "$OWNER_REPO" ]; then
  # Fail-safe (ADR-0011 D1): non-canonical URLs (trailing slash, sub-path like
  # /tree/main, or any owner/repo we cannot extract cleanly) intentionally fall
  # to silent rather than guessing — a false "public" is the defect to avoid.
  echo "silent"
  exit 0
fi

# Step 5: check gh availability and authentication
command -v gh >/dev/null 2>&1
if [ $? -ne 0 ]; then
  # gh not installed — visibility not determinable
  echo "silent"
  exit 0
fi

gh auth status >/dev/null 2>&1
if [ $? -ne 0 ]; then
  # gh not authenticated — visibility not determinable
  echo "silent"
  exit 0
fi

# Step 6: query visibility via gh API
VISIBILITY=$(gh repo view "$OWNER_REPO" --json visibility -q .visibility 2>/dev/null)
if [ "$VISIBILITY" = "PUBLIC" ]; then
  echo "public"
  echo "repo=$OWNER_REPO"
  exit 0
fi

# PRIVATE, INTERNAL, error, or empty — fail-safe silent
echo "silent"
exit 0
