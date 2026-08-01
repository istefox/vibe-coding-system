#!/usr/bin/env bash
# nightly-disarm.sh v1.0 — clear a nightly run's transient state after the run is over.
# Issue #321 (with #323), ADR-0112. Bash 3.2 clean: no assoc array, no mapfile, no ${v^^}.
#
# WHY THIS EXISTS. `nightly-autopilot` creates `.claude/nightly-state/active` in Phase 1 and removes
# it ONLY in Phase 2. A session that dies — context exhaustion, a crash, the human pressing stop —
# never reaches Phase 2, so the marker outlives the run and `nightly-guard` stays live in the
# human's own working sessions. The guard is RIGHT to fail closed; what was missing is an exit.
# Grepping the RUNBOOK for disarm/stale/interrupt/crash/recover/stuck returned exactly one hit, and
# it was about interrupting a turn, not recovering afterwards.
#
# IT IS A CHECKER. The caller branches on the EXIT CODE.
#   0  disarmed, or there was nothing armed (both are success; stdout says which)
#   1  REFUSED — this session is the one that armed the marker
#   2  bad invocation (no root, or root is not a directory)
#   3  the check DID NOT RUN
#
# WHY 3 IS SEPARATE FROM 0. "Nothing was armed" and "I could not look" must not be the same answer.
# A human who runs this while blocked reads exit 0 as "you are free now"; if that came from an
# unreadable state directory they are still blocked and now believe they are not. Same line
# ADR-0076 draws between a fact about the INPUT and a fact about the ENVIRONMENT.
#
# R-04 HOLDS BY CONSTRUCTION, NOT BY PROMISE. It refuses when the marker's recorded `session_id`
# equals `CLAUDE_CODE_SESSION_ID`, so an active run cannot disarm itself through this script — the
# owning session is exactly the one that gets told no.
#
# IT CLAIMS NO LIVENESS ORACLE, DELIBERATELY. A different session id is not proof the owner is
# dead. A transcript-mtime threshold would look like proof and would be a heuristic; a pid is worse
# still and is worth naming because the issue suggested one: the marker is written from a Bash tool
# call whose subprocess exits within milliseconds, so `$$` would record a pid that is ALWAYS dead
# and would read as "definitely stale" for a perfectly live run. Session id and timestamp are the
# two real signals. This reports what it found and lets the human decide.
#
# A LEGACY MARKER IS A VALID MARKER. Before this feature `active` was a bare `touch`, so it carries
# no `session_id`. That is ABSENT, not foreign and not corrupt (ADR-0076): disarm proceeds with a
# note. Refusing would strand exactly the people this exists for — the ones whose marker predates
# the fix.

set -u

STATE_SUBDIR=".claude/nightly-state"

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  echo "nightly-disarm: usage: nightly-disarm.sh <project-root>" >&2
  exit 2
fi
if [ ! -d "$ROOT" ]; then
  echo "nightly-disarm: not a directory: $ROOT" >&2
  exit 2
fi

SDIR="$ROOT/$STATE_SUBDIR"
MARKER="$SDIR/active"

# The state directory may legitimately not exist (this repo has never run nightly). That is
# "nothing armed", not "did not run".
if [ ! -e "$SDIR" ] && [ ! -e "$ROOT/.claude/needs-human" ]; then
  echo "DISARM: NOTHING-ARMED — no $STATE_SUBDIR and no needs-human under $ROOT"
  exit 0
fi
if [ -e "$SDIR" ] && [ ! -d "$SDIR" ]; then
  echo "nightly-disarm: DID-NOT-RUN — $SDIR exists and is not a directory" >&2
  exit 3
fi
if [ -d "$SDIR" ] && [ ! -r "$SDIR" ]; then
  echo "nightly-disarm: DID-NOT-RUN — cannot read $SDIR" >&2
  exit 3
fi

# --- ownership -----------------------------------------------------------------------------------
OWNER=""
NOTE=""
if [ -f "$MARKER" ]; then
  if [ -r "$MARKER" ]; then
    OWNER=$(grep '^session_id=' "$MARKER" 2>/dev/null | head -1 | sed 's/^session_id=//')
    ARMED_AT=$(grep '^started_at=' "$MARKER" 2>/dev/null | head -1 | sed 's/^started_at=//')
    if [ -z "$OWNER" ]; then
      NOTE="note: the marker records no session_id — it predates issue #321, or was written by hand."
    fi
  else
    NOTE="note: the marker is unreadable, so its owner could not be determined."
  fi
fi

CUR="${CLAUDE_CODE_SESSION_ID:-}"
if [ -n "$OWNER" ] && [ -n "$CUR" ] && [ "$OWNER" = "$CUR" ]; then
  echo "DISARM: REFUSED — this session ($CUR) is the one that armed the marker${ARMED_AT:+ at $ARMED_AT}." >&2
  echo "  A run does not disarm itself. If the run really is over, finish it (Phase 2 clears the" >&2
  echo "  marker) or run this from a different session." >&2
  exit 1
fi

# --- clear ---------------------------------------------------------------------------------------
# The whole transient set, not just `active`. A stale `build-status` reading RED halts the in-script
# `--check` gate REGARDLESS of the marker, and a stale `needs-human` halts every publish — so
# clearing only the marker would leave this command looking like it worked while the human stayed
# blocked by one of four other files. `started-at` is included because an orchestrator invented that
# path (it appears in no script and no SKILL.md; §3.1 said "record started_at" without saying where)
# and it is debris either way; the canonical timestamp now lives inside the marker.
CLEARED=""
for f in "$MARKER" "$SDIR/build-status" "$SDIR/rtf-blocker" "$SDIR/token-budget" \
         "$SDIR/started-at" "$ROOT/.claude/needs-human"; do
  [ -e "$f" ] || continue
  if rm -f "$f" 2>/dev/null; then
    CLEARED="$CLEARED
  removed: ${f#$ROOT/}"
  else
    echo "nightly-disarm: DID-NOT-RUN — could not remove ${f#$ROOT/}" >&2
    exit 3
  fi
done

if [ -z "$CLEARED" ]; then
  echo "DISARM: NOTHING-ARMED — no marker and no halt state under $ROOT"
  [ -n "$NOTE" ] && echo "  $NOTE"
  exit 0
fi

echo "DISARM: CLEARED${OWNER:+ (was armed by session $OWNER${ARMED_AT:+ at $ARMED_AT})}"
printf '%s\n' "$CLEARED" | sed '/^$/d'
[ -n "$NOTE" ] && echo "  $NOTE"
echo "  nightly-guard is now inert for this repo. Your own pushes are unaffected by it."
exit 0
