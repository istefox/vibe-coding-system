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

# T6-T9 removed with post-md-tells-hint.sh (ADR-0040). The hook fired on every .md written,
# which in this repo means every ADR and every doc. It was also a no-op from the model's point
# of view: it printed its hint as plain stdout on exit 0, and PostToolUse stdout on exit 0 goes
# to the debug log, never into context (code.claude.com/docs/en/hooks).
# detect-ai-tells.sh itself stays and keeps its coverage in T1-T5 above.

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

# T13: README prompt → silent (ADR-0040: internal artifact, no humanize pass)
HOOK_OUT=$(echo '{"prompt":"write the README for my open source project"}' | bash "$PROMPT_HOOK" 2>/dev/null)
check "prompt hook on README prompt → silent" "" "$HOOK_OUT"

# T14: publication target named without a writing verb → silent (ADR-0040: the hook must match
# the intent, not the word — a message *about* Reddit is not a request to write a Reddit post)
HOOK_OUT=$(echo '{"prompt":"the skill is for publications, for example reddit or forum posts"}' | bash "$PROMPT_HOOK" 2>/dev/null)
check "prompt hook on target-without-verb → silent" "" "$HOOK_OUT"

# Summary
printf '\n--- humanize-en harness: PASS=%d FAIL=%d ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
