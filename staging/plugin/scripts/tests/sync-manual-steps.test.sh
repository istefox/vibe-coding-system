#!/bin/bash
# sync-manual-steps.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Run: bash sync-manual-steps.test.sh
#
# sync-to-claude.sh used to end with one unconditional heredoc printing two MANUAL STEP
# notices. Checked live on 2026-07-25, both steps were already done — the nightly-guard hook
# was wired and the retired backup-before-deploy.sh did not exist — yet the script printed
# them on every run. Fixed noise is what buries the notice that one day matters, so each
# notice is now gated on the state it describes.
#
# HERMETIC $HOME OVERRIDE. The script derives DEST from $HOME (line 14) and nothing else, so
# pointing HOME at a fixture directory gives a full run that cannot touch the real ~/.claude.
# Runs are dry-run (no --apply), so the script only reads. ADR-0024 recorded $HOME coupling as
# the reason several legacy harnesses are CI-dark; this is the pattern that closes that gap
# without editing the script under test — reusable for the others.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SYNC="$STAGING/sync-to-claude.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

WIRING_MARK="MANUAL STEP: hook wiring"
RETIRED_MARK="MANUAL STEP: retired hook cleanup"
CLEAR_MARK="no manual steps outstanding"

# build_home <name> <wired:yes|no|nofile> <retired:yes|no> — returns the fixture HOME path.
build_home() {
  _h="$TMP/$1"; mkdir -p "$_h/.claude/hooks"
  case "$2" in
    yes) printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.claude/hooks/nightly-guard.sh"}]}]}}\n' > "$_h/.claude/settings.json" ;;
    no)  printf '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","command":"protect-files.sh"}]}]}}\n' > "$_h/.claude/settings.json" ;;
    nofile) : ;;
  esac
  [ "$3" = "yes" ] && printf '#!/bin/bash\n# retired one-shot backup\n' > "$_h/.claude/hooks/backup-before-deploy.sh"
  printf '%s' "$_h"
}

run_sync() { HOME="$1" bash "$SYNC" 2>&1; }

# =====================================================================================
# A. Wired, no retired file — the real state of this machine on 2026-07-25. Neither notice
# may print, and the all-clear line must, so silence is never ambiguous with "forgot to check".
OUT=$(run_sync "$(build_home a yes no)")
case "$OUT" in
  *"$WIRING_MARK"*) bad "A1: wiring notice printed although the hook is wired" ;;
  *) ok "A1: wiring notice suppressed when nightly-guard is already wired" ;;
esac
case "$OUT" in
  *"$RETIRED_MARK"*) bad "A2: retired-hook notice printed although the file is absent" ;;
  *) ok "A2: retired-hook notice suppressed when the file does not exist" ;;
esac
case "$OUT" in
  *"$CLEAR_MARK"*) ok "A3: all-clear line printed when nothing is outstanding" ;;
  *) bad "A3: no all-clear line — silence is ambiguous with a skipped check" ;;
esac

# =====================================================================================
# B. Not wired — the notice must fire, and only that one.
OUT=$(run_sync "$(build_home b no no)")
case "$OUT" in
  *"$WIRING_MARK"*) ok "B1: wiring notice printed when nightly-guard is absent from settings.json" ;;
  *) bad "B1: wiring notice suppressed although the hook is NOT wired" ;;
esac
case "$OUT" in
  *"$RETIRED_MARK"*) bad "B2: retired-hook notice leaked into the not-wired case" ;;
  *) ok "B2: retired-hook notice still suppressed" ;;
esac

# =====================================================================================
# C. Retired file present, hook wired — mirror image of B.
OUT=$(run_sync "$(build_home c yes yes)")
case "$OUT" in
  *"$RETIRED_MARK"*) ok "C1: retired-hook notice printed when the file exists" ;;
  *) bad "C1: retired-hook notice suppressed although the file exists" ;;
esac
case "$OUT" in
  *"$WIRING_MARK"*) bad "C2: wiring notice leaked into the retired-file case" ;;
  *) ok "C2: wiring notice still suppressed" ;;
esac

# =====================================================================================
# D. No settings.json at all. Fail-safe direction is to PRINT: an unconfirmable state must not
# read as "already wired". This is the one case where a false positive is the correct output.
OUT=$(run_sync "$(build_home d nofile no)")
case "$OUT" in
  *"$WIRING_MARK"*) ok "D1: wiring notice printed when settings.json is missing (fail-safe)" ;;
  *) bad "D1: missing settings.json silently treated as wired" ;;
esac

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
