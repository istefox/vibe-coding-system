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
# Z1 -- assertion-count floor (ADR-0083 §D3). A FLOOR, not equality: this file grows across Task 4
# (DP10-DP22) and Task 6 (DP23-DP32), per the header, so 8 is this task's own contribution, raised
# there rather than pinned exactly here (rule 10). NO PLANT: the floor's inversion is a whole
# assertion block silently ceasing to run, a structural deletion, not a one-line needle->replacement
# content mutation -- said here rather than omitted, per this task's own instruction.
_z1_total=$((PASS + FAIL))
if [ "$_z1_total" -ge 8 ]; then
  ok "Z1: assertion-count floor ($_z1_total >= 8)"
else
  bad "Z1: only $_z1_total assertions ran -- floor is 8; a section stopped running, not merely failing"
fi

echo "----"
echo "autopilot-disarm-scope-preserve.test.sh — PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
