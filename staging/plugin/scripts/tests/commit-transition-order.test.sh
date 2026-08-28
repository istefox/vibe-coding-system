#!/bin/bash
# commit-transition-order.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash commit-transition-order.test.sh
#
# Issue #410 (and #357, filed 8 days earlier — the same defect, see ADR-0135 §Context). concept-to-code
# Step 7 invokes the `commit` skill and only afterwards transitions the manifest to `completed`, so the
# committed manifest is still `step_7_commit` / `in_progress`, and the transition that follows is an
# uncommitted change nothing ever commits. `manifest-validate.sh` invariant 4 (ADR-0078, extended to
# both terminality axes by ADR-0113) exempts a dead `project_root` only on a terminal manifest, so this
# validates on the machine that produced it and fails everywhere else — green locally, red on CI.
#
# THIS FILE IS WRITTEN AGAINST THE PRE-FIX FILE, ON PURPOSE (ADR-0101 rule 1 outranks rule 2 — an
# assertion must not sit in the same batch as the task it depends on, even though the checkpoint is
# red). CTO03, CTO04, CTO05, CTO11, CTO14 are RED here and green only after Task 2 (CTO03/CTO11) and
# Task 3 (CTO04/CTO05/CTO14 fully). A red assertion left red at this checkpoint is the deliverable,
# not a defect — see the plan's Batching table.
#
# THE RULE (ADR-0135 §D5) — for every non-exempt `commit` skill invocation in
# concept-to-code/SKILL.md, the NEAREST PRECEDING manifest write must be a
# `manifest-transition.sh … completed completed` call. Not proximity, not adjacency in a
# {transition, commit} stream, not a region bounded by successive commit invocations — each of those
# PASSES the pre-fix file (ADR-0135 §D5's three rejected alternatives, re-verified against this file
# below), which disqualifies it: an assertion that cannot go RED on the defect it was commissioned for
# pins nothing.
#
# THREE PREDICATES, anchored on the two MECHANISMS themselves, never on a heading or a block
# delimiter (ADR-0083 §D3 measured heading-anchored extractors going silently vacuous — plan-task-count
# lost six assertions outright on a rename, scope-guards misattributed its own failure to the thing it
# was guarding). A rename that breaks THIS guard is the same rename that breaks the thing being guarded:
#
#   commit invocation  — the line BEGINS with `Invoke` or `Use`, optionally `the`, then `commit` (bare
#     or backticked), then the word `skill`. Narrow and loud on purpose: a future "Now invoke the
#     commit skill" is invisible to it, and the count guard (CTO02) is what turns THAT into a loud
#     failure instead of a silent one. A file-wide case-insensitive "commit...skill" grep matches 12
#     lines on the live file, mostly prose about the skill — this predicate resolves to exactly 4.
#   manifest write     — any line naming a `manifest-<word>.sh` helper. Deliberately BROAD: it matches
#     a mere MENTION as well as an invocation, so a prose sentence naming a helper, inserted between a
#     transition and its invocation, reddens the guard. Correct direction, no waiver — an unused waiver
#     is an untested waiver (ADR-0084 S2), and the remedy if this ever fires spuriously is to move the
#     sentence, not to excuse the line.
#   terminal transition — `manifest-transition.sh … completed completed`. NOTE: this is NOT a
#     same-to-same `current_step` no-op. `manifest-transition.sh`'s grammar is
#     `<manifest-path> <new-current-step> [<new-status>]` — the second `completed` is the STATUS
#     argument, so this call sets current_step AND status to `completed` in one shot. Confirmed by
#     reading the script directly, not assumed from the two repeated words.
#
# THE PAIRING RULE: for each non-exempt commit invocation, the nearest PRECEDING manifest write must
# be a member of the terminal-transition set. `order_check()` below implements exactly that, over an
# ARGUMENT (a file path), so it runs unchanged against the live file and against small fixtures.
#
# INSTANCE NUMBER, RE-DERIVED (ADR-0086), NOT COPIED FROM THE PLAN. The plan drafted this as instance
# 14 — WRONG, already claimed: skill-fence-positional-tokens.test.sh's own header literally reads
# "instance 14" (ADR-0132), a real marker, not a stale reference. Grepped every
# `staging/plugin/scripts/tests/*.sh` header for a literal `instance N` claim: 1, 2, 3, 4, 5, 6, 8, 9,
# 10 (claimed twice — concept-to-code-bsd-autopilot-gates.test.sh AND conductor-entry-failure-split.test.sh),
# 11, 12 (claimed twice — manifest-field-state.test.sh's own two sections, ADR-0119/ADR-0125 per
# CLAUDE.md) and 14 each carry a literal marker. 7 (ADR-0087) and 13 (ADR-0131's own text, for
# mode-binding-check.sh) are CONSUMED but carry NO literal marker in their own file — the same
# disclosed gap concept-to-code-manifest-helpers-guards.test.sh already records for 7, now also true of
# 13. So 1 through 14 are ALL accounted for, by marker or by disclosed-but-unmarked consumption, and
# nothing above 14 exists anywhere in this tree. This file is instance 15. The numbering has now
# collided or gone silently unmarked often enough (10, 12, 13, and the near-miss at 14 this file would
# have caused) that "grep the plan" is not a safe source for this number — grep the files.
#
# WHY A NEW FILE, NOT AN EXTENSION (ADR-0086's criterion: extract/share only when two copies giving
# different answers would be a defect). Three existing files touch this region —
# step7-snapshot-collapse.test.sh (Step 7.0), spec-pointer-archive.test.sh (Step 7.0b),
# transition-producer.test.sh (the transition graph) — and none of them owns "is the terminal
# transition ordered before the commit that ships the manifest", which spans three steps in two paths.
# It is its own population asking its own question.
#
# TASK SPLIT (ADR-0088/plan): this file grows in three later tasks, all tester-owned. Task 4 adds
# CTO12/CTO13 (the commit-outcome fence) and raises CTOZ1's floor in the same edit. Task 6 adds the
# `# plant:` block. As of Task 1's own commit, neither existed yet — Task 1 wrote assertions only,
# per its own brief. As of THIS edit (Task 4), CTO12/CTO13 exist below and are RED: the fence they
# extract (`c2c-step7-commit-outcome`) does not exist until Task 5 writes it — the declared,
# expected checkpoint state (plan's Batching table, Batch C), not a defect. Task 6's `# plant:`
# block is added below (issue #410, ADR-0135, R-15).
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes or inverts ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing (ADR-0108). CTO04/CTO05/CTO14/CTO11 target
# SKILL.md; the rest are self-targeting (this file), masked out of their own needle search by
# plant-check.sh so a self-targeting plant is expressible at all.
#
# CTO04/CTO05/CTO14 EACH TARGET A DIFFERENT ONE OF THE THREE TRANSITIONS (Standard/Express/Hybrid).
# The needle is the transition's unique COMMENT LINE joined to its COMMAND — the bare command
# (`bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed
# completed`) matches 2-3 sites on the live file (Gate E3's abort branch shares it) and is rejected
# by plant-check.sh's exactly-one-match rule; the comment is what disambiguates. CTO04 drops the
# Standard transition's trailing `completed` (the STATUS argument), so TERM_RE stops matching that
# line and the nearest preceding write for Step 7's commit invocation is no longer a terminal
# transition. CTO05 does the same to Express, which drops OC_OK from 3 to 2 (< 3). CTO14 replaces
# Hybrid's invocation with prose — the INVOCATION SHAPE is what it asserts, never the helper's bare
# name (rule 12; `SP1`'s exact history, named in this file's own header above).
#
# plant: CTO04 | plugin/skills/concept-to-code/SKILL.md | # Standard path: terminal before the commit invocation below (issue #410, ADR-0135). bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh "<manifest-path>" completed completed | # Standard path: terminal before the commit invocation below (issue #410, ADR-0135). bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh "<manifest-path>" completed
# plant: CTO05 | plugin/skills/concept-to-code/SKILL.md | # Express path: terminal before the commit invocation below (issue #410, ADR-0135). bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed | # Express path: terminal before the commit invocation below (issue #410, ADR-0135). bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed
# plant: CTO14 | plugin/skills/concept-to-code/SKILL.md | # Hybrid path: terminal before the commit invocation below (issue #410, ADR-0135). bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed | # Hybrid path: terminal before the commit invocation below (issue #410, ADR-0135). Transition the manifest to completed and completed using the transition helper before invoking commit.
#
# CTO11 — the invariant sentence itself (ADR-0135 §D2), flattened/undecorated/case-insensitive at
# assertion time but matched here against the RAW text (backticks included, since plant-check.sh
# does not flatten before substituting) — the needle carries the literal backtick-wrapped `` `commit` ``
# token for exactly that reason.
#
# plant: CTO11 | plugin/skills/concept-to-code/SKILL.md | Every manifest write in this step precedes the `commit` invocation, and this transition is the last of them | Manifest writes in this step happen at various points relative to the `commit` invocation, and ordering is not fixed
#
# CTO01/CTO02 — the two denominator predicates (ADR-0085: guard the denominator, not just the
# matches). Each mutation narrows WRITE_RE/COMMIT_RE to a token that appears nowhere in the live
# file, so the derivation returns 0 lines instead of >=25 / >=4.
#
# plant: CTO01 | plugin/scripts/tests/commit-transition-order.test.sh | WRITE_RE='manifest-[a-zA-Z0-9_-]*\.sh' | WRITE_RE='manifest-nonexistent-[a-zA-Z0-9_-]*\.sh'
# plant: CTO02 | plugin/scripts/tests/commit-transition-order.test.sh | COMMIT_RE='^(Invoke|Use)([[:space:]]+the)?[[:space:]]+`?commit`?[[:space:]]+skill' | COMMIT_RE='^(Invoke|Use)([[:space:]]+the)?[[:space:]]+`?ZZZNEVERMATCHZZZ`?[[:space:]]+skill'
#
# CTO03 — the waiver-reversal check (ADR-0081 `ZA4`'s direction). Widening the reason-length
# threshold from `< 40` to `< 9999` makes the check flag the LIVE, actually-valid Gate 4.0 waiver as
# malformed — proof the check reads the real exemption's reason length, not merely its presence.
#
# plant: CTO03 | plugin/scripts/tests/commit-transition-order.test.sh | if [ "${#_ereason}" -lt 40 ]; then | if [ "${#_ereason}" -lt 9999 ]; then
#
# CTO06/CTO07/CTO08/CTO09 — each fixture's `order_check` call is retargeted from its own small,
# purpose-built fixture file to `$C2C` (the live, correctly-ordered SKILL.md: OC_N=3, OC_OK=3,
# OC_BAD=0). Every one of the four assertions requires a DIFFERENT OC_N/OC_OK/OC_BAD combination
# than the live file produces, so redirecting any one of them to `$C2C` breaks exactly that
# assertion. This is a fixture SWAP, not a fixture deletion: CTO09's fixture asserts an isolated
# transition has NO invocation counted after it (OC_N==0) — a negative claim — and retargeting to
# `$C2C` REINTRODUCES three real invocations into what the fixture claims has none, rather than
# merely deleting the guard (ADR-0089's rule for negative assertions).
#
# plant: CTO06 | plugin/scripts/tests/commit-transition-order.test.sh | order_check "$TMP/fx06.txt" | order_check "$C2C"
# plant: CTO07 | plugin/scripts/tests/commit-transition-order.test.sh | order_check "$TMP/fx07.txt" | order_check "$C2C"
# plant: CTO08 | plugin/scripts/tests/commit-transition-order.test.sh | order_check "$TMP/fx08.txt" | order_check "$C2C"
# plant: CTO09 | plugin/scripts/tests/commit-transition-order.test.sh | order_check "$TMP/fx09.txt" | order_check "$C2C"
#
# CTO10 — the other negative assertion (Gate E3's "Commit later" branch has no commit invocation
# after it). Deleting the extraction cannot be planted honestly (an empty block trivially satisfies
# "no invocation found" for the wrong reason); instead the required co-occurring text is corrupted
# so the compound condition can never be satisfied even though the real content is unchanged —
# INVERTING the condition rather than deleting the mechanism (ADR-0089).
#
# plant: CTO10 | plugin/scripts/tests/commit-transition-order.test.sh | grep -q 'No commit skill invoked'; then | grep -q 'No commit skill invoked TOTALLY-ABSENT-STRING'; then
#
# CTO12 — fixture Case A ("terminal, committed, clean" -> COMMIT_OK) is rebuilt non-terminal
# (`step_7_commit`/`in_progress`) while its git setup and its comment still claim terminal, so the
# real `c2c-step7-commit-outcome` fence correctly returns COMMIT_NONTERMINAL and case A's own check
# fails — proof the assertion is reading the fence's actual output, not a hardcoded pass.
#
# plant: CTO12 | plugin/scripts/tests/commit-transition-order.test.sh | mk_manifest "$FXA/manifest.yml" completed completed | mk_manifest "$FXA/manifest.yml" step_7_commit in_progress
#
# CTO13 — one of the four required, jointly-improbable words (`absorbing`) is corrupted in the
# test's own grep pattern so the compound AND can never be satisfied, regardless of what Step 7.1
# actually says.
#
# plant: CTO13 | plugin/scripts/tests/commit-transition-order.test.sh | grep -qi 'absorbing' | grep -qi 'absorbingXYZNEVERMATCH'
#
# CTOZ1 — the assertion-count floor itself (ADR-0083 §D3, ADR-0124's warning against a floor that
# carries slack). Raised past what this file can ever produce, so it always fails — the same
# always-red control used by every sibling Z1 plant in this tree.
#
# plant: CTOZ1 | plugin/scripts/tests/commit-transition-order.test.sh | "$_total" -ge 14 | "$_total" -ge 999
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
C2C="$STAGING/plugin/skills/concept-to-code/SKILL.md"
HITL_REF="$STAGING/plugin/skills/concept-to-code/references/hitl-gates.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$C2C" ] || { echo "FATAL: missing $C2C"; exit 1; }
[ -f "$HITL_REF" ] || { echo "FATAL: missing $HITL_REF"; exit 1; }

# VCS-048/ADR-0175: ## 5. HITL gates moved into references/hitl-gates.md. order_check() reads a
# single file positionally (nearest-preceding-write by line number), so Gate 4.0's commit
# invocation, its preceding manifest write and its commit-order-exempt waiver — all now living in
# HITL_REF — need to be spliced back into the heading's old position (merged-view-splice,
# ADR-0174 D4) for the LIVE derivation to see the same population it saw before the move.
C2C_MERGED="$TMP/c2c_merged.md"
awk -v reffile="$HITL_REF" '
  /^## 5\. HITL gates/ {
    print
    while ((getline line < reffile) > 0) print line
    close(reffile)
    skip=1
    next
  }
  skip && /^## 6\. Coexistence invariants/ { skip=0 }
  skip { next }
  { print }
' "$C2C" > "$C2C_MERGED"

# ---------------------------------------------------------------------------
# The three predicates, as functions over an ARGUMENT file — never hardcoded to $C2C — so
# order_check() below runs identically against the live file and against fixtures.
# ---------------------------------------------------------------------------
COMMIT_RE='^(Invoke|Use)([[:space:]]+the)?[[:space:]]+`?commit`?[[:space:]]+skill'
WRITE_RE='manifest-[a-zA-Z0-9_-]*\.sh'
TERM_RE='manifest-transition\.sh.*completed[[:space:]]+completed'

derive_commit_lines() { grep -nE "$COMMIT_RE" "$1" | cut -d: -f1 | sort -n; }
derive_write_lines()  { grep -noE "$WRITE_RE" "$1" | cut -d: -f1 | sort -n -u; }
derive_term_lines()   { grep -nE "$TERM_RE" "$1" | cut -d: -f1 | sort -n; }

# order_check <file> — sets OC_CN/OC_WN/OC_TN (population sizes) and OC_N (non-exempt invocations),
# OC_OK, OC_BAD, OC_WHY (line numbers and the offending write, for the message). Re-derives all three
# predicates FROM THE GIVEN FILE on every call — no state survives between calls except what is copied
# out by the caller immediately after.
order_check() {
  _ocf="$1"
  derive_commit_lines "$_ocf" >"$TMP/oc_commit.txt"
  derive_write_lines  "$_ocf" >"$TMP/oc_write.txt"
  derive_term_lines   "$_ocf" >"$TMP/oc_term.txt"
  OC_CN=$(wc -l <"$TMP/oc_commit.txt" | tr -d ' ')
  OC_WN=$(wc -l <"$TMP/oc_write.txt"  | tr -d ' ')
  OC_TN=$(wc -l <"$TMP/oc_term.txt"   | tr -d ' ')

  OC_N=0; OC_OK=0; OC_BAD=0; OC_WHY=""
  while IFS= read -r _n; do
    [ -n "$_n" ] || continue
    _ocline=$(sed -n "${_n}p" "$_ocf")
    case "$_ocline" in
      *commit-order-exempt:*) continue ;;   # waiver on the SAME line — excluded from the population
    esac
    OC_N=$((OC_N + 1))
    _oclast=$(awk -v n="$_n" '$1 < n {last=$1} END{print last}' "$TMP/oc_write.txt")
    if [ -z "$_oclast" ]; then
      OC_BAD=$((OC_BAD + 1))
      OC_WHY="$OC_WHY
  line $_n: no manifest write precedes this invocation at all"
      continue
    fi
    if grep -qxF "$_oclast" "$TMP/oc_term.txt"; then
      OC_OK=$((OC_OK + 1))
    else
      OC_BAD=$((OC_BAD + 1))
      OC_WHY="$OC_WHY
  line $_n: nearest preceding manifest write is line $_oclast, not a completed-completed transition"
    fi
  done <"$TMP/oc_commit.txt"
}

# ===========================================================================
# Live derivation, once, snapshotted — later fixture calls to order_check() overwrite OC_*, and the
# LIVE_* copies are what CTO01/CTO02/CTO04/CTO05 read.
# ===========================================================================
order_check "$C2C_MERGED"
LIVE_CN=$OC_CN; LIVE_WN=$OC_WN; LIVE_TN=$OC_TN
LIVE_N=$OC_N;   LIVE_OK=$OC_OK; LIVE_BAD=$OC_BAD; LIVE_WHY=$OC_WHY

# ===========================================================================
# CTO01/CTO02 — denominators. Fewer than expected means a predicate stopped matching, which empties
# order_check's population and reads exactly like a clean file (ADR-0085: guard the denominator).
# ===========================================================================
if [ "$LIVE_WN" -ge 25 ]; then
  ok "CTO01 manifest-write denominator non-vacuous on the live file ($LIVE_WN >= 25)"
else
  bad "CTO01 manifest-write derivation returned $LIVE_WN lines (expected >= 25) — the write predicate stopped matching, which empties CTO04/CTO05 and reads as clean"
fi

if [ "$LIVE_CN" -ge 4 ]; then
  ok "CTO02 commit-invocation denominator non-vacuous on the live file ($LIVE_CN >= 4)"
else
  bad "CTO02 commit-invocation derivation returned $LIVE_CN lines (expected >= 4) — Step 7, E4, H5 or Gate 4.0 dropped out of the population"
fi

# ===========================================================================
# CTO03 — the waiver runs in reverse: every declared exemption sits on a line the commit-invocation
# predicate matches, with a reason >= 40 chars on that same line. A stale waiver reads exactly like a
# clean bill of health (ADR-0081 ZA4). RED until Task 2 adds Gate 4.0's waiver — EXEMPT_N is 0 today.
# ===========================================================================
EXEMPT_LINES="$TMP/exempt.txt"
grep -n 'commit-order-exempt:' "$C2C_MERGED" | cut -d: -f1 | sort -n >"$EXEMPT_LINES" 2>/dev/null || : >"$EXEMPT_LINES"
EXEMPT_N=$(wc -l <"$EXEMPT_LINES" | tr -d ' ')

derive_commit_lines "$C2C_MERGED" >"$TMP/live_commit.txt"

_waiver_bad=""
while IFS= read -r _en; do
  [ -n "$_en" ] || continue
  if ! grep -qxF "$_en" "$TMP/live_commit.txt"; then
    _waiver_bad="$_waiver_bad
  line $_en: exemption marker is not on a recognised commit-invocation line"
    continue
  fi
  _ewline=$(sed -n "${_en}p" "$C2C_MERGED")
  _ereason=$(printf '%s' "$_ewline" | sed 's/.*commit-order-exempt:[[:space:]]*//; s/-->.*//')
  if [ "${#_ereason}" -lt 40 ]; then
    _waiver_bad="$_waiver_bad
  line $_en: exemption reason is under 40 chars"
  fi
done <"$EXEMPT_LINES"

if [ "$EXEMPT_N" -ge 1 ] && [ -z "$_waiver_bad" ]; then
  ok "CTO03 every declared commit-order-exempt waiver sits on a commit-invocation line with a reason >= 40 chars ($EXEMPT_N declared)"
else
  bad "CTO03 waiver check failed ($EXEMPT_N declared; expected >= 1 with none malformed):$_waiver_bad"
fi

# ===========================================================================
# CTO04 — live: every non-exempt commit invocation is preceded by a completed-completed transition.
# RED until Task 3. (R-03, R-09)
# ===========================================================================
if [ "$LIVE_BAD" -eq 0 ]; then
  ok "CTO04 every non-exempt commit invocation ($LIVE_N checked) is preceded by a completed-completed transition"
else
  bad "CTO04 $LIVE_BAD of $LIVE_N non-exempt commit invocation(s) are NOT preceded by a completed-completed transition:$LIVE_WHY"
fi

# ===========================================================================
# CTO05 — live: at least 3 commit invocations resolve correctly. A count guard, not a floor for
# convenience — a step dropping out of the population must fail loudly rather than shrink the
# denominator silently. RED until Task 3. (R-11)
# ===========================================================================
if [ "$LIVE_OK" -ge 3 ]; then
  ok "CTO05 at least 3 commit invocations correctly ordered ($LIVE_OK of $LIVE_N)"
else
  bad "CTO05 only $LIVE_OK of $LIVE_N commit invocations are correctly ordered (need >= 3)"
fi

# ===========================================================================
# CTO06 — fixture, wrong order: a commit invocation with the terminal transition AFTER it. Exactly 1
# violation. This is the RED direction, permanently. Anchor strings copied verbatim from the live file
# (lines 2727 and 2866). (R-16)
# ===========================================================================
printf '%s\n' \
  'Use the commit skill (invoke via Skill tool, not Agent tool).' \
  'bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed' \
  >"$TMP/fx06.txt"
order_check "$TMP/fx06.txt"
if [ "$OC_BAD" -eq 1 ] && [ "$OC_OK" -eq 0 ]; then
  ok "CTO06 fixture: commit invocation with the terminal transition AFTER it is exactly 1 violation"
else
  bad "CTO06 fixture returned OC_OK=$OC_OK OC_BAD=$OC_BAD — expected 0/1$OC_WHY"
fi

# ===========================================================================
# CTO07 — fixture, right order: 0 violations, 1 resolved. The positive twin of CTO06 — a negative
# assertion pins nothing without it (ADR-0039's rule).
# ===========================================================================
printf '%s\n' \
  'bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed' \
  'Use the commit skill (invoke via Skill tool, not Agent tool).' \
  >"$TMP/fx07.txt"
order_check "$TMP/fx07.txt"
if [ "$OC_OK" -eq 1 ] && [ "$OC_BAD" -eq 0 ]; then
  ok "CTO07 fixture: right order resolves — 0 violations, 1 resolved"
else
  bad "CTO07 fixture returned OC_OK=$OC_OK OC_BAD=$OC_BAD — expected 1/0$OC_WHY"
fi

# ===========================================================================
# CTO08 — fixture, a manifest-set-artifact.sh line BETWEEN the transition and the invocation: 1
# violation. This is what makes ADR-0135 §D1's 7.0b-then-7.0c ordering enforced rather than merely
# written down. Anchor string copied verbatim from the live file (line 2712). (R-04)
# ===========================================================================
printf '%s\n' \
  'bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed' \
  '  `bash ~/.claude/skills/concept-to-code/scripts/manifest-set-artifact.sh <manifest-path> spec <path>`.' \
  'Use the commit skill (invoke via Skill tool, not Agent tool).' \
  >"$TMP/fx08.txt"
order_check "$TMP/fx08.txt"
if [ "$OC_BAD" -eq 1 ] && [ "$OC_OK" -eq 0 ]; then
  ok "CTO08 fixture: a manifest-set-artifact.sh write between the transition and the invocation is exactly 1 violation"
else
  bad "CTO08 fixture returned OC_OK=$OC_OK OC_BAD=$OC_BAD — expected 0/1$OC_WHY"
fi

# ===========================================================================
# CTO09 — fixture, a terminal transition with NO invocation after it: 0 violations, 0 resolved. Gate
# E3's "Commit later" and the abort branches, in isolation. (R-12)
# ===========================================================================
printf '%s\n' \
  'bash ~/.claude/skills/concept-to-code/scripts/manifest-transition.sh <manifest-path> completed completed' \
  >"$TMP/fx09.txt"
order_check "$TMP/fx09.txt"
if [ "$OC_N" -eq 0 ] && [ "$OC_OK" -eq 0 ] && [ "$OC_BAD" -eq 0 ]; then
  ok "CTO09 fixture: a terminal transition with no invocation after it is 0 violations, 0 resolved"
else
  bad "CTO09 fixture returned OC_N=$OC_N OC_OK=$OC_OK OC_BAD=$OC_BAD — expected 0/0/0$OC_WHY"
fi

# ===========================================================================
# CTO10 — live: at least one terminal transition remains unpaired, and the message names Gate E3's
# "Commit later" branch as the reason it must stay that way — the guard iterates over commit
# invocations, so a terminal transition followed by no invocation is outside it STRUCTURALLY, not by
# exclusion. Green before and after this feature — a forward guard; its plant (Task 6) is its only
# evidence (ADR-0089's rule: a plant that does not fire is evidence about the assertion). (R-12)
# ===========================================================================
_ce3_start=$(grep -n '`Commit later`:' "$C2C" | head -1 | cut -d: -f1)
if [ -n "${_ce3_start:-}" ]; then
  _ce3_blk=$(awk -v a="$_ce3_start" 'NR>=a{print} /No commit skill invoked/{exit}' "$C2C")
else
  _ce3_blk=""
fi
if printf '%s\n' "$_ce3_blk" | grep -qE "$TERM_RE" && printf '%s\n' "$_ce3_blk" | grep -q 'No commit skill invoked'; then
  ok "CTO10 (forward guard) Gate E3's 'Commit later' terminal transition has no commit invocation after it"
else
  bad "CTO10 Gate E3's 'Commit later' branch no longer reads as an unpaired terminal transition — anchor \`Commit later\`: did not resolve, or the transition/no-commit sentence moved"
fi

# ===========================================================================
# CTO11 — live: Step 7 states the §D2 invariant. Matched against a copy of the Step 7 section that is
# flattened, undecorated (backticks and asterisks stripped) and case-insensitive — a clause is the same
# clause whether it wraps, is code-quoted, is bolded or opens a sentence (ADR-0073, ADR-0076, ADR-0080,
# ADR-0098, ADR-0101). RED until Task 2. (R-05)
# ===========================================================================
S7_START=$(grep -n '^### Step 7 — Commit' "$C2C" | head -1 | cut -d: -f1)
S7_END=$(grep -n '^### Express path' "$C2C" | head -1 | cut -d: -f1)
if [ -n "${S7_START:-}" ] && [ -n "${S7_END:-}" ] && [ "$S7_END" -gt "$S7_START" ]; then
  S7BLK=$(awk -v a="$S7_START" -v b="$S7_END" 'NR>=a && NR<b' "$C2C")
else
  S7BLK=""
fi
S7FLAT=$(printf '%s\n' "$S7BLK" | tr '\n' ' ' | tr -d '`*' | tr -s ' ')

if printf '%s\n' "$S7FLAT" | grep -qi 'every manifest write in this step precedes the commit invocation, and this transition is the last of them'; then
  ok "CTO11 Step 7 states the §D2 invariant (matched flattened, undecorated, case-insensitive)"
else
  bad "CTO11 Step 7 does not state the §D2 invariant (heading anchors: S7_START=${S7_START:-<none>} S7_END=${S7_END:-<none>}) — a manifest write added below the commit invocation has nothing telling the next author it must precede it"
fi

# ===========================================================================
# CTO14 — live: the Standard and Hybrid terminal transitions are manifest-transition.sh invocations
# carrying the absolute ~/.claude/skills/concept-to-code/scripts/ prefix, not prose. Asserts the
# INVOCATION SHAPE, never the helper's bare name — Step 7 will legitimately name the helper in prose
# while explaining the ordering (rule 12; SP1's exact history), and a name-needle would walk straight
# through a plant that deletes the call. RED until Tasks 2-3. (R-01, R-02)
# ===========================================================================
H5_START=$(grep -n '^#### Step H5 — Commit' "$C2C" | head -1 | cut -d: -f1)
H5_END=$(grep -n '^## 5\. HITL gates' "$C2C" | head -1 | cut -d: -f1)
if [ -n "${H5_START:-}" ] && [ -n "${H5_END:-}" ] && [ "$H5_END" -gt "$H5_START" ]; then
  H5BLK=$(awk -v a="$H5_START" -v b="$H5_END" 'NR>=a && NR<b' "$C2C")
else
  H5BLK=""
fi

# Anchored at start-of-line with no leading whitespace — every real invocation in this file is fenced
# flush-left (verified against all 3 pre-fix term_lines occurrences: :2866 and :2881 are flush-left,
# :458's usage sample is indented and correctly excluded by this same anchor).
INVOCATION_RE='^bash ~/\.claude/skills/concept-to-code/scripts/manifest-transition\.sh .*completed[[:space:]]+completed'
_s7_inv=0
printf '%s\n' "$S7BLK" | grep -qE "$INVOCATION_RE" && _s7_inv=1
_h5_inv=0
printf '%s\n' "$H5BLK" | grep -qE "$INVOCATION_RE" && _h5_inv=1

if [ "$_s7_inv" -eq 1 ] && [ "$_h5_inv" -eq 1 ]; then
  ok "CTO14 both the Standard Step 7 and Hybrid H5 terminal transitions are manifest-transition.sh invocations carrying the absolute helper path"
else
  bad "CTO14 Standard-path invocation present=$_s7_inv, Hybrid-path invocation present=$_h5_inv (need both=1) — a prose transition has no exit code and nothing to assert against"
fi

# ===========================================================================
# CTO12/CTO13 machinery (Task 4) — extract the Step 7.1 commit-outcome fence
# (`c2c-step7-commit-outcome`, ADR-0135 §D3) by its marker, never by heading or line number
# (ADR-0135 §D5's own reasoning, applied a second time in this file). The fence does not exist yet
# — Task 5 writes it — so extraction fails and CTO12/CTO13 are RED here. That is the expected,
# declared checkpoint state (plan's Batching table, Batch C), not a defect.
#
# A COPY of enumerate_fences/fence_body from fence-contract-coverage.test.sh, kept independent per
# ADR-0086: that file's question is "is every abort-capable fence declared and covered"; this one's
# is "does ONE specific fence exist and behave correctly" — a different population and a different
# question. The literal string below is one of the two needles fence-contract-coverage.test.sh's F4
# accepts as proof a declared contract is executed — written as a literal in the grep pattern
# itself, not built by interpolation, or it would satisfy nothing (rule 12; the same gap that
# file's own header names about itself).
# ===========================================================================
enumerate_fences_ct() {
  awk '
    {
      line = $0
      stripped = line; sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^<!--[[:space:]]*fence-(contract|illustration):/) { pending = stripped; next }
      if (stripped == "") { next }
      if (infence) {
        if (stripped == "```") { infence = 0 }
        next
      }
      if (stripped ~ /^```bash[[:space:]]*$/) {
        printf "%d\t%s\n", NR, (pending == "" ? "NONE" : pending)
        pending = ""; infence = 1; next
      }
      pending = ""
    }
  ' "$1"
}

fence_body_ct() {
  awk -v want="$2" '
    NR == want {
      match($0, /^[[:space:]]*/); ind = RLENGTH; infence = 1; next
    }
    infence {
      s = $0; sub(/^[[:space:]]+/, "", s)
      if (s == "```") { exit }
      match($0, /^[[:space:]]*/); lw = RLENGTH
      strip = (lw < ind) ? lw : ind
      print substr($0, strip + 1)
    }
  ' "$1"
}

extract_fence_ct() {
  _ef_ln=$(enumerate_fences_ct "$C2C" | grep -F "fence-contract: c2c-step7-commit-outcome -->" | head -1 | cut -f1)
  [ -n "$_ef_ln" ] || return 1
  fence_body_ct "$C2C" "$_ef_ln"
}

# run_outcome_fence <manifest-path> — substitutes the ONE placeholder the ADR-0135 §D3 fence takes
# (text-level, before anything is executed — exactly as the fence's own `<baseline>` sibling in
# c2c-step7-snapshot-collapse is substituted: a quoted heredoc does not expand shell variables, so
# text substitution ahead of execution is the only correct order). Runs the RAW extracted body
# (still carrying the ADR-0133 `bash <<'FENCE_BASH' ... FENCE_BASH` wrapper, if Task 5 used one) via
# a single outer `bash`, exactly as fence-contract-coverage.test.sh's own run_fence() does — the
# wrapper is just a nested heredoc invocation and is valid bash on its own. stdout and exit code are
# the fence's only communication channel; stderr is captured separately for diagnostics only and
# never matched against.
run_outcome_fence() {
  _rof_body=$(extract_fence_ct) || return 1
  [ -n "$_rof_body" ] || return 1
  printf '%s\n' "$_rof_body" | sed "s|<manifest-path>|$1|g" >"$TMP/outcome-run.sh"
  # ADR-0168 §D10 repair: after the fence resolves to commit-outcome-check.sh it does a two-tier
  # script lookup, CLAUDE_PLUGIN_ROOT first then $HOME/.claude, exactly like every other
  # concept-to-code helper. Without this export the harness would either fail on an undeployed
  # machine (COMMIT_OUTCOME_NORUN noScript on every fixture) or, on a deployed one, silently
  # exercise $HOME/.claude instead of staging/ — contradicting this file's own "no $HOME
  # dependency" header claim. Same idiom as spec-coverage-baseline-bump.test.sh's NB16.
  ( export CLAUDE_PLUGIN_ROOT="$STAGING/plugin"
    bash "$TMP/outcome-run.sh" >"$TMP/outcome-out" 2>"$TMP/outcome-err" )
  echo "$?" >"$TMP/outcome-rc"
  return 0
}

git_setup() {
  mkdir -p "$1"
  git -C "$1" init -q >/dev/null 2>&1
  git -C "$1" config user.email "test@example.com"
  git -C "$1" config user.name "Test"
  git -C "$1" config commit.gpgsign false
}

# BASE_MANIFEST: a REAL manifest from docs/manifests/, patched — never a hand-written minimal one
# (ADR-0078's lesson, restated in this task's own brief). The fence itself never calls
# manifest-validate.sh, so a hand-written manifest would not trip an unrelated invariant the way it
# does elsewhere in this repository's harness — but a real manifest still matters for a narrower
# reason: its current_step/status lines carry the EXACT quoting manifest-init.sh and
# manifest-transition.sh actually write (`current_step: "value"`), the format any real reader of
# this field has to parse.
REPO=$(cd "$STAGING/.." && pwd)
MANIFEST_VALIDATE="$STAGING/plugin/skills/concept-to-code/scripts/manifest-validate.sh"
BASE_MANIFEST=""; BASE_ROOT=""
for _bm in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$_bm" ] || continue
  if bash "$MANIFEST_VALIDATE" "$_bm" >/dev/null 2>&1; then
    BASE_MANIFEST="$_bm"
    BASE_ROOT=$(grep '^project_root:' "$_bm" | sed -e 's/^project_root:[[:space:]]*"//' -e 's/"[[:space:]]*$//')
    break
  fi
done

# mk_manifest <dest> <current_step> <status> — sed-level patch, quoting preserved.
mk_manifest() {
  [ -n "$BASE_MANIFEST" ] || return 1
  sed -e "s|$BASE_ROOT|$TMP/proj|g" \
      -e "s|^current_step:.*|current_step: \"$2\"|" \
      -e "s|^status:.*|status: \"$3\"|" "$BASE_MANIFEST" >"$1"
}
mkdir -p "$TMP/proj"

# ===========================================================================
# CTO12 — run the Step 7.1 fence against five REAL git fixtures (real `git init` + real commits, per
# this task's own brief: a fixture that cannot produce the state it names pins nothing). Each case
# is built against the FAILURE MODE it exists to catch, not merely made plausible:
#   A. terminal (current_step=status=completed), committed, clean       -> COMMIT_OK, exit 0
#      (also the resumed/already-committed/nothing-to-commit case — R-07 is what this proves)
#   B. terminal, tracked but modified after the commit                  -> COMMIT_UNCOMMITTED modified, exit 1
#   C. terminal, never added/committed (untracked)                      -> COMMIT_UNCOMMITTED untracked, exit 1
#   D. non-terminal (current_step=step_7_commit, status=in_progress),
#      committed and clean                                              -> COMMIT_NONTERMINAL, exit 1
#   E. manifest path outside any git repository                         -> COMMIT_OUTCOME_NORUN, exit 3
# B and C require the EXACT qualifier the plan's own CTO12 bullet names (`modified`/`untracked`); D
# and E require only the prefix, matching that same bullet, which names no qualifier for either —
# the fence may report `current_step` or `status` for D depending on which it checks first, and
# fixture D is built non-terminal on BOTH fields so either order still matches.
# The literal string `fence-contract: c2c-step7-commit-outcome -->` above is the F4 needle. (R-06, R-07)
# ===========================================================================
CTO12_FAIL=""
if [ -z "$BASE_MANIFEST" ]; then
  CTO12_FAIL="
  no manifest under docs/manifests/ passes manifest-validate.sh — cannot build fixtures"
else
  # Case A
  FXA="$TMP/fxA"; git_setup "$FXA"
  mk_manifest "$FXA/manifest.yml" completed completed
  git -C "$FXA" add manifest.yml >/dev/null 2>&1
  git -C "$FXA" commit -q -m init >/dev/null 2>&1
  if run_outcome_fence "$FXA/manifest.yml"; then
    _rc=$(cat "$TMP/outcome-rc"); _out=$(cat "$TMP/outcome-out")
    case "$_out" in
      "COMMIT_OK"*) [ "$_rc" -eq 0 ] || CTO12_FAIL="$CTO12_FAIL
  case A (terminal/committed/clean): exit=$_rc (expected 0), out=$_out" ;;
      *) CTO12_FAIL="$CTO12_FAIL
  case A (terminal/committed/clean): expected COMMIT_OK, got: $_out (exit $_rc)" ;;
    esac
  else
    CTO12_FAIL="$CTO12_FAIL
  case A: fence extraction failed — c2c-step7-commit-outcome not declared yet (Task 5)"
  fi

  # Case B
  FXB="$TMP/fxB"; git_setup "$FXB"
  mk_manifest "$FXB/manifest.yml" completed completed
  git -C "$FXB" add manifest.yml >/dev/null 2>&1
  git -C "$FXB" commit -q -m init >/dev/null 2>&1
  printf '\n# touched after commit\n' >>"$FXB/manifest.yml"
  if run_outcome_fence "$FXB/manifest.yml"; then
    _rc=$(cat "$TMP/outcome-rc"); _out=$(cat "$TMP/outcome-out")
    case "$_out" in
      "COMMIT_UNCOMMITTED modified"*) [ "$_rc" -eq 1 ] || CTO12_FAIL="$CTO12_FAIL
  case B (terminal/tracked-modified): exit=$_rc (expected 1), out=$_out" ;;
      *) CTO12_FAIL="$CTO12_FAIL
  case B (terminal/tracked-modified): expected 'COMMIT_UNCOMMITTED modified', got: $_out (exit $_rc)" ;;
    esac
  else
    CTO12_FAIL="$CTO12_FAIL
  case B: fence extraction failed — c2c-step7-commit-outcome not declared yet (Task 5)"
  fi

  # Case C
  FXC="$TMP/fxC"; git_setup "$FXC"
  mk_manifest "$FXC/manifest.yml" completed completed
  if run_outcome_fence "$FXC/manifest.yml"; then
    _rc=$(cat "$TMP/outcome-rc"); _out=$(cat "$TMP/outcome-out")
    case "$_out" in
      "COMMIT_UNCOMMITTED untracked"*) [ "$_rc" -eq 1 ] || CTO12_FAIL="$CTO12_FAIL
  case C (terminal/untracked): exit=$_rc (expected 1), out=$_out" ;;
      *) CTO12_FAIL="$CTO12_FAIL
  case C (terminal/untracked): expected 'COMMIT_UNCOMMITTED untracked', got: $_out (exit $_rc)" ;;
    esac
  else
    CTO12_FAIL="$CTO12_FAIL
  case C: fence extraction failed — c2c-step7-commit-outcome not declared yet (Task 5)"
  fi

  # Case D
  FXD="$TMP/fxD"; git_setup "$FXD"
  mk_manifest "$FXD/manifest.yml" step_7_commit in_progress
  git -C "$FXD" add manifest.yml >/dev/null 2>&1
  git -C "$FXD" commit -q -m init >/dev/null 2>&1
  if run_outcome_fence "$FXD/manifest.yml"; then
    _rc=$(cat "$TMP/outcome-rc"); _out=$(cat "$TMP/outcome-out")
    case "$_out" in
      "COMMIT_NONTERMINAL"*) [ "$_rc" -eq 1 ] || CTO12_FAIL="$CTO12_FAIL
  case D (non-terminal/committed/clean): exit=$_rc (expected 1), out=$_out" ;;
      *) CTO12_FAIL="$CTO12_FAIL
  case D (non-terminal/committed/clean): expected 'COMMIT_NONTERMINAL', got: $_out (exit $_rc)" ;;
    esac
  else
    CTO12_FAIL="$CTO12_FAIL
  case D: fence extraction failed — c2c-step7-commit-outcome not declared yet (Task 5)"
  fi

  # Case E
  FXE="$TMP/fxE"; mkdir -p "$FXE"
  mk_manifest "$FXE/manifest.yml" completed completed
  if git -C "$FXE" rev-parse --show-toplevel >/dev/null 2>&1; then
    CTO12_FAIL="$CTO12_FAIL
  case E: fixture invalid — $FXE is unexpectedly inside a git repository, cannot exercise the no-repo path"
  elif run_outcome_fence "$FXE/manifest.yml"; then
    _rc=$(cat "$TMP/outcome-rc"); _out=$(cat "$TMP/outcome-out")
    case "$_out" in
      "COMMIT_OUTCOME_NORUN"*) [ "$_rc" -eq 3 ] || CTO12_FAIL="$CTO12_FAIL
  case E (outside any repo): exit=$_rc (expected 3), out=$_out" ;;
      *) CTO12_FAIL="$CTO12_FAIL
  case E (outside any repo): expected 'COMMIT_OUTCOME_NORUN', got: $_out (exit $_rc)" ;;
    esac
  else
    CTO12_FAIL="$CTO12_FAIL
  case E: fence extraction failed — c2c-step7-commit-outcome not declared yet (Task 5)"
  fi
fi

if [ -z "$CTO12_FAIL" ]; then
  ok "CTO12 c2c-step7-commit-outcome, run against 5 real git fixtures (A-E), returns the correct token and exit code for each"
else
  bad "CTO12 c2c-step7-commit-outcome fixture check failed:$CTO12_FAIL"
fi

# ===========================================================================
# CTO13 — Step 7 routes COMMIT_UNCOMMITTED to a stop-and-report path that states no rollback is
# attempted and no transition is added (ADR-0135 §D3; the plan's own Task 5 bullet 3). The needle is
# planted, not guessed: grepped against the LIVE file before Task 5 exists, so each of the four is
# confirmed to match NOTHING today (rule 12 — a needle already present elsewhere pins nothing):
#   grep -c "COMMIT_UNCOMMITTED" concept-to-code/SKILL.md  -> 0
#   grep -c "no rollback"        concept-to-code/SKILL.md  -> 0
#   grep -c "no transition"      concept-to-code/SKILL.md  -> 0
#   grep -c "absorbing"          concept-to-code/SKILL.md  -> 0
# All four required together (compound AND) inside S7FLAT — the SAME flattened, undecorated,
# case-insensitive copy of the Step 7 block CTO11 already computes above. Step 7.1 is a subsection
# of Step 7 (it is inserted before the "### Express path" heading that bounds S7_END), so once Task
# 5 lands its text is inside S7FLAT with no change needed here. A single long literal phrase was
# rejected in favour of four short, independently-distinctive words: this file's own history
# (MALFORMED, "not measured" — ADR-0091) is about a short token colliding with unrelated prose; a
# long literal clause instead risks the opposite failure, breaking on a paraphrase a coder writes in
# good faith. Four short, jointly-improbable words are the middle ground. (R-06)
# ===========================================================================
if printf '%s\n' "$S7FLAT" | grep -qi 'commit_uncommitted' \
   && printf '%s\n' "$S7FLAT" | grep -qi 'no rollback' \
   && printf '%s\n' "$S7FLAT" | grep -qi 'no transition' \
   && printf '%s\n' "$S7FLAT" | grep -qi 'absorbing'; then
  ok "CTO13 Step 7 routes COMMIT_UNCOMMITTED to stop-and-report and states no rollback is attempted and no transition is added (ADR-0135 §D3)"
else
  bad "CTO13 Step 7 does not yet route COMMIT_UNCOMMITTED to a stop-and-report clause naming no-rollback/no-transition/absorbing — Step 7.1 not yet added (Task 5)"
fi

# ===========================================================================
# CTOZ1 — assertion-count floor (ADR-0083 §D3: a suite reporting FEWER assertions does not read as
# broken and nobody watches the count). Floor, not an exact count.
#
# RAISED BY TASK 4 (CTO12, CTO13 added). Re-measured, not copied from the plan's own "15" — that
# number was written against Task 1's own checklist line, where it did not hold (Task 1 alone
# declares 12 ids: CTO01-CTO11, CTO14; with CTOZ1 itself that was 13, not 15 — see this file's own
# Task-1-era comment, which named the same discrepancy and set the floor to 12 for exactly that
# reason). Applying Task 4's own instruction literally — "raise CTOZ1's floor to the new assertion
# count in the same edit" — the actual PASS+FAIL total immediately before this assertion runs is now
# 14 (CTO01-CTO11 = 11, CTO14 = 1, CTO12 = 1, CTO13 = 1). Floor moves to 14, exact, zero slack — the
# same zero-slack relationship Task 1's own floor(12)/actual(12) already had, not the
# one-unit-slack convention some sibling Z1 floors use (e.g. transition-producer.test.sh: 13 actual,
# floor 12). Zero slack is the stricter guard: a floor carrying slack absorbs its own plant, which is
# the exact defect ADR-0124 removed from SP5 and warned this file by name not to reintroduce.
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 14 ]; then ok "CTOZ1 assertion-count floor ($_total >= 14)"
else bad "CTOZ1 assertion count fell to $_total (floor 14) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
