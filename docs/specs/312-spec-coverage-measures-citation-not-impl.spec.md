# SPEC — spec-coverage measures citation not implementation

Source: GitHub issue #312

## Objectives

1. Quantify, over the existing corpus of SPECs and plans, how often a cited `R-NN` id corresponds to
   a real assertion versus a bare mention.
2. Decide what is actually checkable: the gate cannot verify that an implementation is correct, but
   it may be able to verify that the citing test contains an assertion rather than a comment.
3. Tighten the gate so a no-op task and a comment-only mention no longer read as covered, without
   losing the silent-pass property for a SPEC with no ids and without creating a new false-negative
   class.

## Scope

In: `spec-coverage.sh`'s coverage predicate — the plan-task token extraction and the whole-file
token match against discovered tests; the corpus measurement over `docs/specs/` and
`docs/superpowers/plans/`; the Step 5 → Step 6 gate that consumes it.

Out: verifying that an implementation is correct; the unrecognised-heading inertness, which is
issue #313's subject; the near-miss plain-bullet repair, which ADR-0072 already shipped; the
`R-NN` boundary-anchoring rule established by ADR-0048.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` — the checker. It declares ids
  from checklist items inside a recognised SPEC section, extracts plan tokens from task lines via an
  embedded awk program, emits `MALFORMED` / `DUPLICATE` / `ORPHAN` structural tokens with exit 3,
  takes the silent no-IDs path when `DECL_N` is 0, and matches test coverage by whole-file token
  match over discovered tests.
- `staging/plugin/skills/concept-to-code/scripts/spec-id-predicate.awk` and
  `staging/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk` — the loaded predicates
  (`heading_level()`, `is_checklist_item()`, `is_task_heading()`, `is_task_line()`,
  `is_spec_section_heading()`). ADR-0069 and ADR-0072 both established that the predicate is loaded,
  never pasted.
- `staging/plugin/skills/concept-to-code/SKILL.md` — the Step 5 → Step 6 gate block, where
  `spec-coverage.sh` is a **checker** (branch on exit code) sitting a few lines from
  `weakening-scan.sh`, a **reporter**, with an explicit instruction not to copy one block's
  branching into the other. `step5-report.json` carries the additive `requirement_coverage` object
  (`ids_declared`, `uncovered`, `status`).
- `docs/architecture/ADR-0048-102-requirement-ids-coverage.md` — the source. The issue cites a line
  number for "an ID cited by a no-op task and a no-op test is fully covered" and for the
  false-positive-direction note; those line numbers will have moved, so the sentences are the
  anchors.
- The corpora: `docs/specs/*.spec.md` (36+ files) and `docs/superpowers/plans/*.md` (57+ files),
  plus `staging/plugin/scripts/tests/*.test.sh` as the discovered-test population.
- `staging/plugin/scripts/tests/spec-coverage.test.sh` — the existing harness, including the
  section that runs the checker over every existing SPEC with a count guard against a vacuous loop.
- `staging/plugin/scripts/tests/plant-check.sh` and the plant registry (ADR-0108).

## Data model

The `requirement_coverage` object already written into `step5-report.json`: `ids_declared`,
`uncovered`, `status`. Whether a tightened predicate needs an additional field is TBD and follows
from the decision in objective 2; the schema is additive by the same terms as `step5_mode`,
`checkpoint_reviews`, `weakening_findings` and `plan_deviations`, with no version bump.

## API / Interfaces

- `spec-coverage.sh` — existing CLI: `--spec`, `--plan`, `--tests-root`, `--list`. It is a
  **checker**: exit 0 on pass, exit 3 for the structural tokens and for "did not run", and the
  standing rule requires "did not run" to stay distinct from "found nothing".
- The Step 5 → Step 6 gate block in `concept-to-code/SKILL.md`, which branches on that exit code.
- The loaded awk predicates, which are the one place the recognition rules are decided.

## UI flows

None. Output is checker text read by the orchestrator at the Step 5 → Step 6 boundary and by a human
reading the resulting halt.

## Edge cases

- A SPEC with genuinely no ids must keep passing silently — exit 0, empty stdout, empty stderr —
  asserted over all existing SPECs with a count guard against a vacuous loop (R-02).
- The `.md` exclusion in test discovery exists because without it `--tests-root <project-root>`
  discovers `docs/specs/<slug>.spec.md` as a test file for its own ids, making every SPEC trivially
  self-covered. Any change to the coverage predicate must keep that closed.
- A comment-only mention of an id inside a test file: the case the tightened predicate is meant to
  stop reading as covered. Distinguishing a comment from an assertion is language-dependent, and the
  harness population here is shell.
- A legitimately covered requirement whose citing assertion the new predicate cannot see: the
  false-negative class R-03 forbids, and it must be proven absent over the corpus rather than
  argued.
- The false-positive direction of the current whole-file token match is toward passing, which is the
  wrong direction for a gate; a tightened rule inverts that direction and therefore changes what a
  halt means.
- A no-op plan task that cites an id: recognised as a task by `is_task_line()` regardless of whether
  it does anything, since a plan is prose.
- Rule 12: any needle over `spec-coverage.sh` or its SKILL.md block will match the prose that
  explains the mechanism, including this feature's own SPEC.

## Success criteria

- [ ] R-01 — a no-op task and a comment-only mention no longer read as covered.
- [ ] R-02 — the silent-pass property for a SPEC with no ids is preserved exactly: exit 0, empty
      stdout, empty stderr, asserted over all existing SPECs with a count guard against a vacuous
      loop.
- [ ] R-03 — no new false-negative class: a legitimately covered requirement must not start failing,
      proven over the corpus.
