# SPEC — plant-check.sh cost scales as (plants x target-file runtime), not as their sum

Source: GitHub issue #350

## Objectives

1. Measure and record the per-file cost of the plant registry, ranked, so the dominant term is a
   number rather than an impression.
2. Decide, with a stated reason, whether that cost is reduced or accepted.
3. If it is reduced, keep the mechanism intact: a faster registry that stops catching a non-firing
   plant is worse than a slow one.

## Scope

In:

- `staging/plugin/scripts/tests/plant-check.sh` — the sandbox-copy and target-file-execution loop
  that produces the cost.
- The distribution of plants across target files, and each target file's own runtime.
- The `shell-tests` job in `Docs CI`, where the cost is billed.

Out:

- The prefix-match defect in the same script — that is issue #355.
- The three recorded boundaries: `PC4` indented declarations (ADR-0115), the `../docs/` hatch
  (ADR-0116), a replacement containing a newline (ADR-0112).
- Trimming plants off the slow file as a remedy. The issue rules this out explicitly: #349's `L4`
  plant did not fire on its first run, which is exactly the evidence the registry exists to
  produce, so removing plants trades the mechanism for the symptom.

## Stack

Documentation and blueprint repository: markdown plus bash 3.2 test harnesses, run locally by
`.claude/test-cmd` and on GitHub Actions by the `shell-tests` job of `Docs CI`. No build or package
manager.

## Architecture

- `staging/plugin/scripts/tests/plant-check.sh` runs each declared plant against an isolated
  `cp -R` of the tree, then executes **the whole target test file** to see whether the named
  assertion goes RED. So a file with N plants costs N x its own runtime, every CI run, permanently.
- `worktree-isolation-contract.test.sh` is the measured outlier: **26s** locally, because section W
  builds real git fixture repositories, with **11** plants attached by #349 — 11 x 26s = 4m46s.
- The verdict step is a `grep -q "^FAIL: <id>"` over the file's output, which is what makes a
  single-assertion filter conceivable — but only as a property of each hermetic file, not globally.

## Data model

None. The subject is measured runtime: per-file plant count, per-file execution time, and their
product.

## API / Interfaces

None. `plant-check.sh` is a harness invoked with no arguments.

## UI flows

None.

## Edge cases

- **The headline number is one file; the distribution is unknown and may already be worse
  elsewhere.** The measurement must be ranked across all plant-carrying files, not taken from the
  known outlier.
- **`shell-tests` may have grown for reasons other than the one named.** The measured delta
  (3m53s → 9m39s after #349, a 5m54s increase) is attributed mostly but not wholly to the 11 plants
  on the 26s file; the remainder is that file's own slower run in the main sweep plus growth
  elsewhere. Re-derive rather than inherit.
- **ADR-0108's own estimate no longer holds.** Its ~0.21s per plant is the **sandbox copy**, not
  the test run, and its consequence bullet says "~0.8s per plant, so 100 plants would want their
  own job". At 125 plants and a 26s target file the dominant term is the target file's runtime, and
  it is not bounded.
- **Grouping plants by target file** is a candidate for removing per-plant sandbox copies: plants
  targeting different files cannot interfere, plants against the same file can. Its safety needs
  stating, not assuming.
- **A separate CI job changes wall-clock and not billed minutes.** Which of the two is the actual
  constraint has to be said before choosing.
- **Accepting the cost is a legitimate outcome** and must be recorded as one, not left implicit.
- **The recursion applies**: a change to `plant-check.sh` is a change to the thing that validates
  plants, so how the change itself is verified must be stated explicitly.

## Success criteria

- [ ] R-01 — the per-file cost of the plant registry is measured and recorded, ranked, so the
  dominant term is a number rather than an impression.
- [ ] R-02 — a decision, with its reason, on whether the cost is reduced or accepted. Accepting it
  is a legitimate outcome and must be recorded as one, not left implicit.
- [ ] R-03 — if it is reduced, `PC1`/`PC2` still hold and every existing plant still fires. A faster
  registry that stops catching a non-firing plant is worse than a slow one.
