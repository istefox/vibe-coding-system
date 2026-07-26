# ADR-0052 — Per-task diff budget and scope check

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #106 (seventh feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/106-diff-budget-scope-check.spec.md`
- **Builds on:** ADR-0051 (#105) for the advisory-surfacing pattern — and §D5 below is where that
  pattern's cost finally has to be paid rather than deferred again.
- **Closes:** gap **G-09** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (PARTIAL, P2).

## Context

The agentic spec makes microscopic batch size non-negotiable (§5.7), for a reason that is about
humans rather than about code: a diff nobody can hold in their head is a diff nobody actually
reviews, so an oversized batch silently converts the human review gate into a rubber stamp.

This system bounds several adjacent things and not that one. `deep-refactor` treats 400-line files
and 60-line functions as findings of a whole-codebase *audit*, not as gates on a diff.
`write-scope-enforce.sh` bounds a Step 6 Phase 3 fix agent to one assigned file.
`review-triage-fix` caps coder dispatches at four per cycle. `coder.md:75` says "no new dependencies
unless the plan calls for them" — at the prompt level only.

Nothing compares a coder's actual diff against what the plan said that task would touch.

## Decision

### D1 — The budget is optional, declared per task, and inert when absent

The architect's plan template gains an optional per-task budget: expected files touched and an
approximate ± line ceiling. A plan task without one is not a defect and produces no finding.

Inertness is not a nicety here. More than thirty plans already exist in `docs/superpowers/plans/`
and none carry a budget; a check that required one would either need a migration or would report
every historical plan as violating a rule written after it. Absent means silent.

### D2 — Comparison happens at the Step 5 checkpoints that already exist

At each checkpoint, `git diff --stat` for the batch is compared against the summed budget of the
tasks in it. No new checkpoint mechanism — ADR-0039 §D5 already established the checkpoint as a
`pipeline()` stage and never a barrier.

### D3 — Over-budget surfaces; it does not block

The issue says this outright and it is correct. A line ceiling is an *estimate made before the work*
by an agent that has not read every file it will touch. It will be wrong regularly and in both
directions. A gate that halts on a wrong-more-often-than-the-coder estimate would be routed around
within a week, and would be worse than not having one.

So: over-budget and out-of-scope findings go to the user and into `step5-report.json` as an
additive `budget_findings` array (`{task, files_expected, files_actual, lines_expected,
lines_actual, out_of_scope[]}`). The seventh additive extension of that schema, same terms as
`suspect_findings`.

### D4 — Out-of-scope files are the more valuable half, and are flagged separately

A file touched that appears in **no** declared task scope in the whole plan is a different and
stronger signal than a line count overshoot. Line counts are estimates; "the plan never mentioned
this file" is closer to a fact. It is reported as its own finding type rather than folded into the
budget overshoot, because conflating a soft signal with a firm one degrades the firm one — the same
reasoning ADR-0051 §D2 used to keep `SUSPECT` out of `WEAKENED`.

Exclusions: files the chain itself writes (the manifest, `step5-report.json`, `SPEC.md`), and files
matched by an explicit plan-level `scope:` declaration for cross-cutting work.

### D5 — Gate 5's advisory load is now the actual risk, and this ADR bounds it rather than adding to it

**This is the decision that matters most and it is not in the issue.**

`step5-report.json` now carries `weakening_findings`, `requirement_coverage`, `checkpoint_reviews`,
`tests_written_by`, `suspect_findings` and — with this change — `budget_findings`. Three of those
arrived in the last three features, all advisory, all justified individually by the same argument:
"blocking would be too noisy, so we surface instead."

Each of those arguments was sound. Their sum is not. ADR-0047 §D7's lesson was that *a report nobody
must act on is a report nobody reads*, and the way that failure actually arrives is not one
unreadable report — it is six readable ones stacked into a Gate 5 summary that gets skimmed.

So this feature adds its findings under two constraints:

1. **The Gate 5 summary prints advisory findings as a single roll-up line when all are empty** —
   one line saying so, not six saying nothing. Volume must track signal, not schema size.
2. **`budget_findings` prints at most the top N overshoots by margin**, with a count of the
   remainder. A per-task enumeration of a 40-task plan is not a summary.

This does not solve advisory accumulation; it stops this feature from making it worse. A real
answer — ranking findings across all six arrays by severity, or making some of them blocking once
their false-positive rates are measured — is a separate piece of work and is named here so it is not
mistaken for done.

### D6 — The budget is prose in a plan, parsed leniently

Declared inline on the task line in a form the architect already writes naturally, parsed with a
tolerant matcher. A budget that fails to parse is treated as absent (§D1), never as zero — a
strict parser would turn a formatting slip into a finding on every file the task touched.

## Alternatives rejected

- **A1 — Block on over-budget.** Rejected under §D3. The estimate is made before the work by an
  agent that has not read the files.
- **A2 — Make the budget mandatory in the plan template.** Rejected under §D1: needs a migration of
  30+ existing plans and makes every historical plan retroactively non-conforming.
- **A3 — Derive the budget automatically from the task text.** Rejected: a machine-generated
  estimate compared against machine-generated work, with no human intent anywhere in the loop, is a
  number that measures nothing.
- **A4 — Fold out-of-scope files into the budget overshoot finding.** Rejected under §D4:
  conflating a firm signal with a soft one degrades the firm one.
- **A5 — Add the findings to Gate 5 the way the previous three features did.** Rejected under §D5.
  This is the alternative that would have been taken by default.

## Consequences

### Positive

- The system finally compares what a coder *did* against what the plan *said*, which no existing
  check does.
- Out-of-scope file detection (§D4) catches the class of drift that produced ADR-0049 §D5's stale
  restatement and #93's undeployed fix — work landing in files nobody declared.
- §D5's roll-up shrinks the Gate 5 summary in the common all-clear case rather than growing it.

### Negative, stated plainly

- **Blocks nothing** (§D3). Third advisory feature in a row, and §D5 is an acknowledgement of that
  trajectory, not a fix for it.
- **Budgets will be wrong.** They are pre-work estimates. The finding says "this diverged from the
  plan", which is information, not a verdict.
- **Inert by default** (§D1): until architects actually write budgets, this feature reports nothing
  on most runs. That is the correct trade for not requiring a migration, and it does mean the
  feature's real value arrives later than its merge.
- Instruction, not enforcement, throughout — the harness pins that the check and the roll-up exist,
  never that a model performs them.
