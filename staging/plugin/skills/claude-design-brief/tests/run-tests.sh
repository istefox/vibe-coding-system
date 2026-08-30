#!/usr/bin/env bash
# claude-design-brief self-test harness. Structural anchor checks on SKILL.md.
# bash 3.2-clean. No assoc arrays, no mapfile, no ${v^^}, no <().
set -u
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SKILL="$HOME/.claude/skills/claude-design-brief/SKILL.md"

# Assertion 1: SKILL.md exists
[ -f "$SKILL" ] && ok "claude-design-brief: SKILL.md exists" || bad "claude-design-brief: SKILL.md missing"

# Assertion 2: frontmatter name: claude-design-brief
grep -q '^name: claude-design-brief$' "$SKILL" 2>/dev/null \
  && ok "claude-design-brief: frontmatter name present" \
  || bad "claude-design-brief: frontmatter name missing"

# Assertion 3 (negative): must NOT contain disable-model-invocation: true
grep -q 'disable-model-invocation: true' "$SKILL" 2>/dev/null \
  && bad "claude-design-brief: contains disable-model-invocation: true (must not)" \
  || ok "claude-design-brief: no disable-model-invocation: true (correct)"

# Assertion 4: names gate 1d (the chain-perimeter contract, C8 in skill-coverage-perimeter.test.sh)
grep -qi 'gate 1d' "$SKILL" 2>/dev/null \
  && ok "claude-design-brief: names gate 1d" \
  || bad "claude-design-brief: does not name gate 1d"

# Assertion 5: output contract DESIGN-PROMPT.md present
grep -q 'DESIGN-PROMPT.md' "$SKILL" 2>/dev/null \
  && ok "claude-design-brief: DESIGN-PROMPT.md output contract present" \
  || bad "claude-design-brief: DESIGN-PROMPT.md output contract missing"

# Assertion 6: does NOT write DESIGN.md itself (that is the orchestrator's job at 1d-B)
grep -q 'Does NOT write .DESIGN.md' "$SKILL" 2>/dev/null \
  && ok "claude-design-brief: states it does not write DESIGN.md" \
  || bad "claude-design-brief: missing the does-not-write-DESIGN.md boundary statement"

# Assertion 7: chain invocation return contract present (silent-end instruction)
grep -q 'End execution silently' "$SKILL" 2>/dev/null \
  && ok "claude-design-brief: chain invocation silent-return contract present" \
  || bad "claude-design-brief: chain invocation silent-return contract missing"

# Assertion 8: reads SPEC.md (required input)
grep -q 'SPEC.md' "$SKILL" 2>/dev/null \
  && ok "claude-design-brief: reads SPEC.md" \
  || bad "claude-design-brief: does not mention reading SPEC.md"

# Assertion 9: no public API for Claude Design — states the login-walled/no-API constraint
grep -Eq 'no public API|no API' "$SKILL" 2>/dev/null \
  && ok "claude-design-brief: states the no-public-API constraint" \
  || bad "claude-design-brief: missing the no-public-API constraint"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
