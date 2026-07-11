# Plan — claude-md-slim: whole-line content-union-check matching

**Date:** 2026-07-11
**ADR:** [ADR-0032](../../architecture/ADR-0032-36-claude-md-slim-union-check.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/36-claude-md-slim-whole-line-content-union.spec.md`,
issue #36, confirmed byte-identical)
**Style:** TDD (red → partial-green → green). Auto mode active, no intermediate HITL inside this
plan; commit/push stay HITL per repo `CLAUDE.md` invariant (see HITL gates, end of file). One
finding, two sub-fixes (script behavior + SKILL.md documentation), one shared test file, one
commit.

**Task checklist (five tasks — checked off by the coder as each completes; both `concept-to-code`
SKILL.md's Step 5 pre-dispatch check and `autopilot-build` SKILL.md's Check 5 grep this file for
`- [ ]`, so every task gets one, unlike this plan's own prose elsewhere):**

- [x] Task 1 — RED: new hermetic test file, five sections (A-E), against the current,
  unmodified script and SKILL.md.
- [x] Task 2 — GREEN: fix `content-union-check.sh` (whole-line + trailing-whitespace trim +
  set-based union).
- [x] Task 3 — GREEN: document the multiplicity exemption in `SKILL.md`.
- [x] Task 4 — Wire `docs-ci.yml`, full regression sweep, bash-safety sweep, scope verification.
- [x] Task 5 — SPEC.md checkbox update, final report.

---

## Why every RED in this plan is genuine RED (except explicitly-labeled companions)

Every RED/PASS prediction below was **verified by live execution against the real, unmodified
files** during planning (not reasoned about from source alone) — see ADR-0032 §2.4 for the
methodology. Two categories of non-genuine-RED assertions exist in this plan, and each task states
explicitly which category its own assertions fall into:

1. **Non-regression companions** (A2, B1, D1, D2): already pass today and must keep passing; the
   fix must not break them.
2. **Accidental-pass-today-for-a-different-reason companion** (C1): passes both before and after
   this plan's fix, but for a *different* reason each time. Today it passes because the OLD
   substring-based check treats a shorter original line as a trivial substring of a longer union
   line that shares its prefix — a lucky accident of the very bug this plan fixes, not evidence
   trailing-whitespace tolerance is a deliberately designed property yet. After the fix it passes
   because of the explicit `sed` trim (D3). **Do not mistake C1's "already passing" status for
   "nothing to verify here"** — a live-executed strawman (a naive whole-line fix *without* the
   trim) was built during planning specifically to prove this is not automatic: it turns C1 into a
   real failure (see ADR-0032 §2.3/D3). C2 (skip-logic) is a genuine non-regression companion,
   unrelated to the trim question — its underlying code is untouched by this fix.
3. **Genuine RED** (A1, E1, E2): fail today for the actual reason this plan exists, and must flip
   to PASS only after the corresponding fix lands (A1 after Task 2; E1/E2 after Task 3).

## Fixture and path conventions (read once, applies to every task below)

- **File to create:** `staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh`
  (new file — SPEC.md's own "Stack" section directs new fixtures/harness tests to `docs-ci`
  coverage; the existing `claude-md-slim/tests/run-tests.sh` is confirmed `$HOME`-coupled and
  outside `docs-ci.yml`'s explicit list, so extending it would not close the coverage gap ADR-0032
  §1.2 identifies — see ADR-0032 §3, D4, for the full rejection of extending it instead).
- **No fence-extraction machinery needed:** `content-union-check.sh` is a real, directly-executable
  shell script. Sections A-C invoke it directly against disposable `mktemp -d` fixtures; Section D
  invokes it against the real, pre-existing `claude-md-slim/tests/fixtures/` files; Section E is a
  static `grep` anchor on `SKILL.md`'s new subsection (not executable, matching ADR-0030/0031's
  own static-anchor convention for prose).
- **Header, path derivation, PASS/FAIL idiom** (copy verbatim from `refactor-snapshot-deep-refactor
  .test.sh`'s own preamble, adapted to this file's one target path):
  ```bash
  #!/bin/bash
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
  ```
  Full header comment block (file docstring, summarizing the five sections) is specified in
  Task 1's contract verbatim — do not skip it; every existing file in this directory has one.
- **Bash 3.2 / BSD safety (every file touched this plan):** no `${var,,}`, no `mapfile`, no `<()`,
  no `declare -A`, no GNU-only regex shorthands (`\s`, `\d`) in any `grep -E`/`sed` pattern — plain
  `grep -q`/`grep -c`/`grep -xF`/`grep -F` and `sed 's/[[:space:]]*$//'` only (POSIX bracket
  expression, verified identical under BSD sed, `/usr/bin/sed` on macOS, and GNU sed on
  `docs-ci.yml`'s `ubuntu-latest` runner — no dialect branching needed).
- **Per-task checkpoint (three checks, all must pass before moving to the next task):**
  1. `bash -n <every .sh file touched this task>`.
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' <changed .sh file>` — must be empty.
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay green, unchanged
     (this plan adds zero `PAIRS` entries — the new test file's closest structural siblings,
     `scope-guards.test.sh` and `refactor-snapshot-deep-refactor.test.sh`, are not in `PAIRS`
     either).

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verified during planning, not assumed):
  `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` → 10/10 files
  green (this is also `.claude/test-cmd`'s literal content — confirmed by reading the file).
- Writes are confined to:
  `staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh` (new),
  `staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh`,
  `staging/plugin/skills/claude-md-slim/SKILL.md`, `.github/workflows/docs-ci.yml`, `SPEC.md`
  (checkbox updates, final task), `docs/architecture/` and `docs/superpowers/plans/` (already
  written by this ADR/plan pass).
- Do not touch: any file under `~/.claude` (the deployed copy stays defective until a separate,
  human-gated `sync-to-claude.sh --apply` — same convention as ADR-0025 through ADR-0031),
  `staging/plugin/skills/claude-md-slim/tests/run-tests.sh` and its `tests/fixtures/*.md` files
  (confirmed `$HOME`-coupled, not part of the hermetic `docs-ci` harness, confirmed compatible
  with this fix by direct execution during planning — ADR-0032 §2.4 — no edit needed;
  `tests/fixtures/*.md` are read by the new hermetic test's Section D but not modified),
  `staging/plugin/skills/claude-md-slim/scripts/{parse-sections.sh,classify-sections.sh,
  validate-frontmatter.sh}` (untouched — this fix is scoped to `content-union-check.sh` only),
  any historical ADR (immutable records; ADR-0019 is **amended by**, not edited by, this ADR — see
  ADR-0032's own front matter), any file under `docs/manifests/` (manifest state transitions are
  outside this plan's scope), `staging/sync-to-claude.sh` and
  `staging/plugin/scripts/tests/pairs-completeness.test.sh` (confirmed by reading both before this
  plan was written that no new `PAIRS` entry is needed).
- `content-union-check.sh` edits are scoped exactly to: the header comment (current lines 2-16),
  the core matching block (current lines 41-63, replaced), and one `rm -f "$UNION_TMP"` line
  inserted before the final `if`/`exit` (current lines 65-69). Lines 17-39 (`set -u`, the usage
  check, the `$ORIGINAL` existence check, the outfile-existence pre-check loop) are
  **byte-identical, untouched** — confirm with a targeted diff in Task 4's checkpoint.
- `SKILL.md` edits are scoped exactly to one new subsection inserted between the current line 173
  (blank line after the content-preservation code block's closing fence) and current line 174
  (`3. **Reduction metric.**`). No other line in the file changes.

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/prep.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh` → exit 0, unchanged 39/39
  (untouched by this plan).
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` → exit 0, unchanged 107/107 (no
  new `PAIRS` entries added at any point in this plan).
- `bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` → exit 0, unchanged
  14/14 (untouched).
- `bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` → exit 0,
  unchanged 17/17 (untouched).
- `bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` → exit 0,
  unchanged 21/21 (untouched).
- `bash staging/plugin/scripts/tests/scope-guards.test.sh` → exit 0, unchanged 18/18 (untouched).
- `bash staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh` → exit 0, unchanged
  19/19 (untouched).
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing
  under `~/.claude` is ever touched.

---

## Task 1 — RED: new hermetic test file, five sections (A-E)

- [x] Create `staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh` with
  the file header, path derivation/PASS-FAIL preamble ("Fixture and path conventions" above), and
  all five sections' nine assertions (genuine RED for A1, E1, E2; A2, B1, D1, D2 non-regression
  companions already passing; C1 an accidental-pass-today-for-a-different-reason companion, C2 a
  genuine non-regression companion — all nine predictions verified by live execution against the
  real, unmodified `content-union-check.sh` and `SKILL.md` during planning).

**Files modified:**
- `staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh` (new).

**Contract — file docstring (top of file, immediately after the shebang, before `set -u`):**
```bash
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
```

**Contract — Section A, insert verbatim after the preamble:**
```bash
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
```

**Contract — Section B, insert verbatim after Section A:**
```bash
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
```

**Contract — Section C, insert verbatim after Section B:**
```bash
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
```

**Contract — Section D, insert verbatim after Section C:**
```bash
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
```

**Contract — Section E, insert verbatim after Section D:**
```bash
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
```

**Expected now (RED), verified by live execution during planning:** A1 fails (bug reproduces,
current script exits 0). A2 passes. B1 passes. C1 passes (accidentally, see header). C2 passes.
D1 passes. D2 passes (correctly fails on the incomplete set, so the `ok()` branch fires). E1
fails (subsection absent). E2 fails (multiplicity word absent). **Totals: PASS=6 (A2, B1, C1, C2,
D1, D2), FAIL=3 (A1, E1, E2).**

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh
bash staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh
# expect: PASS=6 FAIL=3 (A1, E1, E2)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 2 — GREEN: fix `content-union-check.sh`

- [x] Replace the header comment and the core matching block with the whole-line,
  trailing-whitespace-trimmed, set-based union check.

**Files modified:**
- `staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh`

**Contract — replace the header comment (current lines 2-16) in full:**
```bash
# content-union-check.sh — verify every non-empty, non-comment line of the original
# CLAUDE.md appears, as a WHOLE LINE, in the union of the proposed output files.
#
# Matching semantics (whole-line, set-based — ADR-0032):
#   - A line counts as PRESERVED if it appears, in full, as one line of at least one output
#     file, after trimming trailing whitespace from both sides. A text PREFIX match (e.g. the
#     original heading "## Git" appearing to "match" because an unrelated "## GitHub Actions"
#     heading survives in the union) does NOT count — see ADR-0032 for the reproduction.
#   - Per-line occurrence counts (multiplicity) between original and union are NOT compared.
#     This is a deliberate, documented exemption, not a gap: the invariant is a SET union
#     (ADR-0019 D6's own "union(output) >= union(input)" framing), and the pipeline's own
#     merge-dedup (SKILL.md Step 7.4) and --global duplicate-removal (Step 3/4) legitimately
#     reduce occurrence counts by design. See SKILL.md "Content-preservation exemptions" and
#     ADR-0032 D2 for the full rationale.
#
# Inputs:
#   $1     = path to the original CLAUDE.md
#   $2..$N = paths to output files (trimmed CLAUDE.md + rules files)
#
# Exit 0 if every original line is preserved (whole-line match) in at least one output file.
# Exit 1 with a stderr summary line: "<N> lines from original not found in any output file".
#
# Lines skipped from the check:
#   - empty / whitespace-only lines
#   - delegation-note comment lines starting with "<!--"
#
# Bash 3.2-clean.
```
(Lines 1 and 17, the shebang and `set -u`, are unchanged and immediately precede/follow.)

**Contract — replace the core matching block (current lines 41-63) in full:**
```bash
# Build the literal union: every output file, trailing-whitespace stripped per line,
# concatenated into one temp file. Whole-line matching then reduces to a single
# grep -qxF per original line against this one file.
UNION_TMP=$(mktemp /tmp/content-union-check.XXXXXX)
for outfile in "$@"; do
  sed 's/[[:space:]]*$//' "$outfile" >> "$UNION_TMP"
done

missing=0
while IFS= read -r line || [ -n "$line" ]; do
  # Skip empty / whitespace-only lines.
  case "$line" in
    "" ) continue ;;
    *[!\ \	]*) : ;;
    *) continue ;;
  esac
  # Skip delegation-note comment lines.
  case "$line" in
    "<!--"*) continue ;;
  esac
  # Trim trailing whitespace before the whole-line comparison (tolerates trailing-space/tab
  # differences between the original and the output files).
  trimmed_line=$(printf '%s' "$line" | sed 's/[[:space:]]*$//')
  if ! grep -qxF -- "$trimmed_line" "$UNION_TMP" 2>/dev/null; then
    missing=$((missing + 1))
  fi
done < "$ORIGINAL"
```

**Contract — insert one line immediately before the final `if [ "$missing" -gt 0 ]` block
(current line 65), i.e. immediately after the `done < "$ORIGINAL"` line above:**
```bash

rm -f "$UNION_TMP"
```
The final `if [ "$missing" -gt 0 ]; then ... exit 1; fi` / `exit 0` block (current lines 65-69)
is otherwise **unchanged**. Lines 17-39 (`set -u`, the usage check, the `$ORIGINAL` existence
check, the outfile pre-check loop) are **byte-identical, untouched**.

**Expected (GREEN):** A1, A2, B1, C1, C2, D1, D2 all pass (A1 newly, for real; the other six
unchanged from Task 1, C1 now passing for the correct, by-design reason instead of by accident).
E1, E2 remain RED (SKILL.md not yet touched).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh
# expect: PASS=7 FAIL=2 (E1, E2)
bash -n staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh   # empty
diff <(git show HEAD:staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh) staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh
# manually confirm: only the header comment, the core matching block, and the one-line
# rm -f "$UNION_TMP" insertion changed; the usage/argument-validation lines are untouched.
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 3 — GREEN: document the multiplicity exemption in `SKILL.md`

- [x] Insert the "Content-preservation exemptions" subsection between the current line 173
  (blank line after the content-preservation code block's closing fence) and current line 174
  (`3. **Reduction metric.**`).

**Files modified:**
- `staging/plugin/skills/claude-md-slim/SKILL.md`

**Contract — insert verbatim (new blank line before and after, matching the file's existing
spacing convention):**
```markdown
   **Content-preservation exemptions (deliberate, not a gap — ADR-0032 D1-D3):**
   - **Matching is whole-line, not substring**, and tolerates trailing-whitespace differences
     (both sides trimmed before comparison). A heading like `## Git` must appear as a complete
     line in some output file; being a text prefix of `## GitHub Actions` does not count.
   - **Per-line occurrence counts (multiplicity) are NOT compared.** The invariant is a SET
     union (`union(output) >= union(input)`, per ADR-0019 D6) — it checks that every distinct
     line survives at least once, not that it survives the same number of times. A line
     duplicated in the original CLAUDE.md and collapsed to a single copy in the output is not
     content loss: the pipeline's own merge step (Step 7.4, dedup by exact-line match against a
     pre-existing target rules file) and the `--global` duplicate-removal step (Step 3/4)
     legitimately reduce occurrence counts by design. Enforcing multiplicity would make the
     invariant fail on the skill's own intended behavior. See ADR-0032 D2.
```
Nothing else in `SKILL.md` changes — not the "Hard constraints" bullet (current lines 29-31), not
the reduction-metric text that immediately follows, not any other Step.

**Expected (GREEN):** E1, E2 pass for real now. A1, A2, B1, C1, C2, D1, D2 unchanged (already
passing since Task 2).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh
# expect: PASS=9 FAIL=0 -- full file green (2 Section A + 1 Section B + 2 Section C +
# 2 Section D + 2 Section E = 9)
diff <(git show HEAD:staging/plugin/skills/claude-md-slim/SKILL.md) staging/plugin/skills/claude-md-slim/SKILL.md
# manually confirm: only the new subsection (between current lines 173 and 174) was inserted;
# everything else in the file is byte-identical.
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 4 — Wire `docs-ci.yml`, full regression sweep, bash-safety sweep, scope verification

- [x] Add `claude-md-slim-content-union-whole-line` to `docs-ci.yml`'s explicit `shell-tests`
  list; run the full local test-cmd; sweep for bash 3.2/BSD safety; confirm the changed-file set
  matches the Pre-flight "writes are confined to" list exactly.

**Files modified:**
- `.github/workflows/docs-ci.yml`

**Contract — `docs-ci.yml`, append `claude-md-slim-content-union-whole-line` as the eleventh
entry in the `for t in ...` list (current line 44):**
```
          for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates concept-to-code-manifest-helpers-guards scope-guards refactor-snapshot-deep-refactor claude-md-slim-content-union-whole-line; do
```

**Verify (full, repo-wide):**
```bash
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done    # local test-cmd, 11/11 green
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                       # unchanged, exit 0
bash -n staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh   # empty
grep -nF '<<<' staging/plugin/scripts/tests/claude-md-slim-content-union-whole-line.test.sh staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh   # empty
echo "bash 3.2 / BSD safety: clean"
diff <(git show HEAD:staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh) staging/plugin/skills/claude-md-slim/scripts/content-union-check.sh
# manually confirm: only the header comment, the core matching block, and the rm -f insertion
# changed; the usage/argument-validation section is untouched (Task 2's contract).
diff <(git show HEAD:staging/plugin/skills/claude-md-slim/SKILL.md) staging/plugin/skills/claude-md-slim/SKILL.md
# manually confirm: only the one new subsection was inserted (Task 3's contract).
grep -c "claude-md-slim-content-union-whole-line" .github/workflows/docs-ci.yml   # 2 (the for-list entry + this grep's own match, sanity-check the count by eye)
git status   # confirm change set matches Pre-flight "writes are confined to" list; nothing under ~/.claude
```

**Report to dispatcher (accumulate for Task 5):**
- Full local `test-cmd` glob result (11/11 files green) pasted verbatim.
- `claude-md-slim-content-union-whole-line.test.sh` final tally: expect `PASS=9 FAIL=0`.
- Confirmation each target file's diff touches only the region named in Pre-flight's scoping
  note — nothing else.
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted.

---

## Task 5 — SPEC checkbox update, final report

- [x] Check off SPEC.md's five satisfied success criteria and produce the final report for the
  dispatcher.

**Files modified:**
- `SPEC.md` — check off all five success-criteria boxes (current lines 39-43): the `## Git`/
  `## GitHub Actions` fixture now fails the gate (Section A); the duplicated-line fixture is
  covered by the documented exemption (Section B + the SKILL.md subsection, satisfying the
  criterion's OR-clause); all existing claude-md-slim tests pass (Task 2/3 checkpoints, plus
  Task 4's full sweep); the script stays bash 3.2 clean (Task 4's safety sweep, and ADR-0032
  §2.4's own `/bin/bash --version` confirmation of `3.2.57`); no file under `~/.claude` was
  modified (Task 4's `git status` check).

**Report to dispatcher:**
- ADR path: `docs/architecture/ADR-0032-36-claude-md-slim-union-check.md`.
- Plan path: `docs/superpowers/plans/2026-07-11-36-claude-md-slim-union-check.md`.
- Spec path: `SPEC.md` (= `docs/specs/36-claude-md-slim-whole-line-content-union.spec.md`).
- `claude-md-slim-content-union-whole-line.test.sh` final tally (`PASS=9 FAIL=0`) and full local
  test-cmd result (11/11 files green), pasted verbatim from Task 4.
- Explicit flag for the human reviewer: `claude-md-slim/tests/run-tests.sh` (the `$HOME`-coupled
  skill-local test file) was confirmed compatible with this fix by direct execution during
  planning but was **not executed** as part of Task 4's verification (it tests the deployed
  `~/.claude` copy, out of this roadmap's `staging/`-is-source-of-truth scope) — a reviewer who
  wants to see it actually run green against a synced `~/.claude` should do so manually, after a
  separate `sync-to-claude.sh --apply`.
- Explicit flag: the *deployed* copy (`~/.claude/skills/claude-md-slim/scripts/
  content-union-check.sh`) keeps today's defective (substring-matching) behavior until a human
  runs `sync-to-claude.sh --apply`.
- Explicit flag: a pre-existing, orthogonal gap was found and disclosed, not fixed, during
  architecture — the `--global` duplication scan's `DUPLICATE`-removed lines are never passed to
  `content-union-check.sh` as a union input (ADR-0032 §1.4). Recommend a follow-up issue; out of
  this plan's scope.
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — mistaking Section C1's "already passing" status at the Task 1 checkpoint for "the
  trim step is unnecessary."** C1 passes both before and after the fix, for different reasons
  (see plan header, category 2). **Mitigation:** the file's own header comment and Section C's
  inline comment both state this explicitly; ADR-0032 §2.3/D3 documents the live-executed
  strawman that proves the trim step is load-bearing. Do not simplify Task 2's contract by
  dropping the `sed` trim "since C1 already passes without it."
- **Risk B — transcribing the `UNION_TMP` construction or the `rm -f` placement incorrectly.** If
  `rm -f "$UNION_TMP"` is moved before the `while` loop that reads it, or omitted, the check
  either always reports every line missing (union deleted too early) or leaks a temp file per
  invocation (omitted). **Mitigation:** Task 2's contract gives the exact, already-verified
  insertion point (immediately after `done < "$ORIGINAL"`, immediately before the final `if`);
  Task 2's checkpoint re-runs the full test file, which would show every Section A-D assertion
  failing if the union file were deleted too early, or D1/D2 behaving identically to today if the
  block were skipped entirely — either failure mode is loudly visible, not silent.
- **Risk C — `sed 's/[[:space:]]*$//'` being transcribed with a GNU-only shorthand (e.g. `\s`
  instead of `[[:space:]]`).** Would pass silently in CI (`ubuntu-latest`, GNU sed) but fail or
  behave differently on a contributor's Mac (BSD sed). **Mitigation:** this exact pattern was
  verified directly against BSD sed (`/usr/bin/sed` on this machine, confirmed via the
  `illegal option --` signature to `--version`) during planning (ADR-0032 §2.4); Task 4's
  checkpoint's full local test-cmd run is the automated backstop, and it runs under the real
  macOS system bash/sed, not just CI.
- **Risk D — scope creep into `run-tests.sh`, its `tests/fixtures/*.md` files, or the other three
  scripts in `claude-md-slim/scripts/`.** All are adjacent, thematically related, and a coder
  might be tempted to "clean up while in the area" (e.g. rewriting `run-tests.sh` to drop its
  `$HOME` coupling, which ADR-0032 §3/D4 explicitly considered and rejected for this issue).
  **Mitigation:** Pre-flight's "do not touch" list is explicit; Task 4's `git status` and targeted
  `diff`s are the automated backstop.
- **Risk E — the deployed skill keeps the defect until sync.** Not a defect in this plan's own
  execution, but a real operational risk this plan cannot itself close. **Mitigation:** flagged
  with explicit priority in Task 5's report, matching ADR-0025 through ADR-0031 precedent.
- **Risk F — the `--global`/`DUPLICATE`-vs-global-file gap (ADR-0032 §1.4) being mistaken for
  something this plan also fixes.** It does not; whole-line matching may make that pre-existing
  gap surface more often (fewer accidental substring-luck passes), which is a visible behavior
  change for `--global` users even though this plan's own reasoning does not regress anything.
  **Mitigation:** Task 5's report flags it explicitly as a disclosed, out-of-scope finding with a
  recommended follow-up issue, not silently bundled into this fix's own success criteria.

## HITL gates

- No HITL gate inside this plan itself (auto mode; every edit is a scoped, corrective change to
  an existing script or skill-instruction file, or a new, isolated hermetic test file; no
  destructive git operations; every live script invocation in Tasks 1-3 targets a disposable
  `mktemp -d` fixture or a real, pre-existing, read-only fixture file, never a real project's
  `.claude/test-cmd` or `docs/manifests/`).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and
  push remain human-gated, as does the follow-up `sync-to-claude.sh --apply` that would actually
  deploy this fix (Risk E) — that sync is explicitly out of this plan's scope and requires its own
  separate human action.
- No DB schema change, no permanent deletion, no production migration in this plan — none of the
  invariant HITL triggers beyond the standard commit/push gate apply here.
