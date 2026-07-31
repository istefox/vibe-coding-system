# SPEC — seventeen ADRs carry the same instruction-not-an-enforcement paragraph and the class is undecided

Source: GitHub issue #315

## Objectives

1. Derive three populations rather than copying them from the issue: the
   instruction-not-enforcement cluster (for each, whether a mechanism is buildable at all and what
   its blast radius would be); the 51 DOC-class residuals (stale counts, prose-versus-tree drift,
   cost notes); and the threat-model bypasses pinned as expected-ALLOW by their own tests.
2. Produce one ADR giving every unfixed residual an explicit disposition — mechanism (with the issue
   that will build it), accepted (with the reason), or superseded (naming the ADR) — with the
   accepted set stated as accepted rather than as pending.
3. Give the already-closed ADRs a dated `Correction` section rather than an edited body, and state
   how the disposition is kept current, or that the next sweep is the mechanism.

## Scope

In: the disposition of every residual left unfixed by the preceding features of this roadmap; the
`Correction` sections on ADRs whose residual a later ADR already closed; the currency mechanism (or
the explicit statement that the next sweep is it).

Out: building any of the mechanisms this disposition names — each is a separate issue by
construction; editing historical ADR bodies (the ADR-0034 precedent, restated by R-03); re-opening
decisions that a preceding feature of this roadmap already settled.

**Ordering constraint:** this is the terminal feature of Phase 10 and must run last. It disposes of
everything the preceding features did not fix, so its populations are not stable until they have
run.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime. This feature's deliverable is
principally documentation under `docs/architecture/`.

## Architecture

- `PROJECT.md` §9.5 ("One decision, not four") and its roadmap table row — the framing this issue
  inherits: "worth deciding once whether any deserve a mechanism, rather than re-disclosing each
  time."
- The instruction-not-enforcement cluster, resolved in `docs/architecture/`:
  `ADR-0047-101-weakening-scan-wiring.md`, `ADR-0048-102-requirement-ids-coverage.md`,
  `ADR-0050-104-recovery-readiness-preflight.md`, `ADR-0051-105-reward-hacking-detectors.md`,
  `ADR-0052-106-diff-budget-scope-check.md`, `ADR-0055-109-proportional-audit-depth.md`,
  `ADR-0056-110-sast-security-audit.md`, `ADR-0057-111-tracer-bullet-probe.md`,
  `ADR-0060-114-external-dependency-gate.md`, `ADR-0062-116-litter-debris-discipline.md`,
  `ADR-0063-117-canonical-mechanism-conformance.md`,
  `ADR-0088-241-test-authoring-split-granularity.md`,
  `ADR-0097-237-gate4-implementation-axes.md`, `ADR-0098-227-gate0-recommendation.md`,
  `ADR-0099-238-hitl-gate-audit-trail.md`, `ADR-0101-247-batch-boundary-precedence.md`,
  `ADR-0103-244-recovery-baseline-rebase.md`. The issue cites a line number per ADR; every one of
  those will have moved, so the paragraph itself is the anchor and the population must be re-derived
  by searching for it.
- The blast-radius precedents that the derivation must test rather than assume generalise:
  ADR-0047 §A2 and ADR-0048 both rejected enforcement in
  `staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh` — a 48-pair state machine
  that touches no git today and would gain a new failure mode on every transition.
- The expected-ALLOW threat-model bypasses and the hooks they belong to:
  `staging/plugin/scripts/agent-command-scope.sh` (ADR-0045 section E, ADR-0079 `J5`) and
  `staging/plugin/scripts/write-scope-enforce.sh` / `agent-write-scope.sh` (ADR-0074). These are
  closed by decision, never by code: `subprocess.run(["git","push"])` splits the verb across list
  elements and variable splicing defeats a command-position guard by construction.
- The corresponding tests that pin those bypasses as expected-ALLOW:
  `staging/plugin/scripts/tests/agent-command-scope.test.sh`,
  `staging/plugin/scripts/tests/write-scope-enforce.test.sh`,
  `staging/plugin/scripts/tests/agent-write-scope.test.sh`.
- `docs/architecture/ADR-0034-38-hook-hardening.md` — the precedent R-03 names: a correction is
  recorded forward, never by editing a historical body. ADR-0107 is the most recent application,
  having added dated `Correction` sections to four ADRs whose consequence bullets became false.
- `staging/plugin/skills/adr-writer/` — the skill that writes the deliverable.
- `staging/plugin/scripts/tests/plant-check.sh` and the plant registry (ADR-0108), for any assertion
  this feature ships.

## Data model

The disposition record: one entry per unfixed residual, carrying at minimum the residual's source
(ADR and anchor), its class (instruction-not-enforcement, DOC, expected-ALLOW bypass), and its
disposition — `mechanism` (naming the issue that will build it), `accepted` (with the reason), or
`superseded` (naming the ADR). Its storage is TBD: the issue requires one ADR, and whether the record
is also machine-readable follows from the R-04 currency decision.

## API / Interfaces

None required by the issue. If R-04's answer is a mechanism rather than "the next sweep", it takes
the repository's standing contract: a checker branches on an exit code and distinguishes "did not
run" (exit 3) from "found nothing"; a reporter always exits 0 and signals on stdout.

## UI flows

None.

## Edge cases

- A residual that a preceding Phase 10 feature closed while this feature was being written: the
  populations are not stable until the terminal position is honoured, which is why the ordering
  constraint is part of the scope.
- A residual already closed by a later ADR with nobody updating the earlier one — the sweep that
  produced this roadmap found 14 of these among 191 open items. R-03 governs how they are recorded.
- A residual whose mechanism is buildable but whose blast radius is disqualifying: `accepted` with
  the reason, not `mechanism` with no issue behind it.
- An `accepted` disposition that still reads as an open defect is the failure R-02 names; the phrasing
  is the deliverable, not a side effect.
- The expected-ALLOW bypasses are pinned by tests that will fail if someone "closes" one, and the
  threat-model paragraph is required to move with the code (ADR-0045). A disposition that reads as
  "should be fixed" contradicts a live assertion.
- A disposition record with no currency mechanism decays exactly as the disclosures did; R-04 forbids
  leaving that unstated, and "the next sweep is the mechanism" is an acceptable answer only if it is
  written as one.
- Rule 12 applies with force here: any scan whose needle is the instruction-not-enforcement
  paragraph will match this feature's own ADR, which necessarily quotes it, and will match every
  disposition entry that names it.
- The issue's "Standing rules for this repository" footer is implementer guidance, not a source of
  requirements; the four criteria below are the whole set.

## Success criteria

- [ ] R-01 — one ADR giving every unfixed residual an explicit disposition: mechanism (with the
      issue that will build it), accepted (with the reason), or superseded (naming the ADR).
- [ ] R-02 — the accepted set is stated as accepted, not as pending. A residual nobody intends to
      fix must not keep reading as an open defect.
- [ ] R-03 — the ADRs whose residual was already closed by a later ADR receive a dated `Correction`
      section rather than an edited body, per the ADR-0034 precedent.
- [ ] R-04 — a mechanism for keeping the disposition current, or an explicit statement that the next
      sweep is the mechanism.
