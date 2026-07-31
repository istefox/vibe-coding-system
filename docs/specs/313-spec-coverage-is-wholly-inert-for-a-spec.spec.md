# SPEC — spec-coverage is wholly inert for a SPEC whose criteria sit under an unrecognised heading

Source: GitHub issue #313

## Objectives

1. Enumerate the headings `spec-coverage.sh` recognises and run it over every SPEC in `docs/specs/`,
   reporting which section each id was found in.
2. Determine whether ADR-0072 §D5's asymmetry applies here — an id outside every recognised section
   is only evidence when nothing was declared, while a near-miss inside one has no innocent reading
   — or whether an unrecognised heading is unambiguous.
3. Make a SPEC whose ids sit under an unrecognised heading reported rather than silently skipped,
   while keeping a genuinely id-free SPEC on the silent path, and bounding any detection by the
   reach of its repair.

## Scope

In: `spec-coverage.sh`'s section recognition (`is_spec_section_heading()`) and the silent no-IDs
path; the corpus sweep over `docs/specs/`; the reported-versus-silent distinction; a repair paired
with detection if ADR-0072's pattern applies.

Out: the citation-versus-implementation weakness of the coverage predicate itself, which is issue
Issue #312's subject; the plain-bullet near-miss, already repaired by `spec-normalize-ids.sh` under
ADR-0072; widening the checker to "any `R-NN` anywhere", which ADR-0048 rejected by name.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` — the checker. Its header states
  that a SPEC emitting IDs under an unrecognised heading yields `MALFORMED`, exit 3, never widened
  to "any `R-NN` anywhere". Its stderr message names the recognised set: **Success criteria,
  Acceptance criteria, Definition of done**. A guard (`GUARD_FIRED`) already exists for a well-formed
  id found outside every recognised section, and the near-miss guard (`NEARMISS_FIRED`) sits beside
  it; the two differ in whether they are conditioned on `DECL_N == 0`, which is exactly the ADR-0072
  §D5 asymmetry this issue must re-examine.
- `staging/plugin/skills/concept-to-code/scripts/spec-id-predicate.awk` — `is_spec_section_heading()`
  and the id recognition rules; loaded alongside `plan-task-predicate.awk`, never pasted (ADR-0072
  §D6).
- `staging/plugin/skills/concept-to-code/scripts/spec-normalize-ids.sh` — ADR-0072's repairer, the
  precedent for detect-and-heal and the source of the rule that the repair's reach bounds the
  detection.
- `staging/plugin/skills/concept-to-code/SKILL.md` — the Step 5 block that runs the checker and, for
  the near-miss cause, runs the repairer automatically and prints the diff.
- `staging/plugin/skills/spec-from-issue/` and `staging/plugin/skills/interview-driver/` — the two
  SPEC producers, both of which write a `## Success criteria` heading; a SPEC arriving from anywhere
  else is where the unrecognised heading comes from.
- `docs/architecture/ADR-0048-102-requirement-ids-coverage.md` — the source. The issue cites a line
  number for "the gate is inert for a SPEC that puts its criteria under an unrecognized heading";
  that line number will have moved, so the sentence is the anchor.
- `docs/architecture/ADR-0072-171-spec-id-near-miss-self-repair.md` — §D4 (the repair's reach bounds
  the detection) and §D5 (the asymmetry), plus the record that issue #171 was this shape one level
  down.
- The corpus: `docs/specs/*.spec.md`, plus `SPEC.md` at the repository root.
- `staging/plugin/scripts/tests/spec-coverage.test.sh` — the existing harness, with the section that
  runs the checker over every existing SPEC and count-guards the loop.
- `staging/plugin/scripts/tests/plant-check.sh` and the plant registry (ADR-0108).

## Data model

None. The sweep's working data is, per SPEC, the heading each recognised id was found under; no
persistent record is implied by the issue.

## API / Interfaces

- `spec-coverage.sh` — existing CLI (`--spec`, `--plan`, `--tests-root`, `--list`) and exit-code
  contract: 0 on pass, 3 for the structural tokens (`MALFORMED`, `DUPLICATE`, `ORPHAN`) and for "did
  not run". No new stdout token was needed for ADR-0072's near-miss, which reported as `MALFORMED`
  with the cause distinguished on stderr; the same option is open here.
- `spec-normalize-ids.sh --spec <path> [--apply]` — the existing repairer, if the detection is
  paired with a repair.
- `is_spec_section_heading()` in `spec-id-predicate.awk` — the one place the recognised set is
  decided.

## UI flows

None. Output is checker text read by the orchestrator at Step 5 and by a human reading the resulting
halt, plus the printed diff when a repair is applied.

## Edge cases

- A SPEC with genuinely no ids must still pass silently — the two states must stay distinguishable
  (R-02), and that silent path is documented behaviour, not an oversight.
- ADR-0072 §D4's invariant: every flagged case must become readable once repaired, or the gate
  reports a problem, rewrites the file and still fails. A heading whose repair is ambiguous — rename
  to which of the three recognised headings? — is outside detection under that rule.
- A bold-wrapped id (`- [ ] **R-01**`) is invisible to the checker in both forms; ADR-0072 pinned it
  as a pre-existing blind spot and it is not this issue's subject.
- An id appearing in prose under a non-criteria heading (a Scope or Architecture paragraph naming
  `R-01`): a heading-based rule must not turn ordinary cross-reference prose into a finding.
- The heading level matters: `is_spec_section_heading()` collects until the next level-1 or level-2
  heading, so a criteria list nested under a level-3 heading behaves differently from one under its
  own level-2.
- A SPEC written by hand rather than by `interview-driver` or `spec-from-issue` is the realistic
  producer of an unrecognised heading; the two generators both write `## Success criteria`.
- Rule 12: a needle naming a recognised heading will match the checker's own stderr message and
  header prose, which name all three.

## Success criteria

- [ ] R-01 — a SPEC with ids under an unrecognised heading is reported, not silently skipped.
- [ ] R-02 — a SPEC with genuinely no ids still passes silently; the two must stay distinguishable.
- [ ] R-03 — if detection can be paired with repair as ADR-0072 did, the repair's reach bounds the
      detection: every flagged case must become readable once repaired.
