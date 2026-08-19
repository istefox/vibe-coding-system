#!/bin/bash
# step7-snapshot-collapse.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash step7-snapshot-collapse.test.sh
#
# Issue #249 / ADR-0104. When Step 7 runs, the feature is ALREADY fully committed — by the
# orchestrator, under messages chosen for a mechanical purpose:
#
#   chore(step5): snapshot tester worktree (tester)
#   chore(step5): snapshot coder worktree (coder)
#   … seven of them on #222's branch, plus three bookkeeping commits, 1260 insertions,
#   and not one of them describes the feature.
#
# By then the staged set is two files, so `commit`'s Step 2 reads `git diff --staged` and composes
# a message describing a manifest state change. **The commit the whole skill exists to produce has
# nothing left to describe.** The `commit` skill is fine — it faithfully describes the diff it is
# given.
#
# NOBODY CHOSE THIS. ADR-0068 §D5 made the orchestrator the committer so the next stage's worktree
# could fork from a HEAD containing the previous stage's output. ADR-0049 §D1 ordered
# tester-before-coder, which doubled the snapshots per task group. Two correct decisions composing
# into a third behaviour neither considered.
#
# THE COLLAPSE IS GUARDED, NOT UNCONDITIONAL, and the guards are the design. A soft reset over a
# range containing a commit the chain did not make would fold a human's separate commit — and its
# message — into the feature commit. Nothing is *lost* (a soft reset keeps tree and index, and the
# reflog holds the old tips), but a record is. So: reset only when the baseline is an ancestor AND
# every commit in range matches a chain-produced pattern. SC4 and SC5 are those two refusals,
# executed.
#
# --- plants (plant-check.sh) ------------------------------------------------------------
# Each line below removes ONE mechanism and names the assertion that must go RED for it.
# An assertion whose plant does not fire pins nothing. Format and rationale: plant-check.sh.
# plant: SC4 | plugin/skills/concept-to-code/SKILL.md | echo "COLLAPSE_SKIP foreignCommit ${_foreign%% *}"; exit 0; | :;
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
CC="$STAGING/plugin/skills/concept-to-code/SKILL.md"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$CC" ] || { echo "FATAL: missing $CC"; exit 1; }
FLAT=$(tr '\n' ' ' <"$CC" | tr -d '`*' | tr -s ' ')

# ===========================================================================
# SC0/SC1 — the block exists, at Step 7, before the skill is invoked.
# ===========================================================================
S7=$(grep -n '^### Step 7 — Commit' "$CC" | head -1 | cut -d: -f1)
if [ -n "${S7:-}" ]; then ok "SC0 the Step 7 anchor resolves (line $S7)"
else bad "SC0 the Step 7 heading was reworded; SC1 asserts nothing"; fi

# Window widened 120 -> 140 (issue #489, ADR-0158): the collapse fence's own paragraph grew by the
# sentence stating that Step 6/Gate 5.06 make no commit of their own, and the "Use the commit
# skill" anchor moved from 127 to 127 lines past the Step 7 heading — inside the old window by
# exactly one legitimate edit's margin. Re-measured rather than padded blindly (CLAUDE.md rule 13):
# the actual distance is 127; 140 leaves the same ~13-line slack the original 120 gave over a
# then-measured ~107.
BLK=$(awk -v a="${S7:-0}" 'NR>=a && NR<a+140' "$CC")
COLLAPSE_LINE=$(printf '%s\n' "$BLK" | grep -n 'fence-contract: c2c-step7-snapshot-collapse' | head -1 | cut -d: -f1)
INVOKE_LINE=$(printf '%s\n' "$BLK" | grep -n 'Use the commit skill' | head -1 | cut -d: -f1)
if [ -n "${COLLAPSE_LINE:-}" ] && [ -n "${INVOKE_LINE:-}" ] && [ "$COLLAPSE_LINE" -lt "$INVOKE_LINE" ]; then
  ok "SC1 the collapse runs before the commit skill is invoked"
else
  bad "SC1 the collapse is missing or runs after the invocation (collapse=${COLLAPSE_LINE:-none} invoke=${INVOKE_LINE:-none}); commit would still see a two-file diff (#249)"
fi

# ===========================================================================
# SC2 — the fence extracts.
# ===========================================================================
FBODY="$TMP/collapse.sh"
awk '/fence-contract: c2c-step7-snapshot-collapse -->/{m=1; next}
     m && /^```bash$/{f=1; next}
     f && /^```$/{exit}
     f{print}' "$CC" >"$FBODY"
if [ -s "$FBODY" ] && grep -q 'reset --soft' "$FBODY"; then
  ok "SC2 the collapse extracts as a declared fence-contract"
else
  bad "SC2 the collapse fence did not extract or does not soft-reset; SC3..SC7 assert nothing"
fi

# ===========================================================================
# SC3..SC7 — executed against real git history.
# ===========================================================================
mk() {   # <n-snapshots> — repo on a feature branch with a baseline then N chain commits
  _r=$(mktemp -d "$TMP/rXXXXXX")
  (
    cd "$_r" || exit 1
    git init -q . && git config user.email t@example.invalid && git config user.name t
    echo a >a.txt && git add a.txt && git commit -qm "docs(demo): SPEC, ADR and plan"
    git checkout -qb feat
    echo base >base.txt && git add base.txt && git commit -qm "chore(demo): record Gate 4"
    git rev-parse HEAD >.baseline
    _i=0
    while [ "$_i" -lt "$1" ]; do
      echo "s$_i" >"s$_i.txt" && git add "s$_i.txt"
      git commit -qm "chore(step5): snapshot coder worktree (coder)"
      _i=$((_i + 1))
    done
  ) >/dev/null 2>&1
  printf '%s' "$_r"
}
run() {  # <repo>
  _base=$(cat "$1/.baseline")
  sed "s|<baseline>|$_base|g" "$FBODY" >"$TMP/collapse.run.sh"
  ( cd "$1" && bash "$TMP/collapse.run.sh" 2>/dev/null )
}

R=$(mk 3); BASE=$(cat "$R/.baseline")
out=$(run "$R"); rc=$?
_head=$(cd "$R" && git rev-parse HEAD)
_staged=$(cd "$R" && git diff --name-only --staged | sort | tr '\n' ' ')
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "COLLAPSED" ] && [ "$_head" = "$BASE" ] \
   && [ "$_staged" = "s0.txt s1.txt s2.txt " ]; then
  ok "SC3 three snapshots collapse: HEAD is the baseline and every file is staged as one diff"
else
  bad "SC3 expected COLLAPSED/0 with HEAD=baseline and 3 staged files; got rc=$rc out=$out head=$_head staged=[$_staged]"
fi

R=$(mk 2)
( cd "$R" && echo h >h.txt && git add h.txt && git commit -qm "fix(demo): a human commit" ) >/dev/null 2>&1
_before=$(cd "$R" && git rev-parse HEAD)
out=$(run "$R"); rc=$?
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "COLLAPSE_SKIP" ] && [ "$(cd "$R" && git rev-parse HEAD)" = "$_before" ]; then
  ok "SC4 a commit the chain did not make refuses the collapse, and HEAD is untouched"
else
  bad "SC4 expected COLLAPSE_SKIP/0 with HEAD unchanged; got rc=$rc out=$out — a human's commit message would have been folded away"
fi

# The default-branch commit carries a CHAIN-SHAPED message on purpose, so the only guard that can
# refuse here is the ancestry one. A first draft used `-qm c`, which the foreign-commit guard caught
# first — SC5 then passed for a reason it does not name, and the plant that removed the ancestry
# guard did not fire. An assertion covered by two guards isolates neither.
R=$(mk 2)
( cd "$R" && git checkout -q master 2>/dev/null || git checkout -q main
  echo c >c.txt && git add c.txt && git commit -qm "chore(demo): record the default branch"
  git checkout -q feat && { git rebase -q master 2>/dev/null || git rebase -q main; } ) >/dev/null 2>&1
_before=$(cd "$R" && git rev-parse HEAD)
out=$(run "$R"); rc=$?
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "COLLAPSE_SKIP" ] && [ "$(cd "$R" && git rev-parse HEAD)" = "$_before" ]; then
  ok "SC5 an orphaned baseline refuses the collapse (#244's state), HEAD untouched"
else
  bad "SC5 expected COLLAPSE_SKIP/0 on a rebased branch; got rc=$rc out=$out — resetting to a non-ancestor would detach the branch"
fi

R=$(mk 0)
out=$(run "$R"); rc=$?
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "COLLAPSE_SKIP" ]; then
  ok "SC6 an empty range skips rather than resetting to itself"
else
  bad "SC6 expected COLLAPSE_SKIP/0 with nothing to collapse; got rc=$rc out=$out"
fi

out=$( ( cd "$TMP" && sed "s|<baseline>|$BASE|g" "$FBODY" >"$TMP/c2.sh"; bash "$TMP/c2.sh" 2>/dev/null ) ); rc=$?
if [ "$rc" -eq 3 ]; then
  ok "SC7 outside a git repository the collapse exits 3 — did not run, never a silent success"
else
  bad "SC7 expected exit 3 outside a repo, got rc=$rc out=$out"
fi

# ===========================================================================
# SC11/SC12 — issue #489/#479, ADR-0158. The collapse sees the WHOLE feature: a post-snapshot
# correction (Gate 5.06, made by hand and never committed, per the new invariant above) is a plain
# tracked modification sitting on top of the last snapshot commit when this fence runs. `git add -u`
# must sweep it in — that is the fix — and must NOT sweep in an untracked file, which is the
# boundary `commit`'s own Step 1 scope rule already draws and this fence must not cross.
# ===========================================================================
R=$(mk 2)
( cd "$R" && echo "corrected" >s1.txt ) >/dev/null 2>&1   # tracked file, modified, never committed
out=$(run "$R"); rc=$?
_staged=$(cd "$R" && git diff --name-only --staged | sort | tr '\n' ' ')
_content=$(cd "$R" && git show :s1.txt 2>/dev/null)
# The needle is written with a plain SPACE where the file has a real newline, not a literal `\n`:
# the `\s+`-joined matcher already treats a real newline as whitespace, and `\n` is an escape valid
# only in the REPLACEMENT field (it INSERTS a line; ADR-0108's stated limit). A needle containing a
# literal backslash-n never matches the file's actual bytes there — measured on the first draft.
# The needle stops BEFORE the real ` | wc -l | tr -d ' '` pipe: the plant declaration's own field
# delimiter is ` | `, and a needle containing one literally fragments the declaration into extra
# fields (measured — PC2's registry run reported this exact line MALFORMED, 6 fields instead of 4).
# The replacement `_staged_n=$(true` leaves the line's own trailing ` | wc -l | tr -d ' ')` intact
# after substitution — `$(true | wc -l | tr -d ' ')` is still valid bash, evaluates to "0", and
# `git add -u` is gone from the span either way, which is the actual mutation SC11 needs.
# plant: SC11 | plugin/skills/concept-to-code/SKILL.md | git add -u _staged_n=$(git diff --name-only --staged | _staged_n=$(true
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "COLLAPSED" ] && [ "$_staged" = "s0.txt s1.txt " ] && [ "$_content" = "corrected" ]; then
  ok "SC11 a post-snapshot tracked correction (s1.txt, edited after its own snapshot commit and never re-committed) is swept into the collapse's staged diff, content and all"
else
  bad "SC11 expected COLLAPSED with s1.txt's CORRECTED content staged; got rc=$rc out=$out staged=[$_staged] content=[$_content] — a Gate 5.06 fix made after the last snapshot would be silently dropped (#479)"
fi

R=$(mk 2)
( cd "$R" && echo stray >debris.txt ) >/dev/null 2>&1   # untracked — never `git add`-ed by the fixture
out=$(run "$R"); rc=$?
_staged=$(cd "$R" && git diff --name-only --staged | sort | tr '\n' ' ')
_untracked=$(cd "$R" && git ls-files --others --exclude-standard)
# `.baseline` is the fixture's OWN untracked bookkeeping file (written by mk(), not by this test),
# so it is also untracked and its presence is expected — the assertion is about debris.txt alone.
if [ "$rc" -eq 0 ] && [ "${out%% *}" = "COLLAPSED" ] && [ "$_staged" = "s0.txt s1.txt " ] \
   && printf '%s\n' "$_untracked" | grep -qx 'debris.txt'; then
  ok "SC12 (forward guard, CLAUDE.md rule 6's boundary) an untracked file is NOT staged by the collapse — git add -u, never git add -A/."
else
  bad "SC12 expected debris.txt to stay untracked and unstaged; got rc=$rc out=$out staged=[$_staged] untracked=[$_untracked] — the collapse would be staging debris the worktree escape check exists to catch"
fi

# ===========================================================================
# SC8 — the cross-file contract. The collapse matches what the merge-back WRITES; if that message
# is reworded the collapse silently stops recognising its own commits and refuses forever.
# ===========================================================================
if grep -qF 'chore(step5): snapshot <stage> worktree (<agent_type>)' "$CC"; then
  ok "SC8 (forward guard) the merge-back snapshot message is unchanged — the collapse matches it"
else
  bad "SC8 the merge-back message was reworded; the collapse pattern no longer recognises chain commits and would refuse on every run"
fi

# ===========================================================================
# SC9/SC10 — the two things a reader must know before trusting a reset.
# ===========================================================================
if printf '%s\n' "$FLAT" | grep -qi 'soft reset keeps the working tree and the index'; then
  ok "SC9 the block says nothing is lost, and why"
else
  bad "SC9 nothing explains that a soft reset destroys no content; a reader has no reason to trust it"
fi

if printf '%s\n' "$FLAT" | grep -qi 'their purpose is spent'; then
  ok "SC10 the block says why the snapshots may be collapsed once Step 5 is over"
else
  bad "SC10 the collapse is asserted without the reason that makes it safe — the snapshots exist so the NEXT stage can fork, and Step 5 is over"
fi

# ===========================================================================
# Z1 — assertion-count floor (ADR-0083 §D3).
# ===========================================================================
_total=$((PASS + FAIL))
# Bumped 11 -> 13 (issue #489, ADR-0158): SC11/SC12 added.
if [ "$_total" -ge 13 ]; then ok "Z1 assertion-count floor ($_total >= 13)"
else bad "Z1 assertion count fell to $_total (floor 13) — assertions vanished from this file"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
