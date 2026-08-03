#!/bin/bash
# batch-dispatch-openers.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash batch-dispatch-openers.test.sh
#
# Issue #242 / ADR-0100. Step 5's pre-dispatch block computes
#
#     tasks=$(plan-tasks.sh --count "<plan>")
#
# for one decision — `tasks = 0` → refuse — which is exactly what ADR-0069 built it for. Twelve
# lines later the Agent-tool fallback opens with a SECOND, different decision, "Batch-dispatch
# policy (>=6 tasks in plan) … split into batches of 2-3 tasks", and names no source for the
# number. The only task count in scope is `$tasks`, and ADR-0069 §D2 says in terms that this is the
# one thing it must not be used for:
#
#   "The count over-counts on purpose … Correct for a `>= 1` guard, wrong for anything that needs a
#    real task count or a task block."
#
# ONE NUMBER SILENTLY SERVED TWO QUESTIONS. That is the defect; the batching arithmetic is the
# symptom.
#
# MEASURED, AND WIDER THAN THE ISSUE STATES. The issue calls it "benign on this plan by luck".
# Across the 58 plans in docs/superpowers/plans/: `--count` and the opener count diverge on **51**,
# and **all 51** are `>= 6` and over-counted. On #222's plan the two are 38 and 7 — batches of 2-3
# over 38 means dispatching a tester and a coder against tasks 8 through 38, which do not exist.
# The threshold branch is the same either way, which is why nothing showed until the arithmetic.
#
# AND THE OBVIOUS FIX INTRODUCES A NEW FAILURE THE ISSUE DOES NOT MENTION. Two plans have
# `openers = 0` while `--count` is non-zero, because they use a different word for a task —
# `### T1 —` and `### Step 0 —`, the two forms ADR-0070 §PTG9 and ADR-0069 §PTE2 already exempt by
# name. `deep-refactor-skill.md` counts 36 and opens 0. Consuming openers naively turns an
# over-batching bug into a batch-nothing bug, so the zero case dispatches as a single block and
# says why (BO7).
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: BO1 | plugin/skills/concept-to-code/scripts/plan-task-predicate.awk | return rest ~ /^[Tt]ask[ \t]+[0-9]+/ | return 1
# plant: BOV1 | plugin/skills/concept-to-code/scripts/plan-task-predicate.awk | return rest ~ /^[Tt]ask[ \t]+[0-9]+/ | return rest ~ /^([Tt]ask|[Ss]tep)[ \t]+[0-9]+|^T[0-9]+[ \t]/
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
PT="$STAGING/plugin/skills/concept-to-code/scripts/plan-tasks.sh"
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
PLANS="$REPO/docs/superpowers/plans"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$PT" ] || { echo "FATAL: missing $PT"; exit 1; }
[ -f "$CC" ] || { echo "FATAL: missing $CC"; exit 1; }

REF="$PLANS/2026-07-30-222-vendor-deployed-only-skills.md"

# ===========================================================================
# BO0 — the corpus premise, derived. A glob that stops resolving reports agreement everywhere.
# ===========================================================================
PLAN_N=$(ls "$PLANS"/*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$PLAN_N" -ge 50 ]; then ok "BO0 plan corpus non-vacuous ($PLAN_N plans)"
else bad "BO0 plan corpus is $PLAN_N (expected >= 50) — BO4 asserts nothing"; fi

if [ -f "$REF" ]; then ok "BO0b the reference plan the issue measured still exists"
else bad "BO0b $REF is gone — BO1/BO3 lose their subject"; fi

# ===========================================================================
# BO1..BO3 — the second mode exists, is right, and did not disturb the first.
# ===========================================================================
co=$(bash "$PT" --count-openers "$REF" 2>/dev/null); co_rc=$?
if [ "$co_rc" -eq 0 ] && [ "${co:-}" = "7" ]; then
  ok "BO1 --count-openers returns 7 on the reference plan (real ## Task N headings)"
else
  bad "BO1 --count-openers returned '${co:-}' rc=$co_rc on the reference plan; expected 7 (#242)"
fi

c=$(bash "$PT" --count "$REF" 2>/dev/null); c_rc=$?
if [ "$c_rc" -eq 0 ] && [ "${c:-}" = "38" ]; then
  ok "BO2 (forward guard) --count still returns 38 — the >= 1 guard is untouched"
else
  bad "BO2 --count returned '${c:-}' rc=$c_rc; the malformed-plan guard's answer changed"
fi

bash "$PT" --count-openers >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok "BO3 --count-openers with no plan file exits 2 (bad invocation)"
else bad "BO3 expected exit 2 on a missing argument, got $rc"; fi

bash "$PT" --count-openers "$TMP/nope.md" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then ok "BO3b an unreadable plan exits 2, not 0-with-zero"
else bad "BO3b expected exit 2 on an unreadable plan, got $rc"; fi

# The did-not-run channel must survive the new mode: a broken predicate is not "no tasks".
FAKE="$TMP/fake"; mkdir -p "$FAKE"
cp "$PT" "$FAKE/plan-tasks.sh"
printf '%s\n' 'this is not awk {{{' >"$FAKE/plan-task-predicate.awk"
bash "$FAKE/plan-tasks.sh" --count-openers "$REF" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 3 ]; then ok "BO3c a broken predicate exits 3 — the check DID NOT RUN, distinct from 0"
else bad "BO3c expected exit 3 with a broken predicate, got $rc — a broken awk would read as 'no tasks'"; fi

# ===========================================================================
# BO4 — the measured premise, re-derived here so a later reader is not trusting a number in prose.
# ===========================================================================
DIV=0; OVER=0; ZERO=""
for p in "$PLANS"/*.md; do
  [ -f "$p" ] || continue
  _c=$(bash "$PT" --count "$p" 2>/dev/null); _o=$(bash "$PT" --count-openers "$p" 2>/dev/null)
  [ -n "${_c:-}" ] && [ -n "${_o:-}" ] || continue
  [ "$_c" != "$_o" ] && DIV=$((DIV + 1))
  if [ "$_c" -ge 6 ] && [ "$_o" -lt "$_c" ]; then OVER=$((OVER + 1)); fi
  if [ "$_o" -eq 0 ] && [ "$_c" -ge 1 ]; then ZERO="$ZERO $(basename "$p")"; fi
done
if [ "$DIV" -ge 40 ]; then
  ok "BO4 the two counts diverge on $DIV of $PLAN_N plans, $OVER of them >= 6 and over-counted"
else
  bad "BO4 divergence is $DIV of $PLAN_N — the premise this fix rests on no longer holds; re-measure before trusting ADR-0100"
fi

# ===========================================================================
# BO5 — the zero-opener population is known and named, not a surprise at dispatch time.
# ===========================================================================
if [ -n "$ZERO" ]; then
  ok "BO5 zero-opener plans exist and are what BO7's branch is for:$ZERO"
else
  bad "BO5 no zero-opener plan found — BO7's branch is now untestable against the real corpus; confirm the two exempted forms still exist"
fi
if [ -f "$PLANS/2026-05-30-deep-refactor-skill.md" ]; then
  ok "BO5b the ### T1 — plan still exists (ADR-0070 §PTG9's exemption, and BO5's subject)"
else
  bad "BO5b the ### T1 — plan is gone; BO5's exemption outlived its subject"
fi
# BOV1 (vacuity assertion, ADR-0121 §D2): BO5b asserts the ### T1 plan still EXISTS. BO5 already
# asserts the zero-opener POPULATION is non-empty; BOV1 is the per-name half, which is what goes
# stale silently — reword this one plan to `### Task N` and BO5/BO5b both stay green while the
# zero-opener branch (BO7) has lost its real subject. Kept SEPARATE from BO5b on purpose: "the
# file is gone" and "the file no longer needs exempting" want different remedies.
bov1_o=$(bash "$PT" --count-openers "$PLANS/2026-05-30-deep-refactor-skill.md" 2>/dev/null); bov1_rc=$?
{ [ "$bov1_rc" -eq 0 ] && [ "$bov1_o" = "0" ]; } \
  && ok "BOV1 (exemption still needed): the ### T1 plan still returns 0 openers" \
  || bad "BOV1: the ### T1 plan now returns openers=$bov1_o rc=$bov1_rc — the zero-opener branch has lost its real subject"

# ===========================================================================
# BO6..BO8 — the call sites. Prose matched flat and undecorated (ADR-0098's rule).
# ===========================================================================
FLAT=$(tr '\n' ' ' <"$CC" | tr -d '`*' | tr -s ' ')

if printf '%s\n' "$FLAT" | grep -q 'count-openers'; then
  ok "BO6 SKILL.md consumes --count-openers"
else
  bad "BO6 SKILL.md never calls --count-openers — the batching still consumes the guard count (#242)"
fi

if printf '%s\n' "$FLAT" | grep -q 'Two counts, two questions'; then
  ok "BO7 the pre-dispatch block states which decision uses which count"
else
  bad "BO7 nothing at the call site distinguishes the two counts — one number silently serving two questions is the defect itself"
fi

if printf '%s\n' "$FLAT" | grep -q 'dispatch as a single block'; then
  ok "BO8 the zero-opener case dispatches as one block rather than computing zero batches"
else
  bad "BO8 no zero-opener branch — consuming openers naively turns over-batching into batch-nothing on the two exempted plan forms"
fi

# ===========================================================================
# BO9 — the issue asked whether the Workflow path consumes the same number. Measured: it does not,
# it derives task GROUPS by reading the plan. Asserted so the answer does not have to be re-derived.
# ===========================================================================
W_A=$(grep -n '^#### Workflow dispatch path — Step 5 implementation' "$CC" | head -1 | cut -d: -f1)
W_B=$(grep -n '^#### Merge-back and base-fork audit' "$CC" | head -1 | cut -d: -f1)
if [ -n "${W_A:-}" ] && [ -n "${W_B:-}" ] && [ "$W_B" -gt "$W_A" ]; then
  ok "BO9 the Workflow dispatch section anchors resolve ($W_A..$W_B)"
  WBLK=$(awk -v a="$W_A" -v b="$W_B" 'NR>a && NR<b' "$CC")
  if printf '%s\n' "$WBLK" | grep -q 'plan-tasks.sh'; then
    bad "BO9b the Workflow path now consumes a numeric task count — it derived task GROUPS from the plan, and #242's defect is a count serving a second question"
  else
    ok "BO9b (forward guard) the Workflow path consumes no numeric task count"
  fi
else
  bad "BO9 the Workflow dispatch anchors did not resolve; BO9b asserts nothing"
  bad "BO9b (not evaluated)"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 13 ]; then ok "Z1 assertion-count floor ($_total >= 13)"
else bad "Z1 assertion count fell to $_total (floor 13) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
