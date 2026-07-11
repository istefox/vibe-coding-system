#!/usr/bin/env bash
# humanize-en: run-tests.sh — test harness for detect-ai-tells.sh and hooks
# bash 3.2-clean. Exit: 0 all pass | 1 any fail.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DETECT="$SCRIPT_DIR/../scripts/detect-ai-tells.sh"
HEAVY="$SCRIPT_DIR/fixture-ai-heavy.md"
CLEAN="$SCRIPT_DIR/fixture-clean.md"
PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS  %s\n' "$desc"
    PASS=$((PASS + 1))
  else
    printf 'FAIL  %s (expected=%s actual=%s)\n' "$desc" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

check_ge() {
  local desc="$1" threshold="$2" actual="$3"
  if [ "$actual" -ge "$threshold" ] 2>/dev/null; then
    printf 'PASS  %s (got %s >= %s)\n' "$desc" "$actual" "$threshold"
    PASS=$((PASS + 1))
  else
    printf 'FAIL  %s (expected >= %s, got %s)\n' "$desc" "$threshold" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

check_lt() {
  local desc="$1" threshold="$2" actual="$3"
  if [ "$actual" -lt "$threshold" ] 2>/dev/null; then
    printf 'PASS  %s (got %s < %s)\n' "$desc" "$actual" "$threshold"
    PASS=$((PASS + 1))
  else
    printf 'FAIL  %s (expected < %s, got %s)\n' "$desc" "$threshold" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# --- Tests ---

# T1: detect script exists and is executable
if [ -x "$DETECT" ]; then
  printf 'PASS  detect-ai-tells.sh is executable\n'
  PASS=$((PASS + 1))
else
  printf 'FAIL  detect-ai-tells.sh missing or not executable (%s)\n' "$DETECT"
  FAIL=$((FAIL + 1))
fi

# T2: non-existent file returns 0
RESULT=$(bash "$DETECT" "/no/such/file.md" 2>/dev/null)
check "non-existent file → 0" "0" "$RESULT"

# T3: clean fixture returns < 3 tells
RESULT=$(bash "$DETECT" "$CLEAN" 2>/dev/null)
check_lt "clean fixture → < 3 tells" 3 "$RESULT"

# T4: AI-heavy fixture returns >= 3 tells
RESULT=$(bash "$DETECT" "$HEAVY" 2>/dev/null)
check_ge "AI-heavy fixture → >= 3 tells" 3 "$RESULT"

# T5: AI-heavy fixture returns >= 10 tells (strong signal)
check_ge "AI-heavy fixture → >= 10 tells (strong)" 10 "$RESULT"

# T6: post-md-tells-hint.sh exists and is executable
HINT_HOOK="$HOME/.claude/hooks/post-md-tells-hint.sh"
if [ -x "$HINT_HOOK" ]; then
  printf 'PASS  post-md-tells-hint.sh is executable\n'
  PASS=$((PASS + 1))
else
  printf 'FAIL  post-md-tells-hint.sh missing or not executable\n'
  FAIL=$((FAIL + 1))
fi

# T7: hook on clean fixture → no output
HOOK_OUT=$(echo '{"tool_input":{"file_path":"'"$CLEAN"'"}}' | bash "$HINT_HOOK" 2>/dev/null)
check "hint hook on clean file → silent" "" "$HOOK_OUT"

# T8: hook on AI-heavy fixture → prints hint
HOOK_OUT=$(echo '{"tool_input":{"file_path":"'"$HEAVY"'"}}' | bash "$HINT_HOOK" 2>/dev/null)
if echo "$HOOK_OUT" | grep -q "humanize-en"; then
  printf 'PASS  hint hook on AI-heavy fixture → prints hint\n'
  PASS=$((PASS + 1))
else
  printf 'FAIL  hint hook on AI-heavy fixture → no hint printed (got: %s)\n' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi

# T9: hook on non-.md file → no output
HOOK_OUT=$(echo '{"tool_input":{"file_path":"/tmp/foo.py"}}' | bash "$HINT_HOOK" 2>/dev/null)
check "hint hook on .py file → silent" "" "$HOOK_OUT"

# T10: prompt-en-prose-detect.sh exists and is executable
PROMPT_HOOK="$HOME/.claude/hooks/prompt-en-prose-detect.sh"
if [ -x "$PROMPT_HOOK" ]; then
  printf 'PASS  prompt-en-prose-detect.sh is executable\n'
  PASS=$((PASS + 1))
else
  printf 'FAIL  prompt-en-prose-detect.sh missing or not executable\n'
  FAIL=$((FAIL + 1))
fi

# T11: EN-prose prompt → emits additionalContext
HOOK_OUT=$(echo '{"prompt":"draft a Reddit post about my CLI tool"}' | bash "$PROMPT_HOOK" 2>/dev/null)
if echo "$HOOK_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'additionalContext' in d" 2>/dev/null; then
  printf 'PASS  prompt hook on EN-prose prompt → emits additionalContext\n'
  PASS=$((PASS + 1))
else
  printf 'FAIL  prompt hook on EN-prose prompt → no additionalContext (got: %s)\n' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi

# T12: code-task prompt → silent
HOOK_OUT=$(echo '{"prompt":"fix the bug in foo.py where the loop runs twice"}' | bash "$PROMPT_HOOK" 2>/dev/null)
check "prompt hook on code-task → silent" "" "$HOOK_OUT"

# T13: README prompt → emits additionalContext
HOOK_OUT=$(echo '{"prompt":"write the README for my open source project"}' | bash "$PROMPT_HOOK" 2>/dev/null)
if echo "$HOOK_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'additionalContext' in d" 2>/dev/null; then
  printf 'PASS  prompt hook on README prompt → emits additionalContext\n'
  PASS=$((PASS + 1))
else
  printf 'FAIL  prompt hook on README prompt → no additionalContext (got: %s)\n' "$HOOK_OUT"
  FAIL=$((FAIL + 1))
fi

# Summary
printf '\n--- humanize-en harness: PASS=%d FAIL=%d ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
