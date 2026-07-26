#!/bin/bash
# agent-metrics.sh v1.0 — cheap, computed-not-self-reported diff metrics for issue #118
# (ADR-0064: agent-level instrumentation). Two of the ADR's four metrics live here
# (test_count_delta, deleted_lines); the other two (iteration_count, elapsed_wall_seconds)
# are pure orchestrator bookkeeping — a dispatch count and a date(1) delta — and need no script,
# per the SKILL.md "Task-level metrics — Step 5 checkpoints (ADR-0064)" block.
#
# CONTRACT. Always exits 0. Reads a FULL unified diff from stdin — the SAME diff already piped
# into weakening-scan.sh and interface-immutability.sh at this checkpoint (git diff "$_pre5"),
# not a second git call and not --stat/--numstat. Prints exactly two TAB-separated lines, always:
#   DELETED_LINES<TAB><non-negative int>
#   TEST_COUNT_DELTA<TAB><signed int>
#
# THIS SCRIPT MEASURES, IT DOES NOT REPORT A FINDING. There is no CLEAN sentinel and no
# could-not-determine case: a genuinely empty diff legitimately produces two zero lines, and that
# zero is real (ADR-0064 §D3 — a task that changed nothing really did delete 0 lines). The
# absent-vs-zero distinction is the CALLER's responsibility, at the resolution step, not in this
# script's output: if agent-metrics.sh does not resolve at the two-location lookup, the caller
# omits both fields from step5-report.json entirely rather than invoking this script and treating
# its absence as 0 — see concept-to-code/SKILL.md, same "_x=\"\" on failure" idiom every sibling
# reporter (weakening-scan.sh, diff-budget-check.sh) already uses.
#
# TEST-FILE PREDICATE reused verbatim from test-write-scope.sh (ADR-0049 §D4 — the "broad union
# minus .md" DENIAL predicate), deliberately NOT spec-coverage.sh's narrower DISCOVERY predicate
# in the same directory. ADR-0049 §D4: the two diverge on purpose because their error directions
# are opposite — a discovery predicate must not over-match (a false coverage pass), a denial
# predicate must not under-match (a missed test path is invisible). Counting tests shares the
# denial predicate's failure direction: a test file this predicate silently missed would make a
# real test-count DROP invisible in this metric — exactly the "manufacture a well-behaved-looking
# task" failure §D3 already names for the absent-vs-zero case, just via under-matching instead of
# zero-defaulting. So the broad/denial predicate is the one that fits *counting* tests, not the
# narrow/discovery one.
#
# CHAIN-OWNED EXCLUSIONS, the same three basenames diff-budget-check.sh excludes (ADR-0052 §D4):
# SPEC.md, step5-report.json, any *.manifest.yml — files the chain itself writes, never the
# coder's own work, must not inflate either metric. (SPEC.md is also never test-shaped under the
# predicate above — *.md is excluded first, unconditionally — so this exclusion only has bite for
# step5-report.json and *.manifest.yml in practice; kept explicit rather than relying on the
# predicate's own .md carve-out, matching diff-budget-check.sh's own explicit three-name list.)
#
# Bash 3.2 clean: no assoc arrays, no mapfile, no process substitution, no <<<.
set -u

DIFF_IN=$(cat)

printf '%s\n' "$DIFF_IN" | awk '
function basename(p,   n, a) { n = split(p, a, "/"); return a[n] }
function is_chain_owned(p,   bn) {
  bn = basename(p)
  if (bn == "SPEC.md" || bn == "step5-report.json") return 1
  if (bn ~ /\.manifest\.yml$/) return 1
  return 0
}
function is_test_path(p,   bn) {
  if (p ~ /\.md$/) return 0
  if (p ~ /(^|\/)tests\//) return 1
  if (p ~ /(^|\/)test\//) return 1
  if (p ~ /(^|\/)spec\//) return 1
  bn = basename(p)
  if (bn ~ /\.test\./) return 1
  if (bn ~ /\.spec\./) return 1
  if (bn ~ /^test_/) return 1
  if (bn ~ /_test\./) return 1
  if (bn ~ /Test\./) return 1
  if (bn ~ /Tests\./) return 1
  if (bn ~ /^test-.*\.sh$/) return 1
  if (bn == "run-tests.sh") return 1
  return 0
}
BEGIN { old=""; new=""; file=""; owned=0; deleted_lines=0; added_test=0; removed_test=0 }
/^--- / {
  old = $2
  sub(/^a\//, "", old)
  next
}
/^\+\+\+ / {
  new = $2
  sub(/^b\//, "", new)
  file = (new != "/dev/null") ? new : old
  owned = is_chain_owned(file)
  if (!owned && is_test_path(file)) {
    if (old == "/dev/null" && new != "/dev/null") added_test++
    if (new == "/dev/null" && old != "/dev/null") removed_test++
  }
  next
}
/^---/ { next }
/^-/ {
  if (!owned) deleted_lines++
  next
}
END {
  print "DELETED_LINES\t" deleted_lines
  print "TEST_COUNT_DELTA\t" (added_test - removed_test)
}
'
exit 0
