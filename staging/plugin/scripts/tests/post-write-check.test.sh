#!/bin/bash
# post-write-check.test.sh — offline, hermetic, no network, no $HOME dependency. Bash 3.2 clean.
# Covers ADR-0039 D1-D4: the deterministic PostToolUse check on Edit|Write.
# Targets staging/plugin/scripts/ directly, never the deployed $HOME/.claude/hooks/ copy.
# Run: bash post-write-check.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$SCRIPTS/post-write-check.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# run <file-path> -> stdout of the hook; RC holds its exit code.
run() {
  OUT=$(printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$HOOK" 2>&1)
  RC=$?
}

# ctx <json> -> the additionalContext string, or empty if absent/unparseable
ctx() {
  printf '%s' "$1" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('hookSpecificOutput', {}).get('additionalContext', ''))
except Exception:
    print('')" 2>/dev/null
}

# =====================================================================================
# Test 1 (D2): a syntactically valid .sh produces no output at all.
printf 'echo ok\n' > "$TMP/good.sh"
run "$TMP/good.sh"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "1: valid .sh stays silent (no tokens spent)"
else
  bad "1: valid .sh produced output (rc=$RC out='$OUT')"
fi

# =====================================================================================
# Test 1b (D4 as revised, the CI-only regression): a .sh fragment with no shebang is valid and
# must stay silent. shellcheck reports SC2148 on it at severity `error`. This was invisible on
# the author's macOS, where shellcheck is not installed, and red on the CI runner, where it is.
# The pair (this and Test 10) is why the hook runs syntax checks only and no external linters.
printf 'echo ok\n' > "$TMP/noshebang.sh"
run "$TMP/noshebang.sh"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "1b: .sh without a shebang stays silent (no linter opinions)"
else
  bad "1b: .sh without shebang produced output (rc=$RC out='$OUT')"
fi

# =====================================================================================
# Test 2 (D1): a broken .sh is reported through additionalContext.
printf 'if [ 1 ]; then\n' > "$TMP/broken.sh"
run "$TMP/broken.sh"
C2=$(ctx "$OUT")
if [ "$RC" -eq 0 ] && [ -n "$C2" ]; then
  ok "2: broken .sh reported via hookSpecificOutput.additionalContext"
else
  bad "2: broken .sh not reported (rc=$RC ctx='$C2')"
fi

# =====================================================================================
# Test 3 (D2, the load-bearing pin): the emitted JSON carries hookEventName PostToolUse and
# carries NO `decision` key. `decision` is what turns an advisory hook into a blocking one;
# this hook must never block a write.
EVT3=$(printf '%s' "$OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('hookSpecificOutput', {}).get('hookEventName', ''))
except Exception:
    print('')" 2>/dev/null)
DEC3=$(printf '%s' "$OUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('PRESENT' if 'decision' in d else 'ABSENT')
except Exception:
    print('UNPARSEABLE')" 2>/dev/null)
if [ "$EVT3" = "PostToolUse" ] && [ "$DEC3" = "ABSENT" ]; then
  ok "3: envelope is PostToolUse and carries no 'decision' key (advisory, never blocking)"
else
  bad "3: envelope wrong (event='$EVT3' decision='$DEC3')"
fi

# =====================================================================================
# Test 4: broken .py reported, and nothing is left behind. py_compile writes __pycache__ next
# to the source unless cfile is redirected; a check must not litter the tree it inspects.
mkdir -p "$TMP/py"
printf 'def f(:\n' > "$TMP/py/broken.py"
run "$TMP/py/broken.py"
C4=$(ctx "$OUT")
LEFTOVER=$(ls -a "$TMP/py" 2>/dev/null | grep -c '__pycache__')
if [ "$RC" -eq 0 ] && [ -n "$C4" ] && [ "$LEFTOVER" -eq 0 ]; then
  ok "4: broken .py reported, no __pycache__ left behind"
else
  bad "4: .py case failed (rc=$RC ctx-empty=$([ -z "$C4" ] && echo yes || echo no) pycache=$LEFTOVER)"
fi

# =====================================================================================
# Test 5: malformed .json reported.
printf '{"a":\n' > "$TMP/broken.json"
run "$TMP/broken.json"
C5=$(ctx "$OUT")
if [ "$RC" -eq 0 ] && [ -n "$C5" ]; then
  ok "5: malformed .json reported"
else
  bad "5: malformed .json not reported (rc=$RC)"
fi

# =====================================================================================
# Test 6: malformed .yml reported.
printf 'a: [1,\n' > "$TMP/broken.yml"
if python3 -c "import yaml" >/dev/null 2>&1; then
  run "$TMP/broken.yml"
  C6=$(ctx "$OUT")
  if [ "$RC" -eq 0 ] && [ -n "$C6" ]; then
    ok "6: malformed .yml reported"
  else
    bad "6: malformed .yml not reported (rc=$RC)"
  fi
else
  echo "SKIP 6: PyYAML not installed (informational)"
fi

# Test 6b: a valid .yml stays silent. With PyYAML absent the hook must skip the check rather
# than report the ImportError as a file defect.
printf 'a: 1\n' > "$TMP/good.yml"
run "$TMP/good.yml"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "6b: valid .yml stays silent (and no false error when PyYAML is absent)"
else
  bad "6b: valid .yml produced output (rc=$RC out='$OUT')"
fi

# =====================================================================================
# Test 7 (D3 boundary): an extension with no check stays silent. .md matters specifically —
# this repo is mostly markdown, and a hook that fired on every doc is exactly what ADR-0040
# retired.
printf '# heading\n' > "$TMP/doc.md"
run "$TMP/doc.md"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "7: uncovered extension (.md) stays silent"
else
  bad "7: .md produced output (rc=$RC out='$OUT')"
fi

# =====================================================================================
# Test 8: payload without file_path stays silent.
OUT=$(printf '{"tool_input":{}}' | bash "$HOOK" 2>&1); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "8: payload without file_path stays silent"
else
  bad "8: missing file_path produced output (rc=$RC out='$OUT')"
fi

# =====================================================================================
# Test 9: a path that is not on disk stays silent (written then deleted, or never landed).
run "/nonexistent/dir/x.sh"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "9: nonexistent file stays silent"
else
  bad "9: nonexistent file produced output (rc=$RC out='$OUT')"
fi

# =====================================================================================
# Test 10 (D4 as revised): a .swift file that is syntactically valid but violates a style rule
# must stay silent. `let x = 1` trips swiftlint's identifier_name rule at severity `error`.
# This is one of the two false positives that removed external linters from the hook entirely
# (the other is Test 1b). It also exercises the missing-engine path where swiftc is absent.
printf 'let x = 1\n' > "$TMP/ok.swift"
run "$TMP/ok.swift"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "10: syntactically valid .swift stays silent despite a style-rule violation"
else
  bad "10: .swift produced output (rc=$RC out='$OUT')"
fi

# =====================================================================================
# Test 10b: a .swift file with a real syntax error IS reported, when swiftc is available.
if command -v swiftc >/dev/null 2>&1; then
  printf 'let x = \n' > "$TMP/broken.swift"
  run "$TMP/broken.swift"
  C10B=$(ctx "$OUT")
  if [ "$RC" -eq 0 ] && [ -n "$C10B" ]; then
    ok "10b: broken .swift reported via swiftc -parse"
  else
    bad "10b: broken .swift not reported (rc=$RC)"
  fi
else
  echo "SKIP 10b: swiftc not installed (informational)"
fi

# =====================================================================================
# Test 11 (hermeticity): empty stdin must not hang or error.
OUT=$(printf '' | bash "$HOOK" 2>&1); RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "11: empty stdin stays silent"
else
  bad "11: empty stdin produced output (rc=$RC out='$OUT')"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
