# ADR-0100 — One task count silently served two questions, and the batching arithmetic was the symptom

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #242 (found by the Phase 7.1 shakedown run at Step 5's dispatch-mode selection)
- **Related:** ADR-0069 (#172, which built the loose predicate and said in terms what it must not be
  used for), ADR-0070 (#184, which added `is_task_opener()` for exactly this distinction), ADR-0089
  (#239 — why no run had ever reached Step 5 to hit this)

## Context

Step 5's pre-dispatch block computes

```bash
tasks=$(plan-tasks.sh --count "<plan>")
```

for one decision — `tasks = 0` → refuse — which is what ADR-0069 built it for. Twelve lines later
the Agent-tool fallback opens with a **second, different** decision:

> **Batch-dispatch policy (≥6 tasks in plan):** … split the dispatch into **batches of 2-3 tasks**

and names no source for the number. The only task count in scope is `$tasks`, and ADR-0069 §D2 says
in terms that this is the one thing it must not be used for:

> The count over-counts on purpose … Correct for a `>= 1` guard, wrong for anything that needs a
> real task count or a task block.

**One number silently served two questions.** The batching arithmetic is the symptom.

### Measured, and wider than the issue states

The issue calls it "benign on this plan by luck". Across the 58 plans in `docs/superpowers/plans/`:
the two counts **diverge on 51**, and **all 51 are `>= 6` and over-counted**. On #222's plan they
are **38 and 7** — batches of 2-3 over 38 means dispatching a tester and a coder against tasks 8
through 38, which do not exist.

The `≥6` threshold is satisfied by both numbers, so the branch taken is the same; only the
arithmetic diverges, one step later. Nothing in the corpus could have hit it before, because no
chain run had ever reached Step 5 (#239).

## Decision

### D1 — `plan-tasks.sh --count-openers`, exposing the predicate that already existed

`is_task_opener()` has been in `plan-task-predicate.awk` since ADR-0070, added because *"is there a
task here"* (guard) and *"does a task BLOCK START here"* (boundary) are different questions and
`diff-budget-check.sh` needed the second. Batching needs the second too. This is the **third**
consumer to need it, so it becomes a mode of the shared script rather than a third private copy —
ADR-0069's own rule, applied to its own script.

### D2 — Both call sites say which count they use, and that they are not interchangeable

The pre-dispatch block carries **"Two counts, two questions"** naming what each is for; the batch
policy names `$openers` explicitly and says why `$tasks` is wrong there. This mirrors the
"Do not copy one block's branching into the other" sentence two blocks up, which exists for the same
class of confusion between adjacent scripts.

**Neither substitution is safe, and that is the part worth stating.** `--count` over-counts: safe
for a guard, wrong for arithmetic. `--count-openers` returns **0** on plans that use a different
word for a task: safe for arithmetic that checks for zero, wrong for a guard.

### D3 — `openers = 0` with `tasks >= 1` dispatches as a single block

**The obvious fix introduces a new failure the issue does not mention.** Two corpus plans have
`openers = 0` and a non-zero `--count`, because they write `### T1 —` and `### Step 0 —` — the two
forms ADR-0070 §PTG9 and ADR-0069 §PTE2 already exempt by name. `deep-refactor-skill.md` counts 36
and opens 0.

Consuming `$openers` naively turns an over-batching bug into a **batch-nothing** bug: zero batches,
nothing dispatched. So the zero case falls back to a single block — today's sub-threshold behaviour
— and says why. Exit 2 or 3 from the counter takes the same branch, for the same reason.

### D4 — The Workflow path was checked and does not consume the number

The issue asked. Measured: the Workflow path derives task **groups** by reading the plan for
file-path mentions, and invokes no counter at all. `BO9b` asserts it as a forward guard, so the
answer does not have to be re-derived by the next reader.

## Verification

16 assertions in `batch-dispatch-openers.test.sh`, plus a `Z1` floor. Harness 61/61. The counts are
executed against **the real corpus**, not fixtures — `BO4` re-derives the 51-of-58 divergence rather
than trusting the number in this ADR, and fails loudly if the premise stops holding.

Seen RED against the unmodified tree: **7 of 16** — `BO1`, `BO3c`, `BO4`, `BO5`, `BO6`, `BO7`,
`BO8`. `BO2` (the `>= 1` guard's answer is unchanged), `BO9b` and the anchors pass before and after.

Five planted defects, all fired, all planted **wrap-insensitively** (ADR-0099's lesson, applied on
the first attempt this time):

| plant | fires |
|---|---|
| `--count-openers` wired to the **loose** predicate | `BO1`, and `BO4`/`BO5` collapse — the divergence measurement detects its own instrument |
| the batch policy reverted to `$tasks` | `BO6` |
| the "Two counts, two questions" statement removed | `BO7` |
| the zero-opener branch removed | `BO8` |
| the Workflow path made to consume the count | `BO9b` |

**A measurement failed silently on the way, in the way this repository keeps finding.** The first
corpus sweep ran `awk -f predicate.awk '{…}' plan` and returned **empty for every plan** — with
`-f`, awk treats the positional program text as a *file*, so it read nothing and reported nothing,
with no error. Had the sweep been trusted, it would have said the two counts agree everywhere. Fixed
by putting the second program in a temp file, which is what `plan-tasks.sh` itself already does and
documents.

## Consequences

- **Batching behaviour changes on 51 of 58 plan shapes.** The threshold branch does not move; the
  ranges do, from wrong to right. The first Step 5 after this deploys will produce visibly fewer
  batches than the instruction used to imply.
- **`task_num()` extracts digits only** (ADR-0070's known limit, carried over): a plan using
  `## Task 1b` cannot be expressed as a batch range, and its opener is counted under `1`.
- The two zero-opener plan forms are handled by a fallback, not recognised. Widening the opener
  predicate to `Step|T[0-9]` was rejected by ADR-0070 §D3 and is not reopened here.
- `plan-tasks.sh` now has two modes with opposite failure directions, and nothing prevents a future
  caller picking the wrong one — only the header and the two call sites say which is which.
- Inert until sync.
