#!/bin/bash
# step6-effort-pin.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash step6-effort-pin.test.sh
#
# Covers the Step 6 counterpart of the PR #78 effort pin. The Workflow tool inherits the
# session effort whenever opts.effort is omitted, exactly as it inherits the session model
# when model is omitted. Step 5 was pinned; Step 6 was not, so the whole review-and-fix
# cycle ran at the orchestrator's level and discarded each agent's frontmatter calibration
# (refactorer being the visible case: frontmatter medium, inherited high).
#
# Every assertion is scoped to the Step 6 workflow-dispatch block, extracted below. The
# Step 5 block already contains the phrase "omit to inherit the session effort", so a
# whole-file grep would report green while Step 6 stayed unpinned.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
CC_SKILL="$STAGING/plugin/skills/concept-to-code/SKILL.md"
AGENTS="$STAGING/plugin/agents"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Anchor on the "### Step 6" heading, NOT on "#### Workflow dispatch path (hook_verified =
# true)" — that subheading is identical in Step 5 and Step 6, so matching it would capture
# both blocks and every Step-6 assertion would be satisfiable by Step 5 text.
STEP6="$TMP/step6.md"
awk '/^### Step 6 — Review cycle/{f=1}
     /^#### Skill fallback/{f=0}
     f' "$CC_SKILL" > "$STEP6"

# Guard: if the section headings are ever renamed the extraction silently yields nothing and
# every later assertion would pass vacuously on an empty file.
if [ -s "$STEP6" ] && grep -q 'Phase 3 — Fix in parallel per file group' "$STEP6"; then
  ok "A0: Step 6 workflow-dispatch block extracted (headings unchanged)"
else
  bad "A0: extraction empty or Phase 3 missing — section headings changed, later assertions are void"
fi

# =====================================================================================
# A. The instruction line must name effort, not only model, and must carry the reason.
# Without the reason a future editor reads the pin as ceremony and drops it.
if grep -q 'pins BOTH its model and its effort explicitly' "$STEP6"; then
  ok "A1: Step 6 instruction line pins model AND effort"
else
  bad "A1: Step 6 instruction line does not pin effort"
fi

if grep -q 'omit to inherit the session effort' "$STEP6"; then
  ok "A2: the inheritance reason is stated inside the Step 6 block"
else
  bad "A2: inheritance reason missing from the Step 6 block"
fi

# =====================================================================================
# B. The two reviewer calls (Phase 1 review, Phase 4 re-review) both carry an explicit
# effort. Counting rather than grep -q: pinning one and forgetting the other is the
# realistic regression.
REV_COUNT=$(grep -c 'agentType: "reviewer", model: "sonnet", effort: "high"' "$STEP6")
if [ "$REV_COUNT" -eq 2 ]; then
  ok "B1: both reviewer dispatches pin model and effort (found 2)"
else
  bad "B1: expected 2 fully-pinned reviewer dispatches, found $REV_COUNT"
fi

# =====================================================================================
# C. Fix agents. agentType is chosen at runtime from fix_type, so the effort cannot be a
# literal — it needs a lookup keyed by the same value.
if grep -q 'const FIX_EFFORT = { debugger: "high", refactorer: "medium", coder: "high" };' "$STEP6"; then
  ok "C1: FIX_EFFORT map present with the three fix-agent types"
else
  bad "C1: FIX_EFFORT map missing or values changed"
fi

if grep -q 'effort: FIX_EFFORT\[group\[0\]\.fix_type\]' "$STEP6"; then
  ok "C2: Phase 3 dispatch resolves effort through the map"
else
  bad "C2: Phase 3 dispatch does not use FIX_EFFORT"
fi

# C3: the map must agree with the agents' own frontmatter. SKILL.md and the agent files are
# not linked — this assertion is the only thing that makes a frontmatter change surface here
# instead of being silently overridden at dispatch.
FE_MISMATCH=""
for a in debugger refactorer coder; do
  want=$(awk -F': ' '/^effort: /{print $2; exit}' "$AGENTS/$a.md")
  got=$(grep -o "$a: \"[a-z]*\"" "$STEP6" | head -1 | sed 's/.*"\(.*\)"/\1/')
  [ "$want" = "$got" ] || FE_MISMATCH="$FE_MISMATCH $a(frontmatter=$want,skill=$got)"
done
if [ -z "$FE_MISMATCH" ]; then
  ok "C3: FIX_EFFORT values match debugger/refactorer/coder frontmatter"
else
  bad "C3: FIX_EFFORT disagrees with agent frontmatter:$FE_MISMATCH"
fi

# =====================================================================================
# D. Argument order. The Workflow API is agent(prompt, opts); the Step 6 template had it
# inverted, so a script generated verbatim from it would be wrong. Step 5 was already correct.
if grep -q 'agent({ agentType' "$STEP6"; then
  bad "D1: Step 6 still calls agent(opts, prompt) — argument order inverted"
else
  ok "D1: no inverted agent({ agentType, ... }, prompt) call remains in Step 6"
fi

# =====================================================================================
# E. Non-regression: the Step 5 pin this change is modelled on must survive untouched.
# Same anchors as step5-checkpoint-review.test.sh C6/C7, checked against the whole file.
if grep -q 'Pin `effort` explicitly too' "$CC_SKILL" \
   && grep -q 'Pass an explicit model AND an explicit effort of "high"' "$CC_SKILL"; then
  ok "E1: Step 5 effort-pin anchors intact (C6/C7 non-regression)"
else
  bad "E1: Step 5 effort-pin text was disturbed by the Step 6 edit"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
