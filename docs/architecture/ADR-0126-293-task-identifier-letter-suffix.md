# ADR-0126 — The task identifier gains a letter suffix, and the `--tasks` expansion moves with it

- **Issue:** #293
- **Status:** Accepted
- **Date:** 2026-08-04
- **Supersedes in part:** ADR-0070 §Negative (the `task_num()` digits-only disclosure)
- **Related:** ADR-0052 (the budget check), ADR-0069 (the shared task predicate), ADR-0070 (the
  four defects that woke this checker up), ADR-0091 (the per-file budget half-parse),
  ADR-0100 (batch dispatch by openers), ADR-0101 (batch boundary precedence)

---

## Context

`diff-budget-check.sh` attributes a plan task's `Budget:` declaration to a task identifier
produced by an awk function, `task_num()`, which matches `Task[ \t]+[0-9]+` and then strips every
non-digit. `## Task 1b` and `## Task 1` therefore both resolve to `1`. ADR-0070 recorded this as a
carried-forward consequence and declined to fix it, on the ground that changing the identifier
model "touches `--tasks` expansion and the `BUDGET_FILE` key, which is a second change of a
different kind".

Everything below was measured before anything was designed. Three of the received premises did not
survive the measurement, and one of them changes what the fix is.

### What the corpus actually contains

64 plans in `docs/superpowers/plans/`, **547 task openers** under `is_task_opener()`.

- **Exactly one opener in the whole corpus carries a letter suffix**:
  `2026-07-28-176-worktree-isolation-contract.md:121`, `## Task 1b — Amend the SPEC to match what
  was measured`. It is a real opener — the predicate matches it, because `is_task_opener()` requires
  `^[Tt]ask[ \t]+[0-9]+` and does not care what follows the digits. No predicate change is needed
  or wanted; the SPEC is right to scope it out.
- **67 pairs of openers share a `task_num()` value, and 66 of them are correct.** They are the same
  task written twice in one plan — a checklist summary line near the top and the heading below it,
  for instance `- [x] Task 1 — RED: harness skeleton` at line 106 and `## Task 1 — RED: harness
  skeleton` at line 118 of the secret-scan plan. Both are openers, both yield `1`, and they must
  keep yielding `1`. **A fix that made every opener's identifier distinct would break 66 healthy
  plans to repair one.** That is the constraint the design is built around, and the issue does not
  mention it.
- The single genuine collision is `Task 1` against `Task 1b`, in the one plan named above — and
  that plan **is** one of the nine that declare budgets, so the defect is live rather than latent.

### What the defect does today, run rather than read

`Task 1` opens at line 79 and declares no budget. `Task 1b` opens at 121 and declares
`Budget: SPEC.md (~90 lines)`. Because both key to `1`, task 1b's ceiling is filed under task 1.
Against a two-file diff:

```
--tasks 1   ->  BUDGET  1  files=1/2  lines=90/70  margin=0
```

A `BUDGET` finding on a task that declared no budget, measured against a ceiling belonging to a
different task. **A false `BUDGET` finding reaching an operator is the failure ADR-0091 named as
the one this checker exists to prevent**, and it is reachable today through the documented Step 5
caller idiom, which passes "a comma list of every task number dispatched so far".

The misattribution is not confined to the ceiling. `MALFORMED` carries the identifier too, so a
declaration that fails to parse inside task 1b's block is reported as `task 1`, sending the
operator to the wrong block to fix it. That is a third call site of the same identifier and the
issue names only two.

And `--tasks 1b` returns `CLEAN`. Not an error — the expansion emits the literal string `1b`, no
`BUDGET_FILE` key equals it, `BUDGET_LIVE` stays 0, and the budget is silently unenforced.

### The premise that changes the design

The SPEC lists the `BUDGET_FILE` key and the `--tasks` expansion as two bullets of R-02, which
reads as two independent edits. They are not. Measured on a three-task fixture (`Task 1` ~10 lines,
`Task 1b` ~100 lines, `Task 2` ~10 lines) against a 105-line diff:

| selector | today | key widened, range left numeric |
|---|---|---|
| `--tasks 1` | `BUDGET files=2/3 lines=110/105` (over-counts) | `BUDGET lines=10/105 margin=95` (correct) |
| `--tasks 1-2` | `CLEAN` | **`BUDGET lines=20/105 margin=85`** |

Today's collision makes ranges *accidentally* correct: `1-2` expands to `{1,2}`, and because task
1b is filed under `1` its ceiling is picked up anyway. Widen the key alone and the range loses
task 1b's 100 lines, the expected total falls from 120 to 20, and the checker reports an 85-line
overshoot that does not exist. **Fixing half of R-02 converts a permissive misattribution into a
new false positive of exactly the class this feature exists to prevent.** The two halves are one
coupled change, and the ADR says so because the SPEC's phrasing invites doing them separately.

---

## Decision

### D1 — `task_num()` extracts digits plus an optional letter suffix, normalised to lowercase

```awk
function task_num(l,   t) {
  match(l, /[Tt]ask[ \t]+[0-9]+[a-zA-Z]*/)
  t = substr(l, RSTART, RLENGTH)
  sub(/^[Tt]ask[ \t]+/, "", t)
  return tolower(t)
}
```

Measured across all 547 corpus openers under both the old and the new function: **exactly one
opener changes**, the `Task 1b` heading, from `1` to `1b`. Nothing else in the corpus moves. The
66 legitimate same-task pairs are untouched, because neither member of any of them carries a
suffix.

Lowercase normalisation is included because the failure mode of omitting it is silent: `--tasks 1B`
against a `## Task 1b` block would match no key, drop the ceiling, and under-count the expected
total — the same false-overshoot direction the range defect above produces. The cost is one
`tolower()` and one `tr` at the selection side.

### D2 — A range covers declared members whose numeric part falls inside it; a bare identifier is exact

`--tasks 1` selects task 1 and nothing else. `--tasks 1b` selects task 1b. `--tasks 1-2` selects
every declared identifier whose numeric part lies in [1,2] — so `1`, `1b` and `2`.

This is what preserves the cumulative-sum contract stated at the Step 5 call site and in this
script's own header: the caller re-scans the whole diff since the Step 5 baseline at every
checkpoint and sums the budgets of every task dispatched so far. A range names a span of plan
order, and a lettered task is a task inserted after its numeric sibling, inside that span. Dropping
it under-counts the expectation and manufactures an overshoot.

The expansion reads `BUDGET_FILE` to discover which lettered members exist. That is an ordering
dependency — `expand_tasks` must run after the plan parse, which it already does — and it is
stated at the function, because it is invisible from the call.

Range endpoints are reduced to their digits before the numeric walk, so `1b-3` behaves as `1-3`
rather than yielding nothing. Today `[ "1b" -le "3" ]` errors into a suppressed `2>/dev/null` and
the range expands to the empty set in silence.

### D3 — Backward compatibility is proven at the function level in the harness, and end to end here

The harness repeats ADR-0091 §BK9's pattern: embed the pre-#293 `task_num()` as the specification
of what must not change, extract the live one from the script, run both over every corpus opener,
and require that the differing set is small and that nothing which previously produced an
identifier now produces none.

**Its boundary, stated for the same reason BK9 states its own:** it compares the *function*, so it
is blind to a script that defines it correctly and stops calling it. The call sites are covered by
fixtures instead.

The end-to-end proof was run at design time and is recorded here rather than in the harness: both
scripts, all 64 plans, 14 selectors each — **896 invocations, 895 identical, one differing**, and
the one is the removal of the false `BUDGET` line quoted above. It is not in the harness because
896 script invocations would exceed the file's own stated performance budget, and the function-level
comparison plus the fixtures cover the same ground within it.

### D4 — The bounded-difference assertion is a range, not an exact count

The corpus assertion requires between 1 and 3 differing openers, following BK9b's `>= 1 && <= 5`
precedent in the same file rather than pinning the current value of 1.

An exact count would turn the next plan that legitimately uses a letter suffix into a red test a
human must hand-edit — which is precisely the mechanism `BB2b` has become, hand-raised four times
in eight days, and which issue #358 exists to remove. Writing a fifth absolute count into this file
while #358 is scheduled to delete the last one would be adding an instance of the defect class the
roadmap is closing.

### D5 — The Step 5 call site is told that an opener count is not an identifier

`plan-tasks.sh --count-openers` returns **11** on the colliding plan while the highest `Task N`
designation in it is **10**. The batching instruction says to split into "batches of 2-3 task
blocks, numbered by their `Task N` designations", so an orchestrator deriving ranges from the count
produces a batch `10-11` addressing a task that does not exist, and never names `1b` at all. That
is ADR-0100's defect — ranges over tasks that do not exist — reappearing through a different door.

`concept-to-code/SKILL.md` gains a sentence at the Step 5 call site: a lettered task must be named
explicitly in the accumulating comma list, and the opener count is not the highest designation.
This is an instruction, not an enforcement; the deeper arithmetic gap in the batching derivation is
disclosed below as a follow-up rather than fixed here, because `plan-tasks.sh` carries no
identifier extraction at all and giving it one is a different change.

### D6 — `plan-tasks.sh` and `plan-task-predicate.awk` are byte-untouched

Measured: `task_num` is defined once and called once, both inside `diff-budget-check.sh`.
`spec-coverage.sh` extracts no task identifier. `plan-tasks.sh` counts and never numbers. There is
one copy of the identifier model, so ADR-0086's extraction criterion has no subject here — there is
nothing to share and nothing that could disagree.

---

## Alternatives considered

### A1 — Leave it disclosed, as ADR-0070 chose (rejected)

ADR-0070's scoping judgement was correct for its moment: the change genuinely is "of a different
kind" from the four parser defects it was fixing, and bundling it would have widened that change
materially. What has not survived is its severity assessment. Its consequence bullet says a budget
"can be attributed to a sibling task on a plan that uses letter suffixes" — conditional, and read
as latent. Measured, it *is* so attributed, on the only corpus plan with a letter suffix, and the
direction is a false `BUDGET` finding rather than a silent miss. ADR-0091 then established that
class as the one the checker must not produce. The deferral was sound; its premise has been
overtaken by a later decision in the same file.

### A2 — Widen the key and leave range expansion numeric (rejected, measured)

The obvious minimal change, and it makes things worse. Measured on the fixture in §Context:
`--tasks 1-2` goes from `CLEAN` to `BUDGET lines=20/105 margin=85`, a false overshoot of 85 lines,
because the range silently drops the lettered member's ceiling. The current collision is what makes
ranges accidentally correct today, so removing the collision without moving the expansion trades a
permissive error for a false positive. Rejected on evidence, not on taste.

### A3 — A bare `N` selects `N` and every `N<letter>` sibling (rejected, measured)

Attractive because it is fully backward compatible for the comma-list caller: `1,2,3` would sum
exactly what it sums today. Measured on the live plan, it does not fix the defect — `--tasks 1`
still picks up task 1b's 90-line ceiling and still emits the false `BUDGET 1 files=1/2` line,
because the selection is lenient even though the keys are distinct. It buys expressibility for
`--tasks 1b` and leaves the reported symptom exactly where it was. An alternative that does not
remove the finding the issue was filed about is not a candidate.

### A4 — Make `is_task_opener()` reject a lettered designation (rejected)

Explicitly out of scope per the SPEC, and strictly worse on its merits. If `## Task 1b` stopped
opening a block, its content would be absorbed into task 1's block — including its `Budget:` line,
which task 1's `got` flag would then consume or discard depending on ordering. The declaration
would be attributed to task 1 outright rather than merely keyed to it, and `Task 1b`'s 66 healthy
same-task siblings elsewhere in the corpus depend on the opener predicate staying as it is.

### A5 — Rename `Task 1b` to `Task 11` in the corpus plan (rejected)

It would make the harness green with no code change. It also falsifies a completed historical
record — the plan documents an amendment that was made mid-chain and approved at a Gate 2 re-entry,
which is exactly why it is numbered `1b` rather than appended at the end. ADR-0075 and ADR-0078
both refuse to rewrite completed records to satisfy a checker. And it fixes nothing for the next
plan that inserts a task, which `architect.md` neither forbids nor discourages.

### A6 — Give `plan-tasks.sh` an identifier-aware batching mode (rejected for this change)

The `--count-openers` versus highest-designation gap in D5 is real and I found it while measuring
this one. Closing it means giving `plan-tasks.sh` a notion of identifier it has never had, deciding
what a batch range means when identifiers are not contiguous, and moving ADR-0100's batching
arithmetic — three decisions, none of which the SPEC scopes in, on a script the SPEC does not list.
Disclosed as a follow-up with the measurement attached, so the next reader starts from the number
rather than rediscovering it.

---

## Consequences

### Positive

- The live false `BUDGET` finding on `2026-07-28-176-worktree-isolation-contract.md` is removed.
  Measured end to end: 896 invocations across the whole corpus, one output changes, and that is it.
- `--tasks 1b` becomes expressible, so a lettered task's budget can be enforced at all. It could
  not be before, in either direction — naming it did nothing, and not naming it charged the ceiling
  to its numeric sibling.
- `MALFORMED` now names the block the unparseable declaration actually sits in, so the operator is
  sent to the right place. This third call site was not in the issue and is fixed by the same line.
- Ranges spanning a lettered task sum correctly, which is what the Step 5 cumulative contract
  assumes and what today's behaviour only achieves by accident.
- `1b-3` as a range endpoint stops expanding to the empty set in silence.
- The 66 legitimate same-task opener pairs are provably unaffected, and the harness now says so
  rather than leaving it to inspection.

### Negative

- **`--tasks 1` on a plan with a lettered sibling returns a different number than it did
  yesterday.** It is the correct number, and it is the point of the change, but any consumer that
  recorded a `budget_findings` entry from before this lands is comparing against a different
  arithmetic. One corpus invocation is affected; nothing persists those totals across runs.
- `expand_tasks()` now reads `BUDGET_FILE`, coupling selection to the plan parse having already
  run. It has always run first; the dependency is new, invisible from the call site, and stated at
  the function for that reason.
- **`## Task 1B` and `## Task 1b` in one plan now collapse to a single key.** Lowercase
  normalisation buys the `--tasks 1B` case and pays for it with a collision on absurd input. No
  corpus plan mixes cases; recorded rather than guarded, because a guard would be a second
  identifier rule to keep in agreement with the first.
- The identifier is still lexical, taken from the text of the opener line. A plan that writes
  `## Task 1 (b)` or `## Task one` remains outside the model entirely, exactly as before.
- **`BB2b` will fire regardless of what this plan declares** — see the risk note below. That is a
  consequence of writing a plan about the budget checker, not of this decision, and it is recorded
  here because the next reader will meet the red test before they meet the ADR.

### Neutral

- No manifest field, no schema bump, no new stdout token. The grammar stays `BUDGET`, `SCOPE`,
  `MALFORMED`, `CLEAN`, and the reporter contract — always exit 0, signal on stdout — is untouched.
- `plan-task-predicate.awk`, `plan-tasks.sh` and `spec-coverage.sh` are byte-unchanged.
- The harness file is already in `.github/workflows/docs-ci.yml`'s `shell-tests` list under the
  bare name `diff-budget-scope`, and already matches `.claude/test-cmd`'s `*.test.sh` glob. No CI
  wiring changes.
- `diff-budget-scope.test.sh` carries **zero** plant declarations today; the nine added here are the
  first in that file, which also lifts `plant-check.sh`'s `PC3` file-spread count by one.
- Inert until `sync-to-claude.sh --apply`, like every change to a deployed script. Both `PAIRS`
  entries already exist.

---

## Disclosed, not fixed

- **`--count-openers` is not the highest designation** (D5, A6). 11 versus 10 on the colliding
  plan. An orchestrator deriving batch ranges from the count addresses a task that does not exist
  and omits the lettered one. Mitigated by a call-site instruction here; the arithmetic needs its
  own issue.
- **`BB2b`'s exclusion predicate is a loose substring**, `grep -q '[Bb]udget:'`, so it counts a plan
  that *discusses* budget declarations as one that *makes* them. Measured: 9 plans match, **8**
  actually parse a declaration — the ninth is the `# Performance budget: <10s typical` comment
  ADR-0091 already records as a known false positive. This feature's own plan makes 10 and turns
  `BB2b` red **whether or not it declares a single budget**, because its subject is the string
  `Budget:`. That is rule 12 at the corpus level and it is new evidence for issue #358: the previous
  four hand-raises were all plans that genuinely declared budgets. No fifth hand-raise is planned
  here.
- **A broken predicate file makes this reporter print `CLEAN`.** Observed while prototyping: if
  `plan-task-predicate.awk` cannot be loaded, awk writes to stderr and the script emits the clean
  sentinel. Correct under the fail-open reporter contract, and it means a deployment that loses the
  predicate reports "nothing to report" forever. Pre-existing, out of scope, worth someone's issue.

---

## Correction (2026-09-12)

The chain that would have implemented this ADR stalled at Step 2 on 2026-08-04, after the ADR was
written and before the plan (`VCS-002`). Picking it back up over a month later, measuring the
premise first (rule 13) rather than assuming this decision was still entirely unimplemented:

- **D1 (`task_num()` extracts digits plus letter suffix) had already shipped**, as a side effect of
  an unrelated later refactor — VCS-057/ADR-0185 extracted `task_num()` out of
  `diff-budget-check.sh` and into the shared `plan-budget-parse.awk`, and the extracted version
  already preserves the letter suffix exactly as D1 specifies. Verified directly against the exact
  corpus line this ADR cites (`## Task 1b — Amend the SPEC...`): `task_num()` returns `1b`, not
  `1`. Nobody set out to implement D1; the extraction happened to carry it along.
- **D2 (`expand_tasks()` range expansion, and range-endpoint digit reduction) was still live** and
  was implemented now, in `expand_tasks()` only. Reproduced against the deployed script before
  fixing: `--tasks 1-2` summed only the plain-numeric members' ceilings, silently dropping `1b`'s;
  `--tasks 1b-2` (lettered low endpoint) expanded to nothing. Both now match this ADR's D2.
- D3-D6 were not separately implemented as distinct work — D3's harness-level backward-compat
  pattern and D6's byte-untouched-files claim both remain true of the fixed code (verified: only
  `expand_tasks()` changed); D5's call-site instruction was not added to `concept-to-code/SKILL.md`
  in this pass, and stays open as a small follow-up rather than blocking this closure.

The consequences and alternatives sections above describe the design as a whole and are left
unedited (rule 14: a historical record is not corrected in place) — only D1's implementation
history differs from what this ADR originally proposed to do itself, not the design's correctness.

## References

- Issue #293; `SPEC.md` (this chain)
- `docs/architecture/ADR-0070-184-diff-budget-task-predicate.md` §Negative — the deferral this
  supersedes in part
- `docs/architecture/ADR-0091-246-per-file-budget-half-parse.md` §BK9 — the both-parsers corpus
  pattern D3 repeats, and the false-`BUDGET` failure class
- `docs/architecture/ADR-0069-172-plan-task-form.md` §D1/§D2 — the shared predicate, loaded not
  pasted
- `docs/architecture/ADR-0100-242-batch-dispatch-openers.md` — the opener-versus-line distinction
  D5 extends
- `docs/architecture/ADR-0101-247-batch-boundary-precedence.md` — the batch-boundary precedence the
  plan follows
- `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh` — `task_num()`,
  `expand_tasks()`, the `BUDGET_FILE` key
- `staging/plugin/scripts/tests/diff-budget-scope.test.sh` — `BK9a`/`BK9b`/`BK9c`, `BB2b`, `Z1`
- Issue #358 (BB2b absolute ceiling), issue #355 (plant-check prefix match)
