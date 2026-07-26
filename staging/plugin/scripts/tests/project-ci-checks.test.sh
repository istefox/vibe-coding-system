#!/bin/bash
# project-ci-checks.test.sh — offline, hermetic, no network, no $HOME dependency.
# Bash 3.2 clean. Run: bash project-ci-checks.test.sh
#
# Covers issue #108 / ADR-0054: a fail-closed `checks` job in the target-project CI template, and
# `vendor-checks.sh`, which copies the four existing check scripts into a target repo's
# `.claude/scripts/`.
#
# THE CONSTRAINT THIS FILE EXISTS TO GUARD (ADR-0054 §D1, plan risk flag 1): NO EXISTING CHECK
# SCRIPT MAY BE MODIFIED. secret-scan.sh, dependency-scan.sh, weakening-scan.sh and
# interface-check.sh stay byte-identical. The posture (fail-open at the hook, fail-closed in CI)
# belongs to the CALLER — this test file and the `checks` job it pins — never to the script.
# Section CE is the guard for that constraint specifically.
#
# ASSERTION LABELS ARE C-PREFIXED (CA1, CB3, CC2, ...) to stay distinguishable from every other
# harness printing into the same CI shell-tests job (B-, R-, H-, W-, I-, ...).
#
# NO FIXTURE PATH IN THIS FILE CONTAINS "secret", "credential", ".env", ".pem", or ".key" —
# secret-dep-gate.test.sh section D scans this repository's tracked files as its false-positive
# corpus, and protect-files.sh denies any path containing "secrets" (ADR-0046).
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

CITPL="$STAGING/project-templates/ci/ci.yml"
VENDOR="$SCRIPTS/vendor-checks.sh"
SECRET="$SCRIPTS/secret-scan.sh"
DEP="$SCRIPTS/dependency-scan.sh"
WEAK="$STAGING/plugin/skills/review-triage-fix/scripts/weakening-scan.sh"
IFACE="$SCRIPTS/interface-check.sh"

# ==================================================================================================
# C0. Anchors every other section depends on.
# ==================================================================================================
if [ -f "$CITPL" ] && [ -r "$CITPL" ]; then
  ok "C0a: $CITPL exists and is readable"
else
  bad "C0a: $CITPL not found or unreadable — every CA/CB/CC/CF assertion below is meaningless"
fi
for f in "$SECRET" "$DEP" "$WEAK" "$IFACE"; do
  if [ -f "$f" ] && [ -r "$f" ]; then
    ok "C0b: $(basename "$f") exists and is readable at its expected pre-existing path"
  else
    bad "C0b: $f not found or unreadable — this feature must not relocate any of the four scripts"
  fi
done

# --- helper: extract a top-level (2-space-indented) job block from ci.yml, from its "  <name>:"
# line up to (not including) the next top-level job key. Mirrors the Step-1-extraction idiom
# secret-dep-gate.test.sh already uses for commit/SKILL.md. -----------------------------------
job_block() { # job_block <job-key> -> prints to stdout
  awk -v key="  $1:" '
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      if ($0 == key) { f=1; print; next } else { f=0 }
    }
    f { print }
  ' "$CITPL"
}

CHECKSBLOCK="$TMP/checks_block.yml"
job_block checks > "$CHECKSBLOCK"
CIBLOCK="$TMP/ci_block.yml"
job_block ci > "$CIBLOCK"

# step_block <label-substring> <file> -> prints from the matching "- name: ..." line to the next
# "      - name:" line (6-space step indent) or EOF.
step_block() {
  awk -v pat="$1" '
    /^      - name:/ {
      if (index($0, pat) > 0) { f=1; print; next } else { f=0 }
    }
    f { print }
  ' "$2"
}

# ==================================================================================================
# CA. The `checks` job exists, is separate from `ci`, and each gate step is present (§D2).
# ==================================================================================================
if [ -s "$CHECKSBLOCK" ]; then
  ok "CA1: a top-level 'checks:' job key exists in the CI template"
else
  bad "CA1: no top-level 'checks:' job key found — every CA/CB/CC assertion below is meaningless"
fi

if grep -qE '^    name: checks$' "$CHECKSBLOCK"; then
  ok "CA2: the checks job declares 'name: checks'"
else
  bad "CA2: 'name: checks' not found inside the checks job block"
fi

if [ -s "$CIBLOCK" ] && grep -qE '^    name: ci$' "$CIBLOCK"; then
  ok "CA3a: the 'ci' job still exists as its own separate top-level job"
else
  bad "CA3a: the 'ci' job block is missing or malformed — checks must be ADDED, not a replacement"
fi
if ! grep -qF 'name: checks' "$CIBLOCK"; then
  ok "CA3b: the checks job is not nested inside the ci job block (true separation, §D2)"
else
  bad "CA3b: 'name: checks' appears inside the ci job block — checks must be a sibling job, not nested"
fi

CA4OK=1
grep -qF 'Secret scan' "$CHECKSBLOCK"     || CA4OK=0
grep -qF 'Dependency scan' "$CHECKSBLOCK" || CA4OK=0
grep -qF 'Weakening scan' "$CHECKSBLOCK"  || CA4OK=0
grep -qF 'Interface immutability' "$CHECKSBLOCK" || CA4OK=0
if [ "$CA4OK" -eq 1 ]; then
  ok "CA4: all four gate step names (secret/dependency/weakening/interface) are present in the checks job"
else
  bad "CA4: at least one of the four gate step names is missing from the checks job"
fi

CA5OK=1
grep -qF '.claude/scripts/secret-scan.sh'     "$CHECKSBLOCK" || CA5OK=0
grep -qF '.claude/scripts/dependency-scan.sh' "$CHECKSBLOCK" || CA5OK=0
grep -qF '.claude/scripts/weakening-scan.sh'  "$CHECKSBLOCK" || CA5OK=0
grep -qF '.claude/scripts/interface-check.sh' "$CHECKSBLOCK" || CA5OK=0
if [ "$CA5OK" -eq 1 ]; then
  ok "CA5: all four scripts are invoked from .claude/scripts/ inside the checks job"
else
  bad "CA5: at least one .claude/scripts/<name> invocation is missing from the checks job"
fi

# ==================================================================================================
# CB. The fail-closed / print-only split is exactly as specified (§D5): SECRET, WEAKENED and
# interface-check.sh exit 3 fail the build; SUSPECT and dependency notes print only.
# ==================================================================================================
SECSTEP="$TMP/sec_step.txt"; step_block "Secret scan" "$CHECKSBLOCK" > "$SECSTEP"
DEPSTEP="$TMP/dep_step.txt"; step_block "Dependency scan" "$CHECKSBLOCK" > "$DEPSTEP"
WEAKSTEP="$TMP/weak_step.txt"; step_block "Weakening scan" "$CHECKSBLOCK" > "$WEAKSTEP"
IFACESTEP="$TMP/iface_step.txt"; step_block "Interface immutability" "$CHECKSBLOCK" > "$IFACESTEP"

if [ -s "$SECSTEP" ] && grep -qF "grep -q '^SECRET'" "$SECSTEP" && grep -qF 'exit 1' "$SECSTEP"; then
  ok "CB1: the secret-scan step greps for ^SECRET and exits 1 on a match (fails the build)"
else
  bad "CB1: the secret-scan step does not branch on ^SECRET into exit 1 — got:
$(cat "$SECSTEP" 2>/dev/null)"
fi

if [ -s "$WEAKSTEP" ]; then
  WEXIT1_N=$(grep -c 'exit 1' "$WEAKSTEP" 2>/dev/null || true)
  [ -z "$WEXIT1_N" ] && WEXIT1_N=0
  if grep -qF "grep -q '^WEAKENED'" "$WEAKSTEP" && [ "$WEXIT1_N" -ge 1 ]; then
    ok "CB2: the weakening-scan step greps for ^WEAKENED and exits 1 on a match (fails the build)"
  else
    bad "CB2: the weakening-scan step does not branch on ^WEAKENED into exit 1 — got:
$(cat "$WEAKSTEP" 2>/dev/null)"
  fi
  if [ "$WEXIT1_N" -eq 1 ]; then
    ok "CB3: the weakening-scan step has exactly one build-failing exit (WEAKENED only, never SUSPECT)"
  else
    bad "CB3: the weakening-scan step has $WEXIT1_N 'exit 1' occurrences — SUSPECT must never fail the build (§D5/§A4)"
  fi
else
  bad "CB2/CB3: weakening-scan step not found — cannot check the WEAKENED/SUSPECT split"
fi

if [ -s "$DEPSTEP" ]; then
  if ! grep -qF 'exit 1' "$DEPSTEP"; then
    ok "CB4: the dependency-scan step contains no build-failing exit — NEWDEP notes print only (§D5)"
  else
    bad "CB4: the dependency-scan step contains 'exit 1' — dependency notes must never fail the build"
  fi
else
  bad "CB4: dependency-scan step not found"
fi

if [ -s "$IFACESTEP" ]; then
  if grep -qF '.claude/scripts/interface-check.sh --root .' "$IFACESTEP" \
     && ! grep -qE '\.claude/scripts/interface-check\.sh --root \. *(\|\||&&) *true' "$IFACESTEP"; then
    ok "CB5: interface-check.sh's exit code is left to propagate (checker contract, not grepped like a reporter)"
  else
    bad "CB5: the interface-check.sh call is missing or its exit code is being suppressed — got:
$(cat "$IFACESTEP" 2>/dev/null)"
  fi
else
  bad "CB5: interface immutability step not found"
fi

# ==================================================================================================
# CC. Every gate step is [ -x ... ]-guarded and prints a SKIP NOTICE naming vendor-checks.sh —
# the notice TEXT is asserted, not just the guard (§D4, plan risk flag 2).
# ==================================================================================================
cc_check() { # cc_check <label> <step-file> <script-basename>
  _lbl="$1"; _f="$2"; _name="$3"
  if [ ! -s "$_f" ]; then bad "$_lbl: step not found"; return; fi
  if grep -qF "[ -x .claude/scripts/$_name ]" "$_f" \
     && grep -qF "$_name" "$_f" \
     && grep -qF 'vendor-checks.sh' "$_f" \
     && grep -qi 'notice' "$_f"; then
    ok "$_lbl: $_name is [ -x ... ]-guarded and the skip notice names vendor-checks.sh as the remedy"
  else
    bad "$_lbl: $_name's guard or skip-notice text (naming vendor-checks.sh) is missing — got:
$(cat "$_f" 2>/dev/null)"
  fi
}
cc_check "CC1" "$SECSTEP" "secret-scan.sh"
cc_check "CC2" "$DEPSTEP" "dependency-scan.sh"
cc_check "CC3" "$WEAKSTEP" "weakening-scan.sh"
cc_check "CC4" "$IFACESTEP" "interface-check.sh"

# ==================================================================================================
# CD. vendor-checks.sh copies the expected script set and is idempotent (Task 4).
# ==================================================================================================
if [ -f "$VENDOR" ] && [ -r "$VENDOR" ]; then
  ok "CD0: vendor-checks.sh exists and is readable at the expected path"
else
  bad "CD0: $VENDOR not found or unreadable — every CD assertion below is meaningless"
fi

TARGET="$TMP/target_repo"
mkdir -p "$TARGET"

# CD1 — dry run (no --apply): reports NEW for all four scripts plus the manifest, writes nothing.
OUT=$(bash "$VENDOR" "$TARGET" 2>"$TMP/vderr"); RC=$?
CD1OK=1
[ "$RC" -eq 0 ] || CD1OK=0
printf '%s\n' "$OUT" | grep -qF 'NEW' || CD1OK=0
printf '%s\n' "$OUT" | grep -qF 'secret-scan.sh' || CD1OK=0
printf '%s\n' "$OUT" | grep -qF 'dependency-scan.sh' || CD1OK=0
printf '%s\n' "$OUT" | grep -qF 'weakening-scan.sh' || CD1OK=0
printf '%s\n' "$OUT" | grep -qF 'interface-check.sh' || CD1OK=0
[ -f "$TARGET/.claude/scripts/secret-scan.sh" ] && CD1OK=0
if [ "$CD1OK" -eq 1 ]; then
  ok "CD1: a dry run (no --apply) reports all four scripts as NEW and writes nothing"
else
  bad "CD1: dry-run output/behaviour unexpected — rc=$RC out=[$OUT]"
fi

# CD2 — --apply copies all four scripts byte-identical, plus a VENDORED manifest.
OUT=$(bash "$VENDOR" "$TARGET" --apply 2>"$TMP/vderr"); RC=$?
CD2OK=1
[ "$RC" -eq 0 ] || CD2OK=0
for pair in "secret-scan.sh:$SECRET" "dependency-scan.sh:$DEP" "weakening-scan.sh:$WEAK" "interface-check.sh:$IFACE"; do
  dname="${pair%%:*}"; sname="${pair#*:}"
  d="$TARGET/.claude/scripts/$dname"
  [ -f "$d" ] || CD2OK=0
  diff -q "$sname" "$d" >/dev/null 2>&1 || CD2OK=0
  [ -x "$d" ] || CD2OK=0
done
[ -f "$TARGET/.claude/scripts/VENDORED" ] || CD2OK=0
if [ "$CD2OK" -eq 1 ]; then
  ok "CD2: --apply copies all four scripts byte-identical and executable, plus a VENDORED manifest"
else
  bad "CD2: --apply did not produce the expected byte-identical, executable copies — rc=$RC out=[$OUT]"
fi

if grep -qF 'secret-scan.sh' "$TARGET/.claude/scripts/VENDORED" 2>/dev/null \
   && grep -qF 'dependency-scan.sh' "$TARGET/.claude/scripts/VENDORED" 2>/dev/null \
   && grep -qF 'weakening-scan.sh' "$TARGET/.claude/scripts/VENDORED" 2>/dev/null \
   && grep -qF 'interface-check.sh' "$TARGET/.claude/scripts/VENDORED" 2>/dev/null \
   && grep -qiE 'revision|sha|commit' "$TARGET/.claude/scripts/VENDORED" 2>/dev/null; then
  ok "CD3: the VENDORED manifest lists all four scripts and records a source revision"
else
  bad "CD3: VENDORED manifest missing a script name or a source-revision marker — got:
$(cat "$TARGET/.claude/scripts/VENDORED" 2>/dev/null)"
fi

# CD4 — idempotent: a second --apply run against an unchanged source and target reports nothing
# and touches nothing (silent, since no dry-run trailer prints with --apply).
BEFORE_SHA=$(cd "$TARGET/.claude/scripts" && shasum secret-scan.sh dependency-scan.sh weakening-scan.sh interface-check.sh VENDORED 2>/dev/null)
OUT2=$(bash "$VENDOR" "$TARGET" --apply 2>"$TMP/vderr2"); RC2=$?
AFTER_SHA=$(cd "$TARGET/.claude/scripts" && shasum secret-scan.sh dependency-scan.sh weakening-scan.sh interface-check.sh VENDORED 2>/dev/null)
if [ "$RC2" -eq 0 ] && [ "$BEFORE_SHA" = "$AFTER_SHA" ] && ! printf '%s' "$OUT2" | grep -qE 'NEW|CHANGED'; then
  ok "CD4: a second --apply run against an unchanged source is idempotent — no NEW/CHANGED, no content drift"
else
  bad "CD4: second run was not idempotent — rc=$RC2 out=[$OUT2]"
fi

# CD5 — the house rule: an existing, DIFFERENT target file shows a diff before being overwritten,
# both without --apply (diff shown, file untouched) and with --apply (diff shown, then written).
printf '#!/bin/bash\necho "a locally hand-edited copy"\n' > "$TARGET/.claude/scripts/secret-scan.sh"
DRYOUT=$(bash "$VENDOR" "$TARGET" 2>"$TMP/vderr3")
if printf '%s\n' "$DRYOUT" | grep -qF 'CHANGED' \
   && printf '%s\n' "$DRYOUT" | grep -qF 'secret-scan.sh' \
   && printf '%s\n' "$DRYOUT" | grep -qF 'hand-edited' \
   && grep -qF 'hand-edited' "$TARGET/.claude/scripts/secret-scan.sh"; then
  ok "CD5: a dry run against a modified target shows the diff (naming the file) and leaves it untouched"
else
  bad "CD5: dry-run diff-before-overwrite behaviour missing — got:
$DRYOUT"
fi
APPLYOUT=$(bash "$VENDOR" "$TARGET" --apply 2>"$TMP/vderr4")
if printf '%s\n' "$APPLYOUT" | grep -qF 'CHANGED' \
   && printf '%s\n' "$APPLYOUT" | grep -qF 'hand-edited' \
   && diff -q "$SECRET" "$TARGET/.claude/scripts/secret-scan.sh" >/dev/null 2>&1; then
  ok "CD5b: --apply shows the same diff first, then overwrites the modified target with the source"
else
  bad "CD5b: --apply did not show the diff before overwriting, or did not overwrite — got:
$APPLYOUT"
fi

# CD6 — bad invocation: missing target argument.
OUT=$(bash "$VENDOR" 2>"$TMP/vderr5"); RC=$?
if [ "$RC" -eq 2 ] && [ -s "$TMP/vderr5" ]; then
  ok "CD6: a missing target-repo-root argument exits 2 with usage on stderr"
else
  bad "CD6: expected exit 2 + stderr for a missing argument — got rc=$RC"
fi

# CD7 — bad invocation: nonexistent target directory.
OUT=$(bash "$VENDOR" "$TMP/does-not-exist-$$" 2>"$TMP/vderr6"); RC=$?
if [ "$RC" -eq 2 ]; then
  ok "CD7: a nonexistent target-repo-root exits 2"
else
  bad "CD7: expected exit 2 for a nonexistent target — got rc=$RC"
fi

# ==================================================================================================
# CE. NO EXISTING CHECK SCRIPT WAS MODIFIED — the guard for the plan's headline constraint.
# ALWAYS-PASS FORWARD GUARD (true before and after every task in this feature): this is a
# regression pin, never fix evidence. If this goes RED, the fix is to revert the script, never to
# relax this assertion.
# ==================================================================================================
for pair in "secret-scan.sh:staging/plugin/scripts/secret-scan.sh" \
            "dependency-scan.sh:staging/plugin/scripts/dependency-scan.sh" \
            "weakening-scan.sh:staging/plugin/skills/review-triage-fix/scripts/weakening-scan.sh" \
            "interface-check.sh:staging/plugin/scripts/interface-check.sh"; do
  dname="${pair%%:*}"; relpath="${pair#*:}"
  if git -C "$REPO" diff --quiet -- "$relpath" 2>/dev/null; then
    ok "CE-$dname: no uncommitted change against the tracked copy of $dname (forward guard)"
  else
    bad "CE-$dname: $dname has uncommitted changes — this feature must NEVER modify existing check scripts"
  fi
done

# Minimal contract smoke, one call per script — still exits 0 / keeps its documented shape.
: >"$TMP/empty_list"
SOUT=$(bash "$SECRET" --files "$TMP/empty_list" 2>/dev/null); SRC=$?
[ "$SRC" -eq 0 ] && [ -z "$SOUT" ] && ok "CE-secret-scan.sh: contract intact (empty list -> exit 0, no findings)" \
  || bad "CE-secret-scan.sh: contract changed — rc=$SRC out=[$SOUT]"

: >"$TMP/empty_diff"
DOUT=$(bash "$DEP" --diff <"$TMP/empty_diff" 2>/dev/null); DRC=$?
[ "$DRC" -eq 0 ] && [ -z "$DOUT" ] && ok "CE-dependency-scan.sh: contract intact (empty diff -> exit 0, no findings)" \
  || bad "CE-dependency-scan.sh: contract changed — rc=$DRC out=[$DOUT]"

WOUT=$(bash "$WEAK" <"$TMP/empty_diff" 2>/dev/null); WRC=$?
[ "$WRC" -eq 0 ] && [ "$WOUT" = "CLEAN" ] && ok "CE-weakening-scan.sh: contract intact (empty diff -> exit 0, CLEAN)" \
  || bad "CE-weakening-scan.sh: contract changed — rc=$WRC out=[$WOUT]"

IROOT="$TMP/iface_repo"
mkdir -p "$IROOT"
( cd "$IROOT" && git init -q && git config user.email t@t.com && git config user.name t && git config commit.gpgsign false )
printf 'placeholder\n' > "$IROOT/f.txt"
( cd "$IROOT" && git add -A && git commit -q -m baseline )
IOUT=$(bash "$IFACE" --root "$IROOT" 2>/dev/null <"$TMP/empty_diff"); IRC=$?
[ "$IRC" -eq 0 ] && [ -z "$IOUT" ] && ok "CE-interface-check.sh: contract intact (no declaration -> exit 0, silent)" \
  || bad "CE-interface-check.sh: contract changed — rc=$IRC out=[$IOUT]"

# ==================================================================================================
# CF. The reporter trap is restated at each reporter call site, and the checker branches on exit
# code (§D6) — the fourth restatement of this contract, per ADR-0053 §D3.
# ==================================================================================================
CF1=1
grep -qF '`[ -n "$out" ]`' "$CITPL" || CF1=0
grep -qF 'grep -c ... || echo 0' "$CITPL" || CF1=0
if [ "$CF1" -eq 1 ]; then
  ok "CF1: the CI template restates the reporter trap (never [ -n \"\$out\" ], never grep -c ... || echo 0)"
else
  bad "CF1: the reporter-trap restatement is missing from $CITPL"
fi

if grep -qF 'CHECKER' "$CITPL" && grep -qi 'branches on its exit code' "$CITPL"; then
  ok "CF2: the CI template states that interface-check.sh is a CHECKER that branches on exit code"
else
  bad "CF2: the checker/branches-on-exit-code statement is missing from $CITPL"
fi

# ==================================================================================================
# CG. Registration in both CI registries, plus the PAIRS deployment entry.
# ==================================================================================================
DOCSCI="$REPO/.github/workflows/docs-ci.yml"
DOCSCI_LOOP=$(grep 'for t in ' "$DOCSCI" 2>/dev/null | head -1)
if printf '%s' "$DOCSCI_LOOP" | grep -qE '[[:space:]]project-ci-checks[[:space:];]'; then
  ok "CG1: docs-ci.yml's shell-tests loop list runs project-ci-checks"
else
  bad "CG1: project-ci-checks is not in docs-ci.yml's explicit harness list — append it after interface-immutability"
fi
REMAINDER=$(printf '%s' "$DOCSCI_LOOP" | sed 's/.*interface-immutability//')
if printf '%s' "$REMAINDER" | grep -qE '[[:space:]]project-ci-checks[[:space:];]'; then
  ok "CG1b: project-ci-checks is registered AFTER interface-immutability, as the DoD specifies"
else
  bad "CG1b: project-ci-checks is not positioned after interface-immutability in the loop list"
fi

CI_YML="$REPO/.github/workflows/ci.yml"
if [ -f "$CI_YML" ] && grep -qE 'tests/\*\.test\.sh|scripts/tests' "$CI_YML"; then
  ok "CG2: this repo's own ci.yml discovers *.test.sh via a glob (automatic registration, forward guard)"
else
  bad "CG2: ci.yml does not appear to glob staging/plugin/scripts/tests/*.test.sh — check the workflow"
fi

SYNCSH="$STAGING/sync-to-claude.sh"
awk '/^PAIRS="$/{f=1; next} /^"$/{f=0} f' "$SYNCSH" >"$TMP/pairs"
if grep -qxF 'plugin/scripts/vendor-checks.sh|hooks/vendor-checks.sh' "$TMP/pairs"; then
  ok "CG3: PAIRS deploys vendor-checks.sh to ~/.claude/hooks/, following the sibling scripts' registration"
else
  bad "CG3: the vendor-checks.sh PAIRS entry is missing — it will never reach a deployed tree"
fi

if grep -q 'project-ci-checks' "$TMP/pairs"; then
  bad "CG4: PAIRS gained an entry for this harness — test files do not deploy (established precedent)"
else
  ok "CG4: no PAIRS entry for project-ci-checks.test.sh (harnesses do not deploy)"
fi

echo "----"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
