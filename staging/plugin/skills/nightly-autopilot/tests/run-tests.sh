#!/bin/bash
# nightly-autopilot test harness (ADR-0022). Layout-aware: runs from the repo staging tree
# (staging/plugin/...) or from the installed ~/.claude tree, resolving script/skill paths in
# either. Tests the shell helpers, the conductor patch, and the ci.yml token. Bash 3.2 clean.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }

# Resolve the scripts dir: staging is plugin/scripts, the install keeps helpers in ~/.claude/hooks.
SCRIPTS=""
for cand in "$HERE/../../../scripts" "$HOME/.claude/hooks"; do
  if [ -f "$cand/publish-feature.sh" ]; then SCRIPTS=$(cd "$cand" && pwd); break; fi
done
[ -n "$SCRIPTS" ] || { printf 'FAIL cannot locate scripts dir\n1 passed, 1 failed\n'; exit 1; }

# Resolve the skills dir (for the conductor patch check).
SKILLS=""
for cand in "$HERE/../.." "$HOME/.claude/skills"; do
  if [ -d "$cand/project-conductor" ]; then SKILLS=$(cd "$cand" && pwd); break; fi
done

# Resolve the ci.yml template (staging path or installed path).
CI=""
for cand in "$HERE/../../../../project-templates/ci/ci.yml" "$HOME/.claude/templates/ci.yml"; do
  [ -f "$cand" ] && { CI="$cand"; break; }
done

# 1. Phase 1 script tests (co-located with the scripts under tests/).
if [ -f "$SCRIPTS/tests/phase1.test.sh" ] && bash "$SCRIPTS/tests/phase1.test.sh" >/dev/null 2>&1; then
  ok "phase1 script tests pass"
else
  no "phase1 script tests pass"
fi

# 2. The three helpers exist and are syntax-clean.
for s in nightly-guard publish-feature set-branch-protection; do
  if [ -f "$SCRIPTS/$s.sh" ] && bash -n "$SCRIPTS/$s.sh" >/dev/null 2>&1; then
    ok "helper ok: $s.sh"
  else
    no "helper ok: $s.sh"
  fi
done

# 3. Conductor carries the nightly roadmap-autopilot patch.
if [ -n "$SKILLS" ] && grep -q '_nightly' "$SKILLS/project-conductor/SKILL.md" 2>/dev/null; then
  ok "conductor has nightly mode"
else
  no "conductor has nightly mode"
fi

# 4. CI template holds the substitution token.
if [ -n "$CI" ] && grep -q '__TEST_CMD__' "$CI" 2>/dev/null; then
  ok "ci.yml has __TEST_CMD__ token"
else
  no "ci.yml has __TEST_CMD__ token"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
