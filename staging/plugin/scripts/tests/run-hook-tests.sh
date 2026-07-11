#!/bin/bash
# Hook unit test harness. Isolated state dir; never touches real state.
set -u
HOOKS="$HOME/.claude/hooks"
TMP="$(mktemp -d)"
export STOP_GATE_STATE_DIR="$TMP/state"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS: $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# --- Task 1: ensure-state-dir.sh ---
rm -rf "$STOP_GATE_STATE_DIR"
echo '{"session_id":"s1","hook_event_name":"SessionStart"}' | bash "$HOOKS/ensure-state-dir.sh" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && [ -d "$STOP_GATE_STATE_DIR" ] && ok "ensure-state-dir creates dir, exit 0" || bad "ensure-state-dir"

# --- Task 2: mark-dirty.sh ---
mkdir -p "$STOP_GATE_STATE_DIR"
echo '{"session_id":"s2","tool_name":"Write","tool_input":{"file_path":"/x/a.py"}}' | bash "$HOOKS/mark-dirty.sh" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && [ -f "$STOP_GATE_STATE_DIR/s2.dirty" ] && ok "mark-dirty creates <sid>.dirty" || bad "mark-dirty creates dirty"
# fail-open: no session_id → exit 0, no file
echo '{"tool_name":"Edit"}' | bash "$HOOKS/mark-dirty.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "mark-dirty fail-open without session_id" || bad "mark-dirty fail-open"

# --- Task 3: reset-gate-counter.sh ---
mkdir -p "$STOP_GATE_STATE_DIR"; echo 2 > "$STOP_GATE_STATE_DIR/s3.count"
echo '{"session_id":"s3","hook_event_name":"UserPromptSubmit","prompt":"hi"}' | bash "$HOOKS/reset-gate-counter.sh" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && [ ! -f "$STOP_GATE_STATE_DIR/s3.count" ] && ok "reset-gate-counter deletes count" || bad "reset-gate-counter"

# --- Task 4: stop-gate.sh (Phase A) ---
mkdir -p "$STOP_GATE_STATE_DIR"

# 4a: no dirty → allow stop (exit 0, no stdout)
rm -f "$STOP_GATE_STATE_DIR/s4.dirty" "$STOP_GATE_STATE_DIR/s4.count"
OUT=$(echo '{"session_id":"s4","hook_event_name":"Stop"}' | bash "$HOOKS/stop-gate.sh" 2>/dev/null); rc=$?
[ $rc -eq 0 ] && [ -z "$OUT" ] && ok "stop-gate: no dirty → allow" || bad "stop-gate no dirty"

# 4b: dirty + counter 0 → block + counter becomes 1
: > "$STOP_GATE_STATE_DIR/s4.dirty"
OUT=$(echo '{"session_id":"s4","hook_event_name":"Stop","cwd":"/tmp"}' | bash "$HOOKS/stop-gate.sh" 2>/dev/null)
echo "$OUT" | grep -q '"decision":"block"' && [ "$(cat "$STOP_GATE_STATE_DIR/s4.count")" = "1" ] \
  && ok "stop-gate: dirty → block + counter=1" || bad "stop-gate dirty block"

# 4c: counter at N (=3) → allow + warning on stderr, no block json
echo 3 > "$STOP_GATE_STATE_DIR/s4.count"
ERR=$(echo '{"session_id":"s4","hook_event_name":"Stop","cwd":"/tmp"}' | bash "$HOOKS/stop-gate.sh" 2>&1 1>/dev/null); rc=$?
OUT=$(echo '{"session_id":"s4","hook_event_name":"Stop","cwd":"/tmp"}' | bash "$HOOKS/stop-gate.sh" 2>/dev/null)
[ $rc -eq 0 ] && echo "$ERR" | grep -qi "anti-loop" && ! echo "$OUT" | grep -q '"decision":"block"' \
  && ok "stop-gate: counter>=N → allow + warn" || bad "stop-gate anti-loop cap"

# 4d: fail-open, no session_id → allow
OUT=$(echo '{"hook_event_name":"Stop"}' | bash "$HOOKS/stop-gate.sh" 2>/dev/null); rc=$?
[ $rc -eq 0 ] && [ -z "$OUT" ] && ok "stop-gate: no session_id → fail-open allow" || bad "stop-gate fail-open"

# --- Task 5: clear-dirty-on-test.sh (RETIRED — superseded by testcmd authoritative tier, swarm-testcmd Task 8) ---
ok "clear-dirty retired (testcmd design)"

# --- Task 7: backup-before-deploy.sh ---
BK="$TMP/backups/2026-05-19-swarm-fase-A"
mkdir -p "$TMP/fakehome/.claude/agents"
echo '{"hooks":{}}' > "$TMP/fakehome/.claude/settings.json"
echo "desc" > "$TMP/fakehome/.claude/agents/tester.md"
BACKUP_SRC_HOME="$TMP/fakehome" BACKUP_DEST="$BK" bash "$HOOKS/backup-before-deploy.sh" >/dev/null 2>&1
rc=$?
[ $rc -eq 0 ] && [ -f "$BK/settings.json" ] && [ -f "$BK/agents/tester.md" ] && [ -f "$BK/MANIFEST.md" ] \
  && grep -q "settings.json" "$BK/MANIFEST.md" && ok "backup: copies files + MANIFEST" || bad "backup infra"

# --- testcmd Task 1: retired (v2.sh deleted, path-case fix 2026-05-20) ---
ok "testcmd Task 1 retired (v2.sh deleted, v3 supersedes)"
# --- testcmd Task 2: retired (v2.sh deleted, path-case fix 2026-05-20) ---
ok "testcmd Task 2 retired (v2.sh deleted, v3 supersedes)"
# --- testcmd Task 3: retired (v2.sh deleted, path-case fix 2026-05-20) ---
ok "testcmd Task 3 retired (v2.sh deleted, v3 supersedes)"
# --- testcmd Task 4: retired (v2.sh deleted, path-case fix 2026-05-20) ---
ok "testcmd Task 4 retired (v2.sh deleted, v3 supersedes)"
# --- testcmd Task 5: retired (v2.sh deleted, path-case fix 2026-05-20) ---
ok "testcmd Task 5 retired (v2.sh deleted, v3 supersedes)"
# --- testcmd Task 6: approve-test-cmd.sh ---
export STOP_GATE_TRUST_FILE="$TMP/trust6"; rm -f "$STOP_GATE_TRUST_FILE"
PC="$TMP/proj_apr/.claude"; mkdir -p "$PC"; printf 'pytest -q\n' > "$PC/test-cmd"
bash "$HOOKS/approve-test-cmd.sh" "$TMP/proj_apr" >/dev/null 2>&1; r=$?
HC=$( (command -v shasum >/dev/null && shasum -a 256 "$PC/test-cmd" | awk '{print $1}') || sha256sum "$PC/test-cmd" | awk '{print $1}')
# Compute expected normalized path using the same norm_path algorithm as the
# v3 hooks (pwd -P + lowercase on Darwin); approve-test-cmd.sh post-2026-05-20
# stores canonical paths, so the trust line uses the canonical form, not the
# literal $TMP/proj_apr (which may contain uppercase /T/ on macOS tmpdir).
EXP=$(cd "$TMP/proj_apr" && pwd -P)
[ "$(uname)" = "Darwin" ] && EXP=$(printf '%s' "$EXP" | tr '[:upper:]' '[:lower:]')
[ $r -eq 0 ] && grep -F -x -q -- "$(printf '%s\t%s' "$HC" "$EXP")" "$STOP_GATE_TRUST_FILE" \
  && ok "approve: writes trust entry" || bad "approve writes"
# idempotent: second call → still one line
bash "$HOOKS/approve-test-cmd.sh" "$TMP/proj_apr" >/dev/null 2>&1
[ "$(grep -c . "$STOP_GATE_TRUST_FILE")" = "1" ] && ok "approve: idempotent" || bad "approve idempotent"
# subdir arg uses upward search
mkdir -p "$TMP/proj_apr/sub/deep"
bash "$HOOKS/approve-test-cmd.sh" "$TMP/proj_apr/sub/deep" >/dev/null 2>&1
[ "$(grep -c . "$STOP_GATE_TRUST_FILE")" = "1" ] && ok "approve: subdir upward search" || bad "approve subdir"

# --- testcmd Task 7: retired (v2.sh deleted, path-case fix 2026-05-20) ---
ok "testcmd Task 7 retired (v2.sh deleted, v3 supersedes)"
# --- testcmd Task 8: retired (v2.sh deleted, path-case fix 2026-05-20) ---
ok "testcmd Task 8 retired (v2.sh deleted, v3 supersedes)"
# --- path-case A1: v3 case-variant lookup + trust migration ---
# These vars point to .v3 staging until Task 5 (MIGRATION) swaps in live .sh.
V3_SG="$HOOKS/stop-gate.sh"
V3_AT="$HOOKS/approve-test-cmd.sh"
MIG="$HOOKS/migrate-trust-paths.sh"

# 1a: case-variant trust lookup → match on Darwin
# Approve via lowercase path, lookup gate via uppercase path → must match.
mkdir -p "$STOP_GATE_STATE_DIR"
export STOP_GATE_TRUST_FILE="$TMP/trust_a1"; : > "$STOP_GATE_TRUST_FILE"
PCV="$TMP/proj_case/.claude"; mkdir -p "$PCV"; printf 'true\n' > "$PCV/test-cmd"
# Note: macOS case-insensitive FS lets both paths resolve to same dir.
bash "$V3_AT" "$TMP/proj_case" >/dev/null 2>&1
: > "$STOP_GATE_STATE_DIR/v3cv.dirty"
# Pass capital-C version of /proj_case (= /Proj_Case). On Darwin: should match.
PCV_UP=$(printf '%s' "$TMP/proj_case" | sed 's/proj_case$/Proj_Case/')
O=$(echo "{\"session_id\":\"v3cv\",\"cwd\":\"$PCV_UP\"}" | bash "$V3_SG" 2>/dev/null); r=$?
[ $r -eq 0 ] && [ -z "$O" ] && ok "v3: case-variant lookup → trust match" || bad "v3 case-variant"

# 1b: migration dedup case-variant duplicates → 1 entry, lowercase
export STOP_GATE_TRUST_FILE="$TMP/trust_a2"
PMD="$TMP/proj_mig/.claude"; mkdir -p "$PMD"; printf 'true\n' > "$PMD/test-cmd"
HMD=$( (command -v shasum >/dev/null && shasum -a 256 "$PMD/test-cmd" | awk '{print $1}') || sha256sum "$PMD/test-cmd" | awk '{print $1}')
PMD_UP=$(printf '%s' "$TMP/proj_mig" | sed 's/proj_mig$/Proj_Mig/')
# Seed trust with 3 case-variant duplicates of same project (same sha)
printf '%s\t%s\n%s\t%s\n%s\t%s\n' \
  "$HMD" "$TMP/proj_mig" \
  "$HMD" "$PMD_UP" \
  "$HMD" "$TMP/PROJ_MIG" > "$STOP_GATE_TRUST_FILE"
bash "$MIG" >/dev/null 2>&1
N=$(grep -c . "$STOP_GATE_TRUST_FILE")
# Canonical-agnostic assertion: the single remaining line's path field
# (column 2) must contain no uppercase letters. This works regardless of
# whether $TMP contains uppercase (macOS /var/folders/.../T/...) or whether
# norm_path resolved symlinks (/var → /private/var), since both produce
# all-lowercase paths after norm_path's tr on Darwin.
LOWER_OK=$(awk -F'\t' '{print $2}' "$STOP_GATE_TRUST_FILE" | grep -vE '[A-Z]' | wc -l | tr -d ' ')
[ "$N" = "1" ] && [ "$LOWER_OK" = "1" ] && ok "v3 migrate: dedup case-variant → 1 lowercase entry" || bad "v3 migrate dedup"

# 1c: migration idempotency → second run is byte-identical
# CRITICAL: also require migrate exit 0, else missing $MIG gives vacuous PASS
# (no-op migrate → unchanged file → cmp matches the pre-copy trivially).
cp "$STOP_GATE_TRUST_FILE" "$TMP/trust_pre"
bash "$MIG" >/dev/null 2>&1; mig_rc_c=$?
[ "$mig_rc_c" -eq 0 ] && cmp -s "$TMP/trust_pre" "$STOP_GATE_TRUST_FILE" \
  && ok "v3 migrate: idempotent" || bad "v3 migrate idempotent"

# 1d: STOP_GATE_UNAME=Linux → migrate's no-cd branch preserves case
# CRITICAL: must use a NON-EXISTENT path. On macOS case-insensitive FS, any
# uppercase path that shadows a lowercase real dir would go through norm_path's
# cd && pwd -P which returns FS-canonical case (lowercase) REGARDLESS of the
# platform check — masking the env override's effect. Forcing the non-existent
# branch isolates the platform-detection logic from pwd -P's case canonicalization.
export STOP_GATE_TRUST_FILE="$TMP/trust_a4"
printf 'deadbeefcafefeedfacedeadbeefcafefeedfacedeadbeefcafefeedface\t/never/exists/Proj_Linux\n' \
  > "$STOP_GATE_TRUST_FILE"
STOP_GATE_UNAME=Linux bash "$MIG" >/dev/null 2>&1; mig_rc_d=$?
[ "$mig_rc_d" -eq 0 ] && grep -F "Proj_Linux" "$STOP_GATE_TRUST_FILE" >/dev/null \
  && ok "v3 migrate: non-Darwin preserves case" || bad "v3 migrate non-darwin"

unset STOP_GATE_TRUST_FILE STOP_GATE_UNAME

echo "----"; echo "PASS=$PASS FAIL=$FAIL"; rm -rf "$TMP"
[ $FAIL -eq 0 ]
