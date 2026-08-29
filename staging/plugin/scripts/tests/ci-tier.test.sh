#!/bin/bash
# ci-tier.test.sh — offline, hermetic, no network. Bash 3.2 clean. Run: bash ci-tier.test.sh
#
# Covers VCS-051 / ADR-0180: ci-tier.sh's --classify and --resolve subcommands, the exit-3
# denominator guard (rule 4/7 — "did not run" must never read as "docs"), and the
# commit-step37-ci-tier-classify fence in commit/SKILL.md (rule 16: an instruction is not an
# enforcement — this section actually EXECUTES the fence, in an isolated sandbox, against the
# real ci-tier.sh).
#
# CTF1/SKF1 USE A LIVE PLANT TARGET, NEVER A HARDCODED ONE (plan requirement). The registry
# changes over time; re-deriving the first declared target on every run is what keeps this
# harness honest about "full tier is triggered by a REAL plant-registry match", not a frozen
# example that could silently stop being a target.
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)
STAGING=$(cd "$SCRIPTS/../.." && pwd)
REPO=$(cd "$STAGING/.." && pwd)
CT="$SCRIPTS/ci-tier.sh"
COMMITMD="$STAGING/plugin/skills/commit/SKILL.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# mklist <path>... -> prints a tmp changed-files-file path with one line per argument
mklist() {
  _l=$(mktemp "$TMP/list.XXXXXX"); : >"$_l"
  for _p in "$@"; do printf '%s\n' "$_p" >>"$_l"; done
  printf '%s' "$_l"
}

OUT=""; RC=0
run_classify() { OUT=$(bash "$CT" --classify "$1" 2>"$TMP/classify.err"); RC=$?; }
run_resolve()  { OUT=$(bash "$CT" --resolve "$1" "$2" 2>"$TMP/resolve.err"); RC=$?; }
tier_of() { printf '%s\n' "$1" | grep '^TIER: ' | head -1 | sed 's/^TIER: //'; }

# ==================================================================================================
# CT0. Derive one REAL, currently-declared plant target — the same resolution rule ci-tier.sh
# itself documents (staging-relative by default, a literal ../docs/ prefix reaches docs/).
# ==================================================================================================
FIRST_RAW=$(grep -rh '^# plant:' "$STAGING/plugin/scripts/tests" 2>/dev/null \
  | awk -F'|' '{ gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 != "") print $2 }' \
  | sort -u | head -1)
case "$FIRST_RAW" in
  ../docs/*) FIRST_REL="docs/${FIRST_RAW#../docs/}" ;;
  *)         FIRST_REL="staging/$FIRST_RAW" ;;
esac

if [ -n "$FIRST_RAW" ] && [ -f "$REPO/$FIRST_REL" ]; then
  ok "CT0: derived a live plant target ($FIRST_REL) — every CTF/SKF assertion below reads it"
else
  bad "CT0: could not derive a live, resolvable plant target — every CTF/SKF assertion below is meaningless"
fi

# ==================================================================================================
# CTF/CTS/CTD. --classify: full (a changed plant target), standard (a staging/ change with no
# plant-target match), docs (neither).
# ==================================================================================================
run_classify "$(mklist "$FIRST_REL")"
[ "$RC" -eq 0 ] && [ "$(tier_of "$OUT")" = "full" ] \
  && ok "CTF1: a changed file that IS a declared plant target classifies full" \
  || bad "CTF1: classifying '$FIRST_REL' gave rc=$RC out='$OUT', expected TIER: full"

printf '%s\n' "$OUT" | grep -qxF "PLANT-MATCH: $FIRST_REL" \
  && ok "CTF2: the full classification names the matching file via PLANT-MATCH" \
  || bad "CTF2: no 'PLANT-MATCH: $FIRST_REL' line in: $OUT"

run_classify "$(mklist "staging/plugin/scripts/ci-tier-not-a-real-file-standard-fixture.sh")"
[ "$RC" -eq 0 ] && [ "$(tier_of "$OUT")" = "standard" ] \
  && ok "CTS1: a staging/ change that is not a plant target classifies standard" \
  || bad "CTS1: classifying a staging/-only change gave rc=$RC out='$OUT', expected TIER: standard"
printf '%s\n' "$OUT" | grep -q '^PLANT-MATCH: ' \
  && bad "CTS2: standard classification must not report a PLANT-MATCH — got: $OUT" \
  || ok "CTS2: standard classification carries no PLANT-MATCH line"

run_classify "$(mklist "ci-tier-not-a-real-file-docs-fixture.md")"
[ "$RC" -eq 0 ] && [ "$(tier_of "$OUT")" = "docs" ] \
  && ok "CTD1: a change outside staging/.github/.claude and outside the plant registry classifies docs" \
  || bad "CTD1: classifying an unrelated top-level file gave rc=$RC out='$OUT', expected TIER: docs"

run_classify "$(mklist "ci-tier-not-a-real-file-docs-fixture.md" "$FIRST_REL" "staging/some/other/file.sh")"
[ "$RC" -eq 0 ] && [ "$(tier_of "$OUT")" = "full" ] \
  && ok "CTM1: a mixed changed-file set with one plant-target match still classifies full" \
  || bad "CTM1: classifying a mixed set gave rc=$RC out='$OUT', expected TIER: full"

# ==================================================================================================
# CT-DENOM. The exit-3 denominator guard (rule 4/7): callers MUST treat exit 3 as full, never
# silently as docs. Planted so the guard's actual enforcement is proven, not just its presence.
# ==================================================================================================
mkdir -p "$TMP/empty-registry"
CHF=$(mklist "$FIRST_REL")

# plant: CT-DENOM | plugin/scripts/ci-tier.sh | if [ ! -s "$RAW" ]; then | if false; then
OUT=$(CI_TIER_REGISTRY_DIR="$TMP/empty-registry" bash "$CT" --classify "$CHF" 2>"$TMP/denom.err")
RC=$?
[ "$RC" -eq 3 ] && grep -q 'DID-NOT-RUN' "$TMP/denom.err" \
  && ok "CT-DENOM: an empty derived plant-target set exits 3 with a DID-NOT-RUN reason, never a silent docs/standard/full guess" \
  || bad "CT-DENOM: empty registry gave rc=$RC stderr='$(cat "$TMP/denom.err")', expected exit 3 with DID-NOT-RUN"

CT_DENOM2_OUT=$(CI_TIER_REGISTRY_DIR="$TMP/does-not-exist-registry-dir" bash "$CT" --classify "$CHF" 2>"$TMP/denom2.err")
CT_DENOM2_RC=$?
[ "$CT_DENOM2_RC" -eq 3 ] && grep -q 'DID-NOT-RUN' "$TMP/denom2.err" \
  && ok "CT-DENOM2: an unreadable registry directory exits 3 with a DID-NOT-RUN reason" \
  || bad "CT-DENOM2: missing registry dir gave rc=$CT_DENOM2_RC stderr='$(cat "$TMP/denom2.err")', expected exit 3"

mkdir -p "$TMP/bad-registry"
printf '# plant: X | plugin/scripts/DOES-NOT-EXIST-ci-tier-fixture.sh | a | b\n' >"$TMP/bad-registry/fake.test.sh"
CT_DENOM3_OUT=$(CI_TIER_REGISTRY_DIR="$TMP/bad-registry" bash "$CT" --classify "$CHF" 2>"$TMP/denom3.err")
CT_DENOM3_RC=$?
[ "$CT_DENOM3_RC" -eq 3 ] && grep -q 'DID-NOT-RUN' "$TMP/denom3.err" \
  && ok "CT-DENOM3: a declared plant-target path that fails to resolve on disk exits 3 with a DID-NOT-RUN reason" \
  || bad "CT-DENOM3: an unresolved plant-target path gave rc=$CT_DENOM3_RC stderr='$(cat "$TMP/denom3.err")', expected exit 3"

# ==================================================================================================
# CT2-CT5. Bad invocation — exit 2, never 0 or 3.
# ==================================================================================================
bash "$CT" --classify >/dev/null 2>"$TMP/e2.err"; RC=$?
[ "$RC" -eq 2 ] && ok "CT2: --classify with no changed-files-file argument exits 2" \
  || bad "CT2: --classify with no argument gave rc=$RC, expected 2"

bash "$CT" --classify "$TMP/does-not-exist.txt" >/dev/null 2>"$TMP/e3.err"; RC=$?
[ "$RC" -eq 2 ] && ok "CT3: --classify with an unreadable changed-files-file exits 2" \
  || bad "CT3: --classify with an unreadable file gave rc=$RC, expected 2"

bash "$CT" --bogus foo >/dev/null 2>"$TMP/e4.err"; RC=$?
[ "$RC" -eq 2 ] && ok "CT4: an unrecognised flag exits 2" \
  || bad "CT4: --bogus gave rc=$RC, expected 2"

bash "$CT" >/dev/null 2>"$TMP/e5.err"; RC=$?
[ "$RC" -eq 2 ] && ok "CT5: no arguments at all exits 2" \
  || bad "CT5: no arguments gave rc=$RC, expected 2"

# ==================================================================================================
# CTR. --resolve: never below the computed floor (full > standard > docs); always exits 0 on a
# valid pair; exit 2 on a bad invocation or an unrecognised tier name.
# ==================================================================================================
run_resolve full docs
[ "$RC" -eq 0 ] && [ "$(tier_of "$OUT")" = "full" ] \
  && ok "CTR1: --resolve full docs keeps the stricter requested tier" \
  || bad "CTR1: --resolve full docs gave rc=$RC out='$OUT', expected TIER: full"

run_resolve docs full
[ "$RC" -eq 0 ] && [ "$(tier_of "$OUT")" = "full" ] \
  && ok "CTR2: --resolve docs full is floored up to the computed tier, never silently honours the cheaper request" \
  || bad "CTR2: --resolve docs full gave rc=$RC out='$OUT', expected TIER: full"
grep -q 'DOWNGRADED-BY-REQUEST: requested=docs computed=full' "$TMP/resolve.err" \
  && ok "CTR2b: the floor-up case notes DOWNGRADED-BY-REQUEST on stderr" \
  || bad "CTR2b: no DOWNGRADED-BY-REQUEST note — got stderr: $(cat "$TMP/resolve.err")"

run_resolve standard standard
[ "$RC" -eq 0 ] && [ "$(tier_of "$OUT")" = "standard" ] \
  && ok "CTR3: --resolve standard standard keeps standard with no downgrade note" \
  || bad "CTR3: --resolve standard standard gave rc=$RC out='$OUT', expected TIER: standard"
[ -s "$TMP/resolve.err" ] \
  && bad "CTR3b: an equal-strictness resolve must not print a DOWNGRADED-BY-REQUEST note — got: $(cat "$TMP/resolve.err")" \
  || ok "CTR3b: no downgrade note on an equal-strictness resolve"

bash "$CT" --resolve bogus full >/dev/null 2>"$TMP/er1.err"; RC=$?
[ "$RC" -eq 2 ] && ok "CTR4: --resolve with an unrecognised requested tier exits 2" \
  || bad "CTR4: --resolve bogus full gave rc=$RC, expected 2"

bash "$CT" --resolve full bogus >/dev/null 2>"$TMP/er2.err"; RC=$?
[ "$RC" -eq 2 ] && ok "CTR5: --resolve with an unrecognised computed tier exits 2" \
  || bad "CTR5: --resolve full bogus gave rc=$RC, expected 2"

bash "$CT" --resolve full >/dev/null 2>"$TMP/er3.err"; RC=$?
[ "$RC" -eq 2 ] && ok "CTR6: --resolve with a missing second argument exits 2" \
  || bad "CTR6: --resolve full (one arg) gave rc=$RC, expected 2"

# ==================================================================================================
# SKF. commit/SKILL.md's Step 3.7 fence — extracted and EXECUTED (rule 16: an instruction is not
# an enforcement). Same extraction idiom as recovery-preflight.test.sh's BR2/BR6. The pattern
# below matches the marker's full literal text, trailing ` -->` included: fence-contract-coverage
# .test.sh's F4 greps test files for the exact string `fence-contract: <id> -->` as one of the two
# accepted proofs that a declared contract is actually run, and that string must appear here.
SKF_FENCE=$(awk '/fence-contract: commit-step37-ci-tier-classify -->/{f=1;next} f&&/^```bash/{g=1;next} g&&/^```/{exit} g' "$COMMITMD")

if [ -z "$SKF_FENCE" ]; then
  bad "SKF0: the Step 3.7 fence extracted nothing — an empty extraction is a FAILURE, never a skip; every SKF assertion below is meaningless"
else
  _skdir=$(mktemp -d "${TMPDIR:-/tmp}/skf.XXXXXX")
  printf '%s\n' "$SKF_FENCE" >"$_skdir/fence.sh"
  bash -n "$_skdir/fence.sh" 2>/dev/null \
    && ok "SKF0: the Step 3.7 fence parses as bash (ADR-0083 F7)" \
    || bad "SKF0: the Step 3.7 fence does not parse"

  # _mksandbox <name> -> prints an isolated repo dir with one committed file so `git diff HEAD`
  # has a base to compare against.
  _mksandbox() {
    _d="$_skdir/$1"; mkdir -p "$_d"
    git -C "$_d" init -q -b main >/dev/null 2>&1
    git -C "$_d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init >/dev/null 2>&1
    printf '%s' "$_d"
  }
  # _run_step37 <sandbox-dir> <extra-env-assignments...> -> prints the fence's stdout
  _run_step37() {
    _d="$1"; shift
    ( cd "$_d"
      export CI_TIER_SH="$CT"
      for _e in "$@"; do export "$_e"; done
      bash "$_skdir/fence.sh" 2>/dev/null )
  }

  _r=$(_mksandbox full)
  mkdir -p "$_r/$(dirname "$FIRST_REL")"
  printf 'fixture\n' >"$_r/$FIRST_REL"
  git -C "$_r" add -- "$FIRST_REL" >/dev/null 2>&1
  _out=$(_run_step37 "$_r")
  printf '%s\n' "$_out" | grep -qxF "computed_tier=full" \
    && ok "SKF1: the Step 3.7 fence computes full when the change stages a real plant target ($FIRST_REL)" \
    || bad "SKF1: staging $FIRST_REL gave: $_out — expected computed_tier=full"
  printf '%s\n' "$_out" | grep -q "^plant_match=$FIRST_REL\$" \
    && ok "SKF1b: the Step 3.7 fence surfaces the matching path via plant_match=" \
    || bad "SKF1b: no plant_match=$FIRST_REL line — got: $_out"

  _r=$(_mksandbox docs)
  printf 'fixture\n' >"$_r/ci-tier-not-a-real-file-docs-fixture.md"
  git -C "$_r" add -- ci-tier-not-a-real-file-docs-fixture.md >/dev/null 2>&1
  _out=$(_run_step37 "$_r")
  printf '%s\n' "$_out" | grep -qxF "computed_tier=docs" \
    && ok "SKF2: the Step 3.7 fence computes docs for a change outside staging/.github/.claude with no plant-target match" \
    || bad "SKF2: staging an unrelated file gave: $_out — expected computed_tier=docs"

  _r=$(_mksandbox fallback)
  printf 'fixture\n' >"$_r/ci-tier-not-a-real-file-docs-fixture.md"
  git -C "$_r" add -- ci-tier-not-a-real-file-docs-fixture.md >/dev/null 2>&1
  _out=$(_run_step37 "$_r" "CI_TIER_REGISTRY_DIR=$TMP/empty-registry")
  printf '%s\n' "$_out" | grep -qxF "computed_tier=full" \
    && ok "SKF3: the Step 3.7 fence falls back to full, never docs, when ci-tier.sh cannot classify (exit 3)" \
    || bad "SKF3: forced-empty-registry run gave: $_out — expected computed_tier=full"
  printf '%s\n' "$_out" | grep -q '^did_not_run=' \
    && ok "SKF3b: the fallback case surfaces did_not_run= so the caller can render why" \
    || bad "SKF3b: no did_not_run= line on the exit-3 fallback — got: $_out"
fi

printf '\nPASS=%s FAIL=%s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
