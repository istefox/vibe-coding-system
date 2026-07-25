#!/bin/bash
# pairs-completeness test harness (ADR-0024, extended by ADR-0043) — two structural checks, in
# opposite directions:
#   1. every PAIRS src exists under staging/  (ADR-0024, the original check)
#   2. every file in the covered staging subtrees appears as a PAIRS src  (ADR-0043, issue #93)
# Direction 2 exists because direction 1 cannot see the failure that motivated it: PR #90's fix to
# architect.md never deployed, because no agent file was in PAIRS at all. A file missing FROM the
# list is invisible to a check that only validates the list's own entries. Nothing failed, nothing
# looked wrong, and the deployed agent kept a stale line for half a day.
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

# check_complete <pairs-file> <staging-relative-dir> <name-pattern>
# The reverse direction (ADR-0043): asserts every file matching <name-pattern> under
# <staging-relative-dir> appears as a src on some PAIRS line. Compares the staging-relative path
# exactly as PAIRS spells it, so a typo'd entry counts as missing rather than as coverage.
# <name-pattern> may span a directory level (e.g. '*/SKILL.md'), which is why the relative path is
# derived by stripping the staging prefix rather than by basename — the first version flattened
# skills/<name>/SKILL.md to skills/SKILL.md and would have reported every skill as uncovered.
check_complete() {
  _file="$1"; _dir="$2"; _pat="$3"
  for _f in "$STAGING/$_dir"/$_pat; do
    [ -f "$_f" ] || continue                       # unexpanded glob when a dir is empty
    _rel="${_f#$STAGING/}"
    if cut -d'|' -f1 < "$_file" | grep -qxF "$_rel"; then
      PASS=$((PASS+1)); printf 'PASS: covered by PAIRS: %s\n' "$_rel"
    else
      FAIL=$((FAIL+1)); printf 'FAIL: in staging but not in PAIRS (edits will never deploy): %s\n' "$_rel"
    fi
  done
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

# --- self-test 2 (ADR-0043): prove the reverse checker detects an UNLISTED staging file ------------
# Without this the new check could pass vacuously — a glob that matches nothing reports nothing, and
# a silent zero-file check reads exactly like full coverage. Point it at a real, non-empty subtree
# with an empty PAIRS list: every file there must be reported missing.
PASS=0; FAIL=0
: > "$tmp/empty-pairs"
check_complete "$tmp/empty-pairs" "plugin/agents" '*.md' > "$tmp/self-test-2.out"
_agent_count=$(ls -1 "$STAGING/plugin/agents"/*.md 2>/dev/null | wc -l | tr -d ' ')

if [ "$_agent_count" -gt 0 ] && [ "$PASS" -eq 0 ] && [ "$FAIL" -eq "$_agent_count" ]; then
  printf 'ok   self-test 2: reverse checker flags every unlisted staging file (FAIL=%s)\n' "$FAIL"
else
  printf 'FAIL self-test 2: reverse checker did not flag the unlisted fixture (files=%s PASS=%s FAIL=%s)\n' \
    "$_agent_count" "$PASS" "$FAIL"
  exit 1
fi

# reset counters before the real check
PASS=0; FAIL=0

# --- real check: every PAIRS src in sync-to-claude.sh must exist under staging/ --------------------
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNC" > "$tmp/real-pairs"
check_pairs "$STAGING" "$tmp/real-pairs"

# --- real check, reverse direction (ADR-0043, issue #93) ------------------------------------------
# Covered subtrees: the two whose files reach ~/.claude ONLY through docs/RUNBOOK.md Step 6's bulk
# `cp`, which is a full-install procedure nobody runs to ship a one-line frontmatter fix.
# staging/plugin/hooks/hooks.json is deliberately NOT covered: it has no deployed counterpart at all,
# so a PAIRS entry would create a file that has never existed there. That is a deployment decision,
# not a completeness fix — ADR-0043 Consequences.
check_complete "$tmp/real-pairs" "plugin/agents" '*.md'
check_complete "$tmp/real-pairs" "user/rules" '*.md'
# Skills: SKILL.md only, not the scripts/ and tests/ files under each skill. Those are vendored
# selectively by design (ADR-0024 scope), so demanding an entry for each would report intended
# absences as defects. A skill's SKILL.md is the file that always has to reach the machine.
check_complete "$tmp/real-pairs" "plugin/skills" '*/SKILL.md'

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
