#!/bin/bash
# gate0-recommendation.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash gate0-recommendation.test.sh
#
# Issue #227 / ADR-0098. Gate 0 displayed TWO "recommended" markers that can point at different
# options, with nothing saying which wins:
#
#   1. the question string hardcodes  "Recommended: [<path>] — <auto_detect_reason>"
#   2. the global AskUserQuestion convention makes the orchestrator put ITS recommendation first
#      and append "(Recommended)" to the label
#
# On the Phase 7 shakedown run the user saw `Recommended: [h] hybrid` in the question text and
# `[s] Standard … (Recommended)` in the options, in the same box, and asked which to believe.
# Neither was wrong: the auto-detect is a mechanical vote on repo size and title keywords; the
# orchestrator knew the run existed to exercise Steps 5 and 6, which hybrid never reaches.
#
# SECOND FINDING, MEASURED, AND STRONGER THAN THE ISSUE STATES. The issue says file_vote pins to
# `standard` "on any repository past a few hundred files". The threshold is **20**:
#
#   < 10  -> express      < 20 -> hybrid      otherwise -> standard
#
# So on any repository with 20+ files the vote is permanently `standard`. Feeding that into the
# documented majority rule — "file_vote + keyword_vote + (tie-break: both express -> express, else
# hybrid)" — leaves exactly two reachable outcomes, `standard` when the title carries an
# architecture keyword and `hybrid` otherwise, and makes **`express` impossible to auto-recommend**.
# Corroborated by the corpus: 3 manifests ever recorded a file_vote and all 3 are `standard`
# (repos of 255, 541 and 595 files).
#
# The field is renamed `repo_file_count` rather than re-tuned. At Gate 0 there is no feature-size
# signal to be had — no SPEC, no plan, only a title and a repository — so a repo-size proxy is not
# a lazy choice, it is the only measurable thing at that moment. What was wrong was the NAME
# claiming to estimate something else. Inventing better thresholds without a better signal would be
# the same error with fresher numbers.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: N5 | plugin/skills/concept-to-code/scripts/gate0-detect.sh | echo "repo_file_count=$file_count" | echo "file_estimate=$file_count"
# plant: N1 | plugin/skills/concept-to-code/SKILL.md | Auto-detect suggests: [<path>] | Recommended: [<path>]
# plant: N3 | plugin/skills/concept-to-code/SKILL.md | The orchestrator's recommendation wins | Pick one
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
G0="$STAGING/plugin/skills/concept-to-code/scripts/gate0-detect.sh"
LEGACY="$STAGING/plugin/skills/concept-to-code/tests/run-tests.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$CC" ] || { echo "FATAL: missing $CC"; exit 1; }
[ -f "$G0" ] || { echo "FATAL: missing $G0"; exit 1; }

# --- Gate 0 block, anchored on headings, never line numbers (rule 3) -------------------------
N_A=$(grep -n '^\*\*Gate 0 — Chain routing' "$CC" | head -1 | cut -d: -f1)
N_B=$(grep -n '^\*\*Gate 0b — Anonymous mode' "$CC" | head -1 | cut -d: -f1)
if [ -n "${N_A:-}" ] && [ -n "${N_B:-}" ] && [ "$N_B" -gt "$N_A" ]; then
  ok "N0 Gate 0 block anchors resolve ($N_A..$N_B)"
else
  bad "N0 Gate 0 block anchors did not resolve — a heading was reworded, and every prose assertion below is vacuous"
fi
BLOCK=$(awk -v a="${N_A:-0}" -v b="${N_B:-0}" 'NR>=a && NR<b' "$CC")
BLOCK_N=$(printf '%s\n' "$BLOCK" | grep -c .)
if [ "$BLOCK_N" -ge 30 ]; then ok "N0b the extracted block is non-vacuous ($BLOCK_N lines)"
else bad "N0b the Gate 0 block extracted $BLOCK_N lines (expected >= 30)"; fi

# Prose is matched against a copy with line breaks AND markdown decoration removed. A clause is the
# same clause whether it wraps, whether a word inside it is code-quoted, and whether it is bolded —
# this repository has been bitten by each of those separately (ADR-0073 line wrap, ADR-0076 comment
# marker, ADR-0080 backticks, ADR-0082 one-line marker, ADR-0092 a derivation reading its own
# source), and N7b hit the backtick form again while this very ADR was being written. Structural
# markers are matched against BLOCK, line-wise and undecorated, because there the decoration IS the
# structure.
FLAT=$(printf '%s\n' "$BLOCK" | tr '\n' ' ' | tr -d '`*' | tr -s ' ')

# ===========================================================================
# N1..N4 — precedence, stated where the reader is.
# ===========================================================================
if printf '%s\n' "$BLOCK" | grep -q 'question: "Gate 0 .*Recommended: \[<path>\]'; then
  bad "N1 the question still labels the mechanical vote 'Recommended' — two recommendations, no precedence (#227)"
else
  ok "N1 the question does not label the mechanical vote as the recommendation"
fi

if printf '%s\n' "$FLAT" | grep -q 'Auto-detect suggests'; then
  ok "N2 the mechanical vote is presented as advisory"
else
  bad "N2 the question does not present the vote as advisory ('Auto-detect suggests')"
fi

if printf '%s\n' "$FLAT" | grep -q "orchestrator's recommendation wins"; then
  ok "N3 precedence is stated: the orchestrator's judgement wins"
else
  bad "N3 no precedence rule stated — the defect is not which signal wins, it is that neither is declared to"
fi

if printf '%s\n' "$FLAT" | grep -q 'they disagree' && printf '%s\n' "$FLAT" | grep -q 'say so in the question'; then
  ok "N4 a divergence must be stated in the gate rather than silently resolved"
else
  bad "N4 the block does not require the divergence to be shown to the user"
fi

# ===========================================================================
# N5..N7 — the field says what it measures.
# ===========================================================================
mk_repo() {  # <n-files>
  _r=$(mktemp -d "$TMP/gXXXXXX")
  _i=0
  while [ "$_i" -lt "$1" ]; do : >"$_r/f$_i.txt"; _i=$((_i + 1)); done
  printf '%s' "$_r"
}

r=$(mk_repo 25)
out=$(bash "$G0" "$r" "a plain title" 2>&1)
if printf '%s\n' "$out" | grep -q '^repo_file_count='; then
  ok "N5 gate0-detect.sh emits repo_file_count"
else
  bad "N5 gate0-detect.sh does not emit repo_file_count; got: $(printf '%s' "$out" | tr '\n' ' ')"
fi
if printf '%s\n' "$out" | grep -q '^file_estimate='; then
  bad "N5b gate0-detect.sh still emits file_estimate — the name that reads as a feature-size estimate (#227)"
else
  ok "N5b file_estimate is gone"
fi

# Both directions (rule 8): the degenerate case AND the case that is not degenerate.
if printf '%s\n' "$out" | grep -qx 'file_vote=standard'; then
  ok "N6 a 25-file repository votes standard — the threshold is 20, not a few hundred"
else
  bad "N6 a 25-file repository did not vote standard; the measured premise for N7 no longer holds"
fi
r=$(mk_repo 5)
out5=$(bash "$G0" "$r" "a plain title" 2>&1)
if printf '%s\n' "$out5" | grep -qx 'file_vote=express'; then
  ok "N6b a 5-file repository still votes express — the vote is degenerate, not broken"
else
  bad "N6b a 5-file repository did not vote express; file_vote is not doing what its thresholds say"
fi

if printf '%s\n' "$FLAT" | grep -q 'repository size, not feature size'; then
  ok "N7 the gate says what the count measures"
else
  bad "N7 the gate does not say the count measures repository size rather than feature size"
fi

if printf '%s\n' "$FLAT" | grep -q 'express can never be auto-recommended'; then
  ok "N7b the degenerate consequence is stated where the reader is"
else
  bad "N7b the block does not state that express is unreachable above the threshold"
fi

# ===========================================================================
# N8/N9 — the other two consumers of the renamed field.
# ===========================================================================
if grep -q 'repo_file_count' "$CC"; then
  ok "N8 SKILL.md's gate0-detect field list names repo_file_count"
else
  bad "N8 SKILL.md still lists file_estimate among gate0-detect's outputs"
fi

# The needle is the harness's actual GREP PATTERN, not any mention of the name. A first draft
# matched `repo_file_count` anywhere in the file and passed a planted defect that changed only the
# pattern — the ok()/bad() message strings still carried the new name. The needle must belong to the
# mechanism, not to the prose describing it (rule 12's cousin; SA10 in spec-archive.test.sh hit the
# same shape earlier the same day).
if [ -f "$LEGACY" ]; then
  if grep -qF "grep -q '^repo_file_count='" "$LEGACY"; then
    ok "N9 the skill-private harness greps for the renamed field"
  else
    bad "N9 concept-to-code/tests/run-tests.sh does not grep for ^repo_file_count= — it would go red against the renamed script"
  fi
else
  bad "N9 the skill-private harness is missing; the rename's third consumer is unchecked"
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
