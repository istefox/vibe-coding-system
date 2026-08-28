#!/bin/bash
# recovery-baseline-rebase.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash recovery-baseline-rebase.test.sh
#
# Issue #244 / ADR-0103. ADR-0050 §D3 writes `recovery_baseline_sha` once at Step 5 entry and never
# rewrites it — "a baseline that moves is not a baseline". Correct as far as it goes, and it assumes
# the HISTORY under the sha does not move either.
#
# Measured on this repository, both manifests that carry a baseline:
#
#   2026-07-30-222-…  dfa9a6ff…  object exists  ORPHANED   (paused across a rebase)
#   2026-07-28-176-…  129d5e09…  object exists  ancestor   (never paused)
#
# One of two, and it is the one whose chain was paused. That is the whole argument: the sequence is
# not exotic, it is the paused-run workflow — Step 5 records the baseline, something halts the run,
# fixing the blocker means a PR to main, resuming means bringing the branch up to date, and a rebase
# is the obvious way to do that. #239 already establishes a paused Step 5 as the normal state.
#
# THE ORPHANED OBJECT SURVIVES ONLY IN THE REFLOG, so it is one `git gc` from being unrecoverable,
# and a recovery that reset to it would detach from the branch's actual history. RB8 pins that third
# state separately from the second: "exists but is not an ancestor" and "gone entirely" need
# different sentences to a human.
#
# THE MANIFEST IS DELIBERATELY NOT CORRECTED. §D3 forbids rewriting the field and the invariant is
# worth more than one record; RB5 is the forward guard that keeps this fix from starting to.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: RB1 | plugin/skills/concept-to-code/references/step5-implementation.md | merge `main` into the feature branch; do not rebase it | keep the branch up to date
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"
STEP5_REF="$STAGING/plugin/skills/concept-to-code/references/step5-implementation.md"
ADR50=$(ls "$REPO"/docs/architecture/ADR-0050-*.md 2>/dev/null | head -1)

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$CC" ] || { echo "FATAL: missing $CC"; exit 1; }
if [ -n "${ADR50:-}" ] && [ -f "$ADR50" ]; then ok "RB0 ADR-0050 resolves ($(basename "$ADR50"))"
else bad "RB0 ADR-0050 not found — RB4 asserts nothing"; fi

# VCS-047/ADR-0174: RB1/RB3/RB5's needles moved to references/step5-implementation.md.
FLAT=$(cat "$CC" "$STEP5_REF" 2>/dev/null | tr '\n' ' ' | tr -d '`*' | tr -s ' ')

# ===========================================================================
# RB1..RB3 — the rule and the check, at the site where the baseline is written.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'merge main into the feature branch; do not rebase'; then
  ok "RB1 the merge-not-rebase rule is stated"
else
  bad "RB1 the merge-not-rebase rule appears nowhere — it is the operational rule that keeps the baseline meaningful, and nothing said it (#244)"
fi

if printf '%s\n' "$FLAT" | grep -qi 'merge-base --is-ancestor'; then
  ok "RB2 the resumed-run branch validates the recorded baseline"
else
  bad "RB2 a resumed run still proceeds on a possibly-dead baseline without checking (#244)"
fi

if printf '%s\n' "$FLAT" | grep -qi 'report, not a halt'; then
  ok "RB3 the check reports rather than halting — the run is not damaged, only its recovery path"
else
  bad "RB3 nothing says the baseline check is a report; a halt here would stop a healthy run over a dead recovery path"
fi

# ===========================================================================
# RB4/RB5 — ADR-0050's own wording, and the invariant this must not start violating.
# ===========================================================================
if [ -n "${ADR50:-}" ] && grep -q '^## Correction' "$ADR50" && grep -qi 'orphan' "$ADR50"; then
  ok "RB4 ADR-0050 says what 'written once' means when the object is orphaned rather than moved"
else
  bad "RB4 ADR-0050 §D3 still reads as covering the orphaned-object case, and does not"
fi

if printf '%s\n' "$FLAT" | grep -qi 'never rewritten by a later step'; then
  ok "RB5 (forward guard) the write-once invariant survives — the fix reports, it does not correct the field"
else
  bad "RB5 the write-once invariant is gone; #244 says explicitly the manifest must not be corrected"
fi

# ===========================================================================
# RB6..RB9 — the check EXECUTED against real git history, all three states plus did-not-run.
# ===========================================================================
FBODY="$TMP/check.sh"
# VCS-047/ADR-0174: this fence-contract marker physically moved into
# references/step5-implementation.md with the rest of Step 5's body.
awk '/fence-contract: c2c-step5-baseline-ancestry -->/{m=1; next}
     m && /^```bash$/{f=1; next}
     f && /^```$/{exit}
     f{print}' "$STEP5_REF" >"$FBODY"

if [ -s "$FBODY" ] && grep -q 'is-ancestor' "$FBODY"; then
  ok "RB6 the check extracts as a declared fence-contract: c2c-step5-baseline-ancestry -->"
else
  bad "RB6 the check carries no fence-contract marker or did not extract; RB7..RB9 assert nothing"
fi

mk_repo() {   # prints the repo path; leaves HEAD on a feature branch
  _r=$(mktemp -d "$TMP/gXXXXXX")
  (
    cd "$_r" || exit 1
    git init -q . && git config user.email t@example.invalid && git config user.name t
    echo a >a.txt && git add a.txt && git commit -qm a
    git checkout -qb feat
    echo b >b.txt && git add b.txt && git commit -qm b
  ) >/dev/null 2>&1
  printf '%s' "$_r"
}
run_check() {  # <repo> <baseline-sha>
  sed "s|<baseline>|$2|g" "$FBODY" >"$TMP/check.run.sh"
  ( cd "$1" && bash "$TMP/check.run.sh" 2>/dev/null )
}

R=$(mk_repo); BASE=$(cd "$R" && git rev-parse HEAD)
out=$(run_check "$R" "$BASE"); rc=$?
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "BASELINE_OK" ]; then
  ok "RB7 an unrebased baseline reports BASELINE_OK"
else
  bad "RB7 expected BASELINE_OK/0 on an intact branch, got rc=$rc out=$out"
fi

# Rebase the feature branch over a new main commit: the recorded sha stops being an ancestor while
# the object survives in the reflog. This is #222's exact situation, reproduced.
R=$(mk_repo); BASE=$(cd "$R" && git rev-parse HEAD)
(
  cd "$R" || exit 1
  git checkout -q master 2>/dev/null || git checkout -q main
  echo c >c.txt && git add c.txt && git commit -qm c
  git checkout -q feat && git rebase -q master 2>/dev/null || git rebase -q main
) >/dev/null 2>&1
out=$(run_check "$R" "$BASE"); rc=$?
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "BASELINE_ORPHANED" ]; then
  ok "RB8 a rebased-away baseline reports BASELINE_ORPHANED (#222's exact state)"
else
  bad "RB8 expected BASELINE_ORPHANED/0 after a rebase, got rc=$rc out=$out"
fi

out=$(run_check "$R" "0000000000000000000000000000000000000000"); rc=$?
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "BASELINE_GONE" ]; then
  ok "RB9 an object that no longer exists reports BASELINE_GONE — distinct from ORPHANED"
else
  bad "RB9 expected BASELINE_GONE/0 for a missing object, got rc=$rc out=$out — 'gone' and 'not an ancestor' need different sentences to a human"
fi

out=$( ( cd "$TMP" && sed "s|<baseline>|$BASE|g" "$FBODY" >"$TMP/c2.sh"; bash "$TMP/c2.sh" 2>/dev/null ) ); rc=$?
if [ "$rc" -eq 3 ]; then
  ok "RB10 outside a git repository the check exits 3 — did not run, not 'baseline fine'"
else
  bad "RB10 expected exit 3 outside a repo, got rc=$rc out=$out; a check that cannot run must not read as a clean result"
fi

# ===========================================================================
# RB11 — the corpus measurement, re-derived. If both baselines ever become ancestors the premise
# has changed and this ADR's argument needs re-reading, not silently inheriting.
# ===========================================================================
TOT=0; ORPH=0
for m in "$REPO"/docs/manifests/*.manifest.yml; do
  [ -f "$m" ] || continue
  _b=$(grep '^recovery_baseline_sha:' "$m" 2>/dev/null | sed 's/.*: *//; s/"//g')
  case "${_b:-null}" in null|"") continue ;; esac
  TOT=$((TOT + 1))
  git -C "$REPO" merge-base --is-ancestor "$_b" HEAD >/dev/null 2>&1 || ORPH=$((ORPH + 1))
done
if [ "$TOT" -ge 1 ]; then
  ok "RB11 corpus: $ORPH of $TOT recorded baselines are not ancestors of HEAD"
else
  bad "RB11 no manifest carries a baseline — the derivation broke, or the corpus moved"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
if [ "$_total" -ge 12 ]; then ok "Z1 assertion-count floor ($_total >= 12)"
else bad "Z1 assertion count fell to $_total (floor 12) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
