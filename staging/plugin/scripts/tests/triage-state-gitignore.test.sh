#!/bin/bash
# triage-state-gitignore.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash triage-state-gitignore.test.sh
#
# Issue #250 / ADR-0094. `review-triage-fix`'s state file is per-branch by design, and Step 5's
# `triage-state.sh commit` gitignored it by appending its RESOLVED name:
#
#     .claude/.triage-fix-last-feat_222-vendor-deployed-only-skills.json
#
# The branch is deleted at merge; the .gitignore line is not. One dead entry per branch, forever,
# and in a public repo that is a list of every feature branch ever reviewed, abandoned ones
# included.
#
# IT ALSO DEFEATED ITS OWN PURPOSE. A per-branch line protects exactly one branch. The NEXT branch
# is unprotected until its own cycle appends its own line — so the mechanism that exists to keep
# RTF state out of the repository was, on any new branch, not yet doing it.
#
# The fix appends a GLOB, and asks `git check-ignore` whether the path is already covered by ANY
# rule rather than grepping for its own line — because a human may have written a broader one by
# hand, and this repository's own .gitignore is the proof: it carried
# `.claude/.triage-fix-last*.json` before the glob existed.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TS="$STAGING/plugin/skills/review-triage-fix/scripts/triage-state.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

GLOB='.claude/.triage-fix-last-*.json'
FIX_N=0

# mk_repo <seed-gitignore-line> — a throwaway git repo with .claude/ and a seeded .gitignore.
mk_repo() {
  FIX_N=$((FIX_N + 1))
  _r="$TMP/r$FIX_N"
  mkdir -p "$_r/.claude"
  ( cd "$_r" && git init -q . && git config user.email t@example.invalid && git config user.name t )
  printf '%s\n' "$1" >"$_r/.gitignore"
  printf '%s' "$_r"
}

# cycle <repo> <branch>... — run one commit cycle per branch, as RTF Step 5 does.
cycle() {
  _r="$1"; shift
  for _b in "$@"; do
    printf '[]' >"$_r/.claude/.triage-fix-last-$_b.json"
    printf '[]' | bash "$TS" commit "$_r/.claude/.triage-fix-last-$_b.json" >/dev/null 2>&1
  done
}

gi_lines() { grep -c . "$1/.gitignore" 2>/dev/null || true; }

# ==================================================================================================
# T0. Anchor.
# ==================================================================================================
if [ -f "$TS" ] && [ -r "$TS" ]; then
  ok "T0: triage-state.sh exists and is readable"
else
  bad "T0: $TS not found — every assertion below is meaningless"
fi

# ==================================================================================================
# T1. RED EVIDENCE, and it is DERIVED rather than hand-written: the pre-#250 append is reconstructed
# from the shipped script by sed, so it cannot drift into testing some other logic. Three branches
# must have produced three dead lines.
# ==================================================================================================
PRE="$TMP/triage-state-pre250.sh"
sed -e 's|glob="${pref}\.triage-fix-last-\*\.json"|glob="${pref}$(basename "$SF")"|' \
    -e 's|if git -C "\$d" check-ignore -q -- "\$(basename "\$SF")" 2>/dev/null; then|if false; then|' \
    "$TS" >"$PRE"
if bash -n "$PRE" 2>/dev/null && grep -q 'basename "\$SF"' "$PRE" && grep -q 'if false; then' "$PRE"; then
  ok "T1a: the pre-#250 variant was reconstructed from the shipped script and parses"
else
  bad "T1a: could not reconstruct the pre-#250 variant — T1b below proves nothing"
fi
R_PRE=$(mk_repo 'seed')
for _b in feat_aaa feat_bbb fix_ccc; do
  printf '[]' >"$R_PRE/.claude/.triage-fix-last-$_b.json"
  printf '[]' | bash "$PRE" commit "$R_PRE/.claude/.triage-fix-last-$_b.json" >/dev/null 2>&1
done
T1_N=$(gi_lines "$R_PRE")
if [ "${T1_N:-0}" -eq 4 ] && grep -q 'triage-fix-last-feat_aaa' "$R_PRE/.gitignore"; then
  ok "T1b (red evidence): the pre-#250 append leaves one dead per-branch line per branch (seed + 3 = $T1_N lines)"
else
  bad "T1b: the pre-#250 variant did not reproduce the accumulation (lines=$T1_N) — T2 is not pinning the bug it claims to"
fi

# ==================================================================================================
# T2-T3. THE FIX. Three branches, one line, and it is the glob.
# ==================================================================================================
R1=$(mk_repo 'seed')
cycle "$R1" feat_aaa feat_bbb fix_ccc
T2_N=$(gi_lines "$R1")
if [ "${T2_N:-0}" -eq 2 ]; then
  ok "T2: three branches add exactly ONE line (seed + 1 = $T2_N), not one per branch"
else
  bad "T2: three branches produced $T2_N .gitignore line(s) — expected 2 (seed + one glob): $(tr '\n' '|' <"$R1/.gitignore")"
fi
if grep -Fxq "$GLOB" "$R1/.gitignore"; then
  ok "T3: the line added is the glob $GLOB"
else
  bad "T3: the added line is not the expected glob: $(tr '\n' '|' <"$R1/.gitignore")"
fi
if grep -q 'triage-fix-last-feat_aaa\|triage-fix-last-fix_ccc' "$R1/.gitignore"; then
  bad "T4: a resolved per-branch name still reached .gitignore — the accumulation is not fixed"
else
  ok "T4: no resolved per-branch name appears in .gitignore"
fi

# ==================================================================================================
# T5-T8. ALREADY-COVERED, by four differently-shaped rules a human might have written. A literal
# grep for the script's own glob recognises none of them and would append a duplicate beside each.
# ==================================================================================================
t_covered() {  # t_covered <label> <seed-rule>
  _r=$(mk_repo "$2")
  cycle "$_r" feat_zzz
  _n=$(gi_lines "$_r")
  if [ "${_n:-0}" -eq 1 ]; then ok "$1"
  else bad "$1 — appended beside an existing covering rule: $(tr '\n' '|' <"$_r/.gitignore")"; fi
}
t_covered "T5: a broader hand-written rule (.claude/.triage-fix-last*.json) suppresses the append" \
          '.claude/.triage-fix-last*.json'
t_covered "T6: a whole-directory rule (.claude/) suppresses the append" '.claude/'
t_covered "T7: a wide rule (*.json) suppresses the append" '*.json'
t_covered "T8: the script's own glob, already present, is not duplicated" "$GLOB"

# ==================================================================================================
# T9. Idempotence across repeated cycles on the SAME branch — the common case, since RTF runs its
# cycle more than once per branch.
# ==================================================================================================
R9=$(mk_repo 'seed')
cycle "$R9" feat_same
cycle "$R9" feat_same
cycle "$R9" feat_same
T9_N=$(gi_lines "$R9")
if [ "${T9_N:-0}" -eq 2 ]; then
  ok "T9: three cycles on one branch still add exactly one line"
else
  bad "T9: repeated cycles on one branch produced $T9_N line(s): $(tr '\n' '|' <"$R9/.gitignore")"
fi

# ==================================================================================================
# T10. An ABSOLUTE state-file path. `git -C "$d"` runs from the file's own directory, so a path
# passed relative to the ORIGINAL cwd is resolved a second time against "$d" and matches nothing —
# the check then reports "not ignored" for a file that is ignored. Caught live against T5's fixture;
# the fix passes a basename. This assertion keeps both invocation styles honest.
# ==================================================================================================
R10=$(mk_repo "$GLOB")
printf '[]' >"$R10/.claude/.triage-fix-last-abs.json"
( cd "$R10" && printf '[]' | bash "$TS" commit "$R10/.claude/.triage-fix-last-abs.json" >/dev/null 2>&1 )
T10_N=$(gi_lines "$R10")
if [ "${T10_N:-0}" -eq 1 ]; then
  ok "T10: an absolute state-file path still resolves against the repo, so an existing rule is seen"
else
  bad "T10: absolute-path invocation appended beside an existing rule: $(tr '\n' '|' <"$R10/.gitignore")"
fi

# T10b — a RELATIVE state-file path, which is what actually exercises the `git -C "$d"` fix. An
# absolute path is not re-resolved, so T5-T10 above pass with or without the basename — the plant
# proved it: reverting `$(basename "$SF")` to `$SF` fired nothing here until this assertion existed.
#
# RTF itself passes an ABSOLUTE path (`RTF_SF="<root>/.claude/…"`), so the basename is defensive
# rather than load-bearing today. Pinned anyway, because "defensive" and "untested" are the pair
# that lets a later simplification look free.
# THE SEED HAD TO BE CHOSEN, not picked. It must (a) differ from the script's own glob, or the
# literal-grep fallback suppresses the append and the check-ignore branch is never exercised, and
# (b) NOT cover the doubled path `.claude/.claude/…` that the bug produces, or check-ignore
# answers "ignored" for the wrong reason and the assertion passes anyway. The first draft used the
# glob itself (fails (a)); the second used `.claude/` (fails (b)). Both passed and caught nothing
# when the basename was reverted. An assertion that cannot be made to fail is pinning nothing.
R10B=$(mk_repo '.claude/.triage-fix-last*.json')
printf '[]' >"$R10B/.claude/.triage-fix-last-rel.json"
( cd "$R10B" && printf '[]' | bash "$TS" commit ".claude/.triage-fix-last-rel.json" >/dev/null 2>&1 )
T10B_N=$(gi_lines "$R10B")
if [ "${T10B_N:-0}" -eq 1 ]; then
  ok "T10b: a RELATIVE state-file path is still resolved against the repo, so an existing rule is seen"
else
  bad "T10b: a relative path was re-resolved against the file's own directory and matched nothing, so an existing rule was missed: $(tr '\n' '|' <"$R10B/.gitignore")"
fi

# ==================================================================================================
# T11. No git repo at all — unchanged contract: touch nothing, exit 0.
# ==================================================================================================
NR="$TMP/nogit"; mkdir -p "$NR/.claude"
printf '[]' >"$NR/.claude/.triage-fix-last-x.json"
( cd "$NR" && GIT_CEILING_DIRECTORIES="$TMP" printf '[]' | GIT_CEILING_DIRECTORIES="$TMP" bash "$TS" commit "$NR/.claude/.triage-fix-last-x.json" >/dev/null 2>&1 )
T11_RC=$?
if [ "$T11_RC" -eq 0 ] && [ ! -f "$NR/.gitignore" ]; then
  ok "T11: outside a git tree nothing is written and the exit code stays 0"
else
  bad "T11: outside a git tree the script wrote a .gitignore or exited $T11_RC"
fi

# ==================================================================================================
# T12. This repository's own .gitignore carries no dead per-branch entry. A live check on the real
# file, not a fixture — the accumulation this issue is about happened here.
# ==================================================================================================
T12_DEAD=$(grep -c 'triage-fix-last-[a-z]' "$REPO/.gitignore" 2>/dev/null || true)
[ -n "${T12_DEAD:-}" ] || T12_DEAD=0
if [ "$T12_DEAD" -eq 0 ]; then
  ok "T12: this repository's .gitignore holds no per-branch triage-fix-last entry"
else
  bad "T12: $T12_DEAD dead per-branch entr(ies) remain in $REPO/.gitignore — sweep them"
fi

# ==================================================================================================
# T13. Registration in both CI registries (rule 2).
# ==================================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
if grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1 | grep -qE '[[:space:]]triage-state-gitignore[[:space:];]'; then
  ok "T13: docs-ci.yml's explicit shell-tests list runs triage-state-gitignore"
else
  bad "T13: triage-state-gitignore is not in docs-ci.yml's explicit harness list — a new test needs BOTH registries"
fi
CI_YML="$REPO/.github/workflows/ci.yml"
if [ -f "$CI_YML" ] && grep -qE 'tests/\*\.test\.sh|scripts/tests' "$CI_YML"; then
  ok "T14: ci.yml discovers *.test.sh via a glob (automatic registration)"
else
  bad "T14: ci.yml does not glob staging/plugin/scripts/tests/*.test.sh"
fi

# Z1 — assertion-count floor (ADR-0083 §D3).
Z1_TOTAL=$((PASS + FAIL))
if [ "$Z1_TOTAL" -ge 15 ]; then
  ok "Z1: assertion-count floor met ($Z1_TOTAL executed)"
else
  bad "Z1: only $Z1_TOTAL assertions executed — expected >= 15; assertions have gone missing, not passed"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
