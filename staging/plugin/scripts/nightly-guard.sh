#!/bin/bash
# nightly-guard v1.1 (ADR-0022 D7) — pre-publish fail-safe gate for overnight runs.
#
# Two invocation paths, one logic:
#   1. PreToolUse hook: reads the tool event JSON on stdin. While a nightly run is active it
#      HARD-BLOCKS any forbidden publish (merge, auto-merge, force-push, push to main/master)
#      regardless of state, and runs the halt checks on an allowed publish (push feat/*,
#      gh pr create). It is inert for non-publish commands and outside a nightly run.
#   2. In-script gate: `nightly-guard.sh --check <root>` — publish-feature.sh calls this right
#      before it pushes. Prints "NIGHTLY-GUARD HALT: <reason>" and exits 2 on halt, 0 when clean.
#
# Fail-safe: unlike stop-gate (fail-open), this hook BLOCKS on malformed input, a missing jq, or
# an internal error once it sees a nightly publish. Allowing an unchecked publish is the dangerous
# direction. Outside a nightly run the hook is inert (exit 0).
#
# v1.1 (2026-07-01, review finding #1/#4): the guard now parses the command to block merge /
# auto-merge / force / push-to-main directly, and fails closed when jq is absent.
# v1.2 (2026-07-11, audit findings 1.3/2.11/2.12/3.22): +<ref> force-refspecs and --no-verify
# are forbidden; force flags match only inside the push segment (no false positive on an
# unrelated `rm -f`); malformed JSON with jq present now fails closed like the jq-less path.
#
# Bash 3.2 clean: no assoc array, no mapfile, no ${v^^}, no process substitution.

STATE_SUBDIR=".claude/nightly-state"

# print_halt: emit the machine-readable halt line the /goal evaluator keys off, plus a human
# line on stderr, then exit 2 (block).
print_halt() {
  printf 'NIGHTLY-GUARD HALT: %s\n' "$1"
  printf 'nightly-guard: publish blocked — %s\n' "$1" >&2
  exit 2
}

# is_forbidden_publish <cmd>: return 0 if the command is a never-allowed publish during a nightly
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
      # Destination main/master (space-, slash-, colon- or plus-delimited ref).
      printf '%s' "$c" | grep -Eq '(^|[ :/+])(main|master)([ ]|$)' && return 0
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

  if [ -f "$sdir/token-budget" ]; then
    limit=$(grep '^limit=' "$sdir/token-budget" 2>/dev/null | head -1 | sed 's/^limit=//')
    spent=$(grep '^spent=' "$sdir/token-budget" 2>/dev/null | head -1 | sed 's/^spent=//')
    case "$limit" in ''|*[!0-9]*) limit=0;; esac
    case "$spent" in ''|*[!0-9]*) spent=0;; esac
    if [ "$limit" -gt 0 ] && [ "$spent" -ge "$limit" ]; then
      print_halt "token budget exceeded ($spent >= $limit)"
    fi
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

# Publish-shaped command, but no active nightly run: guard is inert (do not block manual work).
[ -f "$CWD/$STATE_SUBDIR/active" ] || exit 0

# Active nightly run. A forbidden publish is blocked unconditionally.
if is_forbidden_publish "$CMD"; then
  print_halt "forbidden publish during a nightly run (merge/auto-merge/force/no-verify/push-to-main)"
fi

# Allowed publish: run the halt checks (fail-safe blocks on any halt).
run_halt_checks "$CWD"
exit 0
