#!/bin/bash
# step5-checkpoint-review.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Covers ADR-0039 D5-D9: the per-task checkpoint review in c2c Step 5.
# Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash step5-checkpoint-review.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
CC_SKILL="$STAGING/plugin/skills/concept-to-code/SKILL.md"
CC_SCRIPTS="$STAGING/plugin/skills/concept-to-code/scripts"
INIT="$CC_SCRIPTS/manifest-init.sh"
VALIDATE="$CC_SCRIPTS/manifest-validate.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# =====================================================================================
# A. manifest-init.sh writes the field, defaulted to none (D8 as amended: opt-in, not
# 'checkpoint on 3+ task plans' — the ADR calls that threshold an unmeasured guess).
# manifest-init.sh <topic-slug> <topic-full-title> <project-root> [mode]; it computes the path
# itself as <root>/docs/manifests/<YYYY-MM-DD>-<slug>.manifest.yml, so resolve it by glob rather
# than by recomputing today's date (a run across midnight would break a date-literal match).
mkdir -p "$TMP/proj"
bash "$INIT" "test-topic" "Test Topic" "$TMP/proj" >/dev/null 2>&1
M1=$(ls "$TMP/proj/docs/manifests/"*-test-topic.manifest.yml 2>/dev/null | head -1)
cp "$M1" "$TMP/m1.yml" 2>/dev/null
if [ -n "$M1" ] && grep -q '^step5_review_mode: none$' "$TMP/m1.yml"; then
  ok "A1: manifest-init writes 'step5_review_mode: none'"
else
  bad "A1: field missing or not defaulted to none"
fi

# The flip instruction must be discoverable from the manifest itself: there is no gate for
# this field, so the comment is the only place a human learns how to turn it on.
# manifest-set-flag.sh only accepts true|false, so it cannot set this field. The comment must
# carry the sed form instead, or a human would follow an instruction that fails.
if grep -q "step5_review_mode: checkpoint" "$TMP/m1.yml" \
   && grep -q "only accepts true|false" "$TMP/m1.yml"; then
  ok "A2: manifest carries the opt-in instruction as a comment"
else
  bad "A2: opt-in instruction missing from the generated manifest"
fi

# =====================================================================================
# B. manifest-validate.sh invariant 14.
# B1: the freshly generated manifest (value 'none') validates.
if bash "$VALIDATE" "$TMP/m1.yml" >/dev/null 2>&1; then
  ok "B1: manifest with step5_review_mode=none validates"
else
  bad "B1: none rejected"
fi

# B2: 'checkpoint' validates.
sed 's/^step5_review_mode: none$/step5_review_mode: checkpoint/' "$TMP/m1.yml" > "$TMP/m2.yml"
if bash "$VALIDATE" "$TMP/m2.yml" >/dev/null 2>&1; then
  ok "B2: manifest with step5_review_mode=checkpoint validates"
else
  bad "B2: checkpoint rejected"
fi

# B3: an arbitrary value is rejected, and the message names the field.
sed 's/^step5_review_mode: none$/step5_review_mode: aggressive/' "$TMP/m1.yml" > "$TMP/m3.yml"
OUT3=$(bash "$VALIDATE" "$TMP/m3.yml" 2>&1); RC3=$?
if [ "$RC3" -ne 0 ] && printf '%s' "$OUT3" | grep -q 'step5_review_mode'; then
  ok "B3: arbitrary value rejected, message names the field"
else
  bad "B3: arbitrary value accepted or message unclear (rc=$RC3)"
fi

# B4 (retrocompat pin, the one that matters): a manifest with the field entirely absent must
# still validate. Every manifest written before ADR-0039 lacks it, and absent means 'none'.
# If this ever goes red, the field stopped being additive and needs a migration.
grep -v '^step5_review_mode:' "$TMP/m1.yml" > "$TMP/m4.yml"
if bash "$VALIDATE" "$TMP/m4.yml" >/dev/null 2>&1; then
  ok "B4: manifest without the field still validates (pre-ADR-0039 retrocompat)"
else
  bad "B4: absent field rejected — the field is no longer additive"
fi

# =====================================================================================
# C. SKILL.md anchors. Both dispatch paths must gate on the same field, or a chain would
# behave differently depending on whether hook_verified flipped the Workflow path on.
if grep -q 'IF manifest.step5_review_mode = checkpoint' "$CC_SKILL"; then
  ok "C1: Workflow dispatch path carries the conditional block"
else
  bad "C1: Workflow path conditional block missing"
fi

if grep -q 'IF `manifest.step5_review_mode = checkpoint`' "$CC_SKILL"; then
  ok "C2: Agent-tool fallback path carries the conditional block"
else
  bad "C2: fallback path conditional block missing"
fi

# C3 (D6): the Workflow instruction must name pipeline() and must forbid parallel() as a
# barrier. A barrier here would serialize what Step 5 exists to parallelize.
if grep -q 'Build the script with pipeline()' "$CC_SKILL" \
   && grep -q 'Do NOT use parallel() as a barrier' "$CC_SKILL"; then
  ok "C3: Workflow stage is a pipeline, barrier explicitly forbidden (D6)"
else
  bad "C3: pipeline/barrier instruction missing or incomplete"
fi

# C4 (D5 as amended): review-only. The checkpoint must not fix anything — the fix cycle stays
# in RTF at Step 6. Both paths state it.
N_REVIEW_ONLY=$(grep -c 'reviews only and fixes nothing\|REVIEWS ONLY and fixes nothing' "$CC_SKILL")
if [ "$N_REVIEW_ONLY" -ge 2 ]; then
  ok "C4: both paths state the checkpoint is review-only ($N_REVIEW_ONLY sites)"
else
  bad "C4: review-only contract stated at only $N_REVIEW_ONLY site(s), expected 2"
fi

# C5 (D7 as amended): the severity vocabulary is the one `reviewer` actually emits. The ADR
# text says P1/P2/P3, which comes from deep-refactor (ADR-0018) and does not exist on this path.
if grep -q 'BLOCKER and MAJOR findings into the prompt of the next task' "$CC_SKILL" \
   && ! grep -q 'P1 and P2 findings are fixed before the next task' "$CC_SKILL"; then
  ok "C5: uses BLOCKER/MAJOR, not the P1/P2 vocabulary from deep-refactor"
else
  bad "C5: severity vocabulary wrong or the P1/P2 phrasing leaked into SKILL.md"
fi

# =====================================================================================
# D. step5-report.json schema and the orchestrator read contract.
if grep -q '"checkpoint_reviews"' "$CC_SKILL"; then
  ok "D1: checkpoint_reviews present in the documented schema"
else
  bad "D1: checkpoint_reviews missing from the schema"
fi

# D2: it must be documented as never a failure signal. Findings were already fed forward; making
# them block would turn a feedback channel into a second gate in front of Step 6.
if grep -q 'checkpoint_reviews` is \*\*never\*\* a failure signal' "$CC_SKILL"; then
  ok "D2: read contract states checkpoint_reviews is never a failure signal"
else
  bad "D2: failure-signal exclusion not documented"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -gt 0 ] && exit 1 || exit 0
