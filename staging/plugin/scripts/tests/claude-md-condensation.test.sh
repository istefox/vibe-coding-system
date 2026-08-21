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
# DISCLOSED, NOT CHASED: CMC01-CMC03, CMC07 and CMC12 read CLAUDE.md at the REPO ROOT and carry no
# plant. The reason written here until ADR-0163 was that plant-check.sh copies only staging/ and
# docs/ into its sandbox, so a root file is unplantable by construction. THAT REASON IS NO LONGER
# TRUE and had not been for some time: build_sandbox() copies CLAUDE.md, PROJECT.md, .gitignore and
# .github/ as well, and the comment above it records the measurement that forced it (26 harnesses
# failing, 58 pairs RED before any mutation). The five are unplanted today because nobody has
# planted them, which is a different sentence and a smaller one. Widening that coverage is its own
# issue; the correction is here so the next reader does not inherit the premise this one did.
#
# AND THAT IS NOT THE SAME AS BEING HARMLESS. The eight assertions that used to sit behind an ABORT
# were the reason the four plants below did not fire: the file used to ABORT when CLAUDE.md was
# absent, so no assertion of any kind ran. Five are SKIPPED there now — see the guard below the
# variable block. An unplantable assertion must still not take the plantable ones down with it.
#
# CMC06 carries NO plant, and that is a property of the assertion, not an oversight: it is a
# `>= 90` floor over 117 entries, so no single-line mutation this grammar can express takes it RED
# (rule 10 — a floor absorbs its own plant). It is kept as a vacuity guard on the derivation and the
# site says so; CMC05's exact equality is where a plant actually bites.
# plant: CMC04 | ../docs/chain-decision-index.md | docs/architecture/ADR-0011-clean-public-repo-anonymize.md | docs/architecture/ADR-0011-deliberately-absent.md
# plant: CMC05 | ../docs/chain-decision-index.md | - **ADR-0015**
# plant: CMC08 | ../docs/chain-decisions.md | It is a historical record and is not corrected in place | It is a historical record and may be corrected in place
# plant: CMC09 | plugin/skills/concept-to-code/SKILL.md | Append it to `<project-root>/docs/chain-decisions.md` if that file exists | Append it to CLAUDE.md if that file exists
# plant: CMC10 | plugin/skills/concept-to-code/SKILL.md | Rules line — only when the ADR establishes a recurring invariant that is not already in | Rules line — always, appended unconditionally alongside the index line and not already in
# plant: CMC11 | plugin/skills/concept-to-code/SKILL.md | If the count exceeds 400, prepend to the | If the count exceeds 180, prepend to the
# plant: CMC13 | plugin/skills/concept-to-code/SKILL.md | Append it to `<project-root>/docs/chain-decision-index.md` if that | Append it to `<project-root>/CLAUDE.md.proposed` if that
# ------------------------------------------------------------------------------------------

set -u
cd "$(dirname "$0")/../../.." || exit 1          # -> staging/
REPO=$(cd .. && pwd)
SKILL="plugin/skills/concept-to-code/SKILL.md"
CMD="$REPO/CLAUDE.md"
ARC="$REPO/docs/chain-decisions.md"
IDX="$REPO/docs/chain-decision-index.md"

PASS=0; FAIL=0; SKIP=0
ok()   { echo "PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
skip() { echo "SKIP: $1"; SKIP=$((SKIP+1)); }

# Prose needles match a FLATTENED, UNDECORATED, CASE-INSENSITIVE copy: a clause is the same clause
# whether it wraps across lines, is backticked, is bolded, or opens a sentence (ADR-0073, ADR-0076,
# ADR-0080, ADR-0098, ADR-0101 — the decoration family, met five times). Structural checks below
# stay line-wise on purpose, because there the decoration IS the structure.
flat() { tr '\n' ' ' < "$1" | tr -d '`*_' | tr 'A-Z' 'a-z' | sed 's/  */ /g'; }
has_flat() { printf '%s' "$2" | grep -qF "$(printf '%s' "$3" | tr -d '`*_' | tr 'A-Z' 'a-z' | sed 's/  */ /g')"; }

[ -f "$SKILL" ] || { echo "FAIL: $SKILL not found"; exit 1; }

# THE ABORT THAT ATE FOUR PLANTS. This file used to exit 1 here when CLAUDE.md was absent. Inside
# plant-check.sh's sandbox it is ALWAYS absent — the sandbox is `cp -R` of staging/ and docs/ only,
# with no repo root — so the harness died before printing a single line, no `FAIL: CMC08` was ever
# emitted, and plant-check's verdict (`grep -q "^FAIL: $aid"`) correctly read all four plants as
# NOT FIRED. The plants pinned nothing, and the abort is why. Found by the registry on its first
# real run against this file; the per-plant check done while writing it had used a copy that still
# had the repo root, which is exactly the environment the sandbox is not.
#
# So the CLAUDE.md-dependent assertions are now SKIPPED rather than aborting the file, and skipping
# is a THIRD state printed as `SKIP:` — never counted as a pass (rule 4: a check that could not run
# must not read as a check that found nothing). CMCZ1 below counts skips into its floor, so the
# eight cannot quietly disappear instead of being skipped.
#
# Discriminated by the ABSENCE OF .git, not by the absence of CLAUDE.md. Keying on CLAUDE.md itself
# would make a genuinely deleted CLAUDE.md in a real checkout skip the five assertions that exist to
# guard it — the fail-open this whole file is about. Note that since build_sandbox() started copying
# CLAUDE.md this branch is no longer reached from plant-check.sh at all (ADR-0163); it is kept as
# the fail-safe it always was, not as a sandbox accommodation.
CMD_PRESENT=0
if [ -f "$CMD" ]; then
  CMD_PRESENT=1
elif [ -d "$REPO/.git" ]; then
  echo "FAIL: CLAUDE.md not found at $CMD, and this IS a real checkout (.git present)"
  exit 1
fi
cmd_skip() { skip "$1 — CLAUDE.md unreachable and $REPO has no .git, so this is not a checkout (ADR-0136, ADR-0163)"; }

# --- A. the condensed file's shape ---------------------------------------------------------

CEILING=400
if [ "$CMD_PRESENT" -eq 0 ]; then
  cmd_skip "CMC01"; cmd_skip "CMC07"; cmd_skip "CMC03"; cmd_skip "CMC02"
  cmd_skip "CMC12"
else
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
fi   # end of the CMD_PRESENT guard opened in section A

# --- C. the index, and its agreement with the archive ---------------------------------------
# The index moved to docs/chain-decision-index.md (ADR-0163), so these three no longer read
# CLAUDE.md and are OUTSIDE the guard above. Their subject lives under docs/, which the plant
# sandbox copies and every real checkout has, so an absent index is a DEFECT and not an
# environment: bad, never skip. That is rule 4 pointing the other way, and it is why this is not
# the placement CMC08 has for the opposite reason.

if [ ! -f "$IDX" ]; then
  bad "CMC06 $IDX does not exist — the index has nowhere to live"
  bad "CMC04 $IDX does not exist"
  bad "CMC05 $IDX does not exist"
else
IDX_N=$(grep -c '^- \*\*ADR-[0-9][0-9][0-9][0-9]\*\*' "$IDX" || true); IDX_N=${IDX_N:-0}
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
$(grep '^- \*\*ADR-' "$IDX" | grep -o 'docs/architecture/[A-Za-z0-9._-]*\.md')
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
else
  bad "CMC05 $ARC does not exist — the narrative has nowhere to go"
fi
fi   # end of the index-presence guard opened above

# CMC08 reads ONLY the archive, which the sandbox does copy (ADR-0116's ../docs/ hatch), so it sits
# OUTSIDE the CLAUDE.md guard above — that placement is what makes its plant reachable at all.
if [ -f "$ARC" ]; then
  # The archive is a historical record. A stale count inside a block is a correct snapshot of its
  # day (ADR-0034, ADR-0075, ADR-0078); saying so is what stops a future reader "fixing" 95 blocks.
  ARC_FLAT=$(flat "$ARC")
  if has_flat x "$ARC_FLAT" "is not corrected in place"; then
    ok "CMC08 the archive declares itself a historical record that is not corrected in place"
  else
    bad "CMC08 the archive does not state that it is not corrected in place — without it, its stale counts read as defects to be fixed rather than as snapshots"
  fi
else
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

if has_flat x "$S_FLAT" "append it to <project-root>/docs/chain-decision-index.md if that file exists"; then
  ok "CMC13 Step 3 sends the index line to docs/chain-decision-index.md"
else
  bad "CMC13 Step 3 does not append the index line to docs/chain-decision-index.md — the producer writes it back into CLAUDE.md and the condensation undoes itself one feature at a time (ADR-0163)"
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
#
# SKIP is counted in. Without it the sandbox run would report a floor of 4 and either fail for the
# wrong reason or need a slack the plants would then absorb (ADR-0124). Counting skips keeps ONE
# floor honest in both environments: an assertion that vanished is not replaced by a skip, because
# a skip is printed by name.
_total=$((PASS + FAIL + SKIP))
if [ "$_total" -ge 13 ]; then
  ok "CMCZ1 assertion-count floor ($_total >= 13; $SKIP skipped)"
else
  bad "CMCZ1 assertion count fell to $_total (floor 13) — assertions vanished from this file"
fi

echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[ "$FAIL" -eq 0 ]
