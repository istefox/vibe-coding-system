#!/bin/bash
# nightly-autopilot test harness (ADR-0022). Runs the Phase 1 script tests and checks that
# the skill's runtime artifacts and cross-references exist. Bash 3.2 clean.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
# repo layout: .../staging/plugin/skills/nightly-autopilot/tests
PLUGIN=$(cd "$HERE/../../.." && pwd)
REPO=$(cd "$PLUGIN/../.." && pwd)

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
no() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }

# 1. Phase 1 script tests.
if bash "$PLUGIN/scripts/tests/phase1.test.sh" >/dev/null 2>&1; then
  ok "phase1 script tests pass"
else
  no "phase1 script tests pass"
fi

# 2. Required artifacts present.
for f in \
  "$PLUGIN/scripts/nightly-guard.sh" \
  "$PLUGIN/scripts/publish-feature.sh" \
  "$PLUGIN/scripts/set-branch-protection.sh" \
  "$PLUGIN/skills/nightly-autopilot/SKILL.md" \
  "$PLUGIN/skills/project-conductor/SKILL.md" \
  "$REPO/staging/project-templates/ci/ci.yml" \
  "$REPO/docs/RUNBOOK-nightly-autopilot.md" \
  "$REPO/docs/architecture/ADR-0022-nightly-autopilot-goal.md" \
  "$REPO/docs/architecture/ADR-0022-morning-report-schema.md"
do
  [ -f "$f" ] && ok "exists: ${f#$REPO/}" || no "missing: ${f#$REPO/}"
done

# 3. Conductor carries the nightly roadmap-autopilot patch.
grep -q '_nightly' "$PLUGIN/skills/project-conductor/SKILL.md" \
  && ok "conductor has nightly mode" || no "conductor has nightly mode"

# 4. CI template still holds the substitution token.
grep -q '__TEST_CMD__' "$REPO/staging/project-templates/ci/ci.yml" \
  && ok "ci.yml has __TEST_CMD__ token" || no "ci.yml has __TEST_CMD__ token"

# 5. Scripts are executable and syntax-clean.
for s in nightly-guard publish-feature set-branch-protection; do
  bash -n "$PLUGIN/scripts/$s.sh" >/dev/null 2>&1 \
    && ok "syntax: $s.sh" || no "syntax: $s.sh"
done

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
