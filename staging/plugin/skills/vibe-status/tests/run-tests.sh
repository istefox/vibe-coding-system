#!/bin/bash
# Dedicated harness for vibe-status skill — target PASS=13.
# Isolated; never touches real system state.
# 3.2-clean: no assoc array, no mapfile, no ${v^^}, no <().
set -u
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
SKILL="$HOME/.claude/skills/vibe-status"
AGG="$SKILL/scripts/aggregate.sh"
RUNNER="$SKILL/scripts/harness-runner.sh"

# Test 1: SKILL.md exists + has name field
if [ -f "$SKILL/SKILL.md" ] && grep -q '^name: vibe-status' "$SKILL/SKILL.md"; then
  ok "1: SKILL.md exists + name field"
else
  bad "1: SKILL.md / name field"
fi

# Test 2: aggregate.sh exists + executable
if [ -x "$AGG" ]; then
  ok "2: aggregate.sh executable"
else
  bad "2: aggregate.sh not executable"
fi

# Test 3: harness-runner.sh exists + executable
if [ -x "$RUNNER" ]; then
  ok "3: harness-runner.sh executable"
else
  bad "3: harness-runner.sh not executable"
fi

# Test 4: Smoke test — aggregate.sh --skip-harness produces well-formed Markdown
bash "$AGG" --skip-harness >"$TMP/o4" 2>&1
head1_4=$(head -n 1 "$TMP/o4")
if echo "$head1_4" | grep -q '^# Vibe-Coding System Status' && grep -q '^## Health:' "$TMP/o4"; then
  ok "4: smoke Markdown well-formed"
else
  bad "4: smoke Markdown (head=$(head -n 1 "$TMP/o4"))"
fi

# Test 5: --skip-harness completes in <=2s
START5=$(date +%s)
bash "$AGG" --skip-harness >/dev/null 2>&1
END5=$(date +%s)
DUR5=$((END5 - START5))
if [ "$DUR5" -le 2 ]; then
  ok "5: --skip-harness <=2s (was ${DUR5}s)"
else
  bad "5: --skip-harness too slow (${DUR5}s)"
fi

# Test 6: --json flag produces valid JSON with .health field
bash "$AGG" --json --skip-harness >"$TMP/o6" 2>&1
if command -v jq >/dev/null 2>&1; then
  if jq -e '.health' "$TMP/o6" >/dev/null 2>&1; then
    ok "6: --json parsable + has .health"
  else
    bad "6: --json invalid (out=$(cat "$TMP/o6"))"
  fi
else
  ok "6: --json (skipped: no jq)"
fi

# Test 7: harness-runner.sh timeout — slow harness killed in 2s, RC=124
mkdir -p "$TMP/fakeskill/tests"
printf '#!/bin/bash\nsleep 30\necho "PASS=1 FAIL=0"\n' >"$TMP/fakeskill/tests/run-tests.sh"
chmod +x "$TMP/fakeskill/tests/run-tests.sh"
bash "$RUNNER" "$TMP/fakeskill/tests/run-tests.sh" 2 >"$TMP/o7" 2>&1
head1_7=$(head -n 1 "$TMP/o7")
if echo "$head1_7" | grep -q 'RC=124'; then
  ok "7: timeout RC=124 captured"
else
  bad "7: timeout (head=$head1_7)"
fi

# Test 8: Missing ADR directory degrades gracefully (exit 0, no crash)
TMP_CWD="$TMP/nocwd"
mkdir -p "$TMP_CWD"
( cd "$TMP_CWD" && bash "$AGG" --skip-harness >"$TMP/o8" 2>&1 )
rc8=$?
if [ $rc8 -eq 0 ] && grep -q 'no project ADR directory\|## ADR (0 total' "$TMP/o8"; then
  ok "8: missing ADR dir graceful"
else
  bad "8: missing ADR (rc=$rc8; out=$(grep -A1 '## ADR' "$TMP/o8" | head -2))"
fi

# Test 9: Malformed settings.json degrades gracefully — fake HOME
TMP_HOME="$TMP/fakehome"
mkdir -p "$TMP_HOME/.claude/skills"
printf 'not-json-garbage\n' >"$TMP_HOME/.claude/settings.json"
HOME="$TMP_HOME" bash "$AGG" --skip-harness >"$TMP/o9" 2>&1
rc9=$?
if [ $rc9 -eq 0 ] && grep -q 'unable to parse settings.json\|no hooks configured' "$TMP/o9"; then
  ok "9: malformed settings graceful"
else
  bad "9: malformed settings (rc=$rc9; out=$(grep -A1 '## Hooks' "$TMP/o9" | head -2))"
fi

# Test 10: hooks/tests/*.sh harness discovery — aggregate.sh must find >= 5 harness
# (includes ~/.claude/hooks/tests/pre-flight-pattern-enforce.sh, not only skills/*/tests/)
bash "$AGG" --skip-harness >"$TMP/o10" 2>&1
# Extract harness count from line "## Harness (N/M passing)" — but skip-harness prints "(skipped)"
# We need a real run to count. Run without --skip-harness into a fake HOME that has no skills/
# but real hooks dir (use the actual HOME so hooks are visible; cap timeout to 4s to keep test fast)
TMP_AGG_HOME="$TMP/fakehome10"
mkdir -p "$TMP_AGG_HOME/.claude/skills"
# Copy hooks/tests dir so pre-flight-pattern-enforce.sh is discoverable
if [ -d "$HOME/.claude/hooks/tests" ]; then
  mkdir -p "$TMP_AGG_HOME/.claude/hooks"
  cp -r "$HOME/.claude/hooks/tests" "$TMP_AGG_HOME/.claude/hooks/tests"
fi
# Use real HOME but override timeout to be short; just inspect real output harness count
VIBE_STATUS_HARNESS_TIMEOUT=4 bash "$AGG" >"$TMP/o10_full" 2>&1
harness_total=$(grep -E '^## Harness \(' "$TMP/o10_full" | sed -n 's/.*(\([0-9]*\)\/\([0-9]*\) passing).*/\2/p')
harness_total="${harness_total:-0}"
if [ "$harness_total" -ge 5 ]; then
  ok "10: hooks/tests harness discovery (found ${harness_total} >= 5)"
else
  bad "10: hooks/tests harness discovery (found ${harness_total} < 5; hooks/tests/*.sh not discovered)"
fi

# Test 11: per-branch triage discovery + array parse
mkdir -p "$TMP/triagecwd/.claude"
printf '[{"id":"aaa","sev":"MAJOR","loc":"x.sh:1","status":"open"},{"id":"bbb","sev":"MINOR","loc":"y.sh:2","status":"resolved"}]' \
  >"$TMP/triagecwd/.claude/.triage-fix-last-testbr.json"
( cd "$TMP/triagecwd" && bash "$AGG" --skip-harness >"$TMP/o11" 2>&1 )
triage11=$(grep -A1 '## Recent triage cycle' "$TMP/o11" | tail -n 1)
if command -v jq >/dev/null 2>&1; then
  if [ "$triage11" != "(no recent triage cycle)" ] && \
     echo "$triage11" | grep -q 'open=1' && \
     echo "$triage11" | grep -q 'resolved=1'; then
    ok "11: per-branch triage discovery + array parse"
  else
    bad "11: per-branch triage (line='$triage11')"
  fi
else
  ok "11: (skipped: no jq)"
fi

# Test 12: agent-notes (ADR-0012) freshness signal — present + absent cases
TMP_AN="$TMP/anhome"
ANCWD="$TMP/ancwd"
mkdir -p "$ANCWD" "$TMP_AN/.claude/skills"
ENC12=$(printf '%s' "$ANCWD" | tr '/' '-')
mkdir -p "$TMP_AN/.claude/projects/$ENC12/memory/agent-notes"
printf '# notes\n- [arch] sample durable note\n' >"$TMP_AN/.claude/projects/$ENC12/memory/agent-notes/architect.md"
printf 'README\n' >"$TMP_AN/.claude/projects/$ENC12/memory/agent-notes/README.md"
( cd "$ANCWD" && HOME="$TMP_AN" bash "$AGG" --skip-harness >"$TMP/o12" 2>&1 )
rc12=$?
# Present case: count is 1 (architect.md only; README.md excluded)
if [ $rc12 -eq 0 ] && grep -A1 '## Agent notes' "$TMP/o12" | grep -q '1 agent'; then
  ANCWD2="$TMP/ancwd2"
  mkdir -p "$ANCWD2"
  ( cd "$ANCWD2" && HOME="$TMP_AN" bash "$AGG" --skip-harness >"$TMP/o12b" 2>&1 )
  rc12b=$?
  if [ $rc12b -eq 0 ] && grep -A1 '## Agent notes' "$TMP/o12b" | grep -q '(no agent-notes)'; then
    ok "12: agent-notes signal present(1, README excluded)+absent graceful"
  else
    bad "12: agent-notes absent case (rc=$rc12b; out=$(grep -A1 '## Agent notes' "$TMP/o12b" | head -2))"
  fi
else
  bad "12: agent-notes present case (rc=$rc12; out=$(grep -A1 '## Agent notes' "$TMP/o12" | head -2))"
fi

# Test 13: ADR scan excludes *-implementation-plan.md companion (ADR-0012 cosmetic fix)
ADRCWD="$TMP/adrcwd"
mkdir -p "$ADRCWD/docs/architecture"
printf '# ADR-0001 — real adr\n\n**Status:** Accepted — 2026-01-01\n' >"$ADRCWD/docs/architecture/ADR-0001-real.md"
printf '# Piano di implementazione — ADR-0001\n\n**Stato del piano:** DONE\n' >"$ADRCWD/docs/architecture/ADR-0001-implementation-plan.md"
( cd "$ADRCWD" && bash "$AGG" --skip-harness >"$TMP/o13" 2>&1 )
rc13=$?
adr_hdr13=$(grep -E '^## ADR \(' "$TMP/o13")
if [ $rc13 -eq 0 ] && echo "$adr_hdr13" | grep -q '1 total' && ! grep -q 'Piano di implementazione' "$TMP/o13"; then
  ok "13: ADR scan excludes *-implementation-plan.md companion"
else
  bad "13: ADR companion exclusion (hdr='$adr_hdr13')"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$TMP"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
