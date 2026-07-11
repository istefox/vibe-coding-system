#!/bin/bash
# fresh-history-publish.sh — D5: fresh-history publish helper.
# Guides the orchestrator through creating a clean orphan-branch publish.
# NEVER pushes automatically; NEVER creates a remote repo automatically.
# Operates entirely locally; all destructive / remote actions require explicit HITL.
#
# Usage: fresh-history-publish.sh <ROOT> [dry-run|prepare]
#   ROOT      — path to the git repository root (default: $PWD)
#   MODE      — dry-run (default, non-mutating) | prepare (safe local setup, then STOP)
#
# Exit codes:
#   0 — success (dry-run printed plan, or prepare completed local setup)
#   2 — not a git repository or precondition error
#   5 — safety abort: a .git-backup-*.tar.gz path was staged (would leak private history)
#
# Bash 3.2-clean: no assoc arrays, no mapfile, no ${v^^}, no <(), no <<<
set -u

ROOT="${1:-$PWD}"
MODE="${2:-dry-run}"

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------
info() { echo "[fresh-history] INFO:  $*"; }
warn() { echo "[fresh-history] WARN:  $*"; }
err()  { echo "[fresh-history] ERROR: $*" >&2; }

# -----------------------------------------------------------------------
# Precondition: must be a git repository
# -----------------------------------------------------------------------
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1
if [ $? -ne 0 ]; then
  err "Not a git repository: $ROOT"
  err "Cannot proceed — fresh-history publish requires a git repo."
  exit 2
fi

# -----------------------------------------------------------------------
# Resolve the true repository top-level (ROOT may be any subdirectory of it)
# -----------------------------------------------------------------------
GIT_TOPLEVEL=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$GIT_TOPLEVEL" ]; then
  err "Could not resolve the repository top-level directory for: $ROOT"
  exit 2
fi

# -----------------------------------------------------------------------
# Warn if working tree is dirty
# -----------------------------------------------------------------------
DIRTY=$(git -C "$ROOT" status --porcelain 2>/dev/null)
if [ -n "$DIRTY" ]; then
  warn "Working tree has uncommitted changes."
  warn "Commit or stash them before running 'prepare' to ensure a clean snapshot."
fi

# -----------------------------------------------------------------------
# Timestamp for backup name
# -----------------------------------------------------------------------
TS=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME=".git-backup-${TS}.tar.gz"
# Written outside the work tree (the true top-level's parent), never inside ROOT: this is
# what keeps the private-history backup from ever being swept up by `git add -A` below.
BACKUP_PATH="$(dirname "$GIT_TOPLEVEL")/${BACKUP_NAME}"

# -----------------------------------------------------------------------
# MODE: dry-run — print the plan, mutate NOTHING
# -----------------------------------------------------------------------
if [ "$MODE" = "dry-run" ]; then
  info "=== FRESH-HISTORY PUBLISH — DRY-RUN PLAN ==="
  info ""
  info "Step 1 — Backup (would create):"
  info "  tar -czf \"${BACKUP_PATH}\" -C \"${GIT_TOPLEVEL}\" .git"
  info "  This preserves the full original history locally."
  info ""
  info "Step 2 — Orphan branch (would create):"
  info "  git -C \"${ROOT}\" checkout --orphan public-clean"
  info "  git -C \"${ROOT}\" add -A"
  info "  (prepare mode also runs a safety check here: hard-fails, exit 5, if any"
  info "   .git-backup-*.tar.gz path is found staged, so the private-history backup"
  info "   can never ship inside the public commit)"
  info "  The branch 'public-clean' starts with NO prior history."
  info ""
  info "Step 3 — Single curated commit (would create):"
  info "  git -C \"${ROOT}\" commit -m \"Initial public release\""
  info "  One commit, clean working-tree snapshot, no tool-trace messages."
  info ""
  info "Step 4 — Push to a NEW public repo (NOT force-push on original):"
  info "  Create a new repo on GitHub (e.g. via 'gh repo create')."
  info "  git remote add public <new-repo-url>"
  info "  git push public public-clean:main"
  info "  The original repo with full history stays PRIVATE."
  info "  NO force-push on the original repo — original history is never rewritten."
  info ""
  if command -v gh >/dev/null 2>&1; then
    info "  'gh' detected — on confirmation, suggest:"
    info "    gh repo create <owner/new-repo-name> --public --source=. --push"
    info "  (adjust name/org as needed; run from the root after prepare+commit)"
  else
    info "  'gh' not installed — create the repo manually on github.com, then:"
    info "    git remote add public https://github.com/<owner>/<new-repo>.git"
    info "    git push public public-clean:main"
  fi
  info ""
  info "=== DRY-RUN COMPLETE — no changes made ==="
  exit 0
fi

# -----------------------------------------------------------------------
# MODE: prepare — non-destructive local steps only, then STOP for HITL
# -----------------------------------------------------------------------
if [ "$MODE" = "prepare" ]; then
  info "=== FRESH-HISTORY PUBLISH — PREPARE MODE ==="
  info "Performing non-destructive local steps only."
  info "Will STOP before commit/push and instruct HITL confirmation."
  info ""

  # Step 1: backup tar (non-destructive — adds a file, does not alter .git)
  # -C uses GIT_TOPLEVEL (not the raw ROOT argument): .git only exists literally at the
  # true top-level, so this also makes prepare work when ROOT is a subdirectory of the repo.
  info "Step 1 — Creating backup of .git ..."
  tar -czf "$BACKUP_PATH" -C "$GIT_TOPLEVEL" .git 2>/dev/null
  if [ $? -ne 0 ]; then
    err "Backup failed. Aborting."
    exit 2
  fi
  info "  Backup created: ${BACKUP_PATH}"
  info "  Keep this file until you have verified the public repo is correct."
  info ""

  # Step 2: create orphan branch locally
  info "Step 2 — Creating orphan branch 'public-clean' locally ..."
  # Check if branch already exists
  git -C "$ROOT" branch | grep -q 'public-clean'
  if [ $? -eq 0 ]; then
    warn "  Branch 'public-clean' already exists — skipping checkout --orphan."
    warn "  Delete it first with 'git branch -D public-clean' if you want to recreate."
  else
    git -C "$ROOT" checkout --orphan public-clean 2>/dev/null
    if [ $? -ne 0 ]; then
      err "Failed to create orphan branch. Aborting."
      exit 2
    fi
    info "  Orphan branch 'public-clean' created."
  fi
  info ""

  # Step 3: stage all files
  info "Step 3 — Staging all files for the clean commit ..."
  git -C "$ROOT" add -A 2>/dev/null
  if [ $? -ne 0 ]; then
    err "git add -A failed. Aborting."
    exit 2
  fi
  info "  All files staged."
  info ""

  # Independent hard-fail guard: catches a staged .git-backup-*.tar.gz path regardless of
  # mechanism (relocation above closes the specific cause; this closes the pattern), e.g.
  # a stray backup left inside ROOT by an interrupted prior run.
  STAGED_BACKUP=$(git -C "$ROOT" ls-files 2>/dev/null | grep -E '(^|/)\.git-backup-.*\.tar\.gz$')
  if [ -n "$STAGED_BACKUP" ]; then
    err "SAFETY ABORT: the following .git-backup-*.tar.gz path(s) are staged for commit:"
    printf '%s\n' "$STAGED_BACKUP" | while read -r p; do err "  $p"; done
    err "Committing this would ship the full private git history inside the public release."
    err "Unstage it and investigate, e.g.: git -C \"$ROOT\" reset -- <path>"
    exit 5
  fi
  info "  Safety check passed: no .git-backup-*.tar.gz path is staged."
  info ""

  # STOP — HITL required before commit and push
  info "=== PREPARE COMPLETE — STOP FOR HITL ==="
  info ""
  info "Local setup is ready. The following steps require EXPLICIT USER CONFIRMATION:"
  info ""
  info "  NEXT: Review staged files with 'git diff --cached --name-only'"
  info "        then commit:"
  info "    git -C \"${ROOT}\" commit -m \"Initial public release\""
  info ""
  info "  THEN: Create a NEW public repository on GitHub (do NOT force-push original):"
  if command -v gh >/dev/null 2>&1; then
    info "    gh repo create <owner/new-repo-name> --public"
    info "    git -C \"${ROOT}\" remote add public <new-repo-url>"
  else
    info "    Create the repo on github.com, then:"
    info "    git -C \"${ROOT}\" remote add public https://github.com/<owner>/<new-repo>.git"
  fi
  info "    git -C \"${ROOT}\" push public public-clean:main"
  info ""
  info "  IMPORTANT: Do NOT force-push on the original repo."
  info "  The original branch with full history stays local and private."
  info ""
  info "  Orchestrator: present this HITL to the user before proceeding."
  exit 0
fi

# -----------------------------------------------------------------------
# Unknown mode
# -----------------------------------------------------------------------
err "Unknown mode: '${MODE}'. Use 'dry-run' (default) or 'prepare'."
exit 2
