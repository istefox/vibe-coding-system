#!/bin/bash
# Dedicated harness for vibe-status skill — target PASS=17.
# Isolated; never touches real system state.
# 3.2-clean: no assoc array, no mapfile, no ${v^^}, no <().
set -u
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
# VIBE_STATUS_SKILL_DIR override (issue #37): default unchanged (deployed copy), so this
# harness stays $HOME-coupled/CI-dark by design (ADR-0033 §Neutral). Setting it lets a
# checkpoint or a human test the staging tree's own fixes directly, without touching
# ~/.claude — see INTEGRATION.md.
SKILL="${VIBE_STATUS_SKILL_DIR:-$HOME/.claude/skills/vibe-status}"
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

# Test 10: skills/*/tests/run-tests.sh + hooks/tests/*.sh harness discovery finds >= 5 harnesses,
# with the recursion guard active (issue #37) — no unbounded self-recursion, no hang.
START10=$(date +%s)
VIBE_STATUS_HARNESS_TIMEOUT=4 bash "$AGG" >"$TMP/o10_full" 2>&1
rc10=$?
END10=$(date +%s); DUR10=$((END10 - START10))
harness_total=$(grep -E '^## Harness \(' "$TMP/o10_full" | sed -n 's/.*(\([0-9]*\)\/\([0-9]*\) passing).*/\2/p')
harness_total="${harness_total:-0}"
if [ $rc10 -eq 0 ] && [ "$harness_total" -ge 5 ] && [ "$DUR10" -le 15 ]; then
  ok "10: skills+hooks harness discovery (found ${harness_total} >= 5, ${DUR10}s, no recursion hang)"
else
  bad "10: harness discovery (found ${harness_total} < 5, rc=$rc10, dur=${DUR10}s)"
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

# Test 14: harness-runner.sh timeout kills the WHOLE process group, not just the top PID
# (issue #37 finding 1b — a pre-fix branch kills only one PID, orphaning any grandchild the
# harness itself forked). PGID-scoped, bounded-wait ps assertion — not a fixed sleep, not a
# loose string pgrep.
# NON-REGRESSION NOTE: on a machine with GNU timeout on PATH (Homebrew coreutils), this
# single-level fork case already passes pre-fix — GNU timeout puts its child in a new process
# group and kills that whole group on its own (ADR-0033 §1, "correct in isolation"). Only the
# *nested*-timeout case (Test 15) reproduces genuine pre-fix RED for finding 1b on such a
# machine. Kept here as a non-regression companion pinning the group-kill contract for every
# machine, including one without timeout/gtimeout installed, where this test IS the RED case.
mkdir -p "$TMP/orphanskill"
MARK14="$TMP/orphan-marker"; PIDFILE14="$TMP/orphan-pgid"
rm -f "$MARK14" "$PIDFILE14"
cat > "$TMP/orphanskill/slow.sh" <<EOF
#!/bin/bash
echo \$\$ > "$PIDFILE14"
( sleep 20; echo done >> "$MARK14" ) &
sleep 20
EOF
chmod +x "$TMP/orphanskill/slow.sh"
bash "$RUNNER" "$TMP/orphanskill/slow.sh" 2 >"$TMP/o14" 2>&1 &
R14=$!

w=0
while [ ! -s "$PIDFILE14" ] && [ $w -lt 5 ]; do sleep 1; w=$((w+1)); done
PGID14=$(cat "$PIDFILE14" 2>/dev/null | tr -d ' ')

wait "$R14" 2>/dev/null

SURVIVORS=1
if [ -n "$PGID14" ]; then
  i=0
  while [ $i -lt 8 ]; do
    if ! ps -eo pgid | tr -d ' ' | grep -qx "$PGID14"; then
      SURVIVORS=0
      break
    fi
    sleep 1; i=$((i+1))
  done
else
  SURVIVORS=2
fi

if [ "$SURVIVORS" -eq 0 ] && [ ! -f "$MARK14" ]; then
  ok "14: harness-runner.sh timeout kills the whole process group (PGID ${PGID14:-?} empty, no orphaned grandchild)"
else
  bad "14: orphan check failed (survivors=$SURVIVORS pgid=${PGID14:-none} marker=$([ -f "$MARK14" ] && echo present || echo absent))"
  [ -n "$PGID14" ] && kill -9 -- "-$PGID14" 2>/dev/null
fi

# Test 15: recursion guard caps vibe-status's self-invocation to exactly one nested level
# (issue #37 finding 1a). Fully hermetic: isolated fake $HOME, does not touch the real one.
TMP_REC="$TMP/recguard"
mkdir -p "$TMP_REC/.claude/skills/vibe-status/scripts" "$TMP_REC/.claude/skills/vibe-status/tests"
cp "$RUNNER" "$TMP_REC/.claude/skills/vibe-status/scripts/harness-runner.sh"
chmod +x "$TMP_REC/.claude/skills/vibe-status/scripts/harness-runner.sh"
MARK15="$TMP/recguard-marker"
rm -f "$MARK15"
cat > "$TMP_REC/.claude/skills/vibe-status/tests/run-tests.sh" <<EOF
#!/bin/bash
echo hit >> "$MARK15"
HOME="$TMP_REC" VIBE_STATUS_HARNESS_TIMEOUT=3 bash "$AGG" >/dev/null 2>&1
echo "PASS=1 FAIL=0"
EOF
chmod +x "$TMP_REC/.claude/skills/vibe-status/tests/run-tests.sh"

START15=$(date +%s)
HOME="$TMP_REC" VIBE_STATUS_HARNESS_TIMEOUT=3 bash "$AGG" >"$TMP/o15" 2>&1
rc15=$?
END15=$(date +%s); DUR15=$((END15 - START15))
hits15=$(wc -l < "$MARK15" 2>/dev/null | tr -d ' '); hits15="${hits15:-0}"

if [ $rc15 -eq 0 ] && [ "$hits15" = "1" ] && [ "$DUR15" -le 12 ]; then
  ok "15: recursion guard caps self-invocation to exactly one nested level (hits=1, ${DUR15}s)"
else
  bad "15: recursion guard (rc=$rc15 hits=$hits15 expected 1, dur=${DUR15}s)"
fi
# Cleanup for this specific RED-phase run: the unfixed aggregate.sh recurses unboundedly inside
# TMP_REC until harness-runner.sh's own per-level TMO bounds it — any stragglers still unwinding
# in the background are scoped to this fixture's own path, safe to force-clean here.
pkill -9 -f "$TMP_REC/.claude/skills/vibe-status" 2>/dev/null
true

# Test 16: MEMORY.md with zero '- [' index entries renders a single-line count, not the
# two-line "0\n0..." the unfixed `grep -c ... || echo 0` produces (issue #37 finding 2, same
# bug class ADR-0028/#32 already fixed once in a sibling script).
MEMCWD="$TMP/memcwd"; MEMHOME="$TMP/memhome"
mkdir -p "$MEMCWD"
ENC16=$(printf '%s' "$MEMCWD" | tr '/' '-')
mkdir -p "$MEMHOME/.claude/projects/$ENC16/memory"
printf '# Memory index\n\nNo entries yet.\n' > "$MEMHOME/.claude/projects/$ENC16/memory/MEMORY.md"
( cd "$MEMCWD" && HOME="$MEMHOME" bash "$AGG" --skip-harness >"$TMP/o16" 2>&1 )
rc16=$?
mem16=$(grep -A1 '^## Memory$' "$TMP/o16" | tail -n 1)
if [ $rc16 -eq 0 ] && [ "$mem16" = "0 entries indexed in MEMORY.md" ]; then
  ok "16: MEMORY.md with zero index entries renders single-line '0 entries indexed'"
else
  bad "16: Memory zero-count (rc=$rc16 line='$mem16')"
fi

# Test 17: chain-memory wiring — aggregate.sh calls chain-memory-section.sh at the right point
# with the right MEM_DIR argument (issue #37 finding 3, ADR-0021 follow-up; zero prior coverage
# anywhere in the repo, confirmed by a full grep during planning).
CHAINCWD="$TMP/chaincwd"; CHAINHOME="$TMP/chainhome"
mkdir -p "$CHAINCWD"
ENC17=$(printf '%s' "$CHAINCWD" | tr '/' '-')
CHAINHIST="$CHAINHOME/.claude/projects/$ENC17/memory/chain-history"
mkdir -p "$CHAINHIST"
# aggregate.sh's wired call resolves chain-memory-section.sh via ITS OWN $HOME at execution
# time (matching the existing RUNNER/harness-runner.sh pattern) — since this fixture overrides
# $HOME to the isolated $CHAINHOME below, seed the script there too, same as Test 15 already
# does for harness-runner.sh (cp "$RUNNER" ...).
mkdir -p "$CHAINHOME/.claude/skills/vibe-status/scripts"
cp "$SKILL/scripts/chain-memory-section.sh" "$CHAINHOME/.claude/skills/vibe-status/scripts/chain-memory-section.sh"
chmod +x "$CHAINHOME/.claude/skills/vibe-status/scripts/chain-memory-section.sh"
cat > "$CHAINHIST/demo-chain.md" <<'EOF'
---
node_type: chain-history
topic: demo-chain
---

# Chain history — demo-chain

## STATE OF FACT
- current_step: step_e2_execute
- status: in_progress
- next_action: run tests
EOF
( cd "$CHAINCWD" && HOME="$CHAINHOME" bash "$AGG" --skip-harness >"$TMP/o17a" 2>&1 )
rc17a=$?

NOCHAINCWD="$TMP/nochaincwd"
mkdir -p "$NOCHAINCWD"
( cd "$NOCHAINCWD" && HOME="$CHAINHOME" bash "$AGG" --skip-harness >"$TMP/o17b" 2>&1 )
rc17b=$?

if [ $rc17a -eq 0 ] && grep -q '^## Active chains' "$TMP/o17a" && grep -q 'demo-chain' "$TMP/o17a" \
   && [ $rc17b -eq 0 ] && ! grep -q '^## Active chains' "$TMP/o17b"; then
  ok "17: chain-memory wiring — Active chains present with data, absent without"
else
  bad "17: chain-memory wiring (rc17a=$rc17a rc17b=$rc17b)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
rm -rf "$TMP"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
