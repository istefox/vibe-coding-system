#!/bin/bash
# TOFU approval CLI for .claude/acceptance-cmd — NOT a hook (issue #439, ADR-0141).
# Usage: approve-acceptance-cmd.sh [project-or-subdir]
# Records <sha256>\t<normalized-project-root> in the SAME registry as approve-test-cmd.sh.
# Never runs the acceptance command.
#
# WHY THIS IS A SIBLING AND NOT A FLAG ON approve-test-cmd.sh. The trust line format is one
# question with two askers — a writer and a reader that disagree produce a check which silently
# never trusts anything — and CLAUDE.md rule 6 says that shape must be extracted. Extraction here
# means editing stop-gate.sh, the armed hook that runs on every turn, for a change that does not
# otherwise need to touch it. So this follows ADR-0086's precedent instead: keep the copies, add the
# guard. acceptance-contract.test.sh builds one root holding .claude/test-cmd and
# .claude/acceptance-cmd with IDENTICAL content, runs both approvers, and asserts the two registry
# lines are byte-identical. A divergence in normalisation or hashing fails there, loudly, rather
# than becoming a trust check that quietly matches nothing.
#
# CONSEQUENCE, declared rather than discovered: because the line is (content-hash, root), two files
# with identical content produce the identical line — approving one approves the other. TOFU reviews
# the COMMAND, not the filename. That is the intended reading; assuming per-file approval is not.
TRUST="${STOP_GATE_TRUST_FILE:-${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}/trust}"

norm_path() {
  local p; p=$(cd "$1" 2>/dev/null && pwd -P) || { printf '%s' "$1"; return 0; }
  local sys="${STOP_GATE_UNAME:-$(uname)}"
  [ "$sys" = "Darwin" ] && p=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$p"
}

start="${1:-$PWD}"
[ -d "$start" ] || { echo "approve-acceptance-cmd: path does not exist: $start" >&2; exit 1; }
start=$(cd "$start" 2>/dev/null && pwd) || { echo "approve-acceptance-cmd: cd failed" >&2; exit 1; }
ROOT=""; d="$start"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -f "$d/.claude/acceptance-cmd" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done
[ -z "$ROOT" ] && { echo "approve-acceptance-cmd: no .claude/acceptance-cmd found ascending from $start" >&2; exit 1; }
# Hash the pre-normalization (case-preserving) path — the one that actually resolves on disk.
# Normalizing first could point shasum at a nonexistent lowercased path on a case-sensitive volume
# and yield an empty digest without aborting (issue #38, same fix as approve-test-cmd.sh).
ACF="$ROOT/.claude/acceptance-cmd"
if command -v shasum >/dev/null 2>&1; then H=$(shasum -a 256 "$ACF" 2>/dev/null | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then H=$(sha256sum "$ACF" 2>/dev/null | awk '{print $1}')
else echo "approve-acceptance-cmd: no sha256 tool available" >&2; exit 1; fi
[ -z "$H" ] && { echo "approve-acceptance-cmd: hash computation failed for $ACF (empty digest) — aborting, not writing an invalid trust line" >&2; exit 1; }
ROOT=$(norm_path "$ROOT")
mkdir -p "$(dirname "$TRUST")" 2>/dev/null || true
LINE=$(printf '%s\t%s' "$H" "$ROOT")
if [ -f "$TRUST" ] && grep -F -x -q -- "$LINE" "$TRUST" 2>/dev/null; then
  echo "Already approved: $ROOT"
  exit 0
fi
printf '%s\n' "$LINE" >> "$TRUST" || { echo "approve-acceptance-cmd: registry write failed" >&2; exit 1; }
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$ACF")
echo "Approved for $ROOT — acceptance command pinned as authoritative: $CMD"
exit 0
