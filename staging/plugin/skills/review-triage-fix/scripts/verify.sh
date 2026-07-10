#!/bin/bash
# review-triage-fix: verification reporter (NOT a gate). Reuses the project's
# .claude/test-cmd with stop-gate's exact resolution + parser. Always exits 0;
# the cycle status is the FIRST stdout token: PASS | FAIL | UNVERIFIED.
# Usage: verify.sh [start-dir]   (default: $PWD)
TMO="${RTF_TEST_TIMEOUT:-120}"; case "$TMO" in ''|*[!0-9]*) TMO=120;; esac
start="${1:-$PWD}"
[ -d "$start" ] || { printf 'UNVERIFIED\tstart-dir not found\n'; exit 0; }
start=$(cd "$start" 2>/dev/null && pwd) || { printf 'UNVERIFIED\tcd failed\n'; exit 0; }
ROOT=""; d="$start"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -f "$d/.claude/test-cmd" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done
[ -z "$ROOT" ] && { printf 'UNVERIFIED\tno .claude/test-cmd found\n'; exit 0; }
TCF="$ROOT/.claude/test-cmd"
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$TCF" 2>/dev/null)
[ "$CMD" = "NONE" ] && { printf 'UNVERIFIED\ttest-cmd=NONE (opt-out)\n'; exit 0; }
[ -z "$CMD" ] && { printf 'UNVERIFIED\ttest-cmd empty\n'; exit 0; }
run_with_timeout() {  # $1=secs $2=cmdstring → rc; 124=timeout 125=cannot-run
  if command -v timeout >/dev/null 2>&1; then timeout "$1" bash -c "$2"; return $?
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$1" bash -c "$2"; return $?
  else
    bash -c "$2" & local p=$!
    ( sleep "$1"; kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null ) & local w=$!
    wait "$p" 2>/dev/null; local rc=$?
    kill -9 "$w" 2>/dev/null; wait "$w" 2>/dev/null
    [ "$rc" -eq 137 ] && return 124
    return "$rc"
  fi
}
OUT=$(mktemp)
run_with_timeout "$TMO" "cd $(printf %q "$ROOT") && ( $CMD )" >"$OUT" 2>&1
RC=$?
if [ "$RC" -eq 124 ] || [ "$RC" -eq 125 ] || [ "$RC" -eq 126 ] || [ "$RC" -eq 127 ]; then
  rm -f "$OUT"; printf 'UNVERIFIED\ttest not executable/timeout (rc=%s)\n' "$RC"; exit 0
fi
if [ "$RC" -eq 0 ]; then rm -f "$OUT"; printf 'PASS\n'; exit 0; fi
TAIL=$(tail -c 600 "$OUT" 2>/dev/null | tr '\n' ' '); rm -f "$OUT"
printf 'FAIL\texit=%s\t%s\n' "$RC" "$TAIL"
exit 0
