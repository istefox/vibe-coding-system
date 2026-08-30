#!/bin/bash
# claude-design-gate.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash claude-design-gate.test.sh
#
# Covers VCS-052 / ADR-0181: Gate 1d — Claude Design, the two new CHECKER scripts
# (design-url-check.sh, design-coverage.sh), the new claude-design-brief skill, and the
# reach-to-the-coder wiring (architect brief, both coder dispatch templates, the widened
# 5.0.1 pre-flight classifier).
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Needles belong to the mechanism, never to the string "claude-design" or "Gate 1d", which
# appear in every explanatory paragraph of this feature (rule 1).
# plant: CD1 | plugin/skills/concept-to-code/scripts/design-url-check.sh | -z "$URL" ]; then exit 3 | -z "$URL" ]; then exit 0
# plant: CD2 | plugin/skills/concept-to-code/scripts/design-coverage.sh | rows" -eq 0 | rows" -eq 999
# plant: CD3 | plugin/skills/concept-to-code/references/hitl-gates.md | Gate 1d: autopilot — Claude Design needs a human in a browser, skipped | Gate 1d: autopilot — Claude Design needs a human in a meeting, skipped
# plant: CD4 | plugin/skills/concept-to-code/references/step5-implementation.md | not an input to weigh. TEST-AUTHORING SCOPE | not a constraint at all. TEST-AUTHORING SCOPE
# plant: CD5 | plugin/skills/concept-to-code/SKILL.md | Binding decisions are a constraint on the plan, not an input to weigh | Binding decisions are a suggestion for the plan, freely reinterpreted
# plant: CD6 | plugin/skills/concept-to-code/scripts/manifest-init.sh | echo "  design: null" | echo "  designx: null"
# plant: CD7 | plugin/skills/claude-design-brief/SKILL.md | DESIGN-PROMPT.md`. The skill writes **only this file** | DESIGN-OUTPUT.md`. The skill writes **only this file**
#
# CD6 IS THE LOAD-BEARING ONE (rule 1): it proves the manifest-key enforcement is
# manifest-set-artifact.sh's `grep -q "^  design: "` gate, not its usage-comment (which the
# whole feature otherwise depends on trusting).
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)                    # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                         # staging/
SKILLS="$STAGING/plugin/skills"
C2C_SCRIPTS="$SKILLS/concept-to-code/scripts"
C2C="$SKILLS/concept-to-code/SKILL.md"
HITL_REF="$SKILLS/concept-to-code/references/hitl-gates.md"
STEP5_REF="$SKILLS/concept-to-code/references/step5-implementation.md"
DESIGN_SKILL="$SKILLS/claude-design-brief/SKILL.md"
URL_CHECK="$C2C_SCRIPTS/design-url-check.sh"
COVERAGE="$C2C_SCRIPTS/design-coverage.sh"
MANIFEST_INIT="$C2C_SCRIPTS/manifest-init.sh"
MANIFEST_SET_ARTIFACT="$C2C_SCRIPTS/manifest-set-artifact.sh"
MANIFEST_VALIDATE="$C2C_SCRIPTS/manifest-validate.sh"
MANIFEST_TRANSITION="$C2C_SCRIPTS/manifest-transition.sh"
RRP="$C2C_SCRIPTS/repo-rel-path.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# ==================================================================================================
# A. design-url-check.sh — shape-only CHECKER, never fetches the URL (plan §5).
# ==================================================================================================
if [ -x "$URL_CHECK" ]; then
  ok "A0: design-url-check.sh exists and is executable"
else
  bad "A0: design-url-check.sh missing or not executable"
fi

bash "$URL_CHECK" >/dev/null 2>&1
if [ "$?" -eq 3 ]; then
  ok "CD1: design-url-check.sh with no --url exits 3 (DID-NOT-RUN, rule 4) — never silently valid"
else
  bad "CD1: design-url-check.sh with no --url did not exit 3"
fi

bash "$URL_CHECK" --url "" >/dev/null 2>&1
[ "$?" -eq 3 ] && ok "A1: design-url-check.sh with an empty --url value exits 3" \
                || bad "A1: design-url-check.sh with an empty --url value did not exit 3"

bash "$URL_CHECK" --url "https://claude.ai/design/abc123" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "A2: a valid https://claude.ai/... URL exits 0" \
               || bad "A2: a valid https://claude.ai/... URL did not exit 0"

bash "$URL_CHECK" --url "https://not-claude.example/design" >/dev/null 2>&1
[ "$?" -eq 1 ] && ok "A3: a non-matching, non-empty URL exits 1 (re-prompt, do not proceed)" \
               || bad "A3: a non-matching URL did not exit 1"

bash "$URL_CHECK" --bogus-flag >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "A4: an unrecognized flag is a bad invocation, exit 2" \
               || bad "A4: an unrecognized flag did not exit 2"

# It must not fetch: no network primitive INVOKED in the script's code (comments may
# legitimately explain the non-fetching contract in English prose, e.g. "must not fetch").
if grep -v '^[[:space:]]*#' "$URL_CHECK" | grep -qE '\b(curl|wget)\b'; then
  bad "A5: design-url-check.sh invokes a network primitive — it must be shape-only (plan §5)"
else
  ok "A5: design-url-check.sh invokes no network primitive — shape-only, never fetched"
fi

# ==================================================================================================
# B. design-coverage.sh — DESIGN.md Screens-table -> plan-task coverage CHECKER.
# ==================================================================================================
if [ -x "$COVERAGE" ]; then
  ok "B0: design-coverage.sh exists and is executable"
else
  bad "B0: design-coverage.sh missing or not executable"
fi

DESIGN_EMPTY="$TMP/DESIGN-empty.md"
printf '%s\n' "# Design — Demo" "" "## Screens" "| Screen | Purpose | SPEC ids | Notes |" "|---|---|---|---|" "" "## Binding decisions" >"$DESIGN_EMPTY"
PLAN_ANY="$TMP/plan-any.md"
printf '%s\n' "# Plan" "- [ ] T-01 Build something" >"$PLAN_ANY"

bash "$COVERAGE" --design "$DESIGN_EMPTY" --plan "$PLAN_ANY" >/dev/null 2>&1
if [ "$?" -eq 3 ]; then
  ok "CD2: design-coverage.sh with zero Screens rows exits 3 — the denominator guard (rule 7), never a clean pass"
else
  bad "CD2: design-coverage.sh with zero Screens rows did not exit 3"
fi

DESIGN_FULL="$TMP/DESIGN-full.md"
printf '%s\n' "# Design — Demo" "" "## Screens" "| Screen | Purpose | SPEC ids | Notes |" "|---|---|---|---|" "| Home | Landing | R-01 | |" "| Settings | Prefs | R-02 | |" "" "## Binding decisions" >"$DESIGN_FULL"
PLAN_PARTIAL="$TMP/plan-partial.md"
printf '%s\n' "# Plan" "- [ ] T-01 Build the Home screen" >"$PLAN_PARTIAL"
PLAN_FULL="$TMP/plan-full.md"
printf '%s\n' "# Plan" "- [ ] T-01 Build the Home screen" "- [ ] T-02 Wire up the Settings screen" >"$PLAN_FULL"

B1_OUT=$(bash "$COVERAGE" --design "$DESIGN_FULL" --plan "$PLAN_FULL" 2>/dev/null); B1_RC=$?
[ "$B1_RC" -eq 0 ] && [ -z "$B1_OUT" ] && ok "B1: every screen cited by the plan exits 0, silent stdout" \
                                       || bad "B1: a fully-cited design/plan pair did not exit 0 clean (rc=$B1_RC out=$B1_OUT)"

B2_OUT=$(bash "$COVERAGE" --design "$DESIGN_FULL" --plan "$PLAN_PARTIAL" 2>/dev/null); B2_RC=$?
if [ "$B2_RC" -eq 1 ] && printf '%s' "$B2_OUT" | grep -qE 'UNCOVERED.*Settings'; then
  ok "B2: an uncovered screen exits 1 and names it, TAB-separated (UNCOVERED<TAB>Settings)"
else
  bad "B2: an uncovered screen did not report UNCOVERED/Settings on exit 1 (rc=$B2_RC out=$B2_OUT)"
fi

bash "$COVERAGE" --design "$DESIGN_FULL" >/dev/null 2>&1
[ "$?" -eq 2 ] && ok "B3: a missing --plan argument is a bad invocation, exit 2" \
               || bad "B3: a missing --plan argument did not exit 2"

# Population guard (rule 18): the checker's own usage/CLI never accepts a repo-wide sweep target.
if grep -q -- '--plan <file>' "$COVERAGE"; then
  ok "B4: design-coverage.sh matches against the --plan FILE only, not a repo-wide file set (rule 18)"
else
  bad "B4: design-coverage.sh's usage no longer names a single --plan file"
fi

# ==================================================================================================
# C. Gate 1d prose in hitl-gates.md — heading, autopilot marker, two-phase structure.
# ==================================================================================================
if grep -Fxq '**Gate 1d — Claude Design (optional)**' "$HITL_REF"; then
  ok "C0: the Gate 1d heading matches gate_ids()'s derivation regex exactly, at column 0"
else
  bad "C0: hitl-gates.md does not carry the exact Gate 1d heading gate_ids() derives from"
fi

if grep -q 'Gate 1d: autopilot — Claude Design needs a human in a browser, skipped' "$HITL_REF"; then
  ok "CD3: Gate 1d's autopilot default states the structural (human-in-a-browser) reason, not just 'No'"
else
  bad "CD3: Gate 1d's autopilot default no longer states the structural reason"
fi

if grep -q 'Not yet, still designing' "$HITL_REF" && grep -q 'do .*not.* transition' "$HITL_REF"; then
  ok "C1: Gate 1d-B's 'Not yet, still designing' option is documented as a resumable, non-transitioning pause"
else
  bad "C1: Gate 1d-B's resumable pause option is not documented"
fi

if grep -q 'design-url-check.sh --url' "$HITL_REF"; then
  ok "C2: Gate 1d invokes design-url-check.sh on the pasted URL"
else
  bad "C2: Gate 1d does not invoke design-url-check.sh"
fi

C3_HITS=0
grep -q 'URL only' "$HITL_REF" && C3_HITS=$((C3_HITS+1))
grep -q 'standalone-HTML export' "$HITL_REF" && C3_HITS=$((C3_HITS+1))
grep -q 'handoff bundle' "$HITL_REF" && C3_HITS=$((C3_HITS+1))
[ "$C3_HITS" -eq 3 ] && ok "C3: all three fidelity tiers (URL only / standalone-HTML export / handoff bundle) are named at the gate" \
                      || bad "C3: only $C3_HITS of the 3 fidelity tiers are named at Gate 1d"

# ==================================================================================================
# D. Coder dispatch — references/step5-implementation.md, BOTH templates (plan §4b).
# ==================================================================================================
D_COUNT=$(grep -c 'If a Claude Design artifact exists, read it at <manifest.artifacts.design>' "$STEP5_REF" 2>/dev/null || true)
D_COUNT=${D_COUNT:-0}
[ "$D_COUNT" -eq 2 ] && ok "D0: the coder design-read line appears in exactly 2 dispatch templates (verification item 8)" \
                     || bad "D0: the coder design-read line appears $D_COUNT times, expected exactly 2"

if [ "$(python3 - "$STEP5_REF" 2>/dev/null <<'PY'
import re, sys
text = open(sys.argv[1]).read()
needle = 'not an input to weigh. TEST-AUTHORING SCOPE'
pat = re.compile(r'\s+'.join(re.escape(w) for w in needle.split()))
print(len(pat.findall(text)))
PY
)" = "1" ]; then
  ok "CD4: the coder-facing (non-tester) dispatch template carries the design-read line immediately before its TEST-AUTHORING SCOPE marker"
else
  bad "CD4: the coder-facing dispatch template no longer carries the design-read line where expected"
fi

# Negative direction (rule 8): the TESTER-only template must NOT carry the design line — design
# context serves implementation, not test-writing (dispatch instruction, resolved during this task).
TESTER_BLOCK=$(awk '/Tester batch dispatch template/{f=1} f{print} f&&/^```$/{c++; if(c==2) exit}' "$STEP5_REF")
if printf '%s' "$TESTER_BLOCK" | grep -q 'Claude Design artifact exists'; then
  bad "D1: the tester-only dispatch template carries the design-read line — it should not (tester writes tests, not implementation)"
else
  ok "D1: the tester-only dispatch template does not carry the design-read line"
fi

# ==================================================================================================
# E. Architect dispatch, §25 whitelist, and Step 2 / Hybrid routing — concept-to-code/SKILL.md.
# ==================================================================================================
if grep -q 'Binding decisions are a constraint on the plan, not an input to weigh' "$C2C"; then
  ok "CD5: the architect dispatch states Binding decisions are a constraint, not an input to weigh"
else
  bad "CD5: the architect dispatch no longer states the Binding-decisions constraint"
fi

if grep -qF '`claude-design-brief` (gate 1d only)' "$C2C"; then
  ok "E1: §25's chain whitelist restricts claude-design-brief to gate 1d only"
else
  bad "E1: §25's chain whitelist does not name claude-design-brief (gate 1d only)"
fi

if grep -q 'gate_1c_macos_ux_decision → gate_1d_claude_design_decision' "$C2C"; then
  ok "E2: Step 2 routes Gate 1c's resolution through Gate 1d, not directly to the architect"
else
  bad "E2: Step 2 no longer routes Gate 1c through Gate 1d"
fi

if grep -q 'gate_1b_brainstorm_decision → gate_1d_claude_design_decision' "$C2C"; then
  ok "E3: Step 2 routes the NOT_MACOS branch through Gate 1d, not directly to the architect"
else
  bad "E3: Step 2 no longer routes the NOT_MACOS branch through Gate 1d"
fi

if grep -q 'gate_h1d_claude_design' "$C2C"; then
  ok "E4: the Hybrid path names gate_h1d_claude_design (Gate H1d wired into Step H2 routing)"
else
  bad "E4: the Hybrid path does not name gate_h1d_claude_design"
fi

if grep -q 'Read SPEC.md (and BRAINSTORM.md, DESIGN.md if present)' "$C2C"; then
  ok "E5: Hybrid Step H2's read-first line names DESIGN.md"
else
  bad "E5: Hybrid Step H2's read-first line does not name DESIGN.md"
fi

# ==================================================================================================
# F. Manifest scripts — the actual enforcement (CD6 is the load-bearing plant, rule 1).
# ==================================================================================================
if grep -q 'echo "  design_prompt: null"' "$MANIFEST_INIT"; then
  ok "F1: manifest-init.sh writes the design_prompt artifact key"
else
  bad "F1: manifest-init.sh does not write the design_prompt artifact key"
fi

if grep -q 'echo "  design: null"' "$MANIFEST_INIT"; then
  ok "CD6: manifest-init.sh writes the design artifact key — the actual enforcement (manifest-set-artifact.sh's grep -q gate), not the usage comment"
else
  bad "CD6: manifest-init.sh no longer writes the design artifact key"
fi

if grep -q 'design_prompt' "$MANIFEST_SET_ARTIFACT" && grep -q '\bdesign\b' "$MANIFEST_SET_ARTIFACT"; then
  ok "F2: manifest-set-artifact.sh's usage comment lists design_prompt and design (documentation kept in sync)"
else
  bad "F2: manifest-set-artifact.sh's usage comment does not list the new artifact keys"
fi

if grep -q 'echo "gate_1d_claude_design_decision"' "$MANIFEST_VALIDATE" && grep -q 'echo "gate_h1d_claude_design"' "$MANIFEST_VALIDATE"; then
  ok "F3: manifest-validate.sh accepts both gate_1d_claude_design_decision and gate_h1d_claude_design as valid states"
else
  bad "F3: manifest-validate.sh is missing one or both new valid states"
fi

F4_HITS=0
grep -q 'gate_1b_brainstorm_decision,gate_1d_claude_design_decision' "$MANIFEST_TRANSITION" && F4_HITS=$((F4_HITS+1))
grep -q 'gate_1c_macos_ux_decision,gate_1d_claude_design_decision' "$MANIFEST_TRANSITION" && F4_HITS=$((F4_HITS+1))
grep -q 'gate_1d_claude_design_decision,step_2_architecture' "$MANIFEST_TRANSITION" && F4_HITS=$((F4_HITS+1))
grep -q 'gate_h1b_brainstorm,gate_h1d_claude_design' "$MANIFEST_TRANSITION" && F4_HITS=$((F4_HITS+1))
grep -q 'gate_h1c_macos_ux,gate_h1d_claude_design' "$MANIFEST_TRANSITION" && F4_HITS=$((F4_HITS+1))
grep -q 'gate_h1d_claude_design,step_h2_plan' "$MANIFEST_TRANSITION" && F4_HITS=$((F4_HITS+1))
[ "$F4_HITS" -eq 6 ] && ok "F4: all 6 new Gate 1d/H1d transition pairs are declared in manifest-transition.sh" \
                      || bad "F4: only $F4_HITS of the 6 new transition pairs are declared (expected 6)"

# ==================================================================================================
# G. claude-design-brief/SKILL.md — the prompt-generating skill.
# ==================================================================================================
if grep -q '^name: claude-design-brief$' "$DESIGN_SKILL"; then
  ok "G0: claude-design-brief/SKILL.md carries the correct frontmatter name"
else
  bad "G0: claude-design-brief/SKILL.md frontmatter name is missing or wrong"
fi

if [ "$(python3 - "$DESIGN_SKILL" 2>/dev/null <<'PY'
import re, sys
text = open(sys.argv[1]).read()
needle = "DESIGN-PROMPT.md" + chr(96) + ". The skill writes **only this file**"
pat = re.compile(r'\s+'.join(re.escape(w) for w in needle.split()))
print(len(pat.findall(text)))
PY
)" = "1" ]; then
  ok "CD7: claude-design-brief/SKILL.md states it writes only DESIGN-PROMPT.md"
else
  bad "CD7: claude-design-brief/SKILL.md no longer states its single-file output contract"
fi

grep -q 'disable-model-invocation: true' "$DESIGN_SKILL" \
  && bad "G1: claude-design-brief/SKILL.md sets disable-model-invocation: true (must not — it is chain-invoked)" \
  || ok "G1: claude-design-brief/SKILL.md does not set disable-model-invocation: true"

grep -qi 'gate 1d' "$DESIGN_SKILL" \
  && ok "G2: claude-design-brief/SKILL.md names gate 1d (skill-coverage-perimeter C8's own-text half)" \
  || bad "G2: claude-design-brief/SKILL.md does not name gate 1d"

grep -q 'End execution silently' "$DESIGN_SKILL" \
  && ok "G3: claude-design-brief/SKILL.md carries the chain-invocation silent-return contract" \
  || bad "G3: claude-design-brief/SKILL.md is missing the silent-return contract"

grep -q 'Does NOT write .DESIGN.md' "$DESIGN_SKILL" \
  && ok "G4: claude-design-brief/SKILL.md states it does not write DESIGN.md (the orchestrator's job at 1d-B)" \
  || bad "G4: claude-design-brief/SKILL.md does not state the DESIGN.md boundary"

# ==================================================================================================
# H. The 5.0.1 pre-flight fence classifies DESIGN.md (and siblings) as CHAIN, not OTHER (plan §6).
# ==================================================================================================
H_FENCE="$TMP/h_fence.sh"
awk '
  index($0, "fence-contract: c2c-step5-preflight-dirty-classify -->") { grab=1; next }
  grab && /^```bash/ { infence=1; next }
  grab && infence && /^```/ { exit }
  grab && infence { print }
' "$STEP5_REF" >"$H_FENCE"

if [ -s "$H_FENCE" ] && bash -n "$H_FENCE" 2>/dev/null; then
  ok "H0: the widened 5.0.1 fence still extracts and parses as bash"
else
  bad "H0: the 5.0.1 fence no longer extracts or no longer parses"
fi

H_REPO="$TMP/hrepo"
mkdir -p "$H_REPO/docs/manifests" "$H_REPO/docs/architecture" "$H_REPO/docs/superpowers/plans"
( cd "$H_REPO" || exit 1
  git init -q . >/dev/null 2>&1
  git config user.email t@example.invalid; git config user.name t
  printf 'current_step: "x"\n' >docs/manifests/m.yml
  printf 'spec\n' >SPEC.md; printf 'adr\n' >docs/architecture/A.md
  printf 'plan\n' >docs/superpowers/plans/p.md
  printf 'design\n' >DESIGN.md
  git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1 )
# Dirty the tree with ONLY DESIGN.md (post-commit edit) — the exact shape the defect in plan §6 named.
printf 'design v2\n' >>"$H_REPO/DESIGN.md"

H_OUT=$( cd "$H_REPO" && MANIFEST="$H_REPO/docs/manifests/m.yml" SPEC="$H_REPO/SPEC.md" \
  ADR="$H_REPO/docs/architecture/A.md" PLAN="$H_REPO/docs/superpowers/plans/p.md" \
  BRAINSTORM="" UXB="" DESIGN_PROMPT="" DESIGN="$H_REPO/DESIGN.md" \
  CLAUDE_PLUGIN_ROOT="$STAGING/plugin" \
  bash "$H_FENCE" 2>&1 ); H_RC=$?

case "$H_OUT" in
  *PREFLIGHT_CHAIN*) ok "H1: a dirty tree containing only DESIGN.md classifies PREFLIGHT_CHAIN, not PREFLIGHT_OTHER (plan §6 defect fixed, rc=$H_RC)" ;;
  *) bad "H1: a dirty tree containing only DESIGN.md did not classify PREFLIGHT_CHAIN (got: $H_RC $H_OUT)" ;;
esac

# ==================================================================================================
# Z. Assertion floor (rule 10, vacuity guard only — a frozen per-file baseline is not worth the tax
# on a file this actively edited during its own introduction).
# ==================================================================================================
TOTAL=$((PASS + FAIL))
if [ "$TOTAL" -ge 35 ]; then
  ok "Z1: assertion floor met ($TOTAL executed, floor 35)"
else
  bad "Z1: only $TOTAL assertions executed — the floor is 35, so something stopped running"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
