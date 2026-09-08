# Implementation plan — Migrate `deep-refactor` out of the vendored PAIRS surface

- **Topic slug:** migrate-deep-refactor-out-of-vendored-pa
- **SPEC:** `/Users/stefer/emdash/worktrees/vibe-coding-system-19f4e0e7/emdash-light-experts-cross-4qo9n/SPEC.md`
  (R-01 … R-14; every id is cited by at least one task below — see §Requirement coverage)
- **ADR:** `docs/architecture/ADR-0197-deep-refactor-migrated-to-istefox-skills.md` (Accepted 2026-09-07)
- **ARCH:** n/a — a repository-structure migration following an already-documented pattern
  (ADR-0087 → ADR-0191 → this), not a new subsystem.
- **Stack:** Bash 3.2 (macOS `/bin/bash`) plus POSIX `grep`/`sed`/`awk`/`diff`. No `mapfile`, no
  associative arrays, no `${var^^}`, no `<<<`, no process substitution. Markdown for the record.

TEST-CMD CANDIDATE: none

TEST-CMD MODE: brownfield

CODER-MODEL CANDIDATE: sonnet

Verification is run by hand, since `.claude/test-cmd` is `NONE` in this repo. The loop every task
below means by "the suite":

```text
for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" >/dev/null || echo "RED: $t"; done
```

---

## Read this first — state measured 2026-09-07 at `46cb127` (rule 13)

**Re-derive it; do not trust this block.** Every count is a snapshot, and this repo has been wrong
on its own numbers before.

```text
ADR-0197 file:                                    FREE (no docs/architecture/ADR-0197* exists)
deployed-only: entries in sync-to-claude.sh:      9  -> 10 after Task 3   (DO1 floor is >= 5)
PAIRS lines matching ^(plugin|user)/...|:         ~180 -> ~176 after Task 3 (ZA2 floor is >= 100)
staging/plugin/skills/*/SKILL.md:                 32 -> 31 after Task 6   (floors are >= 25)
staging/plugin/skills/*/ directories:             32 -> 32 (deep-refactor/ survives, SKILL.md-less)
deep-refactor PAIRS lines:                        4, at sync-to-claude.sh:251-254
codex-audit-mode.test.sh:                         44 `ok "CX..."` sites, 38 `# plant:` declarations
`# plant:` decls naming plugin/skills/deep-refactor/SKILL.md:  5  (CX20 CX21 CX22 CX23 CX24)
assertion prefix CR across staging/:              CHECK before using (grep -rnoE '\bCR[0-9]+')
plant-check.sh harness glob:                      "$TESTS"/*.test.sh  == staging/plugin/scripts/tests/
                                                  only. skills/*/tests/ is OUTSIDE it, and outside
                                                  docs-ci.yml's list. `.claude/test-ignore` says so.
docs-ci.yml shell-tests list:                     hand-maintained NAMED list; no file is created or
                                                  deleted by this plan, so NO edit is expected
markdownlint:                                     docs/architecture IS linted; docs/superpowers and
                                                  staging/plugin/skills are IGNORED
markdown links to deleted files:                  0 (grep -rn "](.*deep-refactor" --include="*.md")
```

## Read this second — the observable contracts that move, and every call-site asserting the old one

Two contracts move. The greps were run; the call-sites are listed here, not left to be discovered.

**Contract 1 — `staging/plugin/skills/deep-refactor/SKILL.md` stops existing.**

```text
staging/plugin/scripts/tests/codex-audit-mode.test.sh:243   SKILL_MD=...  (S0 HARD-EXITS 1 if absent:
                                                            all 44 CX assertions die, not just 8)
  :264 SKILL_TEXT   :300,:310 finding-schema extraction (CX10's denominator, CX25)
  :780,:791-794,:802-820,:835-846,:861  CX20 CX21 CX22 CX23 CX24 CX25
  :789,:800,:833,:843,:852               the five # plant: declarations
staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh:38  DR_SKILL -> Section C, C1-C5
staging/plugin/scripts/tests/workflow-dispatch-pins.test.sh:24  DR -> A1 A2 A3
                                            (A1 is NEGATIVE-shaped: with the file gone it PASSES
                                             VACUOUSLY. It must go with A2/A3, not survive.)
staging/plugin/scripts/tests/dispatch-completion.test.sh:44,184,191-192
                                            DISPATCH_SITE_FILES is a `find "$SKILLS"` sweep; DC21 is
                                            a FROZEN EXACT baseline listing deep-refactor-fix-agents
                                            and deep-refactor-reviewers. NOT NAMED BY THE SPEC.
staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh:337
                                            prose disclosure only, no assertion. Leave it (rule 14 —
                                            it is a dated measurement note, not a live claim).
```

Blind by construction and therefore checked by hand after Task 6, not asserted: the `>= 25`
population floors in `skill-coverage-perimeter.test.sh` (S0), `skill-fence-positional-tokens.test.sh`
(SFP1) and `worktree-isolation-contract.test.sh`. All three iterate `*/SKILL.md` and skip a
directory without one, so the retained residue is invisible to them and 31 clears every floor.

**Contract 2 — the four `deep-refactor` PAIRS lines stop existing.**

```text
staging/plugin/scripts/tests/pairs-completeness.test.sh:122  awk-parses the PAIRS block
  :136  check_complete '*/SKILL.md'      -> 31 files, all still covered
  :197  ZA2 count guard >= 100           -> ~176, ample
  :245  DO1 count guard >= 5             -> 10, ample
  :261  DO2 stale-waiver: asserts staging/plugin/skills/deep-refactor/SKILL.md does NOT exist.
        This is why Task 3 and Task 6 MUST land in one commit: waiver-without-deletion is DO2 red.
```

**Not a call-site, and must not become one:** `staging/plugin/scripts/codex-reviewer.sh:206`
(`ENUM="$SCRIPT_DIR/../skills/deep-refactor/scripts/enumerate-sources.sh"`) and its call at `:315`.
ADR-0197 §D11 — `codex-reviewer.sh` is not edited by this plan. `CX08`, `CX09` and `CX32` pin that
resolution and the staging-side existence of the file it names; all three stay green because the
file stays exactly where it is.

**After the whole plan, run the FULL suite, not just the touched harnesses.** Two of the four
harnesses that break were not named by the SPEC, and both were found by grepping the changed
symbol across the corpus rather than by reading the SPEC's list.

---

## Read this third — `spec-coverage.sh` exits 3 on SPEC.md as written; two lines fix it at Gate 2

**Run, not predicted.** Every statement below was produced by executing `spec-coverage.sh` against
this SPEC and this plan on 2026-09-07, including the fixes, against copies in a scratch directory.
An earlier draft of this section predicted a different failure and was wrong (rule 13).

### The gate fails today, before any code exists

```text
$ bash staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh \
    --spec SPEC.md --plan docs/superpowers/plans/2026-09-07-migrate-deep-refactor-out-of-vendored-pa.md \
    --tests-root .
MALFORMED   R-14
ORPHAN      R-14
rc=3
```

Nothing else is evaluated — the structural check aborts the run. The cause is a formatting detail,
not a content defect: **the SPEC parser is strictly line-oriented.** It reads each checklist item's
own line and nothing else, so a `(no-test:` marker's reason is measured only up to the wrap.
R-14's marker sits on its item line with just `verified by` (11 characters) before the line ends,
under the 20-character reason floor → `MALFORMED`, and the id never reaches the coverage loop, so
this plan's citation of it becomes `ORPHAN`.

### The fix: two SPEC lines, at Gate 2, before Step 5 dispatches

1. **R-14** — reflow so the whole clause sits on one line:

   ```text
   - [ ] R-14 — CI is green on all 7 checks on the resulting PR before merge.
     (no-test: verified by observing the PR CI status directly, not a repository-local assertion)
   ```

2. **R-13** — append a `(no-test: ...)` clause on the item's own line, ≥ 20 characters of reason
   after the colon. Without it R-13 reports `UNSCOPED` and the run exits 1: no repository-local
   assertion tests "`plant-check.sh` reports no `BADPLANT`", because `plant-check.sh` is the
   verifier, not a subject.

Verified: with exactly those two edits the gate returns **rc=0, 14 of 14 `COVERED`, 0 uncovered,
0 unscoped, 10 files in scope**.

### Do NOT "fix" R-09, R-10 or R-12 — measured, each one breaks the gate

R-09's `(no-test: ...)` marker sits on a *continuation* line, so the parser never sees it and R-09
is not exempt at all. Moving it onto the item's own line looks like an obvious tidy-up and is a
trap: measured, it turns R-09 into `STALE-WAIVER`, **exit 3, not auto-repaired**. The same happens
if `(no-test:)` is added to R-10 or R-12:

```text
STALE-WAIVER    R-09
STALE-WAIVER    R-10
STALE-WAIVER    R-12
rc=3
```

The reason is rule 18. The `R-NN` namespace restarts per feature, `spec-coverage.sh` greps the bare
token, and these ids occur as *other features'* ids inside harnesses this plan legitimately names.
`R-13` is the only waivable id here precisely because no in-scope file happens to contain that
token. Leave R-09, R-10 and R-12 exactly as they are.

### The 14/14 verdict is over-optimistic, and that is disclosed rather than worked around

The scope filter is a conjunction (ADR-0154 §D1): a file counts only if the plan names it **and**
the file's own text names the plan basename or an ADR id the plan cites. Both harnesses carrying
this feature's new assertions must satisfy half 2 to count at all — which is why Tasks 1 and 2
instruct adding the back-reference — so both enter scope, and so do the legacy harnesses this plan
must name. Censused `grep -ohE '\bR-[0-9]+' <file> | sort -u`:

```text
pairs-completeness.test.sh                R-05  R-09              (ADR-0087's ids, DO2/DO4 comments)
sync-manual-steps.test.sh                 R-03  R-05  R-06  R-17  (ADR-0068's ids)
codex-audit-mode.test.sh                  R-01 … R-11             (ADR-0193's ids)
refactor-snapshot-deep-refactor.test.sh   (none)
workflow-dispatch-pins.test.sh            (none)
dispatch-completion.test.sh               (none)
```

The line-granular negative filter does not help: it drops only lines carrying a *foreign* claim
token (`#<n>` or `ADR-NNNN`) on the same line, and none of these do — e.g.
`pairs-completeness.test.sh:322`, `# DO4 (backward self-test, the R-09 evidence for R-05): ...`.

**A green verdict is therefore not evidence that any of these requirements is tested.** Read Task
8's command output as the evidence.

### The citation policy that converts foreign matches into real ones

Every new assertion header and **every rule-19 deletion comment** cites this feature's own id
together with `ADR-0197`, at the exact site of the change. That is not gaming the tool: it is this
feature's own record, written where the change was made, and it is what a reader needs anyway.

```text
pairs-completeness.test.sh   CR block header      -> R-04, R-11   (the new assertions)
pairs-completeness.test.sh   one line at CI1/CI2  -> R-08         (CI1/CI2 discharge R-08)
sync-manual-steps.test.sh    new section header   -> R-04         (the drift report)
codex-audit-mode.test.sh     rule-19 comments     -> R-03, R-05
refactor-snapshot-deep-refactor.test.sh  §C comment / §B header -> R-06
workflow-dispatch-pins.test.sh           §A comment            -> R-07
dispatch-completion.test.sh              DC21 comment          -> R-05
skills/deep-refactor/tests/enumerate-sources.test.sh  header    -> R-04
```

Never write `R-13` or `R-14` into any test file: both carry `(no-test:)` after the Gate-2 fix, and
a fresh occurrence in an in-scope file is an immediate `STALE-WAIVER`.

### The verdict moves during implementation — re-run after Task 4, not only at the end

`codex-audit-mode.test.sh:773` (`# CX20-CX24 (R-05, R-06, R-07, R-08, R-09, R-10, R-11) — ...`) is
the **only** line in that file carrying R-05 through R-10, and Task 4 deletes it. Ids whose sole
in-scope source it was will flip out of `COVERED` the moment that edit lands. The citation policy
above is what keeps them covered honestly. Re-run `spec-coverage.sh` after Task 4 and again after
Task 7 — the scope set moves on prose changes, in both files.

---

## Batches

Ordering is by dependency, not by convenience. Tasks 5 and 6 **must land in one commit** (see
Contract 2 above). Everything else may be committed per task.

- **Batch A (tester-first, red):** Task 1, Task 2 — new assertions, expected RED.
- **Batch B (coder, green):** Task 3 — the `sync-to-claude.sh` edits that turn Batch A green.
- **Batch C (one commit):** Task 4, Task 5, Task 6 — retire the orphaned assertions, delete the
  vendored files, re-head what survives.
- **Batch D:** Task 7 — the forward record.
- **Batch E:** Task 8 — verification sweep and CI.

---

### Task 1 — Assert the `contract-reference` declaration and the deployed-only residue rule (R-04, R-11)

**Owner:** tester. Expected RED on every new assertion until Task 3.

Add a `CR` block to `staging/plugin/scripts/tests/pairs-completeness.test.sh`, after the
`DEPLOYED-ONLY REGISTRY` block and before the `CI` block. Build the needle at run time
(`CMARK="contract-""reference"`) so the file does not match its own explanatory prose (rule 12) —
the `DMARK`/`ZMARK` lines immediately above are the pattern to copy. Extract via redirection into a
tmp file, never a pipe into `while read` (a piped `while` runs in a subshell and drops the
counters) — the file's own comment at line 237 says so.

Five assertions, ids `CR1`-`CR5` (**confirm the `CR` prefix is free across `staging/` first**:
`grep -rnoE '\bCR[0-9]+' staging/` — if taken, pick another two-letter prefix and keep the ids
fixed-width two-digit, `CR01`…, per `plant-check.sh`'s prefix matching):

- `CR1` — count guard on the derivation (rule 7): `>= 1` `contract-reference:` line parsed.
  Vacuity guard only; say so at the site (rule 10).
- `CR2` — every declared path exists under `$STAGING/`. Same direction as `check_exemptions_live`.
- `CR3` — no declared path appears as a PAIRS `src` (`cut -d'|' -f1 < "$tmp/real-pairs" | grep -qxF`).
- `CR4` — backward self-test for `CR3`: a synthetic one-line fixture declaring a path that **is**
  in PAIRS (use `plugin/scripts/codex-reviewer.sh`), run through `CR3`'s exact logic, asserted
  flagged. Mirrors `DO4`. Without it `CR3` is vacuously satisfiable.
- `CR5` — the reverse direction (rule 8): for every `deployed-only:` name, every file found under
  `$STAGING/plugin/skills/<name>/` must appear as a `contract-reference:` declared path. Use
  `find "$STAGING/plugin/skills/$_dname" -type f` guarded by `[ -d ... ]`; a name with no directory
  contributes nothing and is not an error. Include a count guard on the `deployed-only` derivation
  it reuses, or state at the site that `DO1` already guards it.

Declare a plant for each of `CR1`, `CR3` and `CR5` — the three that assert a mechanism rather than
self-test one — targeting `sync-to-claude.sh` (in `staging/`, therefore inside `plant-check.sh`'s
sandbox). `CR2` and `CR4` are self-tests against synthetic fixtures and are exempt for the same
reason `DO4`/`DO5` are; state that in a comment. A plant replacement may not contain ` | `.

**ADR-0154 §D1:** this file's own text must name either this plan's basename
(`2026-09-07-migrate-deep-refactor-out-of-vendored-pa.md`) or `ADR-0197`. Put both in the `CR`
block's header comment, or the feature's ids report `UNSCOPED` at the coverage gate. Cite `R-04`
and `R-11` in that header, and add one line at the existing `CI1`/`CI2` block recording that those
two assertions discharge this feature's `R-08` (see §Read this third's citation policy). Never
write `R-13` or `R-14` into this file.

- Budget: `staging/plugin/scripts/tests/pairs-completeness.test.sh` (~110 lines)

### Task 2 — Assert the drift report's three states (R-04)

**Owner:** tester. Expected RED on every new assertion until Task 3.

Add a section to `staging/plugin/scripts/tests/sync-manual-steps.test.sh`, reusing that file's
existing hermetic `$HOME` override (`HOME="$TMP/fixture" bash "$SYNC"`, dry run, the script reads
only). Use the next free section letter in that file; do not renumber the existing ones.

Three fixtures, three distinct states (rules 4 and 5):

1. fixture `$HOME` with **no** `skills/deep-refactor/scripts/enumerate-sources.sh` → output
   contains a `DID-NOT-RUN` line naming the path, and **does not** contain a `DRIFT` line.
2. fixture with a **byte-identical** copy of the retained
   `staging/plugin/skills/deep-refactor/scripts/enumerate-sources.sh` → output reports `CLEAN` for
   that file and no `DRIFT`.
3. fixture with a **modified** copy (append one comment line) → output contains `DRIFT` naming the
   file.

Plus the assertion that protects `A3`: in state 1 and state 2, the all-clear line
(`no manual steps outstanding`) must still print — proving the report never sets `MANUAL=1`
(ADR-0197 §D7). This is the assertion that would have caught the obvious wrong implementation.

Declare a plant per state-distinguishing assertion, targeting the report block in
`sync-to-claude.sh`.

**ADR-0154 §D1:** this section's header comment must name `ADR-0197` or this plan's basename, or
the section counts for nothing on the test axis. Cite `R-04` there, and **only** `R-04` — never
type `R-13` or `R-14` into any test file (both carry `(no-test: ...)` after the Gate-2 fix, and a
fresh occurrence in an in-scope file is an immediate `STALE-WAIVER`, exit 3).

- Budget: `staging/plugin/scripts/tests/sync-manual-steps.test.sh` (~90 lines)

### Task 3 — `sync-to-claude.sh`: registry, PAIRS removal, contract-reference block, drift report (R-01, R-02, R-04, R-11)

**Owner:** coder. Turns Tasks 1 and 2 green. Does **not** touch Phase 0's symlink guard.

1. **R-01** — add one line to the `deployed-only` registry, alphabetically **between `daily-open`
   and `impeccable`**, em-dash (`—`) separator, reason ≥ 40 characters. Model it on the
   `project-tasks` entry directly above the target position: name `Developer/Skills/Deep_refactor`,
   `github.com/istefox/Skills`, and `ADR-0197`, and place it in the same class as
   `auto-learning`/`project-tasks`/`website-auditor`.
2. **R-02** — delete the four PAIRS lines at `251-254` (`skills/deep-refactor/SKILL.md`,
   `scripts/enumerate-sources.sh`, `tests/enumerate-sources.test.sh`, `tests/run-tests.sh`). All
   four, including the two whose source files are retained — retained means *not deployed*, and
   `CR3` asserts exactly that.
3. **R-04** — add the `contract-reference:` declaration block. Place it immediately after the
   `deployed-only` registry, with its own explanatory header stating: the two retained paths, that
   they are contract-test references and never deploy sources, that ADR-0077's travel rule cannot
   apply because a marker inside the file would break the byte-diff (ADR-0197 §D5), and that
   `pairs-completeness.test.sh`'s `CR` block derives this registry at run time. Two lines:

   ```text
   # contract-reference: plugin/skills/deep-refactor/scripts/enumerate-sources.sh — <reason>
   # contract-reference: plugin/skills/deep-refactor/tests/enumerate-sources.test.sh — <reason>
   ```

4. **R-04** — add the drift **REPORT** to the report section, immediately after the existing
   `DEPLOYED SKILL REPORT` block. Derive the file list from the `contract-reference:` lines in this
   same script (`grep "^# *contract-reference: "`, the same self-read idiom `DECLARED_SKILLS` uses
   two blocks up — one question, one answer, rule 6). For each declared path compare
   `$STAGING/<path>` against `$DEST/skills/<path-with-plugin/skills/-stripped>` with `diff -q`, and
   print exactly one line per file: `DID-NOT-RUN` (counterpart absent), `CLEAN` (identical), or
   `DRIFT` (differs, naming the `diff -u` command to run and pointing at the live-side probe).
   **Never set `MANUAL=1`, never change the exit code** — the block immediately above it carries
   the same contract and the same ADR-0087 §D3 reason; state that in a comment.

`bash -n staging/sync-to-claude.sh` must be clean. Bash 3.2: no `mapfile`, no `${v^^}`, no `<<<`.

- Budget: `staging/sync-to-claude.sh` (~60 lines changed)

### Task 4 — Retire every assertion that reads the vendored `SKILL.md` (R-05, R-06, R-07)

**Owner:** tester (all four files are under `tests/`, which `test-write-scope.sh` denies the coder).
Lands in one commit with Tasks 5 and 6.

Every deletion leaves a comment where it stood, naming this migration and `ADR-0197` (rule 19).
The comment goes at the site, not in the file header.

- **R-05** `codex-audit-mode.test.sh`: remove the `SKILL_MD`/`SKILL_TEXT` definitions, the `S0`
  half that hard-exits on a missing `SKILL.md` (keep the `codex-reviewer.sh` half and reword `S0`'s
  message), the finding-schema extraction at `:300`/`:310` and everything that consumes
  `FINDING_FIELD_COUNT` / `FINDING_FIELDS_CSV` — **note `CX10` consumes the denominator too, and
  the SPEC does not name it**; decide `CX10`'s fate explicitly rather than leaving it reading an
  empty variable. Remove `CX20`-`CX25` and the **five** `# plant:` declarations at `:789`, `:800`,
  `:833`, `:843`, `:852`. A plant whose needle now matches zero times is `BADPLANT`, not a pass.
  Correct the header's own count claims in place — a live claim, not a historical record — after
  re-deriving them.
  **Do not touch `CX08`, `CX09`, `CX32`**: they read `enumerate-sources.sh`, which is retained.
- **R-06** `refactor-snapshot-deep-refactor.test.sh`: remove Section C (`extract_gate2_block`,
  `C1`-`C5`) and the `DR_SKILL` definition. Leave Sections A and B untouched here; Section B's
  re-heading is Task 6.
- **R-07** `workflow-dispatch-pins.test.sh`: remove Section A entirely — `A1`, `A2` **and** `A3`,
  plus the `DR` definition and the Section-A paragraph in the file header. `A1` is negative-shaped
  (`if grep -q ... "$DR"; then bad; else ok`), so with the file gone it passes *vacuously*; leaving
  it is worse than deleting it (rule 4).
- **R-05** `dispatch-completion.test.sh`: remove `deep-refactor-fix-agents` and
  `deep-refactor-reviewers` from `DC21`'s frozen `EXPECTED` baseline. A shrinking frozen baseline
  is exactly the silent edit ADR-0124 warns about — the rule-19 comment above `EXPECTED` is the
  only record. Check `DC20`'s `>= 10` floor still clears (13 → 11) and that the class/exempt loops
  below `DC21` do not separately name either id.

- Budget: `staging/plugin/scripts/tests/codex-audit-mode.test.sh`,
  `staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh`,
  `staging/plugin/scripts/tests/workflow-dispatch-pins.test.sh`,
  `staging/plugin/scripts/tests/dispatch-completion.test.sh` (~140 lines removed)

### Task 5 — Delete the vendored tree (R-03)

**Owner:** coder. Same commit as Tasks 4 and 6.

`git rm staging/plugin/skills/deep-refactor/SKILL.md staging/plugin/skills/deep-refactor/tests/run-tests.sh`.

Two files, no more. `scripts/enumerate-sources.sh` and `tests/enumerate-sources.test.sh` stay, at
their exact current paths (ADR-0197 §D4). Do not `rm -rf` the directory; do not move anything.

Deletion of tracked files is a HITL gate under the global rules — see §Risks.

- Budget: 2 files deleted (0 lines authored)

### Task 6 — Re-head what survives: the contract test and the live-side probe (R-04, R-06)

**Owner:** tester. Same commit as Tasks 4 and 5.

- **R-06** `refactor-snapshot-deep-refactor.test.sh`: rewrite Section B's header comment so its role
  is stated rather than incidental — Section B is now **the** CI-runnable compatibility contract
  test for `enumerate-sources.sh` (ADR-0197 §D8): offline, hermetic, `mktemp` git fixture, zero
  `$HOME` dependency, pinning the `<root> [<path-override>]` argument shape, both override forms,
  the exclusion set and the empty-output-on-no-match behaviour that `codex-reviewer.sh --mode audit`
  depends on. Fold B6's existing "purely for CI-visible coverage" sentence into the new role
  statement rather than deleting it. Update the file's top-of-file section list, which currently
  describes Section C. **Do not rename the file** — `docs-ci.yml`, ADR-0031 and ADR-0032 name it.
- **R-04** `staging/plugin/skills/deep-refactor/tests/enumerate-sources.test.sh`: keep it pointed at
  `$HOME/.claude/skills/deep-refactor/scripts/enumerate-sources.sh`. Rewrite its header to state its
  new role — the live-side behavioural probe, run by hand when the dry-run report says `DRIFT`, to
  distinguish a cosmetic change from a contract break (ADR-0197 §D9) — and record that it sits
  outside `docs-ci.yml`'s list and outside `plant-check.sh`'s `staging/plugin/scripts/tests/*.test.sh`
  glob by design, as `.claude/test-ignore` already documents. Add a rule-4 guard at the top: if the
  live script is absent, print one `DID-NOT-RUN` line naming the path and `exit 3`, instead of
  producing thirteen `FAIL` lines that read as thirteen contract breaks.
  Note: this file is outside `plant-check.sh`'s perimeter, so no plant is declarable for it. Say so
  in the header rather than leaving the absence unexplained.

- Budget: `staging/plugin/scripts/tests/refactor-snapshot-deep-refactor.test.sh`,
  `staging/plugin/skills/deep-refactor/tests/enumerate-sources.test.sh` (~60 lines)

### Task 7 — Correct the record forward, never in place (R-09, R-10)

**Owner:** doc-writer. Rule 14 throughout: append a dated `## Correction` or a new entry; never
rewrite an existing sentence.

**R-10** is already discharged — `docs/architecture/ADR-0197-deep-refactor-migrated-to-istefox-skills.md`
exists, is parallel in structure to ADR-0191, and records option 1 selected with options 2 and 3
rejected and why. This task **verifies** it (present, Accepted, Alternatives section names A2/A3
with rejection reasons) rather than writing it.

**R-09** — a dated forward correction on each doc whose reference list or claim would now point at
a deleted file. **Confirm each still says what is claimed before editing it**; the SPEC's list was
measured and found to over-claim in four places, recorded here so the same greps are not re-run:

```text
NEEDS a forward correction:
  ADR-0193-codex-review-gate-deep-refactor.md  References list names SKILL.md (~:398) and
                                               enumerate-sources.sh (~:399); §D3 (~:131-140)
                                               describes the staging-side resolution. Add a
                                               dated Correction pointing at ADR-0197.
  ADR-0018-deep-refactor-skill.md              the skill's home ADR; add a Correction stating the
                                               canonical source is now istefox/Skills.
  ADR-0031-35-refactor-snapshot-deep-refactor  References (~:21-24) name all four files, two now
    .md                                        deleted; Section B is now the contract test.
  ADR-0194-codex-substitution-not-extended-to  :25 describes the "SKILL.md, scripts/, tests/"
    -deep-refactor.md                          subtree; :313 References names SKILL.md.
  docs/chain-decisions.md                      append a new `## Decisions from ...` section.
  docs/chain-decision-index.md                 append one ADR-0197 line, same shape as ADR-0191's.
  TODO.md                                      append a NEW entry (next free id is VCS-076 —
                                               re-derive it) recording this migration. Do NOT edit
                                               :134 or :170.

NEEDS NOTHING — measured, do not "fix":
  ADR-0195  mentions deep-refactor only as the rejected comparison case; no path claim.
  ADR-0032-36  two incidental mentions, neither a path claim about the vendored tree.
  ADR-0033 / ADR-0034 / ADR-0035  ZERO deep-refactor mentions. The SPEC read the filename
                                  `ADR-0031-35-...` as a range; it is ADR number 0031, issue 35.
  .claude/test-ignore:34  says the deep-refactor tests dir sits outside the measured perimeter.
                          Still true after this migration, AND a dated measurement record.
                          Rule 14: not edited either way.
  PROJECT.md:107          completed roadmap ledger line for issue #35. Makes no vendoring claim.
  TODO.md:134, :170       completed ledger entries; mention deep-refactor only as a scope note.
```

Markdownlint applies to `docs/architecture` (MD001/MD003/MD009/MD010/MD051 among others) and not to
`docs/superpowers`. Avoid `#anchor` links (MD051 validates fragments).

- Budget: `docs/architecture/ADR-0193-codex-review-gate-deep-refactor.md`,
  `docs/architecture/ADR-0018-deep-refactor-skill.md`,
  `docs/architecture/ADR-0031-35-refactor-snapshot-deep-refactor.md`,
  `docs/architecture/ADR-0194-codex-substitution-not-extended-to-deep-refactor.md`,
  `docs/chain-decisions.md`, `docs/chain-decision-index.md`, `TODO.md` (~120 lines added)

### Task 8 — Full verification sweep and CI (R-08, R-12, R-13, R-14)

**Owner:** tester, then the orchestrator for the CI half.

- **R-08** — verify `.github/workflows/docs-ci.yml`'s `shell-tests` list matches disk. **No edit is
  expected**: this plan creates and deletes no `staging/plugin/scripts/tests/*.test.sh` file, and the
  two deleted files were never in that list, which only ever runs that one directory. The check is
  mechanical and already exists — `pairs-completeness.test.sh` `CI1` (every harness listed or
  `ci-dark-exempt`) and `CI2` (every listed name resolves to a file). Both must be green. If either
  is red, the list is edited to match disk; if both are green, R-08 is discharged with no edit and
  that fact is stated in the commit message.
- **R-12** — the **full** `staging/plugin/scripts/tests/` suite, zero failures. Not just the six
  touched harnesses: two of the four broken by this change (`dispatch-completion`,
  and the population floors) were not in the SPEC's list. Run the loop at the top of this plan.
- **R-13** — `bash staging/plugin/scripts/tests/plant-check.sh` full sweep (run it in the
  background; it takes minutes): exit 0, `SWEEP DONE`, zero `BADPLANT`, zero `NOFIRE`. The five
  CX20-CX24 declarations must be **gone**, not orphaned — a needle matching zero times is
  `BADPLANT`. Confirm the new `CR` and drift plants fire RED as declared, and **inspect what each
  plant actually produced** rather than trusting the summary (rule 2).
- Also run, though no requirement id names them: `bash -n staging/sync-to-claude.sh`;
  `bash staging/sync-to-claude.sh` (dry run) showing no `skills/deep-refactor/*` target, no
  `REFUSED` line for one, and one contract-reference state line per declared file;
  `npx markdownlint-cli2` clean.
- **R-14** — open the PR and confirm all 7 checks green (markdownlint, links, 4 × plant-shard,
  shell-tests) **before** merge. Poll on the printed text, never on `gh pr checks`' exit code:

  ```text
  until [ "$(gh pr checks <N> --json bucket -q '[.[].bucket] | all(. != "pending")' 2>/dev/null)" = "true" ]; do sleep 15; done
  ```

- Budget: no files authored (verification only)

---

## Requirement coverage

| id | cited by |
| --- | --- |
| R-01 | Task 3 |
| R-02 | Task 3 |
| R-03 | Task 5 |
| R-04 | Task 1, Task 2, Task 3, Task 6 |
| R-05 | Task 4 |
| R-06 | Task 4, Task 6 |
| R-07 | Task 4 |
| R-08 | Task 8 |
| R-09 | Task 7 |
| R-10 | Task 7 |
| R-11 | Task 1, Task 3 |
| R-12 | Task 8 |
| R-13 | Task 8 |
| R-14 | Task 8 |

R-09 and R-14 carry `(no-test: ...)` in the SPEC. That marker exempts them from the test axis only,
never from the plan axis — both are cited above like any other id.

## Risks, dependencies and HITL gates

- **BLOCKING, act at Gate 2 before Step 5 dispatches: two SPEC.md line edits.** As written,
  `spec-coverage.sh` exits 3 with `MALFORMED R-14` / `ORPHAN R-14` and evaluates nothing. Reflow
  R-14's `(no-test:)` clause onto one line, and add a `(no-test:)` clause to R-13 on its own line.
  Verified to give rc=0. Full trace and the exact text in §Read this third.
- **Do not tidy R-09's `(no-test:)` marker onto its item line, and do not add `(no-test:)` to R-10
  or R-12.** All three were measured: each produces `STALE-WAIVER`, exit 3, not auto-repaired. The
  marker being invisible to the parser is what currently keeps R-09 out of that state.
- **The `spec-coverage.sh` verdict for this feature is structurally over-optimistic.** It reports
  14/14 `COVERED` before a line of code exists, largely from foreign `R-NN` matches in three legacy
  harnesses. Read Task 8's command output as the evidence, never the coverage table.
- **The coverage verdict moves mid-implementation.** Task 4 deletes the only line in
  `codex-audit-mode.test.sh` carrying R-05 through R-10. Re-run `spec-coverage.sh` after Task 4 and
  after Task 7, not once at the end.
- **HITL — deletion of tracked files (Task 5).** `git rm` of two tracked files is a permanent
  deletion under the global safety rules. Confirm before running.
- **HITL — commit and push (Batches B, C, D) and merge (Task 8).** Auto mode is active for the
  chain's own gates; the commit/push/merge gates are not waived by it.
- **Tasks 4, 5 and 6 must land in one commit.** `DO2` asserts a `deployed-only`-declared name has no
  `staging/plugin/skills/<name>/SKILL.md`. Task 3 adds the declaration; Task 5 removes the file.
  Split across commits, one release sits with `DO2` correctly red.
- **`codex-audit-mode.test.sh`'s `S0` hard-exits 1**, so a partial Task 4 does not degrade — it
  silences 44 assertions at once and the suite still reports a single failure. Re-derive that
  harness's assertion and plant counts after the edit rather than trusting this plan's numbers.
- **`dispatch-completion.test.sh` DC21 and the three population floors were not in the SPEC.** They
  were found by grepping the changed symbol across the corpus. Assume the same is true of anything
  else this plan missed and run the full suite, not the touched subset.
- **The `CR` assertion prefix may already be taken.** Verify before writing (Task 1), and keep ids
  fixed-width two-digit — `plant-check.sh` matches plant ids by *prefix*, so `CR1` beside `CR10`
  collides silently.
- **The drift report reads `$HOME/.claude/`, outside the project root.** That is a runtime read by a
  deploy script that already derives everything from `$HOME`; it is not this session reading outside
  its working directory. It is unverifiable in CI by construction (ADR-0087 §D3) and is therefore a
  report, never a gate.
- **Unvalidated assumption carried from the SPEC:** that `~/.claude/skills/deep-refactor` is today a
  symlink into `/Users/stefer/Developer/Skills/Deep_refactor`. The `sync-to-claude.sh` guard's
  behaviour was verified by reading the code; the symlink itself was not inspected, because it lies
  outside this session's working directory. Confirm with `readlink ~/.claude/skills/deep-refactor`
  before Task 3 — if it is a real directory rather than a symlink, D1's reason text is wrong and the
  whole premise needs re-examining.
- **`plant-check.sh` full sweep is slow** (minutes). Run it with `run_in_background: true`; a
  foreground call is killed at 2 minutes and its output discarded.
