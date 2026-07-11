#!/bin/bash
# TOFU approval CLI — NOT a hook. Usage: approve-test-cmd.sh [project-or-subdir]
# Records <sha256>\t<normalized-project-root> for the project's .claude/test-cmd.
# ROOT normalized via norm_path (pwd -P + lowercase on Darwin) for
# case-invariant trust matching with stop-gate.sh. Never runs the test-cmd.
TRUST="${STOP_GATE_TRUST_FILE:-${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}/trust}"

norm_path() {
  local p; p=$(cd "$1" 2>/dev/null && pwd -P) || { printf '%s' "$1"; return 0; }
  local sys="${STOP_GATE_UNAME:-$(uname)}"
  [ "$sys" = "Darwin" ] && p=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$p"
}

start="${1:-$PWD}"
[ -d "$start" ] || { echo "approve-test-cmd: path does not exist: $start" >&2; exit 1; }
start=$(cd "$start" 2>/dev/null && pwd) || { echo "approve-test-cmd: cd failed" >&2; exit 1; }
ROOT=""; d="$start"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -f "$d/.claude/test-cmd" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done
[ -z "$ROOT" ] && { echo "approve-test-cmd: no .claude/test-cmd found ascending from $start" >&2; exit 1; }
# v3: normalize ROOT for case-invariant trust storage on Darwin.
ROOT=$(norm_path "$ROOT")
TCF="$ROOT/.claude/test-cmd"
if command -v shasum >/dev/null 2>&1; then H=$(shasum -a 256 "$TCF" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then H=$(sha256sum "$TCF" | awk '{print $1}')
else echo "approve-test-cmd: no sha256 tool available" >&2; exit 1; fi
mkdir -p "$(dirname "$TRUST")" 2>/dev/null || true
LINE=$(printf '%s\t%s' "$H" "$ROOT")
if [ -f "$TRUST" ] && grep -F -x -q -- "$LINE" "$TRUST" 2>/dev/null; then
  echo "Already approved: $ROOT"
  exit 0
fi
printf '%s\n' "$LINE" >> "$TRUST" || { echo "approve-test-cmd: registry write failed" >&2; exit 1; }
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$TCF")
echo "Approved for $ROOT — command pinned as authoritative: $CMD"
exit 0
