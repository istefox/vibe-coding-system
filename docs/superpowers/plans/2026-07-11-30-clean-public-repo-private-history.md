# Plan — clean-public-repo: keep private history out of the public branch

**Date:** 2026-07-11
**ADR:** [ADR-0026](../../architecture/ADR-0026-30-clean-public-repo-private-history.md)
**Spec:** [SPEC.md](../../../SPEC.md) (= `docs/specs/30-clean-public-repo-keep-private-history-o.spec.md`, issue #30)
**Style:** TDD (red → green → checkpoint). Auto mode active, no intermediate HITL inside this plan; commit/push
stay HITL per repo `CLAUDE.md` invariant (see HITL gates). Security note: these are defensive fixes preventing
private-history disclosure — the fix scope is exactly SPEC's three findings, nothing broader (ADR-0026 §3
records every scope boundary considered and rejected).

---

## Why this plan's RED is real RED, not a self-test proxy

Unlike ADR-0024's vendoring plan (no bug existed yet; "RED" there meant proving a checker against a synthetic
fixture), this plan patches three confirmed, traced-through bugs in live scripts. Tasks 1, 3, and 5 each write
assertions that **fail against the current, unmodified code** for a concrete, understood reason (stated in each
task's Contract), then Tasks 2, 4, and 6 apply the minimal fix and the same assertions pass. The one exception
is Finding 2 (Task 5/6): its tests are static source-anchors, not live execution (ADR-0026 §2.4/§3.5 —
`git-filter-repo` gates every mode of `surgical-rewrite.sh` behind an unconditional version check, and is
confirmed absent on this machine and uninstalled in CI), but they are still genuine RED→GREEN: the anchor greps
fail against the current source and pass only once the fix is applied, they are just source-level rather than
behavior-level assertions.

## Fixture and path conventions (read once, applies to every task below)

- **New test file:** `staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh`. Path derivation
  mirrors `pairs-completeness.test.sh` exactly:
  ```bash
  SCRIPTS=$(cd "$(dirname "$0")/.." && pwd)          # staging/plugin/scripts
  STAGING=$(cd "$SCRIPTS/../.." && pwd)                # staging/
  SKILL_DIR="$STAGING/plugin/skills/clean-public-repo"
  FRESH_HISTORY="$SKILL_DIR/scripts/fresh-history-publish.sh"
  SURGICAL_REWRITE="$SKILL_DIR/scripts/surgical-rewrite.sh"
  DETECT_TRACES="$SKILL_DIR/scripts/detect-tool-traces.sh"
  SKILL_MD="$SKILL_DIR/SKILL.md"
  ```
  Zero `$HOME` dependency anywhere in the file — it must run identically in CI (`ubuntu-latest`, no `~/.claude`)
  and locally.
- **PASS/FAIL idiom:** same as `pairs-completeness.test.sh` — `PASS=0; FAIL=0`, `ok() { PASS=$((PASS+1)); echo
  "PASS: $1"; }`, `bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }`, final line `PASS=$PASS FAIL=$FAIL`, exit
  status `[ "$FAIL" -eq 0 ]`.
- **Live fixtures (Sections A, B):** every fixture is built under its own `mktemp -d` **TESTROOT**, with the
  actual git repo one level *inside* it (`FIXTURE="$TESTROOT/repo"`, `mkdir -p "$FIXTURE"`, `git -C "$FIXTURE"
  init -q`). This makes `dirname "$FIXTURE"` == `$TESTROOT`, fully isolated from the shared system tmp root and
  from every other test's fixture, so "does the backup land outside the fixture" can be asserted with a simple
  `find "$TESTROOT" -maxdepth 1 -name '.git-backup-*.tar.gz'` with zero cross-test collision risk. One
  `trap 'rm -rf "$TESTROOT_A1" "$TESTROOT_A2" ... ' EXIT` at the top of the file cleans up every fixture
  regardless of where the script exits.
- **Git identity:** every fixture sets `git config user.email t@example.com` and `git config user.name Test`
  before committing (same as the vendored `tests/run-tests.sh`'s own fixtures, e.g. its `t13_noremote` case);
  `git init -q` (quiet, matches existing precedent).
- **Section C (static anchors):** plain `grep` against `$SURGICAL_REWRITE` and `$SKILL_MD` file contents. No
  subprocess execution of `surgical-rewrite.sh`, no fixture needed.
- **Per-task checkpoint (three checks, all must pass before moving to the next task):**
  1. `bash -n staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` (and, once created, `bash -n`
     on whichever of the three patched scripts changed this task).
  2. `grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' <changed-file>` — must be empty, for every file
     touched this task (bash 3.2 / BSD-safety gate, same idiom as ADR-0024's plan). This does not itself
     check for here-strings (`<<<`) or process-substitution reads; treat "no `<<<`, no `<(`" as a hard rule to
     write against, not only what the grep happens to catch (the grep is a fast net, not the full spec).
  3. `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` — must stay `PASS=107 FAIL=0` (unchanged;
     this plan adds zero PAIRS entries, ADR-0026 §2.5). Any deviation from 107 signals accidental out-of-scope
     drift into `sync-to-claude.sh`.

## Pre-flight constraints

- Confirmed baseline before Task 1 (re-verify, do not assume from the ADR): `pairs-completeness.test.sh` →
  `PASS=107 FAIL=0`; all of `phase1.test.sh`, `prep.test.sh`, `hook-probe.test.sh`,
  `hook-verify-workflow.test.sh` → exit 0.
- `git filter-repo --version` is expected to fail on this machine (confirmed absent during planning,
  2026-07-11) — this is expected, not a setup error; do not attempt to install it (ADR-0026 §3.5 rejects this).
- Writes are confined to: `staging/plugin/skills/clean-public-repo/scripts/fresh-history-publish.sh`,
  `staging/plugin/skills/clean-public-repo/scripts/surgical-rewrite.sh`,
  `staging/plugin/skills/clean-public-repo/scripts/detect-tool-traces.sh`,
  `staging/plugin/skills/clean-public-repo/SKILL.md`,
  `staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` (new file),
  `.github/workflows/docs-ci.yml`, `SPEC.md` (checkbox updates, final task),
  `docs/architecture/`, `docs/superpowers/plans/` (already written by this ADR/plan pass).
- Do not touch: `staging/sync-to-claude.sh` (no PAIRS changes needed, ADR-0026 §2.5), `docs/RUNBOOK.md` (no
  changes needed, same section), `staging/plugin/skills/clean-public-repo/tests/run-tests.sh` (targets deployed
  `$HOME/.claude/...` paths by design; extending it was considered and rejected, ADR-0026 §3.6 Alternative B —
  do not add assertions there for this issue), any file under `~/.claude`.
- SKILL.md edits are scoped exactly to: lines 249-262 (Finding 1's "Mandatory backup" step) plus one appended
  bullet in "Safety notes" (~lines 277-282), and lines 354-355 (Finding 2's stale claim). Do **not** touch the
  surgical-rewrite "Flow" section's own backup-command example (~line 311) — deliberately left alone, ADR-0026
  §3.4.

## Anchor invariants (HARD — must stay true after every task)

- `bash staging/plugin/scripts/tests/phase1.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/prep.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/hook-probe.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/hook-verify-workflow.test.sh` → exit 0.
- `bash staging/plugin/scripts/tests/pairs-completeness.test.sh` → `PASS=107 FAIL=0` (never changes across this
  plan).
- `git status` shows changes only under the Pre-flight "writes are confined to" list. Nothing under `~/.claude`
  is ever touched.

---

## Task 1 — RED: Finding 1 fixture harness + failing assertions (backup-outside-work-tree, hard-fail guard)

**Files created:**
- `staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` (scaffold: shebang, header comment
  describing all three sections up front, path derivation per "Fixture and path conventions," PASS/FAIL idiom,
  Section A only for this task).

**Contract — Section A, 5 tests:**
- **A1 (clean fixture, prepare succeeds, backup lands outside).** Build a one-commit fixture (`file.txt`).
  Run `bash "$FRESH_HISTORY" "$FIXTURE" prepare` (capture exit code and stdout+stderr). Assert: exit code is
  `0`; `find "$FIXTURE" -maxdepth 1 -name '.git-backup-*.tar.gz'` is empty (no backup inside the work tree);
  `find "$TESTROOT" -maxdepth 1 -name '.git-backup-*.tar.gz'` is non-empty (backup exists one level up, i.e.
  outside the work tree). **Expected now (RED):** the inside-check finds a match (bug present) and/or the
  outside-check finds nothing — assert both directions explicitly so the failure mode is unambiguous in the
  test's own output.
- **A2 (subdirectory ROOT still resolves the true top-level).** Same fixture shape, but create a subdirectory
  `"$FIXTURE/sub"` (`mkdir -p`, no need to add/commit anything in it) and invoke
  `bash "$FRESH_HISTORY" "$FIXTURE/sub" prepare`. Assert the backup lands in `$TESTROOT` (the true repo's
  parent), **not** in `dirname("$FIXTURE/sub")` == `"$FIXTURE"` (which is still inside the work tree). **Expected
  now (RED):** the script has no top-level resolution at all yet, so `BACKUP_PATH` is computed from the raw
  `"$FIXTURE/sub"` argument and lands inside `$FIXTURE`.
- **A3 (hard-fail guard fires on a tainted fixture).** Fresh, separate fixture/TESTROOT. Commit `file.txt`
  normally, then — before invoking the script — write an untracked decoy file directly inside the fixture:
  `printf 'decoy' > "$FIXTURE/.git-backup-20260101-000000.tar.gz"`. Run
  `bash "$FRESH_HISTORY" "$FIXTURE" prepare`, capture exit code and combined output. Assert exit code is `5`
  and output contains `SAFETY ABORT` (case-sensitive, matches the planned error message literally). **Expected
  now (RED):** no such guard exists; the script proceeds to its normal success exit (`0`) and prints the
  ordinary "STOP FOR HITL" instructions instead.
- **A4 (non-regression companion — no false positive).** Reuse A1's clean fixture/output (do not re-run the
  script if A1's output was already captured for this same fixture instance; a fresh clean fixture is
  acceptable too). Assert the output contains the phrase `STOP FOR HITL` and exit code is `0`. Note explicitly
  in the test file's comments that this assertion is expected to **already pass today** — it is not a bug
  reproduction, it is a guard against Task 2's fix later becoming an over-broad false-positive trap.
- **A5 (SKILL.md anchor).** `grep -A5 'Mandatory backup' "$SKILL_MD"` (or an equivalent narrow context grep)
  contains a case-insensitive match for `outside`. **Expected now (RED):** the current text has no such wording.

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh   # empty
bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh   # expect PASS=0 FAIL=4, A4 alone passing (real RED for A1/A2/A3/A5)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                 # PASS=107 FAIL=0, unchanged
```

---

## Task 2 — GREEN: Finding 1 fix (`fresh-history-publish.sh`) + SKILL.md mirror

**Files modified:**
- `staging/plugin/skills/clean-public-repo/scripts/fresh-history-publish.sh`
- `staging/plugin/skills/clean-public-repo/SKILL.md`

**Contract (script), exact insertion points against the current file:**
- After the existing "must be a git repository" check (currently ends at the `fi` closing the `exit 2` block,
  original line 36) and before the "Warn if working tree is dirty" section, insert the `GIT_TOPLEVEL`
  resolution block specified in ADR-0026 §2.1 (`git -C "$ROOT" rev-parse --show-toplevel`; `exit 2` with a clear
  message if empty).
- Change the single `BACKUP_PATH="${ROOT}/${BACKUP_NAME}"` assignment (original line 52) to
  `BACKUP_PATH="$(dirname "$GIT_TOPLEVEL")/${BACKUP_NAME}"`. Do not touch `TS`/`BACKUP_NAME`'s assignments or
  the dry-run block's printed `tar -czf "${BACKUP_PATH}" ...` line — both already reference the shared variable
  and need no further edit.
- After the existing `git add -A` step inside `prepare` mode (original lines 132-138) and before the "STOP —
  HITL required" block, insert the hard-fail guard from ADR-0026 §2.1 (`git ls-files | grep -E
  '(^|/)\.git-backup-.*\.tar\.gz$'`; on match, print `SAFETY ABORT`, list the offending path(s), `exit 5`; on
  no match, print a one-line confirmation and continue).
- Update the file's own header "Exit codes" comment block to add `5 — safety abort: a .git-backup-*.tar.gz
  path was staged (would leak private history)`.
- Optional, low-risk parity addition: extend the `dry-run` mode's printed plan with one line noting the safety
  check `prepare` will run (does not change dry-run's exit code or existing lines, purely additive).

**Contract (SKILL.md), exact scope:**
- Lines 249-253 (the "Mandatory backup" numbered step): reword per ADR-0026 §2.1's SKILL.md mirror — state the
  backup is written outside the work tree and why, update the illustrative `tar` command to show an
  outside-work-tree destination, add a one-line mention that `prepare` hard-fails (exit 5) if a
  `.git-backup-*.tar.gz` path is ever found staged.
- "Safety notes" list (~lines 277-282): append one new bullet stating the same two-layer guarantee (relocation
  + hard-fail) in the section's existing bullet style.
- No other line in SKILL.md changes for this task.

**Expected (GREEN):** Task 1's Section A assertions all pass (A1-A5), with A4 unchanged (was already passing).

**Checkpoint:**
```
bash -n staging/plugin/skills/clean-public-repo/scripts/fresh-history-publish.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/clean-public-repo/scripts/fresh-history-publish.sh   # empty
bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh   # Section A: PASS=5 FAIL=0
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 3 — RED: Finding 3 failing assertions (SHA-matching, `core.abbrev=8`)

**Files modified:**
- `staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` (append Section B, 2 tests).

**Contract:**
- **B1 (the real bug, `core.abbrev=8`).** Fresh fixture/TESTROOT. `git -C "$FIXTURE" config core.abbrev 8`.
  Two commits: first plain (`a.txt`), second with a real trailer in its message body
  (`printf 'second commit\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n'` as the `-m` argument, or an
  equivalent multi-line commit message). Compute `EXPECTED_SHA=$(git -C "$FIXTURE" log -1 --format=%h HEAD)` and
  assert `${#EXPECTED_SHA}` is exactly `8` (fixture sanity check — proves the fixture actually forces the >7
  scenario the bug needs, fail loudly and distinctly if git's abbreviation behavior ever changes). Run
  `bash "$DETECT_TRACES" "$FIXTURE"`, extract the `commit-trailer` line matching `Co-Authored-By`, take field 3
  (`cut -d'|' -f3`) as `REPORTED_SHA`. Assert `REPORTED_SHA` equals `EXPECTED_SHA`. **Expected now (RED):**
  traced through the current regex (ADR-0026 §1) — `REPORTED_SHA` is empty, not equal to `EXPECTED_SHA`.
- **B2 (non-regression companion, natural ~7-char default).** Fresh fixture, no explicit `core.abbrev` (rely on
  git's own default), single commit with a trailer in the message. Assert the reported SHA is non-empty and
  equals `git log -1 --format=%h`. Note in the test's comments that `{7,40}` is mathematically guaranteed to
  still match anything `{7}` matched (superset), so this is expected to **already pass today** — included as an
  explicit, cheap, visible check rather than left as an implicit assumption.

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh
bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh   # Section A: 5/5 green (Task 2 already landed); Section B: PASS=1 FAIL=1 (B1 red, B2 already green)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                 # PASS=107 FAIL=0
```

---

## Task 4 — GREEN: Finding 3 fix (`detect-tool-traces.sh`)

**Files modified:**
- `staging/plugin/skills/clean-public-repo/scripts/detect-tool-traces.sh`

**Contract:** single-line change at line 198 (ADR-0026 §2.3):
```
-    MAYBE_SHA=$(echo "$LOG_LINE" | grep -Eo '^[0-9a-f]{7} ')
+    MAYBE_SHA=$(echo "$LOG_LINE" | grep -Eo '^[0-9a-f]{7,40} ')
```
No other line in this file changes. Do not touch the `SKILL.md` illustrative example (ADR-0026 §2.3 / Neutral
consequence — out of scope, SPEC does not name it). Do not extend the vendored, deployed-path-targeting
`staging/plugin/skills/clean-public-repo/tests/run-tests.sh` either: its two `detect-tool-traces.sh` cases
(#16 the `claude-sdk` dependency guard, #21 the doc-mention/backtick guard) both exercise the **working-tree
file** scanning path, not the **commit-message** scanning path this fix touches — they would not have caught
this bug and are not a meaningful regression check for it; this plan's own Section B (Task 3) is the correct
and sufficient coverage.

**Expected (GREEN):** Task 3's Section B assertions both pass (B1 now green, B2 unchanged).

**Checkpoint:**
```
bash -n staging/plugin/skills/clean-public-repo/scripts/detect-tool-traces.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/clean-public-repo/scripts/detect-tool-traces.sh   # empty
bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh   # Sections A+B: PASS=7 FAIL=0
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 5 — RED: Finding 2 failing static anchors (`surgical-rewrite.sh` rollback truthfulness)

**Files modified:**
- `staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh` (append Section C, 7 tests).

**Contract — all 7 are `grep` assertions against `$SURGICAL_REWRITE` (the script source) or `$SKILL_MD`, no
subprocess execution of `surgical-rewrite.sh` (ADR-0026 §2.4/§3.5):**
- **C1.** `grep -F 'BACKUP_PATH="${ROOT}/${BACKUP_NAME}"' "$SURGICAL_REWRITE"` finds **no** match (old buggy
  assignment gone). **Expected now (RED):** matches (bug present).
- **C2.** `grep -F 'dirname "$GIT_TOPLEVEL"' "$SURGICAL_REWRITE"` finds a match (new assignment present).
  **Expected now (RED):** no match.
- **C3.** `grep -E 'ORIGIN_URL=\$\(git -C "\$ROOT" remote get-url origin' "$SURGICAL_REWRITE"` finds a match.
  **Expected now (RED):** no match.
- **C4.** `grep -F 'remote add origin' "$SURGICAL_REWRITE"` finds a match. **Expected now (RED):** no match.
- **C5.** `grep -F 'filter-repo/commit-map' "$SURGICAL_REWRITE"` finds a match. **Expected now (RED):** no match.
- **C6.** `grep -F 'diff ${BACKUP_BRANCH} --stat' "$SURGICAL_REWRITE"` finds **no** match (dead verification line
  removed). **Expected now (RED):** matches (bug present).
- **C7.** `grep -Ei 'live check|do not treat.*verified present|authoritative' "$SKILL_MD"` (or an equivalent
  anchor tied to whatever exact rewording Task 6 lands — pick one distinctive phrase from ADR-0026 §2.2's
  drafted replacement text and grep for it specifically) finds a match near the `git-filter-repo`
  environment-note section. **Expected now (RED):** the current text ("Verified environment (2026-05-23):
  ... PRESENT") does not contain it.

Each assertion is a single `ok()`/`bad()` call per the file's established idiom — do not combine C1-C7 into
fewer, compound checks; each maps to one independently-reviewable line of ADR-0026 §2.2.

**Checkpoint:**
```
bash -n staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh
bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh   # Sections A+B: 7/7 green; Section C: PASS=0 FAIL=7 (all 7 red)
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                 # PASS=107 FAIL=0
```

---

## Task 6 — GREEN: Finding 2 fix (`surgical-rewrite.sh`) + SKILL.md stale-claim reword

**Files modified:**
- `staging/plugin/skills/clean-public-repo/scripts/surgical-rewrite.sh`
- `staging/plugin/skills/clean-public-repo/SKILL.md`

**Contract (script), exact insertion points against the current file:**
- After the existing "must be a git repository" check (original lines 76-80) and before the fresh-clone check
  block, insert the same `GIT_TOPLEVEL` resolution pattern as Task 2 (ADR-0026 §2.2 — identical shape,
  duplicated deliberately per ADR-0026 §4/Negative, not shared via a new helper).
- Change `BACKUP_PATH="${ROOT}/${BACKUP_NAME}"` (original line 121) to
  `BACKUP_PATH="$(dirname "$GIT_TOPLEVEL")/${BACKUP_NAME}"`.
- In Step 2 of apply mode (original lines 177-191), immediately after the existing `CURRENT_BRANCH=$(git -C
  "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)` line, add:
  `ORIGIN_URL=$(git -C "$ROOT" remote get-url origin 2>/dev/null)` with a one-line comment explaining it must be
  captured before Step 3 removes the remote (ADR-0026 §2.2).
- Replace the "STOP — HITL required before force-push" message block (original lines 212-232) per ADR-0026
  §2.2's full specification: remove the `git diff ${BACKUP_BRANCH} --stat` line; add the "rewrites all refs,
  diff against the backup branch is never meaningful" note; add the `filter-repo/commit-map` pointer; add the
  "tar is the sole rollback" statement; add the conditional `ORIGIN_URL`-based `remote add origin` instruction
  (with a manual-fallback branch when `ORIGIN_URL` is empty) immediately before the existing, unmodified
  force-push instructions. Keep the existing "Restore from backup" and final "Orchestrator: present this HITL"
  lines unchanged, at the end of the block.
- No changes to the fresh-clone check, the dry-run mode block, the graceful-degrade check, or any exit code
  (Finding 2's fix introduces no new exit path).

**Contract (SKILL.md), exact scope:** lines 354-355 only — replace the "Verified environment (2026-05-23):
`git-filter-repo` PRESENT..." sentence with the reworded, non-perishable text from ADR-0026 §2.2 (points at the
script's own live `git filter-repo --version` check as authoritative; explicitly states dependency presence is
machine-specific and drifts; keeps the `gitleaks`/`git` notes). Do not touch the surgical-rewrite "Flow"
section's step 2 backup example (ADR-0026 §3.4 — deliberately out of scope for this finding).

**Expected (GREEN):** Task 5's Section C assertions all pass (C1-C7).

**Checkpoint:**
```
bash -n staging/plugin/skills/clean-public-repo/scripts/surgical-rewrite.sh
grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' staging/plugin/skills/clean-public-repo/scripts/surgical-rewrite.sh   # empty
bash staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh   # Sections A+B+C: PASS=14 FAIL=0 (full file green)
for t in phase1 prep hook-probe hook-verify-workflow pairs-completeness; do bash "staging/plugin/scripts/tests/$t.test.sh" || exit 1; done
```

---

## Task 7 — GREEN: CI wiring

**Files modified:**
- `.github/workflows/docs-ci.yml` — append `clean-public-repo-history-safety` to the `shell-tests` job's `for t
  in phase1 prep hook-probe hook-verify-workflow pairs-completeness` list (line 44), becoming `for t in phase1
  prep hook-probe hook-verify-workflow pairs-completeness clean-public-repo-history-safety; do`.

No change needed to `.claude/test-cmd` (the existing `staging/plugin/scripts/tests/*.test.sh` glob already picks
up the new file automatically — confirmed during planning by reading its current, single-line content;
ADR-0026 §2.4).

**Checkpoint:**
```
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # local test-cmd verbatim: 6/6 green
grep -n 'clean-public-repo-history-safety' .github/workflows/docs-ci.yml       # exactly one match, inside the shell-tests `for t in ...` line
```

---

## Task 8 — Final verification, bash-safety sweep, SPEC checkbox update, report

**Files modified:**
- `SPEC.md` — check off the 4 success-criteria boxes (only the ones genuinely satisfied; leave unchecked and
  explain in the report if any is not).

**Verify (full, repo-wide):**
```
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done   # local test-cmd, 6/6 green
bash staging/plugin/scripts/tests/pairs-completeness.test.sh                     # PASS=107 FAIL=0, unchanged
for f in staging/plugin/skills/clean-public-repo/scripts/fresh-history-publish.sh \
         staging/plugin/skills/clean-public-repo/scripts/surgical-rewrite.sh \
         staging/plugin/skills/clean-public-repo/scripts/detect-tool-traces.sh \
         staging/plugin/scripts/tests/clean-public-repo-history-safety.test.sh; do
  bash -n "$f" || exit 1
  grep -nE '<\(|mapfile|declare -A|\$\{[a-zA-Z_]+\^\^\}' "$f" && exit 1
  grep -nF '<<<' "$f" && exit 1
done
echo "bash 3.2 / BSD safety: clean"
npx --yes markdownlint-cli2 "staging/plugin/skills/clean-public-repo/SKILL.md"   # expect exit 0 (already-ignored subtree per ADR-0024 §2.5)
git status   # confirm change set matches Pre-flight "writes are confined to" list; nothing under ~/.claude
```

**Report to dispatcher:**
- ADR path, spec path, plan path.
- Confirmation `pairs-completeness.test.sh` stayed at `PASS=107 FAIL=0` throughout (no PAIRS drift).
- New test file's final tally (expect `PASS=14 FAIL=0`, sections A=5, B=2, C=7).
- Full local `test-cmd` glob result (6/6 files green) pasted verbatim.
- Explicit confirmation: zero files under `~/.claude` were created, modified, or deleted during this session.
- Explicit flag, elevated priority: the *deployed* `clean-public-repo` copy at `~/.claude/skills/clean-public-repo/`
  still contains the P1 defect (Finding 1) until a human runs `sync-to-claude.sh --apply` — recommend prompt
  sync given the security-relevant severity (ADR-0026 §4/Negative).
- Confidence declared in chat, not in any deliverable file (repo invariant).

---

## Risk register (for the coder executing this plan)

- **Risk A — `git init` default-branch warnings polluting test output.** Modern git prints an informational
  (non-fatal) note about `init.defaultBranch` to stderr on `git init` without `-b`/`--initial-branch`.
  **Mitigation:** use `git init -q` throughout (matches the vendored `tests/run-tests.sh`'s own fixtures) and
  do not assert on stderr content unless a specific test's contract requires it.
- **Risk B — `git checkout --orphan` inherits the previous branch's index, not an empty one.** Easy to
  mis-design a fixture assuming `git add -A` after `--orphan` starts from a clean slate. **Mitigation:** already
  reasoned through in ADR-0026's planning (a clean fixture's inherited index already matches its clean working
  tree, so `add -A` is a no-op for tracked content and only newly stages genuinely untracked files — exactly
  what A3's decoy file relies on). If a coder's fixture behaves unexpectedly, verify with `git -C "$FIXTURE"
  status --porcelain` immediately after the `--orphan` checkout, before assuming the guard logic is wrong.
- **Risk C — Section C anchors accidentally matching unrelated text.** A loose `grep -F` pattern (e.g. a bare
  `origin` or `commit-map` substring) could false-pass against incidental text elsewhere in a 240-line script.
  **Mitigation:** the exact patterns specified in Task 5 are deliberately tied to specific variable names and
  multi-word literal strings, not generic single words; do not loosen them for convenience.
- **Risk D — scope creep into the surgical-rewrite "Flow" section or the SKILL.md illustrative SHA example.**
  Tempting to "fix while you're in there" for consistency. **Mitigation:** Pre-flight constraints and ADR-0026
  §3.4/§2.3 are explicit that these are deliberately out of scope; `git status` in Task 8 is the backstop.
- **Risk E — the deployed skill stays exploitable until sync.** Not a defect in this plan's own execution, but
  a real operational risk this plan cannot itself close (staging-only scope is this roadmap's established,
  unchanged convention). **Mitigation:** flagged with elevated urgency in Task 8's report so a human sees it
  promptly, not buried in a routine "done" message.
- **Risk F — a future `git-filter-repo` reinstall on this machine silently leaves Section C's live-behavior gap
  uncovered.** Static anchors do not regress even if the tool becomes available again; nobody is currently
  planning to add the conditional-live branch ADR-0026 §3.5 rejected. **Mitigation:** none needed for this plan
  — recorded here only so a future contributor does not assume live coverage exists.

## HITL gates

- No HITL gate inside this plan itself (auto mode, additive/corrective changes, no destructive git operations
  performed by the plan itself — `fresh-history-publish.sh`/`surgical-rewrite.sh` are edited as files, never
  *executed* against this repository's own real history by this plan; every live invocation in Tasks 1-6 targets
  a disposable, isolated `mktemp -d` fixture, never `vibe-coding-system` itself).
- Repo `CLAUDE.md` invariant still applies and is **not** overridden by "auto mode": commit and push remain
  human-gated, as does the follow-up `sync-to-claude.sh --apply` that would actually deploy these fixes (Risk
  E) — that sync is explicitly out of this plan's scope and requires its own separate human action.
- No DB schema change, no permanent deletion, no production migration in this plan — none of the invariant
  HITL triggers beyond the standard commit/push gate apply here.
