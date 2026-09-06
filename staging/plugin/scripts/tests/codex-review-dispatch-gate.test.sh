#!/bin/bash
# codex-review-dispatch-gate.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash codex-review-dispatch-gate.test.sh
#
# Covers ADR-0193: the Codex-vs-Claude review choice moved from a single chain-start gate
# ("Gate CDX", ADR-0187) to each dispatch mechanism's own entry point — review-triage-fix's
# Step 0 item 6 (backend + model, once per RTF cycle) and a pre-dispatch ask immediately
# before Step 5 (backend only, conditional on step5_review_mode=checkpoint). The manifest
# field itself (`use_codex_review`, schema 1.4, Invariant 24) is untouched and already
# covered by use-codex-review-manifest-field.test.sh — this file does not re-test it.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
C2C="$SCRIPTS/../skills/concept-to-code/SKILL.md"
STEP5="$SCRIPTS/../skills/concept-to-code/references/step5-implementation.md"
RTF="$SCRIPTS/../skills/review-triage-fix/SKILL.md"
MINIT="$SCRIPTS/../skills/concept-to-code/scripts/manifest-init.sh"
MVALIDATE="$SCRIPTS/../skills/concept-to-code/scripts/manifest-validate.sh"
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

for _f in "$C2C" "$STEP5" "$RTF" "$MINIT" "$MVALIDATE"; do
  [ -f "$_f" ] || { echo "FATAL: missing $_f"; exit 1; }
done

# =====================================================================================
# A. Gate CDX's ask is gone from concept-to-code/SKILL.md's chain start, replaced by a
# removal note in the shape of the existing Gate 0c precedent (rule 19).
if ! grep -qF 'Gate CDX (Codex assist' "$C2C"; then
  ok "A1: the chain-start Gate CDX AskUserQuestion prompt is gone from concept-to-code/SKILL.md"
else
  bad "A1: Gate CDX's ask still present at concept-to-code/SKILL.md's chain start"
fi
# plant: A1 | plugin/skills/concept-to-code/SKILL.md | (Gate CDX, the chain-start Codex-assist ask, was removed per ADR-0193/VCS-063 | (Gate CDX (Codex assist — RESTORED FOR PLANT

if grep -qF 'ADR-0193/VCS-063' "$C2C"; then
  ok "A2: a removal note naming ADR-0193/VCS-063 stands where Gate CDX stood (rule 19)"
else
  bad "A2: no removal note naming ADR-0193/VCS-063 found in concept-to-code/SKILL.md"
fi

# =====================================================================================
# B. RTF Step 0 gained item 6 (backend + model), without disturbing item 5's pinned anchor
# (cross-reference-form C4 pins the literal string "item 5" in both this file and
# concept-to-code/SKILL.md's Step 6 Workflow path — renumbering breaks that green test).
if grep -qF 'Review backend and model (ADR-0193' "$RTF"; then
  ok "B1: RTF Step 0 item 6 (backend/model ask) is present"
else
  bad "B1: no item 6 backend/model ask found in review-triage-fix/SKILL.md"
fi
# plant: B1 | plugin/skills/review-triage-fix/SKILL.md | Review backend and model (ADR-0193 | Review backend REMOVED_FOR_PLANT

if grep -qF 'branches on the variant declared in Step 0, item 5' "$RTF"; then
  ok "B2: item 5's pinned anchor still reads 'item 5' in review-triage-fix/SKILL.md"
else
  bad "B2: item 5's pinned anchor is missing or renumbered in review-triage-fix/SKILL.md"
fi

if grep -qF 'Model override — branches on the variant declared in Step 0, item 5:' "$C2C"; then
  ok "B3: the matching anchor in concept-to-code/SKILL.md (Step 6 Workflow path) is untouched"
else
  bad "B3: the matching anchor in concept-to-code/SKILL.md is missing — Step 6 cross-reference broken"
fi

# =====================================================================================
# C. Each of the three RTF dispatch sites (Step 1, advisor call, Step 4 re-review) now
# branches on the CYCLE VALUE resolved by item 6, not on manifest.use_codex_review
# directly. Count guard (rule 7): exactly 3, not merely >=1 — a derivation that silently
# dropped a site would still show a non-zero count and read as clean without this.
SITE_COUNT=$(grep -cF "If this cycle's backend (Step 0 item 6) is \`codex\`" "$RTF")
if [ "$SITE_COUNT" -eq 3 ]; then
  ok "C1: exactly 3 RTF dispatch sites branch on the item-6 cycle value (found $SITE_COUNT)"
else
  bad "C1: expected exactly 3 RTF sites branching on the item-6 cycle value, found $SITE_COUNT"
fi
# plant: C1 | plugin/skills/review-triage-fix/SKILL.md | **If this cycle's backend (Step 0 item 6) is `codex`:** run `~/.claude/hooks/codex-reviewer.sh --mode review | **If manifest.use_codex_review (Gate CDX):** run `~/.claude/hooks/codex-reviewer.sh --mode review

# C4. Producer-consumer contract (rule 17, VCS-063 live-dispatch finding 2026-09-06): the
# script every dispatch site names must be the path sync-to-claude.sh's own PAIRS mapping
# actually deploys (plugin/scripts/codex-reviewer.sh -> hooks/codex-reviewer.sh), not a
# plausible-looking one nobody deploys there. Scoped to the 3 actual invocation lines
# (each carries `--mode`), not item 6's prose description of them (line 85, no `--mode`) —
# count guard (rule 7): all 3, not merely one — a partial fix would still look clean without this.
HOOKS_PATH_COUNT=$(grep -F '~/.claude/hooks/codex-reviewer.sh' "$RTF" | grep -cF -- '--mode')
if [ "$HOOKS_PATH_COUNT" -eq 3 ]; then
  ok "C4: all 3 RTF codex dispatch invocations name the actually-deployed hooks/ path (found $HOOKS_PATH_COUNT)"
else
  bad "C4: expected 3 RTF invocations naming ~/.claude/hooks/codex-reviewer.sh, found $HOOKS_PATH_COUNT"
fi
# plant: C4 | plugin/skills/review-triage-fix/SKILL.md | `~/.claude/hooks/codex-reviewer.sh --mode review --diff-scope uncommitted --out <tmp-review-file>` | `~/.claude/scripts/codex-reviewer.sh --mode review --diff-scope uncommitted --out <tmp-review-file>`

OTHERWISE_COUNT=$(grep -cF 'Otherwise (backend is `claude-sonnet` or `claude-opus`)' "$RTF")
if [ "$OTHERWISE_COUNT" -eq 2 ]; then
  ok "C2: exactly 2 RTF sites' Claude fallback names the item-6 model choice (Step 1, Step 4)"
else
  bad "C2: expected exactly 2 (Step 1 + Step 4 re-review), found $OTHERWISE_COUNT"
fi

if grep -qF "manifest.use_codex_review = true' (Gate CDX)" "$RTF" 2>/dev/null \
   || grep -qF 'If `manifest.use_codex_review = true` (Gate CDX)' "$RTF"; then
  bad "C3: a stale direct manifest-field read (Gate CDX) still guards an RTF dispatch site"
else
  ok "C3: no RTF dispatch site reads manifest.use_codex_review directly any more"
fi

# =====================================================================================
# D. Step 5: a pre-dispatch ask exists, conditional on step5_review_mode=checkpoint, and
# the two original checkpoint sites still read the SAME manifest field, now pointing back
# at that ask instead of at the retired Gate CDX label.
if grep -qF 'Codex review backend for Step 5 checkpoints (ADR-0193, conditional' "$STEP5"; then
  ok "D1: the Step 5 pre-dispatch ask block exists"
else
  bad "D1: the Step 5 pre-dispatch ask block is missing"
fi
# plant: D1 | plugin/skills/concept-to-code/references/step5-implementation.md | #### Codex review backend for Step 5 checkpoints (ADR-0193, conditional | #### REMOVED FOR PLANT

# The conditional must live INSIDE that specific block, not merely appear somewhere else in
# a 1700-line file (rule 3/12) — slice from the new heading to the next `#### ` heading.
D_BLOCK=$(awk '
  /^#### Codex review backend for Step 5 checkpoints/ {grab=1}
  grab && /^#### / && !/^#### Codex review backend for Step 5 checkpoints/ {exit}
  grab {print}
' "$STEP5")
if printf '%s' "$D_BLOCK" | grep -qF 'manifest.step5_review_mode = checkpoint'; then
  ok "D2: the pre-dispatch ask is conditional on step5_review_mode=checkpoint"
else
  bad "D2: the pre-dispatch block does not condition on step5_review_mode=checkpoint"
fi
if printf '%s' "$D_BLOCK" | grep -qF 'does not fire under `--autopilot`'; then
  ok "D3: the pre-dispatch ask is skipped under autopilot"
else
  bad "D3: no autopilot-skip clause found in the pre-dispatch block"
fi

ORIG_SITE_COUNT=$(grep -cF 'set by the pre-dispatch ask above, ADR-0193' "$STEP5")
if [ "$ORIG_SITE_COUNT" -eq 2 ]; then
  ok "D4: exactly 2 original Step 5 checkpoint sites point back at the pre-dispatch ask"
else
  bad "D4: expected exactly 2 (Workflow path + Agent-tool path), found $ORIG_SITE_COUNT"
fi

# =====================================================================================
# E. Correction (2026-09-05, found by a Codex dry-run review of this same change): the
# pre-dispatch gate must fire ONCE per manifest regardless of the answer. use_codex_review
# alone cannot carry that — it is seeded false, and a "no" answer also leaves it false, so a
# naive re-check would re-prompt on every Step 5 run after a decline. A dedicated
# step5_codex_review_asked field records that the ask happened, independent of the answer.
if grep -qF 'Gate on `manifest.step5_codex_review_asked`, not on `use_codex_review` itself' "$STEP5"; then
  ok "E1: the pre-dispatch block gates on step5_codex_review_asked, not on use_codex_review alone"
else
  bad "E1: no step5_codex_review_asked gating found in the pre-dispatch block"
fi
# plant: E1 | plugin/skills/concept-to-code/references/step5-implementation.md | Gate on `manifest.step5_codex_review_asked`, not on `use_codex_review` itself | Gate on REMOVED_FOR_PLANT, not on `use_codex_review` itself

if grep -qF 'echo "step5_codex_review_asked: false" >> "$T"' "$MINIT"; then
  ok "E2: manifest-init.sh seeds step5_codex_review_asked: false"
else
  bad "E2: manifest-init.sh does not seed step5_codex_review_asked"
fi
# plant: E2 | plugin/skills/concept-to-code/scripts/manifest-init.sh | echo "step5_codex_review_asked: false" >> "$T" | :

if grep -qF 'step5_codex_review_asked field present but value is not' "$MVALIDATE"; then
  ok "E3: manifest-validate.sh validates step5_codex_review_asked (Invariant 25)"
else
  bad "E3: manifest-validate.sh has no Invariant 25 for step5_codex_review_asked"
fi
# plant: E3 | plugin/skills/concept-to-code/scripts/manifest-validate.sh | fail "step5_codex_review_asked field present but value is not 'true' or 'false'" | :

# =====================================================================================
# F. Correction (2026-09-05, same dry-run review): the RTF advisor call's Claude branch was
# hardcoded to model:"opus" regardless of the backend/model chosen at Step 0 item 6 — the
# only one of the three RTF dispatch sites that ignored the choice it claims to implement.
if grep -F 'dispatch `subagent_type: "reviewer"`' "$RTF" | grep -qF 'model chosen in Step 0 item 6'; then
  ok "F1: the RTF advisor call's Claude branch uses the model chosen in Step 0 item 6"
else
  bad "F1: the RTF advisor call's Claude branch does not reference the item-6 model choice"
fi
# plant: F1 | plugin/skills/review-triage-fix/SKILL.md | at the model chosen in Step 0 item 6 (`model: "sonnet"` or `model: "opus"`). Brief: the finding, `loc`, the reviewer's suggested fix | at `model: "opus"`. Brief: the finding, `loc`, the reviewer's suggested fix REMOVED_ITEM6_REF

# Each of the three sites whose Claude-fallback path can be reached with NO Claude model
# resolved (item 6 selected `codex`, then Codex turned out unavailable) must name an
# explicit default rather than deferring to "as below"/"below", which has nothing to defer
# to. Exact count, not a floor (rule 10): the population is frozen at 3 (Step 1, advisor,
# Step 4) and a floor here would absorb the very plant below, silently passing at 2.
# Matched word-wise (rule 3) rather than by physical line, because the advisor site's own
# prose happens to wrap the clause across a line break where the other two sites do not.
FALLBACK_DEFAULT_COUNT=$(python3 -c '
import re, sys
text = open(sys.argv[1]).read()
needle = "there is none to reuse for this fallback"
pat = re.compile(r"\s+".join(re.escape(w) for w in needle.split()))
print(len(pat.findall(text)))
' "$RTF")
if [ "$FALLBACK_DEFAULT_COUNT" -eq 3 ]; then
  ok "F2: exactly 3 RTF codex-unavailable fallbacks name an explicit default Claude model"
else
  bad "F2: expected exactly 3 explicit fallback-model defaults, found $FALLBACK_DEFAULT_COUNT"
fi
# plant: F2 | plugin/skills/review-triage-fix/SKILL.md | unavailable at RTF Step 1: `<reason from stderr>`. Fallback to Claude's reviewer agent for this dispatch, or halt the chain?" Options: "Fallback to Claude reviewer (Recommended)" → dispatch `reviewer` at `model: "sonnet"` (today's default — item 6 selected `codex`, not a Claude model, so there is none to reuse for this fallback) | unavailable at RTF Step 1: `<reason from stderr>`. Fallback to Claude's reviewer agent for this dispatch, or halt the chain?" Options: "Fallback to Claude reviewer (Recommended)" → dispatch `reviewer` at `model: "sonnet"` (today's default — item 6 selected `codex`, not a Claude model, so REMOVED_FOR_PLANT)

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
_total=$((PASS + FAIL))
if [ "$_total" -ge 18 ]; then
  echo "PASS: Z1: $_total assertions ran (floor: 18)"
  PASS=$((PASS+1))
else
  echo "FAIL: Z1: assertion count fell to $_total (floor 18) — assertions vanished"
  FAIL=$((FAIL+1))
fi

[ "$FAIL" -eq 0 ]
