#!/usr/bin/env bash
# autopilot-disarm.sh v1.1 — clear an autopilot run's transient state after the run is over.
# Issue #321 (with #323), ADR-0112. Bash 3.2 clean: no assoc array, no mapfile, no ${v^^}.
#
# WHY THIS EXISTS. `autopilot` creates `.claude/autopilot-state/active` in Phase 1 and removes
# it ONLY in Phase 2. A session that dies — context exhaustion, a crash, the human pressing stop —
# never reaches Phase 2, so the marker outlives the run and `autopilot-guard` stays live in the
# human's own working sessions. The guard is RIGHT to fail closed; what was missing is an exit.
# Grepping the RUNBOOK for disarm/stale/interrupt/crash/recover/stuck returned exactly one hit, and
# it was about interrupting a turn, not recovering afterwards.
#
# IT IS A CHECKER. The caller branches on the EXIT CODE.
#   0  disarmed, or there was nothing armed (both are success; stdout says which)
#   1  REFUSED — the caller has no standing to disarm this marker (see the two modes below)
#   2  bad invocation (no root, root is not a directory, unknown option)
#   3  the check DID NOT RUN
#
# WHY 3 IS SEPARATE FROM 0. "Nothing was armed" and "I could not look" must not be the same answer.
# A human who runs this while blocked reads exit 0 as "you are free now"; if that came from an
# unreadable state directory they are still blocked and now believe they are not. Same line
# ADR-0076 draws between a fact about the INPUT and a fact about the ENVIRONMENT.
#
# TWO MODES, EXACT MIRRORS. Each has exactly one legitimate caller, and each refuses the other's.
#
#   autopilot-disarm.sh <root>                 RECOVERY. A human clearing a stale marker, from a
#                                            session that is not the run. The OWNER is refused.
#   autopilot-disarm.sh --completing <root>    COMPLETION. `autopilot` Phase 2, in the
#                                            session that armed it. A FOREIGN session is refused.
#
# R-04 HOLDS BY CONSTRUCTION, NOT BY PROMISE, and its content is: no session disarms on the
# strength of a claim it cannot back. The bare form refuses the owner because a foreign session
# cannot prove the owner is dead — that is the paragraph below, unchanged.
#
# A RUN DOES DISARM ITSELF, AT PHASE 2, AND THAT IS NOT A HOLE (issue #321 follow-up). The bare
# form used to be the only form, and `autopilot` Phase 2 called it from the owning session,
# so it was refused on every completed run — the marker outlived the run through the PRIMARY path,
# not through a crash, which is the failure this script exists to remove. Worse, the refusal below
# told the caller to "finish the run, Phase 2 clears the marker" while Phase 2 cleared it BY
# CALLING THIS SCRIPT. `--completing` is the exit that circle had no room for. The owning session
# at Phase 2 is the one caller with certainty: it IS the run, and it is ending. It backs its claim
# with identity, which is why the mirror refuses anyone else — a session that did not arm the
# marker has no standing to declare the run over.
#
# DO NOT COLLAPSE THE TWO MODES INTO ONE PERMISSIVE BRANCH. A flag that merely skips the ownership
# check is not a mirror, it is a bypass, and it would let any session clear any marker by adding a
# word. Test CP6 pins the bare form's refusal for exactly that reason and passes before and after.
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
#
# v1.1 (2026-08-23, issue #400, ADR-0167): `scope` and `published` leave the clear loop below — they
# are the run's configuration and progress, not guard conditions, and disarm cannot tell a paused
# run from a finished one. The output grows a `preserved:` block, in both terminal branches, naming
# the surviving bound and the override to relaunch with.

set -u

STATE_SUBDIR=".claude/autopilot-state"

COMPLETING=0
ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --completing) COMPLETING=1 ;;
    --) shift; ROOT="${1:-}"; break ;;
    -*)
      # Named as an unknown OPTION, never silently read as the root. Before the flag existed
      # `--bogus` was taken as the project root and exited 2 for the unrelated reason that no such
      # directory exists — the right code for the wrong cause, which is the thing this file spends
      # three paragraphs refusing to do elsewhere.
      echo "autopilot-disarm: unknown option: $1" >&2
      echo "autopilot-disarm: usage: autopilot-disarm.sh [--completing] <project-root>" >&2
      exit 2 ;;
    *) ROOT="$1" ;;
  esac
  shift
done

if [ -z "$ROOT" ]; then
  echo "autopilot-disarm: no project root given" >&2
  echo "autopilot-disarm: usage: autopilot-disarm.sh [--completing] <project-root>" >&2
  exit 2
fi
if [ ! -d "$ROOT" ]; then
  echo "autopilot-disarm: not a directory: $ROOT" >&2
  exit 2
fi

SDIR="$ROOT/$STATE_SUBDIR"
MARKER="$SDIR/active"

# The state directory may legitimately not exist (this repo has never run autopilot). That is
# "nothing armed", not "did not run".
if [ ! -e "$SDIR" ] && [ ! -e "$ROOT/.claude/needs-human" ]; then
  echo "DISARM: NOTHING-ARMED — no $STATE_SUBDIR and no needs-human under $ROOT"
  exit 0
fi
if [ -e "$SDIR" ] && [ ! -d "$SDIR" ]; then
  echo "autopilot-disarm: DID-NOT-RUN — $SDIR exists and is not a directory" >&2
  exit 3
fi
if [ -d "$SDIR" ] && [ ! -r "$SDIR" ]; then
  echo "autopilot-disarm: DID-NOT-RUN — cannot read $SDIR" >&2
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
if [ "$COMPLETING" -eq 1 ]; then
  # COMPLETION mode. The mirror: the owner is the permitted caller, a foreign session is refused.
  if [ -n "$OWNER" ] && [ -n "$CUR" ] && [ "$OWNER" != "$CUR" ]; then
    echo "DISARM: REFUSED — this session ($CUR) did not arm the marker (owner: $OWNER${ARMED_AT:+, at $ARMED_AT})." >&2
    echo "  --completing declares 'I am the run and I am finishing'. A session that did not arm the" >&2
    echo "  marker cannot declare that. To clear a marker left by someone else, drop the flag:" >&2
    echo "    bash autopilot-disarm.sh \"$ROOT\"" >&2
    exit 1
  fi
  if [ -n "$OWNER" ] && [ -z "$CUR" ]; then
    # Ownership could not be established either way. Proceed with a note, because failing closed
    # here would strand a run that cannot finish clearing up after itself — this feature's own bug
    # in a narrower case. Both leniencies (this and the ownerless marker above) match what the
    # recovery path already does; neither invents a second policy.
    NOTE="note: ownership could not be established — the marker names $OWNER and this session reports no id."
  fi
else
  # RECOVERY mode. Unchanged: the owning session is exactly the one that gets told no.
  # Written as a nested `if` rather than an `elif` on purpose — the mode dispatch and the ownership
  # rule are two different questions, and flattening them puts a needle for one inside the other.
  if [ -n "$OWNER" ] && [ -n "$CUR" ] && [ "$OWNER" = "$CUR" ]; then
    echo "DISARM: REFUSED — this session ($CUR) is the one that armed the marker${ARMED_AT:+ at $ARMED_AT}." >&2
    echo "  A run does not disarm itself through the recovery path. If this IS the run ending, that" >&2
    echo "  is what autopilot Phase 2 passes --completing for; otherwise run this from a" >&2
    echo "  different session." >&2
    exit 1
  fi
fi

# --- clear ---------------------------------------------------------------------------------------
# The whole transient set, not just `active`. A stale `build-status` reading RED halts the in-script
# `--check` gate REGARDLESS of the marker, and a stale `needs-human` halts every publish — so
# clearing only the marker would leave this command looking like it worked while the human stayed
# blocked by one of four other files. `started-at` is included because an orchestrator invented that
# path (it appears in no script and no SKILL.md; §3.1 said "record started_at" without saying where)
# and it is debris either way; the canonical timestamp now lives inside the marker.
CLEARED=""
# `published` (issue #364, ADR-0127 §D4) and `scope` (issue #365, ADR-0129 §D1) no longer leave here
# (issue #400, ADR-0167 §D1). This loop clears guard conditions — the files whose mere presence stops
# a publish. It does not clear the run's configuration or its progress, because those two are not
# conditions and disarm cannot tell a paused run from a finished one; that judgement moves to the
# next launch (ADR-0167 §D3/§D6), never to this script.
for f in "$MARKER" "$SDIR/build-status" "$SDIR/rtf-blocker" \
         "$SDIR/started-at" "$ROOT/.claude/needs-human"; do
  [ -e "$f" ] || continue
  if rm -f "$f" 2>/dev/null; then
    CLEARED="$CLEARED
  removed: ${f#$ROOT/}"
  else
    echo "autopilot-disarm: DID-NOT-RUN — could not remove ${f#$ROOT/}" >&2
    exit 3
  fi
done

# --- preserved -------------------------------------------------------------------------------------
# `scope` and `published` (ADR-0167 §D1, above) are reported here instead: best-effort, and reading
# either can never fail this disarm (ADR-0167 §D2) — an unreadable or empty bound degrades to
# "(bound unreadable)" rather than an exit-3. This script still never exits 3 for a preserved file.
PRESERVED=""
if [ -e "$SDIR/scope" ]; then
  _sf="$SDIR/scope"
  _sbound="(bound unreadable)"
  if [ -r "$_sf" ]; then
    _feat=$(grep '^features=' "$_sf" 2>/dev/null | head -1 | sed 's/^features=//')
    _only=$(grep -c '^only=' "$_sf" 2>/dev/null || true)
    if [ -n "$_feat" ] || [ "${_only:-0}" -gt 0 ] 2>/dev/null; then
      _sbound="(features=$_feat, only=${_only:-0} rows)"
    fi
  fi
  PRESERVED="$PRESERVED
  preserved: $STATE_SUBDIR/scope $_sbound"
fi
if [ -e "$SDIR/published" ]; then
  _pf="$SDIR/published"
  _pbound="(bound unreadable)"
  if [ -r "$_pf" ]; then
    _delivered=$(grep -c . "$_pf" 2>/dev/null || true)
    if [ -n "$_delivered" ] && [ "$_delivered" -gt 0 ] 2>/dev/null; then
      _pbound="($_delivered delivered)"
    fi
  fi
  PRESERVED="$PRESERVED
  preserved: $STATE_SUBDIR/published $_pbound"
fi

if [ -z "$CLEARED" ]; then
  echo "DISARM: NOTHING-ARMED — no marker and no halt state under $ROOT"
  [ -n "$NOTE" ] && echo "  $NOTE"
  if [ -n "$PRESERVED" ]; then
    printf '%s\n' "$PRESERVED" | sed '/^$/d'
    echo "  Relaunch with no --features/--only to reuse this bound; pass either to replace it."
  fi
  exit 0
fi

echo "DISARM: CLEARED${OWNER:+ (was armed by session $OWNER${ARMED_AT:+ at $ARMED_AT})}"
printf '%s\n' "$CLEARED" | sed '/^$/d'
[ -n "$NOTE" ] && echo "  $NOTE"
if [ -n "$PRESERVED" ]; then
  printf '%s\n' "$PRESERVED" | sed '/^$/d'
  echo "  Relaunch with no --features/--only to reuse this bound; pass either to replace it."
fi
echo "  autopilot-guard is now inert for this repo. Your own pushes are unaffected by it."
exit 0
