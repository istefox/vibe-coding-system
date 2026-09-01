# ADR-0186 — VCS-057 Fase 2 L2: budget-driven batch sizing

- **Status:** Accepted
- **Date:** 2026-09-01
- **Related:** ADR-0185 (Fase 2 L1, `step5-brief.sh` — this is a fourth mode of that same script),
  ADR-0100 (`--count-openers`, the proxy this replaces where a budget exists), ADR-0070/ADR-0052
  (the shared task predicate and `Budget:` parser this loads, never restates), ADR-0184 (Fase 1,
  untouched here).

## Context

VCS-057 Fase 2's plan-sequence closes with L2: dimension the Step 5 batch-dispatch policy on the
work the plan *declares*, in each task's `Budget:` line, instead of the fixed opener-count proxy
(`plan-tasks.sh --count-openers`, batches of 2-3 task blocks) it uses today.

**The plan's own prerequisite was blocking: re-derive `Budget:` coverage with the real predicate
before deciding whether L2 is worth building at all.** Two earlier rough counts (109 and 157)
disagreed and neither was reproducible. Re-derived 2026-09-01 with `plan-task-predicate.awk` as the
task-block boundary and `plan-budget-parse.awk` as the parser (both loaded, never restated — rule
6), over the 79 plans in `docs/superpowers/plans/`:

| Measure | Value |
|---|---|
| Task blocks, total | 672 |
| With a parseable `Budget:` | 159 (23.7%) |
| `MALFORMED` (an attempt that does not parse) | 0 |
| Median declared ceiling per task | 70 lines (q1 30, q3 160, max 430) |
| Plans fully budgeted / **mixed** / unbudgeted | 7 / **16** / 54 |

Both earlier estimates were wrong for the same underlying reason: they counted declared ceilings
per FILE, not summed per TASK — `parse_budget()` sums every paren-group ceiling on a `Budget:`
line, so a task naming three files with three ceilings is one task-level total, not three separate
counts. `TODO.md`'s open question is closed here, forward, with this derivation (rule 14).

**Two measured facts reshaped the design against the plan's original draft wording:**

1. **Mixed plans are the dominant budgeted shape (16 of 23), almost all at high coverage** (8/11,
   7/8, 8/9, 6/7 task blocks budgeted). A rule that closes a batch on encountering an unbudgeted
   task would fragment exactly the best-annotated plans in the corpus — the opposite of what L2 is
   for.
2. **The default budget is not a sensitive parameter.** Simulated across the corpus, a budget of
   105 through 350 lines changes only 15-22 of 77 candidate plans' batching. The mechanism is
   robust to the exact value, which shifts the design weight onto correctness at the edges (the
   hard cap, the floor, the fallback) rather than onto tuning.

## Decision

`step5-brief.sh --suggest-batches --plan <file> [--budget N]` (fourth mode of the ADR-0185 script,
not a new script — rule 6) computes batch ranges: fill a batch with **consecutive** task openers
while the sum of their declared `Budget:` ceilings stays at or under `--budget` (default **210
lines = 3x the corpus median (70), measured 2026-09-01** — not invented, not hand-tuned; it is the
value at which a batch of three median tasks fits exactly, which is why it reproduces today's
behavior on the typical plan and diverges only where tasks are genuinely large). **Hard cap 3 task
blocks, floor 1** — the same bound the fixed "2-3" rule already enforced.

**An unbudgeted or `MALFORMED` task never moves the running sum and never closes a batch by
itself** — only the hard cap of 3 does. This is a deliberate departure from the plan's original
draft language ("a `MALFORMED` task counts as absent, never as zero"), and the departure is worth
stating explicitly rather than leaving implicit: the draft's stated danger was a batch collapsing
to size 1 on a formatting slip. With 16 of 23 budgeted plans mixed, closing the batch on an
unbudgeted task would realize exactly that danger on all sixteen. The task still enters the batch —
it just does not affect sizing, and the hard cap remains the only thing that can end a batch early
regardless of budget state.

**Plan-wide fallback.** Zero parseable budgets anywhere in the plan → the mode reports
`mode\topeners` and returns ranges from plain opener grouping (fixed groups of ≤3), byte-identical
to today's policy. Covers 54 of 79 corpus plans.

**The controlling invariant: this can only shrink a batch relative to today's fixed grouping, never
grow it.** The hard cap is unchanged at 3; a declared budget can only close a batch earlier. Checked
against the implementation across the full corpus (79 plans, 77 with at least one task opener):
zero cases where the budget-driven range count came in lower than `ceil(openers/3)` — i.e., zero
cases of a bigger-than-today batch. Measured against the built implementation: **222 → 259 batches**
corpus-wide at the default budget (a 17% increase in batch count, meaning smaller batches). An
earlier pre-implementation simulation reported 245 → 282 for the same comparison; that simulation
counted raw opener LINES rather than deduplicated task designations, so it double-counted the ~66
"Task checklist" index-restatement lines ADR-0185 already documents (a task number can legitimately
open twice — the leading index line and the real heading). Both the "today" and "new" totals were
inflated by the same artifact, which is why the *conclusion* (never fewer batches, i.e. never
bigger) held either way; only the absolute counts needed correcting, and this ADR states the
verified ones, not the simulated ones.

**Contract — same CHECKER convention as the other three modes:** `0` ranges printed, `2` bad
invocation (includes a non-numeric or non-positive `--budget`), `3` DID-NOT-RUN (the plan has zero
task openers — the caller falls back to the fixed `2-3` grouping and **declares** the fallback
fired, rule 4).

**Scope: the Agent-tool fallback only, not the Workflow dispatch path.** `dispatch-state.sh`
measures 32 of 34 recorded dispatch modes as `agent_batch` against 2 `workflow` — the batch policy
this ADR changes is the one nearly every real run exercises. Leaving the Workflow path untouched
keeps the change surface to one call site and preserves `batch-dispatch-openers.test.sh`'s BO9b
assertion that the Workflow block never names a task-batching script.

**`step5-report.json` gains `batch_sizing`, a scalar OBJECT — not a seventh advisory array.**
ADR-0052 §D5 caps the Gate 5 roll-up at six consultative arrays and `diff-budget-scope.test.sh`
BG4 enumerates them by name; adding a seventh would break that bound. `batch_sizing` follows the
precedent `task_metrics` (ADR-0064 §D2) already set — a field documented in its own paragraph and
excluded by name from the six-array count — and is emitted **only when the dispatched ranges
diverge from the computed ones**; the normal case adds no line to the roll-up. Fields: `mode`,
`budget`, `computed`, `dispatched`.

**Enforcement vs. instruction, stated explicitly (rule 16).** The batch-range *calculation* is
enforcement — shell, exit-coded, testable, corpus-verified. That the orchestrator actually
dispatches those ranges is instruction: nothing here stops a dispatch from ignoring the suggestion.
`batch_sizing` does not convert the instruction half into enforcement — it makes a divergence
visible after the fact, which is the limit of what is affordable here.

**Rejected alternative: infer a budget from the task's own text when none is declared.** ADR-0052
§A3 already rejected this by name for `diff-budget-check.sh` — a machine-generated estimate
compared against machine-generated work has no human intent in the loop and measures nothing. L2
consumes only budgets the architect explicitly declared; an absent one is absent, never inferred.

## Consequences

### Positive

- Batch sizing now reflects declared work on the 23 of 79 corpus plans (29%) that carry at least
  one `Budget:` line, without ever producing a larger batch than today's fixed rule on any plan.
- The default (210) is derived, dated, and measured robust to its own value — not a number chosen
  by feel, and not one that needs re-tuning as the corpus grows unless the median itself shifts
  materially.
- `batch_sizing`'s divergence-only emission keeps Gate 5's roll-up exactly as quiet as ADR-0052 §D5
  requires in the normal case.

### Negative

- The 54 of 79 plans with zero declared budgets see no behavior change — L2's benefit is
  conditional on the architect actually writing `Budget:` lines, which this ADR does not mandate.
- A task whose declared ceiling is itself wrong (the architect's estimate, not the coder's actual
  diff) still drives sizing; `diff-budget-check.sh`'s post-hoc overshoot check is unaffected by this
  ADR and remains the only place that catches the estimate being wrong after the fact.
- Inert until `sync-to-claude.sh --apply`, like every change to a deployed script.

### Neutral

- No manifest field, no schema bump beyond the optional `batch_sizing` object, no new state-machine
  transition.
- ADR-0052's "inert by default" framing and ADR-0070's "the one plan that has any" framing were
  correct snapshots of their day (2026-07-26, 2026-07-30) — 23.7% task-level coverage, measured
  today, does not retroactively falsify either; both are left as they were written (rule 14).

## References

- `staging/plugin/skills/concept-to-code/scripts/step5-brief.sh` — `--suggest-batches` mode
- `staging/plugin/skills/concept-to-code/scripts/plan-budget-parse.awk` — the loaded parser,
  unmodified by this ADR
- `staging/plugin/scripts/tests/step5-brief.test.sh` — the extended assertions for this mode
- `staging/plugin/scripts/tests/batch-dispatch-openers.test.sh` — the flattened-prose assertion on
  the new call-site text
- `staging/plugin/skills/concept-to-code/references/step5-implementation.md` — the batch-dispatch
  policy paragraph and the `step5-report.json` schema section
- `docs/architecture/ADR-0185-step5-task-brief.md` — L1, the script this extends
- `docs/architecture/ADR-0052-106-diff-budget-scope-check.md` §D5 (the six-array bound), §A3 (the
  rejected inference alternative)
- `/Users/stefer/.claude/plans/zippy-whistling-crescent.md` — the approved plan, Fase 2 §L2
