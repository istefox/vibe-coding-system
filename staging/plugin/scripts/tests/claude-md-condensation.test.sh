#!/bin/bash
# claude-md-condensation.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash claude-md-condensation.test.sh
#
# Issue #380 (ADR-0136). CLAUDE.md is loaded in full into every orchestrator turn and re-injected
# after every /compact. Sub-agents do not load it. It had become an append-only log — one narrative
# block per merged feature, 95 of them, 98% of the file — at ~75,000 tokens per turn and 21.5% of
# the orchestrator's measured cache-read volume.
#
# TWO OF THE ISSUE'S PREMISES DID NOT REPRODUCE, and both changed the design:
#
#   1. The blocks are NOT duplicates of the ADRs. Measured over all 95 before the move: whole-line
#      overlap with the ADR each block points at is 6 of 3,132 substantive lines; distinctive
#      6-word-phrase overlap is 2,501 of 45,765 (5%); four of six spot-checked distinctive claims
#      are absent from their ADR entirely; and eleven blocks carry an explicit cross-ADR synthesis
#      ("third of its family") that by construction cannot live in any single ADR. So deleting a
#      block does not leave its content on disk — hence docs/chain-decisions.md, verbatim.
#   2. "Every rule preserved, verified mechanically" is not achievable as stated. Re-deriving the
#      recurring-rule table gives different counts in both directions depending on the needle, which
#      are recorded nowhere. An unenumerable set cannot be checked for preservation. What IS
#      mechanical is that no LINE was lost (content-union-check.sh) — see CMC08's note.
#
# WHAT THIS FILE DOES NOT CHECK, stated so a green run is not over-read: nothing here verifies that
# every rule worth promoting WAS promoted. That set is not enumerable (premise 2 above). The
# preservation guarantee is the union check, which is run at implementation time and on demand
# against the pre-condensation file — it is not re-runnable from here, because the original is only
# in git history, and an assertion that silently stopped resolving would read as coverage.
#
# WHY A NEW FILE (ADR-0086's criterion: share only when two copies giving different answers would be
# a defect). claude-md-slim-content-union-whole-line.test.sh owns the union CHECKER's semantics;
# this file owns the SHAPE of one particular condensed file and its producer. Different populations,
# different questions.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line removes or inverts ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing (ADR-0108).
#
# DISCLOSED, NOT CHASED: CMC01-CMC07 and CMC12 read CLAUDE.md at the REPO ROOT, and plant-check.sh
# copies only staging/ and docs/ into its sandbox (plus ADR-0116's `../docs/` hatch). A root file is
# unplantable by construction, so those eight assertions carry no plant. This is the same limit
# ADR-0122 recorded for .github/workflows/ and ADR-0118 for .gitignore. Do not chase it here;
# widening the registry's sandbox is its own issue.
#
# plant: CMC08 | ../docs/chain-decisions.md | It is a historical record and is not corrected in place | It is a historical record and may be corrected in place
# plant: CMC09 | plugin/skills/concept-to-code/SKILL.md | Append it to `<project-root>/docs/chain-decisions.md` if that file exists | Append it to CLAUDE.md if that file exists
# plant: CMC10 | plugin/skills/concept-to-code/SKILL.md | Rules line — only when the ADR establishes a recurring invariant that is not already in | Rules line — always, appended unconditionally alongside the index line and not already in
# plant: CMC11 | plugin/skills/concept-to-code/SKILL.md | If the count exceeds 400, prepend to the | If the count exceeds 180, prepend to the
# ------------------------------------------------------------------------------------------

set -u
cd "$(dirname "$0")/../../.." || exit 1          # -> staging/
REPO=$(cd .. && pwd)
SKILL="plugin/skills/concept-to-code/SKILL.md"
CMD="$REPO/CLAUDE.md"
ARC="$REPO/docs/chain-decisions.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Prose needles match a FLATTENED, UNDECORATED, CASE-INSENSITIVE copy: a clause is the same clause
# whether it wraps across lines, is backticked, is bolded, or opens a sentence (ADR-0073, ADR-0076,
# ADR-0080, ADR-0098, ADR-0101 — the decoration family, met five times). Structural checks below
# stay line-wise on purpose, because there the decoration IS the structure.
flat() { tr '\n' ' ' < "$1" | tr -d '`*_' | tr 'A-Z' 'a-z' | sed 's/  */ /g'; }
has_flat() { printf '%s' "$2" | grep -qF "$(printf '%s' "$3" | tr -d '`*_' | tr 'A-Z' 'a-z' | sed 's/  */ /g')"; }

[ -f "$CMD" ] || { echo "FAIL: CLAUDE.md not found at $CMD"; exit 1; }
[ -f "$SKILL" ] || { echo "FAIL: $SKILL not found"; exit 1; }

# --- A. the condensed file's shape ---------------------------------------------------------

CEILING=400
CMD_LINES=$(wc -l < "$CMD" | tr -d ' ')
if [ "$CMD_LINES" -le "$CEILING" ]; then
  ok "CMC01 CLAUDE.md is $CMD_LINES lines (ceiling $CEILING)"
else
  bad "CMC01 CLAUDE.md is $CMD_LINES lines, over the $CEILING ceiling — a narrative block is being appended again, or Rules has accumulated near-duplicates"
fi

# The narrative moved out. This is the one assertion that would catch a regression to the old
# producer even if every other check stayed green.
BLOCKS_IN_CMD=$(grep -c '^## Decisions from' "$CMD" || true)
if [ "${BLOCKS_IN_CMD:-0}" -eq 0 ]; then
  ok "CMC07 CLAUDE.md carries no narrative block"
else
  bad "CMC07 CLAUDE.md carries $BLOCKS_IN_CMD narrative block(s) — they belong in docs/chain-decisions.md (ADR-0136)"
fi

# --- B. the Rules section ------------------------------------------------------------------

# Derived population: every numbered Rules entry. Count-guarded, because an empty derivation makes
# CMC02 vacuously true and a silent pass reads exactly like coverage (ADR-0085).
RULES_N=$(sed -n '/^## Rules$/,/^## /p' "$CMD" | grep -c '^[0-9][0-9]*\. \*\*' || true)
RULES_N=${RULES_N:-0}
if [ "$RULES_N" -ge 10 ]; then
  ok "CMC03 the Rules population is non-vacuous ($RULES_N entries)"
else
  bad "CMC03 only $RULES_N Rules entries found (expected >= 10) — the derivation is broken, not clean"
fi

# Every rule cites at least one ADR, and every cited ADR exists on disk. A rule with no
# counterexample behind it is a slogan (#380's own words); a rule citing an ADR that is not there
# is worse, because it looks sourced.
_r_nocite=0; _r_dead=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  _cited=$(printf '%s' "$line" | grep -o 'ADR-[0-9][0-9][0-9][0-9]' | sort -u)
  if [ -z "$_cited" ]; then _r_nocite=$((_r_nocite+1)); continue; fi
  for _a in $_cited; do
    ls "$REPO"/docs/architecture/"$_a"-*.md >/dev/null 2>&1 || _r_dead="$_r_dead $_a"
  done
done <<EOF
$(sed -n '/^## Rules$/,/^## Chain decision index$/p' "$CMD" | awk '/^[0-9]+\. \*\*/{if(b)print b; b=$0; next} /^   /{if(b)b=b" "$0; next} {if(b){print b; b=""}} END{if(b)print b}')
EOF
if [ "$_r_nocite" -eq 0 ] && [ -z "$_r_dead" ]; then
  ok "CMC02 all $RULES_N Rules entries cite an ADR that exists on disk"
else
  bad "CMC02 $_r_nocite rule(s) cite no ADR; dead citation(s):${_r_dead:-none}"
fi

# The honesty clause. #380's DoD asks for mechanical verification that every rule is preserved; the
# set is not enumerable, so the file must say so rather than imply a guarantee it does not have.
CMD_FLAT=$(flat "$CMD")
if has_flat x "$CMD_FLAT" "this list is hand-curated"; then
  ok "CMC12 the Rules section declares itself hand-curated rather than derived"
else
  bad "CMC12 the Rules section does not declare that it is hand-curated — a reader would take the list as exhaustive, which nothing verifies (ADR-0136 premise 2)"
fi

# --- C. the index, and its agreement with the archive ---------------------------------------

IDX_N=$(grep -c '^- \*\*ADR-[0-9][0-9][0-9][0-9]\*\*' "$CMD" || true); IDX_N=${IDX_N:-0}
if [ "$IDX_N" -ge 90 ]; then
  ok "CMC06 the index population is non-vacuous ($IDX_N entries)"
else
  bad "CMC06 only $IDX_N index entries found (expected >= 90) — the derivation is broken, not clean"
fi

_i_dead=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ -f "$REPO/$p" ] || _i_dead="$_i_dead $p"
done <<EOF
$(grep '^- \*\*ADR-' "$CMD" | grep -o 'docs/architecture/[A-Za-z0-9._-]*\.md')
EOF
if [ -z "$_i_dead" ]; then
  ok "CMC04 all $IDX_N index entries point at an ADR file that exists"
else
  bad "CMC04 index entries pointing at a missing file:$_i_dead"
fi

if [ -f "$ARC" ]; then
  ARC_N=$(grep -c '^## Decisions from' "$ARC" || true); ARC_N=${ARC_N:-0}
  if [ "$IDX_N" -eq "$ARC_N" ] && [ "$ARC_N" -gt 0 ]; then
    ok "CMC05 index entries == archive blocks ($IDX_N)"
  else
    bad "CMC05 index has $IDX_N entries, the archive has $ARC_N blocks — the producer appends one of each, so a difference means one of the two writes was skipped"
  fi

  # The archive is a historical record. A stale count inside a block is a correct snapshot of its
  # day (ADR-0034, ADR-0075, ADR-0078); saying so is what stops a future reader "fixing" 95 blocks.
  ARC_FLAT=$(flat "$ARC")
  if has_flat x "$ARC_FLAT" "is not corrected in place"; then
    ok "CMC08 the archive declares itself a historical record that is not corrected in place"
  else
    bad "CMC08 the archive does not state that it is not corrected in place — without it, its stale counts read as defects to be fixed rather than as snapshots"
  fi
else
  bad "CMC05 $ARC does not exist — the narrative has nowhere to go"
  bad "CMC08 $ARC does not exist"
fi

# --- D. the producer -------------------------------------------------------------------------
# Without this section the condensation is a one-off: measured re-growth over the last six merged
# features is 55, 55, 49, 76, 61 and 56 lines, so a ~250-line file doubles in four features.

S_FLAT=$(flat "$SKILL")

if has_flat x "$S_FLAT" "append it to <project-root>/docs/chain-decisions.md if that file exists"; then
  ok "CMC09 Step 3 Branch A appends the narrative block to the archive"
else
  bad "CMC09 Step 3 Branch A does not append the block to docs/chain-decisions.md — the producer still grows CLAUDE.md by ~58 lines per feature (ADR-0136)"
fi

if has_flat x "$S_FLAT" "index line — always" \
   && has_flat x "$S_FLAT" "rules line — only when the adr establishes a recurring invariant that is not already in"; then
  ok "CMC10 the index line is unconditional and the Rules line conditional"
else
  bad "CMC10 Step 3 Branch A does not state one-index-line-always plus a conditional Rules line — an unconditional Rules line reintroduces the restatement #380 measured at over two hundred occurrences"
fi

# The old guard warned above 180 and recommended claude-md-slim: it fired on every run for months
# against a 3,895-line file, and #380 measured that remedy at 3.0% yield on this exact file. Both
# halves are asserted — a ceiling that can be met, and no revival of the dead remedy.
_ceil_ok=0; _slim_ok=0
has_flat x "$S_FLAT" "if the count exceeds 400, prepend to the" && _ceil_ok=1
printf '%s' "$S_FLAT" | grep -q "consider running /skill claude-md-slim on this file" || _slim_ok=1
if [ "$_ceil_ok" -eq 1 ] && [ "$_slim_ok" -eq 1 ]; then
  ok "CMC11 the ceiling guard is 400 and no longer recommends claude-md-slim"
else
  bad "CMC11 ceiling-at-400 present=$_ceil_ok, claude-md-slim recommendation absent=$_slim_ok (need both=1)"
fi

# --- Z. floor ---------------------------------------------------------------------------------
# A floor, not an exact count, so a new assertion does not require a bump — but it must track the
# population, because a floor carrying slack absorbs its own plant (ADR-0124, and RH2's lesson).
_total=$((PASS + FAIL))
if [ "$_total" -ge 12 ]; then
  ok "CMCZ1 assertion-count floor ($_total >= 12)"
else
  bad "CMCZ1 assertion count fell to $_total (floor 12) — assertions vanished from this file"
fi

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
