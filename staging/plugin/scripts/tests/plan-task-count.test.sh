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
CC_STEP5=$(extract_fence "$CC" '**Pre-dispatch: plan structure validation')
AB_BLOCK=$(extract_fence "$AB" '**Check 5 — Plan has tasks:**')

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

echo
echo "plan-task-count: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
