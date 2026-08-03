# SPEC — a bold-wrapped requirement id is invisible to both the checker and the repairer

Source: GitHub issue #291

## Objectives

1. Run `spec-coverage.sh` over a SPEC declaring `- [ ] **R-01** — …` and confirm the id reaches
   neither the declared set nor the malformed set — the silence ADR-0072 §D4 named and left unfixed.
2. Decide whether a bold-wrapped id reads as **declared** or is reported **`MALFORMED`**; silence is
   the one outcome that must not remain.
3. If it is made readable, extend `spec-normalize-ids.sh` so the repairer can normalise it, per
   ADR-0072 §D4's invariant that a flagged line must become readable once repaired.

## Scope

In: `spec-id-predicate.awk`'s recognition of a requirement id; `spec-coverage.sh`'s declared,
malformed and near-miss sets; `spec-normalize-ids.sh`'s repair reach; the corpus regression check
over `docs/specs/`.

Out: rewriting any existing SPEC in `docs/specs/`. Out: the plain-bullet near-miss repair ADR-0072
already shipped. Out: the boundary-anchoring rule that keeps `R-NN` from colliding with `ADR-NNNN`
(ADR-0048), which is not what this issue touches.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/scripts/spec-id-predicate.awk` — the one place that decides
  what counts as a requirement id, loaded by both the checker and the repairer (it loads
  `plan-task-predicate.awk` first).
- `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh` — the checker; emits `MALFORMED`,
  distinguishes near-miss causes on stderr, and takes the documented silent no-IDs path when
  `DECL_N` is 0.
- `staging/plugin/skills/concept-to-code/scripts/spec-normalize-ids.sh` — the repairer; adds a
  missing checklist marker to a plain-bullet declaration and prints the diff.
- `staging/plugin/skills/concept-to-code/SKILL.md` — Step 5's gate block, which runs the repairer
  automatically on the one diagnosable cause and then re-runs the checker.
- `staging/plugin/scripts/tests/spec-coverage.test.sh` — the harness, including **`RN12`**, which
  currently pins the bold-wrapped case as a *disclosed limit* ("a bold-wrapped id is not detected —
  the checker cannot read it in either form"). `RN12` is the assertion this issue inverts, and it
  must be changed in kind rather than deleted.
- `docs/specs/` — the regression corpus, 36 SPECs measured at spec time.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0072-171-spec-id-near-miss-self-repair.md` — the source; anchor on the
  "Bold-wrapped ids stay invisible to the checker in both forms" sentence, not on `:147`.

## Data model

A requirement declaration in a SPEC's Success criteria: `- [ ] R-01 — <text>`. The forms at issue
are `- [ ] **R-01** — <text>` and, following ADR-0072's "in both forms", the plain-bullet bold
variant `- **R-01** — <text>`.

## API / Interfaces

`spec-coverage.sh` is a **checker**: it branches on an exit code and must distinguish "did not run"
(exit 3) from "found nothing". `spec-normalize-ids.sh` is the repairer and prints `CLEAN` when there
is nothing to repair. No new stdout token should be introduced unless the exit-code contract
demands it — ADR-0072 deliberately reported the near-miss as `MALFORMED` and separated the causes on
stderr.

## UI flows

The Step 5 gate output: the checker's verdict, the repairer's diff when it acts, and the re-run
verdict.

## Edge cases

- **The silent path is the failure.** A SPEC whose ids are all bold-wrapped keeps `DECL_N` at 0, the
  gate passes, and the requirement-coverage gate is inert for that whole feature. This is #171 with
  a different decoration.
- **Detection is bounded by the repair's reach** (ADR-0072 §D4): every flagged line must become
  readable once repaired, or the gate reports a problem, rewrites the file and still fails. That
  invariant is precisely why the bold case was excluded, and R-02 is the condition for lifting the
  exclusion.
- **A mixed SPEC is the worse case** — only *partially* silent. ADR-0072 records that the near-miss
  guard is deliberately **not** conditioned on `DECL_N`, and a bold-id guard needs the same
  reasoning applied to it explicitly rather than inherited.
- **The corpus must produce the same verdicts as before** (R-03), with a count guard against a
  vacuous loop — a sweep over zero SPECs reports no regressions and looks identical to a clean run.
- **The repairer edits a human-reviewed artifact without asking**, which is safe only because Gate
  4.0 has already committed the planning artifacts (ADR-0071); any widening of the repair inherits
  that dependency.
- **`RN12` is a needle for the old behaviour.** Inverting the behaviour without changing the
  assertion in kind leaves a green test asserting the opposite of the new contract.

## Success criteria

- [ ] R-01 — a bold-wrapped id either reads as declared or is reported `MALFORMED`; silence is the
      one outcome that must not remain.
- [ ] R-02 — if it is made readable, the repairer must be able to normalise it, per ADR-0072 §D4's
      invariant that a flagged line must become readable once repaired.
- [ ] R-03 — every existing SPEC in `docs/specs/` still produces the same verdict as before, proven
      by running the checker over the whole corpus with a count guard against a vacuous loop.
