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
- **The forward form of that trap is the plan's job to prevent, and it is easy to walk into.** A
  plan that cites a `(no-test:)` id in a task heading is correct (the marker exempts the *test*
  axis, never the plan axis — ADR-0138), but if the same plan also puts that id in a per-assertion
  bullet the tester will copy it into the harness comment header and detonate `STALE-WAIVER` on the
  first run. Write the id in the task heading only, and say in the plan, in words, that the token
  must never be typed into a test file. Caught live 2026-09-05 on the codex-review-gate-deep-refactor
  plan: three ids (R-12/R-13/R-14) were about to be written into a new harness.
- **Before naming any harness by basename in a plan, census its `R-NN` tokens** —
  `grep -ohE '\bR-[0-9]+' <harness> | sort -u`. Zero tokens means the basename is free to use;
  anything else imports that namespace. Measured 2026-09-05: `codex-reviewer-schema.test.sh`,
  `workflow-dispatch-pins.test.sh`, `dispatch-completion.test.sh` are all zero and safe;
  `fence-contract-coverage.test.sh` (8 ids), `plant-registry-parallel.test.sh` (11),
  `spec-coverage-baseline-bump.test.sh` (8) and `pairs-completeness.test.sh` (2) are not — refer to
  those descriptively. The census is one command; the alternative is a plan whose ids read green
  before a line of code exists.
- **The SPEC parser is strictly LINE-oriented, and this produces two opposite traps around
  `(no-test:)`.** It reads each checklist item's own line and nothing else. (a) A marker on the item
  line whose reason wraps — only `verified by` before the newline — measures 11 chars against the
  20-char floor and is `MALFORMED`, exit 3, aborting the run before ANY id is evaluated (observed
  2026-09-07: the whole output was `MALFORMED R-14` / `ORPHAN R-14`, the ORPHAN a cascade from the
  plan citing an id the parser never registered). (b) A marker on a CONTINUATION line is invisible,
  so the id is simply not exempt — and "tidying" it onto the item line can be strictly worse:
  measured, moving R-09's marker up, and adding `(no-test:)` to R-10/R-12, each turned a passing id
  into `STALE-WAIVER`, exit 3, because those tokens occur as OTHER features' ids in in-scope
  harnesses. Only an id with zero in-scope token occurrences is safely waivable. Always simulate a
  proposed SPEC fix against a scratch copy before recommending it.
- **`--count` is the LOOSE predicate and legitimately over-counts; `--count-openers` is the one that
  matters.** Anything that batches, ranges or attributes content to a task uses openers. A plan with
  8 tasks reported 10/8 here; a known-good precedent plan reported 39/8. Never read `--count` as a
  task count.
- **A `COVERED` verdict on a removal-shaped feature is usually a foreign match.** Measured
  2026-09-07: 14 of 14 ids `COVERED`, rc 0, before a line of code existed — because legacy harnesses
  the plan must name carry their own features' `R-NN` tokens and the line-granular negative filter
  drops only lines bearing a foreign `#<n>`/`ADR-NNNN` on the SAME line, which comment prose rarely
  does. The remedy that is honest rather than evasive: have every rule-19 deletion comment and every
  new assertion header cite THIS feature's id beside its ADR, at the site of the change. Do not
  instead refer to harnesses descriptively to dodge half 1 — that buys a green verdict by hiding
  filenames from the coder.
- **Each shipped Codex-backend harness adds a new landmine to that census, and they are the worst
  kind: they name the ADRs a successor feature inevitably cites, so both halves of the ADR-0154
  scope filter close on their own.** Measured 2026-09-07: the tester's dispatch-gate harness carries
  R-01…R-14 (naming ADR-0194) and the `test-write-scope` harness carries R-11 (naming
  ADR-0049/0068). A coder-backend SPEC waiving R-11/R-13 with `(no-test:)` detonates STALE-WAIVER,
  exit 3, on either basename. Refer to a sibling harness by *prefix* ("the tester's own
  dispatch-gate harness, prefix `CX`") — never by filename — and re-run the census each time, since
  the population grows with every feature in the family. Note `plant-check.sh` stays safe for the
  opposite reason: its basename matches no discovery pattern, so its own R-01/R-05/R-12 never
  scope in.
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
