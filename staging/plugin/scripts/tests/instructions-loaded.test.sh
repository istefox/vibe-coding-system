#!/bin/bash
# instructions-loaded test harness (ADR-0171) — offline, hermetic, no live claude session.
# Bash 3.2 clean. Run: bash instructions-loaded.test.sh
#
# Tests the WRITER (instructions-loaded-log.sh), the shared canon helper, and the VERIFIER
# (instructions-loaded-verify.sh). A green run says the mechanism records and reads what it is
# given correctly; it says nothing about whether the InstructionsLoaded event actually fires
# inside a live Claude Code session — that is a live smoke test, run separately (ADR-0171).
#
# Reduced set vs. the full design review (13 plants, 9 states, a liveness heartbeat): this file
# covers the core mechanism, not every enumerated state. The cut is declared here, not implicit.
#
# plant: IL1 | plugin/scripts/instructions-loaded-verify.sh | .file_path_canon == $p | (.file_path_canon|contains($p))
# plant: IL2 | plugin/scripts/instructions-loaded-canon.sh  | _rd=$(cd "$_d" 2>/dev/null && pwd -P) || return 1 | _rd="$_d"
# plant: IL3 | plugin/scripts/instructions-loaded-log.sh    | printf '%s\n' "${_oldest:-unknown}" > "$DIR/trim-watermark" 2>/dev/null | printf '%s\n' "${_oldest:-unknown}" > "$DIR/trim-watermark-DISABLED" 2>/dev/null
# plant: IL4 | user/settings.json | "command": "\"$HOME\"/.claude/hooks/instructions-loaded-log.sh" | "command": "\"$HOME\"/.claude/hooks/instructions-loaded-log-DISABLED.sh"

set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
LOG_SCRIPT="$SCRIPTS/instructions-loaded-log.sh"
VERIFY_SCRIPT="$SCRIPTS/instructions-loaded-verify.sh"

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

if ! command -v jq >/dev/null 2>&1; then
  printf 'SKIP instructions-loaded tests: jq not available\n'
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# fire <dir> <target-file> <session_id> [load_reason]
fire() {
  _dir="$1"; _target="$2"; _sid="$3"; _reason="${4:-session_start}"
  printf '{"session_id":"%s","hook_event_name":"InstructionsLoaded","load_reason":"%s","file_path":"%s","cwd":"%s"}' \
    "$_sid" "$_reason" "$_target" "$_dir" \
    | INSTRUCTIONS_LOADED_DIR="$_dir" bash "$LOG_SCRIPT"
}

# --- IL-A: writer records a valid payload with all expected fields ---------------------------------
D1="$tmp/a/state"; mkdir -p "$D1"
T1="$tmp/a/tools.md"; printf 'content\n' > "$T1"
fire "$D1" "$T1" "s1"
LOG1="$D1/events.jsonl"
REC=$(jq -c 'select(.record=="instructions_loaded")' "$LOG1" 2>/dev/null | tail -1)
[ -n "$REC" ] && ok "writer: valid payload produces a parsed instructions_loaded record" \
              || bad "writer: valid payload produces a parsed instructions_loaded record"
echo "$REC" | jq -e '.session_id=="s1" and .load_reason=="session_start" and .file_path_canon != null and .file_mtime != null and .file_size != null and .file_sha256 != null' >/dev/null 2>&1 \
  && ok "writer: record carries session_id/load_reason/canon/mtime/size/sha256" \
  || bad "writer: record carries session_id/load_reason/canon/mtime/size/sha256"

# --- IL-B: no jq available => raw fallback record, never an empty log ------------------------------
D2="$tmp/b/state"; mkdir -p "$D2"
T2="$tmp/b/tools.md"; printf 'content\n' > "$T2"
FAKEBIN="$tmp/fakebin"; mkdir -p "$FAKEBIN"
printf '{"session_id":"s2","hook_event_name":"InstructionsLoaded","load_reason":"session_start","file_path":"'"$T2"'","cwd":"'"$tmp/b"'"}' \
  | PATH="/usr/bin:/bin" INSTRUCTIONS_LOADED_DIR="$D2" bash "$LOG_SCRIPT" >/dev/null 2>&1
if command -v /usr/bin/jq >/dev/null 2>&1 || command -v /bin/jq >/dev/null 2>&1; then
  ok "writer: no-jq path skipped (jq present in /usr/bin or /bin on this host)"
else
  grep -q '"record":"raw"' "$D2/events.jsonl" 2>/dev/null && grep -q 'payload_b64' "$D2/events.jsonl" 2>/dev/null \
    && ok "writer: degrades to raw record with payload_b64 when jq is unavailable" \
    || bad "writer: degrades to raw record with payload_b64 when jq is unavailable"
fi

# --- IL-C: malformed / empty stdin still writes a record, never a silent no-op ----------------------
D3="$tmp/c/state"; mkdir -p "$D3"
printf '' | INSTRUCTIONS_LOADED_DIR="$D3" bash "$LOG_SCRIPT" >/dev/null 2>&1
grep -q '"reason":"empty-stdin"' "$D3/events.jsonl" 2>/dev/null \
  && ok "writer: empty stdin recorded as raw/empty-stdin, not silently dropped" \
  || bad "writer: empty stdin recorded as raw/empty-stdin, not silently dropped"

# --- IL-D: verify a file never observed loading => LOADED=false, exit 0 (not an error) --------------
D4="$tmp/d/state"; mkdir -p "$D4"
T4="$tmp/d/tools.md"; printf 'content\n' > "$T4"
NEVER="$tmp/d/never-seen.md"; printf 'x\n' > "$NEVER"
fire "$D4" "$T4" "s4"
OUT=$(INSTRUCTIONS_LOADED_DIR="$D4" bash "$VERIFY_SCRIPT" "$NEVER" 2>&1); RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'LOADED=false' \
  && ok "verify: file never observed loading => LOADED=false, exit 0" \
  || bad "verify: file never observed loading => LOADED=false, exit 0"

# IL1 plant target: exact-match, not substring. A record for a LONGER path must not satisfy a
# query for a path that is merely contained in it (repo rule 18).
LONGER="$tmp/d/tools-extended.md"; printf 'y\n' > "$LONGER"
fire "$D4" "$LONGER" "s4b"
# no target file at $tmp/d/tools -- pass --since explicitly, since the default anchor needs the
# target to exist on disk (a separate, already-covered BADARG state).
OUT=$(INSTRUCTIONS_LOADED_DIR="$D4" bash "$VERIFY_SCRIPT" "$tmp/d/tools" --since 2000-01-01T00:00:00Z 2>&1); RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'LOADED=false' \
  && ok "IL1: a substring path is not satisfied by a longer sibling's record (rule 18)" \
  || bad "IL1: a substring path is not satisfied by a longer sibling's record (rule 18)"

# --- IL-E: log absent => exit 3 INCONCLUSIVE reason=log-absent --------------------------------------
D5="$tmp/e/state"
T5="$tmp/e-target.md"; mkdir -p "$tmp/e"; printf 'x\n' > "$T5"
OUT=$(INSTRUCTIONS_LOADED_DIR="$D5" bash "$VERIFY_SCRIPT" "$T5" 2>&1); RC=$?
[ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'reason=log-absent' \
  && ok "verify: log absent => exit 3, reason=log-absent" \
  || bad "verify: log absent => exit 3, reason=log-absent"

# --- IL-F: records exist but none inside the anchor window => reason=empty-window, exit 3 -----------
D6="$tmp/f/state"; mkdir -p "$D6"
T6="$tmp/f/tools.md"; printf 'old\n' > "$T6"
touch -t 202001010000 "$T6"
fire "$D6" "$T6" "s6"
sleep 1
printf 'new\n' > "$T6"   # bump mtime forward, strictly past the only recorded load's ts
OUT=$(INSTRUCTIONS_LOADED_DIR="$D6" bash "$VERIFY_SCRIPT" "$T6" 2>&1); RC=$?
[ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'reason=empty-window' \
  && ok "verify: no session in the anchor window => reason=empty-window, exit 3 (not a false LOADED=false)" \
  || bad "verify: no session in the anchor window => reason=empty-window, exit 3 (not a false LOADED=false)"

# --- IL-G: a match older than the file's current version => LOADED=stale, not true ------------------
D7="$tmp/g/state"; mkdir -p "$D7"
T7="$tmp/g/tools.md"; printf 'old\n' > "$T7"
touch -t 202001010000 "$T7"
OLDM=$(stat -f %m "$T7" 2>/dev/null || stat -c %Y "$T7" 2>/dev/null)
fire "$D7" "$T7" "s7"
sleep 1
printf 'new\n' > "$T7"
SINCE_ISO=$(date -u -r "$OLDM" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$OLDM" +%Y-%m-%dT%H:%M:%SZ)
OUT=$(INSTRUCTIONS_LOADED_DIR="$D7" bash "$VERIFY_SCRIPT" "$T7" --since "$SINCE_ISO" 2>&1); RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'LOADED=stale' \
  && ok "verify: a match older than the current file version => LOADED=stale" \
  || bad "verify: a match older than the current file version => LOADED=stale"

# --- IL-H (IL3 plant target): forced trim shortens the log and leaves a watermark receipt -----------
D8="$tmp/h/state"; mkdir -p "$D8"
T8="$tmp/h/tools.md"; printf 'x\n' > "$T8"
export INSTRUCTIONS_LOADED_HIGH_WATER=1 INSTRUCTIONS_LOADED_CAP=3
i=1
while [ "$i" -le 8 ]; do
  fire "$D8" "$T8" "s$i" >/dev/null 2>&1
  i=$((i+1))
done
unset INSTRUCTIONS_LOADED_HIGH_WATER INSTRUCTIONS_LOADED_CAP
LINES=$(wc -l < "$D8/events.jsonl" 2>/dev/null | tr -d ' ')
[ -n "$LINES" ] && [ "$LINES" -le 3 ] \
  && ok "writer: trim caps the log at INSTRUCTIONS_LOADED_CAP" \
  || bad "writer: trim caps the log at INSTRUCTIONS_LOADED_CAP (got $LINES lines)"
[ -s "$D8/trim-watermark" ] \
  && ok "IL3: trim leaves a trim-watermark receipt" \
  || bad "IL3: trim leaves a trim-watermark receipt"

# --- IL-I: an anchor older than the trim watermark => reason=truncated, exit 3 -----------------------
D9="$tmp/i/state"; mkdir -p "$D9"
T9="$tmp/i/tools.md"; printf 'x\n' > "$T9"
date -u +%Y-%m-%dT%H:%M:%SZ > "$D9/trim-watermark"
fire "$D9" "$T9" "s9"
OUT=$(INSTRUCTIONS_LOADED_DIR="$D9" bash "$VERIFY_SCRIPT" "$T9" --since 2020-01-01T00:00:00Z 2>&1); RC=$?
[ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q 'reason=truncated' \
  && ok "verify: anchor predating the trim watermark => reason=truncated, exit 3" \
  || bad "verify: anchor predating the trim watermark => reason=truncated, exit 3"

# --- IL-J: bad --since argument => exit 2 BADARG, never silently ignored -----------------------------
D10="$tmp/j/state"; mkdir -p "$D10"
T10="$tmp/j/tools.md"; printf 'x\n' > "$T10"
INSTRUCTIONS_LOADED_DIR="$D10" bash "$VERIFY_SCRIPT" "$T10" --since not-a-date >/dev/null 2>&1
[ $? -eq 2 ] && ok "verify: malformed --since => exit 2 BADARG" || bad "verify: malformed --since => exit 2 BADARG"

# --- IL2 plant target: canon helper actually resolves the directory chain, not a no-op --------------
D11="$tmp/k/state"; mkdir -p "$D11"
mkdir -p "$tmp/k/sub"
T11="$tmp/k/sub/../sub/tools.md"; printf 'x\n' > "$tmp/k/sub/tools.md"
fire "$D11" "$T11" "s11"
OUT=$(INSTRUCTIONS_LOADED_DIR="$D11" bash "$VERIFY_SCRIPT" "$tmp/k/sub/tools.md" 2>&1); RC=$?
[ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q 'LOADED=true' \
  && ok "IL2: a non-normalised path (../) still matches the canonicalised record" \
  || bad "IL2: a non-normalised path (../) still matches the canonicalised record"

# --- IL4 plant target: the InstructionsLoaded hook is actually registered in staging settings ------
STAGING_SETTINGS="$SCRIPTS/../../user/settings.json"
if [ -r "$STAGING_SETTINGS" ]; then
  grep -q '"command": "\\"\$HOME\\"/.claude/hooks/instructions-loaded-log.sh"' "$STAGING_SETTINGS" \
    && ok "IL4: InstructionsLoaded hook wired in staging/user/settings.json" \
    || bad "IL4: InstructionsLoaded hook wired in staging/user/settings.json"
else
  bad "IL4: InstructionsLoaded hook wired in staging/user/settings.json (settings.json unreadable at $STAGING_SETTINGS)"
fi

# --- Z1: assertion-count floor (ADR-0083 §D3). A floor, not equality: catches an assertion that -----
# vanishes without failing, per repo rule 10. This assertion carries no plant of its own — a plant
# on a floor is absorbed by slack in the ">=" comparison (rule 10 itself).
_total=$((PASS+FAIL))
if [ "$_total" -ge 15 ]; then ok "Z1: assertion-count floor ($_total >= 15)"
else bad "Z1: assertion count fell to $_total (floor 15) -- assertions vanished from this file"; fi

# --- summary ------------------------------------------------------------------------------------------
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
