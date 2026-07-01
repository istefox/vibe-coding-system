#!/bin/bash
# sync-to-claude v1.0 (ADR-0022 Phase 5) — copy the nightly-autopilot blueprint into ~/.claude.
#
# Dry-run by default: prints a diff for every target and changes nothing. Pass --apply to write.
# For an existing target, the diff is shown before it is overwritten (global safety rule). The live
# settings.json is NOT auto-edited; the script prints the hook wiring to add by hand.
#
# Bash 3.2 clean. Run from the repo root: bash staging/sync-to-claude.sh [--apply]

set -u

REPO=$(cd "$(dirname "$0")/.." && pwd)
STAGING="$REPO/staging"
DEST="$HOME/.claude"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

# src|dst pairs (dst relative to ~/.claude). Scripts land in hooks/ (this deployment's convention).
PAIRS="
plugin/scripts/nightly-guard.sh|hooks/nightly-guard.sh
plugin/scripts/publish-feature.sh|hooks/publish-feature.sh
plugin/scripts/set-branch-protection.sh|hooks/set-branch-protection.sh
plugin/skills/nightly-autopilot/SKILL.md|skills/nightly-autopilot/SKILL.md
plugin/skills/nightly-autopilot/tests/run-tests.sh|skills/nightly-autopilot/tests/run-tests.sh
plugin/scripts/tests/phase1.test.sh|hooks/tests/phase1.test.sh
plugin/skills/project-conductor/SKILL.md|skills/project-conductor/SKILL.md
project-templates/ci/ci.yml|templates/ci.yml
plugin/scripts/detect-test-cmd.sh|hooks/detect-test-cmd.sh
plugin/scripts/roadmap-from-issues.sh|hooks/roadmap-from-issues.sh
plugin/scripts/spec-issue-gate.sh|hooks/spec-issue-gate.sh
plugin/scripts/tests/prep.test.sh|hooks/tests/prep.test.sh
plugin/skills/spec-from-issue/SKILL.md|skills/spec-from-issue/SKILL.md
"

printf '%s\n' "$PAIRS" | while IFS='|' read -r src dst; do
  [ -z "$src" ] && continue
  s="$STAGING/$src"; d="$DEST/$dst"
  [ -f "$s" ] || { printf '!! source missing: %s\n' "$src"; continue; }
  if [ ! -f "$d" ]; then
    printf '\n== NEW: %s\n' "$dst"
    [ "$APPLY" -eq 1 ] && { mkdir -p "$(dirname "$d")"; cp "$s" "$d"; printf '   written\n'; }
  elif ! diff -q "$s" "$d" >/dev/null 2>&1; then
    printf '\n== CHANGED: %s\n' "$dst"
    diff -u "$d" "$s" | sed 's/^/   /'
    [ "$APPLY" -eq 1 ] && { cp "$s" "$d"; printf '   overwritten\n'; }
  fi
done

# Preserve executable bit on the shell helpers.
if [ "$APPLY" -eq 1 ]; then
  chmod +x "$DEST/hooks/nightly-guard.sh" "$DEST/hooks/publish-feature.sh" \
    "$DEST/hooks/set-branch-protection.sh" "$DEST/hooks/detect-test-cmd.sh" \
    "$DEST/hooks/roadmap-from-issues.sh" "$DEST/hooks/spec-issue-gate.sh" 2>/dev/null || true
fi

cat <<'NOTE'

--- MANUAL STEP: hook wiring (not auto-applied) ---
Add this PreToolUse entry to ~/.claude/settings.json (alongside the Edit|Write protect-files entry):

  { "matcher": "Bash",
    "hooks": [ { "type": "command", "command": "\"$HOME\"/.claude/hooks/nightly-guard.sh" } ] }

The staged reference version is staging/user/settings.json. Review the live file first — it may have
diverged. nightly-guard is inert outside a nightly run, so wiring it globally is safe.
NOTE

[ "$APPLY" -eq 0 ] && printf '\n(dry-run — no files written. Re-run with --apply after reviewing.)\n'
exit 0
