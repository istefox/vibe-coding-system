#!/bin/bash
# pairs-completeness test harness (ADR-0024) — structural check: every PAIRS src exists under staging/.
# This is a "self-test the checker" harness (see the plan's rationale): there is no live PAIRS defect to
# drive a real RED against, so it first proves the check function itself detects a missing file against a
# synthetic broken fixture, then runs the same check against the real PAIRS block in sync-to-claude.sh.
# It does NOT compare against ~/.claude (deliberately — see ADR-0024 §3.4): staging is expected to move
# ahead of deployed as the audit-fix roadmap lands fixes.
# Bash 3.2 clean. Run: bash pairs-completeness.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
SYNC="$STAGING/sync-to-claude.sh"

PASS=0; FAIL=0

# check_pairs <base-dir> <pairs-file>
# Reads src|dst lines from <pairs-file>, asserts <base-dir>/<src> exists as a file.
# Updates the global PASS/FAIL counters and prints PASS: <src> / FAIL: <src> per line.
check_pairs() {
  _base="$1"; _file="$2"
  while IFS='|' read -r src dst; do
    [ -z "$src" ] && continue
    if [ -f "$_base/$src" ]; then
      PASS=$((PASS+1)); printf 'PASS: %s\n' "$src"
    else
      FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$src"
    fi
  done < "$_file"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- self-test: prove the checker detects a missing PAIRS src (real RED) --------------------------
printf 'does/not/exist.sh|hooks/does-not-exist.sh\n' > "$tmp/broken-pairs"
check_pairs "$tmp" "$tmp/broken-pairs" > "$tmp/self-test.out"

if [ "$PASS" -eq 0 ] && [ "$FAIL" -eq 1 ] && grep -q '^FAIL: does/not/exist.sh$' "$tmp/self-test.out"; then
  printf 'ok   self-test: checker detects a missing PAIRS src (FAIL=1)\n'
else
  printf 'FAIL self-test: checker did not detect the broken fixture (PASS=%s FAIL=%s)\n' "$PASS" "$FAIL"
  exit 1
fi

# reset counters before the real check
PASS=0; FAIL=0

# --- real check: every PAIRS src in sync-to-claude.sh must exist under staging/ --------------------
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNC" > "$tmp/real-pairs"
check_pairs "$STAGING" "$tmp/real-pairs"

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
