# spec-coverage.sh, diff-budget-check.sh, plan-tasks.sh

- `spec-coverage.sh` extracts requirement IDs literally from a task heading: an ellipsis range like
  `(R-01 … R-11)` cites only the two endpoints. Cite every ID a task actually satisfies.
- The `R-NN` namespace **restarts per feature**, but the tool's test-side axis greps the *whole*
  discovered test population — a foreign file's ids satisfy coverage regardless of feature. Cite
  the ids in the new assertions' own comment headers (53% of well-tested features are comment-only
  citations; a rule treating comment-only as non-evidence would fail the best-tested features).
- A plan that names a discovered harness by basename imports that harness's whole `R-NN` namespace
  if it also cites an ADR that harness names. Refer to specific assertion ids, never filenames, to
  avoid importing foreign matches. **Measured 2026-09-02 (ADR-0189/#296): ONE throwaway prose aside
  naming `commit-transition-order.test.sh` flipped all three declared ids from
  `COVERED/UNSCOPED/UNSCOPED` to `COVERED/COVERED/COVERED`, rc 1 → 0, before a line of source
  existed.** The remedy that works: write the assertion-id range instead of the basename ("the
  harness carrying `RS0`–`RS10`"). Always re-run `spec-coverage.sh` after every plan edit, not once
  at the end — the scope set moves on prose changes.
- **Writing the plan file itself turns `RS7`/`RS8a` RED, and that is the correct in-flight state.**
  Once `docs/specs/<N>-*.spec.md` exists (the chain archives the SPEC pointer early), landing
  `docs/superpowers/plans/<date>-<slug>.md` resolves a new (spec, plan) pair, so the live sweep
  finds N more rows than the frozen `spec-coverage-scope-baseline.tsv`. Observed 2026-09-02:
  `PASS=174 FAIL=2`, "3 of 201 live verdicts diverge", baseline at 198 rows, pair count 15 → 23.
  Owner is Step 7.0b's `c2c-step7-baseline-bump` fence (ADR-0166/#460) — never hand-edit the `.tsv`,
  never weaken `RS7`. Say so in the plan or the coder will "fix" it.
- `plant-check.sh` and `test-write-scope.sh` are two useful "safe to name freely" precedents:
  `plant-check.sh`'s basename matches no discovery pattern at all; `test-write-scope.sh` is
  discovered (`test-*.sh`) but carries zero `R-NN` tokens.
- A SPEC id carrying `(no-test: …)` whose token appears anywhere in a scoped test file produces
  `STALE-WAIVER`, exit 3, blocking Step 5→6 before any code exists. Fix is a SPEC.md edit at Gate 2
  plus real existence-level assertions — never deleting the waiver alone.
- Takes `--spec`/`--plan` flags, not positionals; a bad invocation exits 0 with a usage message on
  stdout. Always check the `COVERED` lines are actually printed, not just the exit code.
- Run `spec-coverage.sh --spec SPEC.md --plan <plan> --tests-root .` before finishing any plan — a
  plan's own prose can scope in files nobody intended (measured: enumerating a discovery predicate
  pulled 11 unrelated per-skill runners into scope, 13 files instead of 2).
- `diff-budget-check.sh` attributes a `Budget:` line to the task block delimited by `is_task_opener`
  — a budget on its own line after the checkbox list parses correctly, but one that **wraps across
  two lines produces no budget for that task, silently**. Verify with a fake `git diff --stat` piped
  into `diff-budget-check.sh --plan <p> --tasks N`, confirm it reports `BUDGET` not `CLEAN`. A task
  with no `Budget:` line reports nothing at all — omitting on an unguessable task is genuinely free.
- `plan-tasks.sh` has three invocations, not two — `--count` and `--count-openers` in one fence,
  plus `--count` in a second, unrelated one. Re-derive before assuming a two-call model.
- Corpus/count claims in a prior ADR, SPEC, or PROJECT.md are snapshots of their moment, never
  citable facts — re-derive every count from the files before designing on it (rule 13; measured
  wrong on this repo's own numbers at least four separate times).
