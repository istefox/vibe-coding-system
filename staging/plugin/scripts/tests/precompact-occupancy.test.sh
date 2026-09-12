#!/bin/bash
# precompact-occupancy.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash precompact-occupancy.test.sh
#
# Covers issue #112 / ADR-0058's PreCompact guard (§D1-D3 only): a hook that forces a
# chain-history handoff write when `current_step` is a dispatch state (§D1), refuses AT MOST ONCE
# per compaction cycle (§D2 — the decision that keeps the hook from being harmful, since
# PreCompact fires because the window is full and an unbounded refusal strands the session instead
# of protecting it), and fails open on every error (§D3).
#
# §D4/D5 (context-occupancy.sh's measurement, and usage-daily-hint.sh's Stop-hook reporting of it)
# were retired 2026-09-12 — see ADR-0058's dated Correction. XD2 below still stands: it pins that
# the guard never reached for the occupancy script, which is worth keeping even with that script
# gone.
#
# ASSERTION LABELS ARE X-PREFIXED (XA, XB, ...). Checked before use: `grep -RhoE '"[A-Z]{1,3}[0-9]'
# across every existing tests/*.test.sh file turns up A/B/C/.../TB/TI/... but no bare or compound
# prefix starting with X. Collision-free.
#
# NO FIXTURE PATH CONTAINS "secret", "credential", ".env", ".pem" or ".key" — protect-files.sh
# denies any path containing "secrets" (plural); this file uses none of those substrings anywhere,
# singular or plural, in any fixture name.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
REPO=$(cd "$STAGING/.." && pwd)                          # repo root

GUARD="$SCRIPTS/precompact-guard.sh"
SYNCSH="$STAGING/sync-to-claude.sh"
SETTINGSJSON="$STAGING/user/settings.json"
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
SYNC_MANUAL_TEST="$SCRIPTS/tests/sync-manual-steps.test.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------------------------

# make_root <name> -> path to a fresh project root with docs/manifests/ present.
make_root() {
  _r="$TMP/proj-$1"; mkdir -p "$_r/docs/manifests"
  printf '%s' "$_r"
}

# write_manifest <root> <slug> <current_step> <status>
write_manifest() {
  cat > "$1/docs/manifests/2026-07-26-$2.manifest.yml" <<EOF
current_step: "$3"
status: "$4"
chain_path: "standard"
next_action: "resume the chain"
EOF
}

pc_payload() {  # <session_id> <cwd> <transcript_path>
  printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s","hook_event_name":"PreCompact"}' \
    "$1" "$2" "$3"
}

run_guard() {  # <json> <state_dir>
  printf '%s' "$1" | PRECOMPACT_GUARD_DIR="$2" bash "$GUARD" 2>/dev/null
}

blocked() { printf '%s' "$1" | jq -e '.decision == "block"' >/dev/null 2>&1; }

# ===================================================================================
# XA. The hook forces the handoff write when current_step is a dispatch state (§D1).
# ===================================================================================
ROOT_XA=$(make_root xa)
write_manifest "$ROOT_XA" demoxa step_5_implementation in_progress
TRANSCRIPT_XA="$TMP/sess-xa/replay.jsonl"; mkdir -p "$(dirname "$TRANSCRIPT_XA")"; : > "$TRANSCRIPT_XA"
OUT_XA=$(run_guard "$(pc_payload s-xa "$ROOT_XA" "$TRANSCRIPT_XA")" "$TMP/state-xa")
HIST_XA="$TMP/sess-xa/memory/chain-history/demoxa.md"

if [ -f "$HIST_XA" ]; then
  ok "XA1: chain-history handoff file was created for a dispatch-state manifest"
else
  bad "XA1: no chain-history handoff file was created — $HIST_XA missing"
fi

if [ -f "$HIST_XA" ] && grep -q 'current_step: step_5_implementation' "$HIST_XA" 2>/dev/null; then
  ok "XA2: handoff file records the current_step that triggered it"
else
  bad "XA2: handoff file does not record current_step=step_5_implementation"
fi

if [ -f "$HIST_XA" ] && grep -qi 'precompact-guard' "$HIST_XA" 2>/dev/null; then
  ok "XA3: handoff file's event log attributes the write to precompact-guard"
else
  bad "XA3: handoff file does not attribute the forced write to precompact-guard"
fi

# Non-dispatch current_step -> no handoff write at all.
ROOT_XA2=$(make_root xa2)
write_manifest "$ROOT_XA2" demoxa2 step_1_interview in_progress
TRANSCRIPT_XA2="$TMP/sess-xa2/replay.jsonl"; mkdir -p "$(dirname "$TRANSCRIPT_XA2")"; : > "$TRANSCRIPT_XA2"
run_guard "$(pc_payload s-xa2 "$ROOT_XA2" "$TRANSCRIPT_XA2")" "$TMP/state-xa2" >/dev/null
HIST_XA2="$TMP/sess-xa2/memory/chain-history/demoxa2.md"
if [ ! -f "$HIST_XA2" ]; then
  ok "XA4: non-dispatch current_step (step_1_interview) triggers no handoff write"
else
  bad "XA4: a handoff write happened for a non-dispatch current_step"
fi

# ===================================================================================
# XB. The refusal is ONE-SHOT — a second PreCompact in the same cycle proceeds regardless of
# manifest state, and the one-shot state is cleared appropriately for a later cycle.
# ===================================================================================
ROOT_XB=$(make_root xb)
write_manifest "$ROOT_XB" demoxb step_6_review in_progress
TRANSCRIPT_XB="$TMP/sess-xb/replay.jsonl"; mkdir -p "$(dirname "$TRANSCRIPT_XB")"; : > "$TRANSCRIPT_XB"
STATE_XB="$TMP/state-xb"
PAYLOAD_XB=$(pc_payload s-xb "$ROOT_XB" "$TRANSCRIPT_XB")

OUT1=$(run_guard "$PAYLOAD_XB" "$STATE_XB")
if blocked "$OUT1"; then
  ok "XB1: first PreCompact of the cycle refuses (dispatch state present)"
else
  bad "XB1: first PreCompact did not refuse — got: $OUT1"
fi

OUT2=$(run_guard "$PAYLOAD_XB" "$STATE_XB")
if [ -z "$OUT2" ]; then
  ok "XB2: second PreCompact in the same cycle proceeds (allows) regardless of manifest state"
else
  bad "XB2: second PreCompact was not a silent allow — got: $OUT2"
fi

OUT3=$(run_guard "$PAYLOAD_XB" "$STATE_XB")
if blocked "$OUT3"; then
  ok "XB3: one-shot state cleared after the allow — a later cycle refuses again"
else
  bad "XB3: one-shot state did not reset — third call did not refuse (would strand every future compaction into a permanent allow, or a permanent refuse if inverted)"
fi

# Independent per-session tracking: a different session_id gets its own one-shot budget.
ROOT_XB2=$(make_root xb2)
write_manifest "$ROOT_XB2" demoxb2 step_6_review in_progress
TRANSCRIPT_XB2="$TMP/sess-xb2/replay.jsonl"; mkdir -p "$(dirname "$TRANSCRIPT_XB2")"; : > "$TRANSCRIPT_XB2"
STATE_XB2="$TMP/state-xb2"
run_guard "$(pc_payload s-xb2-A "$ROOT_XB2" "$TRANSCRIPT_XB2")" "$STATE_XB2" >/dev/null
OUT_OTHER_SID=$(run_guard "$(pc_payload s-xb2-B "$ROOT_XB2" "$TRANSCRIPT_XB2")" "$STATE_XB2")
if blocked "$OUT_OTHER_SID"; then
  ok "XB4: one-shot state is keyed per session_id, not global"
else
  bad "XB4: a different session_id's first PreCompact did not get its own refusal — got: $OUT_OTHER_SID"
fi

# ===================================================================================
# XC. Fail-open on every error path (§D3).
# ===================================================================================

# No manifest anywhere under cwd.
NOROOT="$TMP/noroot"; mkdir -p "$NOROOT"
OUT_NOMANIFEST=$(run_guard "$(pc_payload s-xc1 "$NOROOT" "$TMP/xc1.jsonl")" "$TMP/state-xc1")
[ -z "$OUT_NOMANIFEST" ] && ok "XC1: no manifest found -> allow (empty output)" \
                          || bad "XC1: no manifest found but output was non-empty: $OUT_NOMANIFEST"

# Unreadable manifest.
ROOT_XC2=$(make_root xc2)
write_manifest "$ROOT_XC2" demoxc2 step_5_implementation in_progress
chmod 000 "$ROOT_XC2/docs/manifests/2026-07-26-demoxc2.manifest.yml" 2>/dev/null
OUT_UNREADABLE=$(run_guard "$(pc_payload s-xc2 "$ROOT_XC2" "$TMP/xc2.jsonl")" "$TMP/state-xc2")
chmod 644 "$ROOT_XC2/docs/manifests/2026-07-26-demoxc2.manifest.yml" 2>/dev/null
[ -z "$OUT_UNREADABLE" ] && ok "XC2: unreadable manifest -> allow (empty output)" \
                          || bad "XC2: unreadable manifest but output was non-empty: $OUT_UNREADABLE"

# jq missing.
STUBDIR="$TMP/nobin"; mkdir -p "$STUBDIR"
for b in bash cat printf mkdir grep sed awk basename dirname date mv rm mktemp env; do
  p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$STUBDIR/$(basename "$p")" 2>/dev/null
done
ROOT_XC3=$(make_root xc3)
write_manifest "$ROOT_XC3" demoxc3 step_5_implementation in_progress
OUT_NOJQ=$(printf '%s' "$(pc_payload s-xc3 "$ROOT_XC3" "$TMP/xc3.jsonl")" \
  | PATH="$STUBDIR" PRECOMPACT_GUARD_DIR="$TMP/state-xc3" bash "$GUARD" 2>/dev/null)
[ -z "$OUT_NOJQ" ] && ok "XC3: jq missing -> allow (empty output)" \
                    || bad "XC3: jq missing but output was non-empty: $OUT_NOJQ"

# Unwritable state dir (parent path component is a plain file, mkdir -p must fail).
: > "$TMP/blocked-file"
ROOT_XC4=$(make_root xc4)
write_manifest "$ROOT_XC4" demoxc4 step_5_implementation in_progress
OUT_UNWRITABLE=$(run_guard "$(pc_payload s-xc4 "$ROOT_XC4" "$TMP/xc4.jsonl")" "$TMP/blocked-file/sub")
[ -z "$OUT_UNWRITABLE" ] && ok "XC4: unwritable state dir -> allow (empty output)" \
                          || bad "XC4: unwritable state dir but output was non-empty: $OUT_UNWRITABLE"

# Malformed JSON input.
OUT_MALFORMED=$(printf 'not json' | PRECOMPACT_GUARD_DIR="$TMP/state-xc5" bash "$GUARD" 2>/dev/null)
[ -z "$OUT_MALFORMED" ] && ok "XC5: malformed JSON input -> allow (empty output)" \
                         || bad "XC5: malformed JSON but output was non-empty: $OUT_MALFORMED"

# ===================================================================================
# XD. The refusal path stays independent of occupancy reporting (§D4 originally covered occupancy
# itself too; §D3/D4/D5 — context-occupancy.sh and usage-daily-hint.sh — were retired 2026-09-12,
# ADR-0058 dated Correction. XD2 is the one assertion still meaningful post-retirement: it pins
# that the guard never reached for the occupancy script even when it existed, and (now) that it
# doesn't reach for a script that no longer exists either.
# ===================================================================================

# Bare mentions in prose (explaining why occupancy is NOT read here) are fine and expected; what
# must be absent is an actual INVOCATION of the occupancy script from within the refusal path.
if [ -f "$GUARD" ] && ! grep -qE 'context-occupancy\.sh["'"'"']?[[:space:]]*$|bash[[:space:]]+.*context-occupancy\.sh' "$GUARD"; then
  ok "XD2: precompact-guard.sh never invokes context-occupancy.sh — its refusal cannot depend on it"
else
  bad "XD2: precompact-guard.sh invokes context-occupancy.sh — the refusal path must stay independent of the occupancy figure"
fi

# Same distinction: a comment explaining the threshold is not read is fine; an actual shell
# expansion of the variable (an ACTUAL read) is what must be absent.
for f in "$GUARD"; do
  if [ -f "$f" ] && ! grep -qE '\$\{?CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' "$f"; then
    ok "XD3: $(basename "$f") does not read the compaction threshold env var"
  else
    bad "XD3: $(basename "$f") reads CLAUDE_AUTOCOMPACT_PCT_OVERRIDE as a variable, or does not exist yet"
  fi
done

# ===================================================================================
# XG. Registration — PAIRS entries + a conditional MANUAL-STEP notice. sync-manual-steps.test.sh's
# all-clear fixture enumerates every wired hook, so this notice is a CONTRACT CHANGE to that
# existing test file, not just an addition (this caught ADR-0049 too).
# ===================================================================================
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" > "$TMP/pairs" 2>/dev/null

if grep -qxF 'plugin/scripts/precompact-guard.sh|hooks/precompact-guard.sh' "$TMP/pairs" 2>/dev/null; then
  ok "XG1: PAIRS deploys precompact-guard.sh to ~/.claude/hooks/"
else
  bad "XG1: precompact-guard.sh PAIRS entry is missing"
fi

if grep -F 'chmod +x' "$SYNCSH" 2>/dev/null | grep -qF 'precompact-guard.sh'; then
  ok "XG3: the executable-bit preservation block includes precompact-guard.sh on the physical chmod +x line"
else
  bad "XG3: precompact-guard.sh is not on the physical 'chmod +x' line — a backslash-continuation line does not count (#108's trap)"
fi

if grep -q 'precompact-guard' "$SYNCSH" 2>/dev/null && grep -q 'PreCompact' "$SYNCSH" 2>/dev/null; then
  ok "XG4: sync-to-claude.sh carries a MANUAL-STEP notice naming precompact-guard and the PreCompact event key"
else
  bad "XG4: sync-to-claude.sh has no MANUAL-STEP notice for precompact-guard/PreCompact"
fi

if grep -q 'precompact-guard' "$SETTINGSJSON" 2>/dev/null && grep -q 'PreCompact' "$SETTINGSJSON" 2>/dev/null; then
  ok "XG5: staging/user/settings.json carries a PreCompact reference entry for precompact-guard.sh"
else
  bad "XG5: staging/user/settings.json has no PreCompact hook entry"
fi

if grep -qi 'precompact-guard' "$SYNC_MANUAL_TEST" 2>/dev/null; then
  ok "XG6: sync-manual-steps.test.sh was updated with the new notice's contract (not just sync-to-claude.sh)"
else
  bad "XG6: sync-manual-steps.test.sh makes no mention of precompact-guard — its all-clear fixture is now wrong"
fi

# Dynamic check: a fixture settings.json missing PreCompact wiring must trigger the notice; one
# that has it must suppress it. Hermetic HOME override, dry-run only (no --apply).
HOME_NO="$TMP/home-no"; mkdir -p "$HOME_NO/.claude/hooks"
printf '{"hooks":{"PreToolUse":[{"matcher":"Edit|Write","hooks":[{"type":"command","command":"protect-files.sh"}]}]}}\n' \
  > "$HOME_NO/.claude/settings.json"
OUT_SYNC_NO=$(HOME="$HOME_NO" bash "$SYNCSH" 2>&1)
if printf '%s' "$OUT_SYNC_NO" | grep -q 'precompact-guard'; then
  ok "XG7: sync-to-claude.sh dry-run prints the precompact-guard notice when PreCompact is not wired"
else
  bad "XG7: sync-to-claude.sh dry-run did not print a precompact-guard notice for an unwired settings.json"
fi

HOME_YES="$TMP/home-yes"; mkdir -p "$HOME_YES/.claude/hooks"
printf '{"hooks":{"PreCompact":[{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/precompact-guard.sh"}]}]}}\n' \
  > "$HOME_YES/.claude/settings.json"
OUT_SYNC_YES=$(HOME="$HOME_YES" bash "$SYNCSH" 2>&1)
if ! printf '%s' "$OUT_SYNC_YES" | grep -q 'MANUAL STEP: hook wiring.*\n.*precompact-guard\|precompact-guard.*MANUAL'; then
  # simpler: the notice body itself should not appear when already wired
  if ! printf '%s' "$OUT_SYNC_YES" | grep -A3 'MANUAL STEP' | grep -q 'precompact-guard.sh" } ]'; then
    ok "XG8: sync-to-claude.sh dry-run suppresses the precompact-guard notice once PreCompact is wired"
  else
    bad "XG8: notice still printed although PreCompact is already wired"
  fi
else
  bad "XG8: notice still printed although PreCompact is already wired"
fi

# ===================================================================================
# XH. Registration in both CI registries.
# ===================================================================================
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]precompact-occupancy[[:space:];]'; then
  ok "XH1: docs-ci.yml's shell-tests loop list runs precompact-occupancy"
else
  bad "XH1: precompact-occupancy is not in docs-ci.yml's explicit harness list — append it after tracer-bullet-probe"
fi

if printf '%s' "$DOCSCI_LOOP" | grep -qE 'tracer-bullet-probe[[:space:]]+precompact-occupancy'; then
  ok "XH1b: precompact-occupancy is placed immediately after tracer-bullet-probe in the docs-ci.yml list"
else
  bad "XH1b: precompact-occupancy is not positioned right after tracer-bullet-probe in docs-ci.yml's list"
fi

# XH2 removed (ADR-0193): ci.yml, the second registry this pinned, was deleted — docs-ci.yml's
# shell-tests list above (XH1/XH1b) is now the only harness runner, and pairs-completeness.test.sh's
# CI3 asserts exactly one workflow executes the suite.

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
