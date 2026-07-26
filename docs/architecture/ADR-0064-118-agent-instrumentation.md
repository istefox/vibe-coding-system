# ADR-0064 — Agent-level instrumentation metrics

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #118 (nineteenth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/118-agent-instrumentation.spec.md`
- **Closes:** gap **G-23** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (PARTIAL, **P3**).

## Context

`usage-report.py` gives daily tokens, cache hit rate and agent dispatch counts, and states plainly
that sub-agent token cost is **not locally observable** — Claude Code does not persist sub-agent
turns as sidechain entries with their own usage. `usage-snapshot.py` diffs are logged per chain.
`vibe-status` aggregates system health.

None of the spec's control metrics exist: test-count delta per task, deleted lines per task, claim-
vs-reality mismatch count, iteration count, session duration. Those are the inputs to rut detection
(§7 cases 7 and 8) and to any per-agent trust score. Wait time per phase boundary — the actual
constraint per §8.4 — is not measured either.

## Decision

### D1 — Four cheap metrics per task, into schemas that already exist

Test-count delta, deleted lines, iteration count, elapsed wall time. Into `step5-report.json` and
`nightly-report.json`, both of which already have a schema and a reader.

Cheap is the selection criterion. Each is derivable from git or a timestamp at effectively zero cost,
which is what makes four of them affordable where one expensive metric would not be.

### D2 — These are METRICS, not findings, and that distinction is load-bearing

ADR-0052 §D5 recorded that Gate 5's advisory load is the live risk in this system, and six advisory
arrays now exist. This feature adds four more fields and must not make that worse.

It does not, because a metric and a finding are different things. **A finding asserts something is
wrong and asks for a decision. A metric is a number with no claim attached.** Findings compete for
attention at a gate; metrics accumulate for later analysis and are read when someone goes looking.

So these are **not surfaced at Gate 5**, not counted in the advisory roll-up, and not presented as
requiring action. They land in the report for the analysis that rut detection and trust scoring will
eventually need. This ADR builds the inputs, not the detector.

### D3 — Absent means "not recorded", never zero

The distinction that matters most, and the one this codebase keeps relearning.

A task with `deleted_lines: 0` genuinely deleted nothing. A task with the field absent was never
measured. Collapsing those makes every historical task look like a well-behaved one and quietly
poisons any future analysis built on the data.

This is ADR-0046's exit-code lesson (scan-completed-with-no-findings must be distinguishable from
scan-did-not-run), ADR-0043's completeness lesson (a check that reports nothing must be
distinguishable from one that finds nothing), and ADR-0048's silent-pass rule, applied to stored
data rather than to a check.

Additive fields, conditional-if-present, no schema bump, no migration.

### D4 — Every metric is computed, never self-reported

Test-count delta and deleted lines come from git. Iteration count and elapsed time come from the
dispatch loop. None is an agent's answer to a question about itself.

That is the same rule ADR-0047 §A3, ADR-0048 §A7, ADR-0055, ADR-0057 §D3 and ADR-0062 §D2 each
applied in their own domain, and it is why these four were chosen over the spec's
claim-vs-reality mismatch count — which cannot be computed without an agent adjudicating its own
claims, so it is deferred rather than approximated badly.

### D5 — Sub-agent token cost stays unobservable, and is not faked

`usage-report.py` already documents that it is not locally observable. Nothing here changes that,
and no estimated or modelled figure is introduced. An estimate that looks like a measurement is
worse than a gap that is labelled — the same reasoning ADR-0058 §D5 used to reject an independent
token counter.

## Alternatives rejected

- **A1 — Surface the metrics at Gate 5.** Rejected under §D2: they carry no claim, and adding four
  more lines to a gate whose advisory load is already the recorded risk would degrade the findings
  that do need action.
- **A2 — Default absent metrics to zero.** Rejected under §D3. This is the tempting simplification
  and it destroys the dataset.
- **A3 — Include claim-vs-reality mismatch count.** Rejected under §D4: not computable without
  self-adjudication. Deferred, not approximated.
- **A4 — Estimate sub-agent token cost.** Rejected under §D5.
- **A5 — Build rut detection now.** Rejected as premature: no corpus exists yet, so any threshold
  would be invented rather than measured — and ADR-0051 established that this system measures
  detector behaviour against a real corpus before shipping it.

## Consequences

### Positive

- The inputs to rut detection and trust scoring start accumulating, which is the precondition for
  ever building either.
- Four metrics at near-zero cost, into two schemas that already have readers.
- Nothing added to the Gate 5 advisory load (§D2).

### Negative, stated plainly

- **This ships data collection with no consumer.** Its value is entirely deferred, and if the
  detector is never built the metrics are dead weight. That is an accepted bet, not an oversight.
- **Wall time measures the wrong thing on an unattended run** — it includes queueing, rate limiting
  and anything else in the way. It is a coarse signal and should not be read as agent effort.
- **Test-count delta is not test-quality delta.** #105's detectors exist precisely because a test
  count can rise while test value falls, and nothing here connects the two.
- **The corpus starts empty**, so any analysis is months away from being meaningful.
