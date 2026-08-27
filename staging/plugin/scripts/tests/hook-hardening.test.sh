#!/bin/bash
# hook-hardening.test.sh — offline, hermetic, no network, no $HOME dependency. Bash 3.2 clean.
# Covers issue #38 / ADR-0034's five findings, targeting staging/plugin/scripts/ directly (not
# the deployed $HOME/.claude/hooks/ copy the legacy pre-flight-pattern-enforce.sh test targets).
# Run: bash hook-hardening.test.sh
set -u

# Hermeticity: a live Claude Code session exports CLAUDE_CODE_SESSION_ID (issue #33 convention).
# None of the five scripts under test reads it (confirmed during planning); unset defensively.
unset CLAUDE_CODE_SESSION_ID

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# =====================================================================================
# Test 1 (finding 1 / D1): pre-flight-pattern-enforce.sh emits the verified "deny" enum
# member, not the legacy "block", when PATTERN: is missing from a coder subagent window.
FIXTURE_CWD="/test/hookhardening"
FIXTURE_ENC="-test-hookhardening"
SID1="hh1"; AID1="agent001"
PROJ_DIR1="$TMP/.claude/projects/$FIXTURE_ENC"
mkdir -p "$PROJ_DIR1/$SID1/subagents"
JSONL1="$PROJ_DIR1/$SID1/subagents/agent-$AID1.jsonl"
printf '{"type":"assistant","message":{"content":[{"text":"no pattern header here"}]}}\n' > "$JSONL1"
TP1="$PROJ_DIR1/$SID1.jsonl"
touch "$TP1"
PAYLOAD1=$(printf '{"session_id":"%s","tool_name":"Write","cwd":"%s","agent_type":"coder","agent_id":"%s","transcript_path":"%s"}' \
  "$SID1" "$FIXTURE_CWD" "$AID1" "$TP1")
OUT1=$(printf '%s' "$PAYLOAD1" | HOME="$TMP" PATTERN_ENFORCE_DIR="$TMP/state1" bash "$SCRIPTS/pre-flight-pattern-enforce.sh" 2>&1)
if printf '%s' "$OUT1" | grep -q '"permissionDecision":"deny"'; then
  ok "1: pre-flight-pattern-enforce.sh emits verified 'deny' (not legacy 'block')"
else
  bad "1: expected permissionDecision:deny, got: $OUT1"
fi

# =====================================================================================
# Test 2 (finding 2 / D2): chain-memory-capture.sh does not delete a lock directory it
# never acquired, and skips the MEMORY.md upsert event on lock-acquisition timeout.
# Single-process, deterministic: pre-creates the lock dir to simulate a foreign holder —
# no real concurrency needed. Bounded: the unfixed code's own retry loop takes ~2s
# (40 * 0.05s) to exhaust before either behavior (old or new) is observable.
if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP 2: jq not available on this host (informational, not a failure)"
else
  CMCWD="$TMP/cm2cwd"; CMHOME="$TMP/cm2home"
  mkdir -p "$CMCWD"
  ENC2=$(printf '%s' "$CMCWD" | tr '/' '-')
  MEMDIR2="$CMHOME/.claude/projects/$ENC2/memory"
  mkdir -p "$MEMDIR2"
  FORLOCK2="$MEMDIR2/.chain-memory.lock"
  mkdir -p "$FORLOCK2"   # simulate a foreign process already holding the lock
  MANIFEST2="$TMP/2026-07-11-hh2.manifest.yml"
  cat > "$MANIFEST2" <<EOF
current_step: step_e2_execute
status: in_progress
chain_path: standard
next_action: run tests
EOF
  TP2="$CMHOME/.claude/projects/$ENC2/sess2.jsonl"
  touch "$TP2"
  PAYLOAD2=$(printf '{"transcript_path":"%s","tool_input":{"command":"bash manifest-transition.sh %s step_e2_execute"},"tool_response":{"exit_code":0}}' \
    "$TP2" "$MANIFEST2")
  printf '%s' "$PAYLOAD2" | bash "$SCRIPTS/chain-memory-capture.sh" >"$TMP/o2cm" 2>&1
  rc2=$?
  if [ "$rc2" -eq 0 ] && [ -d "$FORLOCK2" ] && [ -f "$MEMDIR2/chain-history/hh2.md" ] && [ ! -f "$MEMDIR2/MEMORY.md" ]; then
    ok "2: foreign lock preserved, per-slug history written, MEMORY.md upsert skipped on timeout"
  else
    bad "2: lock ownership (rc=$rc2 lock=$([ -d "$FORLOCK2" ] && echo present || echo gone) hist=$([ -f "$MEMDIR2/chain-history/hh2.md" ] && echo yes || echo no) memory=$([ -f "$MEMDIR2/MEMORY.md" ] && echo written || echo absent))"
  fi
fi

# =====================================================================================
# Test 3a (finding 3 / D3): approve-test-cmd.sh aborts (nonzero exit) instead of writing
# a hash-less trust line when hash computation yields empty output. Portable: stubs
# shasum/sha256sum on PATH to simulate the failure deterministically — no filesystem
# case-sensitivity dependency, runs identically on every host.
STUBDIR="$TMP/stubbin3"; mkdir -p "$STUBDIR"
printf '#!/bin/bash\nexit 0\n' > "$STUBDIR/shasum"
printf '#!/bin/bash\nexit 0\n' > "$STUBDIR/sha256sum"
chmod +x "$STUBDIR/shasum" "$STUBDIR/sha256sum"

PROJ3A="$TMP/proj3a"; mkdir -p "$PROJ3A/.claude"
echo "echo hi" > "$PROJ3A/.claude/test-cmd"
TRUST3A="$TMP/trust3a"
PATH="$STUBDIR:$PATH" STOP_GATE_TRUST_FILE="$TRUST3A" bash "$SCRIPTS/approve-test-cmd.sh" "$PROJ3A" >"$TMP/o3a" 2>&1
rc3a=$?
if [ "$rc3a" -ne 0 ] && [ ! -s "$TRUST3A" ]; then
  ok "3a: approve-test-cmd.sh aborts on empty hash, no trust line written"
else
  bad "3a: approve-test-cmd.sh empty-hash guard (rc=$rc3a trust_has_content=$([ -s "$TRUST3A" ] && echo yes || echo no))"
fi

# Test 3a-ii: REGRESSION PIN, not a RED assertion (already green before Task 6 too) —
# stop-gate.sh's own, separate, pre-existing fail-open-on-internal-error contract
# (spec §7) must stay exactly as-is: exit 0, silent, no block, when hash computation
# fails. This fix does not and must not change stop-gate.sh's error-handling philosophy.
PROJ3AII="$TMP/proj3aii"; mkdir -p "$PROJ3AII/.claude"
echo "echo hi" > "$PROJ3AII/.claude/test-cmd"
SID3AII="stopgate3aii"
STATE3AII="$TMP/state3aii"; mkdir -p "$STATE3AII"
touch "$STATE3AII/$SID3AII.dirty"
PAYLOAD3AII=$(printf '{"session_id":"%s","cwd":"%s"}' "$SID3AII" "$PROJ3AII")
OUT3AII=$(printf '%s' "$PAYLOAD3AII" | PATH="$STUBDIR:$PATH" STOP_GATE_STATE_DIR="$STATE3AII" bash "$SCRIPTS/stop-gate.sh" 2>&1)
rc3aii=$?
if [ "$rc3aii" -eq 0 ] && [ -z "$OUT3AII" ]; then
  ok "3a-ii: stop-gate.sh stays fail-open (silent allow) when hash computation fails [regression pin]"
else
  bad "3a-ii: stop-gate.sh fail-open regression (rc=$rc3aii out='$OUT3AII')"
fi

# Test 3b (findings 3 + 3b together): on a case-sensitive filesystem, approve-test-cmd.sh
# computes the correct hash for a mixed-case project root, and stop-gate.sh subsequently
# recognizes it as trusted AND successfully cd's into the real (case-preserving) root to
# run the test command. rc alone cannot distinguish old vs. new code here — both fail
# open silently either way (that silence is the bug). The decisive signals are: (a) the
# trust line matches an independently-computed reference hash, and (b) the .dirty marker
# is actually cleared, which only happens after stop-gate.sh's run_with_timeout genuinely
# executes the command with rc=0 — proof the cd into the real path succeeded.
# Portable self-probe: SKIP (counted, not a false PASS/FAIL) on a case-insensitive host.
CASEDIR="$TMP/casecheck3b"; mkdir -p "$CASEDIR/MixedCase"
if [ -d "$CASEDIR/mixedcase" ]; then
  echo "SKIP 3b: host filesystem is case-insensitive, cannot exercise this path (informational)"
else
  PROJ3B="$TMP/CaseSensitiveProj3B"; mkdir -p "$PROJ3B/.claude"
  echo "echo marker3b" > "$PROJ3B/.claude/test-cmd"
  TRUST3B="$TMP/trust3b"
  STOP_GATE_TRUST_FILE="$TRUST3B" STOP_GATE_UNAME=Darwin bash "$SCRIPTS/approve-test-cmd.sh" "$PROJ3B" >"$TMP/o3b-approve" 2>&1
  rc3b_approve=$?
  EXPECT_HASH=$(shasum -a 256 "$PROJ3B/.claude/test-cmd" | awk '{print $1}')
  LOWER3B=$(printf '%s' "$PROJ3B" | tr '[:upper:]' '[:lower:]')
  TRUSTLINE_OK=0
  grep -F -x -q -- "$(printf '%s\t%s' "$EXPECT_HASH" "$LOWER3B")" "$TRUST3B" 2>/dev/null && TRUSTLINE_OK=1

  SID3B="stopgate3b"
  STATE3B="$TMP/state3b"; mkdir -p "$STATE3B"
  touch "$STATE3B/$SID3B.dirty"
  PAYLOAD3B=$(printf '{"session_id":"%s","cwd":"%s"}' "$SID3B" "$PROJ3B")
  OUT3B=$(printf '%s' "$PAYLOAD3B" | STOP_GATE_STATE_DIR="$STATE3B" STOP_GATE_TRUST_FILE="$TRUST3B" STOP_GATE_UNAME=Darwin bash "$SCRIPTS/stop-gate.sh" 2>&1)
  rc3b_stopgate=$?

  if [ "$rc3b_approve" -eq 0 ] && [ "$TRUSTLINE_OK" -eq 1 ] && [ "$rc3b_stopgate" -eq 0 ] \
     && [ -z "$OUT3B" ] && [ ! -f "$STATE3B/$SID3B.dirty" ]; then
    ok "3b: mixed-case root — approve writes the correct hash, stop-gate trusts it and runs the command"
  else
    bad "3b: mixed-case root (rc_approve=$rc3b_approve trustline_ok=$TRUSTLINE_OK rc_stopgate=$rc3b_stopgate out='$OUT3B' dirty_cleared=$([ ! -f "$STATE3B/$SID3B.dirty" ] && echo yes || echo no))"
  fi
fi

# =====================================================================================
# Test 4 (finding 5 / D4): prompt-en-prose-detect.sh emits both the legacy top-level
# additionalContext key and the documented hookSpecificOutput envelope (verified against
# code.claude.com/docs during planning — ADR-0034 §1 Finding 5).
PAYLOAD4='{"prompt":"draft a reddit post announcing this release"}'
OUT4=$(printf '%s' "$PAYLOAD4" | bash "$SCRIPTS/prompt-en-prose-detect.sh" 2>&1)
rc4=$?
TOP4=$(printf '%s' "$OUT4" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('additionalContext',''))
except Exception:
    print('')" 2>/dev/null)
ENV4=$(printf '%s' "$OUT4" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('additionalContext',''))
except Exception:
    print('')" 2>/dev/null)
EVT4=$(printf '%s' "$OUT4" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('hookSpecificOutput',{}).get('hookEventName',''))
except Exception:
    print('')" 2>/dev/null)
if [ "$rc4" -eq 0 ] && [ -n "$TOP4" ] && [ -n "$ENV4" ] && [ "$EVT4" = "UserPromptSubmit" ]; then
  ok "4: prompt-en-prose-detect.sh emits both top-level and hookSpecificOutput envelope forms"
else
  bad "4: dual-envelope (rc=$rc4 top='$TOP4' env='$ENV4' evt='$EVT4')"
fi

# Test 4b: REGRESSION PIN, not RED (already green before this task too) — a non-matching
# prompt must stay completely silent, unchanged by this fix.
PAYLOAD4B='{"prompt":"fix the off-by-one bug in the loop"}'
OUT4B=$(printf '%s' "$PAYLOAD4B" | bash "$SCRIPTS/prompt-en-prose-detect.sh" 2>&1)
rc4b=$?
if [ "$rc4b" -eq 0 ] && [ -z "$OUT4B" ]; then
  ok "4b: non-matching prompt stays silent (no tokens spent) [regression pin]"
else
  bad "4b: non-matching prompt regression (rc=$rc4b out='$OUT4B')"
fi

# Test 4c (ADR-0040): an internal target must stay silent. README, PR, issue, changelog and
# release notes were removed from the target list — those are written plainly, no humanize pass.
PAYLOAD4C='{"prompt":"please draft a README section for this feature"}'
OUT4C=$(printf '%s' "$PAYLOAD4C" | bash "$SCRIPTS/prompt-en-prose-detect.sh" 2>&1)
rc4c=$?
if [ "$rc4c" -eq 0 ] && [ -z "$OUT4C" ]; then
  ok "4c: internal target (README) stays silent"
else
  bad "4c: internal target still fires (rc=$rc4c out='$OUT4C')"
fi

# Test 4d (ADR-0040): naming a publication target without a writing verb must stay silent.
# The old single-regex form matched the word, so a message *about* Reddit fired the hook.
PAYLOAD4D='{"prompt":"the skill is for publications, for example reddit or forum posts"}'
OUT4D=$(printf '%s' "$PAYLOAD4D" | bash "$SCRIPTS/prompt-en-prose-detect.sh" 2>&1)
rc4d=$?
if [ "$rc4d" -eq 0 ] && [ -z "$OUT4D" ]; then
  ok "4d: publication target without a writing verb stays silent"
else
  bad "4d: target-without-verb still fires (rc=$rc4d out='$OUT4D')"
fi

# =====================================================================================
# Test 5 (ADR-0170): chain-memory-capture.sh's write gate. Each hermetic case gets its own
# isolated $TMP subtree (HOME + cwd), mirroring Test 2's pattern. Real bug measured: 44 of 68
# live chain-history files carried a manifest reference that never resolved (unexpanded $PWD,
# a bare glob, a leaked /tmp path) and the hook wrote a permanent all-"?" record anyway.

# plant: 5a | plugin/scripts/chain-memory-capture.sh | [ -r "$MANIFEST" ] || exit 0 | true
# Test 5a — manifest referenced in the command does not exist: no chain-history file, no
# MEMORY.md write. This is the dominant real case (44/68).
CM5A_CWD="$TMP/cm5a/cwd"; CM5A_HOME="$TMP/cm5a/home"
mkdir -p "$CM5A_CWD"
ENC5A=$(printf '%s' "$CM5A_CWD" | tr '/' '-')
MEMDIR5A="$CM5A_HOME/.claude/projects/$ENC5A/memory"
mkdir -p "$MEMDIR5A"
MANIFEST5A="$CM5A_CWD/docs/manifests/2026-08-27-5a-missing.manifest.yml"   # never created
TP5A="$CM5A_HOME/.claude/projects/$ENC5A/sess5a.jsonl"; mkdir -p "$(dirname "$TP5A")"; touch "$TP5A"
PAYLOAD5A=$(printf '{"transcript_path":"%s","cwd":"%s","tool_input":{"command":"bash manifest-transition.sh %s step_e2_execute"},"tool_response":{"exit_code":0}}' \
  "$TP5A" "$CM5A_CWD" "$MANIFEST5A")
printf '%s' "$PAYLOAD5A" | HOME="$CM5A_HOME" bash "$SCRIPTS/chain-memory-capture.sh" >"$TMP/o5a" 2>&1
if [ ! -f "$MEMDIR5A/chain-history/5a-missing.md" ] && [ ! -f "$MEMDIR5A/MEMORY.md" ]; then
  ok "5a: unreadable manifest -> no chain-history file, no MEMORY.md write"
else
  bad "5a: wrote despite an unreadable manifest (hist=$([ -f "$MEMDIR5A/chain-history/5a-missing.md" ] && echo yes || echo no) mem=$([ -f "$MEMDIR5A/MEMORY.md" ] && echo yes || echo no))"
fi

# plant: 5b | plugin/scripts/chain-memory-capture.sh | *[!A-Za-z0-9._-]*) exit 0 ;; | *[!A-Za-z0-9._-]*) : ;;
# Test 5b — the manifest's derived slug carries a glob/shell metacharacter (an unexpanded
# `$(date +%Y-%m-%d)-$SLUG` token, in this fixture). Even though the file is readable and
# well-formed, the slug itself is untrustworthy: no write.
CM5B_CWD="$TMP/cm5b/cwd"; CM5B_HOME="$TMP/cm5b/home"
mkdir -p "$CM5B_CWD/docs/manifests"
ENC5B=$(printf '%s' "$CM5B_CWD" | tr '/' '-')
MEMDIR5B="$CM5B_HOME/.claude/projects/$ENC5B/memory"
mkdir -p "$MEMDIR5B"
MANIFEST5B="$CM5B_CWD/docs/manifests/"'+%Y-%m-%d)-$SLUG.manifest.yml'
cat > "$MANIFEST5B" <<'EOF'
current_step: step_e2_execute
status: in_progress
chain_path: standard
EOF
TP5B="$CM5B_HOME/.claude/projects/$ENC5B/sess5b.jsonl"; mkdir -p "$(dirname "$TP5B")"; touch "$TP5B"
PAYLOAD5B=$(printf '{"transcript_path":"%s","cwd":"%s","tool_input":{"command":"bash manifest-transition.sh %s step_e2_execute"},"tool_response":{"exit_code":0}}' \
  "$TP5B" "$CM5B_CWD" "$MANIFEST5B")
printf '%s' "$PAYLOAD5B" | HOME="$CM5B_HOME" bash "$SCRIPTS/chain-memory-capture.sh" >"$TMP/o5b" 2>&1
if [ ! -d "$MEMDIR5B/chain-history" ] && [ ! -f "$MEMDIR5B/MEMORY.md" ]; then
  ok "5b: slug with a glob/shell metacharacter -> no write"
else
  bad "5b: wrote despite an unsanitized slug (hist_dir=$([ -d "$MEMDIR5B/chain-history" ] && echo present || echo absent) mem=$([ -f "$MEMDIR5B/MEMORY.md" ] && echo yes || echo no))"
fi

# plant: 5c | plugin/scripts/chain-memory-capture.sh | "$CWD_FIELD"/*) : ;; *) exit 0 ;; | "$CWD_FIELD"/*) : ;;\n    *) : ;;
# Test 5c — the manifest is readable and well-named, but resolves outside the payload's own
# `cwd` (a leaked absolute path into a scratch dir, e.g. a test harness running inside a real
# session): no write, even though gates A and B alone would let it through.
CM5C_CWD="$TMP/cm5c/cwd"; CM5C_HOME="$TMP/cm5c/home"; CM5C_OUTSIDE="$TMP/cm5c/outside"
mkdir -p "$CM5C_CWD" "$CM5C_OUTSIDE/docs/manifests"
ENC5C=$(printf '%s' "$CM5C_CWD" | tr '/' '-')
MEMDIR5C="$CM5C_HOME/.claude/projects/$ENC5C/memory"
mkdir -p "$MEMDIR5C"
MANIFEST5C="$CM5C_OUTSIDE/docs/manifests/2026-08-27-5c-outside.manifest.yml"
cat > "$MANIFEST5C" <<'EOF'
current_step: step_e2_execute
status: in_progress
chain_path: standard
EOF
TP5C="$CM5C_HOME/.claude/projects/$ENC5C/sess5c.jsonl"; mkdir -p "$(dirname "$TP5C")"; touch "$TP5C"
PAYLOAD5C=$(printf '{"transcript_path":"%s","cwd":"%s","tool_input":{"command":"bash manifest-transition.sh %s step_e2_execute"},"tool_response":{"exit_code":0}}' \
  "$TP5C" "$CM5C_CWD" "$MANIFEST5C")
printf '%s' "$PAYLOAD5C" | HOME="$CM5C_HOME" bash "$SCRIPTS/chain-memory-capture.sh" >"$TMP/o5c" 2>&1
if [ ! -f "$MEMDIR5C/chain-history/5c-outside.md" ] && [ ! -f "$MEMDIR5C/MEMORY.md" ]; then
  ok "5c: manifest outside the payload cwd -> no write"
else
  bad "5c: wrote despite a manifest resolving outside cwd (hist=$([ -f "$MEMDIR5C/chain-history/5c-outside.md" ] && echo yes || echo no) mem=$([ -f "$MEMDIR5C/MEMORY.md" ] && echo yes || echo no))"
fi

# Test 5d — vacuity guard: a legitimate event (readable manifest, sane slug, inside cwd) still
# writes. Without this, a gate that rejects everything would pass 5a-5c for the wrong reason.
CM5D_CWD="$TMP/cm5d/cwd"; CM5D_HOME="$TMP/cm5d/home"
mkdir -p "$CM5D_CWD/docs/manifests"
ENC5D=$(printf '%s' "$CM5D_CWD" | tr '/' '-')
MEMDIR5D="$CM5D_HOME/.claude/projects/$ENC5D/memory"
mkdir -p "$MEMDIR5D"
MANIFEST5D="$CM5D_CWD/docs/manifests/2026-08-27-5d-legit.manifest.yml"
cat > "$MANIFEST5D" <<'EOF'
current_step: step_e2_execute
status: in_progress
chain_path: standard
next_action: run tests
EOF
TP5D="$CM5D_HOME/.claude/projects/$ENC5D/sess5d.jsonl"; mkdir -p "$(dirname "$TP5D")"; touch "$TP5D"
PAYLOAD5D=$(printf '{"transcript_path":"%s","cwd":"%s","tool_input":{"command":"bash manifest-transition.sh %s step_e2_execute"},"tool_response":{"exit_code":0}}' \
  "$TP5D" "$CM5D_CWD" "$MANIFEST5D")
printf '%s' "$PAYLOAD5D" | HOME="$CM5D_HOME" bash "$SCRIPTS/chain-memory-capture.sh" >"$TMP/o5d" 2>&1
if [ -f "$MEMDIR5D/chain-history/5d-legit.md" ] && grep -q 'current_step: step_e2_execute' "$MEMDIR5D/chain-history/5d-legit.md" && [ -f "$MEMDIR5D/MEMORY.md" ]; then
  ok "5d: legitimate readable/sane/in-cwd manifest still writes [vacuity guard]"
else
  bad "5d: a legitimate event was rejected (hist=$([ -f "$MEMDIR5D/chain-history/5d-legit.md" ] && echo yes || echo no) mem=$([ -f "$MEMDIR5D/MEMORY.md" ] && echo yes || echo no) out=$(cat "$TMP/o5d"))"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
