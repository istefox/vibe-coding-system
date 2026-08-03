#!/bin/bash
# plan-task-count.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash plan-task-count.test.sh
#
# Covers issue #174: `n=$(grep -c PATTERN FILE 2>/dev/null || echo 0)` at the two sites that count
# unchecked plan tasks. `grep -c` PRINTS `0` **and** EXITS 1 when there is no match, so the `||`
# fallback appends a SECOND line and the variable holds the two-line string `0\n0`. A numeric test
# on it does not evaluate — it errors with `integer expression expected` and returns 2.
#
# ASSERTION LABELS ARE PT-PREFIXED (PT0, PTA1, PTB2, ...) to stay distinguishable from every other
# harness printing into the same CI shell-tests job (B-, R-, W-, ...).
#
# WHAT IS AND IS NOT FIX EVIDENCE, stated per assertion below and summarised here, because this
# file's two behavioural fixtures fail in OPPOSITE directions:
#   - PTA*  is a live DEMONSTRATION of the bug's shape against `grep` itself. It passes before and
#           after the fix by construction. It is not evidence of anything having been fixed.
#   - PTB*, PTC1, PTC4, PTD*  were seen RED against the pre-fix tree. These are the fix evidence.
#   - PTC2, PTC3  pass before and after. PTC2 pins the intended EXIT behaviour (which the bug
#           reproduced by accident, via a failed comparison rather than a real one) and PTC3 is the
#           POSITIVE TWIN of PTC1: a check that fails on every input would satisfy a zero-task
#           assertion alone, so the two-task fixture is what makes PTC1 mean something. Rule (8)
#           of .claude/context.md, applied at the point where it bites.
#
# PTD is a repo-wide forward guard, and it deliberately scans only EXECUTABLE context. This
# repository documents the broken idiom verbatim in at least seven prose warnings
# (concept-to-code/SKILL.md, secret-scan.sh, interface-check.sh, untrusted-input-scan.sh,
# diff-budget-check.sh, weakening-wiring.test.sh, roadmap-from-issues.sh) and DEMONSTRATES it
# deliberately in three sibling harnesses, which must never trip their own guard. Three filters,
# each narrowing a distinct false-positive class:
#   1. comment lines are skipped, and in Markdown only ```bash fences are read at all;
#   2. the match must sit inside a command substitution (`$(` or a backtick) — that is what makes it
#      a captured VALUE rather than a message string or a `grep -qF` needle;
#   3. a line carrying the literal waiver `idiom-demo` is skipped as a declared demonstration.
# Filter 3 is a DECLARED exemption, not an identity exemption: this file is scanned like any other
# and its own PTA1 demonstration carries the marker. No file is trusted for being itself.
#
# --- plants (plant-check.sh, ADR-0121) ---------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# PTH0/PTH1/PTH2 back the R-02 corpus-baseline comparison (ADR-0121 §D3); PTE4/PTJ1 are the
# vacuity assertions beside PTE3/PTG10 (ADR-0121 §D2, the ADR-0081 ZA4 stale-waiver direction).
# plant: PTH0 | plugin/scripts/tests/plan-task-count.test.sh | BASELINE="$STAGING/plugin/scripts/tests/plan-shape-baseline.tsv" | BASELINE="$STAGING/plugin/scripts/tests/no-such-baseline.tsv"
# plant: PTH1 | plugin/scripts/tests/plan-shape-baseline.tsv | 2026-05-30-deep-refactor-skill.md 36 0 | 2026-05-30-deleted-plan.md 36 0
# plant: PTH2 | plugin/scripts/tests/plan-shape-baseline.tsv | 2026-07-30-222-vendor-deployed-only-skills.md 38 7 | 2026-07-30-222-vendor-deployed-only-skills.md 38 9
# plant: PTE4 | plugin/skills/concept-to-code/scripts/plan-task-predicate.awk | return (lvl >= 2 && lvl <= 4) && (l ~ /Task/) | return (lvl >= 2 && lvl <= 4) && (l ~ /Task|Step/)
# plant: PTJ1 | plugin/skills/concept-to-code/scripts/plan-task-predicate.awk | return rest ~ /^[Tt]ask[ \t]+[0-9]+/ | return rest ~ /^([Tt]ask|[Ss]tep)[ \t]+[0-9]+|^T[0-9]+[ \t]/
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
AB="$STAGING/plugin/skills/autopilot-build/SKILL.md"

# ==================================================================================================
# PT0. Anchors. Every assertion below is meaningless without these.
# ==================================================================================================
[ -f "$CC" ] && [ -r "$CC" ] \
  && ok "PT0a: concept-to-code/SKILL.md exists and is readable" \
  || bad "PT0a: $CC not found or unreadable"
[ -f "$AB" ] && [ -r "$AB" ] \
  && ok "PT0b: autopilot-build/SKILL.md exists and is readable" \
  || bad "PT0b: $AB not found or unreadable"

# --- extract the body of the first ```-fenced block that follows a marker line. The marker is
# matched with index(), not as a regex: the markers here carry `**` and an em-dash, and awk's -v
# processes escape sequences before the regex engine ever sees them. ---
extract_fence() {
  awk -v m="$2" '
    !found && index($0, m) { found=1; next }
    found && /^```/  { infence = !infence; if (!infence) exit; next }
    found && infence { print }
  ' "$1"
}

# ==================================================================================================
# PTA. Live demonstration of the bug's shape, against `grep` itself.
#      NOT FIX EVIDENCE — passes before and after by construction.
# ==================================================================================================
: > "$TMP/nomatch.txt"

pta_wrong=$(grep -c 'NEEDLE' "$TMP/nomatch.txt" 2>/dev/null || echo 0)   # idiom-demo (PTD filter 3)
pta_wrong_lines=$(printf '%s\n' "$pta_wrong" | grep -c .)
[ "$pta_wrong_lines" = "2" ] \
  && ok "PTA1 (demonstration): grep -c … || echo 0 yields TWO lines on no match" \
  || bad "PTA1 (demonstration): expected 2 lines from the broken idiom, got $pta_wrong_lines"

pta_err=$( { [ "$pta_wrong" -ge 1 ]; } 2>&1 >/dev/null )
case "$pta_err" in
  *"integer expression expected"*)
    ok "PTA2 (demonstration): a numeric test on the two-line value errors, it does not compare" ;;
  *)
    bad "PTA2 (demonstration): expected 'integer expression expected', got [$pta_err]" ;;
esac

pta_c=$(grep -c 'NEEDLE' "$TMP/nomatch.txt" 2>/dev/null); pta_right=${pta_c:-0}
pta_right_lines=$(printf '%s\n' "$pta_right" | grep -c .)
{ [ "$pta_right_lines" = "1" ] && [ "$pta_right" = "0" ]; } \
  && ok "PTA3 (demonstration): the canonical idiom (secret-scan.sh:103 shape) yields the single line 0" \
  || bad "PTA3 (demonstration): canonical idiom gave [$pta_right] over $pta_right_lines line(s)"

printf '# Plan\n\nAll done.\n\n- [x] Task 1 — done\n' > "$TMP/plan-zero.md"
printf '# Plan\n\n- [ ] Task 1 — pending\n- [x] Task 2 — done\n- [ ] Task 3 — pending\n' > "$TMP/plan-two.md"

pta_guarded=$(grep -c -e '- \[ \]' "$TMP/plan-two.md" 2>/dev/null)
pta_unguarded_rc=0
grep -c '- \[ \]' "$TMP/plan-two.md" >/dev/null 2>&1 || pta_unguarded_rc=$?
[ "${pta_guarded:-x}" = "2" ] \
  && ok "PTA4 (demonstration): -e counts both unchecked tasks; the unguarded form exits $pta_unguarded_rc because grep reads the leading dash as an option" \
  || bad "PTA4 (demonstration): grep -c -e '- \\[ \\]' returned [${pta_guarded:-}] on a 2-task plan, expected 2"

# A heading-form plan: what the architect actually writes, and what BOTH consumers rejected before
# issue #172. No checkbox anywhere at task level — the checkbox here is a SUB-STEP inside a task,
# which is exactly why counting checkboxes never counted tasks.
printf '# Plan\n\n## Task 1 — Do the thing (R-01, R-02)\n\n- [ ] Re-run the harness\n\n## Task 2 — Do the other thing (R-03)\n' > "$TMP/plan-heading.md"
# Heading form with no checkbox at all — 7 of the 57 real plans look like this.
printf '# Plan\n\n### Task 1 — Only a heading (R-01)\n\nSome prose.\n\n### Task 2 — Another (R-02)\n' > "$TMP/plan-heading-only.md"
# No task in any form.
printf '# Plan\n\nJust prose, no tasks at all.\n' > "$TMP/plan-none.md"

# ==================================================================================================
# PTB. Static: neither consumer decides for itself what a plan task is. SEEN RED before the fix.
#
# These replace #174's PTB1-4, which asserted that the INLINE grep at each site was guarded against
# both of that issue's defects. There is no inline grep any more, so the same two defect classes are
# now unrepresentable at these sites rather than merely guarded — PTB3 is what keeps them that way.
# The repo-wide `|| echo 0` guard (PTD) is unchanged and still covers the class everywhere else.
# ==================================================================================================
# Anchored on each fence's own `<!-- fence-contract: … -->` marker rather than on the heading above
# it (issue #206). Rewording either heading used to empty the extraction; measured, this file went
# from 43 passed/0 failed to 35 passed/2 failed — one loud failure that also took FIVE dependent
# assertions out of the run, and a suite reporting fewer assertions does not read as broken. The
# marker travels with the fence, and Z1 below is the floor that makes a shrunken run visible.
CC_STEP5=$(extract_fence "$CC" 'fence-contract: concept-to-code-step5-plan-structure -->')
AB_BLOCK=$(extract_fence "$AB" 'fence-contract: autopilot-build-check-5 -->')

printf '%s\n' "$CC_STEP5" | grep -q 'plan-tasks.sh --count' \
  && ok "PTB1: concept-to-code Step 5 delegates the task count to plan-tasks.sh" \
  || bad "PTB1: concept-to-code Step 5 does not call plan-tasks.sh --count"

printf '%s\n' "$AB_BLOCK" | grep -q 'plan-tasks.sh --count' \
  && ok "PTB2: autopilot-build check 5 delegates the task count to plan-tasks.sh" \
  || bad "PTB2: autopilot-build check 5 does not call plan-tasks.sh --count"

ptb3_hits=$(printf '%s\n%s\n' "$CC_STEP5" "$AB_BLOCK" | grep -c 'grep -c')
[ "$ptb3_hits" = "0" ] \
  && ok "PTB3 (forward guard): neither block re-inlines a grep -c over the plan" \
  || bad "PTB3: $ptb3_hits inline grep -c re-appeared in a plan-task block — #172 and #174 both start here"

# The predicate must exist in exactly ONE file. ADR-0069 §D2 is the whole point: three files that
# agree today are the defect, not the fix.
PRED="$STAGING/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk"
[ -f "$PRED" ] \
  && ok "PTB4: the shared predicate file exists at concept-to-code/scripts/plan-task-predicate.awk" \
  || bad "PTB4: $PRED not found — PTB5 and the PTE corpus run are meaningless"

# The trailing `(` makes these count DEFINITIONS rather than mentions. The needles are SPLIT and
# concatenated at run time so the literal never appears anywhere in this file — otherwise the
# scan counts its own search pattern and reports the duplication it exists to detect. Splitting
# beats excluding this file by name: no file is exempt by identity here (same rule as PTD).
_fn="function is_"
ptb5_defs=$(grep -rln "${_fn}task_heading(" "$STAGING" 2>/dev/null | grep -c .)
[ "$ptb5_defs" = "1" ] \
  && ok "PTB5: is_task_heading is defined in exactly one file under staging/" \
  || bad "PTB5: is_task_heading is defined in $ptb5_defs files — the duplication #172 was filed about"

ptb6_defs=$(grep -rln "${_fn}checklist_item(" "$STAGING" 2>/dev/null | grep -c .)
[ "$ptb6_defs" = "1" ] \
  && ok "PTB6: is_checklist_item is defined in exactly one file under staging/" \
  || bad "PTB6: is_checklist_item is defined in $ptb6_defs files — spec-coverage.sh used to hold two copies itself"

# Both SKILL.md blocks call these two files by their DEPLOYED path (~/.claude/...). Without a PAIRS
# entry they never reach ~/.claude, both call sites exit 127, and the "did not run" branch aborts
# every dispatch — the fix would be strictly worse than the defect. pairs-completeness.test.sh
# cannot catch this: skill scripts/ are vendored selectively and are outside its scope (ADR-0043).
SYNC="$STAGING/sync-to-claude.sh"
for _need in plan-tasks.sh plan-task-predicate.awk; do
  if grep -q "concept-to-code/scripts/$_need|" "$SYNC" 2>/dev/null; then
    ok "PTB7: $_need has a PAIRS entry — it will reach ~/.claude, where both SKILL.md blocks call it"
  else
    bad "PTB7: $_need has NO PAIRS entry — both call sites would exit 127 and abort every dispatch"
  fi
done

# ==================================================================================================
# PTC. Behavioural: the check-5 block is EXTRACTED FROM THE SKILL FILE and executed against four
#      fixtures. Executing the real text is what stops this file from drifting away from the block
#      it claims to pin — and it is how #174's leading-dash defect surfaced at all.
#
#      THE BLOCK CALLS ~/.claude/... — the DEPLOYED copy. Rewritten to $STAGING before execution,
#      because a test that validates the deployed tree proves nothing about the change under review
#      and is dark in CI, where no ~/.claude exists. This repository has three such $HOME-coupled
#      harnesses on record (ADR-0032, ADR-0044); this one does not join them. PTC0b asserts the
#      rewrite actually happened, or the run would silently mean the wrong thing.
# ==================================================================================================
if [ -z "$AB_BLOCK" ]; then
  bad "PTC0: could not extract the 'Check 5 — Plan has tasks' block from autopilot-build/SKILL.md — PTC1..PTC4 skipped"
else
  ok "PTC0: check-5 block extracted from autopilot-build/SKILL.md"

  AB_LOCAL=$(printf '%s\n' "$AB_BLOCK" | sed "s|~/.claude/skills/concept-to-code/scripts|$STAGING/plugin/skills/concept-to-code/scripts|g")
  printf '%s\n' "$AB_LOCAL" | grep -q '~/.claude' \
    && bad "PTC0b: the deployed-path rewrite failed — the block would test ~/.claude, not staging/" \
    || ok "PTC0b: the block's script path was rewritten from ~/.claude to staging/"

  run_check5() {
    { printf 'plan=%s\n' "$1"; printf '%s\n' "$AB_LOCAL"; } > "$TMP/check5.sh"
    bash "$TMP/check5.sh" >"$TMP/c5.out" 2>"$TMP/c5.err"
    printf '%s' "$?"
  }

  ptc1_rc=$(run_check5 "$TMP/plan-heading.md")
  { [ "$ptc1_rc" = "0" ] && [ ! -s "$TMP/c5.out" ] && [ ! -s "$TMP/c5.err" ]; } \
    && ok "PTC1: a heading-form plan passes check 5 silently — the #172 defect" \
    || bad "PTC1: heading-form plan gave rc=$ptc1_rc, stdout=[$(cat "$TMP/c5.out")], stderr=[$(cat "$TMP/c5.err")]"

  ptc2_rc=$(run_check5 "$TMP/plan-heading-only.md")
  [ "$ptc2_rc" = "0" ] \
    && ok "PTC2: a plan with headings and NO checkbox anywhere passes — 7 real plans look like this" \
    || bad "PTC2: checkbox-free heading plan gave rc=$ptc2_rc, stdout=[$(cat "$TMP/c5.out")]"

  ptc3_rc=$(run_check5 "$TMP/plan-two.md")
  { [ "$ptc3_rc" = "0" ] && [ ! -s "$TMP/c5.out" ]; } \
    && ok "PTC3 (regression): the checkbox form still passes — widening must not narrow" \
    || bad "PTC3: checkbox-form plan gave rc=$ptc3_rc, stdout=[$(cat "$TMP/c5.out")]"

  ptc4_rc=$(run_check5 "$TMP/plan-none.md")
  { [ "$ptc4_rc" = "1" ] && grep -q 'no recognisable task' "$TMP/c5.out"; } \
    && ok "PTC4 (negative twin of PTC1-3): a plan with no task in any form still aborts" \
    || bad "PTC4: task-free plan gave rc=$ptc4_rc, stdout=[$(cat "$TMP/c5.out")] — the guard is now inert"

  ptc5_rc=$(run_check5 "$TMP/does-not-exist.md")
  { [ "$ptc5_rc" = "1" ] && grep -q 'did not run' "$TMP/c5.out"; } \
    && ok "PTC5: an unreadable plan reports 'did not run', distinct from 'found no tasks'" \
    || bad "PTC5: unreadable plan gave rc=$ptc5_rc, stdout=[$(cat "$TMP/c5.out")]"
fi

# ==================================================================================================
# PTE. The corpus. ADR-0069 §D1 chose its predicate on a measurement, so the measurement is the
#      assertion: every real plan must be recognised. A count guard against a vacuous loop, because
#      a glob matching nothing reports nothing and reads exactly like full coverage
#      (pairs-completeness.test.sh self-test-2 lesson).
# ==================================================================================================
PLAN_TASKS="$STAGING/plugin/skills/concept-to-code/scripts/plan-tasks.sh"
PLANS_DIR="$STAGING/../docs/superpowers/plans"
if [ ! -x "$PLAN_TASKS" ] && [ ! -f "$PLAN_TASKS" ]; then
  bad "PTE0: plan-tasks.sh not found at $PLAN_TASKS — PTE1/PTE2 skipped"
elif [ ! -d "$PLANS_DIR" ]; then
  bad "PTE0: plan corpus not found at $PLANS_DIR — PTE1/PTE2 skipped"
else
  ok "PTE0: plan-tasks.sh and the plan corpus both resolve"
  pte_total=0; pte_zero=0; pte_err=0; : > "$TMP/pte-zero.txt"
  for _p in "$PLANS_DIR"/*.md; do
    [ -f "$_p" ] || continue
    pte_total=$((pte_total+1))
    _n=$(bash "$PLAN_TASKS" --count "$_p" 2>/dev/null) || { pte_err=$((pte_err+1)); continue; }
    [ "$_n" -ge 1 ] || { pte_zero=$((pte_zero+1)); printf '%s\n' "$(basename "$_p")" >> "$TMP/pte-zero.txt"; }
  done

  [ "$pte_total" -ge 30 ] \
    && ok "PTE1 (count guard): the corpus loop ran over $pte_total plans" \
    || bad "PTE1 (count guard): only $pte_total plan(s) scanned — PTE2 proves nothing"

  # ONE named exception, and it is named rather than tolerated by threshold. `2026-06-06-claude-md-
  # slim.md` structures its work as `### Step N — …`, a third word no parser has ever recognised —
  # not spec-coverage.sh either, so ADR-0069 §D1's predicate does not regress it, it inherits it.
  # Pinned by name so a NEW unrecognised plan fails here instead of hiding behind a count.
  PTE_KNOWN="2026-06-06-claude-md-slim.md"
  pte_unexpected=$(grep -vxF "$PTE_KNOWN" "$TMP/pte-zero.txt" 2>/dev/null | grep -c . )
  { [ "$pte_unexpected" -eq 0 ] && [ "$pte_err" -eq 0 ]; } \
    && ok "PTE2: every real plan is recognised except the one known 'Step'-form legacy plan ($pte_total scanned, $pte_zero exempt)" \
    || bad "PTE2: $pte_unexpected unexpected unrecognised plan(s), $pte_err error(s): $(tr '\n' ' ' < "$TMP/pte-zero.txt")"

  # The exemption must not become vacuous: if that plan is ever deleted or reworded, this fails and
  # the exemption gets removed with it, rather than sitting in the file forever protecting nothing.
  [ -f "$PLANS_DIR/$PTE_KNOWN" ] \
    && ok "PTE3 (exemption is live): $PTE_KNOWN still exists — the PTE2 exemption still has a subject" \
    || bad "PTE3: $PTE_KNOWN is gone — delete the PTE2 exemption, it now protects nothing"

  # PTE4 (vacuity assertion, ADR-0121 §D2): PTE3 asserts the exempted file still EXISTS. The
  # exemption's actual subject is that it is still UNRECOGNISED by is_task_line(). Reword it to
  # `### Task N`, or widen the predicate to absorb it, and PTE3 stays green while the exemption
  # protects nothing — the ADR-0081 ZA4 stale-waiver direction, applied here rather than merely
  # cited. Kept SEPARATE from PTE3 on purpose: "the file is gone" and "the file no longer needs
  # exempting" are different failures with different remedies (do not merge them, ADR-0121 §D2).
  # plan-tasks.sh is a CHECKER: branch on the exit code too — exit 3 means it did not run and must
  # not be read as "returned 0".
  pte4_n=$(bash "$PLAN_TASKS" --count "$PLANS_DIR/$PTE_KNOWN" 2>/dev/null); pte4_rc=$?
  { [ "$pte4_rc" -eq 0 ] && [ "$pte4_n" = "0" ]; } \
    && ok "PTE4 (exemption still needed): $PTE_KNOWN still returns 0 — the PTE2 exemption still has work to do" \
    || bad "PTE4: $PTE_KNOWN now returns count=$pte4_n rc=$pte4_rc — the exemption is stale, delete PTE2, it now covers nothing"
fi

# ==================================================================================================
# PTF. The concept-to-code side. Its block has no numeric test of its own — the count is consumed by
#      PROSE ("If `tasks = 0`"), so a model reads whatever the block leaves in `$tasks`. Executed
#      the same way and against the same fixtures, since a value a human never compares is exactly
#      where a wrong one survives (#174's c2c site was wrong for 437 lines under a warning about
#      itself).
# ==================================================================================================
if [ -z "$CC_STEP5" ]; then
  bad "PTF0: could not extract the plan-structure-validation block from concept-to-code/SKILL.md"
else
  ok "PTF0: Step 5 plan-structure block extracted from concept-to-code/SKILL.md"

  run_cc_step5() {
    printf '%s\n' "$CC_STEP5" \
      | sed "s|~/.claude/skills/concept-to-code/scripts|$STAGING/plugin/skills/concept-to-code/scripts|g; s|<manifest.artifacts.plan>|$1|" > "$TMP/ccblock.sh"
    printf 'printf "tasks=[%%s] rc=[%%s]\\n" "$tasks" "$rc"\n' >> "$TMP/ccblock.sh"
    bash "$TMP/ccblock.sh" 2>/dev/null
  }

  ptf1=$(run_cc_step5 "$TMP/plan-heading.md")
  [ "$ptf1" = "tasks=[3] rc=[0]" ] \
    && ok "PTF1: Step 5 counts a heading-form plan (2 headings + 1 sub-step = 3, rc 0)" \
    || bad "PTF1: Step 5 on a heading-form plan produced [$ptf1], expected tasks=[3] rc=[0]"

  ptf2=$(run_cc_step5 "$TMP/plan-none.md")
  [ "$ptf2" = "tasks=[0] rc=[0]" ] \
    && ok "PTF2 (negative twin of PTF1): a task-free plan yields 0 with rc 0 — found nothing, not did-not-run" \
    || bad "PTF2: Step 5 on a task-free plan produced [$ptf2], expected tasks=[0] rc=[0]"

  ptf3=$(run_cc_step5 "$TMP/nope-missing.md")
  case "$ptf3" in
    "tasks=[] rc=[2]") ok "PTF3: an unreadable plan yields rc 2 with no count — the model cannot read it as zero tasks" ;;
    *) bad "PTF3: Step 5 on a missing plan produced [$ptf3], expected tasks=[] rc=[2]" ;;
  esac
fi

# ==================================================================================================
# PTD. Repo-wide forward guard. #174's root cause is that every past instance was fixed only where a
#      comment happened to be written, so this scans staging/ as a whole rather than the two sites.
#      Executable context only — see the header note on the seven prose warnings.
# ==================================================================================================
# filters 2 and 3, applied identically to both scans
ptd_narrow() { grep '|| echo 0' | grep -e '\$(' -e '`' | grep -v 'idiom-demo'; }

# --- shell sources: every non-comment line ---
PTD_SH_FILES=0
: > "$TMP/ptd-hits.txt"
while IFS= read -r f; do
  PTD_SH_FILES=$((PTD_SH_FILES+1))
  grep -n 'grep -c' "$f" 2>/dev/null \
    | grep -v '^[0-9]*:[[:space:]]*#' \
    | ptd_narrow \
    | sed "s|^|${f}:|" >> "$TMP/ptd-hits.txt"
done <<EOF
$(find "$STAGING" -type f -name '*.sh')
EOF

# --- Markdown: only inside ```bash fences, and not on a comment line ---
PTD_MD_FILES=0
while IFS= read -r f; do
  PTD_MD_FILES=$((PTD_MD_FILES+1))
  awk '
    /^```bash/     { infence=1; next }
    infence && /^```/ { infence=0; next }
    infence        { print FILENAME ":" FNR ":" $0 }
  ' "$f" 2>/dev/null \
    | grep -v ':[[:space:]]*#' \
    | grep 'grep -c' \
    | ptd_narrow >> "$TMP/ptd-hits.txt"
done <<EOF
$(find "$STAGING" -type f -name '*.md')
EOF

# Count guard against a vacuous scan: a find that matches nothing reports nothing, and a silent
# zero-hit result reads exactly like full coverage (pairs-completeness.test.sh self-test-2 lesson).
{ [ "$PTD_SH_FILES" -ge 20 ] && [ "$PTD_MD_FILES" -ge 10 ]; } \
  && ok "PTD0 (count guard): scan covered $PTD_SH_FILES shell files and $PTD_MD_FILES markdown files" \
  || bad "PTD0 (count guard): scan covered only $PTD_SH_FILES shell / $PTD_MD_FILES markdown files — the loop is vacuous, PTD1 proves nothing"

PTD_HITS=$(grep -c . "$TMP/ptd-hits.txt" 2>/dev/null); PTD_HITS=${PTD_HITS:-0}
if [ "$PTD_HITS" = "0" ]; then
  ok "PTD1: no executable use of grep -c … || echo 0 anywhere under staging/"
else
  bad "PTD1: $PTD_HITS executable use(s) of grep -c … || echo 0 remain under staging/:"
  while IFS= read -r h; do echo "        $h"; done < "$TMP/ptd-hits.txt"
fi

# --- self-checks: PTD1's green is worthless unless the same filter chain still FIRES on a real
# instance (PTD2) and still SUPPRESSES only what it is meant to (PTD3). A guard narrowed by three
# filters can be narrowed into inertness, and an inert guard reports exactly what a clean tree does.
mkdir -p "$TMP/selfcheck"
{ printf '#!/bin/bash\n'
  printf 'n=$(grep -c X f 2>/dev/null || echo 0)\n'                                  # idiom-demo
  printf '# n=$(grep -c X f || echo 0)  <- a comment, must not count\n'              # idiom-demo
  printf 'ok "message: grep -c ... || echo 0 is wrong"  <- a string, must not count\n'
  printf 'w=$(grep -c X f || echo 0)  # idiom-demo declared\n'
} > "$TMP/selfcheck/planted.sh"
PTD_SELF=$(grep -n 'grep -c' "$TMP/selfcheck/planted.sh" | grep -v '^[0-9]*:[[:space:]]*#' | ptd_narrow | grep -c .)
[ "$PTD_SELF" = "1" ] \
  && ok "PTD2 (self-check): the guard flags the one real instance among a comment, a message string and a declared demo" \
  || bad "PTD2 (self-check): guard found $PTD_SELF hit(s) on the 4-line fixture, expected exactly 1"

PTD_SELF3=$(printf 'w=$(grep -c X f || echo 0)  # idiom-demo declared\n' | ptd_narrow | grep -c .)
[ "$PTD_SELF3" = "0" ] \
  && ok "PTD3 (self-check, positive twin of PTD2): the idiom-demo waiver suppresses a real instance" \
  || bad "PTD3 (self-check): the idiom-demo waiver did not suppress ($PTD_SELF3 hit(s)) — filter 3 is dead"

# ==================================================================================================
# PTG. is_task_opener() — the SECOND predicate (ADR-0070 §D1, issue #184). It answers "does a task
#      BLOCK START here", not "is there a task here". The distinction is the whole reason it exists:
#      diff-budget-check.sh uses it as a boundary to attribute a Budget: to a task, and the looser
#      is_task_line() would let a checkbox SUB-STEP close the previous task's block and steal it.
# ==================================================================================================
cat > "$TMP/opener.awk" <<'AWKEOF'
{ printf "%d\t%d\t%s\n", is_task_opener($0), is_task_line($0), $0 }
AWKEOF
opener_of() { printf '%s\n' "$1" | awk -f "$PRED" -f "$TMP/opener.awk" | cut -f1; }
line_of()   { printf '%s\n' "$1" | awk -f "$PRED" -f "$TMP/opener.awk" | cut -f2; }

# Both documented forms open a block.
[ "$(opener_of '## Task 1 — Do the thing (R-01)')" = "1" ] \
  && ok "PTG1: an H2 'Task N' heading opens a task block" \
  || bad "PTG1: '## Task 1 — …' did not open a block"
[ "$(opener_of '### Task 3 — … (R-02, R-05)')" = "1" ] \
  && ok "PTG2: the architect.md H3 form opens a task block" \
  || bad "PTG2: '### Task 3 — …' did not open a block"
[ "$(opener_of '- [ ] **Task 1 — the strict legacy form**')" = "1" ] \
  && ok "PTG3 (regression): the old strict checkbox form still opens a block" \
  || bad "PTG3: the strict '- [ ] **Task N' form stopped opening a block — 18 plans use it"
[ "$(opener_of '- [ ] Task 2 — a checkbox task without bold')" = "1" ] \
  && ok "PTG4: a checkbox task without bold opens a block" \
  || bad "PTG4: '- [ ] Task 2 — …' did not open a block"

# The case the whole predicate exists for.
SUBSTEP='- [ ] Re-run Task 2. Sections A and B green.'
{ [ "$(opener_of "$SUBSTEP")" = "0" ] && [ "$(line_of "$SUBSTEP")" = "1" ]; } \
  && ok "PTG5: a sub-step MENTIONING a task is not an opener, though is_task_line() still matches it" \
  || bad "PTG5: the sub-step case is broken — opener=$(opener_of "$SUBSTEP") line=$(line_of "$SUBSTEP"); a Budget: would be attributed to the wrong task"
[ "$(opener_of '## Tasks')" = "0" ] \
  && ok "PTG6: a '## Tasks' section heading is not an opener (is_task_line deliberately still matches it)" \
  || bad "PTG6: '## Tasks' opened a block — every plan with that section would gain a phantom task"
[ "$(opener_of 'Prose that mentions Task 4 in passing.')" = "0" ] \
  && ok "PTG7: prose mentioning a task is not an opener" \
  || bad "PTG7: plain prose opened a task block"

# Corpus. Same shape as PTE, same two named exemptions plus one more: deep-refactor writes `### T1`.
if [ -d "$PLANS_DIR" ]; then
  cat > "$TMP/openct.awk" <<'AWKEOF'
{ if (is_task_opener($0)) n++ } END { print n + 0 }
AWKEOF
  ptg_total=0; : > "$TMP/ptg-zero.txt"
  for _p in "$PLANS_DIR"/*.md; do
    [ -f "$_p" ] || continue
    ptg_total=$((ptg_total+1))
    _n=$(awk -f "$PRED" -f "$TMP/openct.awk" "$_p" 2>/dev/null)
    [ "${_n:-0}" -ge 1 ] || printf '%s\n' "$(basename "$_p")" >> "$TMP/ptg-zero.txt"
  done
  # Two plans name their tasks with a different word entirely — `### Step 0 —` and `### T1 —`, both
  # predating architect.md's `Task N` contract. Widening to Step|T[0-9] was rejected in ADR-0070 §D3:
  # `## The T1 approach` would become a task boundary. Named, so a NEW miss fails here.
  cat > "$TMP/ptg-known" <<'EOF'
2026-06-06-claude-md-slim.md
2026-05-30-deep-refactor-skill.md
EOF
  ptg_unexpected=$(grep -vxF -f "$TMP/ptg-known" "$TMP/ptg-zero.txt" 2>/dev/null | grep -c .)
  [ "$ptg_total" -ge 30 ] \
    && ok "PTG8 (count guard): the opener corpus loop ran over $ptg_total plans" \
    || bad "PTG8 (count guard): only $ptg_total plan(s) scanned"
  [ "$ptg_unexpected" -eq 0 ] \
    && ok "PTG9: every plan has a task opener except the two known non-'Task' plans ($(grep -c . "$TMP/ptg-zero.txt") exempt of $ptg_total)" \
    || bad "PTG9: $ptg_unexpected plan(s) unexpectedly have no opener: $(tr '\n' ' ' < "$TMP/ptg-zero.txt")"
  ptg_live=0
  while IFS= read -r _k; do [ -f "$PLANS_DIR/$_k" ] && ptg_live=$((ptg_live+1)); done < "$TMP/ptg-known"
  [ "$ptg_live" = "2" ] \
    && ok "PTG10 (exemptions are live): both named plans still exist" \
    || bad "PTG10: only $ptg_live of 2 exempted plans exist — prune the list, it protects nothing"

  # PTJ1 (vacuity assertion, ADR-0121 §D2): PTG10 asserts the two named plans still EXIST. The
  # exemption's actual subject is that they are still UNRECOGNISED by is_task_opener() — reword
  # either to `### Task N` and PTG10 stays green while the waiver protects nothing (the ADR-0081
  # ZA4 stale-waiver direction). Kept as a SEPARATE assertion from PTG10 on purpose: "the file is
  # gone" and "the file no longer needs exempting" are different failures with different remedies.
  ptj1_bad=""
  while IFS= read -r _k; do
    [ -f "$PLANS_DIR/$_k" ] || continue
    _kn=$(awk -f "$PRED" -f "$TMP/openct.awk" "$PLANS_DIR/$_k" 2>/dev/null); _kn_rc=$?
    if [ "$_kn_rc" -ne 0 ] || [ "${_kn:-x}" != "0" ]; then
      ptj1_bad="$ptj1_bad $_k(openers=${_kn:-err} rc=$_kn_rc)"
    fi
  done < "$TMP/ptg-known"
  [ -z "$ptj1_bad" ] \
    && ok "PTJ1 (exemption still needed): both PTG9-named plans still return 0 openers" \
    || bad "PTJ1: an exemption no longer needed — this plan now has openers, delete it from ptg-known:$ptj1_bad"
fi

# ==================================================================================================
# PTH. The R-02 instrument (ADR-0121 §D3): a committed corpus baseline. Any predicate edit is run
#      against it and fails naming exactly which plans moved and by how much — the "before/after
#      comparison over the whole corpus" R-02 asks for, executed rather than re-derived.
#
#      REGENERATE with (after a DELIBERATE predicate change — the resulting diff is the review
#      evidence, ADR-0121 §D3). Write this awk program to a temp file (this file's own Bash 3.2
#      convention — no process substitution), then:
#        FNR==1 { if (NR>1) emit(); f=FILENAME; L=0; O=0 }
#        { if (is_task_line($0)) L++; if (is_task_opener($0)) O++ }
#        END { emit() }
#        function emit(  n,p,b) { n=split(f,p,"/"); b=p[n]; printf "%s\t%d\t%d\n", b, L, O }
#      and run:
#        awk -f staging/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk \
#            -f <the-temp-file> docs/superpowers/plans/*.md | sort > \
#            staging/plugin/scripts/tests/plan-shape-baseline.tsv
# ==================================================================================================
BASELINE="$STAGING/plugin/scripts/tests/plan-shape-baseline.tsv"
pth_rows=0
if [ -f "$BASELINE" ]; then
  pth_rows=$(grep -c . "$BASELINE" 2>/dev/null || true); pth_rows=${pth_rows:-0}
fi

if [ -f "$BASELINE" ] && [ "$pth_rows" -ge 55 ]; then
  ok "PTH0 (denominator guard): $BASELINE resolves and holds $pth_rows rows (>= 55) — a baseline that stopped resolving discovers nothing and reads exactly like full agreement"

  # PTH1 — stale-entry guard: every baseline row's plan still exists under docs/superpowers/plans/.
  : > "$TMP/pth-missing.txt"
  while read -r _bn _bl _bo; do
    [ -n "${_bn:-}" ] || continue
    [ -f "$PLANS_DIR/$_bn" ] || printf '%s\n' "$_bn" >> "$TMP/pth-missing.txt"
  done < "$BASELINE"
  pth1_missing=$(grep -c . "$TMP/pth-missing.txt" 2>/dev/null || true); pth1_missing=${pth1_missing:-0}
  [ "$pth1_missing" -eq 0 ] \
    && ok "PTH1 (stale-entry guard): every baseline row's plan still exists under $PLANS_DIR" \
    || bad "PTH1: $pth1_missing baseline row(s) name a plan that no longer exists: $(tr '\n' ' ' < "$TMP/pth-missing.txt")"

  # PTH2 — the comparison itself, recomputed with a single awk pass loading the shared predicate,
  # never a reimplementation (ADR-0069 §D2). Rows whose file is missing are PTH1's business, not
  # this one's — keeping them out is what makes each Task-5 plant isolate to one assertion
  # (ADR-0104: an assertion covered by two guards isolates neither).
  cat > "$TMP/pth-both.awk" <<'AWKEOF'
{ if (is_task_line($0)) L++; if (is_task_opener($0)) O++ }
END { printf "%d\t%d\n", L+0, O+0 }
AWKEOF
  : > "$TMP/pth-diff.txt"
  pth2_compared=0
  while read -r _bn _bl _bo; do
    [ -n "${_bn:-}" ] || continue
    [ -f "$PLANS_DIR/$_bn" ] || continue
    pth2_compared=$((pth2_compared+1))
    _res=$(awk -f "$PRED" -f "$TMP/pth-both.awk" "$PLANS_DIR/$_bn" 2>/dev/null)
    _cl=$(printf '%s' "$_res" | cut -f1)
    _co=$(printf '%s' "$_res" | cut -f2)
    if [ "${_cl:-x}" != "$_bl" ] || [ "${_co:-x}" != "$_bo" ]; then
      printf '%s: lines %s->%s openers %s->%s\n' "$_bn" "$_bl" "${_cl:-?}" "$_bo" "${_co:-?}" >> "$TMP/pth-diff.txt"
    fi
  done < "$BASELINE"
  pth2_diffs=$(grep -c . "$TMP/pth-diff.txt" 2>/dev/null || true); pth2_diffs=${pth2_diffs:-0}
  { [ "$pth2_diffs" -eq 0 ] && [ "$pth2_compared" -ge 1 ]; } \
    && ok "PTH2: both predicates agree with the baseline on all $pth2_compared plan(s) compared" \
    || bad "PTH2: $pth2_diffs plan(s) diverge from the baseline: $(tr '\n' '; ' < "$TMP/pth-diff.txt")"
else
  bad "PTH0 (denominator guard): baseline missing or holds only $pth_rows row(s) (need >= 55) at $BASELINE — PTH1/PTH2 skipped"
fi

echo
# Z1: assertion-count FLOOR. PTC0/PTF0 fail loudly on an empty extraction, but their DEPENDENTS
# are skipped, and a run reporting fewer assertions than before does not look like a defect. The
# floor is what makes a vanished assertion visible; lowering it needs a deliberate edit.
_TOTAL=$((PASS + FAIL))
[ "$_TOTAL" -ge 43 ] \
  && ok "Z1: $_TOTAL assertions ran (floor 43) — none silently vanished" \
  || bad "Z1: only $_TOTAL assertions ran, floor 43 — assertions disappeared, they did not fail"

echo "plan-task-count: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
