#!/bin/bash
# autopilot-migrate.sh v1.0 (ADR-0127 §D2.3) — one-time rename of a repo's local autopilot state.
#
# The nightly-* -> autopilot-* rename moved three per-repo artefacts. They live in the target
# repository's .claude/ directory, not in ~/.claude, so sync-to-claude.sh cannot reach them and
# a repo that has opted into unattended publishing keeps the old names until someone runs this.
#
#   .claude/nightly-autopilot.yml  ->  .claude/autopilot.yml
#   .claude/nightly-state/         ->  .claude/autopilot-state/
#   .claude/nightly-report.json    ->  .claude/autopilot-report.json
#
# WHY THIS IS A SCRIPT AND NOT A FALLBACK. The tempting alternative is to have the opt-in check
# read either filename. That would mean two files can disagree about whether a repository has
# authorised unattended `git push`, and the failure is silent in the PERMISSIVE direction — the
# one case where a wrong answer costs something irreversible. So nothing falls back: the callers
# DETECT the old names and abort naming this script (ADR-0127 §D2.3).
#
# Exit codes — a checker, so callers branch on these:
#   0  migrated, or already migrated (nothing to do)
#   1  refused: both old and new exist, so the correct merge is not knowable here
#   2  bad invocation
#   3  did not run (not a git repository / no .claude directory)
#
# Bash 3.2 clean.

set -u

ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    -h|--help) printf 'usage: autopilot-migrate.sh --root <repo>\n'; exit 0 ;;
    *) printf 'autopilot-migrate: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -n "$ROOT" ] || { printf 'autopilot-migrate: missing --root\n' >&2; exit 2; }
[ -d "$ROOT" ] || { printf 'autopilot-migrate: root is not a directory: %s\n' "$ROOT" >&2; exit 2; }

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
  printf 'autopilot-migrate: %s is not a git repository — DID NOT RUN\n' "$ROOT" >&2
  exit 3
}
[ -d "$ROOT/.claude" ] || {
  printf 'autopilot-migrate: %s/.claude does not exist — DID NOT RUN\n' "$ROOT" >&2
  printf '  Nothing has ever been armed here; there is no state to migrate.\n' >&2
  exit 3
}

C="$ROOT/.claude"
MOVED=0
CONFLICT=0

# old|new, one per line. Directories and files alike; `mv` handles both.
ITEMS="nightly-autopilot.yml|autopilot.yml
nightly-state|autopilot-state
nightly-report.json|autopilot-report.json"

printf '%s\n' "$ITEMS" | while IFS='|' read -r old new; do
  [ -n "$old" ] || continue
  o="$C/$old"; n="$C/$new"
  if [ -e "$o" ] && [ -e "$n" ]; then
    printf 'REFUSED %s: both %s and %s exist\n' "$old" "$old" "$new" >&2
    printf '  Which one is current is not knowable from here, and picking wrong either\n' >&2
    printf '  re-arms a finished run or discards a live one. Merge them by hand.\n' >&2
    printf 'conflict\n' >> "$C/.autopilot-migrate.state"
  elif [ -e "$o" ]; then
    mv "$o" "$n" && printf 'migrated: %s -> %s\n' "$old" "$new"
    printf 'moved\n' >> "$C/.autopilot-migrate.state"
  fi
done

# The loop above runs in a subshell (pipe), so counters set inside it do not survive. State is
# passed back through a file rather than by restructuring into a here-doc: this keeps the item
# list readable as data. The file is transient and removed here.
if [ -f "$C/.autopilot-migrate.state" ]; then
  CONFLICT=$(grep -c '^conflict$' "$C/.autopilot-migrate.state" 2>/dev/null || true)
  MOVED=$(grep -c '^moved$' "$C/.autopilot-migrate.state" 2>/dev/null || true)
  rm -f "$C/.autopilot-migrate.state"
fi
[ -n "$CONFLICT" ] || CONFLICT=0
[ -n "$MOVED" ] || MOVED=0

if [ "$CONFLICT" -gt 0 ]; then
  printf 'autopilot-migrate: %s item(s) refused, %s migrated. Resolve the above and re-run.\n' \
    "$CONFLICT" "$MOVED" >&2
  exit 1
fi
if [ "$MOVED" -eq 0 ]; then
  printf 'autopilot-migrate: nothing to migrate (already on the autopilot-* names).\n'
  exit 0
fi
printf 'autopilot-migrate: %s item(s) migrated under %s/.claude/\n' "$MOVED" "$ROOT"
printf '  Commit the rename: the opt-in marker is tracked, and an untracked autopilot.yml\n'
printf '  means the next run reads no opt-in and refuses to publish.\n'
exit 0
