#!/bin/bash
# autopilot-disarm-scope-preserve.test.sh — offline, hermetic, no network. Bash 3.2 clean.
# Targets staging/ directly, never the deployed $HOME/.claude/ copy.
# Run: bash autopilot-disarm-scope-preserve.test.sh
#
# Issue #400 (TODO.md VCS-018; live incident VCS-020). ADR-0167 — disarm clears guard state; the
# LAUNCH decides whether a surviving bound is live or spent.
# Plan: docs/superpowers/plans/2026-08-23-400-autopilot-disarm-scope-unbounded.md
#
# WHAT THIS FILE PINS. `autopilot-disarm.sh` today treats `.claude/autopilot-state/` as one
# undifferentiated transient set: `active`, `build-status`, `rtf-blocker`, `scope`, `published`,
# `started-at` and `.claude/needs-human` are all removed in one loop (ADR-0112). ADR-0167 §D1 splits
# that set: `scope` and `published` are the run's CONFIGURATION and PROGRESS, not guard conditions,
# and stop being cleared; the other five stay a byte-for-byte-unchanged whole-clear (R-03). §D2
# grows the output with a `preserved:` block, printed in both terminal branches, that can never fail
# the disarm even when the file it names cannot be read.
#
# THIS FILE GROWS ACROSS LATER TASKS, LIKE autopilot-run-scope.test.sh DID (issue #365). Task 1
# (this batch) writes DP1-DP8 against `autopilot-disarm.sh` directly. Task 4 adds DP10-DP15 (plus
# DP16-DP22) against the new `scope-file-read.sh` reporter; Task 6 adds DP23-DP32 against the launch
# path's Phase S/check-9 fences. DP9 is deliberately absent — the plan's own id list skips it. Do
# not write those later sections here; they are later tasks' own RED/GREEN pairs (ADR-0101 rule 1 —
# an assertion must not sit in the same batch as the task it depends on).
#
# EVERY DP1-DP8 ASSERTION BELOW IS RED AGAINST TODAY'S autopilot-disarm.sh, WITH ONE NAMED
# EXCEPTION: DP3 is a REGRESSION GUARD, not a red assertion — measured by running it against the
# unmodified script before writing this file (rule 13). `autopilot-disarm.sh`'s existing clear loop
# already removes `active`/`build-status`/`rtf-blocker`/`started-at`/`.claude/needs-human` (it
# removes scope/published too, today, as a superset DP3 does not examine), so the five-file-gone
# plus `--check`-exits-0 check DP3 makes is true both before and after Task 2 by construction — it
# exists to prove Task 2's loop edit does not ALSO drop a guard file by accident, exactly the role
# `autopilot-run-scope.test.sh`'s KB2/KB3 play for their own feature ("REGRESSION GUARD, NO PLANT
# ... their only job here is to prove the fix is not a guard that has stopped guarding at all"). No
# `# plant:` declarations appear in this file: per this task's own instruction and this plan's
# "Task 9 — Verify" step, plants for new `DP` assertions are declared there, once the mutation
# targets they need exist in the post-Task-2 file; declaring one now against unmodified code would
# be validated against a script Task 2 has not yet rewritten.
#
# Every block below carries an id-mapping comment (`# DPn (R-xx) — ...`), naming the requirement(s)
# from SPEC.md it addresses, per this plan's own convention.

set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
DISARM="$SCRIPTS/autopilot-disarm.sh"
GUARD="$SCRIPTS/autopilot-guard.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# mk_root <name> — a scratch project root. NOT a counter incremented inside $(...): that runs in a
# SUBSHELL, so every call returns the same directory and fixtures accumulate into each other
# (the bug ADR-0096 and ADR-0110 each hit in turn).
mk_root() {
  _r="$TMPROOT/$1"
  mkdir -p "$_r/.claude/autopilot-state"
  printf '%s' "$_r"
}

# arm <root> <session-id> — write a run marker in the current format.
arm() {
  printf 'session_id=%s\nstarted_at=%s\n' "$2" "2026-08-23T00:00:00Z" > "$1/.claude/autopilot-state/active"
}

# mk_dp_fixture <name> — a root carrying every file the PRE-Task-2 clear loop ever named: the four
# guard files, the invented started-at debris, needs-human, and the two configuration/progress
# files this feature moves out of that loop. Armed as session-AAA throughout.
mk_dp_fixture() {
  _r=$(mk_root "$1")
  arm "$_r" "session-AAA"
  printf 'RED' > "$_r/.claude/autopilot-state/build-status"
  printf 'blocker\n' > "$_r/.claude/autopilot-state/rtf-blocker"
  printf 'source=arguments\nfeatures=2\nonly=Some feature  (issue #42)\n' > "$_r/.claude/autopilot-state/scope"
  printf 'some-feature\n' > "$_r/.claude/autopilot-state/published"
  printf '2026-08-23T00:00:00Z' > "$_r/.claude/autopilot-state/started-at"
  printf 'a reason\n' > "$_r/.claude/needs-human"
  printf '%s' "$_r"
}

# =====================================================================================
# DP1 (R-02, R-08) — RECOVERY path (bare form, foreign session): a preserved `scope`/`published`
# survive disarm BYTE-IDENTICAL to what was written, not merely present. A truncated or rewritten
# file would still pass a bare `[ -f ]` check; `cmp -s` against a pre-disarm copy would not.
R=$(mk_dp_fixture dp1)
cp "$R/.claude/autopilot-state/scope" "$TMPROOT/dp1-scope-before"
cp "$R/.claude/autopilot-state/published" "$TMPROOT/dp1-published-before"
OUT=$(CLAUDE_CODE_SESSION_ID=session-BBB bash "$DISARM" "$R" 2>&1); RC=$?
if [ "$RC" = "0" ] \
   && [ -f "$R/.claude/autopilot-state/scope" ] && cmp -s "$TMPROOT/dp1-scope-before" "$R/.claude/autopilot-state/scope" \
   && [ -f "$R/.claude/autopilot-state/published" ] && cmp -s "$TMPROOT/dp1-published-before" "$R/.claude/autopilot-state/published"; then
  ok "DP1: scope and published survive the RECOVERY-path disarm, byte-identical"
else
  bad "DP1: rc=$RC scope=$( [ -f "$R/.claude/autopilot-state/scope" ] && echo present || echo absent ) published=$( [ -f "$R/.claude/autopilot-state/published" ] && echo present || echo absent ) -- $(printf '%s' "$OUT" | head -1)"
fi

# DP2 (R-02, R-08) — the mirror: COMPLETION mode (--completing), from the OWNING session. ADR-0167
# §A2 rejects a mode split on exactly this feature, so this is what stops it being reintroduced as
# a "small" fix: both modes must preserve the pair identically.
R=$(mk_dp_fixture dp2)
cp "$R/.claude/autopilot-state/scope" "$TMPROOT/dp2-scope-before"
cp "$R/.claude/autopilot-state/published" "$TMPROOT/dp2-published-before"
OUT=$(CLAUDE_CODE_SESSION_ID=session-AAA bash "$DISARM" --completing "$R" 2>&1); RC=$?
if [ "$RC" = "0" ] \
   && [ -f "$R/.claude/autopilot-state/scope" ] && cmp -s "$TMPROOT/dp2-scope-before" "$R/.claude/autopilot-state/scope" \
   && [ -f "$R/.claude/autopilot-state/published" ] && cmp -s "$TMPROOT/dp2-published-before" "$R/.claude/autopilot-state/published"; then
  ok "DP2: scope and published survive the COMPLETION-path (--completing) disarm too, byte-identical"
else
  bad "DP2: rc=$RC scope=$( [ -f "$R/.claude/autopilot-state/scope" ] && echo present || echo absent ) published=$( [ -f "$R/.claude/autopilot-state/published" ] && echo present || echo absent ) -- $(printf '%s' "$OUT" | head -1)"
fi

# DP3 (R-03) — REGRESSION GUARD, see header: same fixture shape, RECOVERY path. active,
# build-status, rtf-blocker, started-at and .claude/needs-human are all gone, and
# `autopilot-guard.sh --check` exits 0 afterwards — ADR-0112's behaviour asserted from inside the
# feature that edits this loop, so Task 2 cannot ship a partial disarm of the guard set unnoticed.
R=$(mk_dp_fixture dp3)
OUT=$(CLAUDE_CODE_SESSION_ID=session-BBB bash "$DISARM" "$R" 2>&1); RC=$?
LEFT=""
for f in active build-status rtf-blocker started-at; do
  [ -e "$R/.claude/autopilot-state/$f" ] && LEFT="$LEFT $f"
done
[ -e "$R/.claude/needs-human" ] && LEFT="$LEFT needs-human"
bash "$GUARD" --check "$R" >/dev/null 2>&1; CHECK_RC=$?
if [ "$RC" = "0" ] && [ -z "$LEFT" ] && [ "$CHECK_RC" = "0" ]; then
  ok "DP3: active/build-status/rtf-blocker/started-at/needs-human are all gone and --check exits 0"
else
  bad "DP3: rc=$RC still present:$LEFT check_rc=$CHECK_RC"
fi

# DP4 (R-08) — the exact bound text ADR-0167 §D2 specifies: a scope with features=3 and two only=
# rows, a published with two delivered lines. Matched with grep -F (substring), not a whole-line
# match, so the assertion survives whatever leading indentation the coder's IMPL sub-step picks for
# the preserved: block.
R=$(mk_root dp4)
printf 'RED' > "$R/.claude/autopilot-state/build-status"
printf 'source=arguments\nfeatures=3\nonly=Some feature  (issue #42)\nonly=Another feature  (issue #77)\n' > "$R/.claude/autopilot-state/scope"
printf 'some-feature\nanother-feature\n' > "$R/.claude/autopilot-state/published"
OUT=$(bash "$DISARM" "$R" 2>&1); RC=$?
if [ "$RC" = "0" ] \
   && printf '%s' "$OUT" | grep -qF 'preserved: .claude/autopilot-state/scope (features=3, only=2 rows)' \
   && printf '%s' "$OUT" | grep -qF 'preserved: .claude/autopilot-state/published (2 delivered)'; then
  ok "DP4: the output names both surviving files on a preserved: line, with the bound"
else
  bad "DP4: rc=$RC -- $(printf '%s' "$OUT" | grep -i preserved | head -2 | tr '\n' ' ')"
fi

# DP5 (R-08) — the REVERSE direction (rule 8): neither scope nor published ever appears on a line
# beginning removed:. Assert on the removed: lines' OWN text, extracted by prefix, never on a
# whole-output grep — the paths legitimately appear in the preserved: lines and a naive scan is
# satisfied by those (rule 12). Reuses the full seven-file fixture so at least one removed: line is
# guaranteed — guarding the denominator (rule 7): a fixture producing none would make this
# assertion vacuously true.
R=$(mk_dp_fixture dp5)
OUT=$(CLAUDE_CODE_SESSION_ID=session-BBB bash "$DISARM" "$R" 2>&1)
REMOVED_LINES=$(printf '%s\n' "$OUT" | sed -n 's/^[[:space:]]*removed: //p')
REMOVED_COUNT=$(printf '%s\n' "$REMOVED_LINES" | grep -c .)
if [ "$REMOVED_COUNT" -ge 1 ] && ! printf '%s\n' "$REMOVED_LINES" | grep -qi 'scope\|published'; then
  ok "DP5: no removed: line ever names scope or published ($REMOVED_COUNT removed: line(s) checked)"
else
  bad "DP5: $REMOVED_COUNT removed: line(s), scope/published leaked into one -- $(printf '%s' "$REMOVED_LINES" | tr '\n' ' ')"
fi

# DP6 (R-08) — the preserved: block prints in the NOTHING-ARMED branch too: a root carrying scope
# and published and NO guard files at all still exits 0, prints NOTHING-ARMED, and still names both
# preserved files — a disarm that finds nothing to clear still has to say the bound survived it.
R=$(mk_root dp6)
printf 'source=arguments\nfeatures=1\nonly=Some feature  (issue #42)\n' > "$R/.claude/autopilot-state/scope"
printf 'some-feature\n' > "$R/.claude/autopilot-state/published"
OUT=$(bash "$DISARM" "$R" 2>&1); RC=$?
if [ "$RC" = "0" ] \
   && printf '%s' "$OUT" | grep -qF 'NOTHING-ARMED' \
   && printf '%s' "$OUT" | grep -qF 'preserved: .claude/autopilot-state/scope' \
   && printf '%s' "$OUT" | grep -qF 'preserved: .claude/autopilot-state/published'; then
  ok "DP6: NOTHING-ARMED still names both preserved files"
else
  bad "DP6: rc=$RC -- $(printf '%s' "$OUT" | head -3 | tr '\n' ' ')"
fi

# DP7 (R-08) — the output names the override: a relaunch with no --features/--only reuses the
# bound, passing either replaces it. Matched flattened, undecorated, case-insensitive (rule 3) — a
# clause is the same clause whether it wraps or is backticked.
R=$(mk_dp_fixture dp7)
OUT=$(CLAUDE_CODE_SESSION_ID=session-BBB bash "$DISARM" "$R" 2>&1)
OUT_FLAT=$(printf '%s' "$OUT" | tr '\n' ' ' | tr -s ' ' | tr -d '`*')
if printf '%s' "$OUT_FLAT" | grep -qi "relaunch with no --features/--only to reuse this bound; pass either to replace it"; then
  ok "DP7: the output names the override -- relaunch with no --features/--only reuses the bound"
else
  bad "DP7: no override sentence found in the output -- $(printf '%s' "$OUT_FLAT" | head -c 160)"
fi

# DP8 — a scope file at mode 000 still leaves the disarm at exit 0, printing
# "preserved: ... (bound unreadable)". A disarm must not fail on a file it is not touching. Skipped
# when the test user can read a chmod-000 file (CI often runs as root — ADR-0028's caveat), the
# established idiom in autopilot-run-scope.test.sh section CG (e.g. CG7).
R=$(mk_root dp8)
printf 'RED' > "$R/.claude/autopilot-state/build-status"
printf 'source=arguments\nfeatures=1\n' > "$R/.claude/autopilot-state/scope"
chmod 000 "$R/.claude/autopilot-state/scope" 2>/dev/null
if [ -r "$R/.claude/autopilot-state/scope" ]; then
  ok "DP8 (skipped, not asserted): this user can read a chmod-000 file, so unreadable-scope is not expressible here"
else
  OUT=$(bash "$DISARM" "$R" 2>&1); RC=$?
  if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -qF 'preserved: .claude/autopilot-state/scope (bound unreadable)'; then
    ok "DP8: a chmod-000 scope file still exits 0, preserved as (bound unreadable)"
  else
    bad "DP8: rc=$RC -- $(printf '%s' "$OUT" | grep -i preserved | head -1)"
  fi
fi

# =====================================================================================
# DP10-DP22 (Task 4, issue #400, ADR-0167 §D6/§D7, R-01/R-05/R-06). Drive the new REPORTER,
# staging/plugin/skills/autopilot/scripts/scope-file-read.sh, directly. RED until Task 5 creates it:
# every invocation below fails the way `bash <missing-file>` fails -- "No such file or directory",
# rc=127 -- not from a bug in this assertion code. Confirmed by running this file before Task 5
# lands (rule 13's discipline, applied to a script that does not exist yet rather than to a metric).
#
# SIX STATES, DP10-DP15 (six ids): ABSENT, REUSABLE, SPENT, NOT-REUSABLE (tested twice -- DP13a via
# source=marker, DP13b via source=none -- both landing on the same state string through different
# inputs), MALFORMED, UNREADABLE.
#
# SKILLS/SFR/PC are added here because DP21's differential also drives conductor-scope-gate (issue
# #365, already landed in project-conductor/SKILL.md) via the SAME run_fence/extract_fence/fence_body
# machinery autopilot-run-scope.test.sh's section CG uses. That machinery is a DELIBERATE COPY, not
# an import (ADR-0086: two independently-runnable harnesses must fail independently) -- the same
# posture autopilot-run-scope.test.sh already takes against conductor-entry-failure-split.test.sh.
SKILLS=$(cd "$SCRIPTS/../skills" && pwd)
SFR="$SKILLS/autopilot/scripts/scope-file-read.sh"
PC="$SKILLS/project-conductor/SKILL.md"

enumerate_fences() {
  awk '
    {
      line = $0
      stripped = line; sub(/^[[:space:]]+/, "", stripped)
      if (stripped ~ /^<!--[[:space:]]*fence-(contract|illustration):/) { pending = stripped; next }
      if (stripped == "") { next }
      if (infence) { if (stripped == "```") { infence = 0 } ; next }
      if (stripped ~ /^```bash[[:space:]]*$/) {
        printf "%d\t%s\n", NR, (pending == "" ? "NONE" : pending)
        pending = ""; infence = 1; next
      }
      pending = ""
    }
  ' "$1"
}

fence_body() {
  awk -v want="$2" '
    NR == want { match($0, /^[[:space:]]*/); ind = RLENGTH; infence = 1; next }
    infence {
      s = $0; sub(/^[[:space:]]+/, "", s)
      if (s == "```") { exit }
      match($0, /^[[:space:]]*/); lw = RLENGTH
      strip = (lw < ind) ? lw : ind
      print substr($0, strip + 1)
    }
  ' "$1"
}

extract_fence() {
  _ln=$(enumerate_fences "$1" | grep -F "fence-contract: ${2} -->" | head -1 | cut -f1)
  [ -n "$_ln" ] || return 1
  fence_body "$1" "$_ln"
}

subst_paths() { sed -e "s|\$HOME/.claude/skills/|$SKILLS/|g" -e "s|~/.claude/skills/|$SKILLS/|g"; }

# run_fence <contract-id> <skill-md> <setup-script> -- same contract as autopilot-run-scope.test.sh's
# own (echoes EXTRACT_FAILED / EXTRACT_EMPTY / the exit code); "dp-" prefixed scratch files so a
# combined test run never collides with that file's own $TMPROOT entries.
run_fence() {
  _id="$1"; _f="$2"; _setup="$3"
  _body=$(extract_fence "$_f" "$_id") || { echo "EXTRACT_FAILED"; return; }
  if [ -z "$_body" ]; then echo "EXTRACT_EMPTY"; return; fi
  _s="$TMPROOT/dp-run-$_id.sh"
  { cat "$_setup"; printf '\n'; } >"$_s"
  printf '%s\n' "$_body" | subst_paths >>"$_s"
  ( bash "$_s" >"$TMPROOT/dp-out-$_id" 2>&1 ); echo "$?"
}

# setup_cg <root> <feature> <autopilot> -- binds conductor-scope-gate's three free variables, same
# shape as autopilot-run-scope.test.sh's own setup_cg (section CG).
setup_cg() {
  cat >"$TMPROOT/dp-setup-cg.sh" <<SETUP_EOF
_root='$1'
_feature='$2'
_autopilot='$3'
SETUP_EOF
  printf '%s' "$TMPROOT/dp-setup-cg.sh"
}

# DP10 (rule 11, ADR-0076) -- ABSENT: no scope file at all.
R=$(mk_root dp10)
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=ABSENT'; then
  ok "DP10: no scope file -> state=ABSENT"
else
  bad "DP10: -- $(printf '%s' "$OUT" | head -1)"
fi

# DP11 (R-05) -- REUSABLE: source=arguments, bound not yet satisfied.
R=$(mk_root dp11)
printf 'source=arguments\nfeatures=3\n' > "$R/.claude/autopilot-state/scope"
printf 'a\nb\n' > "$R/.claude/autopilot-state/published"
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=REUSABLE'; then
  ok "DP11: source=arguments, features=3, delivered=2 -> state=REUSABLE"
else
  bad "DP11: -- $(printf '%s' "$OUT" | head -1)"
fi

# DP12 (R-05) -- SPENT: source=arguments, delivered already satisfies the bound.
R=$(mk_root dp12)
printf 'source=arguments\nfeatures=2\n' > "$R/.claude/autopilot-state/scope"
printf 'a\nb\n' > "$R/.claude/autopilot-state/published"
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=SPENT'; then
  ok "DP12: source=arguments, features=2, delivered=2 -> state=SPENT"
else
  bad "DP12: -- $(printf '%s' "$OUT" | head -1)"
fi

# DP13a/DP13b -- NOT-REUSABLE, tested twice: source=marker and source=none both land on the same
# state string, through two different inputs (see block header).
R=$(mk_root dp13a)
printf 'source=marker\nfeatures=2\n' > "$R/.claude/autopilot-state/scope"
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=NOT-REUSABLE'; then
  ok "DP13a: source=marker -> state=NOT-REUSABLE"
else
  bad "DP13a: -- $(printf '%s' "$OUT" | head -1)"
fi

R=$(mk_root dp13b)
printf 'source=none\n' > "$R/.claude/autopilot-state/scope"
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=NOT-REUSABLE'; then
  ok "DP13b: source=none -> state=NOT-REUSABLE"
else
  bad "DP13b: -- $(printf '%s' "$OUT" | head -1)"
fi

# DP14 (rule 11, ADR-0076) -- MALFORMED: readable, but no usable source=/features=/only= line.
R=$(mk_root dp14)
printf 'garbage, no source line\n' > "$R/.claude/autopilot-state/scope"
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=MALFORMED'; then
  ok "DP14: readable, no source= line -> state=MALFORMED"
else
  bad "DP14: -- $(printf '%s' "$OUT" | head -1)"
fi

# DP15 (rule 11, ADR-0076) -- UNREADABLE: present, cannot be read. Skipped when the test user can
# read a chmod-000 file (CI often runs as root), the established idiom DP8/CG7 already use.
R=$(mk_root dp15)
printf 'source=arguments\nfeatures=1\n' > "$R/.claude/autopilot-state/scope"
chmod 000 "$R/.claude/autopilot-state/scope" 2>/dev/null
if [ -r "$R/.claude/autopilot-state/scope" ]; then
  ok "DP15 (skipped, not asserted): this user can read a chmod-000 file, so state=UNREADABLE is not expressible here"
else
  OUT=$(bash "$SFR" "$R" 2>&1)
  if printf '%s' "$OUT" | grep -qF 'state=UNREADABLE'; then
    ok "DP15: a chmod-000 scope file -> state=UNREADABLE"
  else
    bad "DP15: -- $(printf '%s' "$OUT" | head -1)"
  fi
fi

# DP16 (rule 5) -- it is a REPORTER: every one of the six states exits 0, not just the interesting
# ones. Fresh fixtures, independent of DP10-DP15's own roots. UNREADABLE follows the same skip idiom
# as DP15 (excluded from the aggregate, never silently counted as a pass, when this user can read a
# chmod-000 file).
DP16_BAD=""
R=$(mk_root dp16-absent)
bash "$SFR" "$R" >/dev/null 2>&1; _dp16_rc=$?
[ "$_dp16_rc" = "0" ] || DP16_BAD="$DP16_BAD ABSENT(rc=$_dp16_rc)"

R=$(mk_root dp16-reusable)
printf 'source=arguments\nfeatures=3\n' > "$R/.claude/autopilot-state/scope"
bash "$SFR" "$R" >/dev/null 2>&1; _dp16_rc=$?
[ "$_dp16_rc" = "0" ] || DP16_BAD="$DP16_BAD REUSABLE(rc=$_dp16_rc)"

R=$(mk_root dp16-spent)
printf 'source=arguments\nfeatures=1\n' > "$R/.claude/autopilot-state/scope"
printf 'a\n' > "$R/.claude/autopilot-state/published"
bash "$SFR" "$R" >/dev/null 2>&1; _dp16_rc=$?
[ "$_dp16_rc" = "0" ] || DP16_BAD="$DP16_BAD SPENT(rc=$_dp16_rc)"

R=$(mk_root dp16-notreusable)
printf 'source=none\n' > "$R/.claude/autopilot-state/scope"
bash "$SFR" "$R" >/dev/null 2>&1; _dp16_rc=$?
[ "$_dp16_rc" = "0" ] || DP16_BAD="$DP16_BAD NOT-REUSABLE(rc=$_dp16_rc)"

R=$(mk_root dp16-malformed)
printf 'garbage\n' > "$R/.claude/autopilot-state/scope"
bash "$SFR" "$R" >/dev/null 2>&1; _dp16_rc=$?
[ "$_dp16_rc" = "0" ] || DP16_BAD="$DP16_BAD MALFORMED(rc=$_dp16_rc)"

R=$(mk_root dp16-unreadable)
printf 'source=arguments\nfeatures=1\n' > "$R/.claude/autopilot-state/scope"
chmod 000 "$R/.claude/autopilot-state/scope" 2>/dev/null
if [ -r "$R/.claude/autopilot-state/scope" ]; then
  :  # skip, established idiom -- this user can read a chmod-000 file
else
  bash "$SFR" "$R" >/dev/null 2>&1; _dp16_rc=$?
  [ "$_dp16_rc" = "0" ] || DP16_BAD="$DP16_BAD UNREADABLE(rc=$_dp16_rc)"
fi

if [ -z "$DP16_BAD" ]; then
  ok "DP16: every state exits 0 (REPORTER, rule 5)"
else
  bad "DP16: non-zero exit on --$DP16_BAD"
fi

# DP17 (rule 5) -- ABSENT is this reporter's CLEAN: it prints state=ABSENT on stdout rather than
# printing nothing, so a caller writing `[ -n "$out" ]` cannot misread "no file" as "some state".
R=$(mk_root dp17)
OUT=$(bash "$SFR" "$R" 2>&1)
if [ -n "$OUT" ] && printf '%s' "$OUT" | grep -qF 'state=ABSENT'; then
  ok "DP17: ABSENT prints state=ABSENT on stdout, never empty output"
else
  bad "DP17: output was $( [ -z "$OUT" ] && echo EMPTY || printf '%s' "$OUT" | head -1 )"
fi

# DP18 -- bad invocation (no root) exits 2; a non-existent root also exits 2 (an invalid root,
# distinct from a valid root with no scope file -- that is ABSENT, exit 0, DP10). Neither shape
# produces exit 3: rule 4's distinction lives at the CALLER (Task 6's DP24), never in this script
# (ADR-0167 §D6).
bash "$SFR" >/dev/null 2>&1; RC_NOARG=$?
bash "$SFR" "$TMPROOT/dp18-does-not-exist" >/dev/null 2>&1; RC_BADROOT=$?
if [ "$RC_NOARG" = "2" ] && [ "$RC_BADROOT" = "2" ]; then
  ok "DP18: no root exits 2, a non-existent root exits 2, neither is 3"
else
  bad "DP18: rc_noarg=$RC_NOARG rc_badroot=$RC_BADROOT (want 2 and 2, never 3)"
fi

# DP19 (R-05) -- SPENT boundary: features=3 with 2/3/4 delivered. An off-by-one here is a silent
# no-op night (ADR-0167 Context).
R=$(mk_root dp19a)
printf 'source=arguments\nfeatures=3\n' > "$R/.claude/autopilot-state/scope"
printf 'a\nb\n' > "$R/.claude/autopilot-state/published"
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=REUSABLE'; then
  ok "DP19a: features=3, delivered=2 -> REUSABLE"
else
  bad "DP19a: -- $(printf '%s' "$OUT" | head -1)"
fi

R=$(mk_root dp19b)
printf 'source=arguments\nfeatures=3\n' > "$R/.claude/autopilot-state/scope"
printf 'a\nb\nc\n' > "$R/.claude/autopilot-state/published"
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=SPENT'; then
  ok "DP19b: features=3, delivered=3 -> SPENT (boundary)"
else
  bad "DP19b: -- $(printf '%s' "$OUT" | head -1)"
fi

R=$(mk_root dp19c)
printf 'source=arguments\nfeatures=3\n' > "$R/.claude/autopilot-state/scope"
printf 'a\nb\nc\nd\n' > "$R/.claude/autopilot-state/published"
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=SPENT'; then
  ok "DP19c: features=3, delivered=4 -> SPENT (over)"
else
  bad "DP19c: -- $(printf '%s' "$OUT" | head -1)"
fi

# DP20 (R-05) -- features absent, only= rows present: SPENT only when every row is delivered;
# REUSABLE when one is missing. INTERPRETATION NOTE (not a literal SPEC/ADR sentence, flagged
# rather than silently assumed): "every only= row already appears in published" cannot be a literal
# per-row text match -- `published` holds topic SLUGS (project-conductor Step 5's
# `printf '%s\n' "<topic-slug>"`), while `only=` holds the roadmap row's exact TITLE text
# (ADR-0129 §D2); the two strings are never comparable. Measured against conductor-scope-gate's own
# fence, which has no per-row match against `published` at all (its only= check is scope-file-vs-
# _feature only). This assertion therefore uses the same delivered->=N comparison DP19 makes with
# N=features, substituting N=count(only= rows) -- the reading DP21's differential also depends on.
R=$(mk_root dp20a)
printf 'source=arguments\nonly=Some feature  (issue #42)\nonly=Another feature  (issue #77)\n' > "$R/.claude/autopilot-state/scope"
printf 'a\nb\n' > "$R/.claude/autopilot-state/published"
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=SPENT'; then
  ok "DP20a: features absent, 2 only= rows, delivered=2 -> SPENT (every row delivered)"
else
  bad "DP20a: -- $(printf '%s' "$OUT" | head -1)"
fi

R=$(mk_root dp20b)
printf 'source=arguments\nonly=Some feature  (issue #42)\nonly=Another feature  (issue #77)\n' > "$R/.claude/autopilot-state/scope"
printf 'a\n' > "$R/.claude/autopilot-state/published"
OUT=$(bash "$SFR" "$R" 2>&1)
if printf '%s' "$OUT" | grep -qF 'state=REUSABLE'; then
  ok "DP20b: features absent, 2 only= rows, delivered=1 -> REUSABLE (one row missing)"
else
  bad "DP20b: -- $(printf '%s' "$OUT" | head -1)"
fi

# DP21 (rule 17) -- THE DIFFERENTIAL. ADR-0167 §D6 keeps scope-file-read.sh and
# conductor-scope-gate as two independent copies of one "delivered >= bound" comparison; this
# assertion is the entire reason that duplication is acceptable (§D6's own words). Fixture matrix:
# bounded-unstarted, bounded-partial, bounded-exhausted (features= alone), only-list-partial,
# only-list-complete (features=<count of only= rows>, PAIRED with the only= rows themselves).
#
# WHY only-list-* CARRIES A features= LINE TOO, rather than reusing DP20's features-absent shape.
# Measured against the real conductor-scope-gate fence (project-conductor/SKILL.md): its EXHAUSTED
# (exit 2) branch reads `features=`/`published` exclusively; it never checks `only=` membership
# against `published` at all -- that fence's only= check answers "is THIS one candidate in the
# bound", not "is the bound used up" (the already-published skip is the SEPARATE
# conductor-published-skip fence, not exercised here, and not named in this task's brief). A scope
# file carrying only= rows with no features= line can therefore never make conductor-scope-gate
# exit 2, for any delivered count -- there is no exit-2 signal to differentially compare there; that
# state is DP20's own, scope-file-read.sh-only, assertion. Pairing features=<count> with the only=
# rows is the one construction where both sides are answering the same question, and it is a real
# scope-file shape: an operator passing both `--features N` and `--only` tokens together.
DP21_BAD=""
CG_DP21_FEATURE='Some feature  (issue #42)'

dp21_check() {
  # dp21_check <label> <root> <sfr-expected-spent 0|1>
  _label="$1"; _root="$2"; _want_spent="$3"
  _sfr_out=$(bash "$SFR" "$_root" 2>&1)
  if printf '%s' "$_sfr_out" | grep -qF 'state=SPENT'; then _sfr_spent=1; else _sfr_spent=0; fi
  _csg_rc=$(run_fence "conductor-scope-gate" "$PC" "$(setup_cg "$_root" "$CG_DP21_FEATURE" "true")")
  if [ "$_csg_rc" = "2" ]; then _csg_exhausted=1; else _csg_exhausted=0; fi
  if [ "$_sfr_spent" != "$_want_spent" ] || [ "$_sfr_spent" != "$_csg_exhausted" ]; then
    DP21_BAD="$DP21_BAD $_label(sfr_spent=$_sfr_spent,csg_exhausted=$_csg_exhausted,csg_rc=$_csg_rc,want=$_want_spent)"
  fi
}

R=$(mk_root dp21-unstarted)
printf 'source=arguments\nfeatures=3\n' > "$R/.claude/autopilot-state/scope"
dp21_check "bounded-unstarted" "$R" 0

R=$(mk_root dp21-partial)
printf 'source=arguments\nfeatures=3\n' > "$R/.claude/autopilot-state/scope"
printf 'a\nb\n' > "$R/.claude/autopilot-state/published"
dp21_check "bounded-partial" "$R" 0

R=$(mk_root dp21-exhausted)
printf 'source=arguments\nfeatures=3\n' > "$R/.claude/autopilot-state/scope"
printf 'a\nb\nc\n' > "$R/.claude/autopilot-state/published"
dp21_check "bounded-exhausted" "$R" 1

R=$(mk_root dp21-only-partial)
printf 'source=arguments\nfeatures=2\nonly=%s\nonly=Another feature  (issue #77)\n' "$CG_DP21_FEATURE" > "$R/.claude/autopilot-state/scope"
printf 'a\n' > "$R/.claude/autopilot-state/published"
dp21_check "only-list-partial" "$R" 0

R=$(mk_root dp21-only-complete)
printf 'source=arguments\nfeatures=2\nonly=%s\nonly=Another feature  (issue #77)\n' "$CG_DP21_FEATURE" > "$R/.claude/autopilot-state/scope"
printf 'a\nb\n' > "$R/.claude/autopilot-state/published"
dp21_check "only-list-complete" "$R" 1

if [ -z "$DP21_BAD" ]; then
  ok "DP21: scope-file-read.sh's SPENT/REUSABLE verdict agrees with conductor-scope-gate's EXHAUSTED exit code across 5 fixtures"
else
  bad "DP21: disagreement on --$DP21_BAD"
fi

# DP22 -- bash -n parses the new script. RED right now: the file does not exist yet (Task 5 is a
# coder task, out of scope here), so `bash -n` fails with "No such file or directory", not a syntax
# error in a file that exists -- exactly the expected RED reason for this whole block.
if bash -n "$SFR" 2>/dev/null; then
  ok "DP22: bash -n parses scope-file-read.sh without a syntax error"
else
  bad "DP22: bash -n failed on scope-file-read.sh -- expected until Task 5 creates the file"
fi

# =====================================================================================
# DP23-DP32 (Task 6, issue #400, ADR-0167 §D3/§D4/§D5/§D6/§D7/§D8/§D9,
# R-01/R-04/R-05/R-06/R-07). Drive the TWO EXISTING fences from issue #365 --
# autopilot-scope-args (Phase S) and autopilot-scope-resolve (Phase 0 check 9) -- through the same
# run_fence/extract_fence/fence_body machinery DP10-DP22 above already stood up, this time against
# staging/plugin/skills/autopilot/SKILL.md itself: both fences already exist there (issue #365);
# Task 7 is what teaches them the precedence and reuse/reset branches this section pins. RED until
# Task 7 (fences) and Task 8 (RUNBOOK/conductor prose) land -- confirmed by running this file
# before either lands (rule 13's discipline). A few sub-cases below (DP23a/c/d, DP25, DP26c, DP28)
# are already true today by construction -- ADR-0167 §D3/§D4's own words for several of them -- and
# are called out as such rather than silently left to look red.
#
# ASSUMPTION, flagged rather than silently assumed (Task 7's own plan text: "add _scope_preserved
# (or whatever Phase S emits) to the export line"): DP24/DP26/DP27/DP28 bind a SIXTH free variable
# to check 9's fence, _scope_preserved, carrying the same state token scope-file-read.sh's own
# state= line produces (REUSABLE/SPENT/NOT-REUSABLE/MALFORMED/UNREADABLE/ABSENT), paired with a
# _scope_source value of "preserved" for the reuse branch (ADR-0167 §D3 point 2). If Task 7's coder
# names or shapes either differently, these assertions need re-anchoring at Task 9's
# plant-verification sweep -- the exact discipline autopilot-run-scope.test.sh's own RS1-RS10
# header already records for its own needles ("TASK 9 SWEEP").

NA="$SKILLS/autopilot/SKILL.md"
PLUGIN_ROOT=$(cd "$SKILLS/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
RUNBOOK="$REPO/docs/RUNBOOK-autopilot.md"

dp_out() { cat "$TMPROOT/dp-out-$1" 2>/dev/null; }

# extract_between <file> <start-regex> <end-regex> -- lines strictly between the first line
# matching <start-regex> and the next line matching <end-regex> (both exclusive). Scopes a prose
# assertion to the section it targets, never the whole file (rule 12 -- a needle must belong to the
# mechanism it asserts about, and to nothing else; "scope" and "published" both appear elsewhere in
# the RUNBOOK, in unrelated sentences).
extract_between() {
  awk -v s="$2" -v e="$3" '
    $0 ~ s { found=1; next }
    found && $0 ~ e { exit }
    found { print }
  ' "$1"
}

# setup_dp23 <root> <args> -- binds Phase S's two free variables, the same shape
# autopilot-run-scope.test.sh's own setup_ar (section AR) uses.
setup_dp23() {
  cat >"$TMPROOT/dp-setup-args.sh" <<SETUP_EOF
_root='$1'
_args='$2'
CLAUDE_PLUGIN_ROOT='$PLUGIN_ROOT'
SETUP_EOF
  printf '%s' "$TMPROOT/dp-setup-args.sh"
}

# mk_dp_launch_root <name> -- a scratch root for check 9 (autopilot-scope-resolve), which requires
# a readable PROJECT.md to not exit 3 on that check alone. One roadmap row, issue #42, matching
# every fixture below that needs a token to resolve.
mk_dp_launch_root() {
  _r="$TMPROOT/$1"
  mkdir -p "$_r/.claude/autopilot-state"
  printf -- '- [ ] Some feature  (issue #42)\n' > "$_r/PROJECT.md"
  printf '%s' "$_r"
}

# setup_launch <root> <source> <features> <only> <dry_run> <preserved> -- binds check 9's five
# existing free variables (RS section's own setup_rs shape) plus the assumed sixth, above.
setup_launch() {
  cat >"$TMPROOT/dp-setup-launch.sh" <<SETUP_EOF
_root='$1'
_scope_source='$2'
_scope_features='$3'
_scope_only='$4'
_dry_run='$5'
_scope_preserved='$6'
SETUP_EOF
  printf '%s' "$TMPROOT/dp-setup-launch.sh"
}

# DP23 (R-05) -- precedence: explicit argument -> preserved bound -> marker -> none (ADR-0167 §D3).
# Four sub-cases, one per path.

# DP23a: a REUSABLE file on disk, --features 2 on the command line -> source=arguments still wins.
# Already true today by construction (D3 point 1) -- pinned, not built, here.
R=$(mk_root dp23a)
printf 'source=arguments\nfeatures=1\n' > "$R/.claude/autopilot-state/scope"
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_dp23 "$R" "--features 2")")
OUT=$(dp_out autopilot-scope-args)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'source=arguments' && printf '%s' "$OUT" | grep -q 'features=2'; then
  ok "DP23a: an explicit --features still wins over a REUSABLE preserved file (source=arguments, already true today)"
else
  bad "DP23a: rc=$RC -- $(printf '%s' "$OUT" | head -2)"
fi

# DP23b: the same REUSABLE file, no argument -> source=preserved. The new branch; expected RED.
R=$(mk_root dp23b)
printf 'source=arguments\nfeatures=3\n' > "$R/.claude/autopilot-state/scope"
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_dp23 "$R" "")")
OUT=$(dp_out autopilot-scope-args)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'source=preserved'; then
  ok "DP23b: no argument, a REUSABLE preserved file on disk -> source=preserved"
else
  bad "DP23b: rc=$RC -- $(printf '%s' "$OUT" | head -2)"
fi

# DP23c: no argument, no file, a scope: marker -> source=marker. Already true today (unchanged
# branch); pinned so DP23b's new insertion cannot silently swallow it.
R=$(mk_root dp23c)
printf 'scope:\n  features: 3\n' > "$R/.claude/autopilot.yml"
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_dp23 "$R" "")")
OUT=$(dp_out autopilot-scope-args)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'source=marker'; then
  ok "DP23c: no argument, no preserved file, a scope: marker -> source=marker (already true today)"
else
  bad "DP23c: rc=$RC -- $(printf '%s' "$OUT" | head -2)"
fi

# DP23d: none of the three -> source=none. Already true today (unchanged branch).
R=$(mk_root dp23d)
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_dp23 "$R" "")")
OUT=$(dp_out autopilot-scope-args)
if [ "$RC" = "0" ] && printf '%s' "$OUT" | grep -q 'source=none'; then
  ok "DP23d: no argument, no preserved file, no marker -> source=none (already true today)"
else
  bad "DP23d: rc=$RC -- $(printf '%s' "$OUT" | head -2)"
fi

# DP24 (R-06, rule 4) -- the malformed/unreadable path at check 9 (see ASSUMPTION note above).
# DP24a is the proceed-anyway warning; DP24b is the refusal when removal itself is impossible;
# DP24c checks the two are VISIBLY different answers (rule 4: DID-NOT-RUN is not found-nothing).

# DP24a: a MALFORMED scope file is removed (its content does not survive), the run proceeds
# unbounded (a fresh source=none is written), and the output warns, naming the file.
R=$(mk_dp_launch_root dp24a)
SF_A="$R/.claude/autopilot-state/scope"
printf 'garbage, no source line\n' > "$SF_A"
RC_A=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_launch "$R" "none" "" "" "false" "MALFORMED")")
OUT_A=$(dp_out autopilot-scope-resolve)
if [ "$RC_A" = "0" ] && [ -f "$SF_A" ] && grep -qF 'source=none' "$SF_A" \
   && ! grep -qF 'garbage' "$SF_A" \
   && printf '%s' "$OUT_A" | grep -qi 'malformed' \
   && printf '%s' "$OUT_A" | grep -qF "$SF_A"; then
  ok "DP24a: a MALFORMED scope file is removed, the run proceeds unbounded, and the output warns, naming the file"
else
  bad "DP24a: rc=$RC_A -- $(printf '%s' "$OUT_A" | head -2)"
fi

# DP24b: removal made impossible (the containing directory chmod 555'd -- the established
# unwritable-directory idiom, concept-to-code-manifest-helpers-guards.test.sh's own
# assert_unwritable_exit4) -> exit 3, naming both the file and the manual remedy. Probed first, the
# same idiom DP8/DP15/AR9 already use for chmod-000-readable: some users (commonly root) can still
# remove a file inside a 555 directory, and there this state is not expressible.
R=$(mk_dp_launch_root dp24b)
SFDIR="$R/.claude/autopilot-state"
SF_B="$SFDIR/scope"
printf 'garbage, no source line\n' > "$SF_B"
_probe="$SFDIR/dp24-probe"
printf 'x' > "$_probe"
chmod 555 "$SFDIR"
if rm -f "$_probe" 2>/dev/null; then
  chmod 755 "$SFDIR"
  ok "DP24b (skipped, not asserted): this user can remove a file inside a chmod 555 directory, so the removal-refusal state is not expressible here"
  DP24B_SKIPPED=1
else
  RC_B=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_launch "$R" "none" "" "" "false" "MALFORMED")")
  OUT_B=$(dp_out autopilot-scope-resolve)
  chmod 755 "$SFDIR"
  rm -f "$_probe" 2>/dev/null
  DP24B_SKIPPED=0
  if [ "$RC_B" = "3" ] && printf '%s' "$OUT_B" | grep -qF "$SF_B" \
     && printf '%s' "$OUT_B" | grep -qi 'DID-NOT-RUN' && printf '%s' "$OUT_B" | grep -qi 'run:'; then
    ok "DP24b: removal made impossible -> exit 3, message names the file and the manual remedy"
  else
    bad "DP24b: rc=$RC_B -- $(printf '%s' "$OUT_B" | head -2)"
  fi
fi

# DP24c (rule 4) -- DID-NOT-RUN (DP24b) and found-nothing (DP24a) are visibly different answers:
# distinct exit codes AND distinct messages. Skipped alongside DP24b when this user can remove a
# file inside a 555 directory -- there is no second message to compare against.
if [ "$DP24B_SKIPPED" = "1" ]; then
  ok "DP24c (skipped, not asserted): DP24b's refusal state is not expressible for this user"
else
  if [ "$RC_A" != "$RC_B" ] && [ "$OUT_A" != "$OUT_B" ]; then
    ok "DP24c: DID-NOT-RUN (rc=$RC_B) and found-nothing (rc=$RC_A) are visibly different answers"
  else
    bad "DP24c: rc_a=$RC_A rc_b=$RC_B -- messages identical or exit codes equal"
  fi
fi

# DP25 (R-06) -- an ABSENT scope file (and no marker) produces NO warning at all: the ordinary
# never-had-a-bound case. Already true today by construction (no scope-file read exists yet), so
# this is a REGRESSION GUARD here, not a red assertion -- it must stay true once Task 7 lands.
R=$(mk_root dp25)
RC=$(run_fence "autopilot-scope-args" "$NA" "$(setup_dp23 "$R" "")")
OUT=$(dp_out autopilot-scope-args)
if [ "$RC" = "0" ] && ! printf '%s' "$OUT" | grep -qi 'malformed\|unreadable\|cannot be read\|could not be read'; then
  ok "DP25: an absent scope file produces no warning at all (regression guard -- already true today, must stay true)"
else
  bad "DP25: rc=$RC -- $(printf '%s' "$OUT" | head -2)"
fi

# DP26 (R-05, ADR-0167 §D4) -- the published reset, both directions, plus --dry-run.

# DP26a: a fresh write (no preserved bound reused) clears published.
R=$(mk_dp_launch_root dp26a)
printf 'source=marker\nfeatures=1\n' > "$R/.claude/autopilot-state/scope"
printf 'some-feature\n' > "$R/.claude/autopilot-state/published"
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_launch "$R" "none" "" "" "false" "NOT-REUSABLE")")
OUT=$(dp_out autopilot-scope-resolve)
if [ "$RC" = "0" ] && [ ! -f "$R/.claude/autopilot-state/published" ]; then
  ok "DP26a: check 9 removes published exactly when it writes a fresh scope"
else
  bad "DP26a: rc=$RC published=$( [ -f "$R/.claude/autopilot-state/published" ] && echo present || echo absent ) -- $(printf '%s' "$OUT" | head -2)"
fi

# DP26b: reusing a preserved bound (REUSABLE) leaves published untouched.
R=$(mk_dp_launch_root dp26b)
printf 'source=arguments\nfeatures=3\nonly=Some feature  (issue #42)\n' > "$R/.claude/autopilot-state/scope"
printf 'some-feature\n' > "$R/.claude/autopilot-state/published"
cp "$R/.claude/autopilot-state/published" "$TMPROOT/dp26b-published-before"
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_launch "$R" "preserved" "3" "" "false" "REUSABLE")")
OUT=$(dp_out autopilot-scope-resolve)
if [ "$RC" = "0" ] && [ -f "$R/.claude/autopilot-state/published" ] \
   && cmp -s "$TMPROOT/dp26b-published-before" "$R/.claude/autopilot-state/published"; then
  ok "DP26b: reusing a preserved bound (REUSABLE) leaves published untouched"
else
  bad "DP26b: rc=$RC -- $(printf '%s' "$OUT" | head -2)"
fi

# DP26c: --dry-run removes nothing and writes nothing (neither scope nor published). Already true
# today by construction (dry-run has always short-circuited before any write) -- pinned here.
R=$(mk_dp_launch_root dp26c)
printf 'source=arguments\nfeatures=1\nonly=Some feature  (issue #42)\n' > "$R/.claude/autopilot-state/scope"
printf 'some-feature\n' > "$R/.claude/autopilot-state/published"
cp "$R/.claude/autopilot-state/scope" "$TMPROOT/dp26c-scope-before"
cp "$R/.claude/autopilot-state/published" "$TMPROOT/dp26c-published-before"
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_launch "$R" "arguments" "1" "42" "true" "REUSABLE")")
OUT=$(dp_out autopilot-scope-resolve)
if [ "$RC" = "0" ] \
   && cmp -s "$TMPROOT/dp26c-scope-before" "$R/.claude/autopilot-state/scope" \
   && cmp -s "$TMPROOT/dp26c-published-before" "$R/.claude/autopilot-state/published"; then
  ok "DP26c: --dry-run removes nothing and writes nothing (already true today)"
else
  bad "DP26c: rc=$RC -- $(printf '%s' "$OUT" | head -2)"
fi

# DP27 (R-01) -- a preserved bound is announced: check 9's output names the source and the bound it
# is about to apply. Matched flattened, undecorated (rule 3).
R=$(mk_dp_launch_root dp27)
printf 'source=arguments\nfeatures=3\nonly=Some feature  (issue #42)\n' > "$R/.claude/autopilot-state/scope"
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_launch "$R" "preserved" "3" "" "false" "REUSABLE")")
OUT=$(dp_out autopilot-scope-resolve)
OUT_FLAT=$(printf '%s' "$OUT" | tr '\n' ' ' | tr -s ' ' | tr -d '`*')
if [ "$RC" = "0" ] && printf '%s' "$OUT_FLAT" | grep -qi 'preserved' \
   && printf '%s' "$OUT_FLAT" | grep -qF 'Some feature  (issue #42)'; then
  ok "DP27: a preserved bound is announced -- check 9's output names the source and the bound it is about to apply"
else
  bad "DP27: rc=$RC -- $(printf '%s' "$OUT" | head -3)"
fi

# DP28 (R-05) -- an explicit --features overwrites: after the fence, the scope file contains the
# new bound and NO line of the old one -- never merged, never appended. Already true today by
# construction (check 9's write has always been a truncating redirect); this pins it rather than
# building it (ADR-0167 §D3 point 1).
R=$(mk_dp_launch_root dp28)
printf 'source=arguments\nfeatures=1\nonly=An old row  (issue #1)\n' > "$R/.claude/autopilot-state/scope"
RC=$(run_fence "autopilot-scope-resolve" "$NA" "$(setup_launch "$R" "arguments" "1" "42" "false" "")")
OUT=$(dp_out autopilot-scope-resolve)
SF="$R/.claude/autopilot-state/scope"
if [ "$RC" = "0" ] && [ -f "$SF" ] && grep -qF 'only=Some feature  (issue #42)' "$SF" \
   && ! grep -qF 'only=An old row' "$SF"; then
  ok "DP28: an explicit --features overwrites -- the scope file carries the new bound and no line of the old one (already true today)"
else
  bad "DP28: rc=$RC -- $(printf '%s' "$OUT" | head -2) -- $(cat "$SF" 2>/dev/null | tr '\n' ' ')"
fi

# DP29 (ADR-0167 §D8) -- source=preserved takes the Phase P skip branch. INSTRUCTION, not
# enforcement (rule 16): this greps the ROUTING PROSE in autopilot/SKILL.md §1.3/§1.5, flattened
# and undecorated. A green result here is NOT proof the model actually skips Phase P at runtime --
# it is proof the instruction telling it to exists.
NA_FLAT=$(tr '\n' ' ' < "$NA" | tr -s ' ' | tr -d '`*')
if printf '%s' "$NA_FLAT" | grep -qi 'source=preserved' \
   && printf '%s' "$NA_FLAT" | grep -qi 'skip' \
   && printf '%s' "$NA_FLAT" | grep -qi 'phase p'; then
  ok "DP29 (INSTRUCTION, not enforcement, rule 16 -- not proof the model skips Phase P at runtime): autopilot/SKILL.md's routing prose states source=preserved skips Phase P"
else
  bad "DP29: no source=preserved / skip Phase P sentence found in autopilot/SKILL.md"
fi

# DP30 (R-04) -- the RUNBOOK's Aborting a run section states all three facts. Reached via the one
# .. prefix plant-check.sh allows, the same hatch autopilot-run-scope.test.sh's TU section uses,
# since this file lives outside staging/. Scoped to the section itself (rule 12) -- "scope" and
# "published" both appear elsewhere in the RUNBOOK, in unrelated sentences.
RUNBOOK_ABORT_FLAT=$(extract_between "$RUNBOOK" '^## Aborting a run' '^## ' | tr '\n' ' ' | tr -s ' ' | tr -d '`*')
DP30_OK=1
printf '%s' "$RUNBOOK_ABORT_FLAT" | grep -qi 'scope' || DP30_OK=0
printf '%s' "$RUNBOOK_ABORT_FLAT" | grep -qi 'published' || DP30_OK=0
printf '%s' "$RUNBOOK_ABORT_FLAT" | grep -qi 'survive' || DP30_OK=0
printf '%s' "$RUNBOOK_ABORT_FLAT" | grep -qi 'reuse' || DP30_OK=0
printf '%s' "$RUNBOOK_ABORT_FLAT" | grep -qi -- '--features' || DP30_OK=0
if [ "$DP30_OK" = "1" ]; then
  ok "DP30: the RUNBOOK's Aborting a run section states scope/published survive, a bare relaunch reuses the bound, and --features/--only overrides it"
else
  bad "DP30: the RUNBOOK's Aborting a run section is missing one or more of: survive / reuse / --features override"
fi

# DP31 (R-04) -- LOCAL REGRESSION GUARD for this feature's own edit to this section, NOT
# independent evidence: autopilot-run-scope.test.sh's KB8 already pins "four ways to be stuck" and
# the four-row table independently. This assertion exists because Task 8 touches the sentence
# immediately above the table (ADR-0167 §D9) and must not disturb the phrase or the row count while
# doing so.
RUNBOOK_ARMED=$(extract_between "$RUNBOOK" '^## The guard is still armed and I cannot push' '^## ')
RUNBOOK_ARMED_FLAT=$(printf '%s' "$RUNBOOK_ARMED" | tr '\n' ' ' | tr -s ' ' | tr -d '`*')
TABLE_ROWS=$(printf '%s\n' "$RUNBOOK_ARMED" | grep -c '^| `\.claude/')
if printf '%s' "$RUNBOOK_ARMED_FLAT" | grep -qi 'four ways to be stuck' && [ "$TABLE_ROWS" = "4" ]; then
  ok "DP31 (local regression guard, not independent evidence -- see comment): the guard-is-still-armed section still says four ways to be stuck and still has its four-row table"
else
  bad "DP31: table_rows=$TABLE_ROWS -- the phrase or the table row count changed"
fi

# DP32 (R-07) -- the consumer audit's landing place: project-conductor/SKILL.md's Step 2 prose,
# above the conductor-scope-gate fence, names the preserved-file lifecycle and states why this
# gate's exit-3 stays a halt (ADR-0167 §D5, rule 11 -- two call sites, opposite policies on the
# same ABSENT/UNREADABLE state, both right).
PC_STEP2_FLAT=$(extract_between "$PC" '^### Step 2 ' 'fence-contract: conductor-scope-gate' | tr '\n' ' ' | tr -s ' ' | tr -d '`*')
DP32_OK=1
printf '%s' "$PC_STEP2_FLAT" | grep -qi 'disarm' || DP32_OK=0
printf '%s' "$PC_STEP2_FLAT" | grep -qi 'survive' || DP32_OK=0
printf '%s' "$PC_STEP2_FLAT" | grep -qi 'launch' || DP32_OK=0
printf '%s' "$PC_STEP2_FLAT" | grep -qi 'halt' || DP32_OK=0
if [ "$DP32_OK" = "1" ]; then
  ok "DP32: project-conductor/SKILL.md Step 2's prose names the preserved-file lifecycle and states why conductor-scope-gate's exit-3 stays a halt"
else
  bad "DP32: Step 2's prose above conductor-scope-gate is missing one or more of: disarm / survive / launch / halt reasoning"
fi

# =====================================================================================
# Z1 -- assertion-count floor (ADR-0083 §D3). A FLOOR, not equality: this file grows across Task 4
# (DP10-DP22) and Task 6 (DP23-DP32, done here), per the header. 8 was Task 1's own contribution;
# Task 4 added 17 more (DP10-DP15 x7 incl. DP13a/DP13b, DP16, DP17, DP18, DP19a-c x3, DP20a-b x2,
# DP21, DP22), reaching 25; Task 6 adds 17 more (DP23a-d x4, DP24a-c x3, DP25, DP26a-c x3, DP27,
# DP28, DP29, DP30, DP31, DP32), so the floor rises to 42 here rather than staying pinned at 25
# (rule 10). NO PLANT: the floor's inversion is a whole assertion block silently ceasing to run, a
# structural deletion, not a one-line needle->replacement content mutation -- said here rather than
# omitted, per this task's own instruction.
_z1_total=$((PASS + FAIL))
if [ "$_z1_total" -ge 42 ]; then
  ok "Z1: assertion-count floor ($_z1_total >= 42)"
else
  bad "Z1: only $_z1_total assertions ran -- floor is 42; a section stopped running, not merely failing"
fi

echo "----"
echo "autopilot-disarm-scope-preserve.test.sh — PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
