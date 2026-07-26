#!/bin/bash
# interface-immutability.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash interface-immutability.test.sh
#
# Covers issue #107 / ADR-0053: an optional `.claude/protected-interfaces` declaration file plus
# `interface-check.sh`, a CHECKER (not a reporter) that BLOCKS — exit 0 clean, 2 bad invocation,
# 3 one or more protected interfaces broken. The first blocking gate in this family (ADR-0053 §D2):
# do not soften any assertion below into a reporter-shaped one to match its advisory neighbours.
#
# ASSERTION LABELS ARE I-PREFIXED (IA1, ID3, IH2, ...) to stay distinguishable from every other
# harness printing into the same CI shell-tests job (B-, R-, H-, W-, ...).
#
# THE FIXTURES HERE CONTAIN NO KEY-SHAPED LITERAL and no fixture path contains "secret",
# "credential", ".env", ".pem", or ".key" — secret-dep-gate.test.sh section D scans this
# repository's tracked files as its false-positive corpus.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
TAB=$(printf '\t')
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

IC="$SCRIPTS/interface-check.sh"

# ==================================================================================================
# I0. The anchor every I assertion below depends on.
# ==================================================================================================
if [ -f "$IC" ] && [ -r "$IC" ]; then
  ok "I0: interface-check.sh exists and is readable at the expected path"
else
  bad "I0: $IC not found or unreadable — every I assertion below is meaningless"
fi

# --- fixture helper: a throwaway git repo under $TMP/repo_<name>. Prints the repo path. -----------
new_repo() {
  _name="$1"
  _repo="$TMP/repo_$_name"
  rm -rf "$_repo"; mkdir -p "$_repo"
  ( cd "$_repo" \
      && git init -q \
      && git config user.email t@t.com \
      && git config user.name t \
      && git config commit.gpgsign false )
  printf '%s' "$_repo"
}

run_ic() { OUT=$(bash "$IC" "$@" 2>"$TMP/err" <"$TMP/diff_in"); RC=$?; ERR=$(cat "$TMP/err" 2>/dev/null); }

# ==================================================================================================
# IA. A removed protected signature is detected and the script exits 3.
# ==================================================================================================
R=$(new_repo ia)
mkdir -p "$R/src"
printf 'def foo(a, b):\n    return a + b\n\ndef bar(x):\n    return x\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf 'def foo(a, b):\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
printf 'def bar(x):\n    return x\n' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 3 ]; then
  ok "IA1: a fully deleted protected function exits 3"
else
  bad "IA1: expected exit 3 on a deleted protected function — got rc=$RC out=[$OUT] err=[$ERR]"
fi
if printf '%s\n' "$OUT" | grep -qE "^PROTECTED${TAB}def foo\(a, b\):${TAB}src/api\.py:1${TAB}(removed|changed)$"; then
  ok "IA2: the PROTECTED line names the entry, file:line, and a removed|changed tag"
else
  bad "IA2: PROTECTED line shape not found — got out=[$OUT]"
fi

# Companion, same fixture family: an ADDED function is never reported (accrete, don't destroy).
R=$(new_repo ia3)
mkdir -p "$R/src"
printf 'def foo(a, b):\n    return a + b\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf 'def foo(a, b):\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
printf 'def foo(a, b):\n    return a + b\n\ndef baz(c):\n    return c\n' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "IA3: adding a new, unprotected function alongside an untouched protected one is clean (accrete, don't destroy)"
else
  bad "IA3: expected exit 0 / empty stdout on an addition-only diff — got rc=$RC out=[$OUT]"
fi

# ==================================================================================================
# IB. A signature-changed protected entry is detected (not just a full deletion).
# ==================================================================================================
R=$(new_repo ib)
mkdir -p "$R/src"; printf 'def foo(a, b):\n    return a + b\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf 'def foo(a, b):\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
printf 'def foo(a, b, c):\n    return a + b + c\n' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -qE "^PROTECTED${TAB}def foo\(a, b\):${TAB}src/api\.py:1${TAB}changed$"; then
  ok "IB1: an added parameter (function still present, signature text changed) exits 3, tagged changed"
else
  bad "IB1: expected exit 3 / tag=changed on a signature edit — got rc=$RC out=[$OUT]"
fi

# Moved-but-identical signature is NOT reported when the entry is a signature (path-independent) —
# the SPEC's own edge case, contrasted with ID's path-glob case below.
R=$(new_repo ib2)
mkdir -p "$R/src"; printf 'def foo(a, b):\n    return a + b\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf 'def foo(a, b):\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
( cd "$R" && git mv src/api.py src/util.py )
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "IB2: a signature entry moved verbatim to a different file is NOT reported (accrete/relocate, not destroy)"
else
  bad "IB2: expected exit 0 on a verbatim file move — got rc=$RC out=[$OUT]"
fi

# ==================================================================================================
# IC. Absent .claude/protected-interfaces is fully inert: exit 0, no stdout, no stderr. The hard
# backward-compatibility gate (ADR-0053 §D1/§D2) — asserted against a fixture AND against this repo.
# ==================================================================================================
R=$(new_repo ic)
mkdir -p "$R/src"; printf 'def foo(a, b):\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
printf 'def foo(a, b, c):\n' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  ok "IC1: no .claude/protected-interfaces in a fixture repo -> exit 0, no stdout, no stderr"
else
  bad "IC1: expected fully silent exit 0 — got rc=$RC out=[$OUT] err=[$ERR]"
fi

( cd "$REPO" && git diff --no-renames HEAD ) > "$TMP/diff_in" 2>/dev/null
run_ic --root "$REPO"
if [ ! -f "$REPO/.claude/protected-interfaces" ]; then
  if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
    ok "IC2: this repository (which declares no protected interfaces) is also fully silent, exit 0"
  else
    bad "IC2: expected fully silent exit 0 against this repo's own working diff — got rc=$RC out=[$OUT] err=[$ERR]"
  fi
else
  bad "IC2: this repository unexpectedly has a .claude/protected-interfaces — IC2's premise (no such file) no longer holds"
fi

# ==================================================================================================
# ID. Comments and blank lines are ignored; path globs and exact signatures both work.
# ==================================================================================================
R=$(new_repo id1)
mkdir -p "$R/src"; printf 'def foo(a, b):\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"
printf '# a whole-line comment, ignored\n\n   \ndef foo(a, b):\n# trailing comment line, also ignored\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
printf 'def bar(z):\n' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 3 ]; then
  ok "ID1: comments and blank lines around a real entry do not prevent detection"
else
  bad "ID1: expected exit 3 with comments/blanks present — got rc=$RC out=[$OUT]"
fi

# A comment-only / blank-only declaration file behaves as absent (SPEC edge case) — same silence
# contract as IC.
R=$(new_repo id2)
mkdir -p "$R/src"; printf 'def foo(a, b):\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf '# nothing here\n\n\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
printf 'def bar(z):\n' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; then
  ok "ID2: a comment-only/blank-only declaration file is fully silent, same as absent"
else
  bad "ID2: expected fully silent exit 0 for a comment-only file — got rc=$RC out=[$OUT] err=[$ERR]"
fi

# A path-glob entry protects declaration-shaped lines in any matching file — no exemption for a
# reappearance elsewhere (unlike ID... wait IB2's signature case): moving OUT of a glob-protected
# file is still a violation, because a glob entry is path-scoped.
R=$(new_repo id3)
mkdir -p "$R/src" "$R/other"
printf 'def foo(a, b):\n    return a + b\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf 'src/*.py\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
( cd "$R" && git mv src/api.py other/api.py )
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 3 ] && printf '%s\n' "$OUT" | grep -qE "^PROTECTED${TAB}src/\*\.py${TAB}src/api\.py:1${TAB}"; then
  ok "ID3: a path-glob entry fires even when the declaration moved verbatim to a non-matching file — path-scoped, not text-scoped"
else
  bad "ID3: expected exit 3 naming the glob entry — got rc=$RC out=[$OUT]"
fi

# Glob entries ignore non-declaration-shaped removed lines (body edits are not interface changes).
R=$(new_repo id4)
mkdir -p "$R/src"; printf 'def foo(a, b):\n    x = 1\n    return a + b + x\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf 'src/*.py\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
printf 'def foo(a, b):\n    return a + b\n' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "ID4: a glob entry does not fire on a removed non-declaration body line (only declaration-shaped lines are protected)"
else
  bad "ID4: expected exit 0 on a body-only edit under a glob entry — got rc=$RC out=[$OUT]"
fi

# ==================================================================================================
# IE. Exit-code contract — 0 clean, 3 broken, 2 bad invocation — pinned explicitly so nobody
# converts this into a reporter (ADR-0053 §D2/§D3, the plan's risk flag 1).
# ==================================================================================================
R=$(new_repo ie1)
mkdir -p "$R/src"; printf 'def foo(a, b):\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf 'def foo(a, b):\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
printf 'def foo(a, b):\n    return a + b\n' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "IE1: a clean run (declaration present, nothing broken) exits 0 with EMPTY stdout — never a CLEAN sentinel, this is a checker not a reporter"
else
  bad "IE1: expected exit 0 / empty stdout on a clean run — got rc=$RC out=[$OUT]"
fi

printf '' > "$TMP/diff_in"
OUT=$(bash "$IC" 2>"$TMP/err" <"$TMP/diff_in"); RC=$?
if [ "$RC" -eq 2 ]; then
  ok "IE2: missing --root is a bad invocation, exit 2 (not 0 — this checker does not fail-open like the reporters)"
else
  bad "IE2: expected exit 2 for a missing --root — got rc=$RC"
fi

OUT=$(bash "$IC" --root "$TMP/does-not-exist-$$" 2>"$TMP/err" <"$TMP/diff_in"); RC=$?
if [ "$RC" -eq 2 ]; then
  ok "IE3: a nonexistent --root directory is a bad invocation, exit 2"
else
  bad "IE3: expected exit 2 for a nonexistent --root — got rc=$RC"
fi

R=$(new_repo ie4)
mkdir -p "$R/src"; printf 'def foo(a, b):\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf 'def foo(a, b):\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
printf '' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 3 ]; then
  ok "IE4: exit 3 reproduced once more (paired with IE1/IE2/IE3) so the three-way contract 0/2/3 is visible as one block"
else
  bad "IE4: expected exit 3 — got rc=$RC"
fi

# ==================================================================================================
# IF. The §D4 known limits are EXPECTED behaviour, not bugs — pinned so closing either forces the
# ADR paragraph to move with the code (the ADR-0045 section-E pattern).
# ==================================================================================================
R=$(new_repo if1)
mkdir -p "$R/src"
printf 'def foo(a,\n        b=1):\n    return a + b\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf 'def foo(a,\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
printf 'def foo(a,\n        b=2):\n    return a + b\n' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then
  ok "IF1: KNOWN MISS (expected) — a default-argument edit on a continuation line is invisible when the protected entry is only the signature's first line (ADR-0053 §D4)"
else
  bad "IF1: expected the documented miss (exit 0) — got rc=$RC out=[$OUT] — if this now fires, §D4's MISS paragraph in interface-check.sh must move with this change"
fi

R=$(new_repo if2)
mkdir -p "$R/src"; printf 'def foo(a, b):\n    return a+b\n' > "$R/src/api.py"
( cd "$R" && git add -A && git commit -q -m baseline )
mkdir -p "$R/.claude"; printf 'def foo(a, b):\n' > "$R/.claude/protected-interfaces"
( cd "$R" && git add -A && git commit -q -m decl )
printf 'def foo(a,\n        b):\n    return a+b\n' > "$R/src/api.py"
( cd "$R" && git add -A && git diff --no-renames --cached HEAD ) > "$TMP/diff_in"
run_ic --root "$R"
if [ "$RC" -eq 3 ]; then
  ok "IF2: KNOWN OVER-FIRE (expected) — a pure reformat (single line wrapped to two, same semantics) still reports a broken interface (ADR-0053 §D4)"
else
  bad "IF2: expected the documented over-fire (exit 3) — got rc=$RC out=[$OUT] — if this no longer fires, §D4's OVER-FIRE paragraph in interface-check.sh must move with this change"
fi

# ==================================================================================================
# IG. The c2c Step 6 call site branches on the EXIT CODE and says so; the §D3 contract table is
# present naming all four scripts in this directory family.
# ==================================================================================================
C2C="$STAGING/plugin/skills/concept-to-code/SKILL.md"
if [ -f "$C2C" ]; then
  if grep -qF 'interface-check.sh' "$C2C"; then
    ok "IG1: concept-to-code/SKILL.md references interface-check.sh"
  else
    bad "IG1: concept-to-code/SKILL.md does not reference interface-check.sh — Task 4 wiring is missing"
  fi

  if grep -qF 'Step 6' "$C2C" && grep -B2 -A40 'interface-check.sh' "$C2C" | grep -qE '_rc|exit code'; then
    ok "IG2: the interface-check.sh call site is documented to branch on the exit code"
  else
    bad "IG2: no exit-code branching language found near the interface-check.sh call site"
  fi

  if grep -qF 'weakening-scan.sh' "$C2C" && grep -qF 'diff-budget-check.sh' "$C2C" \
     && grep -qF 'spec-coverage.sh' "$C2C" && grep -qF 'interface-check.sh' "$C2C"; then
    ok "IG3: all four directory-family scripts (weakening-scan, diff-budget-check, spec-coverage, interface-check) are named in concept-to-code/SKILL.md"
  else
    bad "IG3: not all four family scripts are named in concept-to-code/SKILL.md"
  fi

  if grep -qE '\| *reporter *\|' "$C2C" && grep -qE '\| *checker *\|' "$C2C" \
     && grep -qF 'interface-check.sh' "$C2C" && grep -qF 'grep stdout' "$C2C" \
     && grep -qF 'branch on exit code' "$C2C"; then
    ok "IG4: a contract table distinguishing reporter vs checker, with caller idiom per script, is present"
  else
    bad "IG4: the §D3 contract table (reporter/checker/caller-idiom per script) was not found in concept-to-code/SKILL.md"
  fi
else
  bad "IG0: concept-to-code/SKILL.md not found — every IG assertion above is meaningless"
fi

# ==================================================================================================
# IH. Registration in both CI registries, plus the PAIRS deployment entry (Task 6).
# ==================================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]interface-immutability[[:space:];]'; then
  ok "IH1: docs-ci.yml's shell-tests loop list runs interface-immutability"
else
  bad "IH1: interface-immutability is not in docs-ci.yml's explicit harness list — append it after diff-budget-scope"
fi

CI_YML="$REPO/.github/workflows/ci.yml"
if [ -f "$CI_YML" ] && grep -qE 'tests/\*\.test\.sh|scripts/tests' "$CI_YML"; then
  ok "IH2: ci.yml discovers *.test.sh via a glob (automatic registration, no per-file edit needed)"
else
  bad "IH2: ci.yml does not appear to glob staging/plugin/scripts/tests/*.test.sh — check the workflow"
fi

SYNCSH="$STAGING/sync-to-claude.sh"
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" >"$TMP/pairs"
if grep -qxF 'plugin/scripts/interface-check.sh|hooks/interface-check.sh' "$TMP/pairs"; then
  ok "IH3: PAIRS deploys interface-check.sh to ~/.claude/hooks/, following secret-scan.sh's exact registration"
else
  bad "IH3: the interface-check.sh PAIRS entry is missing — it will never reach a deployed tree"
fi

if grep -q 'interface-immutability.test' "$TMP/pairs"; then
  bad "IH4: PAIRS gained an entry for this harness — test files do not deploy (diff-budget-scope.test.sh precedent)"
else
  ok "IH4: no PAIRS entry for interface-immutability.test.sh (harnesses do not deploy)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
