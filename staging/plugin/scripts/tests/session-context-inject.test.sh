#!/bin/bash
# session-context-inject.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Covers the compact-laziness contract added for the autocompact thrashing
# measured on 2026-08-21 (17 compactions in ~70 minutes, the whole 3,087-byte payload
# re-created in every one of them).
#
# The contract has two halves and the second is the one that matters: the payload is
# withheld ONLY on an exact, positively-read source=compact. Every other source, and every
# payload the reader cannot make sense of, injects as before — a shape change may lose the
# saving, it may never silently stop injecting the context.
# Run: bash session-context-inject.test.sh

# plant: SCI1 | plugin/scripts/session-context-inject.sh | [ "$SRC" = "compact" ] | [ "$SRC" = "__never__" ]
# plant: SCI2 | plugin/scripts/session-context-inject.sh | not re-injected at compact | PLANTED-AWAY
# plant: SCI3 | plugin/scripts/session-context-inject.sh | cat "$CTX_FILE" | true
# plant: SCI4 | plugin/scripts/session-context-inject.sh | s/.*"source"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p | s/.*/compact/p
# plant: SCI5 | plugin/scripts/session-context-inject.sh | HOOK_STDIN=$(cat 2>/dev/null | HOOK_STDIN=$(printf '{"source":"compact"}'
# plant: SCI6 | plugin/scripts/session-context-inject.sh | if [ -f "$CTX_FILE" ]; then | if true; then
set -u

unset CLAUDE_CODE_SESSION_ID
SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$SCRIPTS/session-context-inject.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# A fixture project whose context.md carries a marker that cannot occur by accident, so
# "the payload was injected" is decided by the payload itself and not by the frame around
# it (the === PROJECT CONTEXT === header is printed in BOTH branches).
PROJ="$TMP/proj"
mkdir -p "$PROJ/.claude"
MARK="SCI-FIXTURE-PAYLOAD-4f2a"
printf 'first line\n%s\nlast line\n' "$MARK" > "$PROJ/.claude/context.md"

run() { printf '%s' "$1" | CLAUDE_PROJECT_DIR="$PROJ" bash "$HOOK" 2>/dev/null; }

# --- the saving ----------------------------------------------------------------------
OUT=$(run '{"session_id":"s","source":"compact","cwd":"/tmp"}')
if printf '%s' "$OUT" | grep -q "$MARK"; then
  bad "SCI1 source=compact injected the whole payload — the saving is not in effect"
else
  ok "SCI1 source=compact withholds the context.md payload"
fi

if printf '%s' "$OUT" | grep -q 'not re-injected at compact'; then
  ok "SCI2 source=compact still names the file, so the fact stays reachable"
else
  bad "SCI2 source=compact printed no pointer — the context became silently unreachable"
fi

# --- the fail-open half, which is the part a shape change would break ------------------
_open_case() {   # $1 = assertion id, $2 = label, $3 = payload
  _o=$(run "$3")
  if printf '%s' "$_o" | grep -q "$MARK"; then
    ok "$1 $2 injects the payload"
  else
    bad "$1 $2 withheld the payload — only an exact source=compact may withhold"
  fi
}
_open_case SCI3 "source=startup"                 '{"session_id":"s","source":"startup"}'
_open_case SCI4 "a payload carrying no source"   '{"session_id":"s","cwd":"/tmp"}'
_open_case SCI5 "a payload that is not JSON"     'this is not json at all'

# --- the pre-existing behaviour this change must not disturb --------------------------
EMPTY="$TMP/empty"
mkdir -p "$EMPTY/.claude"
OUT6=$(printf '%s' '{"source":"startup"}' | CLAUDE_PROJECT_DIR="$EMPTY" bash "$HOOK" 2>/dev/null)
if [ -z "$OUT6" ]; then
  ok "SCI6 no context.md is still a silent no-op"
else
  bad "SCI6 no context.md produced output: $OUT6"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
