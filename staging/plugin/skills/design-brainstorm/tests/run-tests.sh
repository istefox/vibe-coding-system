#!/usr/bin/env bash
# design-brainstorm self-test harness. Structural anchor checks on SKILL.md.
# bash 3.2-clean. No assoc arrays, no mapfile, no ${v^^}, no <().
set -u
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

SKILL="$HOME/.claude/skills/design-brainstorm/SKILL.md"

# Assertion 1: SKILL.md exists
[ -f "$SKILL" ] && ok "design-brainstorm: SKILL.md exists" || bad "design-brainstorm: SKILL.md missing"

# Assertion 2: frontmatter name: design-brainstorm
grep -q '^name: design-brainstorm$' "$SKILL" 2>/dev/null \
  && ok "design-brainstorm: frontmatter name present" \
  || bad "design-brainstorm: frontmatter name missing"

# Assertion 3 (negative): must NOT contain disable-model-invocation: true
grep -q 'disable-model-invocation: true' "$SKILL" 2>/dev/null \
  && bad "design-brainstorm: contains disable-model-invocation: true (must not)" \
  || ok "design-brainstorm: no disable-model-invocation: true (correct)"

# Assertion 4: cardine first-principles present
grep -q 'first-principles' "$SKILL" 2>/dev/null \
  && ok "design-brainstorm: first-principles technique present" \
  || bad "design-brainstorm: first-principles technique missing"

# Assertion 5: cross-domain analogy present (cross-dominio or cross-domain)
grep -Eq 'cross-dominio|cross-domain' "$SKILL" 2>/dev/null \
  && ok "design-brainstorm: cross-domain analogy technique present" \
  || bad "design-brainstorm: cross-domain analogy technique missing"

# Assertion 6: inversione / pre-mortem present
grep -Eq 'inversione|pre-mortem' "$SKILL" 2>/dev/null \
  && ok "design-brainstorm: inversione/pre-mortem technique present" \
  || bad "design-brainstorm: inversione/pre-mortem technique missing"

# Assertion 7: output contract BRAINSTORM.md present
grep -q 'BRAINSTORM.md' "$SKILL" 2>/dev/null \
  && ok "design-brainstorm: BRAINSTORM.md output contract present" \
  || bad "design-brainstorm: BRAINSTORM.md output contract missing"

# Assertion 8: ## Lingua section REMOVED (EN output policy applies globally)
grep -q '^## Lingua$' "$SKILL" 2>/dev/null \
  && bad "design-brainstorm: ## Lingua section still present (should be removed — EN policy is global)" \
  || ok "design-brainstorm: ## Lingua section absent (EN output policy applied globally)"

# Assertion 9: prior-art technique present (stato dell'arte)
grep -Eq 'prior-art|stato dell.arte' "$SKILL" 2>/dev/null \
  && ok "design-brainstorm: prior-art technique present" \
  || bad "design-brainstorm: prior-art technique missing"

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ] && exit 0 || exit 1
