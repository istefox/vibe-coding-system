#!/bin/bash
# batch-boundary-precedence.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash batch-boundary-precedence.test.sh
#
# Issue #247 / ADR-0101. A correction to a rule shipped four hours earlier, not a defect someone
# else left. ADR-0088 §D5 states two batch-boundary rules as if they were jointly satisfiable:
#
#   1. do not put an assertion in the same batch as the task it depends on
#   2. do not split a red assertion from the task that turns it green
#
# On #222's plan they pull opposite ways. Rule 1 forces task 3 into a later batch than task 2,
# because `C7`'s RED must be "the vendored file exists but does not name gate 5.05" and the tester
# cannot observe that before task 2 vendors it. Rule 2 wants tasks 2 and 3 together, because `S1`
# reddens at task 2 and greens at task 3. **No batching satisfies both**, and ADR-0088 gave a reader
# applying them in good faith no way to choose.
#
# THE ISSUE OVERSTATES THE URGENT HALF, and measuring settled it. It says an unattended run "would
# stop, write a partial report, and present a correctly-working TDD sequence as a failure".
# `autopilot-build`'s circuit breaker reads `.claude/step5-report.json` **after dispatch** —
# once, at the end of Step 5, not per checkpoint. `S1` greens at task 3, inside Step 5, so that run
# would not have halted. The claim holds only for an expected red that survives to the END of
# Step 5, which is a plan already violating rule 2 with no task to green it. BP6/BP7 pin both
# halves: the breaker's cadence, and that it still halts on a real RED.
#
# So what is left is the documentation defect, and it is real: two rules presented as compatible,
# with no precedence and no account of what a red checkpoint means.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
AB="$STAGING/plugin/skills/autopilot-build/SKILL.md"
ADR88="$REPO/docs/architecture/ADR-0088-241-test-authoring-split-granularity.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

for _f in "$CC" "$AB" "$ADR88"; do
  [ -f "$_f" ] || { echo "FATAL: missing $_f"; exit 1; }
done

# Prose is matched case-INSENSITIVELY as well as flat and undecorated. Capitalisation is the same
# class as a line wrap, a backtick or a bold marker: a clause is the same clause whether it opens
# a sentence or sits inside one. BP3 first failed against correct text for exactly that reason —
# the seventh member of this family (ADR-0073 wrap, ADR-0076 comment marker, ADR-0080 backticks,
# ADR-0082 one-line marker, ADR-0092 self-derivation, ADR-0098 backticks again, this).
FLAT=$(tr '\n' ' ' <"$CC" | tr -d '`*' | tr -s ' ')
AB_FLAT=$(tr '\n' ' ' <"$AB" | tr -d '`*' | tr -s ' ')

# ===========================================================================
# BP0 — the block exists and is non-vacuous. Without it every prose assertion is vacuous.
# ===========================================================================
B_A=$(grep -n '^\*\*Batch boundaries are a design choice' "$CC" | head -1 | cut -d: -f1)
if [ -n "${B_A:-}" ]; then ok "BP0 the batch-boundary block anchor resolves (line $B_A)"
else bad "BP0 the batch-boundary block anchor did not resolve — it was reworded, and BP1/BP2 assert nothing"; fi

# ===========================================================================
# BP1 — forward guard: both rules survive. A precedence rule that deletes one of the two rules is
# not a precedence rule.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'do not put an assertion in the same batch as the task it depends on' \
   && printf '%s\n' "$FLAT" | grep -qi 'do not split a red assertion from the task that turns it green'; then
  ok "BP1 (forward guard) both batch-boundary rules are still stated"
else
  bad "BP1 one of the two rules is gone; #247 is about ordering them, not removing one"
fi

# ===========================================================================
# BP2 — the precedence, WITH its reason. A bare "rule 1 wins" is a coin toss written down.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'the first rule outranks the second'; then
  ok "BP2 precedence is stated"
else
  bad "BP2 no precedence between the two rules — on #222's plan they cannot both be satisfied and a reader has no way to choose (#247)"
fi

if printf '%s\n' "$FLAT" | grep -qi 'evidence quality beats checkpoint tidiness'; then
  ok "BP2b the reason for the precedence is stated, not just the verdict"
else
  bad "BP2b the precedence is asserted without its reason — violating rule 1 destroys the RED evidence, violating rule 2 only leaves a checkpoint red"
fi

# ===========================================================================
# BP3/BP4 — what a red checkpoint means. The ADR-0049 flow assumes the batch's own tests go
# red-then-green within the batch; a third-party guard whose premise a later task restores is
# neither, and the chain had no concept of it.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'an intermediate checkpoint can be legitimately red'; then
  ok "BP3 the checkpoint says an intermediate red can be legitimate"
else
  bad "BP3 the checkpoint block says nothing about what a red result means at an intermediate point (#247)"
fi

if printf '%s\n' "$FLAT" | grep -qi "this batch's own tests"; then
  ok "BP4 and it names what is NOT expected — a red in this batch's own tests"
else
  bad "BP4 the expected-red paragraph does not bound itself; without the negative half it excuses any red"
fi

# ===========================================================================
# BP5 — the correction reaches ADR-0088, which is where the two rules are recorded. Its body is not
# edited in place (ADR-0034 precedent); it gains a Correction section.
# ===========================================================================
if grep -q '^## Correction' "$ADR88" && grep -q 'ADR-0101' "$ADR88"; then
  ok "BP5 ADR-0088 carries a Correction pointing at ADR-0101"
else
  bad "BP5 ADR-0088 still states the two rules as jointly satisfiable with no correction"
fi

# ===========================================================================
# BP6/BP7 — the measured premise about autopilot-build, and the guard that it stays strict.
# ===========================================================================
if printf '%s\n' "$AB_FLAT" | grep -qi 'Circuit breaker — read .claude/step5-report.json after dispatch'; then
  ok "BP6 autopilot-build's breaker reads the report AFTER dispatch — once, not per checkpoint"
else
  bad "BP6 the breaker's cadence changed; #247's autopilot argument was measured against 'after dispatch' and must be re-measured"
fi

if printf '%s\n' "$AB_FLAT" | grep -qi 'test_result = RED → halt'; then
  ok "BP7 (forward guard) the breaker still halts on a real RED — not relaxed by this fix"
else
  bad "BP7 the breaker no longer halts on RED; #247 says explicitly it must not be relaxed without an expected-red mechanism"
fi

# ===========================================================================
# BP8 — the deferred mechanism is named rather than silently dropped, and the reason with it.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'expected-red declaration'; then
  ok "BP8 the deferred mechanism is named at the call site"
else
  bad "BP8 nothing records that a mechanism was considered and deferred; a reader cannot tell a decision from an omission"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 9 ]; then ok "Z1 assertion-count floor ($_total >= 9)"
else bad "Z1 assertion count fell to $_total (floor 9) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
