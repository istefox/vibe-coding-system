#!/bin/bash
# instructions-loaded-verify.sh v1.0 — read-only consumer of instructions-loaded-log.sh's log
# (ADR-0171). Answers "did THIS file actually load into a session's context" with a measured
# verdict instead of trusting documented behaviour.
#
# Usage: instructions-loaded-verify.sh <absolute-file-path> [--since <YYYY-MM-DD|ISO8601Z>]
#
# Exit codes:
#   0  a verdict was produced — read LOADED= (true/stale/false)
#   2  bad --since argument
#   3  INCONCLUSIVE — see reason=; absence of a record here is NOT evidence the file never loaded
#   4  the log exists but jq is unavailable, so it cannot be read
#
# This is a REPORTER with a DID-NOT-RUN sentinel, not a checker (repo rule 5): it always prints,
# never abstains silently. A caller branches on the exit code FIRST, then parses stdout — never
# `[ -n "$out" ]`, this script prints on every path including the inconclusive ones.
#
# Anchor: defaults to the TARGET FILE'S OWN mtime, not a timestamp the human must remember to
# supply. Making the anchor optional-and-forgettable would silently reopen the exact failure this
# feature exists to close (a query that can never come back false) — see instructions-loaded-log.sh's
# header, finding C1. --since overrides it.
#
# What this CANNOT tell you (state plainly, do not let a caller infer more than this measures):
#   - LOADED=true means the file's bytes entered the model's context window. It does NOT mean the
#     correction was obeyed. Read the loaded= line as "delivered", never as "in effect".
#   - subagent coverage is unknown: the payload carries no agent_id/agent_type, and whether this
#     event fires inside a Workflow subagent at all is an open question (ADR-0016).
#   - a record proves SOME session loaded the file, not necessarily the one the caller has in
#     mind — the session_id list in a verdict is printed so a caller can check.
#
# Bash 3.2 clean. Read-only: never writes, never mutates a manifest.
#
# transcript-scan-exempt: reads instructions-loaded-log.sh's own log; not a CC transcript.

set -u

SELF_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd) || { printf 'INSTRUCTIONS_LOADED status=UNREADABLE\nreason=cannot resolve own directory\n'; exit 4; }
# shellcheck source=instructions-loaded-canon.sh
. "$SELF_DIR/instructions-loaded-canon.sh" 2>/dev/null || { printf 'INSTRUCTIONS_LOADED status=UNREADABLE\nreason=canon helper missing\n'; exit 4; }

TARGET=""
SINCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="${2:-}"; shift 2 ;;
    --since=*) SINCE="${1#--since=}"; shift ;;
    *) [ -z "$TARGET" ] && TARGET="$1"; shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  printf 'INSTRUCTIONS_LOADED status=BADARG\nreason=usage: instructions-loaded-verify.sh <absolute-file-path> [--since <YYYY-MM-DD|ISO8601Z>]\n'
  exit 2
fi

DIR="${INSTRUCTIONS_LOADED_DIR:-$HOME/.claude/state/instructions-loaded}"
LOG="$DIR/events.jsonl"
WATERMARK_FILE="$DIR/trim-watermark"

printf 'LOG=%s\n' "$LOG"

CANON=$(_il_canon "$TARGET") || {
  printf 'INSTRUCTIONS_LOADED status=BADARG\n'
  printf 'reason=%s\n' "target path does not resolve: $TARGET"
  exit 2
}
printf 'TARGET_CANON=%s\n' "$CANON"

# --- anchor ---------------------------------------------------------------------------------
if [ -n "$SINCE" ]; then
  case "$SINCE" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) : ;;
    *)
      printf 'INSTRUCTIONS_LOADED status=BADARG\n'
      printf 'reason=%s\n' "--since must be YYYY-MM-DD or YYYY-MM-DDTHH:MM:SSZ (UTC); got: $SINCE"
      exit 2 ;;
  esac
  case "$SINCE" in
    ????-??-??) ANCHOR="${SINCE}T00:00:00Z" ;;
    *) ANCHOR="$SINCE" ;;
  esac
  ANCHOR_SRC="--since"
  ANCHOR_EPOCH=$(_epoch_of_iso "$SINCE") || ANCHOR_EPOCH=0
  ANCHOR_EPOCH=${ANCHOR_EPOCH:-0}
else
  [ -e "$TARGET" ] || {
    printf 'INSTRUCTIONS_LOADED status=BADARG\n'
    printf 'reason=%s\n' "target file does not exist and no --since given, no anchor available: $TARGET"
    exit 2
  }
  ANCHOR_EPOCH=$(_fmtime "$TARGET")
  if [ -z "$ANCHOR_EPOCH" ]; then
    printf 'INSTRUCTIONS_LOADED status=INCONCLUSIVE\n'
    printf 'reason=%s\n' "target-unreadable: could not stat $TARGET for its own mtime"
    printf 'RECOMMEND loaded=unchanged\n'
    exit 3
  fi
  ANCHOR=$(_iso_of_epoch "$ANCHOR_EPOCH")
  ANCHOR_SRC="mtime($TARGET)"
fi
printf 'ANCHOR=%s\n' "$ANCHOR"
printf 'ANCHOR_SOURCE=%s\n' "$ANCHOR_SRC"

# CURRENT_MTIME is the target's LIVE mtime right now, independent of the anchor. It is what
# separates LOADED=true from LOADED=stale. The two are the same value in the default (no
# --since) case, by construction. They diverge under --since: the anchor becomes an old
# checkpoint used only to gate the opportunity window (state 5, empty-window), while a match
# found in that window can still describe a version of the file OLDER than what is on disk right
# now — exactly the state a naive "ts >= anchor implies current" comparison would miss, and did
# miss until this was caught by a manual smoke test (2026-08-27): with the anchor doing double
# duty as both the window gate and the freshness bar, LOADED=stale was unreachable, because any
# record whose ts passed the window gate necessarily also had file_mtime >= that same anchor.
CURRENT_MTIME=""
[ -e "$TARGET" ] && CURRENT_MTIME=$(_fmtime "$TARGET")

# --- log presence -----------------------------------------------------------------------------
if [ ! -f "$LOG" ]; then
  printf 'INSTRUCTIONS_LOADED status=INCONCLUSIVE\n'
  printf 'reason=%s\n' "log-absent: the hook may never have run (not wired, or no session since deploy)"
  printf 'RECOMMEND loaded=unchanged\n'
  exit 3
fi
if [ ! -s "$LOG" ]; then
  printf 'INSTRUCTIONS_LOADED status=INCONCLUSIVE\n'
  printf 'reason=%s\n' "log-empty: state dir exists but the hook never wrote a record"
  printf 'RECOMMEND loaded=unchanged\n'
  exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'INSTRUCTIONS_LOADED status=UNREADABLE\n'
  printf 'reason=%s\n' "jq is required to read the log"
  exit 4
fi

# --- denominators (rule 7: zero matches and zero candidates look identical from outside) ------
TOTAL=$(wc -l < "$LOG" 2>/dev/null | tr -d ' '); TOTAL=${TOTAL:-0}
PARSED=$(jq -s '[.[] | select(.record == "instructions_loaded")] | length' "$LOG" 2>/dev/null); PARSED=${PARSED:-0}
RAW=$(jq -s '[.[] | select(.record == "raw")] | length' "$LOG" 2>/dev/null); RAW=${RAW:-0}

printf 'RECORDS_TOTAL=%s\n' "$TOTAL"
printf 'RECORDS_PARSED=%s\n' "$PARSED"
printf 'RECORDS_RAW=%s\n' "$RAW"

if [ "$PARSED" -eq 0 ]; then
  printf 'INSTRUCTIONS_LOADED status=INCONCLUSIVE\n'
  printf 'reason=%s\n' "no-parsed-records: $TOTAL total line(s), 0 parsed (jq was missing when they were written — see RECORDS_RAW)"
  printf 'RECOMMEND loaded=unchanged\n'
  exit 3
fi

# --- truncation guard: was the answer possibly trimmed away? ----------------------------------
if [ -r "$WATERMARK_FILE" ]; then
  WM=$(head -1 "$WATERMARK_FILE" 2>/dev/null)
  printf 'TRIM_WATERMARK=%s\n' "${WM:-none}"
  if [ -n "$WM" ] && [ "$WM" != "unknown" ]; then
    if [ "$ANCHOR" \< "$WM" ]; then
      printf 'INSTRUCTIONS_LOADED status=INCONCLUSIVE\n'
      printf 'reason=%s\n' "truncated: the anchor ($ANCHOR) predates the oldest retained record ($WM) — a matching event may have been trimmed"
      printf 'RECOMMEND loaded=unchanged\n'
      exit 3
    fi
  fi
else
  printf 'TRIM_WATERMARK=none\n'
fi

# --- window: any parsed records at or after the anchor, regardless of file -------------------
IN_WINDOW=$(jq -r --arg a "$ANCHOR" 'select(.record=="instructions_loaded" and .ts >= $a) | .ts' "$LOG" 2>/dev/null | wc -l | tr -d ' ')
SESS_WIN=$(jq -r --arg a "$ANCHOR" 'select(.record=="instructions_loaded" and .ts >= $a) | (.session_id // "-")' "$LOG" 2>/dev/null | sort -u | wc -l | tr -d ' ')
printf 'RECORDS_IN_WINDOW=%s\n' "$IN_WINDOW"
printf 'SESSIONS_IN_WINDOW=%s\n' "$SESS_WIN"

if [ "$IN_WINDOW" -eq 0 ]; then
  printf 'INSTRUCTIONS_LOADED status=INCONCLUSIVE\n'
  printf 'reason=%s\n' "empty-window: no session has loaded ANY instruction file since $ANCHOR yet — absence here is absence of opportunity, not evidence the file was not loaded"
  printf 'RECOMMEND loaded=unchanged\n'
  exit 3
fi

# --- exact match on the canonical path (rule 18: never contains/startswith/glob) --------------
MATCH_PRED='.record=="instructions_loaded" and .file_path_canon == $p and .ts >= $a'
MATCHES_WIN=$(jq -r --arg p "$CANON" --arg a "$ANCHOR" "select($MATCH_PRED) | .ts" "$LOG" 2>/dev/null | wc -l | tr -d ' ')
printf 'MATCHES_IN_WINDOW=%s\n' "$MATCHES_WIN"

if [ "$MATCHES_WIN" -eq 0 ]; then
  printf 'INSTRUCTIONS_LOADED status=VERDICT\n'
  printf 'LOADED=false\n'
  printf 'subagent_coverage=unknown\n'
  printf 'reason=%s\n' "no session in the anchor window loaded $CANON"
  exit 0
fi

MATCH_SESSIONS=$(jq -r --arg p "$CANON" --arg a "$ANCHOR" "select($MATCH_PRED) | (.session_id // \"-\")" "$LOG" 2>/dev/null | sort -u | paste -sd, - )
printf 'MATCH_SESSIONS=%s\n' "$MATCH_SESSIONS"

printf 'INSTRUCTIONS_LOADED status=VERDICT\n'
if [ -z "$CURRENT_MTIME" ]; then
  # TARGET no longer exists on disk — there is no "current version" left to be stale against.
  # A match inside the window is the strongest statement left to make: some load happened after
  # the anchor. Collapsing fresh/stale here is a declared limit, not a silent guess (rule 4).
  printf 'LOADED=true\n'
  printf 'reason=%s\n' "$MATCHES_WIN matching load(s) in the anchor window; $CANON no longer exists on disk, so freshness cannot be judged against a current version"
else
  FRESH=$(jq -r --arg p "$CANON" --arg a "$ANCHOR" --argjson me "$CURRENT_MTIME" \
    "select($MATCH_PRED and .file_mtime != null and .file_mtime >= \$me) | .ts" "$LOG" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$FRESH" -gt 0 ]; then
    printf 'LOADED=true\n'
    printf 'reason=%s\n' "$FRESH matching load(s) at or after the file's current mtime; the version on disk right now was delivered into context"
  else
    printf 'LOADED=stale\n'
    printf 'reason=%s\n' "$MATCHES_WIN matching load(s) in the anchor window, all of an OLDER version than what is on disk right now — the current content has not been observed loading yet"
  fi
fi
printf 'subagent_coverage=unknown\n'
printf 'note=%s\n' "LOADED means the bytes entered context. It does NOT mean the correction was followed."
exit 0
