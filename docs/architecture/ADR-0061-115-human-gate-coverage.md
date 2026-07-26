# ADR-0061 — Human-gate coverage: test diff (H4) and direction check (H16)

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #115 (sixteenth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/115-human-gate-coverage.spec.md`
- **Builds on:** ADR-0049 (#103) — H4 exists for the same reason generator/verifier separation does.
  ADR-0052 (#106) §D5, whose advisory-accumulation warning constrains how H16 may be delivered.
- **Closes:** gap **G-24** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (PARTIAL, P2).

## Context

The spec's human gates H1–H20 are mostly covered here: H1/H2/H3 by c2c Gates 2/1/2; H5/H6/H7 by
`commit/SKILL.md:174-207`; H8 by the settings deny list plus `agent-command-scope.sh`; H12 by
`review-triage-fix`; H14 by `db-backup-guardrail.sh`.

Two are missing.

**H4 — test eyeballing.** Nobody is ever asked to read the tests. The commit gate shows a file
list, and a test file appears in it as one line among many. The spec makes this a human gate
*precisely because AI-written tests are themselves suspect*, which is the same premise ADR-0049
acted on when it separated the tester from the coder. #103 fixed who *writes* the tests; nothing
fixed who *reads* them.

**H16 — the periodic direction check.** "Let's double-check, is this the right direction?" No
mechanism asks it.

## Decision

### D1 — The commit gate shows the test diff as its own section

Not a line in a file list — a separate, labelled section showing what changed **inside** the test
files, above or beside the message and file list that `commit` Step 4 already presents.

The reasoning is the reasoning for the whole roadmap: the tests are the accept decision. A green
suite means the implementation satisfies the tests, so a test the human never read is an accept
decision the human never made. #105's detectors catch some ways that goes wrong mechanically; H4 is
the case where nothing mechanical will help and a person has to look.

When the change set touches no test files, the section is omitted entirely — not shown empty. A
section that usually says "none" trains the eye to skip it, and it is the one section that must not
be skipped.

### D2 — H16 triggers on accumulated evidence, not on a counter

This is the decision that determines whether H16 is useful or ignored.

A direction check on a fixed cadence — every N features, every N commits — becomes furniture. It
fires when nothing is wrong, the answer is always "yes, continue", and by the time it fires when
something *is* wrong it has been trained into a reflex click. ADR-0052 §D5 already recorded that
Gate 5's advisory load is the live risk in this system; a periodic prompt with no signal behind it
makes that worse in the most literal way.

So H16 fires on **evidence the system already collects**:

- accumulated `budget_findings` overshoots across features (ADR-0052),
- repeated out-of-scope file findings — work landing where no plan declared it,
- a feature reaching `amber` or `red` at the tracer probe (ADR-0057),
- `suspect_findings` recurring in the same area (ADR-0051).

Those are the conditions under which "is this the right direction?" is a real question rather than a
ritual. Reusing signals already computed also means H16 costs no new measurement — the same
collection ADR-0047 §A1 made when a new detector reached four call sites with no second edit.

### D3 — H16 asks, it does not block

It surfaces the question with the evidence that raised it, and records the answer. It does not halt.

A blocking direction check would be a gate whose trigger is a bundle of heuristics, and this roadmap
has established four times now (ADR-0051 §D2, ADR-0053 §D2, ADR-0054 §D5, ADR-0058 §D4) that
heuristics report and mechanical facts gate. Every input to §D2's trigger is a heuristic.

### D4 — H4 is shown, not summarised

The gate shows the actual diff, not a model's description of it. A summary of a test diff is a
generated artefact standing between the human and the thing they are being asked to verify, which
defeats the gate — the same objection ADR-0057 §D3 made to a self-assessed tracer verdict, and
ADR-0047 §D-trust made to trusting an agent's `weakening_findings` self-report.

Truncation for very large diffs is acceptable and must be **labelled as truncated with the full
command to see the rest**. Silent truncation is worse than no gate, because it looks like the whole
thing.

## Alternatives rejected

- **A1 — Leave test files in the general file list.** Rejected under §D1: that is the current
  behaviour and the gap.
- **A2 — Show an LLM summary of the test changes.** Rejected under §D4.
- **A3 — Fire H16 every N features.** Rejected under §D2 — becomes furniture, and trains the reflex
  click that makes it useless when it matters.
- **A4 — Make H16 blocking.** Rejected under §D3: its every input is a heuristic.
- **A5 — Show the test-diff section always, empty when there are no test changes.** Rejected under
  §D1: a section that usually says "none" is a section the eye learns to skip.

## Consequences

### Positive

- The tests — the actual accept criteria — are put in front of a human before the commit click,
  which no gate did before.
- H16 asks its question when there is a reason to, using signals four earlier features already pay
  to collect.
- No new measurement, no new advisory array.

### Negative, stated plainly

- **H4 is a prompt to look, and looking is not guaranteed.** A human can click through a test diff
  as easily as a file list. The gate makes it possible to notice, not certain.
- **H16's trigger inherits every false-positive rate feeding it**, including `literal-assertion-added`
  which ADR-0051 measured at 25% precision and shipped disabled. If H16 proves noisy, the fix is to
  narrow which signals feed it — not to fall back to a timer.
- **Large test diffs will be truncated**, and truncation is where a hostile change would hide. The
  label mitigates; it does not solve.
- `commit/SKILL.md` still has no test coverage of its own (recorded in ADR-0046), so this change
  lands in a file whose behaviour is pinned only indirectly.
