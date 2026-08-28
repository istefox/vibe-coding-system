#!/bin/bash
# instructions-loaded-log.sh v1.0 — observational hook, InstructionsLoaded event (ADR-0171).
#
# Purpose: give a later, measured answer to "did this instruction file actually load into a
# session's context", instead of trusting Claude Code's documented behaviour on faith. Records
# ONE JSONL line per file load. Decides nothing, never blocks — the event's own exit code is
# already ignored by Claude Code, so this hook has no decision to make even in principle.
#
# The record carries file_mtime/file_size/file_sha256 of the TARGET FILE at hook time, not just
# its path. A record keyed on path alone can never come back false: a load that happened BEFORE a
# correction was written still satisfies a query for the same path forever, which would make the
# whole verification feature structurally incapable of saying "no" (design review finding C1,
# 2026-08-27). The hash/mtime let instructions-loaded-verify.sh tell "loaded, current version"
# apart from "loaded, but a stale one" apart from "never observed".
#
# Fail-open by construction, same posture as hook-probe.sh (the closest template): a malfunctioning
# probe must never break a session, so every path ends in exit 0.
#
# Log location: $INSTRUCTIONS_LOADED_DIR (state-dir convention shared by 15+ hooks in this repo,
# e.g. precompact-guard.sh, commit-outcome-backstop.sh) or $HOME/.claude/state/instructions-loaded.
#
# Volume: this event fires once per instruction file per session_start, again on lazy loads
# (nested_traversal/path_glob_match/include), and again in full on every compact. The rate is NOT
# measured (the hook did not exist to measure it before this commit) — ADR-0171 states that
# openly and the cap below is sized to survive a wide margin of error, not tuned to a number.
# Trimming is amortised behind an O(1) size probe rather than run per event, because this event
# arrives in a BURST at session start and tail -n $CAP is O(file) — trimming per event would put
# many multi-MB rewrites into the session-startup path to manage a file that needs trimming on
# the order of once a month.
#
# Bash 3.2 clean: no associative arrays, no mapfile, no process substitution.
#
# transcript-scan-exempt: writes its own observational log; does not read a CC transcript.

set -u
trap 'exit 0' EXIT

SELF_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 0
# shellcheck source=instructions-loaded-canon.sh
. "$SELF_DIR/instructions-loaded-canon.sh" 2>/dev/null || exit 0

DIR="${INSTRUCTIONS_LOADED_DIR:-$HOME/.claude/state/instructions-loaded}"
LOG="$DIR/events.jsonl"
CAP="${INSTRUCTIONS_LOADED_CAP:-20000}"
HIGH_WATER="${INSTRUCTIONS_LOADED_HIGH_WATER:-12582912}"

mkdir -p "$DIR" 2>/dev/null || exit 0

PAYLOAD=$(cat 2>/dev/null) || PAYLOAD=""

have_jq=0
command -v jq >/dev/null 2>&1 && have_jq=1

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TS="unknown"

# Without jq we cannot parse, but we must still record: an empty log is indistinguishable from
# "the hook never fired", which is the single most dangerous misreading of this log (rule 4 —
# DID-NOT-RUN must not collapse into FOUND-NOTHING).
if [ "$have_jq" -eq 0 ] || [ -z "$PAYLOAD" ]; then
  B64=$(printf '%s' "$PAYLOAD" | base64 2>/dev/null | tr -d '\n') || B64=""
  printf '{"record":"raw","ts":"%s","reason":"%s","payload_b64":"%s"}\n' \
    "$TS" \
    "$([ "$have_jq" -eq 0 ] && printf 'no-jq' || printf 'empty-stdin')" \
    "$B64" >> "$LOG" 2>/dev/null
  exit 0
fi

FILE_PATH=$(printf '%s' "$PAYLOAD" | jq -r '.file_path // empty' 2>/dev/null)
LOAD_REASON=$(printf '%s' "$PAYLOAD" | jq -r '.load_reason // empty' 2>/dev/null)
SESSION_ID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null)

CANON=""
[ -n "$FILE_PATH" ] && CANON=$(_il_canon "$FILE_PATH") 2>/dev/null

MTIME=""
SIZE=""
SHA=""
if [ -n "$FILE_PATH" ] && [ -r "$FILE_PATH" ]; then
  MTIME=$(_fmtime "$FILE_PATH")
  SIZE=$(_fsize "$FILE_PATH")
  SHA=$(_fsha "$FILE_PATH")
fi

printf '%s' "$PAYLOAD" | jq -c \
  --arg ts "$TS" \
  --arg fpcanon "$CANON" \
  --argjson mtime "${MTIME:-null}" \
  --argjson size "${SIZE:-null}" \
  --arg sha "$SHA" \
  '{
     record: "instructions_loaded",
     ts: $ts,
     session_id: (.session_id // null),
     load_reason: (.load_reason // null),
     file_path: (.file_path // null),
     file_path_canon: (if $fpcanon == "" then null else $fpcanon end),
     file_mtime: $mtime,
     file_size: $size,
     file_sha256: (if $sha == "" then null else $sha end),
     cwd: (.cwd // null)
   }' >> "$LOG" 2>/dev/null

# --- amortised trim, with a receipt for what it destroys ---------------------------------------
# The trim DESTROYS EVIDENCE, so it leaves a watermark. Without it, a query whose answer was
# trimmed away is indistinguishable from a file that was never loaded, and the verifier would
# report a hard false negative for a correction that did load (rule 4 again, at the read side).
SZ=$(_fsize "$LOG"); SZ=${SZ:-0}
if [ "$SZ" -gt "$HIGH_WATER" ]; then
  # A lock leaked by a process killed mid-trim would stop trimming forever and silently, so a
  # stale one is reclaimed after a generous margin over any observed trim duration.
  find "$DIR/.trim.lock" -maxdepth 0 -mmin +1 -exec rmdir {} \; 2>/dev/null
  if mkdir "$DIR/.trim.lock" 2>/dev/null; then
    _tmp="$LOG.trim.$$"
    if tail -n "$CAP" "$LOG" > "$_tmp" 2>/dev/null && [ -s "$_tmp" ]; then
      _oldest=$(head -1 "$_tmp" | jq -r '.ts // empty' 2>/dev/null)
      if mv -f "$_tmp" "$LOG" 2>/dev/null; then
        printf '%s\n' "${_oldest:-unknown}" > "$DIR/trim-watermark" 2>/dev/null
      fi
    fi
    rm -f "$_tmp" 2>/dev/null
    rmdir "$DIR/.trim.lock" 2>/dev/null
  fi
fi

exit 0
