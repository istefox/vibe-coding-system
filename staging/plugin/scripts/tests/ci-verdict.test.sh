#!/bin/bash
# ci-verdict.test.sh — offline, hermetic, no network, no gh dependency. Bash 3.2 clean.
# Run: bash ci-verdict.test.sh
#
# Issue #398. `commit` Step 6b used to read `gh pr checks --watch --fail-fast`'s own exit code as
# the CI verdict: `rc=0` meant "CI green — all required checks passed." `gh` also exits 0 when the
# watch itself dies for an unrelated reason (observed live on PR #397: a TLS handshake timeout
# while `shell-tests` was still pending, `rc=0`, one of four required contexts unconcluded) — so
# the same exit code meant both "everything passed" and "stopped watching." ci-verdict.sh replaces
# that: it derives GREEN/PENDING/RED from the PR's own `statusCheckRollup`, never from a watch
# command's exit code.
#
# CV2 is the PR #397 shape verbatim — this is R-04 from the issue's own success criteria: "an
# assertion seen RED against a fixture that simulates a dead watch with a pending context, with
# its plant declared in the registry."
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
CV="$SCRIPTS/ci-verdict.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "DID NOT RUN: jq not found — ci-verdict.sh cannot be exercised"
  exit 3
fi

verdict_of() { printf '%s\n' "$1" | grep '^VERDICT: ' | head -1 | sed 's/^VERDICT: //'; }

run() {
  # run <json> [required-file]
  if [ -n "${2:-}" ]; then
    printf '%s' "$1" | bash "$CV" --required "$2"
  else
    printf '%s' "$1" | bash "$CV"
  fi
}

# ==================================================================================================
# CV1 — all checks concluded and successful -> GREEN.
# ==================================================================================================
ALL_GREEN='[{"context":"lint","status":"COMPLETED","conclusion":"SUCCESS"},
            {"context":"tests","status":"COMPLETED","conclusion":"SUCCESS"}]'
out=$(run "$ALL_GREEN")
if [ "$(verdict_of "$out")" = "GREEN" ]; then
  ok "CV1: all-concluded, all-successful rollup -> GREEN"
else
  bad "CV1: expected GREEN, got: $out"
fi

# ==================================================================================================
# CV2 — THE BUG. The exact PR #397 shape: three required contexts concluded successfully, one
# (shell-tests) still IN_PROGRESS. A watch command dying here still exits 0 — but the rollup itself
# says PENDING, and that is what must win, never GREEN.
# plant: CV2 | plugin/scripts/ci-verdict.sh | elif [ -n "$pending_names" ] || [ "$check_count" -eq 0 ]; then | elif false; then
# ==================================================================================================
DEAD_WATCH='[{"context":"lint","status":"COMPLETED","conclusion":"SUCCESS"},
             {"context":"build","status":"COMPLETED","conclusion":"SUCCESS"},
             {"context":"tests","status":"COMPLETED","conclusion":"SUCCESS"},
             {"context":"shell-tests","status":"IN_PROGRESS","conclusion":null}]'
out=$(run "$DEAD_WATCH")
if [ "$(verdict_of "$out")" = "PENDING" ] && printf '%s\n' "$out" | grep -qxF "PENDING: shell-tests"; then
  ok "CV2: dead-watch shape (PR #397) — one required context still unconcluded -> PENDING, never GREEN"
else
  bad "CV2: expected PENDING with shell-tests named, got: $out"
fi

# ==================================================================================================
# CV3 — a concluded, unsuccessful check -> RED, even with the rest green.
# ==================================================================================================
ONE_FAILED='[{"context":"lint","status":"COMPLETED","conclusion":"SUCCESS"},
             {"context":"tests","status":"COMPLETED","conclusion":"FAILURE"}]'
out=$(run "$ONE_FAILED")
if [ "$(verdict_of "$out")" = "RED" ] && printf '%s\n' "$out" | grep -qxF "FAILED: tests"; then
  ok "CV3: one concluded FAILURE among successes -> RED, names the failing check"
else
  bad "CV3: expected RED with tests named, got: $out"
fi

# ==================================================================================================
# CV4 — a failed check takes precedence over an unrelated still-pending one (a definite failure is
# actionable now; withholding it behind an unrelated running check would just delay the human).
# ==================================================================================================
FAILED_AND_PENDING='[{"context":"tests","status":"COMPLETED","conclusion":"FAILURE"},
                     {"context":"build","status":"QUEUED","conclusion":null}]'
out=$(run "$FAILED_AND_PENDING")
if [ "$(verdict_of "$out")" = "RED" ]; then
  ok "CV4: FAILED + PENDING together -> RED (a concluded failure is not hidden behind a slow check)"
else
  bad "CV4: expected RED, got: $out"
fi

# ==================================================================================================
# CV5 — legacy StatusContext objects (`state`, no `status`/`conclusion`) are classified too, not
# silently dropped: ERROR/FAILURE -> failed, PENDING/EXPECTED -> pending, SUCCESS -> ok.
# ==================================================================================================
LEGACY_ERROR='[{"context":"legacy-ctx","state":"ERROR"}]'
out=$(run "$LEGACY_ERROR")
if [ "$(verdict_of "$out")" = "RED" ] && printf '%s\n' "$out" | grep -qxF "FAILED: legacy-ctx"; then
  ok "CV5: legacy StatusContext state=ERROR -> RED, named"
else
  bad "CV5: expected RED with legacy-ctx named, got: $out"
fi

LEGACY_PENDING='[{"context":"legacy-ctx","state":"PENDING"}]'
out=$(run "$LEGACY_PENDING")
if [ "$(verdict_of "$out")" = "PENDING" ]; then
  ok "CV6: legacy StatusContext state=PENDING -> PENDING"
else
  bad "CV6: expected PENDING, got: $out"
fi

# ==================================================================================================
# CV7 — an empty rollup (no checks reported at all yet) is PENDING, never GREEN by default (rule 7:
# guard the denominator, not only the matches — zero checks is not "zero failures, all clear").
# ==================================================================================================
out=$(run '[]')
if [ "$(verdict_of "$out")" = "PENDING" ]; then
  ok "CV7: empty rollup (no checks reported yet) -> PENDING, not GREEN"
else
  bad "CV7: expected PENDING, got: $out"
fi

# ==================================================================================================
# CV8 — required-context filtering: an unrequired check's failure does not flip the verdict; a
# required check's failure does, even amid other unrequired failures.
# ==================================================================================================
MIXED='[{"context":"required-one","status":"COMPLETED","conclusion":"SUCCESS"},
        {"context":"optional-lint","status":"COMPLETED","conclusion":"FAILURE"}]'
REQ_FILE="$TMP/required.txt"
printf 'required-one\n' >"$REQ_FILE"
out=$(run "$MIXED" "$REQ_FILE")
if [ "$(verdict_of "$out")" = "GREEN" ]; then
  ok "CV8: a failing check outside the required-contexts file does not block GREEN"
else
  bad "CV8: expected GREEN (only required-one is required), got: $out"
fi

REQ_FILE2="$TMP/required2.txt"
printf 'optional-lint\n' >"$REQ_FILE2"
out=$(run "$MIXED" "$REQ_FILE2")
if [ "$(verdict_of "$out")" = "RED" ]; then
  ok "CV9: a failing check that IS in the required-contexts file blocks the verdict"
else
  bad "CV9: expected RED, got: $out"
fi

# ==================================================================================================
# CV10 — DID-NOT-RUN (rule 4): unparseable input never reads as a clean GREEN. Exit code carries
# the distinction, same convention as ci-tier.sh's own exit 3.
# ==================================================================================================
out=$(printf 'not json' | bash "$CV" 2>&1); rc=$?
if [ "$rc" -eq 3 ] && printf '%s\n' "$out" | grep -q '^DID-NOT-RUN:'; then
  ok "CV10: unparseable statusCheckRollup input -> exit 3, DID-NOT-RUN, never a silent GREEN"
else
  bad "CV10: expected exit 3 with DID-NOT-RUN, got rc=$rc out=$out"
fi

# ==================================================================================================
# Z1 — assertion-count floor (rule 10: a vacuity guard, not the primary check).
# ==================================================================================================
Z1_FLOOR=10
if [ "$((PASS + FAIL))" -ge "$Z1_FLOOR" ]; then
  ok "Z1: assertion count $((PASS + FAIL)) >= floor $Z1_FLOOR"
else
  bad "Z1: assertion count $((PASS + FAIL)) < floor $Z1_FLOOR — assertions vanished"
fi

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
