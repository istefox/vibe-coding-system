#!/bin/bash
# autopilot-guard v1.3 (ADR-0022 D7) — pre-publish fail-safe gate for overnight runs.
#
# Two invocation paths, one logic:
#   1. PreToolUse hook: reads the tool event JSON on stdin. While an autopilot run is active it
#      HARD-BLOCKS any forbidden publish (merge, auto-merge, force-push, push to main/master)
#      regardless of state, and runs the halt checks on an allowed publish (push feat/*,
#      gh pr create). It is inert for non-publish commands and outside an autopilot run.
#   2. In-script gate: `autopilot-guard.sh --check <root>` — publish-feature.sh calls this right
#      before it pushes. Prints "AUTOPILOT-GUARD HALT: <reason>" and exits 2 on halt, 0 when clean.
#
# Fail-safe: unlike stop-gate (fail-open), this hook BLOCKS on malformed input, a missing jq, or
# an internal error once it sees an autopilot publish. Allowing an unchecked publish is the dangerous
# direction. Outside an autopilot run the hook is inert (exit 0).
#
# v1.1 (2026-07-01, review finding #1/#4): the guard now parses the command to block merge /
# auto-merge / force / push-to-main directly, and fails closed when jq is absent.
# v1.2 (2026-07-11, audit findings 1.3/2.11/2.12/3.22): +<ref> force-refspecs and --no-verify
# are forbidden; force flags match only inside the push segment (no false positive on an
# unrelated `rm -f`); malformed JSON with jq present now fails closed like the jq-less path.
# v1.3 (2026-07-26, issue #114, ADR-0060 §D3): no logic change here, comment only — this is the
# marker split. `.claude/needs-human` is a RUN-LEVEL halt: something is wrong with the run (red
# build, RTF blocker, budget breach, a feature that failed mid-flight leaving unknown state), and
# once set it blocks every subsequent publish, on purpose. A KNOWN, CONTAINED per-feature problem
# (a thin issue, a suspected-injection issue, an unprovisioned external dependency) is a different
# thing and does NOT belong in this file: it now goes to
# `<root>/.claude/autopilot-state/skipped-features` instead, a plain append-only note this script
# deliberately never reads. Before this fix, `spec-from-issue`'s thin-issue skip and its
# injection-suspect skip both wrote needs-human, so one thin issue in a twenty-feature roadmap
# silently halted the other nineteen. If you are about to add a new writer for a per-feature,
# known-cause skip: it goes to skipped-features, never here. See
# `autopilot/SKILL.md` §3.3 "Marker contract" for the full writer list.
# v1.4 (2026-08-01, issue #324, ADR-0111): still no logic change here, comment only. The writer
# list grew from three to five — `project-conductor` Step 4's no-generated-SPEC skip and Step 5
# branch C's `TERMINAL` entry-state skip. Branch C used to write needs-human for EVERY feature that
# did not reach `completed`, so the ADR-0060 blast radius survived through a second door: one
# wedged manifest in a twelve-feature wave cost the eleven behind it. Only a decided end (`TERMINAL`
# from `manifest-entry-state.sh`, which reads `current_step` AND `status`) takes the skip path; a
# crash, a mid-flight stop, an unparseable manifest and the anti-test-weakening halt all still land
# here as run-level halts.
# v1.5 (2026-08-06, issue #365, ADR-0129 §D6): the per-run token budget halt is REMOVED, not wired
# — finding 3 of that ADR settles it: this guard is a PreToolUse hook on the publish, so it gets a
# turn only once per feature, at the end, and a ceiling it evaluates afterwards cannot stop the
# feature that breached it, only the one after (cumulative drift, which --features N now bounds
# deterministically instead). `rtf-blocker`'s halt is DELIBERATELY KEPT, byte-unchanged, and this is
# not the same case made smaller: the removed halt was structurally unable to work; rtf-blocker's
# halt would work correctly the moment something wrote it. No review cycle runs during an unattended
# roadmap run (concept-to-code Gate 5's autopilot default is "Skip review", and project-conductor
# invokes concept-to-code — never autopilot-build — on every feature), which is why rtf-blocker is
# currently unproduced. That is a measured reason it is unreached, not evidence its mechanism is
# unsound — removing a halt that cannot work is a correction, removing one that works and is merely
# unreached is deleting a safeguard because the path it guards is currently idle. See
# autopilot/SKILL.md §3.3.
#
# Bash 3.2 clean: no assoc array, no mapfile, no ${v^^}, no process substitution.

STATE_SUBDIR=".claude/autopilot-state"

# marker_field <root> <key>: read `key=value` from the active marker. Empty when the marker is
# absent, unreadable, or predates issue #321 (a bare `touch`, which is still a valid armed marker —
# presence is what arms the guard, never contents). Absent, foreign and unreadable are three
# different states and the caller must not collapse them (ADR-0076 §THE RULE).
marker_field() {
  _mf="$1/$STATE_SUBDIR/active"
  [ -f "$_mf" ] || return 0
  grep "^$2=" "$_mf" 2>/dev/null | head -1 | sed "s/^$2=//"
}

# STALE_HINT: appended to a halt message ONLY when the marker was armed by a DIFFERENT session
# (issue #321, ADR-0112). Set by the hook path below, before any print_halt can fire.
#
# A different session id is not proof the owner is dead, and this deliberately claims no more than
# it knows: it reports who armed the marker and names the exit. When the ids MATCH — a live run
# halting normally — the message is byte-identical to what it was before this feature, because
# inviting a running roadmap to disarm itself is the one thing R-04 forbids. Same fallback when
# either id is unreadable: say nothing rather than guess.
STALE_HINT=""

# print_halt: emit the machine-readable halt line the /goal evaluator keys off, plus a human
# line on stderr, then exit 2 (block).
print_halt() {
  printf 'AUTOPILOT-GUARD HALT: %s\n' "$1"
  printf 'autopilot-guard: publish blocked — %s\n' "$1" >&2
  [ -n "$STALE_HINT" ] && printf '%s\n' "$STALE_HINT" >&2
  exit 2
}

# is_forbidden_publish <cmd>: return 0 if the command is a never-allowed publish during an autopilot
# run (merge, auto-merge, force-push, or a push whose destination is main/master).
is_forbidden_publish() {
  c="$1"
  case "$c" in
    *"gh pr merge"*) return 0 ;;
    *"enablePullRequestAutoMerge"*) return 0 ;;
    *"--auto-merge"*) return 0 ;;
  esac
  # gh pr merge with a separate --auto flag.
  case "$c" in
    *"gh pr "*"--auto"*) return 0 ;;
  esac
  # --no-verify on any git command skips repo hooks: never allowed unattended (ADR-0022 D2).
  case "$c" in
    *"git "*"--no-verify"*) return 0 ;;
  esac
  case "$c" in
    *"git push"*)
      case "$c" in
        *"+HEAD"*|*":refs/heads/main"*|*":refs/heads/master"*) return 0 ;;
      esac
      # Force flags scoped to the push segment: an unrelated `rm -f x && git push ...`
      # must not match, but any -f/--force* after `git push` must.
      printf '%s' "$c" | grep -Eq 'git push[^|;&]*[[:space:]](-f([[:space:]]|$)|--force)' && return 0
      # Any +<ref> force-refspec after `git push` (+main, +master, +refs/heads/x).
      printf '%s' "$c" | grep -Eq 'git push[^|;&]*[[:space:]]\+[^[:space:]]' && return 0
      # Destination main/master (space-, slash-, colon- or plus-delimited ref), SCOPED TO THE PUSH
      # SEGMENT exactly like the two rules above (issue #323, ADR-0112). It used to run over the
      # whole command, so `git push -u origin feat/x && gh pr create --base main` read the PR's
      # `--base main` as the push's destination and was refused — the most ordinary publish shape
      # there is. `publish-feature.sh` issues push and PR as separate commands, which is why the
      # autopilot path never tripped it and it stayed invisible.
      #
      # The `(^|` alternative is GONE, not merely unused: under segment scoping the match starts at
      # `git push`, so a command beginning with `main` is unreachable and leaving the branch would
      # be dead pattern that reads as coverage.
      #
      # Third recorded instance of fixing a boundary in one rule and not its sibling — ADR-0074 on
      # `agent-command-scope.sh` R1, ADR-0079 on R2, this. **If you add a fourth rule here, scope it
      # to the segment too.**
      printf '%s' "$c" | grep -Eq 'git push[^|;&]*[ :/+](main|master)([ ]|$)' && return 0
      ;;
  esac
  return 1
}

# is_allowed_publish <cmd>: an allowed publish that still runs the halt checks.
is_allowed_publish() {
  case "$1" in
    *"git push"*|*"gh pr create"*) return 0 ;;
  esac
  return 1
}

# run_halt_checks <root>: exit 0 if clean; call print_halt on the first failing condition.
run_halt_checks() {
  root="$1"
  sdir="$root/$STATE_SUBDIR"

  if [ -f "$sdir/build-status" ]; then
    bs=$(cat "$sdir/build-status" 2>/dev/null)
    [ "$bs" = "RED" ] && print_halt "build is RED after the fix cycle"
  fi

  if [ -f "$root/.claude/needs-human" ]; then
    reason=$(head -1 "$root/.claude/needs-human" 2>/dev/null)
    [ -z "$reason" ] && reason="needs-human marker present"
    print_halt "$reason"
  fi

  if [ -f "$sdir/rtf-blocker" ]; then
    reason=$(head -1 "$sdir/rtf-blocker" 2>/dev/null)
    [ -z "$reason" ] && reason="review-triage-fix raised a BLOCKER"
    print_halt "$reason"
  fi

  return 0
}

# --- In-script gate mode ---------------------------------------------------------------
if [ "$1" = "--check" ]; then
  root="$2"
  if [ -z "$root" ] || [ ! -d "$root" ]; then
    print_halt "guard --check called with an invalid root ($root)"
  fi
  run_halt_checks "$root"
  exit 0
fi

# --- PreToolUse hook mode --------------------------------------------------------------
INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

# jq-less fallback: cannot resolve cwd/active state, so fail closed on any forbidden publish
# keyword in the raw event (dangerous direction); allow everything else.
if ! command -v jq >/dev/null 2>&1; then
  if is_forbidden_publish "$INPUT"; then
    print_halt "guard cannot verify (jq missing) — failing safe on a forbidden publish"
  fi
  exit 0
fi

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="$PWD"

# Malformed JSON with jq present: CMD is empty but the event is not parseable, so cwd/active
# state cannot be resolved. Mirror the jq-less branch: fail closed on any forbidden publish
# keyword in the raw event; allow everything else (audit finding 2.11).
if [ -z "$CMD" ] && ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  if is_forbidden_publish "$INPUT"; then
    print_halt "guard cannot parse the event (malformed JSON) — failing safe on a forbidden publish"
  fi
  exit 0
fi

# Not a publish at all: this guard does not care. Allow.
if ! is_allowed_publish "$CMD" && ! is_forbidden_publish "$CMD"; then
  exit 0
fi

# Legacy marker detection (ADR-0127 §D2.3). MUST precede the inert-exit below, because that exit
# is exactly how an unmigrated repo loses its guard: a run armed under .claude/nightly-state/active
# is invisible to this script, so a publish-shaped command would fall straight through to `exit 0`
# and go out UNGUARDED. Halting is the safe direction — a blocked push is recoverable, an
# unguarded one during a live run is not, and this cannot be resolved by reading the old marker
# instead (see autopilot-migrate.sh's header for why nothing falls back).
if [ ! -f "$CWD/$STATE_SUBDIR/active" ] && [ -f "$CWD/.claude/nightly-state/active" ]; then
  print_halt "legacy nightly-state/active marker found — this repo predates the ADR-0127 rename. Run: bash ~/.claude/hooks/autopilot-migrate.sh --root \"$CWD\""
  exit 2
fi

# Publish-shaped command, but no active autopilot run: guard is inert (do not block manual work).
[ -f "$CWD/$STATE_SUBDIR/active" ] || exit 0

# The marker is present. Decide whether THIS session is the one that armed it (issue #321).
# A session that dies never reaches Phase 2, so the marker outlives it and the guard stays live in
# the human's own working sessions with nothing pointing at the file to remove. This does not
# disarm anything and cannot: it only decides whether the halt message is allowed to name the exit.
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
OWNER=$(marker_field "$CWD" session_id)
ARMED_AT=$(marker_field "$CWD" started_at)
if [ -n "$OWNER" ] && [ -n "$SID" ] && [ "$OWNER" != "$SID" ]; then
  STALE_HINT="autopilot-guard: this marker was armed by session $OWNER${ARMED_AT:+ at $ARMED_AT}, not by this session.
autopilot-guard: if that run is over, clear it:  bash ~/.claude/hooks/autopilot-disarm.sh \"$CWD\""
fi

# Active autopilot run. A forbidden publish is blocked unconditionally.
if is_forbidden_publish "$CMD"; then
  print_halt "forbidden publish during an autopilot run (merge/auto-merge/force/no-verify/push-to-main)"
fi

# Allowed publish: run the halt checks (fail-safe blocks on any halt).
run_halt_checks "$CWD"
exit 0
