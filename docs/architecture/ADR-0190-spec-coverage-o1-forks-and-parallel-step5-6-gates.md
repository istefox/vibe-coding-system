# ADR-0190 — `spec-coverage.sh`'s per-id boundary check becomes one precomputed pass, and three Step 5→6 gates stop waiting on each other

- **Status:** Accepted
- **Date:** 2026-09-04
- **Issues:** reported directly in chat (branch `istefox/perf-final-books-slowdown`), no GitHub
  issue filed
- **Related:** ADR-0047 (anti-test-weakening gate), ADR-0048 (`spec-coverage.sh` itself), ADR-0052
  (diff budget check), ADR-0138/ADR-0154/ADR-0157 (the scope-classification machinery this fix
  leaves untouched), ADR-0139 (the "instruction, not a guarantee" caveat on parallel Agent
  dispatch, reused here for parallel Bash dispatch)
- **Out of scope, deliberately:** `interface-check.sh` (runs later, on a different diff snapshot,
  after the Step 6 review/fix cycle — not a sibling of the other three); the Agent-tool fallback
  dispatch path's own per-checkpoint cadence (lower priority, not the default path)

## Context

A user reported that the end of every "coding" pass in the `concept-to-code` chain — the Step 5 →
Step 6 boundary, before the human-facing Gate 5 — blocks for **3-15 minutes** on real target
projects. Two independent, additive causes were found by reading the actual invocation sites
(not assumed from the summary table that lists all four Step 5→6-family scripts together, which
turned out to describe a contract family, not a single execution point):

**Cause 1 (the real minutes).** `spec-coverage.sh`'s `grep_boundary_test()` and
`grep_boundary_test_claimed()` (previously lines ~675-708) were each called **once per declared
requirement id** inside the main coverage loop, and each call forked `xargs -0 grep -hE
"<id-anchored-pattern>"` over the *entire* scoped/unscoped test-file population. For N ids and a
population of size M, that is O(N) subprocess forks each scanning O(M) content. Measured on
synthetic fixtures before the fix: marginal cost ≈ 41.5ms per additional id; on a real project
with ~100+ files and ~100+ ids across features (this repo's own corpus: 15 spec/plan pairs, 117
requirement ids, 98 discovered test files), that scales into minutes.

**Cause 2 (a smaller, additional saving).** Three independent Step 5→6 gates —
`weakening-scan.sh`, `spec-coverage.sh`, `diff-budget-check.sh` — ran sequentially under the
default Workflow dispatch path even though none reads another's output (confirmed: disjoint shell
variable namespaces, each resolves and pipes/passes its own independent input). A fourth gate,
`interface-check.sh`, was confirmed **not** a sibling of these three — it runs later, after the
Step 6 review/fix cycle, on a different cumulative diff, and stays exactly where it is.

## Decision

### D1 — Replace the O(ids) per-id fork with a one-time, single-pass precompute

Two small lookup sets, `COVERED_IDS` and `CLAIMED_IDS`, are built once via `awk` — reusing the
existing `extract_tokens()` token-shape logic already implemented in the file's own embedded
`plan_parse.awk` (the exact scan-anywhere, exactly-two-digit `R-NN` shape that already matches
`$IDS`'s own `strict_ok` predicate) rather than inventing a second, potentially divergent token
regex:

- `COVERED_IDS`: every id-shaped token found on a line of `$TESTFILES_SCOPED` that "qualifies" —
  where qualifies is exactly the OR of `grep_boundary_test`'s two original branches (a line with
  no claim token, or a line with a claim token AND an own-key), evaluated once per line instead of
  once per (line × id).
- `CLAIMED_IDS`: every id-shaped token found anywhere in `$UNSCOPED_POP`, unfiltered — matching
  `grep_boundary_test_claimed`'s original unconditional semantics (VCS-035 deliberately excludes
  the claim-line filter there; membership in `$UNSCOPED_POP` must stay unconditional or the
  ADR-0157 §D1 guarantee breaks).

The precompute is inserted after `$TESTFILES_SCOPED`'s last possible mutation point (the
SCOPE-EMPTY fallback can still overwrite it) and before the boundary check is first used, gated on
`[ -n "$TROOT" ]` and on `-s` checks (an awk call with zero file operands reads stdin and hangs —
the empty-population case must skip the call entirely, not feed it nothing).

Main-loop lookups become `grep -qxF "$id" "$COVERED_IDS"` / `"$CLAIMED_IDS"` — the same
fixed-string, whole-line idiom the file already uses and accepts for `$PLAN_TOKENS`/`$NOTEST`
(both small-file lookups already judged cheap). No new lookup idiom is introduced. The
`grep_boundary_test`/`grep_boundary_test_claimed` functions are removed; nothing else called them.

**`$CLAIM_LINE_RE`/`$OWN_LINE_RE` reach the awk precompute via `ENVIRON[]`, never `-v`.**
`$OWN_LINE_RE` is built from `$PLAN_BN_ESC`, a sed-escaped plan basename — a literal `.` in the
plan's filename (virtually every plan, being a `.plan.md`/`.md` file) becomes the ERE escape `\.`
in this regex. POSIX `-v var=value` re-interprets backslash escapes the same way a string literal
would: measured on this machine's BWK awk, `-v RE='a\.b'` silently drops the backslash and the `.`
becomes an unescaped wildcard, matching any character instead of a literal dot. Reproduced
end-to-end through this script (not just in isolation): a test line carrying a foreign claim
(`#999`) plus a near-miss of the plan's own basename — same length, wrong characters where its
dots sit — was misreported `COVERED` instead of the correct `UNSCOPED`. `$CLAIM_LINE_RE` is a
fixed literal with no interpolated escapes and does not need this; only `$OWN_LINE_RE` does.
`RZ11` (`spec-coverage.test.sh`) plants this exact defect and confirms it goes RED if the
`ENVIRON[]` wiring regresses back to `-v`.

**Nothing before the precompute's insertion point changes.** SPEC/PLAN id extraction, waiver
handling, the back-reference (`$BACKREF_RE`) and ownership (`$OWN_RE`) key sets, and the
file-scope classification machinery (`$TESTFILES_SCOPED`, `$UNSCOPED_POP`, etc.) are untouched —
this fix only changes *how* the two boundary predicates are evaluated, not what they mean, and not
any of the surrounding scope logic.

### D2 — The three independent Step 5→6 gates dispatch as parallel Bash calls, Workflow path only

`references/step5-implementation.md`'s Workflow-dispatch step list now instructs the orchestrator
to issue the weakening-scan, spec-coverage, and diff-budget-check invocations **in the same
message** (parallel tool calls) rather than one after another, then wait for all three before
evaluating policy — modeled on the existing Gate 5.06 parallel-Agent-dispatch precedent
(`hitl-gates.md`) and reusing its same honest caveat: **this is an instruction to the orchestrating
model, not an enforced guarantee** (ADR-0139's reasoning applies identically here). Each gate's own
internal logic — including `spec-coverage.sh`'s plain-bullet self-repair-and-rerun — still runs
entirely within its own invocation; parallelizing across gates changes nothing about what happens
inside one.

**Scope: the Workflow dispatch path only.** The Agent-tool fallback path runs `weakening-scan.sh`
and `diff-budget-check.sh` at every batch checkpoint while `spec-coverage.sh` runs once at the very
end — a different cadence relationship, not the same kind of siblinghood. Left untouched; it is the
non-default path.

## Alternatives considered

### A1 — Cache `grep` results in a bash associative array instead of precomputing to files

Rejected outright: the file's own header states a hard Bash-3.2-clean constraint (no associative
arrays). A file-backed lookup set was already the file's own established idiom for small
memberships (`$PLAN_TOKENS`, `$NOTEST`), so extending it kept the fix idiomatically consistent
rather than introducing a bash-version dependency the rest of the file explicitly avoids.

### A2 — One combined `grep -E` alternation of all ids, instead of an awk single pass

Considered: build one ERE alternation of every declared id and grep the population once. Rejected
because it still couples the extraction pass to the specific ids in `$IDS` rather than to the
generic token shape, and because it does not naturally produce the per-line qualifying
classification `grep_boundary_test`'s two branches require — the awk single pass computes
"qualifies" once per line and extracts tokens only from qualifying lines in the same pass, which a
grep-alternation-then-filter approach would need a second pass to reproduce.

### A3 — Parallelize all four Step 5→6-family gates, including `interface-check.sh`

Rejected after reading the actual call sites (not just the summary contract table that lists all
four together): `interface-check.sh` runs after the Step 6 review/fix cycle, over the cumulative
diff *including* that cycle's own fixes — it has a real ordering dependency on Step 6 having
already run, and is not a sibling of the other three at all.

### A4 — Pass `$CLAIM_LINE_RE`/`$OWN_LINE_RE` to awk via `-v`

This is what the implementation initially selected for this fix actually did (four independent
implementation attempts were produced in parallel for this fix; this one was picked before the
defect below was found). Rejected once measured: `-v`'s backslash re-interpretation silently
loosens `$OWN_LINE_RE` into a wildcard match wherever the plan basename contains a literal dot —
see D1. One of the three *other* parallel attempts had already identified and avoided this exact
defect independently, by passing both regexes via `ENVIRON[]`; that approach is what shipped here.

## Consequences

### Positive

- Marginal per-id cost measured ≈ 3.3× lower (41.5ms → 12.6ms per id on synthetic fixtures);
  subprocess fork count in the id-boundary path is now bounded by a small constant instead of
  scaling with declared-id count (pinned by the new RW1 regression test, 2 `xargs` invocations
  measured on a 24-id/32-file fixture regardless of id count).
- The parallel-dispatch change (D2) saves the wall-clock of the two smaller gates
  (weakening-scan, diff-budget-check) entirely, on top of D1's fix — smaller in absolute terms
  than D1, since D1 removes the dominant cost.
- No change to output vocabulary, exit codes, or any scope-classification semantics — verified
  against the full existing regression suite plus 3 new tests (RW1, RW2, RZ11), 179/0 pass.

### Negative

- The awk single-pass precompute is a second, separate implementation of the "which line
  qualifies" predicate, sharing the *regex definitions* (`$CLAIM_LINE_RE`, `$OWN_LINE_RE`) with
  the removed bash functions but not the code path — a future change to the qualifying-line rule
  must be made in the awk script, and the removed functions' shape no longer exists as a
  cross-check. Mitigated by RZ6-RZ11's direct exercise of exactly that boundary.
- D2's parallel-dispatch instruction is prose an LLM orchestrator is asked to follow, not an
  enforced mechanism (rule 16) — a future model revision could regress to sequential dispatch
  without any harness assertion catching it, the same limitation Gate 5.06's existing parallel
  dispatch already carries.
- The `ENVIRON[]` vs `-v` distinction (D1) is a narrow, awk-implementation-specific escaping
  quirk that is easy to reintroduce by a well-intentioned "simplify this" edit; RZ11 is the only
  thing standing between a future edit and a silent correctness regression here.

### Neutral

- At small/medium fixture scales, total wall-clock improvement is modest relative to the marginal
  per-id gain, because an untouched, pre-existing O(files) scope-classification loop (file
  discovery and ownership classification, unrelated to this fix) dominates at those scales. The
  marginal per-id cost is the more honest metric for what this fix specifically targets, and it is
  the term that scales with a real project's requirement-id count.

## Verification

- `bash staging/plugin/scripts/tests/spec-coverage.test.sh` → `PASS=179 FAIL=0` (all pre-existing
  RS/RX/RY/RZ assertions unchanged, plus RW1 primary fork-count guard with its own `# plant:`
  confirming it goes RED against the removed O(ids) shape, RW2 secondary wall-clock ceiling
  explicitly caveated per rule 10 as investigate-not-regression, and RZ11 — planted and confirmed
  RED against the `ENVIRON[]`→`-v` regression described in D1/A4).
- `bash staging/plugin/scripts/tests/spec-coverage-baseline-bump.test.sh` → `PASS=25 FAIL=0`
  (sibling script, unaffected).
- `bash -n` clean on the modified script.
- Full suite re-run independently a second time in a separate sandbox, with identical results.
- `cross-reference-form.test.sh` (38/0), `human-gate-coverage.test.sh` (55/0), and
  `pairs-completeness.test.sh` (341/0) re-run clean after the doc edits in D2 — no cross-reference
  or CI-registration regressions from this change.
- D2 (the parallel-dispatch prose) has no automated test — verified by re-reading the edited
  section for internal consistency; real-world confirmation is deferred to the next live Step 5→6
  run on an actual project.

## References

- `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh`
- `staging/plugin/scripts/tests/spec-coverage.test.sh` (RW1, RW2, RZ11; updated plants RX5, RZ6,
  RZ7)
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` (Workflow dispatch
  path, steps 4-6)
