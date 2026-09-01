#!/bin/bash
# step5-brief.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash step5-brief.test.sh
#
# VCS-057/ADR-0185 (Fase 2, L1). step5-brief.sh materializes a per-batch dispatch brief so a
# Step 5 coder/tester no longer reads the full plan, ADR, SPEC and project CLAUDE.md unconditionally
# before touching one source file. This harness pins the two things that make that safe:
#
#   1. The slice is BYTE-EXACT, never a paraphrase (a summary that drops a constraint is a silent
#      under-match; a contiguous extract cannot lose one inside its own range).
#   2. --verify's coverage check runs BACKWARD, from the plan to the briefs (rule 8): every real
#      task assigned to exactly one brief, with no gap, no overlap, and no boundary mismatch (a
#      brief whose task-number set is exact but whose recorded lines= is off by one).
#
# Built while debugging two real corpus defects this same session surfaced and fixed one layer
# down (VCS-057/ADR-0185 corrections to ADR-0070 and ADR-0100, rule 14):
#   - a task number can legitimately open TWICE (a leading "Task checklist" index, then the real
#     `## Task N` heading) — plan_task_starts() dedupes to the LAST occurrence;
#   - a letter-suffixed task ("Task 1b") is a DIFFERENT task from the integer it prefixes —
#     task_num() (plan-budget-parse.awk) now keeps the suffix, and a numeric --tasks range that
#     straddles one is refused by name, never silently mis-sliced.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# plant: SB6  | plugin/skills/concept-to-code/scripts/step5-brief.sh | if [ "${_hits:-0}" -eq 0 ]; then | if [ "${_hits:-0}" -eq 999999 ]; then
# plant: SB10 | plugin/skills/concept-to-code/scripts/step5-brief.sh | printf 'DID-NOT-RUN: %s has no task openers -- falling back to the full-plan prompt\n' "$PLAN" >&2 exit 3 | printf 'DID-NOT-RUN: %s has no task openers -- falling back to the full-plan prompt\n' "$PLAN" >&2 exit 0
# plant: SB14 | plugin/skills/concept-to-code/scripts/step5-brief.sh | grep -qF "plan=$PLAN_REAL " | grep -qF "plan="
# plant: SB18 | plugin/skills/concept-to-code/scripts/step5-brief.sh | if [ "$N_LINES" -eq 0 ]; then | if [ "$N_LINES" -eq 999999 ]; then
# plant: SB21 | plugin/skills/concept-to-code/scripts/step5-brief.sh | if (batch_n == 3) close_batch = 1 | if (batch_n == 999999) close_batch = 1
# plant: SB23 | plugin/skills/concept-to-code/scripts/step5-brief.sh | has_plan_budget != 0 && batch_n > 0 && has && (sum + b) > budget | has_plan_budget != 0 && batch_n > 0 && (sum + b) > budget
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
SB="$STAGING/plugin/skills/concept-to-code/scripts/step5-brief.sh"
PT="$STAGING/plugin/skills/concept-to-code/scripts/plan-tasks.sh"
PLANS="$REPO/docs/superpowers/plans"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$SB" ] || { echo "FATAL: missing $SB"; exit 1; }

HH="$PLANS/2026-07-11-38-hook-hardening.md"
WT="$PLANS/2026-07-28-176-worktree-isolation-contract.md"
ZERO_A="$PLANS/2026-05-30-deep-refactor-skill.md"
ZERO_B="$PLANS/2026-06-06-claude-md-slim.md"

[ -f "$HH" ] || { echo "FATAL: missing reference plan $HH"; exit 1; }
[ -f "$WT" ] || { echo "FATAL: missing reference plan $WT"; exit 1; }
[ -f "$ZERO_A" ] || { echo "FATAL: missing zero-opener reference plan $ZERO_A"; exit 1; }
[ -f "$ZERO_B" ] || { echo "FATAL: missing zero-opener reference plan $ZERO_B"; exit 1; }

# ===========================================================================
# SB0 — the corpus premise, derived.
# ===========================================================================
PLAN_N=$(ls "$PLANS"/*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$PLAN_N" -ge 50 ]; then ok "SB0 plan corpus non-vacuous ($PLAN_N plans)"
else bad "SB0 plan corpus is $PLAN_N (expected >= 50) — SB9 asserts nothing"; fi

# ===========================================================================
# SB1 — byte-exact slice: the brief's Task text section is EXACTLY sed -n's own extraction,
# never a paraphrase. Compared against a slice taken independently, not against a stored fixture.
# ===========================================================================
OUT1="$TMP/sb1.md"
bash "$SB" --plan "$HH" --tasks 1 --out "$OUT1" >"$TMP/sb1.log" 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  bad "SB1 step5-brief exited $rc on a well-formed request: $(cat "$TMP/sb1.log")"
else
  START=$(sed -n 's/^<!-- step5-brief:.* lines=\([0-9]*\)-.*-->$/\1/p' "$OUT1")
  END=$(sed -n 's/^<!-- step5-brief:.* lines=[0-9]*-\([0-9]*\) -->$/\1/p' "$OUT1")
  if [ -z "$START" ] || [ -z "$END" ]; then
    bad "SB1 could not parse lines= from the brief header"
  else
    INDEPENDENT=$(sed -n "${START},${END}p" "$HH")
    # The brief wraps the slice with exactly one blank line after the section header and one
    # before the next section (printf '## Task text ...\n\n' then printf '%s\n\n' "$SLICE") —
    # buf[1] and buf[n] are those two blanks; buf[2..n-1] is the slice itself, unmodified.
    IN_BRIEF=$(awk '
      /^## Task text/ { grab=1; n=0; next }
      /^## File map/ { grab=0 }
      grab { n++; buf[n]=$0 }
      END { for (i=2; i<n; i++) print buf[i] }
    ' "$OUT1")
    if [ "$IN_BRIEF" = "$INDEPENDENT" ]; then
      ok "SB1 Task text section is byte-exact vs an independent sed -n extraction of the same lines"
    else
      bad "SB1 brief's Task text diverges from an independent extraction of plan lines $START-$END"
    fi
  fi
fi

# ===========================================================================
# SB2 — file map union: a task known to declare no Budget: reports the explicit
# "no task in this range carries a parseable Budget:" line, never a silent empty section.
# ===========================================================================
OUT2="$TMP/sb2.md"
bash "$SB" --plan "$HH" --tasks 1-2 --out "$OUT2" >/dev/null 2>&1
if grep -q 'no task in this range carries a parseable Budget' "$OUT2" \
   && grep -q 'No parseable Budget: for task(s): 1 2' "$OUT2"; then
  ok "SB2 absent Budget: is reported explicitly, never as a silent empty file map"
else
  bad "SB2 expected an explicit 'no parseable Budget' + per-task list on tasks 1-2 of $HH"
fi

# ===========================================================================
# SB3 — excluded tasks: every OTHER task in the plan is named, pointing at the plan's own path.
# ===========================================================================
OUT3="$TMP/sb3.md"
bash "$SB" --plan "$HH" --tasks 1-2 --out "$OUT3" >/dev/null 2>&1
EXCL_N=$(sed -n '/## Excluded tasks/,/## Context documents/p' "$OUT3" | grep -c '^- Task ')
if [ "$EXCL_N" -eq 7 ]; then
  ok "SB3 excluded-tasks section names all 7 other tasks (9 total, 2 in this batch)"
else
  bad "SB3 expected 7 excluded tasks, found $EXCL_N"
fi
if sed -n '/## Excluded tasks/,/## Context documents/p' "$OUT3" | grep -qF "$HH"; then
  ok "SB3b every excluded task line points at the plan's own path"
else
  bad "SB3b excluded-tasks section does not name the plan's own path"
fi

# ===========================================================================
# SB4 — context documents render as PATHS with a stated reason, never read unconditionally
# (rule 16: this is instruction, not enforcement, and the brief must not imply otherwise).
# ===========================================================================
OUT4="$TMP/sb4.md"
bash "$SB" --plan "$HH" --tasks 1 --out "$OUT4" \
  --adr-path /fake/ADR-0001.md --adr-reason "task text cites a binding decision" >/dev/null 2>&1
if grep -qF '/fake/ADR-0001.md -- task text cites a binding decision' "$OUT4"; then
  ok "SB4 a passed context document renders as a path plus its reason"
else
  bad "SB4 expected the ADR path and reason to render verbatim in Context documents"
fi
OUT4b="$TMP/sb4b.md"
bash "$SB" --plan "$HH" --tasks 1 --out "$OUT4b" >/dev/null 2>&1
if grep -qF '(none passed to this brief)' "$OUT4b"; then
  ok "SB4b no context documents passed -> says so explicitly, not an empty section"
else
  bad "SB4b expected '(none passed to this brief)' when no context paths are given"
fi

# ===========================================================================
# SB5 — verify mode, CLEAN: N briefs that jointly cover every real task, no gaps, no overlaps.
# ===========================================================================
BRIEFS5="$TMP/briefs5"; mkdir -p "$BRIEFS5"
bash "$SB" --plan "$HH" --tasks 1-2 --out "$BRIEFS5/b1.md" >/dev/null 2>&1
bash "$SB" --plan "$HH" --tasks 3-5 --out "$BRIEFS5/b2.md" >/dev/null 2>&1
bash "$SB" --plan "$HH" --tasks 6-7 --out "$BRIEFS5/b3.md" >/dev/null 2>&1
bash "$SB" --plan "$HH" --tasks 8-9 --out "$BRIEFS5/b4.md" >/dev/null 2>&1
OUT5=$(bash "$SB" --verify --plan "$HH" --briefs "$BRIEFS5" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$OUT5" | grep -q '^CLEAN:'; then
  ok "SB5 --verify reports CLEAN when 4 briefs jointly cover all 9 real tasks"
else
  bad "SB5 expected exit 0 + CLEAN, got rc=$rc: $OUT5"
fi

# ===========================================================================
# SB6 — verify mode, GAP: remove one brief, its tasks must be reported uncovered.
# (plant SB6 disables the GAP branch's own condition)
# ===========================================================================
BRIEFS6="$TMP/briefs6"; mkdir -p "$BRIEFS6"
cp "$BRIEFS5/b1.md" "$BRIEFS5/b2.md" "$BRIEFS5/b4.md" "$BRIEFS6/"
OUT6=$(bash "$SB" --verify --plan "$HH" --briefs "$BRIEFS6" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$OUT6" | grep -q '^GAP.task 6' && printf '%s' "$OUT6" | grep -q '^GAP.task 7'; then
  ok "SB6 --verify reports GAP for tasks 6 and 7 when their brief is missing, exit 1"
else
  bad "SB6 expected exit 1 with GAP lines for tasks 6/7, got rc=$rc: $OUT6"
fi

# ===========================================================================
# SB7 — verify mode, OVERLAP: two briefs both claiming the same task.
# ===========================================================================
BRIEFS7="$TMP/briefs7"; mkdir -p "$BRIEFS7"
cp "$BRIEFS5"/*.md "$BRIEFS7/"
cp "$BRIEFS5/b2.md" "$BRIEFS7/b2dup.md"
OUT7=$(bash "$SB" --verify --plan "$HH" --briefs "$BRIEFS7" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$OUT7" | grep -q '^OVERLAP.task 3.*2 briefs'; then
  ok "SB7 --verify reports OVERLAP for tasks covered by two briefs, exit 1"
else
  bad "SB7 expected exit 1 with an OVERLAP line for task 3, got rc=$rc: $OUT7"
fi

# ===========================================================================
# SB8 — verify mode, BOUNDARY-MISMATCH: a brief's declared lines= disagrees with the true span
# for its own declared task set (the dangerous failure mode: coverage-by-number is exact but the
# slice boundary is wrong).
# ===========================================================================
BRIEFS8="$TMP/briefs8"; mkdir -p "$BRIEFS8"
cp "$BRIEFS5/b2.md" "$BRIEFS5/b3.md" "$BRIEFS5/b4.md" "$BRIEFS8/"
sed 's/lines=[0-9]*-[0-9]*/lines=135-999/' "$BRIEFS5/b1.md" > "$BRIEFS8/b1.md"
OUT8=$(bash "$SB" --verify --plan "$HH" --briefs "$BRIEFS8" 2>&1); rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$OUT8" | grep -q '^BOUNDARY-MISMATCH'; then
  ok "SB8 --verify reports BOUNDARY-MISMATCH when a brief's declared lines= is wrong"
else
  bad "SB8 expected exit 1 with a BOUNDARY-MISMATCH line, got rc=$rc: $OUT8"
fi

# ===========================================================================
# SB9 — backward coverage across >= 5 REAL corpus plans (rule 8, and a >= 5 guard against the
# vacuous-loop failure the plan's own spec named). One brief per plan, spanning its full purely-
# numeric task range; --verify must report CLEAN for every one attempted.
# ===========================================================================
TESTED=0; CLEAN_N=0
for f in "$PLANS"/*.md; do
  [ "$TESTED" -lt 15 ] || break   # bound the sweep; the >= 5 guard below is what matters
  n=$(bash "$PT" --count-openers "$f" 2>/dev/null)
  [ -n "$n" ] && [ "$n" -ge 1 ] 2>/dev/null || continue
  labels=$(awk -f "$STAGING/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk" \
                -f "$STAGING/plugin/skills/concept-to-code/scripts/plan-budget-parse.awk" \
                -f - "$f" <<'AWKEOF'
{ if (is_task_opener($0)) print task_num($0) }
AWKEOF
)
  nums=$(printf '%s\n' "$labels" | grep -E '^[0-9]+$')
  [ -n "$nums" ] || continue
  lo=$(printf '%s\n' "$nums" | sort -n | head -1)
  hi=$(printf '%s\n' "$nums" | sort -n | tail -1)
  BD9="$TMP/sb9-$TESTED"; mkdir -p "$BD9"
  bash "$SB" --plan "$f" --tasks "$lo-$hi" --out "$BD9/b.md" >/dev/null 2>&1 || continue
  TESTED=$((TESTED+1))
  v=$(bash "$SB" --verify --plan "$f" --briefs "$BD9" 2>&1)
  case "$v" in CLEAN:*) CLEAN_N=$((CLEAN_N+1)) ;; esac
done
if [ "$TESTED" -ge 5 ] && [ "$CLEAN_N" -eq "$TESTED" ]; then
  ok "SB9 backward coverage CLEAN on $CLEAN_N/$TESTED real corpus plans (>= 5 guard met)"
else
  bad "SB9 backward coverage: $CLEAN_N/$TESTED CLEAN (needed >= 5 tested, all CLEAN)"
fi

# ===========================================================================
# SB10 — DID-NOT-RUN (write mode): a plan with zero task openers falls back, exit 3, nothing
# written. (plant SB10 turns this exit 3 into exit 0)
# ===========================================================================
for ZP in "$ZERO_A" "$ZERO_B"; do
  OUT10="$TMP/sb10-$(basename "$ZP").md"
  bash "$SB" --plan "$ZP" --tasks 1 --out "$OUT10" >/tmp/sb10.log 2>&1
  rc=$?
  if [ "$rc" -eq 3 ] && [ ! -f "$OUT10" ] && grep -q 'DID-NOT-RUN' /tmp/sb10.log; then
    ok "SB10 $(basename "$ZP"): zero-opener plan exits 3, writes nothing, says DID-NOT-RUN"
  else
    bad "SB10 $(basename "$ZP"): expected exit 3 + no file + DID-NOT-RUN, got rc=$rc, file exists=$([ -f "$OUT10" ] && echo yes || echo no)"
  fi
done
rm -f /tmp/sb10.log

# ===========================================================================
# SB11 — DID-NOT-RUN (verify mode): a briefs dir with no brief naming this plan is exit 3, never
# a false CLEAN (rule 4: an unrun check must not read as a clean pass).
# ===========================================================================
EMPTY11="$TMP/empty11"; mkdir -p "$EMPTY11"
OUT11=$(bash "$SB" --verify --plan "$HH" --briefs "$EMPTY11" 2>&1); rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$OUT11" | grep -q 'DID-NOT-RUN'; then
  ok "SB11 --verify with no matching brief exits 3, never a false CLEAN"
else
  bad "SB11 expected exit 3 + DID-NOT-RUN on an empty briefs dir, got rc=$rc: $OUT11"
fi

# ===========================================================================
# SB12 — bad invocation: a requested task that does not exist in the plan exits 2.
# ===========================================================================
bash "$SB" --plan "$HH" --tasks 99 --out "$TMP/sb12.md" >/tmp/sb12.log 2>&1; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'does not exist' /tmp/sb12.log && [ ! -f "$TMP/sb12.md" ]; then
  ok "SB12 a requested task number absent from the plan exits 2, writes nothing"
else
  bad "SB12 expected exit 2 + no file for task 99 of 9, got rc=$rc"
fi
rm -f /tmp/sb12.log

# ===========================================================================
# SB13 — letter-suffixed task in range: named explicitly, distinct from a real numbering gap
# (regression pin for this session's fix — task_num() keeping the "1b" suffix).
# ===========================================================================
bash "$SB" --plan "$WT" --tasks 1-2 --out "$TMP/sb13.md" >/tmp/sb13.log 2>&1; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'also span task(s) 1b' /tmp/sb13.log && [ ! -f "$TMP/sb13.md" ]; then
  ok "SB13 tasks 1-2 on a plan with a real Task 1b names it explicitly, exit 2, writes nothing"
else
  bad "SB13 expected exit 2 naming '1b', got rc=$rc: $(cat /tmp/sb13.log)"
fi
rm -f /tmp/sb13.log

# ===========================================================================
# SB14 — producer/consumer path match (rule 17): --verify must match a brief's header by the
# PLAN'S OWN realpath, not by any looser test — a brief written for a DIFFERENT plan must never
# satisfy this plan's --verify. (plant SB14 loosens the match to accept any plan= header)
# ===========================================================================
BRIEFS14="$TMP/briefs14"; mkdir -p "$BRIEFS14"
bash "$SB" --plan "$WT" --tasks 2 --out "$BRIEFS14/wrong-plan.md" >/dev/null 2>&1
OUT14=$(bash "$SB" --verify --plan "$HH" --briefs "$BRIEFS14" 2>&1); rc=$?
if [ "$rc" -eq 3 ] && printf '%s' "$OUT14" | grep -q 'DID-NOT-RUN'; then
  ok "SB14 a brief written for a different plan is correctly rejected (exit 3, not a false CLEAN)"
else
  bad "SB14 expected exit 3 when the only brief present names a different plan, got rc=$rc: $OUT14"
fi

# ===========================================================================
# SB15 — a comma-list --tasks is refused, not silently interpreted as a range or a single value
# (a brief is one contiguous slice by construction).
# ===========================================================================
bash "$SB" --plan "$HH" --tasks "1,3" --out "$TMP/sb15.md" >/tmp/sb15.log 2>&1; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'comma list' /tmp/sb15.log && [ ! -f "$TMP/sb15.md" ]; then
  ok "SB15 a comma-list --tasks is refused, exit 2, writes nothing"
else
  bad "SB15 expected exit 2 refusing a comma list, got rc=$rc"
fi
rm -f /tmp/sb15.log

# ===========================================================================
# SB16 — dedup regression pin: hook-hardening.md's checklist-index restates every task before its
# real heading. Task 1's brief must slice from the REAL heading (line 135), never the index line
# (line 17) — the exact defect this session found and fixed in plan_task_starts().
# ===========================================================================
OUT16="$TMP/sb16.md"
bash "$SB" --plan "$HH" --tasks 1 --out "$OUT16" >/dev/null 2>&1
START16=$(sed -n 's/^<!-- step5-brief:.* lines=\([0-9]*\)-.*-->$/\1/p' "$OUT16")
if [ "$START16" = "135" ]; then
  ok "SB16 Task 1's slice starts at the real heading (line 135), not the checklist-index line (17)"
else
  bad "SB16 expected Task 1's start_line to be 135 (the heading), got $START16"
fi

# ===========================================================================
# SB17-SB20 — digest mode (VCS-057/ADR-0185, L1 plan-sequence step 4). A small fixture, not the
# real corpus: this mode reads a PROJECT.md-shaped file, not a plan, so the plan corpus above is
# not the right population to test it against.
# ===========================================================================
PROJFIX="$TMP/PROJECT-fixture.md"
cat >"$PROJFIX" <<'PROJEOF'
# Project: fixture

## Overview

Narrative prose that must NOT appear in the digest — the whole point of this mode.

## Phases

### Phase 1 — prep

Narrative between the heading and its checkboxes, also excluded.

- [x] item one  (issue #1)
- [x] item two  (issue #2)

### Phase 2 — build

- [ ] item three  (issue #3)
- [ ] item four  (issue #4)

#### Risks

- a plain, non-checkbox bullet that must NOT appear in the digest either.
PROJEOF

# ---------------------------------------------------------------------------
# SB17 — digest holds exactly the "### Phase" headings and checkbox lines, verified against an
# INDEPENDENT extraction of the same fixture (never compared to a hand-copied string — same
# byte-exact discipline as SB1, applied to this mode's much smaller output).
# ---------------------------------------------------------------------------
OUT17="$TMP/sb17.md"
bash "$SB" --digest --project-md "$PROJFIX" --out "$OUT17" >/tmp/sb17.log 2>&1
rc=$?
INDEPENDENT17=$(awk '/^### Phase/ || /^[ \t]*- \[[ xX]\]/' "$PROJFIX")
IN_DIGEST17=$(sed -n '/^### Phase/,$p' "$OUT17")
if [ "$rc" -eq 0 ] && [ "$IN_DIGEST17" = "$INDEPENDENT17" ]; then
  ok "SB17 digest holds exactly the phase headings and checkbox lines, byte-exact vs an independent extraction"
else
  bad "SB17 expected rc=0 and digest == independent extraction, got rc=$rc"
fi
if printf '%s\n' "$IN_DIGEST17" | grep -qi 'narrative\|Risks\|plain, non-checkbox'; then
  bad "SB17b narrative prose / non-checkbox bullets leaked into the digest"
else
  ok "SB17b no narrative prose or non-checkbox bullet leaked into the digest"
fi

# ---------------------------------------------------------------------------
# SB18 — DID-NOT-RUN: a PROJECT.md with no "### Phase" heading and no checkbox line falls back,
# exit 3, nothing written (plant SB18 disables this guard).
# ---------------------------------------------------------------------------
NOPHASE="$TMP/no-phase-fixture.md"
printf '# Just a title\n\nSome narrative prose only, no phases, no checkboxes.\n' >"$NOPHASE"
OUT18="$TMP/sb18.md"
bash "$SB" --digest --project-md "$NOPHASE" --out "$OUT18" >/tmp/sb18.log 2>&1
rc=$?
if [ "$rc" -eq 3 ] && [ ! -f "$OUT18" ] && grep -q 'DID-NOT-RUN' /tmp/sb18.log; then
  ok "SB18 a PROJECT.md with no phase heading and no checkbox exits 3, writes nothing, says DID-NOT-RUN"
else
  bad "SB18 expected exit 3 + no file + DID-NOT-RUN, got rc=$rc, file exists=$([ -f "$OUT18" ] && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
# SB19 — bad invocation: --digest without --project-md exits 2, writes nothing.
# ---------------------------------------------------------------------------
bash "$SB" --digest --out "$TMP/sb19.md" >/tmp/sb19.log 2>&1; rc=$?
if [ "$rc" -eq 2 ] && grep -q -- '--project-md' /tmp/sb19.log && [ ! -f "$TMP/sb19.md" ]; then
  ok "SB19 --digest without --project-md exits 2, writes nothing"
else
  bad "SB19 expected exit 2 naming --project-md, got rc=$rc"
fi
rm -f /tmp/sb17.log /tmp/sb18.log /tmp/sb19.log

# ===========================================================================
# SB20-SB28 — --suggest-batches mode (VCS-057 plan, Fase 2 L2, ADR-0186). Budget-driven batch
# sizing: fill a batch with consecutive openers while the sum of declared Budget: ceilings stays
# at or under --budget (default 210), hard cap 3, floor 1. An unbudgeted/MALFORMED task never
# moves the sum and never closes a batch on its own -- only the hard cap does. Zero plan-wide
# budgets -> plain opener grouping, reported as mode=openers.
# ===========================================================================
AWK_P="$STAGING/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk"
AWK_B="$STAGING/plugin/skills/concept-to-code/scripts/plan-budget-parse.awk"

# --- SB20/SB20b — corpus invariant: on every real plan with task openers, budget-driven batching
# never produces FEWER batches (i.e. never a batch bigger) than today's fixed ceil(openers/3)
# grouping, and every printed batch spans at most 3 distinct task numbers. Independently derived
# per plan (real opener count, deduped), never hardcoded (rule 2 -- same byte-exact discipline as
# SB17's independent extraction, applied here to a property instead of a string).
# ---------------------------------------------------------------------------
_sb20_fail=0; _sb20b_fail=0; _sb20_n=0
for _p in "$PLANS"/*.md; do
  _openers=$(awk -f "$AWK_P" -f "$AWK_B" -f /dev/fd/3 "$_p" 3<<'AWKEOF'
{ if (is_task_opener($0)) print task_num($0) }
AWKEOF
)
  _n_openers=$(printf '%s\n' "$_openers" | awk '!seen[$0]++' | grep -c .)
  [ "$_n_openers" -eq 0 ] && continue
  _sb20_n=$((_sb20_n+1))
  _out=$(bash "$SB" --suggest-batches --plan "$_p" 2>/dev/null)
  _n_batches=$(printf '%s\n' "$_out" | tail -n +2 | grep -c .)
  _n_today=$(( (_n_openers + 2) / 3 ))
  if [ "$_n_batches" -lt "$_n_today" ]; then
    _sb20_fail=$((_sb20_fail+1))
  fi
  while IFS= read -r _rng; do
    [ -n "$_rng" ] || continue
    case "$_rng" in
      *-*)
        _lo="${_rng%%-*}"; _hi="${_rng##*-}"
        _members=$(printf '%s\n' "$_openers" | awk '!seen[$0]++' | awk -v lo="$_lo" -v hi="$_hi" '
          BEGIN{seen=0} $0==lo{seen=1} seen{c++} $0==hi{exit} END{print c}')
        ;;
      *) _members=1 ;;
    esac
    [ "${_members:-0}" -gt 3 ] && _sb20b_fail=$((_sb20b_fail+1))
  done < <(printf '%s\n' "$_out" | tail -n +2)
done
if [ "$_sb20_n" -ge 20 ] && [ "$_sb20_fail" -eq 0 ]; then
  ok "SB20 corpus invariant: budget-driven batching never produces fewer batches than ceil(openers/3) on any of $_sb20_n plans"
else
  bad "SB20 expected 0 violations across >=20 plans, got $_sb20_fail violations on $_sb20_n plans"
fi
if [ "$_sb20b_fail" -eq 0 ]; then
  ok "SB20b every printed batch spans at most 3 task openers, across the full corpus"
else
  bad "SB20b $_sb20b_fail batch(es) exceeded 3 task openers"
fi

# ---------------------------------------------------------------------------
# SB21 — the hard cap holds against an adversarial budget: 4 tiny-budget tasks with a huge
# --budget still split 3+1, never a batch of 4. (plant SB21 disables the cap.)
# ---------------------------------------------------------------------------
CAPFIX="$TMP/cap-fixture.md"
cat >"$CAPFIX" <<'CAPEOF'
## Task 1 -- a
Budget: `a.py` (~1 lines)

## Task 2 -- b
Budget: `b.py` (~1 lines)

## Task 3 -- c
Budget: `c.py` (~1 lines)

## Task 4 -- d
Budget: `d.py` (~1 lines)
CAPEOF
OUT21=$(bash "$SB" --suggest-batches --plan "$CAPFIX" --budget 999999 2>/dev/null)
EXPECT21="mode	budget
1-3
4"
if [ "$OUT21" = "$EXPECT21" ]; then
  ok "SB21 hard cap holds against a huge --budget: 4 tasks split 1-3, 4 -- never a batch of 4"
else
  bad "SB21 expected [$EXPECT21], got [$OUT21]"
fi

# ---------------------------------------------------------------------------
# SB22 — the floor holds: a single task whose OWN declared budget already exceeds --budget still
# forms a batch of 1, never 0 (never dropped, never merged past the cap by a hostile ceiling).
# ---------------------------------------------------------------------------
FLOORFIX="$TMP/floor-fixture.md"
cat >"$FLOORFIX" <<'FLOOREOF'
## Task 1 -- huge
Budget: `a.py` (~5000 lines)

## Task 2 -- also huge
Budget: `b.py` (~5000 lines)
FLOOREOF
OUT22=$(bash "$SB" --suggest-batches --plan "$FLOORFIX" --budget 10 2>/dev/null)
EXPECT22="mode	budget
1
2"
if [ "$OUT22" = "$EXPECT22" ]; then
  ok "SB22 floor holds: each oversized task forms its own singleton batch, never zero, never merged"
else
  bad "SB22 expected [$EXPECT22], got [$OUT22]"
fi

# ---------------------------------------------------------------------------
# SB23 — a MALFORMED Budget: (an attempt that does not fully parse -- corpus-wide count is 0, so
# this fixture is synthesized, rule 9) never moves the running sum and never closes a batch on its
# own: it joins whatever batch is open, exactly like an absent Budget:.
# ---------------------------------------------------------------------------
MALFIX="$TMP/malformed-fixture.md"
cat >"$MALFIX" <<'MALEOF'
## Task 1 -- a
Budget: `a.py` (~50 lines)

## Task 2 -- b
Budget: `b.py` (~50 lines) extra-trailing-junk-that-does-not-parse

## Task 3 -- c
Budget: `c.py` (~50 lines)
MALEOF
OUT23=$(bash "$SB" --suggest-batches --plan "$MALFIX" --budget 40 2>/dev/null)
EXPECT23="mode	budget
1-2
3"
if [ "$OUT23" = "$EXPECT23" ]; then
  ok "SB23 a MALFORMED Budget: joins the open batch without moving the sum or forcing a close (1-2, 3)"
else
  bad "SB23 expected [$EXPECT23], got [$OUT23]"
fi

# ---------------------------------------------------------------------------
# SB24 — plan-wide fallback: a real corpus plan with zero parseable budgets reports mode=openers
# and ranges byte-identical to an independently-derived plain opener grouping (fixed groups of
# <=3), never mode=budget.
# ---------------------------------------------------------------------------
NOBUDGET="$PLANS/2026-05-17-agents-improvement.md"
[ -f "$NOBUDGET" ] || { echo "FATAL: missing reference plan $NOBUDGET"; exit 1; }
OUT24=$(bash "$SB" --suggest-batches --plan "$NOBUDGET" 2>/dev/null)
MODE24=$(printf '%s\n' "$OUT24" | head -1)
RANGES24=$(printf '%s\n' "$OUT24" | tail -n +2)
INDEP24=$(awk -f "$AWK_P" -f "$AWK_B" -f /dev/fd/3 "$NOBUDGET" 3<<'AWKEOF'
{ if (is_task_opener($0)) print task_num($0) }
AWKEOF
)
INDEP_RANGES24=$(printf '%s\n' "$INDEP24" | awk '!seen[$0]++' | awk '
  { a[NR]=$0 } END {
    for (i=1;i<=NR;i+=3) {
      lo=a[i]; hi=(i+2<=NR)?a[i+2]:a[NR]
      if (i+1>NR) print lo; else if (lo==hi) print lo; else print lo "-" hi
    }
  }')
if [ "$MODE24" = "mode	openers" ] && [ "$RANGES24" = "$INDEP_RANGES24" ]; then
  ok "SB24 an unbudgeted plan reports mode=openers with ranges byte-identical to plain opener grouping"
else
  bad "SB24 expected mode=openers and ranges=[$INDEP_RANGES24], got mode=[$MODE24] ranges=[$RANGES24]"
fi

# ---------------------------------------------------------------------------
# SB25/SB26 — DID-NOT-RUN: the two corpus plans with zero task openers exit 3 under
# --suggest-batches, same as write/verify mode (rule 4).
# ---------------------------------------------------------------------------
bash "$SB" --suggest-batches --plan "$ZERO_A" >/tmp/sb25.log 2>&1; rc=$?
if [ "$rc" -eq 3 ] && grep -q 'DID-NOT-RUN' /tmp/sb25.log; then
  ok "SB25 --suggest-batches on a zero-opener plan ($ZERO_A) exits 3, DID-NOT-RUN"
else
  bad "SB25 expected exit 3 + DID-NOT-RUN on $ZERO_A, got rc=$rc"
fi
bash "$SB" --suggest-batches --plan "$ZERO_B" >/tmp/sb26.log 2>&1; rc=$?
if [ "$rc" -eq 3 ] && grep -q 'DID-NOT-RUN' /tmp/sb26.log; then
  ok "SB26 --suggest-batches on a zero-opener plan ($ZERO_B) exits 3, DID-NOT-RUN"
else
  bad "SB26 expected exit 3 + DID-NOT-RUN on $ZERO_B, got rc=$rc"
fi
rm -f /tmp/sb25.log /tmp/sb26.log

# ---------------------------------------------------------------------------
# SB27 — bad invocation: a non-numeric or non-positive --budget exits 2, naming --budget.
# ---------------------------------------------------------------------------
bash "$SB" --suggest-batches --plan "$HH" --budget abc >/tmp/sb27.log 2>&1; rc27a=$?
bash "$SB" --suggest-batches --plan "$HH" --budget 0 >/tmp/sb27b.log 2>&1; rc27b=$?
if [ "$rc27a" -eq 2 ] && grep -q -- '--budget' /tmp/sb27.log \
   && [ "$rc27b" -eq 2 ] && grep -q -- '--budget' /tmp/sb27b.log; then
  ok "SB27 a non-numeric or non-positive --budget exits 2, naming --budget"
else
  bad "SB27 expected exit 2 naming --budget for both 'abc' and '0', got rc=$rc27a/$rc27b"
fi
rm -f /tmp/sb27.log /tmp/sb27b.log

# ---------------------------------------------------------------------------
# SB28 — producer/consumer meet on the exact flag string (rule 17): "--suggest-batches" appears in
# both the script and the reference doc that invokes it, scanned from both sides rather than
# asserted twice by hand.
# ---------------------------------------------------------------------------
STEP5REF="$STAGING/plugin/skills/concept-to-code/references/step5-implementation.md"
if grep -qF -- '--suggest-batches' "$SB" && [ -f "$STEP5REF" ] && grep -qF -- '--suggest-batches' "$STEP5REF"; then
  ok "SB28 --suggest-batches is named in both step5-brief.sh and step5-implementation.md"
else
  bad "SB28 --suggest-batches missing from step5-brief.sh and/or step5-implementation.md"
fi

# ===========================================================================
# Z1 — assertion-count floor. An exact count, not a >= floor with slack (rule 10): every
# assertion above is enumerated here by hand, so a silently deleted one is caught.
# ===========================================================================
TOTAL=$((PASS+FAIL))
if [ "$TOTAL" -eq 34 ]; then ok "Z1: 34 assertions ran (exact) — none silently vanished"
else bad "Z1: expected exactly 34 assertions, ran $TOTAL"; fi

echo "----"
echo "$SCRIPTS/../step5-brief.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
