#!/bin/bash
# batch-boundary-precedence.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash batch-boundary-precedence.test.sh
#
# Issue #247 / ADR-0101. A correction to a rule shipped four hours earlier, not a defect someone
# else left. ADR-0088 §D5 states two batch-boundary rules as if they were jointly satisfiable:
#
#   1. do not put an assertion in the same batch as the task it depends on
#   2. do not split a red assertion from the task that turns it green
#
# On #222's plan they pull opposite ways. Rule 1 forces task 3 into a later batch than task 2,
# because `C7`'s RED must be "the vendored file exists but does not name gate 5.05" and the tester
# cannot observe that before task 2 vendors it. Rule 2 wants tasks 2 and 3 together, because `S1`
# reddens at task 2 and greens at task 3. **No batching satisfies both**, and ADR-0088 gave a reader
# applying them in good faith no way to choose.
#
# THE ISSUE OVERSTATES THE URGENT HALF, and measuring settled it. It says an unattended run "would
# stop, write a partial report, and present a correctly-working TDD sequence as a failure".
# `autopilot-build`'s circuit breaker reads `.claude/step5-report.json` **after dispatch** —
# once, at the end of Step 5, not per checkpoint. `S1` greens at task 3, inside Step 5, so that run
# would not have halted. The claim holds only for an expected red that survives to the END of
# Step 5, which is a plan already violating rule 2 with no task to green it. BP6/BP7 pin both
# halves: the breaker's cadence, and that it still halts on a real RED.
#
# So what is left is the documentation defect, and it is real: two rules presented as compatible,
# with no precedence and no account of what a red checkpoint means.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: BP2 | plugin/skills/concept-to-code/SKILL.md | the first rule outranks the second | both rules apply
# plant: BP2b | plugin/skills/concept-to-code/SKILL.md | evidence quality beats checkpoint tidiness | that is the convention
# plant: CB1 | plugin/skills/concept-to-code/SKILL.md | lands with the tests
# plant: CB2 | plugin/skills/concept-to-code/SKILL.md | **A third rule, and on a compiled or type-checked language it outranks both (issue #486, ADR-0155).** The tester's batch must leave the target BUILDING. The interface or type declaration its tests reference lands with the tests, not with the implementation: **the tester owns the signature, the coder owns the body.** The two rules above assume something nobody wrote down until #486 — that a failing assertion still compiles. In bash it does: the harness runs, prints `FAIL: <id>`, and the observed failing set can be compared against the plan's expected-red table. In Swift, Rust, Go or TypeScript under `tsc --noEmit` it does not. A test referencing a type the coder has not written yet does not fail; it stops the target from building, and then nothing runs at all. Measured on a live run against a Swift project on 2026-08-18: `cannot find type 'GoogleBooksAPIKeyStoring' in scope`, followed by `Testing cancelled because the build failed`. **Its precedence, in the same terms the tie-break above uses.** Violating rule 1 makes an assertion fail for the wrong reason, so the recorded RED proves nothing. Violating this one means there is no recorded RED at all, and no checkpoint state describing what happened — a strictly larger loss, and why it is a precondition rather than a third peer. | **A rule, and on a compiled or type-checked language it outranks both (issue #486, ADR-0155).** The tester's batch must leave the target BUILDING. The interface or type declaration its tests reference lands with the tests, not with the implementation: **the tester owns the signature, the coder owns the body.** The two rules above assume something nobody wrote down until #486 — that a failing assertion still compiles. In bash it does: the harness runs, prints `FAIL: <id>`, and the observed failing set can be compared against the plan's expected-red table. In Swift, Rust, Go or TypeScript under `tsc --noEmit` it does not. A test referencing a type the coder has not written yet does not fail; it stops the target from building, and then nothing runs at all. Measured on a live run against a Swift project on 2026-08-18: `cannot find type 'GoogleBooksAPIKeyStoring' in scope`, followed by `Testing cancelled because the build failed`. **Its precedence, in the same terms the tie-break above uses.** Violating rule 1 makes an assertion fail for the wrong reason, so the recorded RED proves nothing. Violating this one means there is no recorded RED at all, and no checkpoint state describing what happened — a strictly larger loss, and why it is a precondition rather than an equal peer.
# plant: CB3 | plugin/skills/concept-to-code/SKILL.md | A fourth state exists
# plant: CB4 | plugin/skills/concept-to-code/SKILL.md | a failure: stop the task, clear the ports, restart. Do not proceed to tests. | a failure: stop the task, clear the ports, restart. Do not proceed to tests.\n**Stage 1 — tester.**
# plant: CB4a | plugin/skills/concept-to-code/SKILL.md | the coder owns the body. A test that names
# plant: CB4b | plugin/skills/concept-to-code/SKILL.md | the coder owns the body. A test naming a type nobody
# plant: CB5 | plugin/agents/architect.md | the plan places the interface or type declaration in the TESTER's task
# plant: CB6 | plugin/skills/concept-to-code/SKILL.md | uses. Nothing in the hook layer had to change for this: `test-write-scope.sh` constrains the coder only, so it **already permits** the tester to write the declaration (ADR-0155 §D6). What was missing was anything telling it to. **This is an instruction, not an enforcement (rule 16), and nothing here blocks a dispatch.** No hook checks that a plan placed the declaration in the tester's task; `test-write-scope.sh` already permits it either way. What is enforced is that this rule is written down, and the consequence when | uses. Nothing in the hook layer had to change for this: `test-write-scope.sh` constrains the coder only, so nothing there forbids the tester from writing the declaration (ADR-0155 §D6). What was missing was anything telling it to. **This is an instruction, not an enforcement (rule 16), and nothing here blocks a dispatch.** No hook checks that a plan placed the declaration in the tester's task; `test-write-scope.sh` does not forbid it either way. What is enforced is that this rule is written down, and the consequence when
# plant: CB7 | ../docs/architecture/ADR-0155-compiled-language-tester-batch.md | M4 — the mechanism already permits the fix.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
AB="$STAGING/plugin/skills/autopilot-build/SKILL.md"
AA="$STAGING/plugin/agents/architect.md"
ADR88="$REPO/docs/architecture/ADR-0088-241-test-authoring-split-granularity.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

for _f in "$CC" "$AB" "$AA" "$ADR88"; do
  [ -f "$_f" ] || { echo "FATAL: missing $_f"; exit 1; }
done

# Prose is matched case-INSENSITIVELY as well as flat and undecorated. Capitalisation is the same
# class as a line wrap, a backtick or a bold marker: a clause is the same clause whether it opens
# a sentence or sits inside one. BP3 first failed against correct text for exactly that reason —
# the seventh member of this family (ADR-0073 wrap, ADR-0076 comment marker, ADR-0080 backticks,
# ADR-0082 one-line marker, ADR-0092 self-derivation, ADR-0098 backticks again, this).
FLAT=$(tr '\n' ' ' <"$CC" | tr -d '`*' | tr -s ' ')
AB_FLAT=$(tr '\n' ' ' <"$AB" | tr -d '`*' | tr -s ' ')

# ===========================================================================
# BP0 — the block exists and is non-vacuous. Without it every prose assertion is vacuous.
# ===========================================================================
B_A=$(grep -n '^\*\*Batch boundaries are a design choice' "$CC" | head -1 | cut -d: -f1)
if [ -n "${B_A:-}" ]; then ok "BP0 the batch-boundary block anchor resolves (line $B_A)"
else bad "BP0 the batch-boundary block anchor did not resolve — it was reworded, and BP1/BP2 assert nothing"; fi

# ===========================================================================
# BP1 — forward guard: both rules survive. A precedence rule that deletes one of the two rules is
# not a precedence rule.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'do not put an assertion in the same batch as the task it depends on' \
   && printf '%s\n' "$FLAT" | grep -qi 'do not split a red assertion from the task that turns it green'; then
  ok "BP1 (forward guard) both batch-boundary rules are still stated"
else
  bad "BP1 one of the two rules is gone; #247 is about ordering them, not removing one"
fi

# ===========================================================================
# BP2 — the precedence, WITH its reason. A bare "rule 1 wins" is a coin toss written down.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'the first rule outranks the second'; then
  ok "BP2 precedence is stated"
else
  bad "BP2 no precedence between the two rules — on #222's plan they cannot both be satisfied and a reader has no way to choose (#247)"
fi

if printf '%s\n' "$FLAT" | grep -qi 'evidence quality beats checkpoint tidiness'; then
  ok "BP2b the reason for the precedence is stated, not just the verdict"
else
  bad "BP2b the precedence is asserted without its reason — violating rule 1 destroys the RED evidence, violating rule 2 only leaves a checkpoint red"
fi

# ===========================================================================
# BP3/BP4 — what a red checkpoint means. The ADR-0049 flow assumes the batch's own tests go
# red-then-green within the batch; a third-party guard whose premise a later task restores is
# neither, and the chain had no concept of it.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'an intermediate checkpoint can be legitimately red'; then
  ok "BP3 the checkpoint says an intermediate red can be legitimate"
else
  bad "BP3 the checkpoint block says nothing about what a red result means at an intermediate point (#247)"
fi

if printf '%s\n' "$FLAT" | grep -qi "this batch's own tests"; then
  ok "BP4 and it names what is NOT expected — a red in this batch's own tests"
else
  bad "BP4 the expected-red paragraph does not bound itself; without the negative half it excuses any red"
fi

# ===========================================================================
# BP5 — the correction reaches ADR-0088, which is where the two rules are recorded. Its body is not
# edited in place (ADR-0034 precedent); it gains a Correction section.
# ===========================================================================
if grep -q '^## Correction' "$ADR88" && grep -q 'ADR-0101' "$ADR88"; then
  ok "BP5 ADR-0088 carries a Correction pointing at ADR-0101"
else
  bad "BP5 ADR-0088 still states the two rules as jointly satisfiable with no correction"
fi

# ===========================================================================
# BP6/BP7 — the measured premise about autopilot-build, and the guard that it stays strict.
# ===========================================================================
if printf '%s\n' "$AB_FLAT" | grep -qi 'Circuit breaker — read .claude/step5-report.json after dispatch'; then
  ok "BP6 autopilot-build's breaker reads the report AFTER dispatch — once, not per checkpoint"
else
  bad "BP6 the breaker's cadence changed; #247's autopilot argument was measured against 'after dispatch' and must be re-measured"
fi

if printf '%s\n' "$AB_FLAT" | grep -qi 'test_result = RED → halt'; then
  ok "BP7 (forward guard) the breaker still halts on a real RED — not relaxed by this fix"
else
  bad "BP7 the breaker no longer halts on RED; #247 says explicitly it must not be relaxed without an expected-red mechanism"
fi

# ===========================================================================
# BP8 — the deferred mechanism is named rather than silently dropped, and the reason with it.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'expected-red declaration'; then
  ok "BP8 the deferred mechanism is named at the call site"
else
  bad "BP8 nothing records that a mechanism was considered and deferred; a reader cannot tell a decision from an omission"
fi

# ===========================================================================
# CB1-CB7 — issue #486 / ADR-0155: ADR-0049 §D1's tester-first ordering assumes a failing
# assertion still compiles. In a compiled or type-checked language it does not: the tester's
# stub references a type the coder has not written, the whole test target fails to build, and
# there is no red test at all. Measured: `grep -ci 'compil'` over this file returned 0 before
# this fix. The fix is instruction-layer only — `test-write-scope.sh` line 69 already lets the
# tester (not just the coder) write a production-path interface/type declaration, so no hook
# change is asserted here. Each targets one of the seven obligations; GREEN now that ADR-0155
# has landed, and pinned by the plants declared in the header above.
#
# ADR-0155 has landed (issue #486): the mechanism these assertions check now exists, so each of
# CB1-CB7 and the CB4 denominator guard gets a `# plant:` line below, per this file's own
# convention (rule 2). CB2 and CB6 each needed a wider mutation than the others: both regexes are
# ANDs where one clause is already true elsewhere in the same scoped block (CB2's precedence-verb
# alternation is satisfied by the pre-existing rule-1-vs-rule-2 text; CB6's already-permit clause
# is satisfied twice, once per paragraph) — a narrow single-word deletion left the sibling
# occurrence standing and the assertion stayed GREEN. Confirmed empirically before declaring:
# removing only one of CB2's two "third" tokens, or only one of CB6's two "already permit(s)"
# occurrences, left CB2/CB6 green. The plants below span the full multi-paragraph range that
# contains both occurrences, replacing text in place rather than deleting it, so CB1's and CB5's
# own required phrases (which sit inside the same paragraphs) survive unchanged.
#
# CB4's plant is the denominator guard's own shape (rule 7): it does not touch the Stage 1 tester
# brief's CONTENT, it duplicates the `**Stage 1 — tester.**` anchor line itself (far away, at the
# end of the file) so `grep -c` finds 2 instead of 1 — CB4a's own block still resolves from the
# FIRST match and stays green, confirmed empirically.
# ===========================================================================

# CB1 — the batch-boundary rules block states a third rule: in a compiled or type-checked
# language the tester's batch must leave the target building (compiling / type-checking), which
# means the interface or type declaration its tests reference lands with the tests and not with
# the implementation. Scoped to the rules block itself (BP0's anchor to the next major heading),
# not the whole file, so a stray mention of "compiled" or "interface" elsewhere in the ~4200-line
# document cannot satisfy it (rule 12).
BB_BLOCK=$(awk 'BEGIN{g=0} /^\*\*Batch boundaries are a design choice/{g=1} g{ if ($0 ~ /^\*\*Batch-dispatch policy/) exit; print }' "$CC" 2>/dev/null | tr '\n' ' ' | tr -d '`*' | tr -s ' ')
if [ -z "$BB_BLOCK" ]; then
  bad "CB1 the batch-boundary rules block anchor did not resolve (duplicates BP0's finding) — CB1/CB2 assert nothing"
elif printf '%s\n' "$BB_BLOCK" | grep -qi 'compiled or type-checked' \
   && printf '%s\n' "$BB_BLOCK" | grep -qiE 'leaves? the target building' \
   && printf '%s\n' "$BB_BLOCK" | grep -qi 'lands with the tests' \
   && printf '%s\n' "$BB_BLOCK" | grep -qiE 'not with the implementation'; then
  ok "CB1 the batch-boundary block states a third rule: a compiled/type-checked target must keep building, so the interface/type declaration lands with the tests, not the implementation (issue #486)"
else
  bad "CB1 the batch-boundary block does not yet state the third (compile/build) rule — issue #486, ADR-0155 not written yet"
fi

# CB2 — the third rule states its precedence relative to the two existing rules, the way the
# existing text already resolves rule 1 against rule 2 ("evidence quality beats checkpoint
# tidiness"). Requires the literal token "third" (present in NEITHER today, confirmed) together
# with a precedence verb — the precedence verb alone is insufficient because "outranks"/"beats"
# already appear in the block for the EXISTING rule-1-vs-rule-2 resolution (BP2/BP2b); requiring
# "third" as well is what stops this assertion being satisfied by that pre-existing sentence.
if printf '%s\n' "$BB_BLOCK" | grep -qi 'third' \
   && printf '%s\n' "$BB_BLOCK" | grep -qiE 'outranks?|takes precedence|ranks above|ranks below|comes before|comes after|wins over|defers to|subordinate to|supersedes|beats'; then
  ok "CB2 the third rule's precedence against the first two is stated, not left for a reader to guess (issue #486)"
else
  bad "CB2 no precedence is stated between the third (compile/build) rule and the existing two — issue #486"
fi

# CB3 — the checkpoint-classification block names a FOURTH state: the target did not build.
# Distinct from "expected red" and "unclassifiable red" (both already named in this block for the
# pre-existing two states, confirmed present today) and must say what it MEANS — the third
# batching rule (CB1/CB2) was violated — not merely that the state exists.
CP_BLOCK=$(awk 'BEGIN{g=0} /^ *\*\*An intermediate checkpoint can be legitimately red/{g=1} g{ if ($0 ~ /dispatch-site: step5-checkpoint-reviewer/) exit; print }' "$CC" 2>/dev/null | tr '\n' ' ' | tr -d '`*' | tr -s ' ')
if [ -z "$CP_BLOCK" ]; then
  bad "CP_BLOCK the checkpoint-classification anchor did not resolve (duplicates BP3's finding) — CB3 asserts nothing"
elif printf '%s\n' "$CP_BLOCK" | grep -qi 'fourth' \
   && printf '%s\n' "$CP_BLOCK" | grep -qiE 'did not build|failed to build|build failed|does not build' \
   && printf '%s\n' "$CP_BLOCK" | grep -qi 'violat'; then
  ok "CB3 the checkpoint block names a fourth state (target did not build) and says the third batching rule was violated, not merely that the state exists (issue #486)"
else
  bad "CB3 the checkpoint block does not yet name a fourth state for a non-building target — issue #486"
fi

# CB4 — denominator guard (rule 7): exactly the two named tester-dispatch anchors must resolve
# before CB4a/CB4b assert about their content, or a broken anchor would silently read as "nothing
# to fix here" instead of as a failed derivation.
S1_ANCHOR_N=$(grep -c '^\*\*Stage 1 — tester\.\*\*' "$CC" 2>/dev/null)
S2_ANCHOR_N=$(grep -c '^\*\*Tester batch dispatch template\*\*' "$CC" 2>/dev/null)
if [ "${S1_ANCHOR_N:-0}" -eq 1 ] && [ "${S2_ANCHOR_N:-0}" -eq 1 ]; then
  ok "CB4 both tester-dispatch-site anchors resolve exactly once each (Workflow Stage 1, Agent-tool template)"
else
  bad "CB4 the two tester-dispatch-site anchors do not each resolve exactly once (S1=$S1_ANCHOR_N S2=$S2_ANCHOR_N) — CB4a/CB4b would assert against zero or the wrong site"
fi

# CB4a — Workflow path's "Stage 1 — tester" block carries the instruction to declare the
# interface/type declaration so the target keeps building, with the coder owning the body.
# Asserted SEPARATELY from CB4b (this repo has shipped the defect where only one of two required
# sites was edited and a combined OR/AND-across-both assertion still went green).
S1_BLOCK=$(awk 'BEGIN{g=0} /^\*\*Stage 1 — tester\.\*\*/{g=1} g{ if ($0 ~ /^#### Merge-back and base-fork audit/) exit; print }' "$CC" 2>/dev/null | tr '\n' ' ' | tr -d '`*' | tr -s ' ')
if printf '%s\n' "$S1_BLOCK" | grep -qiE 'declare (the )?interfaces?|interface (or|and) type declaration|type declaration' \
   && printf '%s\n' "$S1_BLOCK" | grep -qiE 'compil|leaves? the target building|target building' \
   && printf '%s\n' "$S1_BLOCK" | grep -qiE 'coder owns? the (body|implementation)|owning the body|leaves? the body (to|for) the coder'; then
  ok "CB4a the Workflow path's Stage 1 tester brief instructs declaring the interface/type declaration so the target builds, coder owns the body (issue #486)"
else
  bad "CB4a the Workflow path's Stage 1 tester brief (line ~1471) does not yet instruct declaring the interface/type declaration — issue #486"
fi

# CB4b — Agent-tool path's "Tester batch dispatch template" carries the SAME instruction. A
# separate assertion from CB4a on purpose (see CB4a's comment).
S2_BLOCK=$(awk 'BEGIN{g=0} /^\*\*Tester batch dispatch template\*\*/{g=1} g{ if ($0 ~ /^\*\*Single batch dispatch template\*\*/) exit; print }' "$CC" 2>/dev/null | tr '\n' ' ' | tr -d '`*' | tr -s ' ')
if printf '%s\n' "$S2_BLOCK" | grep -qiE 'declare (the )?interfaces?|interface (or|and) type declaration|type declaration' \
   && printf '%s\n' "$S2_BLOCK" | grep -qiE 'compil|leaves? the target building|target building' \
   && printf '%s\n' "$S2_BLOCK" | grep -qiE 'coder owns? the (body|implementation)|owning the body|leaves? the body (to|for) the coder'; then
  ok "CB4b the Agent-tool path's Tester batch dispatch template instructs declaring the interface/type declaration so the target builds, coder owns the body (issue #486)"
else
  bad "CB4b the Agent-tool path's Tester batch dispatch template (line ~2437) does not yet instruct declaring the interface/type declaration — issue #486"
fi

# CB5 — architect.md's Implementation-plan bullet (Output Format) states that a plan for a
# compiled or type-checked language places the interface/type declaration in the tester's task.
# Scoped to that one bullet (RI7's technique in spec-coverage.test.sh), not the whole file, so the
# needle cannot be satisfied by an unrelated bullet discussing a different rule under the same
# heading (rule 12).
AA_BULLET=$(awk 'BEGIN{g=0} /^- \*\*Implementation plan\*\*/{g=1} g{ if ($0 !~ /^- \*\*Implementation plan\*\*/ && $0 ~ /^- \*\*/) exit; print }' "$AA" 2>/dev/null | tr -d '`*' | tr -s ' ')
if [ -z "$AA_BULLET" ]; then
  bad "CB5 architect.md's Implementation-plan bullet anchor did not resolve — CB5 asserts nothing"
elif printf '%s\n' "$AA_BULLET" | grep -qi 'compiled or type-checked' \
   && printf '%s\n' "$AA_BULLET" | grep -qiE 'interface (declaration|or type declaration)|type declaration' \
   && printf '%s\n' "$AA_BULLET" | grep -qi 'tester'; then
  ok "CB5 architect.md's Implementation-plan bullet states a compiled/type-checked plan places the interface/type declaration in the tester's task (issue #486)"
else
  bad "CB5 architect.md's Implementation-plan bullet does not yet address the compiled/type-checked interface-declaration placement — issue #486"
fi

# CB6 — the instruction-not-an-enforcement disclosure (CLAUDE.md rule 16) for THIS fix: names
# what IS enforced (test-write-scope.sh already permitting the tester to write the declaration)
# versus what is merely instructed, and states nothing here blocks a dispatch. Scoped to the
# Fallback — Agent-tool batch dispatch subsection (the natural home for CB1-CB4b's content),
# because the bare phrase "instruction, not an enforcement" already occurs twice elsewhere in
# this file for unrelated mechanisms (rule 16 disclosures at the dispatch-template and Step-7
# blocks) and "test-write-scope.sh" is named five times elsewhere too — an unscoped whole-file
# check on either phrase alone would already read GREEN today, which would pin nothing (rule 12).
FB_BLOCK=$(awk 'BEGIN{g=0} /^#### Fallback — Agent-tool batch dispatch/{g=1} g{ if ($0 ~ /^#### Workflow dispatch path — Step 6 review cycle/) exit; print }' "$CC" 2>/dev/null | tr '\n' ' ' | tr -d '`*' | tr -s ' ')
if [ -z "$FB_BLOCK" ]; then
  bad "CB6 the Fallback — Agent-tool batch dispatch section anchor did not resolve — CB6 asserts nothing"
elif printf '%s\n' "$FB_BLOCK" | grep -qiE 'instruction,? not an enforcement|instruction rather than an enforcement' \
   && printf '%s\n' "$FB_BLOCK" | grep -qi 'test-write-scope\.sh' \
   && printf '%s\n' "$FB_BLOCK" | grep -qiE 'already permit|already allow' \
   && printf '%s\n' "$FB_BLOCK" | grep -qiE 'blocks? (a |the )?dispatch|no (hook|gate) (change|blocks)|blocks nothing|does not block'; then
  ok "CB6 the fix carries a rule-16 disclosure naming test-write-scope.sh as already permitting the tester and states nothing here blocks a dispatch (issue #486)"
else
  bad "CB6 no rule-16 (instruction, not an enforcement) disclosure for this fix names test-write-scope.sh's existing permission or confirms nothing blocks a dispatch — issue #486"
fi

# CB7 — docs/architecture/ADR-0155-*.md exists and records the decision, including the measured
# fact that test-write-scope.sh already permits the tester to write the declaration so no hook
# change was needed (recovery-baseline-rebase.test.sh's ADR-existence idiom, ADR-0050).
ADR155=$(ls "$REPO"/docs/architecture/ADR-0155-*.md 2>/dev/null | head -1)
if [ -z "${ADR155:-}" ] || [ ! -f "${ADR155:-/nonexistent}" ]; then
  bad "CB7 docs/architecture/ADR-0155-*.md does not exist yet — issue #486"
else
  ADR155_FLAT=$(tr '\n' ' ' <"$ADR155" | tr -d '`*' | tr -s ' ')
  if printf '%s\n' "$ADR155_FLAT" | grep -qi 'test-write-scope\.sh' \
     && printf '%s\n' "$ADR155_FLAT" | grep -qiE 'already permit|already allow' \
     && printf '%s\n' "$ADR155_FLAT" | grep -qiE 'no hook change|without (a |any )?hook change|hook.s? unchanged|no changes? to the hook|no hook was needed'; then
    ok "CB7 ADR-0155 exists and records that test-write-scope.sh already permitted the tester, so no hook change was needed (issue #486)"
  else
    bad "CB7 $ADR155 exists but does not record the measured test-write-scope.sh fact — issue #486"
  fi
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 9 ]; then ok "Z1 assertion-count floor ($_total >= 9)"
else bad "Z1 assertion count fell to $_total (floor 9) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
