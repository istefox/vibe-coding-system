#!/bin/bash
# claude-md-slim-content-union-whole-line.test.sh -- content-union-check.sh whole-line matching
# fix (SPEC.md / issue #36, ADR-0032). content-union-check.sh is the sole ADR-0019
# content-preservation hard gate for the claude-md-slim skill. Its only prior coverage (T04 in
# staging/plugin/skills/claude-md-slim/tests/run-tests.sh) is $HOME-coupled and was never part
# of the hermetic docs-ci harness -- this file closes that CI gap while fixing the defect. Five
# lettered sections:
#   Section A (substring false-positive, 2 tests) -- line 55 used
#     `grep -qF -- "$line" "$outfile"`, a fixed-STRING but SUBSTRING match: an original
#     containing only the line "## Git" passes when the union contains only "## GitHub
#     Actions", because "## Git" is a literal text prefix of "## GitHub Actions". Fixed with
#     whole-line matching (`grep -qxF` against a constructed union file).
#   Section B (multiplicity, documented exemption, 1 test) -- a line appearing twice in the
#     original and once in the union is NOT flagged as content loss. This is a deliberate,
#     documented exemption (ADR-0032 D2; SKILL.md "Content-preservation exemptions"), not an
#     oversight: the invariant is a SET union (ADR-0019 D6's own "union(output) >= union(input)"
#     framing), and the pipeline's own merge-dedup (SKILL.md Step 7.4) and --global
#     duplicate-removal (Step 3/4) legitimately reduce occurrence counts by design. Verified
#     live during planning: the CURRENT (pre-fix) script already behaves this way too -- this
#     assertion is a non-regression companion, not RED->GREEN.
#   Section C (trailing-whitespace tolerance, 2 tests) -- switching to whole-line matching
#     WITHOUT trimming trailing whitespace would be a REGRESSION: the old substring-based script
#     tolerated trailing-whitespace-only differences by accident (a shorter line is always a
#     substring of a longer line sharing its prefix); a naive `grep -qxF` alone loses this.
#     Fixed by stripping trailing whitespace from both sides before comparison (verified live
#     during planning against a naive no-trim variant, which regresses this exact case). C2
#     covers the unrelated empty-line/"<!--"-comment skip logic, unchanged by this fix.
#   Section D (regression parity, 2 tests) -- content-union-check.sh run directly against the
#     three pre-existing fixtures in claude-md-slim/tests/fixtures/ (sample-claude-md.md,
#     expected-trimmed.md, expected-shell-rules.md), mirroring run-tests.sh's own T04
#     assertions, so this exact pass/fail contract gets real CI coverage for the first time.
#   Section E (SKILL.md documentation anchor, 2 tests) -- the multiplicity exemption is
#     documented in SKILL.md text per SPEC.md's explicit instruction ("or document explicitly
#     why multiplicity is out of scope").
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... -- that is the deployed copy, out of scope.
# content-union-check.sh is a standalone executable; Sections A-C invoke it directly against
# disposable mktemp fixtures, Section D against the real, pre-existing staging fixtures -- no
# fence-extraction machinery needed. Section E is a static grep anchor on SKILL.md prose.
# Bash 3.2 clean. Run: bash claude-md-slim-content-union-whole-line.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
CHECK_SH="$STAGING/plugin/skills/claude-md-slim/scripts/content-union-check.sh"
SKILL_MD="$STAGING/plugin/skills/claude-md-slim/SKILL.md"
FIXTURES="$STAGING/plugin/skills/claude-md-slim/tests/fixtures"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# =====================================================================================
# Section A -- substring false-positive: "## Git" vs union containing only "## GitHub Actions"
# =====================================================================================

printf '## Git\n' > "$TMP/a-original.md"
printf '## GitHub Actions\n' > "$TMP/a-union-bad.md"
printf '## Git\n' > "$TMP/a-union-good.md"

# A1 (dynamic, genuine RED now): original's only line is "## Git"; union's only line is
# "## GitHub Actions" -- "## Git" is a literal text prefix of "## GitHub Actions", so the OLD
# substring-based check wrongly reports success. Must exit non-zero (content genuinely lost).
if bash "$CHECK_SH" "$TMP/a-original.md" "$TMP/a-union-bad.md" >/dev/null 2>&1; then
  bad "A1: '## Git' vs union-only '## GitHub Actions' should FAIL (whole heading was dropped)"
else
  ok "A1: '## Git' vs union-only '## GitHub Actions' correctly FAILS (whole-line match)"
fi

# A2 (dynamic, non-regression companion, already passes today): the exact whole line survives
# in the union -- must still exit 0.
bash "$CHECK_SH" "$TMP/a-original.md" "$TMP/a-union-good.md" >/dev/null 2>&1 \
  && ok "A2: '## Git' vs union containing the exact line '## Git' passes" \
  || bad "A2: '## Git' vs union containing the exact line '## Git' should pass"

# =====================================================================================
# Section B -- multiplicity: documented exemption (non-regression companion, NOT RED->GREEN)
# =====================================================================================

printf 'Never commit secrets.\n\nNever commit secrets.\n' > "$TMP/b-original.md"
printf 'Never commit secrets.\n' > "$TMP/b-union.md"

# B1 (dynamic, non-regression companion -- verified live during planning that the CURRENT,
# unmodified script ALREADY passes this case; the fix must not newly start failing it, since
# the invariant is a SET union, not a multiset -- see file header and ADR-0032 D2).
bash "$CHECK_SH" "$TMP/b-original.md" "$TMP/b-union.md" >/dev/null 2>&1 \
  && ok "B1: line duplicated 2x in original, 1x in union -- passes (documented exemption)" \
  || bad "B1: line duplicated 2x in original, 1x in union should still pass (set-based invariant)"

# =====================================================================================
# Section C -- trailing-whitespace tolerance (regression guard: a naive whole-line-only fix,
# without trimming, would newly break C1 -- verified live during planning) and unrelated
# skip-logic non-regression (C2)
# =====================================================================================

printf '## Trailing test\nSome content here.\n' > "$TMP/c-original.md"
printf '## Trailing test   \nSome content here.\t\n' > "$TMP/c-union.md"

# C1 (dynamic, accidental-pass-today-for-a-different-reason companion -- see plan header "Why
# every RED..."): trailing spaces/tabs on the union side only must not be treated as content
# loss, before AND after the fix, but for different reasons each time.
bash "$CHECK_SH" "$TMP/c-original.md" "$TMP/c-union.md" >/dev/null 2>&1 \
  && ok "C1: trailing-whitespace-only difference is tolerated" \
  || bad "C1: trailing-whitespace-only difference should be tolerated"

printf '\n<!-- a delegation note -->\n   \nReal content line.\n' > "$TMP/c2-original.md"
printf 'Real content line.\n' > "$TMP/c2-union.md"

# C2 (dynamic, genuine non-regression companion -- skip-logic code is untouched by this fix):
# empty lines and "<!--" delegation-note comment lines stay exempt from the check.
bash "$CHECK_SH" "$TMP/c2-original.md" "$TMP/c2-union.md" >/dev/null 2>&1 \
  && ok "C2: empty lines and <!-- comment lines stay exempt from the check" \
  || bad "C2: empty lines and <!-- comment lines should stay exempt"

# =====================================================================================
# Section D -- regression parity against the pre-existing claude-md-slim fixtures (mirrors
# run-tests.sh's own T04, gives this exact pass/fail contract real CI coverage for the first
# time -- T04 itself is $HOME-coupled and outside docs-ci)
# =====================================================================================

# D1 (non-regression companion, already passes today): complete output set preserves every
# original line.
bash "$CHECK_SH" "$FIXTURES/sample-claude-md.md" "$FIXTURES/expected-trimmed.md" \
  "$FIXTURES/expected-shell-rules.md" >/dev/null 2>&1 \
  && ok "D1: content-union-check passes on the complete fixture set" \
  || bad "D1: content-union-check should pass on the complete fixture set"

# D2 (non-regression companion, already correctly fails today): incomplete output set (the
# extracted shell-rules file is missing) must still be flagged.
bash "$CHECK_SH" "$FIXTURES/sample-claude-md.md" "$FIXTURES/expected-trimmed.md" \
  >/dev/null 2>&1 \
  && bad "D2: content-union-check should fail on the incomplete fixture set" \
  || ok "D2: content-union-check correctly fails on the incomplete fixture set"

# =====================================================================================
# Section E -- SKILL.md documents the multiplicity exemption (SPEC.md's explicit instruction)
# =====================================================================================

# E1 (static, genuine RED now): SKILL.md has the new, named exemption subsection.
grep -qF 'Content-preservation exemptions' "$SKILL_MD" \
  && ok "E1: SKILL.md documents the 'Content-preservation exemptions' subsection" \
  || bad "E1: SKILL.md should document a 'Content-preservation exemptions' subsection"

# E2 (static, genuine RED now): the exemption text explicitly names multiplicity/occurrence
# counts -- guards against a heading-only addition that doesn't actually explain the exemption.
grep -Eiq 'multiplicit|occurrence count' "$SKILL_MD" \
  && ok "E2: SKILL.md's exemption names multiplicity/occurrence counts explicitly" \
  || bad "E2: SKILL.md's exemption should name multiplicity/occurrence counts explicitly"

# Section F -- file-boundary newline (RTF finding, issue #36 review cycle)
# =====================================================================================
# BSD sed passes through a missing trailing newline; without a forced boundary newline
# in the union build, a non-last output file lacking a trailing \n merges its final
# line with the next file's first line, spuriously failing BOTH original lines.

F_DIR=$(mktemp -d "$TMP/f-boundary.XXXXXX")
printf 'line preserved\nother stuff\n' > "$F_DIR/original.md"
printf 'line preserved' > "$F_DIR/rules-no-trailing-nl.md"   # deliberately no trailing \n
printf 'other stuff\n' > "$F_DIR/trimmed.md"

# F1: non-last output file without trailing newline must still count both lines preserved.
if bash "$CHECK_SH" "$F_DIR/original.md" "$F_DIR/rules-no-trailing-nl.md" "$F_DIR/trimmed.md" >/dev/null 2>&1; then
  ok "F1: non-last output without trailing newline does not merge across the file boundary"
else
  bad "F1: union build merged lines across a file boundary (missing forced newline)"
fi

# F2: order-independence companion — same files with the no-newline file last must also pass.
if bash "$CHECK_SH" "$F_DIR/original.md" "$F_DIR/trimmed.md" "$F_DIR/rules-no-trailing-nl.md" >/dev/null 2>&1; then
  ok "F2: no-trailing-newline output as the last argument also passes"
else
  bad "F2: no-trailing-newline output as the last argument should pass"
fi

printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
