#!/bin/bash
# ci-verdict v1.0 — derives a GREEN/PENDING/RED CI verdict from a PR's statusCheckRollup, never
# from a watch command's own exit code (issue #398).
#
# BUG THIS CLOSES. `commit` Step 6b used to wait with `timeout 480 gh pr checks "$n" --watch
# --fail-fast` and read `rc=0` as "CI green — all required checks passed." `gh` also exits 0 when
# the watch itself dies for an unrelated reason (observed live on PR #397: a TLS handshake timeout
# while `shell-tests` was still pending) — the branch meaning "the watch finished and everything
# passed" is also reached by "the watch stopped watching." Repo rule 4 applies to `gh`'s exit code
# here exactly as it does to this repo's own checks: a check that did not run must be
# distinguishable from a check that found nothing. This script is that distinction: it reads each
# context's own reported state independently of whatever ended the wait.
#
# CONTRACT. This is a REPORTER (rule 5): it always decides a verdict from the data it is given and
# exits 0, printing `VERDICT: GREEN|PENDING|RED`; it never treats a wait-loop's exit code as
# evidence. The one exception is DID-NOT-RUN (rule 4) — when the input itself is unusable (no jq,
# unparseable JSON), it says so on exit 3 rather than guessing a verdict from nothing.
#
# Usage:
#   gh pr view <n> --json statusCheckRollup -q '.statusCheckRollup' \
#     | ci-verdict.sh [--required <file>]
#
#   --required <file>   one check/context name per line — the branch-protection required-checks
#                        list. Absent, or the file doesn't exist, or is empty -> fail-safe: every
#                        reported check counts as required. This mirrors Step 6b's own existing
#                        policy for an unreadable branch-protection API response (never silently
#                        ignore a red check because "required" couldn't be confirmed).
#
# stdin: a JSON array, as returned by `gh pr view --json statusCheckRollup -q '.statusCheckRollup'`
#        — a mix of GitHub Actions CheckRun objects (`status`/`conclusion`) and legacy
#        StatusContext objects (`state`) is expected and handled; an empty array is a legitimate
#        "no checks reported yet" case, classified PENDING, never GREEN by default.
#
# stdout (exit 0):
#   VERDICT: GREEN|PENDING|RED
#   PENDING: <name>   (zero or more, one per check not yet concluded)
#   FAILED: <name>    (zero or more, one per check that concluded unsuccessfully)
#
# stdout (exit 3, DID-NOT-RUN — rule 4, never read as a clean GREEN):
#   DID-NOT-RUN: <reason>
#
# Precedence: any FAILED check -> RED, even with others still PENDING (a concluded failure is
# actionable now; withholding it behind an unrelated still-running check would just delay the
# human seeing it, the opposite of what Step 6c's own "report ALL failing checks" already does).
# Otherwise any PENDING check -> PENDING (this is R-02: the exact dead-watch shape — a concluded
# rollup query returning one un-concluded required context — must not read as GREEN just because
# the caller's own gh invocation happened to exit 0).
set -u

REQUIRED_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --required) REQUIRED_FILE="${2:-}"; shift 2 ;;
    *) printf 'DID-NOT-RUN: unrecognised argument: %s\n' "$1"; exit 3 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  printf 'DID-NOT-RUN: jq not found\n'
  exit 3
fi

rollup=$(cat)
if ! printf '%s' "$rollup" | jq -e 'type == "array"' >/dev/null 2>&1; then
  printf 'DID-NOT-RUN: statusCheckRollup input did not parse as a JSON array\n'
  exit 3
fi

required=""
if [ -n "$REQUIRED_FILE" ] && [ -f "$REQUIRED_FILE" ]; then
  required=$(sed '/^[[:space:]]*$/d' "$REQUIRED_FILE")
fi

# One line per check: "<name><TAB><bucket>", bucket in {PENDING, FAILED, OK}.
# CheckRun (GitHub Actions): `status` present -> not COMPLETED is PENDING; COMPLETED reads
# `conclusion` (SUCCESS/NEUTRAL/SKIPPED are OK, everything else — FAILURE, CANCELLED, TIMED_OUT,
# ACTION_REQUIRED, STALE, null — is FAILED).
# StatusContext (legacy commit status): no `status` field; `state` PENDING/EXPECTED is PENDING,
# SUCCESS is OK, everything else (ERROR, FAILURE) is FAILED.
classified=$(printf '%s' "$rollup" | jq -r '
  .[] |
  ( .context // .name // "unnamed" ) as $n |
  if has("status") and (.status != null) and (.status != "") then
    if (.status != "COMPLETED") then "\($n)\tPENDING"
    elif (.conclusion == "SUCCESS" or .conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "\($n)\tOK"
    else "\($n)\tFAILED"
    end
  else
    if (.state == "PENDING" or .state == "EXPECTED") then "\($n)\tPENDING"
    elif (.state == "SUCCESS") then "\($n)\tOK"
    else "\($n)\tFAILED"
    end
  end
')

pending_names=""
failed_names=""
while IFS="$(printf '\t')" read -r name bucket; do
  [ -n "$name" ] || continue
  if [ -n "$required" ]; then
    printf '%s\n' "$required" | grep -qxF "$name" || continue   # not a required context — ignore
  fi
  case "$bucket" in
    PENDING) pending_names="$pending_names
$name" ;;
    FAILED) failed_names="$failed_names
$name" ;;
  esac
done <<CLASSIFIED_EOF
$classified
CLASSIFIED_EOF
pending_names=$(printf '%s\n' "$pending_names" | sed '/^$/d')
failed_names=$(printf '%s\n' "$failed_names" | sed '/^$/d')

# An empty rollup (no checks reported at all yet) has no OK/FAILED/PENDING lines either —
# distinguish it from a genuinely all-green rollup rather than defaulting to GREEN on emptiness
# (rule 7: guard the denominator, not only the matches).
check_count=$(printf '%s\n' "$classified" | sed '/^$/d' | wc -l | tr -d ' ')

if [ -n "$failed_names" ]; then
  verdict="RED"
elif [ -n "$pending_names" ] || [ "$check_count" -eq 0 ]; then
  verdict="PENDING"
else
  verdict="GREEN"
fi

printf 'VERDICT: %s\n' "$verdict"
printf '%s\n' "$pending_names" | sed '/^$/d; s/^/PENDING: /'
printf '%s\n' "$failed_names" | sed '/^$/d; s/^/FAILED: /'
exit 0
