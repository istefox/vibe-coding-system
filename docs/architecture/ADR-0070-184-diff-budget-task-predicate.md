# ADR-0070 — `diff-budget-check.sh`: four defects between a written feature and a working one

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #184
- **Extends:** ADR-0069 (the shared plan-task predicate), ADR-0052 (the budget/scope reporter itself)
- **Reported as:** a measurement taken while designing #172, not a failure anyone observed.

## Context

ADR-0052 shipped a per-task diff budget and scope check in July. It has produced no finding on any
real plan since, and nobody noticed, because it is a reporter: it always exits 0 and prints `CLEAN`
when it has nothing. A plan it cannot parse is indistinguishable from a plan with nothing to report
— and "nothing to report" is the documented, legitimate, overwhelmingly common case (§D1).

ADR-0069 §D5 deferred it deliberately, to keep that change attributable. This is that work, and the
deferral was justified: the predicate turned out to be **one of four** independent defects, three of
which are invisible until the one above them is fixed.

## The four defects, in the order they became visible

**1. The task predicate.** `is_task_line()` required `- [ ] **Task N` — checkbox *and* bold *and*
the literal word. Measured over the 57 plans in `docs/superpowers/plans/`: 18 match. The heading
form that `architect.md` documents and that architects actually write matches none of them.

**2. The budget syntax rejected its own corpus.** With the predicate fixed, all nine `Budget:`
declarations in the one plan that has any still failed to parse. The parser required the
parenthesised line ceiling at strict end-of-line, and the plan writes the whole declaration in
markdown italics:

```
*Budget: `SPEC.md` (~90 lines)*
```

A trailing `*` was enough. ADR-0052 §D6 already calls this syntax "lenient prose, not a rigid
schema", so tolerating trailing emphasis applies that intent rather than widening it.

**3. `git diff --stat` elides long paths.** At the default 80-column width — which is what a pipe
gets — git renders a 63-character path as `.../tests/worktree-isolation-contract.test.sh` as soon
as a second file shares the table. An elided name matches nothing in the declared set, so the file
was reported out of scope **and** its lines went uncounted: wrong in both directions at once.

**4. git right-aligns the count column.** The candidate extractor required a digit immediately
after `" | "`. Every file whose change count has fewer digits than the widest one in the same diff
carries leading spaces there, fails the match, and is **dropped from the candidate set entirely** —
no `SCOPE` finding, and its lines missing from the `BUDGET` total. Silently, and for most files in
any diff with a mixed range of sizes.

Defect 4 is the one worth dwelling on. It survives a correct predicate, a correct budget parse and
an untruncated path. It was found by running the checker on a two-file diff and asking why the
totals were short — not by reading it, and not by any assertion in a harness that had been green
for months.

## Decision

### D1 — `is_task_opener()`, a second predicate, in the same shared file

`plan-task-predicate.awk` gains a function beside `is_task_line()`. The two answer different
questions and both are needed:

| | `is_task_line()` | `is_task_opener()` |
|---|---|---|
| Question | is there a task here | does a task BLOCK START here |
| Caller | `plan-tasks.sh`, `spec-coverage.sh` | `diff-budget-check.sh` |
| Safe failure direction | over-count (guard is `>= 1`) | never over-match (it is a boundary) |
| Corpus match | 56 / 57 | 55 / 57 |

The rule: the task designation must be at the **start** of the line's own content, after the
heading or checkbox marker and an optional `**`. That admits `## Task 1 — …`, `### Task 3 — …`,
`- [ ] **Task 1 — …**` and `- [ ] Task 1 — …`, and rejects `- [ ] Re-run Task 2. Sections A and B
green.` — a sub-step that merely mentions a task, and which as a boundary would close the previous
task's block and steal its budget.

### D2 — Loaded, not copied

`diff-budget-check.sh` was the fourth private copy of a task predicate in this repository and the
strictest. It now loads `plan-task-predicate.awk` with `awk -f`, the mechanism ADR-0069 §D2
established. The count of files that decide what a plan task looks like goes from four to one.

### D3 — Two plans stay unrecognised, exempted by name

`2026-06-06-claude-md-slim.md` writes `### Step 0 —`; `2026-05-30-deep-refactor-skill.md` writes
`### T1 —`. Both predate the `architect.md` contract. Widening to `Step|T[0-9]` was rejected: `## The
T1 approach` would become a task boundary, and the cost lands on every plan to accommodate two
completed ones. Named in `PTG9`, with `PTG10` asserting both files still exist so the exemption
cannot outlive its subject.

### D4 — Trailing markdown emphasis is tolerated in the budget syntax

`/\([^()]*\)[ \t]*[*_`]*[ \t]*$/`. Nothing else about the syntax changes.

### D5 — Both call sites pass `--stat=999`, and the script recovers an elided path anyway

The call sites are the real fix. The in-script recovery — resolve the elided tail against the
declared set, and only when it resolves to exactly one distinct path — exists because a caller that
forgets would otherwise get a confidently wrong answer rather than an obvious failure. Ambiguous
tails are left elided and reported, since a guess is worse than the finding.

The uniqueness test is on **distinct** paths: `MASTER_SCOPE` is the union of every task's declared
list, so a file declared by five tasks appears five times, and a raw line count reads that as
ambiguity. This cost a debugging cycle and is written at the call site.

### D6 — Leading whitespace is stripped from the count field

One `sub(/^[ \t]+/, "", rest)`. See defect 4.

## Alternatives considered

### A — Give `diff-budget-check.sh` the ADR-0069 canonical predicate directly

Rejected, and this is the substance of ADR-0069 §D5's deferral. `is_task_line()` matches checkbox
sub-steps, and this consumer uses the predicate as a **block boundary**. On the one plan in the
corpus that declares budgets, sub-steps appear inside task blocks before the `Budget:` line, so the
budget would be attributed to whatever number the sub-step's prose happened to mention. Measured on
the real plan, not hypothesised.

### B — Require plans to use the strict `- [ ] **Task N` form

Rejected on the same ground ADR-0069 rejected its mirror image: the corpus disagrees, `architect.md`
documents both forms, and the writer contract is not the thing that is wrong here.

### C — Make the reporter emit a diagnostic when it cannot parse the plan

Attractive — it is the "did not run" distinction this repository keeps re-learning — and rejected
for now because the reporter contract is stdout-only with a fixed token set (`BUDGET`, `SCOPE`,
`CLEAN`), and adding a fourth token changes every caller's parsing. The tests take the load
instead: `BJ2` fails if the check goes inert again. Worth revisiting if a third reporter needs the
same thing.

## Consequences

### Positive

- The check works. Verified on the real heading-form plan: an in-budget diff is `CLEAN`, an
  over-budget out-of-scope diff reports both `BUDGET` and `SCOPE`.
- One file decides what a plan task is, for both questions.
- Defect 4's fix is not specific to this feature's inputs — it corrects the reading of any
  `git diff --stat` this script is given.

### Negative

- **A dormant feature becomes active.** The first Step 5 run after this deploys may produce
  `BUDGET`/`SCOPE` findings on work in flight, on plans whose budgets were written with no
  expectation that anything read them. They are advisory by contract (ADR-0052: a reporter, the
  caller decides), but they will be new noise and the first one will look like a regression.
- `task_num()` still extracts digits only, so `## Task 1b` and `## Task 1` both resolve to task
  `1`, and `--tasks 1b` cannot be expressed. The plan that exposed this has both. Not fixed here:
  changing the task-identifier model touches `--tasks` expansion and the `BUDGET_FILE` key, which
  is a second change of a different kind. **Disclosed, not silently tolerated** — it means a budget
  can be attributed to a sibling task on a plan that uses letter suffixes.
- The elided-path recovery is a heuristic. It resolves the common case and reports the ambiguous
  one; it cannot resolve a tail that matches two different declared files.

### Neutral

- No manifest field, no schema bump, no new output token. Both call sites change one flag each.
- Inert until sync, like every change to a deployed script.

## References

- Issue #184, filed while designing #172 with the measurement already in it
- `docs/architecture/ADR-0069-172-plan-task-form.md` §D5 — the deferral, and why
- `docs/architecture/ADR-0052-106-diff-budget-scope-check.md` §D1, §D4, §D6 — the contract this
  restores rather than changes
- `staging/plugin/scripts/tests/diff-budget-scope.test.sh` sections BJ, BB2 — and note BB2's
  amendment: it asserted every plan in the corpus stays silent, which passed only because the check
  was inert, and would have blocked this fix
