#!/bin/bash
# Stop gate v3.1: v3 + additionalContext (CC 2.1.163) for test-fail feedback to Claude.
# Contract: exit 0 + empty stdout = allow; exit 0 + {"decision":"block","reason":..} = block.
# Never exit non-zero / never block on internal error (fail-open, spec §7).
DIR="${STOP_GATE_STATE_DIR:-$HOME/.claude/state/stop-gate}"
TRUST="${STOP_GATE_TRUST_FILE:-$DIR/trust}"
N="${STOP_GATE_MAX_REENTRY:-3}"; case "$N" in ''|*[!0-9]*) N=3;; esac
TMO="${STOP_GATE_TEST_TIMEOUT:-120}"; case "$TMO" in ''|*[!0-9]*) TMO=120;; esac

# norm_path: canonical trust path for $1 (a dir that exists).
# pwd -P resolves symlinks (/var → /private/var on macOS).
# On Darwin, lowercase to match case-insensitive FS semantics.
# Fail-open: if cd fails, echo $1 unchanged.
norm_path() {
  local p; p=$(cd "$1" 2>/dev/null && pwd -P) || { printf '%s' "$1"; return 0; }
  local sys="${STOP_GATE_UNAME:-$(uname)}"
  [ "$sys" = "Darwin" ] && p=$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')
  printf '%s' "$p"
}

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && exit 0
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

DIRTY="$DIR/$SID.dirty"
CF="$DIR/$SID.count"
[ ! -f "$DIRTY" ] && exit 0

emit_block() {  # $1 = reason text; $2 = test output to append to reason (optional)
  local count=0
  [ -f "$CF" ] && count=$(cat "$CF" 2>/dev/null || echo 0)
  case "$count" in ''|*[!0-9]*) count=0;; esac
  if [ "$count" -ge "$N" ]; then
    echo "stop-gate: anti-loop guardrail active — unblocked after $N entries. Verify manually." >&2
    exit 0
  fi
  echo $((count + 1)) > "$CF" 2>/dev/null || true
  if [ -n "${2:-}" ]; then
    # Deliver test output inside reason (root-level field only — hookSpecificOutput is not
    # valid for Stop events and causes JSON validation errors in Claude Code).
    jq -nc --arg r "$1" --arg c "$2" \
      '{decision:"block",reason:($r + "\n\n" + $c)}' \
      2>/dev/null \
      || printf '{"decision":"block","reason":"verify tests before closing"}\n'
  else
    jq -nc --arg r "$1" '{decision:"block",reason:$r}' 2>/dev/null \
      || printf '{"decision":"block","reason":"verify tests before closing"}\n'
  fi
  exit 0
}

ROOT=""; d="$CWD"; i=0
while [ -n "$d" ] && [ "$i" -lt 40 ]; do
  [ -f "$d/.claude/test-cmd" ] && { ROOT="$d"; break; }
  [ "$d" = "/" ] && break
  d=$(dirname "$d"); i=$((i + 1))
done

if [ -z "$ROOT" ]; then
  emit_block "Code modified without verification. Run the project tests, or declare the command in .claude/test-cmd (or 'NONE' to opt-out)."
fi
# v4: read/hash test-cmd on the pre-normalization (case-preserving) path — same fix as
# approve-test-cmd.sh (issue #38). ROOT is normalized afterward, into a SEPARATE
# variable, for the case-invariant trust LOOKUP only: run_with_timeout below still
# needs to cd into the real path, so ROOT itself is never overwritten in this script.
TCF="$ROOT/.claude/test-cmd"
CMD=$(awk '{ l=$0; sub(/^[ \t]+/,"",l); sub(/[ \t]+$/,"",l); if(l=="" || substr(l,1,1)=="#") next; print l; exit }' "$TCF" 2>/dev/null)

[ "$CMD" = "NONE" ] && exit 0
[ -z "$CMD" ] && exit 0          # empty/unreadable test-cmd → fail-open (spec §7)
sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else return 1; fi
}
H=$(sha256_of "$TCF") || { echo "stop-gate: no sha256 tool — fail-open" >&2; exit 0; }
[ -z "$H" ] && exit 0
ROOT_NORM=$(norm_path "$ROOT")
LINE=$(printf '%s\t%s' "$H" "$ROOT_NORM")
TRUSTED=0
[ -f "$TRUST" ] && grep -F -x -q -- "$LINE" "$TRUST" 2>/dev/null && TRUSTED=1

if [ "$TRUSTED" -ne 1 ]; then
  emit_block "Project test command not approved (TOFU). Review $TCF and run: bash ~/.claude/hooks/approve-test-cmd.sh \"$ROOT\" — tests will then run automatically at end of task."
fi
run_with_timeout() {  # $1=secs $2=cmdstring → returns rc; 124=timeout 125=cannot-run
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
OUT="$DIR/.$SID.testout"
run_with_timeout "$TMO" "cd $(printf %q "$ROOT") && ( $CMD )" >"$OUT" 2>&1
RC=$?
if [ "$RC" -eq 124 ] || [ "$RC" -eq 125 ] || [ "$RC" -eq 126 ] || [ "$RC" -eq 127 ]; then
  echo "stop-gate: test timeout/not executable — fail-open" >&2
  rm -f "$OUT" 2>/dev/null; exit 0
fi
if [ "$RC" -eq 0 ]; then
  rm -f "$DIRTY" "$OUT" 2>/dev/null || true
  exit 0
fi
TAIL=$(tail -c 600 "$OUT" 2>/dev/null); rm -f "$OUT" 2>/dev/null
emit_block "Tests failed (exit $RC). Failing test output provided in context below." "$TAIL"
exit 0
