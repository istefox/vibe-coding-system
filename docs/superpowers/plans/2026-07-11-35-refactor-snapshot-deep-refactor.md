# Plan — refactor-snapshot filter append and deep-refactor scope glob

**Date:** 2026-07-11
**ADR:** [ADR-0031](../../architecture/ADR-0031-35-refactor-snapshot-deep-refactor.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/35-refactor-snapshot-filter-append-and-deep.spec.md`,
issue #35, confirmed byte-identical)
**Style:** TDD (red → green → checkpoint). Auto mode active, no intermediate HITL inside this plan;
commit/push stay HITL per repo `CLAUDE.md` invariant (see HITL gates, end of file). Three
independent findings, one shared test file, one commit — ADR-0031 §3.4 records why this bundles at
the issue's own granularity rather than splitting into three ADRs/plans/commits.

**Task checklist (eight tasks — checked off by the coder as each completes; both `concept-to-code`
SKILL.md's Step 5 pre-dispatch check and `autopilot-build` SKILL.md's Check 5 grep this file for
`- [ ]`, so every task gets one, unlike this plan's own prose elsewhere):**

- [x] Task 1 — RED: Section A (`refactor-snapshot-deep-refactor.test.sh`, new file) —
  `capture.sh` RFS_FILTER fixtures.
- [x] Task 2 — GREEN: fix `refactor-snapshot/scripts/capture.sh`.
- [x] Task 3 — RED: Section B — `enumerate-sources.sh` glob-override fixtures.
- [x] Task 4 — GREEN: fix `deep-refactor/scripts/enumerate-sources.sh`.
- [x] Task 5 — RED: Section C — `deep-refactor/SKILL.md` Gate 2 DIRTY_TREE fixtures.
- [x] Task 6 — GREEN: fix `deep-refactor/SKILL.md` Gate 2 circuit-breaker text.
- [x] Task 7 — Wire `docs-ci.yml`, full regression sweep, bash-safety sweep, scope verification.
- [x] Task 8 — SPEC.md checkbox update, final report.

---

## Why every RED in this plan is genuine RED (except explicitly-labeled companions)

Every RED/PASS prediction below was **verified by live execution against the real, unmodified
files** during planning (not reasoned about from source alone) — see ADR-0031 §2.4 for the
methodology. Two categories of non-genuine-RED assertions exist, and each task states explicitly
which category its own assertions fall into:

1. **Non-regression companions** (A2, A3, B1, B2, C5): already pass today, pinned so the fix
   cannot silently break the already-working case.
2. **Accidental-pass-today-for-the-wrong-reason companions** (B4, B6): tally as PASS both before
   and after this plan's fixes land, but for a *different* reason each time. B4 (`*.py` override,
   zero matches in the fixture) returns empty today only because the old code returns empty for
   *any* glob-metacharacter-containing override, correct match or not — it is not proof the old
   code discriminates correctly. B6 (a `*.generated.swift` file staying excluded under a `Sources/`
   override) passes today and after because file-exclusion is applied *before* the override step in
   both the old and new code (unchanged ordering) — this property is structurally guaranteed either
   way and was never actually broken; it is included purely to give this composition property
   CI-visible coverage for the first time, since the existing `$HOME`-coupled
   `enumerate-sources.test.sh`'s equivalent case (test 9) never runs in CI. **Do not mistake either
   category's "PASS" at the Task 1/3/5 checkpoints for evidence the fix already works** — only B3,
   B5 (Section B) and every Section A/C assertion not listed above are genuine, fix-dependent RED
   today.

## Fixture and path conventions (read once, applies to every task below)

- **File to create:** `staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh` (new
  file — SPEC.md names three findings across two skills with no existing shared hermetic test file
  to extend).
- **No fence-extraction machinery needed for Sections A and B** (unlike ADR-0027/28/29/30's
  `SKILL.md`-prose fixes): `capture.sh` and `enumerate-sources.sh` are real, directly-executable
  shell scripts. Sections A and B invoke them directly (`bash "$CAPTURE_SH" PRE`, `bash "$ENUM_SH"
  "$REPO" "<override>"`) against disposable `mktemp -d` fixtures. Section C (pure Gate 2 HITL-
  message prose, not executable) uses static `grep` anchors scoped to an `awk`-extracted Gate 2
  block, matching ADR-0030's own static-anchor convention for non-executable text.
- **Header, path derivation, PASS/FAIL idiom** (copy verbatim from `scope-guards.test.sh`'s own
  preamble, adapted to this file's three target paths):
  ```bash
  #!/bin/bash
  set -u

  SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
  STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
  CAPTURE_SH="$STAGING/plugin/skills/refactor-snapshot/scripts/capture.sh"
  ENUM_SH="$STAGING/plugin/skills/deep-refactor/scripts/enumerate-sources.sh"
  DR_SKILL="$STAGING/plugin/skills/deep-refactor/SKILL.md"

  PASS=0; FAIL=0
  ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
  bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  ```
  Full header comment block (file docstring, summarizing the three sections with their finding
  numbers) is specified in Task 1's contract — do not skip it; every existing file in this
  directory has one, and ADR-0031 cites finding numbers 2.6/P2, 3.8, 3.9 that belong in it
  verbatim.
- **Env-var isolation idiom for Section A (new to this file, use exactly this form):** each
  dynamic capture.sh invocation runs inside its own `( ... )` subshell that explicitly `export`s or
  `unset`s `RFS_FILTER`/`RFS_FULL` before calling a shared `run_capture` helper — `export` is
  required (not a plain assignment) because `capture.sh` runs as a genuinely separate `bash`
  process (`bash "$CAPTURE_SH" ...`), which only inherits *exported* variables from the parent, and
  each subshell's `export`/`unset` never leaks into a later, sibling subshell (subshells fork, they
  do not write back to the parent's environment) — confirmed by direct execution during planning,
  not assumed.
- **Bash 3.2 / BSD safety (every file touched this plan):** no `${var,,}`, no `mapfile`, no `<()`,
  no `declare -A`, no GNU-only regex shorthands (`\s`, `\d`) in any `grep -E`/`awk` pattern — plain
  `grep -q`/`grep -c`/`grep -F` (BRE/fixed-string) and `awk` only, matching every existing file in
  this directory.
- **Per-task checkpoint (three checks, all must pass before moving to the next task):**
  1. `bash -n <every .sh file touched this task>` (`SKILL.md` is not a shell script — skip `bash
     -n` for it, use the content-diff/grep check in that task instead).
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' <changed .sh file>` — must be empty.
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay green, unchanged
     (this plan adds zero `PAIRS` entries anywhere — ADR-0031 §2.5).

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verified during planning, not assumed):
  `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done` → 9/9 files green
  (this is also `.claude/test-cmd`'s literal content — confirmed by reading the file).
- Writes are confined to: `staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh`
  (new), `staging/plugin/skills/refactor-snapshot/scripts/capture.sh`,
  `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh`,
  `staging/plugin/skills/deep-refactor/SKILL.md`, `.github/workflows/docs-ci.yml`, `SPEC.md`
  (checkbox updates, final task), `docs/architecture/` and `docs/superpowers/plans/` (already
  written by this ADR/plan pass).
- Do not touch: any file under `~/.claude` (the deployed copies stay defective until a separate,
  human-gated `sync-to-claude.sh --apply` — same convention as ADR-0025 through ADR-0030),
  `refactor-snapshot/scripts/pre-runs.sh` and `refactor-snapshot/scripts/diff.sh` (confirmed
  compatible with Finding 1's fix by reading both before this plan was written — ADR-0031 §1
  "Cross-check" — neither builds `EXEC_CMD` itself; no edit needed to either),
  `refactor-snapshot/tests/run-tests.sh` and `deep-refactor/tests/{run-tests.sh,
  enumerate-sources.test.sh}` (confirmed `$HOME`-coupled, not part of the hermetic `docs-ci`
  harness, traced compatible with every fix in this plan — ADR-0031 §1 "Cross-check" — no edit
  needed to any of them), `refactor-snapshot/SKILL.md` and `deep-refactor/agents/refactorer.md` and
  `docs/guida-workflow-orchestrazione.md` (purpose-level `RFS_FILTER` docs, confirmed accurate
  before and after this fix — no edit needed), `docs/vibe-coding-system.md` (its two `git checkout
  -- .` mentions describe an unrelated CC product feature — confirmed, not edited),
  `staging/sync-to-claude.sh` and `staging/plugin/scripts/tests/pairs-completeness.test.sh`
  (confirmed by reading both before this plan was written that no new `PAIRS` entry is needed —
  ADR-0031 §2.5), any historical ADR (immutable records; ADR-0002, ADR-0006, ADR-0018 are
  **related to, not amended by**, this ADR — none needed a correction, per ADR-0031 §1), any file
  under `docs/manifests/` (manifest state transitions are outside this plan's scope).
- `capture.sh` edits are scoped exactly to a one-line insertion immediately before the current
  `if [ "$RFS_FULL" = "1" ] ...` block (current lines 53-57) — the read loop (lines 32-41), the
  empty-content check (lines 43-46), the SHA256 detection (lines 21-29), and all three timeout
  branches (lines 66-88) are **byte-identical, untouched**. Confirm with a targeted diff in Task
  7's checkpoint.
- `enumerate-sources.sh` edits are scoped exactly to the header usage comment (current lines 3-9)
  and the path-override application block (current lines 43-59) — the exclude-globs `grep -v` step
  (lines 39-41), the git-repository validation (lines 23-27), and the trap/cleanup (lines 21, 37,
  61) are **byte-identical, untouched**.
- `deep-refactor/SKILL.md` edits are scoped exactly to Gate 2's own message, current line 585 (one
  sentence, replaced with a `DIRTY_TREE`-conditional pair) — Gate 0 (Step 0.7's own, separate,
  pre-existing `DIRTY_TREE` warning at line 187), the `CIRCUIT BREAKER FIRED AT:` tag and the two
  lines immediately above line 585 (lines 582-584), the Phase 1-4 audit/fix pipeline, and every
  other Gate are **byte-identical, untouched**.

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/prep.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh` → exit 0, unchanged 39/39
  (untouched by this plan).
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` → exit 0, unchanged (no new
  `PAIRS` entries added at any point in this plan).
- `bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` → exit 0 (untouched).
- `bash staging/plugin/scripts/tests/concept-to-code-bsd-autopilot-gates.test.sh` → exit 0,
  unchanged 17/17 (untouched by this plan).
- `bash staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` → exit 0,
  unchanged (untouched by this plan).
- `bash staging/plugin/scripts/tests/scope-guards.test.sh` → exit 0, unchanged 18/18 (untouched by
  this plan).
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing under
  `~/.claude` is ever touched.

---

## Task 1 — RED: Section A (`refactor-snapshot-deep-refactor.test.sh`, new file) — `capture.sh` fixtures

- [x] Create `staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh` with the file
  header, path derivation/PASS-FAIL preamble ("Fixture and path conventions" above), and Section
  A's seven assertions (genuine RED for A1, A4, A5, A6, A7; A2, A3 non-regression companions,
  already passing — all seven predictions verified by live execution against the real,
  unmodified `capture.sh` during planning).

**Files modified:**
- `staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh` (new).

**Contract — file docstring (top of file, immediately after the shebang, before `set -u`):**
```bash
# refactor-snapshot-deep-refactor.test.sh -- three findings from the concept-to-code audit
# (SPEC.md / issue #35). Three lettered sections:
#   Section A (Finding 2.6, P2, 7 tests) -- refactor-snapshot/scripts/capture.sh's read loop
#     always leaves a trailing newline on CMD_CONTENT, so "$CMD_CONTENT $RFS_FILTER" puts the
#     filter on a NEW line; `bash -c` then runs it as a second, separate (bogus) command, and
#     the LAST command's exit status ($?) is always that bogus command's failure (~127),
#     regardless of the real, filtered suite's actual pass/fail -- silently defeating the
#     harness's own exit-code comparison channel whenever RFS_FILTER is used. Fixed by
#     stripping the single trailing newline before building EXEC_CMD.
#   Section B (Finding 3.8, 6 tests) -- deep-refactor/scripts/enumerate-sources.sh's documented
#     "glob/dir prefix" path-override is interpolated raw into `grep -E`; a leading `*` (e.g.
#     override "*.swift") has no operand to repeat, an undefined case in POSIX ERE -- no
#     tracked path starts with a literal "*", so the override always returns zero files and
#     Step 0.6 aborts. Fixed with a single, unified bash `case`-pattern matching engine (real
#     glob semantics, no external regex dialect) that also preserves the existing
#     directory-literal-prefix contract unchanged.
#   Section C (Finding 3.9, 5 tests) -- deep-refactor/SKILL.md's circuit-breaker HITL message
#     (Gate 2) unconditionally suggests `git checkout -- .` to revert unstaged changes, but
#     Gate 0 explicitly allows starting the audit on a dirty tree (DIRTY_TREE=true) -- on that
#     path, the blanket revert also destroys the user's own pre-existing uncommitted edits.
#     Fixed by conditioning the suggestion on DIRTY_TREE, matching this file's own existing
#     `[If <condition>:]` bracket convention.
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... -- that is the deployed copy, out of scope.
# Sections A and B invoke the real, staging scripts directly against disposable mktemp
# fixtures (both are standalone executables) -- no fence-extraction machinery is needed here,
# unlike ADR-0027/28/29/30's SKILL.md-prose fixes. Section C is prose inside a HITL message
# template, so its coverage is static grep anchors only, scoped to the Gate 2 block via an awk
# extractor.
# Bash 3.2 clean. Run: bash refactor-snapshot-deep-refactor.test.sh
```

**Contract — Section A, insert verbatim after the preamble:**
```bash
# =====================================================================================
# Section A -- Finding 2.6 (P2): refactor-snapshot capture.sh RFS_FILTER trailing-newline bug
# =====================================================================================

# A1 (static, genuine RED now): the trailing-newline strip fix marker is present.
grep -qF 'Strip the single trailing newline' "$CAPTURE_SH" \
  && ok "A1: trailing-newline strip fix is present in capture.sh" \
  || bad "A1: trailing-newline strip fix should be present in capture.sh"

# Fixture: a fake test runner that branches its own stdout/exit on whether it received a
# "SUBSET" argument -- simulates a real `pytest -k <pattern>` narrowing. Two runner variants:
# fake-runner.sh (unfiltered=exit9/ran-full, filtered=exit0/ran-subset) for A2-A6, and
# fake-runner-fail.sh (unfiltered=exit0/ran-full-ok, filtered=exit4/ran-subset-fail) for A7 --
# proves a REAL, non-127, non-zero filtered failure also propagates faithfully.
mkdir -p "$TMP/a/proj/.claude" "$TMP/a/proj2/.claude"
cat > "$TMP/a/fake-runner.sh" <<'RUNNER'
#!/bin/bash
if [ "${1:-}" = "SUBSET" ]; then
  printf 'ran-subset\n'
  exit 0
else
  printf 'ran-full\n'
  exit 9
fi
RUNNER
chmod +x "$TMP/a/fake-runner.sh"
printf 'bash %s/fake-runner.sh\n' "$TMP/a" > "$TMP/a/proj/.claude/test-cmd"

cat > "$TMP/a/fake-runner-fail.sh" <<'RUNNER'
#!/bin/bash
if [ "${1:-}" = "SUBSET" ]; then
  printf 'ran-subset-fail\n'
  exit 4
else
  printf 'ran-full-ok\n'
  exit 0
fi
RUNNER
chmod +x "$TMP/a/fake-runner-fail.sh"
printf 'bash %s/fake-runner-fail.sh\n' "$TMP/a" > "$TMP/a/proj2/.claude/test-cmd"

run_capture() { ( cd "$1" && bash "$CAPTURE_SH" "$2" ) >/dev/null 2>&1; }

SNAP="$TMP/a/proj/.claude/.refactor-snapshot.txt"
SNAP_POST="$TMP/a/proj/.claude/.refactor-snapshot.txt.post"
SNAP2="$TMP/a/proj2/.claude/.refactor-snapshot.txt"

# A2 (dynamic, non-regression companion, already passes today): RFS_FILTER unset -> real
# unfiltered EXIT=9, stdout ran-full. Unaffected by the bug (no filter is ever appended).
( unset RFS_FILTER RFS_FULL; run_capture "$TMP/a/proj" PRE )
EXIT_LINE=$(grep '^EXIT=' "$SNAP")
[ "$EXIT_LINE" = "EXIT=9" ] && grep -qF 'ran-full' "$SNAP" \
  && ok "A2: RFS_FILTER unset -> real unfiltered EXIT=9, stdout ran-full" \
  || bad "A2: RFS_FILTER unset -> real unfiltered EXIT=9, stdout ran-full (got: $EXIT_LINE)"

# A3 (dynamic, non-regression companion, already passes today): RFS_FULL=1 ignores
# RFS_FILTER entirely (this branch never touches RFS_FILTER at all -- structurally cannot
# regress from this plan's fix).
( export RFS_FULL=1 RFS_FILTER=SUBSET; run_capture "$TMP/a/proj" PRE )
EXIT_LINE=$(grep '^EXIT=' "$SNAP")
[ "$EXIT_LINE" = "EXIT=9" ] && grep -qF 'ran-full' "$SNAP" \
  && ok "A3: RFS_FULL=1 ignores RFS_FILTER -> real unfiltered EXIT=9, stdout ran-full" \
  || bad "A3: RFS_FULL=1 should ignore RFS_FILTER (got: $EXIT_LINE)"

# A4 (dynamic, genuine RED now): RFS_FILTER=SUBSET, no RFS_FULL -> real filtered EXIT=0 (not
# the bug's constant 127).
( unset RFS_FULL; export RFS_FILTER=SUBSET; run_capture "$TMP/a/proj" PRE )
EXIT_LINE=$(grep '^EXIT=' "$SNAP")
[ "$EXIT_LINE" = "EXIT=0" ] \
  && ok "A4: RFS_FILTER=SUBSET -> real filtered EXIT=0 (not the bug's constant 127)" \
  || bad "A4: RFS_FILTER=SUBSET should give real filtered EXIT=0 (got: $EXIT_LINE)"

# A5 (dynamic, genuine RED now): same run's stdout shows ran-subset (filter reached the
# runner's $1, landed on the same command line), not ran-full (the unfiltered branch the bug
# actually executes because the filter fell on a bogus second line instead).
grep -qF 'ran-subset' "$SNAP" \
  && ok "A5: RFS_FILTER=SUBSET -> stdout shows ran-subset (filter landed on the same line)" \
  || bad "A5: RFS_FILTER=SUBSET -> stdout should show ran-subset (filter reached the runner)"

# A6 (dynamic, genuine RED now, POST path): the identical defect is fixed on the POST branch
# too (SPEC names "both PRE and POST" as symptomatic; same EXEC_CMD-building code path).
( unset RFS_FULL; export RFS_FILTER=SUBSET; run_capture "$TMP/a/proj" POST )
EXIT_LINE=$(grep '^EXIT=' "$SNAP_POST")
[ "$EXIT_LINE" = "EXIT=0" ] \
  && ok "A6: POST capture, RFS_FILTER=SUBSET -> real filtered EXIT=0" \
  || bad "A6: POST capture, RFS_FILTER=SUBSET should give real filtered EXIT=0 (got: $EXIT_LINE)"

# A7 (dynamic, genuine RED now): RFS_FILTER=SUBSET against a runner whose FILTERED subset
# genuinely fails -> real EXIT=4 propagates faithfully (not the bug's constant 127, and not a
# false-positive 0 from an over-eager fix).
( unset RFS_FULL; export RFS_FILTER=SUBSET; run_capture "$TMP/a/proj2" PRE )
EXIT_LINE=$(grep '^EXIT=' "$SNAP2")
[ "$EXIT_LINE" = "EXIT=4" ] \
  && ok "A7: RFS_FILTER=SUBSET, real failure -> real EXIT=4 propagates faithfully" \
  || bad "A7: RFS_FILTER=SUBSET, real failure should give real EXIT=4 (got: $EXIT_LINE)"
```

**Expected now (RED), verified by live execution during planning:** A1 fails (marker absent).
A2 passes (`EXIT=9`, `ran-full` — already correct, unfiltered path untouched by the bug). A3
passes (`EXIT=9`, `ran-full` — `RFS_FULL=1` branch never touches `RFS_FILTER`). A4 fails
(`EXIT=127`, not `0`). A5 fails (stdout has `ran-full`, not `ran-subset`). A6 fails (`EXIT=127` on
the POST snapshot too). A7 fails (`EXIT=127`, not `4`).

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh
bash staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh
# expect: PASS=2 (A2, A3) FAIL=5 (A1, A4, A5, A6, A7)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 2 — GREEN: fix `refactor-snapshot/scripts/capture.sh`

- [x] Insert the trailing-newline strip immediately before `EXEC_CMD` is built.

**Files modified:**
- `staging/plugin/skills/refactor-snapshot/scripts/capture.sh`

**Contract — insert immediately before the current line 53 (`if [ "$RFS_FULL" = "1" ] ...`),
i.e. immediately after line 51 (`RFS_TIMEOUT="${RFS_TIMEOUT:-120}"`):**
```bash
# Strip the single trailing newline the read loop always appends after the last accepted
# command line (bash 3.2-safe ANSI-C quoting; verified against this exact bash build).
# Without this, appending RFS_FILTER below lands it on a NEW line -- bash -c then runs it as
# a second, separate command (typically "command not found"), and the LAST command's exit
# status becomes EXIT_CODE below, masking the real, filtered suite result behind an unrelated
# failure every time RFS_FILTER is set.
CMD_CONTENT="${CMD_CONTENT%$'\n'}"
```
Do **not** touch the read loop (lines 32-41), the empty-content check (lines 43-46), or any of
the three timeout branches (lines 66-88) — they already share one `EXEC_CMD` variable, so fixing
its construction once, upstream of all three, is sufficient.

**Expected (GREEN):** A1, A4, A5, A6, A7 pass; A2, A3 unchanged (were already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh
# expect: PASS=7 FAIL=0 (Section A complete; Sections B/C not yet added)
bash -n staging/plugin/skills/refactor-snapshot/scripts/capture.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/refactor-snapshot/scripts/capture.sh   # empty
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 3 — RED: Section B — `enumerate-sources.sh` glob-override fixtures

- [x] Append Section B's six assertions to `refactor-snapshot-deep-refactor.test.sh` (genuine RED
  for B3, B5; non-regression companions B1, B2, already passing; accidental-pass-today-for-the-
  wrong-reason companions B4, B6 — see "Why every RED in this plan is genuine RED" above for why
  B4/B6 are not evidence of correctness at this checkpoint).

**Files modified:**
- `staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh` (append).

**Contract — insert verbatim, after Section A:**
```bash
# =====================================================================================
# Section B -- Finding 3.8: deep-refactor enumerate-sources.sh glob path-override
# =====================================================================================

# Fixture: a small git repo mirroring the shape of the existing (non-hermetic)
# enumerate-sources.test.sh fixture, plus a generated file inside Sources/ to test that
# exclusion still composes correctly under BOTH override forms (B6).
REPO="$TMP/b/repo"
mkdir -p "$REPO/Sources/App" "$REPO/Sources/Models" "$REPO/OtherSources"
git -C "$REPO" init -q
git -C "$REPO" config user.email "test@test.local"
git -C "$REPO" config user.name "Test"
printf 'x\n' > "$REPO/Sources/App/normal.swift"
printf 'x\n' > "$REPO/Sources/App/auto.generated.swift"
printf 'x\n' > "$REPO/Sources/Models/Model.swift"
printf 'x\n' > "$REPO/AppDelegate.swift"
printf 'x\n' > "$REPO/OtherSources/Other.swift"
git -C "$REPO" add -A >/dev/null
git -C "$REPO" commit -q -m init

# B1 (non-regression companion, already passes today): directory-literal override "Sources/"
# excludes a top-level file outside Sources/.
OUT=$(bash "$ENUM_SH" "$REPO" "Sources/")
printf '%s\n' "$OUT" | grep -qF "AppDelegate.swift" \
  && bad "B1: override 'Sources/' should exclude AppDelegate.swift" \
  || ok "B1: override 'Sources/' excludes AppDelegate.swift (directory-literal prefix intact)"

# B2 (non-regression companion, already passes today): same override excludes a sibling
# directory sharing a name prefix (same-prefix false-positive guard).
printf '%s\n' "$OUT" | grep -qF "OtherSources/Other.swift" \
  && bad "B2: override 'Sources/' should exclude OtherSources/Other.swift" \
  || ok "B2: override 'Sources/' excludes OtherSources/Other.swift (no same-prefix leak)"

# B3 (dynamic, genuine RED now): bare glob override "*.swift" returns the fixture's swift
# files, across nested directories -- the exact named regression (SPEC finding 3.8).
OUT_GLOB=$(bash "$ENUM_SH" "$REPO" "*.swift")
printf '%s\n' "$OUT_GLOB" | grep -qF "Sources/App/normal.swift" \
  && ok "B3: override '*.swift' returns nested swift files" \
  || bad "B3: override '*.swift' should return the fixture's swift files (got: $OUT_GLOB)"

# B4 (accidental-pass-today-for-the-wrong-reason companion; see plan header): override "*.py"
# (zero .py files exist in the fixture) returns empty cleanly, proving the fix discriminates
# correctly rather than degenerating into "match everything".
OUT_NOPY=$(bash "$ENUM_SH" "$REPO" "*.py")
[ -z "$OUT_NOPY" ] \
  && ok "B4: override '*.py' (no matches) returns empty, not an error or overbroad match" \
  || bad "B4: override '*.py' should return empty (got: $OUT_NOPY)"

# B5 (dynamic, genuine RED now): scoped glob override "Sources/*.swift" matches nested files
# under Sources/ AND still excludes a top-level, non-Sources file -- proves directory-scoping
# composes correctly with a glob wildcard (case-pattern matching crosses "/").
OUT_SCOPED_GLOB=$(bash "$ENUM_SH" "$REPO" "Sources/*.swift")
printf '%s\n' "$OUT_SCOPED_GLOB" | grep -qF "Sources/App/normal.swift" \
  && ok "B5: override 'Sources/*.swift' matches nested Sources/ swift files" \
  || bad "B5: override 'Sources/*.swift' should match nested files (got: $OUT_SCOPED_GLOB)"
printf '%s\n' "$OUT_SCOPED_GLOB" | grep -qF "AppDelegate.swift" \
  && bad "B5b: override 'Sources/*.swift' should NOT match top-level AppDelegate.swift" \
  || ok "B5b: override 'Sources/*.swift' correctly excludes top-level AppDelegate.swift"

# B6 (structurally-guaranteed-both-ways companion; see plan header): a *.generated.swift file
# inside Sources/ stays excluded under the directory-literal override too (exclusion is
# applied upstream of the override step in both old and new code -- included here purely for
# CI-visible coverage, since the equivalent $HOME-coupled test never runs in CI).
printf '%s\n' "$OUT" | grep -qF "auto.generated.swift" \
  && bad "B6: override 'Sources/' should still exclude auto.generated.swift" \
  || ok "B6: override 'Sources/' still excludes auto.generated.swift (exclusion composes)"
```

**Expected now (RED), verified by live execution during planning:** B1, B2 pass (`AppDelegate.
swift`/`OtherSources/Other.swift` correctly excluded already today). B3 fails (empty output
today). B4 passes (empty today, for the wrong reason — see header note). B5 and B5b: B5 fails
(empty output today, so the nested-match check fails); B5b passes vacuously (nothing at all is
returned today, so `AppDelegate.swift` is trivially "not present" — re-verify this is a *real*
pass after Task 4, not another vacuous one, since after the fix the output is non-empty and B5b
must still hold against real content). B6 passes (generated file already excluded today).

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh
bash staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh
# expect: PASS=11 (7 Section A + B1, B2, B4, B6) FAIL=2 (B3, B5) -- B5b tallies inside the B5
# dynamic pair and is counted separately in the raw PASS/FAIL total, i.e. Section B shows
# PASS=5 (B1,B2,B4,B5b,B6) FAIL=1 (B3) at this checkpoint if B5b's vacuous pass is counted at
# face value -- re-verify the actual printed counts match this reasoning exactly; if B5b does
# not vacuously pass as reasoned, stop and reconcile before Task 4.
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 4 — GREEN: fix `deep-refactor/scripts/enumerate-sources.sh`

- [x] Replace the header usage comment and the path-override application block with the unified
  `case`-pattern matching engine.

**Files modified:**
- `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh`

**Contract — replace the header usage comment (current lines 3-9):**
```bash
#!/bin/bash
# enumerate-sources.sh — list source files for deep-refactor audit
# Usage: enumerate-sources.sh <root> [<path-override>]
#   <root>           path to the root of a git repository
#   <path-override>  optional scope restriction, two supported forms:
#                       - directory/path literal (no *, ?, [ characters): restricts to that
#                         exact path or anything nested below it, e.g. "Sources" or "Sources/Foo"
#                       - shell glob (contains *, ?, or [): matched against the full relative
#                         path via bash case-pattern matching, e.g. "*.swift", "Sources/*.swift"
#                         (matches across "/" -- case matching operates on the literal string,
#                         not filesystem pathname expansion)
```
(Lines 6-9 — Excludes/Output/Exit/blank — are unchanged and immediately follow.)

**Contract — replace the path-override application block (current lines 43-59):**
```bash
# Apply optional path-override if provided. Two supported forms, both matched via bash's
# native `case` pattern engine (no external regex dialect, no ERE-injection surface):
#   1. Directory/path-literal prefix (no glob metacharacters, e.g. "Sources", "Sources/Foo"):
#      restricts to that exact path or anything nested below it.
#   2. Shell glob (contains *, ?, or [ -- e.g. "*.swift", "Sources/*.swift"): matched against
#      the full relative path. `case` pattern matching operates on a literal string (it does
#      not do filesystem pathname expansion), so `*` matches across `/` boundaries -- verified
#      directly against this repository's own bash: `case "Sources/App/x.swift" in *.swift)`
#      matches.
if [ -n "$PATH_OVERRIDE" ]; then
  TMP_SCOPED="$(mktemp)"
  # Strip a single trailing slash so "Sources/" and "Sources" behave identically.
  CLEAN_OVERRIDE="$(printf '%s' "$PATH_OVERRIDE" | sed 's|/$||')"
  case "$CLEAN_OVERRIDE" in
    *[\*\?\[]*)
      # Glob form: match every candidate path against the override pattern as-is.
      GLOB_PAT="$CLEAN_OVERRIDE"
      while IFS= read -r _f; do
        case "$_f" in
          $GLOB_PAT) printf '%s\n' "$_f" >> "$TMP_SCOPED" ;;
        esac
      done < "$TMP_FILTERED"
      ;;
    *)
      # Directory/path-literal form: match the override itself, or anything nested under it.
      DIR_PAT="$CLEAN_OVERRIDE"
      while IFS= read -r _f; do
        case "$_f" in
          "$DIR_PAT"|"$DIR_PAT"/*) printf '%s\n' "$_f" >> "$TMP_SCOPED" ;;
        esac
      done < "$TMP_FILTERED"
      ;;
  esac
  cat "$TMP_SCOPED"
  rm -f "$TMP_SCOPED"
else
  cat "$TMP_FILTERED"
fi
```
Do **not** touch the exclude-globs `grep -v` step (lines 39-41, immediately above this block) or
the trailing `rm -f "$TMP_LIST" "$TMP_FILTERED"` (current line 61) — the override block reads
`$TMP_FILTERED` (already exclusion-applied), unchanged input source.

**Expected (GREEN):** B3, B5, B5b all pass for real now (B5b's Task-3 vacuous pass is superseded
by a real pass against real, non-empty content); B1, B2, B4, B6 unchanged (were already passing,
now passing for the correct reason in B4's case too — the glob engine genuinely discriminates
"no matches" from "broken syntax").

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh
# expect: PASS=13 FAIL=0 (7 Section A + 6 Section B; Section C not yet added)
bash -n staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh   # empty
bash staging/plugin/scripts/tests/enumerate-sources.test.sh 2>&1 | true
# informational only (this is the $HOME-coupled live test, pointed at ~/.claude -- it is NOT
# expected to reflect this staging-only fix unless ~/.claude has separately been synced; do
# not treat its result as a pass/fail gate for this task)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 5 — RED: Section C — `deep-refactor/SKILL.md` Gate 2 DIRTY_TREE fixtures

- [x] Append Section C's five assertions to `refactor-snapshot-deep-refactor.test.sh` (genuine RED
  for C1, C2, C3, C4; C5 a non-regression companion, already passing).

**Files modified:**
- `staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh` (append).

**Contract — insert verbatim, after Section B:**
```bash
# =====================================================================================
# Section C -- Finding 3.9: deep-refactor Gate 2 circuit-breaker DIRTY_TREE conditioning
# =====================================================================================

# extract_gate2_block -- isolates HITL Gate 2's own AskUserQuestion message (bounded between
# the Gate 2 heading and the closing fence), so a marker landing in the WRONG place in the
# file (e.g. only in Gate 0's own, separate, pre-existing DIRTY_TREE warning) is not mistaken
# for a pass.
extract_gate2_block() {
  awk '
    /^### HITL Gate 2 — Commit approval/ { grab=1; next }
    grab && /^```$/ && fence==1 { exit }
    grab && /^```$/ { fence=1; next }
    grab && fence { print }
  ' "$DR_SKILL"
}
GATE2_BLOCK="$(extract_gate2_block)"

# C1 (static, genuine RED now): the old, unconditional 'git checkout -- .' sentence is gone
# from Gate 2's own message.
if printf '%s\n' "$GATE2_BLOCK" | grep -qF "git diff' to inspect; 'git checkout -- .' to revert if unwanted"; then
  bad "C1: old unconditional 'git checkout -- .' sentence is still present in Gate 2"
else
  ok "C1: old unconditional 'git checkout -- .' sentence is gone from Gate 2"
fi

# C2 (static, genuine RED now): a DIRTY_TREE=true conditional branch exists inside Gate 2's
# own message (not merely somewhere else in the file, e.g. Gate 0's separate warning).
printf '%s\n' "$GATE2_BLOCK" | grep -qF '[If DIRTY_TREE=true:]' \
  && ok "C2: Gate 2 has a DIRTY_TREE=true conditional branch" \
  || bad "C2: Gate 2 should have a DIRTY_TREE=true conditional branch"

# C3 (static, genuine RED now): the DIRTY_TREE=true branch documents a non-destructive git
# stash alternative.
printf '%s\n' "$GATE2_BLOCK" | grep -qF 'git stash' \
  && ok "C3: Gate 2's DIRTY_TREE=true branch documents a non-destructive git stash alternative" \
  || bad "C3: Gate 2's DIRTY_TREE=true branch should document a git stash alternative"

# C4 (static, genuine RED now): the safe, clean-tree case keeps its own conditional branch
# with the original suggestion's intent.
printf '%s\n' "$GATE2_BLOCK" | grep -qF '[If DIRTY_TREE=false:]' \
  && ok "C4: Gate 2 has a DIRTY_TREE=false branch retaining the safe suggestion" \
  || bad "C4: Gate 2 should have a DIRTY_TREE=false branch"

# C5 (non-regression companion, already true today, must stay true): the circuit-breaker tag
# and its immediately-surrounding lines are untouched by this fix.
printf '%s\n' "$GATE2_BLOCK" | grep -qF 'CIRCUIT BREAKER FIRED AT: <CIRCUIT_BREAKER_DIMENSION>' \
  && ok "C5: circuit-breaker tag line is unchanged" \
  || bad "C5: circuit-breaker tag line should remain unchanged"
```

**Expected now (RED), verified by live execution during planning:** C1 fails (old sentence is
present verbatim today). C2 fails (no `[If DIRTY_TREE=true:]` marker exists in the Gate 2 block
today). C3 fails (no `git stash` text anywhere in the Gate 2 block today — confirmed by full-block
inspection). C4 fails (no `[If DIRTY_TREE=false:]` marker exists today). C5 passes (tag line
present today, untouched by this plan).

**Checkpoint:**
```bash
bash -n staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh
bash staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh
# expect: PASS=14 (13 prior + C5) FAIL=4 (C1, C2, C3, C4)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 6 — GREEN: fix `deep-refactor/SKILL.md` Gate 2 circuit-breaker text

- [x] Replace line 585 with the `DIRTY_TREE`-conditional pair.

**Files modified:**
- `staging/plugin/skills/deep-refactor/SKILL.md`

**Contract — replace the current line 585 in full:**
```
    Unstaged changes from <CIRCUIT_BREAKER_DIMENSION> are present in the working tree (run 'git diff' to inspect; 'git checkout -- .' to revert if unwanted).
```
with:
```
    Unstaged changes from <CIRCUIT_BREAKER_DIMENSION> are present in the working tree (run 'git diff' to inspect).
    [If DIRTY_TREE=true:]
    This run started with a dirty working tree (Gate 0 warning). The unstaged changes above are
    now a MIX of your own pre-existing edits and this dimension's failed fix attempts --
    'git checkout -- .' would discard both indiscriminately. Inspect 'git diff' file by file and
    revert selectively ('git checkout -- <path>' per file), or run 'git stash' to set everything
    aside non-destructively until you have reviewed it.
    [If DIRTY_TREE=false:]
    This run started from a clean working tree, so 'git checkout -- .' safely reverts these
    unstaged changes if unwanted.
```
The blank line, `[If BASELINE=RED or report-only mode:]` block, and everything else in the
`AskUserQuestion` message (current lines 586-595) are unchanged and immediately follow.

**Expected (GREEN):** C1, C2, C3, C4 all pass for real now; C5 unchanged (was already passing).

**Checkpoint:**
```bash
bash staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh
# expect: PASS=18 FAIL=0 -- full file green (7 Section A + 6 Section B + 5 Section C = 18)
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/deep-refactor/SKILL.md   # empty (not a shell script, but keep the sweep habit)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh
```

---

## Task 7 — Wire `docs-ci.yml`, full regression sweep, bash-safety sweep, scope verification

- [x] Add `refactor-snapshot-deep-refactor` to `docs-ci.yml`'s explicit `shell-tests` list; run
  the full local test-cmd; sweep for bash 3.2/BSD safety; confirm the changed-file set matches
  the Pre-flight "writes are confined to" list exactly.

**Files modified:**
- `.github/workflows/docs-ci.yml`

**Contract — `docs-ci.yml`, append `refactor-snapshot-deep-refactor` as the tenth entry in the
`for t in ...` list (current line 44):**
```
          for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety concept-to-code-bsd-autopilot-gates concept-to-code-manifest-helpers-guards scope-guards refactor-snapshot-deep-refactor; do
```

**Verify (full, repo-wide):**
```bash
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done    # local test-cmd, 10/10 green
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                       # unchanged, exit 0
bash -n staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh   # empty
grep -nF '<<<' staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh   # empty
echo "bash 3.2 / BSD safety: clean"
diff <(git show HEAD:staging/plugin/skills/refactor-snapshot/scripts/capture.sh) staging/plugin/skills/refactor-snapshot/scripts/capture.sh
# manually confirm: only the one-line insertion before the RFS_FULL/RFS_FILTER block changed;
# the read loop, empty-content check, SHA256 detection, and all three timeout branches are
# untouched.
diff <(git show HEAD:staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh) staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh
# manually confirm: only the header comment and the path-override block changed; the
# exclude-globs step, git-repo validation, and trap/cleanup are untouched.
diff <(git show HEAD:staging/plugin/skills/deep-refactor/SKILL.md) staging/plugin/skills/deep-refactor/SKILL.md
# manually confirm: only line 585 (now a DIRTY_TREE-conditional pair) changed; Gate 0, the
# CIRCUIT BREAKER FIRED AT: tag, and every other Gate are untouched.
grep -c "refactor-snapshot-deep-refactor" .github/workflows/docs-ci.yml   # 1, the new tenth entry
git status   # confirm change set matches Pre-flight "writes are confined to" list; nothing under ~/.claude
```

**Report to dispatcher (accumulate for Task 8):**
- Full local `test-cmd` glob result (10/10 files green) pasted verbatim.
- `refactor-snapshot-deep-refactor.test.sh` final tally: expect `PASS=18 FAIL=0`.
- Confirmation each target file's diff touches only the region named in Pre-flight's scoping
  note — nothing else.
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted.

---

## Task 8 — SPEC checkbox update, final report

- [x] Check off SPEC.md's satisfied success criteria and produce the final report for the
  dispatcher.

**Files modified:**
- `SPEC.md` — check off all four success-criteria boxes (Harness test for RFS_FILTER; harness
  test for the `*.swift` glob override; Gate 2 text no longer recommends a tree-wide revert on a
  dirty tree; no file under `~/.claude` modified).

**Report to dispatcher:**
- ADR path: `docs/architecture/ADR-0031-35-refactor-snapshot-deep-refactor.md`.
- Plan path: `docs/superpowers/plans/2026-07-11-35-refactor-snapshot-deep-refactor.md`.
- Spec path: `SPEC.md` (= `docs/specs/35-refactor-snapshot-filter-append-and-deep.spec.md`).
- `refactor-snapshot-deep-refactor.test.sh` final tally (`PASS=18 FAIL=0`) and full local
  test-cmd result (10/10 files green), pasted verbatim from Task 7.
- Explicit flag for the human reviewer: the `$HOME`-coupled skill-local test files
  (`refactor-snapshot/tests/run-tests.sh`, `deep-refactor/tests/{run-tests.sh,
  enumerate-sources.test.sh}`) were confirmed compatible with every fix in this plan but were
  **not executed** as part of Task 7's verification (they test the deployed `~/.claude` copy, out
  of this roadmap's `staging/`-is-source-of-truth scope) — a reviewer who wants to see them
  actually run green against a synced `~/.claude` should do so manually, after a separate
  `sync-to-claude.sh --apply`.
- Explicit flag: the *deployed* copies (`~/.claude/skills/refactor-snapshot/scripts/capture.sh`,
  `~/.claude/skills/deep-refactor/scripts/enumerate-sources.sh`,
  `~/.claude/skills/deep-refactor/SKILL.md`) keep today's defective behavior until a human runs
  `sync-to-claude.sh --apply`.
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — Section A's env-var isolation subshells leaking state across assertions.** Because
  `export`/`unset` inside a `( ... )` subshell does not propagate back to the parent shell, each
  of A2/A3/A4/A6/A7's subshells is independent by construction — but a coder "simplifying" this by
  exporting `RFS_FILTER`/`RFS_FULL` directly in the main script body (outside a subshell) would
  cause later assertions to silently inherit an earlier one's filter setting. **Mitigation:** Task
  1's contract explicitly wraps every dynamic capture.sh call in its own `( ... )` subshell; do not
  flatten this structure for "readability."

- **Risk B — Task 3's B4/B6 accidentally being read as evidence the fix already works.** Both
  tally as PASS at the Task 3 checkpoint, before Task 4's fix lands, for reasons unrelated to
  correctness (B4: the old code returns empty for *any* glob override, matching or not; B6:
  exclusion ordering is unchanged either way). **Mitigation:** the plan header's "Why every RED in
  this plan is genuine RED" section states this explicitly, and Task 3's own contract labels both
  assertions with their category; do not treat Section B's Task-3 PASS count as proof of anything
  beyond B1/B2's already-known-working baseline.

- **Risk C — Task 3's B5b vacuous pass before Task 4 lands.** Because override `Sources/*.swift`
  returns *nothing at all* today, the check "does the output exclude AppDelegate.swift" is
  trivially true (an empty string excludes everything) — this is not evidence B5b's real contract
  holds. **Mitigation:** Task 3's "Expected now (RED)" section states this explicitly; Task 4's
  checkpoint re-confirms B5b passes against real, non-empty content, which is the actual evidence.

- **Risk D — the `case` bracket-expression metacharacter test (`*[\*\?\[]*`) being transcribed
  incorrectly.** Bracket-expression escaping is easy to get subtly wrong (e.g. omitting a
  backslash, or placing `]` first without realizing its special first-position rule) and a wrong
  version could either never detect glob intent (silently falling through to the directory-literal
  branch for every override) or over-detect it. **Mitigation:** this exact bracket expression was
  verified by direct execution during planning (ADR-0031 §2.4) against seven inputs spanning both
  categories; Task 4's checkpoint's B3/B5 assertions are the automated backstop — either failing
  loudly if the detection logic is transcribed incorrectly.

- **Risk E — scope creep into `refactor-snapshot/scripts/pre-runs.sh`, `diff.sh`, or the
  `$HOME`-coupled skill-local test files.** All are adjacent, thematically related, and
  confirmed-safe files a coder might be tempted to "clean up while in the area" (`pre-runs.sh`
  passes `RFS_FILTER` through; the `$HOME`-coupled tests reference the same scripts).
  **Mitigation:** Pre-flight's "do not touch" list is explicit about all of them; Task 7's `git
  status` and targeted `diff`s are the automated backstop.

- **Risk F — the deployed skill keeps all three defects until sync.** Not a defect in this plan's
  own execution, but a real operational risk this plan cannot itself close. **Mitigation:** flagged
  with explicit priority in Task 8's report, matching ADR-0025 through ADR-0030 precedent.

## HITL gates

- No HITL gate inside this plan itself (auto mode; every edit is a scoped, corrective change to an
  existing script or skill-instruction file, or a new, isolated hermetic test file; no destructive
  git operations; every live script invocation in Tasks 1-6 targets a disposable, isolated `mktemp
  -d` fixture, never a real project's `.claude/test-cmd` or `docs/manifests/`).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and
  push remain human-gated, as does the follow-up `sync-to-claude.sh --apply` that would actually
  deploy these fixes (Risk F) — that sync is explicitly out of this plan's scope and requires its
  own separate human action.
- No DB schema change, no permanent deletion, no production migration in this plan — none of the
  invariant HITL triggers beyond the standard commit/push gate apply here.
