# Implementation plan — `plan-tasks.sh` mode binding (issue #294)

- **ADR:** `docs/architecture/ADR-0131-294-plan-tasks-mode-binding.md`
- **SPEC:** `docs/specs/294-plan-tasks-sh-has-two-modes-with-opposit.spec.md`
- **Requirements:** R-01 (a caller cannot silently pick the wrong mode; checkable, not a header
  sentence), R-02 (both existing call sites still resolve to the mode they use today, asserted),
  R-03 (the exit-3 "did not run" contract preserved for both modes, distinct from a legitimate zero).

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield

---

## Measured facts the tasks depend on

Re-derived from the tree on 2026-08-08. Several differ from the SPEC and from prose in the
repository. **Do not re-trust the numbers in the SPEC over these.**

1. **Three invocations, not two.** Every line under `staging/` that executes the script:
   - `staging/plugin/skills/concept-to-code/SKILL.md`, fence `concept-to-code-step5-plan-structure`
     — `--count` → binds `tasks` (guard)
   - same file, same fence, two lines later — `--count-openers` → binds `openers` (arithmetic)
   - `staging/plugin/skills/autopilot-build/SKILL.md`, fence `autopilot-build-check-5`
     — `--count` → binds `tasks` (guard)
2. **Both `concept-to-code` invocations are in the SAME fence.** The batch-dispatch policy that
   consumes `$openers` is prose roughly nine hundred lines further down and invokes nothing. A
   per-fence declaration therefore cannot work; the unit is the invocation line.
3. **A live rule-12 trap inside `autopilot-build-check-5`:** the non-comment line
   `[ "$rc" -eq 0 ] || { echo "✗ plan: task check did not run (plan-tasks.sh exit $rc)."; exit 1; }`
   names the script and carries no flag. A population defined as "an executable line naming
   `plan-tasks.sh`" reports it as an unbound invocation.
4. **`--count` is a strict prefix of `--count-openers`.** Substring matching attributes invocation 2
   to the guard mode and reports agreement.
5. **R-03 is asserted for one mode only today.** `batch-dispatch-openers.test.sh` `BO3c` exercises
   `--count-openers` against a broken predicate. Grepping all 74 harness files finds **no**
   equivalent for `--count`. The legitimate-zero halves already exist: `PTF2`/`PTE4` for `--count`,
   `BOV1`/`PTJ1` for `--count-openers`.
6. **Counts that have drifted:** harness is **74** `*.test.sh` files (SPEC says 68); plan corpus is
   **65** (`plan-tasks.sh` and `plan-task-predicate.awk` headers say 62, measured 2026-08-03);
   `docs-ci.yml`'s named list holds **74** entries — complete, so **no CI append is needed** as long
   as no new `*.test.sh` file is created. `scope-guards.test.sh` extracts **no** plan-task call site
   (it names `plan-tasks.sh` once in a comment) — do not add assertions there.
7. **Two live harness defects, fixed in Task 6:** `plan-task-count.test.sh` `Z1` tests `>= 48` while
   both its messages say "floor 43"; `batch-dispatch-openers.test.sh` `Z1` tests `>= 16` while both
   its messages say "floor 13".

## Standing constraints for every task

- **Bash 3.2 / BSD-tools clean.** No assoc arrays, no `mapfile`, no process substitution, no `<<<`,
  no GNU-only `sed`/`grep` flags. Write an awk program to a temp file rather than using `/dev/stdin`
  (the convention `plan-tasks.sh` and `spec-coverage.sh` already follow).
- **Never `grep -c … || echo 0`** — it yields the two-line string `0\n0` (issue #174). Use
  `n=$(grep -c . f 2>/dev/null || true); n=${n:-0}`. `PTD1` scans all of `staging/` for this.
- **No `<file>:<digits>` or `line <digits>` cross-references** in anything touched under
  `staging/plugin/skills/` or `staging/plugin/skills/*/scripts/` — `cross-reference-form.test.sh`
  derives over that population. Name a distinctive anchor instead. (`staging/plugin/scripts/tests/`
  is outside that population, but write no line numbers there either.)
- **No new `*.test.sh` file** — that would require a manual append to `docs-ci.yml`'s explicit named
  list. New assertions go into `plan-task-count.test.sh`, which is already named there.
- **Assertion ids must not prefix one another.** `plant-check.sh` decides a plant fired with
  `grep -q "^FAIL: $aid"`, a PREFIX match (the open defect the ADR-0121 entry in `CLAUDE.md`
  records). Use `PTK1` … `PTK9` and **never** a `PTK10` or a `PTK1b`.
- **Plant declarations sit at column 1** (`^# plant:`) or the collector skips them silently (`PC4`).
  Fields are separated by ` | ` and that sequence cannot appear inside a field; the replacement
  cannot contain a newline.

## Batch boundaries (ADR-0101)

Rule 1 — *do not put an assertion in the same batch as the task it depends on* — outranks rule 2.

- **Batch A: Task 1 alone.** Its assertions must be seen RED before anything greens them.
- **Batch B: Tasks 2–4.** The mechanisms. An intermediate checkpoint after Task 2 or Task 3 is
  legitimately red on `PTK2`/`PTK8`; that is the expected-red case "a red in this batch's own tests
  that a later task in the same Step 5 greens".
- **Batch C: Tasks 5–7.**

---

### Task 1 — RED: the mode-binding, denominator and exit-3 assertions (R-01, R-02, R-03)

Add a new section `PTK` to `staging/plugin/scripts/tests/plan-task-count.test.sh`, placed after
section `PTH` and before the `Z1` floor. Nine assertions, ids `PTK1`–`PTK9`.

The section header comment must state, in the file's own idiom, what the mechanism is and what a
green run does **not** mean (ADR-0131 Consequences/negative): a green run means every invocation
declares its question and the declaration agrees with its flag, never that no invocation is used for
the wrong question.

- [ ] `PTK1` — `mode-binding-check.sh` exists at `$(dirname "$0")/mode-binding-check.sh` and is
      invocable by bash, exiting in `0|1|2|3`. Same shape as `F1` in
      `concept-to-code-manifest-helpers-guards.test.sh`. Any other exit is a failure.
- [ ] `PTK2` — the real tree is CLEAN: run the checker with
      `<plan-tasks-script> = $STAGING/plugin/skills/concept-to-code/scripts/plan-tasks.sh` and
      `<population-root> = $STAGING`; require **exit 0 with EMPTY stdout**. *(fix evidence)*
- [ ] `PTK3` — denominator guard, read off the checker's always-printed stderr summary line: parse
      `modes=<n>` and `invocations=<n>` and require `modes >= 2` **and** `invocations >= 3`. A
      derivation that stops resolving reports nothing and reads exactly like a fully bound tree.
- [ ] `PTK4` — fixture (positive twin of `PTK2`): a temp root holding one `.md` file with a fenced
      bash block whose single invocation carries a mode and **no** marker → exit 1 and stdout
      contains `UNBOUND`.
- [ ] `PTK5` — fixture: an invocation using `--count-openers` whose marker declares `guard` → exit 1
      and stdout contains `MISMATCH`. This is the assertion that proves the prefix trap (fact 4) is
      not present: under substring matching the mode resolves to `--count`, the question matches,
      and the checker wrongly reports clean.
- [ ] `PTK6` — fixture: a temp root containing no invocation at all → **exit 3**, not 0. Assert the
      exit code AND that stdout is empty, so "found nothing" cannot be mistaken for "did not run".
      *(R-03's contract, applied to the mechanism itself)*
- [ ] `PTK7` — two fixtures against a **copy** of `plan-tasks.sh`: (a) a copy whose parser gains a
      third `--<word>)` arm with no matching `# mode-contract:` line → `UNCOVERED-MODE`; (b) a copy
      whose parser loses `--count-openers` while the contract line remains → `STALE-CONTRACT`. Never
      mutate the real script.
- [ ] `PTK8` — the per-call-site tuple, **exact counts, not floors** (R-02). Reuse the already
      extracted `$CC_STEP5` and `$AB_BLOCK` fence bodies. Assert:
      `$CC_STEP5` contains exactly one line binding `tasks=` via `--count` with marker `guard`, and
      exactly one binding `openers=` via `--count-openers` with marker `arithmetic`;
      `$AB_BLOCK` contains exactly one line binding `tasks=` via `--count` with marker `guard`.
      Comment at the site that this is exact **because a floor absorbs its own plant** (ADR-0124) and
      that `PTK3`'s `invocations >= 3` is a vacuity guard only — do not consolidate the two.
- [ ] `PTK9` — `--count` against a **broken predicate** exits 3 (R-03). Build it the way `BO3c`
      does: copy `plan-tasks.sh` to a temp dir, write a syntactically invalid
      `plan-task-predicate.awk` beside it, invoke the copy. **Label it explicitly a forward guard,
      not fix evidence** — it passes the day it is written, because the exit-3 branch is shared by
      both modes; its plant is what makes it mean anything. Note in the comment that the
      legitimate-zero twins already exist (`PTF2`/`PTE4` for `--count`, `BOV1`/`PTJ1` for
      `--count-openers`), so this closes the one measured asymmetry rather than a whole class.

**Checkpoint:** run `bash staging/plugin/scripts/tests/plan-task-count.test.sh`. Expected:
`PTK1`–`PTK8` RED, `PTK9` GREEN (labelled). `Z1` will still pass — it is a floor, and Task 6 raises
it. Record the exact RED list; it is this feature's fix evidence.

Budget: `staging/plugin/scripts/tests/plan-task-count.test.sh` (~140 lines)

---

### Task 2 — GREEN: the `# mode-contract:` table in `plan-tasks.sh` (R-01)

Edit `staging/plugin/skills/concept-to-code/scripts/plan-tasks.sh`. **Comments only — stdout, stderr
and every exit code stay byte-identical.**

- [ ] Add two contract lines in the header, before the `set -u`, each with three ` | `-separated
      fields (flag, question, failure direction ≥ 40 characters):
      `# mode-contract: --count | guard | …over-counts by design…safe for a >= 1 malformed-plan guard, wrong for arithmetic.`
      `# mode-contract: --count-openers | arithmetic | …returns 0 on the two corpus plans naming tasks another word…safe for arithmetic that tests for zero, wrong for a guard.`
- [ ] Add a short paragraph above them saying this table is **the** binding: the header prose
      describes it, the table decides, and `mode-binding-check.sh` compares every call site against
      it. Point at the checker by name, never by line number.
- [ ] Trim the existing `THE TWO MODES ARE NOT INTERCHANGEABLE` paragraph so it no longer restates
      the binding in prose beside the table — one answer, one place (ADR-0069 §D2). Keep the measured
      detail (the two named zero-opener plans, the 38/7 figure) which the table's third field
      summarises but does not replace.

**Do not** update the drifted "62 plans" figures — re-dating a measurement requires re-measuring and
the plan corpus is not this issue's subject (ADR-0131 Consequences/neutral).

**Checkpoint:** `bash staging/plugin/scripts/tests/plan-task-count.test.sh` and
`bash staging/plugin/scripts/tests/batch-dispatch-openers.test.sh` — every pre-existing assertion
must be unchanged (`PTE*`, `PTF*`, `PTG*`, `PTH*`, `BO1`, `BO2`, `BO3*`, `BO4`). Comments cannot move
a count; if any of them moves, stop.

Budget: `staging/plugin/skills/concept-to-code/scripts/plan-tasks.sh` (~25 lines)

---

### Task 3 — GREEN: `mode-binding-check.sh`, the derived checker (R-01, R-03)

New file `staging/plugin/scripts/tests/mode-binding-check.sh`. **Not** a `*.test.sh`, so it is
outside `.claude/test-cmd`'s glob, outside `docs-ci.yml`'s list, and outside
`pairs-completeness.test.sh`'s non-recursive `plugin/scripts/*.sh` population — it needs **no**
`PAIRS` entry and has no inert-until-sync failure mode. Model it on
`staging/plugin/scripts/tests/path-rule-check.sh` and `transition-pair-count.sh`.

- [ ] **Header** carrying, in the repository's idiom: `THIS IS A CHECKER, NOT A REPORTER` (the
      caller branches on the exit code; no `CLEAN` sentinel, ever); the exit contract table; the
      finding taxonomy; the residual limit stated flatly (**the marker declares intent and nothing
      verifies the intent is honest — a call site declaring `guard` and feeding the number to
      arithmetic passes**); and the declared population boundaries.
- [ ] **Usage:** `mode-binding-check.sh <plan-tasks-script> <population-root>`. Both are arguments
      so a later issue can retarget it without editing it (ADR-0117 §3.9). Wrong argument count,
      unreadable script or missing root → exit 2.
- [ ] **Mode derivation** from the target script's own argument parser: the `--<word>)` arms of its
      `case`. Never a hardcoded list. Exclude `-h|--help` through a **declared** one-line exemption
      (`# mode-exempt: --help — …`, reason ≥ 40 chars) and emit a finding if that exemption's
      subject is no longer in the parser (a stale waiver reads as clean coverage, ADR-0081 `ZA4`).
      Zero modes derived → **exit 3**.
- [ ] **Contract-table derivation** from the same script's `# mode-contract:` lines, three fields.
      Compare against the derived mode set **in both directions**: a mode with no contract line is
      `UNCOVERED-MODE`; a contract line for a mode the parser does not accept is `STALE-CONTRACT`; a
      third field under 40 characters is `SHORT-REASON`. The question vocabulary is field 2 of these
      lines and exists nowhere else.
- [ ] **Population derivation** over `<population-root>`, executable context only:
      - `*.sh`, excluding `*/tests/*` — lines whose first non-blank character is not `#`;
      - `*.md` — only lines inside a fenced bash block, with the opening fence matched
        **indentation-tolerantly**: allow leading whitespace before the three backticks and the
        word `bash` (ADR-0083 §S3). Again excluding comment lines.
      A line qualifies as an invocation only if it names `plan-tasks.sh` **and** the
      whitespace-delimited token immediately following the path is present. Write the three filters'
      reasons at the site: the comment filter clears the fences' own explanatory comments and this
      script's header (rule 12); the mode-token requirement clears the measured `echo "… (plan-tasks.sh
      exit $rc)"` message string; the `tests/` exclusion clears the harness's `ok`/`bad` message
      strings, which are code and not commentary, and which no comment filter can reach.
      **Zero invocations → exit 3**, with the reason written at that branch.
- [ ] **Mode extraction by EXACT token equality** against the derived set — never a prefix or
      substring match (`--count` is a strict prefix of `--count-openers`). A token matching no
      derived mode is `UNKNOWN-MODE`, a finding, never a skip, so a variable-held flag fails loudly.
- [ ] **Marker extraction** from the invocation line: `# plan-tasks-question: <word>`. Absent →
      `UNBOUND`. Present but naming a word no contract line binds → `UNKNOWN-QUESTION`. Present,
      a real question, but not this mode's → `MISMATCH`, with the expected question named in the
      message.
- [ ] **Always print to stderr, on every run and every exit code:**
      `mode-binding-check: modes=<n> contracts=<n> invocations=<n> bound=<n> findings=<n>`
      (the `path-rule-check.sh` convention — it is what makes the denominator visible to `PTK3`).
- [ ] Findings go to stdout, one per line, each naming file, line number and token. Exit 1 if any.

**Checkpoint:** `PTK1`, `PTK4`, `PTK5`, `PTK6`, `PTK7` go GREEN. `PTK2`, `PTK3`, `PTK8` remain RED —
the markers do not exist yet. `PTK3` may be RED on `invocations` or GREEN on it depending on how the
run reads; either is expected here. Run the checker by hand once and read its stderr summary before
moving on: `invocations` must already be **3**.

Budget: `staging/plugin/scripts/tests/mode-binding-check.sh` (~230 lines)

---

### Task 4 — GREEN: mark the three invocations (R-01, R-02)

- [ ] `staging/plugin/skills/concept-to-code/SKILL.md`, fence
      `concept-to-code-step5-plan-structure`: append `   # plan-tasks-question: guard` to the
      `--count` line and `   # plan-tasks-question: arithmetic` to the `--count-openers` line.
- [ ] `staging/plugin/skills/autopilot-build/SKILL.md`, fence `autopilot-build-check-5`: append
      `   # plan-tasks-question: guard` to its `--count` line (after the existing `; rc=$?`).
- [ ] Add one short comment line inside each fence explaining the marker. **It must not contain the
      literal string `# plan-tasks-question: guard`** — otherwise Task 5's plant needle matches twice
      and `PC2` rejects it. Name the marker without its delimiters, the way `path-rule-check.sh`'s
      own documentation does. It must also contain no `grep -c` (`PTB3` counts those inside these
      two blocks) and no line-number reference.

Trailing comments are inert shell and cannot change a fence's behaviour: a comment is not a command,
so `rc=$?` on the following line still captures the invocation's status. Do **not** touch the
`~/.claude/...` paths — the checker reads the line's text and executes nothing.

**Checkpoint:** all of `PTK1`–`PTK9` GREEN. Then, because these are declared fence contracts:
`bash -n` both extracted fences, and run `bash staging/plugin/scripts/tests/fence-contract-coverage.test.sh`,
`bash staging/plugin/scripts/tests/plan-task-count.test.sh` (`PTC*` and `PTF*` execute these fences)
and `bash staging/plugin/scripts/tests/batch-dispatch-openers.test.sh`.

Budget: `staging/plugin/skills/concept-to-code/SKILL.md`, `staging/plugin/skills/autopilot-build/SKILL.md` (~15 lines)

---

### Task 5 — Plants: declare one per new assertion and verify each fires (R-01, R-02, R-03)

All plant declarations land here, not earlier: a declaration whose needle matches zero times is a
`PC2` failure, and the mechanisms they target do not exist until Tasks 2–4.

- [ ] Add one `# plant:` line per `PTK` assertion, at **column 1**, in
      `plan-task-count.test.sh`'s plant block. Each removes exactly ONE mechanism:
      - `PTK1` → target `plugin/scripts/tests/mode-binding-check.sh`, make it exit outside `0|1|2|3`
        (the `F1` precedent: prepend `exit 42;` to its argument-count guard).
      - `PTK2` → target `plugin/skills/concept-to-code/SKILL.md`, needle
        `# plan-tasks-question: guard`, replacement a renamed marker. Must match exactly once in
        that file.
      - `PTK3` → target the checker's stderr summary so the derived **mode count** prints `0`. It
        must isolate: `PTK2` should still pass under this plant.
      - `PTK4` → the `UNBOUND` detection.
      - `PTK5` → the exact-equality mode comparison, replaced by a prefix match. This plant is the
        one that proves fact 4 is guarded.
      - `PTK6` → the zero-invocation branch's `exit 3`, replaced by `exit 0`.
      - `PTK7` → the uncovered-mode / stale-contract comparison.
      - `PTK8` → target `plugin/skills/concept-to-code/SKILL.md`, rename the `openers=` binding.
      - `PTK9` → target `plugin/skills/concept-to-code/scripts/plan-tasks.sh`, the **awk-failed**
        branch's `exit 3` → `exit 0`. `exit 3` appears three times in that file, so the needle must
        include enough surrounding text to match exactly once.
- [ ] Run `bash staging/plugin/scripts/tests/plant-check.sh`. Every new plant must appear as
      *fired*, and `PC0`/`PC1`/`PC2`/`PC3`/`PC4` must all pass.
- [ ] **For each plant, inspect what it actually produced before believing what it reports**
      (ADR-0090). A plant that fires is not evidence until you have seen the mutated text. Two known
      traps: a replacement cannot contain a newline (a collapsed `echo … exit 0` turns `exit 0` into
      two arguments to `echo` and nothing exits, ADR-0112); and a plant is credited by a **prefix**
      match on `FAIL: <id>`, so confirm no other assertion's failure is being read as this one's.
- [ ] A plant that does not fire is evidence about the **assertion**, not a step to get past. Fix the
      assertion, or record in the plan why the mutation is not the mutation it describes.

---

### Task 6 — `Z1` floors and the two measured message mismatches (R-01, R-02)

- [ ] `plan-task-count.test.sh`: run the file, read the reported total, raise the `Z1` threshold to
      it, and update **both** message strings — the `ok` and the `bad` — to the new number. They
      currently both say "floor 43" against a test of `>= 48`.
- [ ] `batch-dispatch-openers.test.sh`: no assertions are added there, so the threshold stays `16`;
      correct both messages, which say "floor 13".
- [ ] Add a one-line comment at each `Z1` recording why: *when you change a literal in an assertion,
      grep the message strings in the same edit — the message is not covered by the assertion it
      belongs to* (ADR-0120). A passing `Z1` was printing the wrong number, and the next person to
      raise a floor reads the message.
- [ ] Add a one-line pointer beside `BO3c` in `batch-dispatch-openers.test.sh` naming `PTK9` as its
      `--count` sibling, so the pair is discoverable from either side. No new assertion, no floor
      change.

Budget: `staging/plugin/scripts/tests/plan-task-count.test.sh`, `staging/plugin/scripts/tests/batch-dispatch-openers.test.sh` (~20 lines)

---

### Task 7 — Full harness, plant registry, and record what was found (R-01, R-02, R-03)

- [ ] Run the whole suite:
      `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
      A contract change can break assertions in unrelated modules; do not run only the two files
      touched.
- [ ] Run `bash staging/plugin/scripts/tests/plant-check.sh` again after the full suite.
- [ ] Run `bash staging/plugin/scripts/tests/mode-binding-check.sh` by hand against the real tree and
      paste its stderr summary line into the completion report — it is the denominator this whole
      feature rests on.
- [ ] Confirm no new `*.test.sh` file was created (`docs-ci.yml` would need a manual append) and no
      new `PAIRS` entry is required (`bash staging/plugin/scripts/tests/pairs-completeness.test.sh`).
- [ ] Report, as found-not-fixed: the derived-guard instance-number collision (12 is claimed by both
      ADR-0119 and ADR-0125; this feature takes **13**), the drifted corpus counts (62 → 65 plans in
      two script headers, 62 rows in `plan-shape-baseline.tsv`), and the SPEC's own stale figures
      (68 harness files, `scope-guards.test.sh` named as a call-site harness).

---

## Risks

- **The marker declares intent; nothing verifies it.** A green run must never be reported as closing
  #242's semantic class. If the completion report says "the wrong-mode class is closed", it is wrong.
- **Rule 12 has two live subjects here** (fact 3, and the plant needle collision in Task 4). Both are
  handled by explicit instructions above; both are the shape that has bitten this repository six
  times.
- **The `--count` prefix hazard** is invisible to reading and visible only to `PTK5`'s plant.
- **Plant-registry prefix matching (#355)** means a badly chosen id silently borrows another
  assertion's failure. `PTK1`–`PTK9` with no `PTK10` and no letter suffixes avoids it.
- Deployment: only three trailing comments and one comment block reach `~/.claude`. The checker
  cannot deploy. There is no version-skew failure mode.

## HITL gates

- Commit (Gate 4.0 for the planning artifacts; Step 7 for the implementation). Nothing here touches
  a schema, a migration, a deletion, or an external service.
