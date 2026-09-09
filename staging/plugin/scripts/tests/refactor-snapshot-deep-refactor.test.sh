#!/bin/bash
# refactor-snapshot-deep-refactor.test.sh -- findings from the concept-to-code audit
# (SPEC.md / issue #35). Two lettered sections (Section C removed 2026-09-08,
# migrate-deep-refactor-out-of-vendored-pa / ADR-0197, rule 19 -- see the removal note at its
# former site, below):
#   Section A (Finding 2.6, P2, 7 tests) -- refactor-snapshot/scripts/capture.sh's read loop
#     always leaves a trailing newline on CMD_CONTENT, so "$CMD_CONTENT $RFS_FILTER" puts the
#     filter on a NEW line; `bash -c` then runs it as a second, separate (bogus) command, and
#     the LAST command's exit status ($?) is always that bogus command's failure (~127),
#     regardless of the real, filtered suite's actual pass/fail -- silently defeating the
#     harness's own exit-code comparison channel whenever RFS_FILTER is used. Fixed by
#     stripping the single trailing newline before building EXEC_CMD.
#   Section B (6 tests) -- THE CI-runnable compatibility contract test for
#     deep-refactor/scripts/enumerate-sources.sh (R-06, ADR-0197 §D8,
#     migrate-deep-refactor-out-of-vendored-pa): offline, hermetic, mktemp git fixture, zero
#     $HOME dependency, pinning the documented "<root> [<path-override>]" argument shape, both
#     override forms (directory-literal prefix and glob), the exclusion set, and the
#     empty-output-on-no-match behaviour that `codex-reviewer.sh --mode audit` depends on. It
#     was originally written for Finding 3.8: the override was interpolated raw into `grep -E`;
#     a leading `*` (e.g. override "*.swift") has no operand to repeat, an undefined case in
#     POSIX ERE -- no tracked path starts with a literal "*", so the override always returned
#     zero files and Step 0.6 aborted. Fixed with a single, unified bash `case`-pattern matching
#     engine (real glob semantics, no external regex dialect) that also preserves the existing
#     directory-literal-prefix contract unchanged.
# Zero $HOME dependency: runs identically in CI (ubuntu-latest, no ~/.claude) and locally.
# Never point any variable at $HOME/.claude/... -- that is the deployed copy, out of scope.
# Sections A and B invoke the real, staging scripts directly against disposable mktemp
# fixtures (both are standalone executables) -- no fence-extraction machinery is needed here.
# Bash 3.2 clean. Run: bash refactor-snapshot-deep-refactor.test.sh
set -u

SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)              # staging/plugin/scripts
STAGING=$(cd "$SCRIPTS/../.." && pwd)                    # staging/
CAPTURE_SH="$STAGING/plugin/skills/refactor-snapshot/scripts/capture.sh"
ENUM_SH="$STAGING/plugin/skills/deep-refactor/scripts/enumerate-sources.sh"
# DR_SKILL stood here (pointed at deep-refactor/SKILL.md, Section C's only consumer). Removed
# 2026-09-08, migrate-deep-refactor-out-of-vendored-pa / ADR-0197 (rule 19) — see Section C's own
# removal note below.

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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

# =====================================================================================
# Section B -- THE CI-runnable compatibility contract test for
# deep-refactor/scripts/enumerate-sources.sh (R-06, ADR-0197 §D8,
# migrate-deep-refactor-out-of-vendored-pa). Offline, hermetic, mktemp git fixture, zero
# $HOME dependency: pins the documented "<root> [<path-override>]" argument shape, both
# override forms (directory-literal prefix and glob), the exclusion set, and the
# empty-output-on-no-match behaviour that `codex-reviewer.sh --mode audit` depends on. Under
# this ADR that stops being incidental coverage and becomes Section B's declared purpose --
# folding B6's own note below ("included here purely for CI-visible coverage, since the
# equivalent $HOME-coupled test never runs in CI") into this role statement rather than
# deleting it: B6 is why this section is run in full here, not left as incidental overlap.
# Originally written for Finding 3.8: deep-refactor enumerate-sources.sh's glob path-override.
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

# =====================================================================================
# Section C stood here -- Finding 3.9: deep-refactor Gate 2 circuit-breaker DIRTY_TREE
# conditioning (extract_gate2_block(), C1-C5). Removed 2026-09-08,
# migrate-deep-refactor-out-of-vendored-pa / ADR-0197 (rule 19). Section C read
# staging/plugin/skills/deep-refactor/SKILL.md's Gate 2 HITL message, a file this repo no longer
# vendors after this migration (Task 5 of that plan deletes it) -- the design it pinned
# (Gate 2's DIRTY_TREE-conditioned circuit-breaker suggestion) is unreviewable from this
# repository going forward, ADR-0197's own stated cost. Sections A and B above are untouched:
# they exercise refactor-snapshot/scripts/capture.sh and the retained
# deep-refactor/scripts/enumerate-sources.sh, neither of which this migration moves.
# =====================================================================================

printf '\nPASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
