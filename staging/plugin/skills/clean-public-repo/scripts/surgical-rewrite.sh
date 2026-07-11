#!/bin/bash
# surgical-rewrite.sh — D6: surgical history rewrite orchestrator (safety wrapper).
# Wraps git-filter-repo with mandatory backup, dry-run first, and HITL before force-push.
# NEVER executes force-push automatically.
# This script is OPTION 2 (not the default). Default is fresh-history-publish.sh.
#
# Usage: surgical-rewrite.sh <ROOT> <PATTERNS_FILE> [dry-run|apply]
#   ROOT          — path to the git repository (must be a fresh clone)
#   PATTERNS_FILE — file of replacement patterns for --replace-text
#                   format: "pattern==>replacement" (one per line)
#   MODE          — dry-run (default) | apply
#
# Exit codes:
#   0 — success (dry-run shown, or apply completed up to HITL stop)
#   2 — not a git repository or other precondition error
#   3 — git-filter-repo not installed (degrade graceful)
#   4 — repo is not a fresh clone (protection — use --force flag to override)
#
# HARD constraints (ADR D6 / ADR D8):
#   - Never executes force-push (always STOP + HITL before push)
#   - Always creates backup tar of .git before any operation
#   - Respects git-filter-repo's fresh-clone protection (never passes --force)
#   - If git-filter-repo absent: print install instructions + exit 3
#
# Bash 3.2-clean: no assoc arrays, no mapfile, no ${v^^}, no <(), no <<<
set -u

ROOT="${1:-}"
PATTERNS_FILE="${2:-}"
MODE="${3:-dry-run}"
FORCE_FRESH="${4:-}"   # pass "--force" as 4th arg to skip fresh-clone check (expert use)

# -----------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------
info() { echo "[surgical-rewrite] INFO:  $*"; }
warn() { echo "[surgical-rewrite] WARN:  $*"; }
err()  { echo "[surgical-rewrite] ERROR: $*" >&2; }

# -----------------------------------------------------------------------
# Validate required arguments
# -----------------------------------------------------------------------
if [ -z "$ROOT" ] || [ -z "$PATTERNS_FILE" ]; then
  err "Usage: surgical-rewrite.sh <ROOT> <PATTERNS_FILE> [dry-run|apply]"
  exit 2
fi

# -----------------------------------------------------------------------
# Degrade graceful: git-filter-repo must be present
# -----------------------------------------------------------------------
git filter-repo --version >/dev/null 2>&1
if [ $? -ne 0 ]; then
  err "git-filter-repo is NOT installed."
  err ""
  err "Install it with one of:"
  err "  brew install git-filter-repo"
  err "  pip3 install git-filter-repo"
  err ""
  err "Surgical rewrite disabled — use fresh-history-publish.sh instead."
  err "(fresh-history publish requires only git core and is the recommended default"
  err " for already-public repos: no force-push on the original, no history rewrite.)"
  exit 3
fi

# -----------------------------------------------------------------------
# Precondition: patterns file must exist
# -----------------------------------------------------------------------
if [ ! -f "$PATTERNS_FILE" ]; then
  err "Patterns file not found: $PATTERNS_FILE"
  exit 2
fi

# -----------------------------------------------------------------------
# Precondition: must be a git repository
# -----------------------------------------------------------------------
git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1
if [ $? -ne 0 ]; then
  err "Not a git repository: $ROOT"
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
# Precondition: fresh-clone check
# git-filter-repo refuses non-fresh-clone by default (safety feature).
# We respect this; never pass --force to bypass it.
# A fresh clone has no stash, no modified tracked files, and typically
# has remote refs equal to local refs (indicative only — exact heuristic).
# -----------------------------------------------------------------------
if [ "$FORCE_FRESH" != "--force" ]; then
  # Check for uncommitted changes (dirty working tree → definitely not fresh)
  DIRTY=$(git -C "$ROOT" status --porcelain 2>/dev/null)
  if [ -n "$DIRTY" ]; then
    err "Repo has uncommitted changes — this is NOT a fresh clone."
    err ""
    err "git-filter-repo requires operating on a fresh clone to protect your data."
    err "Steps to proceed:"
    err "  1. git clone <original-repo-url> <fresh-clone-path>"
    err "  2. Run this script against <fresh-clone-path>"
    err "  3. After verifying the rewrite, force-push the fresh clone back."
    err "     (Force-push requires EXPLICIT user confirmation — never automatic.)"
    err ""
    err "Aborting (exit 4). Pass '--force' as 4th argument ONLY if you are certain"
    err "this is intended and have a backup."
    exit 4
  fi

  # Check for stash entries
  STASH=$(git -C "$ROOT" stash list 2>/dev/null)
  if [ -n "$STASH" ]; then
    err "Repo has stash entries — likely not a fresh clone."
    err "Please operate on a fresh clone. See instructions above."
    exit 4
  fi
fi

# -----------------------------------------------------------------------
# Timestamp for backup name
# -----------------------------------------------------------------------
TS=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME=".git-backup-${TS}.tar.gz"
# Written outside the work tree (the true top-level's parent), same rationale as
# fresh-history-publish.sh: a stray backup left inside ROOT is a hygiene/consistency
# risk this script never itself stages, but should still not sit inside the clean clone.
BACKUP_PATH="$(dirname "$GIT_TOPLEVEL")/${BACKUP_NAME}"

# -----------------------------------------------------------------------
# MODE: dry-run — show what would change, mutate NOTHING in history
# -----------------------------------------------------------------------
if [ "$MODE" = "dry-run" ]; then
  info "=== SURGICAL REWRITE — DRY-RUN ==="
  info ""
  info "Patterns file: ${PATTERNS_FILE}"
  info "Repository:    ${ROOT}"
  info ""
  info "Running: git filter-repo --replace-text \"${PATTERNS_FILE}\" --dry-run"
  info "(No history is modified in dry-run mode.)"
  info ""

  git -C "$ROOT" filter-repo --replace-text "$PATTERNS_FILE" --dry-run 2>&1
  FILTER_EXIT=$?

  info ""
  if [ $FILTER_EXIT -eq 0 ]; then
    info "Dry-run completed. Review the output above to confirm replacements."
    info ""
    info "Note on commit message trailers:"
    info "  --replace-text handles file content."
    info "  For commit message trailers (Co-Authored-By, Generated with Claude Code),"
    info "  add a --message-callback to the apply command, e.g.:"
    info "    git filter-repo --replace-text <file> --message-callback \\"
    info "      'return re.sub(b\"Co-Authored-By:.*Claude.*\\\\n?\", b\"\", message)'"
    info ""
    info "To apply the rewrite, run: surgical-rewrite.sh \"${ROOT}\" \"${PATTERNS_FILE}\" apply"
  else
    warn "git filter-repo --dry-run exited with code ${FILTER_EXIT}."
    warn "Inspect the output above. Common cause: non-fresh-clone detection by git-filter-repo."
    warn "Operate on a fresh clone: git clone <url> <fresh-path>"
  fi
  exit 0
fi

# -----------------------------------------------------------------------
# MODE: apply — perform the rewrite, then STOP for HITL before force-push
# -----------------------------------------------------------------------
if [ "$MODE" = "apply" ]; then
  info "=== SURGICAL REWRITE — APPLY MODE ==="
  info ""

  # Step 1: mandatory backup of .git before any destructive operation
  # -C uses GIT_TOPLEVEL (not the raw ROOT argument): .git only exists literally at the
  # true top-level.
  info "Step 1 — Creating mandatory backup of .git ..."
  tar -czf "$BACKUP_PATH" -C "$GIT_TOPLEVEL" .git 2>/dev/null
  if [ $? -ne 0 ]; then
    err "Backup failed. Aborting — no history has been modified."
    exit 2
  fi
  info "  Backup created: ${BACKUP_PATH}"
  info "  Keep this backup until you have verified the rewrite result."
  info ""

  # Step 2: create a backup branch/tag before rewrite
  BACKUP_BRANCH="pre-rewrite-backup-${TS}"
  info "Step 2 — Creating backup branch '${BACKUP_BRANCH}' ..."
  CURRENT_BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
  # In detached HEAD state rev-parse returns the literal "HEAD"; use a descriptive fallback
  if [ "$CURRENT_BRANCH" = "HEAD" ]; then
    CURRENT_BRANCH="your current branch (detached HEAD — resolve before pushing)"
  fi
  # Captured now, before Step 3's filter-repo run unconditionally removes the origin
  # remote (git-filter-repo's own documented, deliberate behavior on a non---partial run).
  ORIGIN_URL=$(git -C "$ROOT" remote get-url origin 2>/dev/null)
  git -C "$ROOT" branch "$BACKUP_BRANCH" 2>/dev/null
  if [ $? -ne 0 ]; then
    warn "  Could not create backup branch (detached HEAD or other issue)."
    warn "  Backup tar is still present at ${BACKUP_PATH}."
  else
    info "  Backup branch '${BACKUP_BRANCH}' created from current HEAD."
  fi
  info ""

  # Step 3: run git-filter-repo apply
  info "Step 3 — Applying rewrite ..."
  git -C "$ROOT" filter-repo --replace-text "$PATTERNS_FILE" 2>&1
  FILTER_EXIT=$?
  info ""

  if [ $FILTER_EXIT -ne 0 ]; then
    err "git filter-repo exited with code ${FILTER_EXIT}."
    err "Rewrite may be partial. Inspect the output above."
    err "Your backup is at: ${BACKUP_PATH}"
    err "Your backup branch is: ${BACKUP_BRANCH}"
    err "To restore: rm -rf .git && tar -xzf ${BACKUP_PATH} -C ${GIT_TOPLEVEL}"
    exit 2
  fi

  info "Rewrite applied to local clone."
  info ""

  # STOP — HITL required before force-push
  info "=== APPLY COMPLETE — STOP FOR HITL BEFORE FORCE-PUSH ==="
  info ""
  info "The local history has been rewritten."
  info ""
  info "  VERIFY the result before pushing:"
  info "    git -C \"${ROOT}\" log --oneline | head -20"
  info "  NOTE: git-filter-repo rewrites ALL refs, including the backup branch"
  info "  '${BACKUP_BRANCH}' created in Step 2 — a diff against it is NEVER meaningful"
  info "  (both sides show the identical post-rewrite state)."
  info "  For a real before/after record, inspect filter-repo's own commit-map instead:"
  info "    cat \"${ROOT}/.git/filter-repo/commit-map\""
  info "  (one 'old-SHA new-SHA' pair per rewritten commit; an all-zero new-SHA means"
  info "  that commit was dropped.)"
  info ""
  info "  The tar backup at ${BACKUP_PATH} is the SOLE rollback for this rewrite."
  info ""
  info "  FORCE-PUSH requires EXPLICIT USER CONFIRMATION — NEVER automatic."
  info "  Force-push is a destructive remote operation that breaks existing clones/forks."
  info "  It must ONLY be done after the user explicitly approves it."
  info ""
  if [ -n "$ORIGIN_URL" ]; then
    info "  git-filter-repo removes the 'origin' remote as part of the rewrite (deliberate,"
    info "  upstream-documented behavior). Re-add it before pushing:"
    info "    git -C \"${ROOT}\" remote add origin ${ORIGIN_URL}"
  else
    info "  git-filter-repo removes the 'origin' remote as part of the rewrite (deliberate,"
    info "  upstream-documented behavior), and its URL could not be captured before the"
    info "  rewrite ran. Re-add it manually before pushing:"
    info "    git -C \"${ROOT}\" remote add origin <original-remote-url>"
  fi
  info ""
  info "  When confirmed by the user, push with:"
  info "    git -C \"${ROOT}\" push --force-with-lease origin ${CURRENT_BRANCH}"
  info "  (--force-with-lease is safer than --force: fails if remote has diverged unexpectedly)"
  info ""
  info "  Restore from backup if needed:"
  info "    rm -rf \"${GIT_TOPLEVEL}/.git\" && tar -xzf \"${BACKUP_PATH}\" -C \"${GIT_TOPLEVEL}\""
  info ""
  info "  Orchestrator: present this HITL to the user before executing any push."
  exit 0
fi

# -----------------------------------------------------------------------
# Unknown mode
# -----------------------------------------------------------------------
err "Unknown mode: '${MODE}'. Use 'dry-run' (default) or 'apply'."
exit 2
