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
# Section F additionally covers the Phase 3 dispatch block's documentation: the file is now
# about that block generally, not only the effort pin it was created for.
#
# Every assertion is scoped to the Step 6 workflow-dispatch block, extracted below. The
# Step 5 block already contains the phrase "omit to inherit the session effort", so a
# whole-file grep would report green while Step 6 stayed unpinned.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
CC_SKILL="$STAGING/plugin/skills/concept-to-code/SKILL.md"
STEP5_REF="$STAGING/plugin/skills/concept-to-code/references/step5-implementation.md"
AGENTS="$STAGING/plugin/agents"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Anchor on the "### Step 6" heading rather than on the "#### Workflow dispatch path" subheading.
# The two subheadings were once identical across Step 5 and Step 6, and matching them captured
# both blocks — every Step-6 assertion was then satisfiable by Step 5 text, which is how the
# first version of this file passed A2 vacuously. They now carry distinct names
# (workflow-dispatch-pins.test.sh B4a/B4b/B5 keep them that way), but the step-level anchor is
# kept deliberately: it is the more stable of the two and does not move if a subheading is
# reworded again.
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
if grep -q 'const FIX_EFFORT = { debugger: "high", refactorer: "medium", coder: "xhigh" };' "$STEP6"; then
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
# VCS-047/ADR-0174: both anchors live physically in references/step5-implementation.md now
# (the Step 5 body moved out of SKILL.md); this stays an explicit Step-5 non-regression check.
if grep -q 'Pin `effort` explicitly too' "$STEP5_REF" \
   && grep -q 'Pass an explicit model AND an explicit effort of "high"' "$STEP5_REF"; then
  ok "E1: Step 5 effort-pin anchors intact (C6/C7 non-regression)"
else
  bad "E1: Step 5 effort-pin text was disturbed by the Step 6 edit"
fi

# =====================================================================================
# F. Phase 3 documentation. The model: "opus" override contradicts the fix agents' sonnet
# frontmatter and arrived byte-identical via the ADR-0024 vendoring commit, so it reads as
# drift unless the block says otherwise. The rationale of record lives in ADR-0018 and in
# review-triage-fix/SKILL.md:170 — Step 6 is the third site of that convention and was the
# only one not citing it.
if grep -q 'ADR-0018' "$STEP6"; then
  ok "F1: Phase 3 cites ADR-0018 for the opus override"
else
  bad "F1: opus override has no rationale pointer in Step 6"
fi

# F2: ADR-0018 argues fix phases must be sequential Agent-tool, never Workflow, partly because
# parallel fixes on a shared tree risk edit conflicts. Phase 3 uses parallel() anyway; it is
# safe only because Phase 2 grouped findings by file, so no two agents touch the same file.
# That mitigation is load-bearing and was implicit — a Phase 2 refactor could drop it blind.
if grep -q 'one file per agent' "$STEP6"; then
  ok "F2: the by-file grouping is documented as what makes parallel fixes safe"
else
  bad "F2: parallel-dispatch safety rationale missing from Phase 3"
fi

# F2b (issue #83): the grouping alone bounds where the FINDINGS are, not where the EDITS land.
# An agent fixing an import or a shared helper can write a file that was nobody's assigned file,
# and then two agents collide on it. The prompt must forbid that explicitly.
if grep -q 'edit ONLY' "$STEP6"; then
  ok "F2b: the fix-agent prompt constrains writes to its assigned file"
else
  bad "F2b: no write-scope constraint — grouping bounds findings, not edits (issue #83)"
fi

# F3: a cross-file need has to survive aggregation, so it is a structured field and not prose in
# `notes`. It must appear in BOTH schemas — the fix agent's return and step6-report.json — or the
# orchestrator never sees what the agent deferred.
F3N=$(grep -c '"deferred"' "$STEP6")
if [ "$F3N" -ge 2 ]; then
  ok "F3: deferred present in both the fix-agent return and the step6-report schema"
else
  bad "F3: expected deferred in 2 schemas, found $F3N occurrence(s)"
fi

# =====================================================================================
# G. Issue #412 — Step 6's dispatch selection is unconditional; the Workflow path documents its
# own unreachability rather than being deleted (ADR-0129 §D6 precedent).
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# plant: G1 | plugin/skills/concept-to-code/SKILL.md | governs Step 5's dispatch path only (issue #412, ADR-0164) | selects Step 6 too: if hook_verified = true, use Workflow dispatch path
# plant: G2 | plugin/skills/concept-to-code/SKILL.md | **Dispatch: always the skill fallback (below).** | **Dispatch: use the skill fallback (below) when appropriate.**
# plant: G3 | plugin/skills/concept-to-code/SKILL.md | **never `"workflow"`.** | **sometimes `"workflow"`.**
# plant: G4 | plugin/skills/concept-to-code/SKILL.md | #### Workflow dispatch path — Step 6 review cycle (NOT SELECTED — see above, issue #412) | #### Workflow dispatch path — Step 6 review cycle (hook_verified = true)
# =====================================================================================

# G1: no hook_verified BRANCH survives in the dispatch-selection line(s) at the top of Step 6 — a
# conditional of the shape "If `manifest.hook_verified` = ...: use ...". Scoped to the selection
# paragraph only (before the first #### subheading). The word itself legitimately still appears
# there, explaining that hook_verified now governs Step 5 alone (issue #412) — this checks for the
# CONDITIONAL construct, not for the word's absence, or that explanatory sentence would fail it.
SELECTION=$(awk '/^### Step 6 — Review cycle/{f=1} /^####/{f=0} f' "$CC_SKILL")
if [ -n "$SELECTION" ]; then
  ok "G0: Step 6's dispatch-selection paragraph is extractable (the anchor G1/G2 below read)"
else
  bad "G0: could not extract Step 6's dispatch-selection paragraph from $CC_SKILL — G1 below would pass vacuously (empty extract, negative-shaped assertion)"
fi

if [ -z "$SELECTION" ]; then
  bad "G1: cannot evaluate — dispatch-selection extraction is empty (see G0)"
elif printf '%s\n' "$SELECTION" | grep -qi 'if.*hook_verified.*use\|hook_verified = true.*use\|hook_verified.*: use'; then
  bad "G1: the Step 6 dispatch-selection paragraph still branches on hook_verified"
else
  ok "G1: Step 6's dispatch selection no longer branches on hook_verified (#412)"
fi

# G2: the selection paragraph states the dispatch is unconditional.
if printf '%s\n' "$SELECTION" | grep -qi 'always'; then
  ok "G2: the selection paragraph states the dispatch is unconditional"
else
  bad "G2: no statement that Step 6 always uses the skill fallback"
fi

# G3: the banner names WHY the Workflow path is not selected — the measured zero-runs fact,
# not merely an assertion that it isn't picked. A reader deciding whether to resurrect it needs
# the reason in front of them, not just the outcome.
if printf '%s\n' "$SELECTION" | grep -q 'never `"workflow"`'; then
  ok "G3: the banner cites the measured fact that no run ever took the Workflow path"
else
  bad "G3: the banner does not cite the measured never-taken fact"
fi

# G4: the retired heading says outright that it is not selected, so a reader landing on it via
# search does not mistake it for a live path.
if grep -q '^#### Workflow dispatch path — Step 6 review cycle (NOT SELECTED' "$CC_SKILL"; then
  ok "G4: the Step 6 Workflow heading states it is not selected"
else
  bad "G4: the Step 6 Workflow heading no longer states NOT SELECTED"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
