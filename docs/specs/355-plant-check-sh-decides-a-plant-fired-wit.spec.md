# SPEC — plant-check.sh decides a plant fired with a PREFIX match: 26 of 166 plants pin nothing

Source: GitHub issue #355

## Objectives

1. Make `plant-check.sh` credit a planted mutation to the assertion it was declared for, rather
   than to any assertion whose id merely starts with the same characters.
2. Re-verify the whole declared plant corpus afterwards, since anchoring the match will expose
   plants that were only ever credited to a sibling's failure.
3. Keep the registry answering the question ADR-0108 built it for — *does this assertion pin
   anything?* — behaviourally rather than by prefix coincidence.

## Scope

In:

- `staging/plugin/scripts/tests/plant-check.sh`, the fired/not-fired decision (`grep -q "^FAIL:
  $aid"` at the site the issue names around line 162).
- Every declared plant in the corpus, which must be re-verified once the match is anchored.

Out:

- The three other recorded boundaries of the same script: `PC4` (indented declarations silently
  skipped, ADR-0115), the `../docs/` path hatch (ADR-0116), and the fact that a replacement cannot
  contain a newline (ADR-0112). Named as context; not this issue's subject.
- The cost characteristics of the registry — that is issue #350.

## Stack

Documentation and blueprint repository: markdown plus bash 3.2 test harnesses. No build, lint, run
or package manager. `plant-check.sh` runs each declared plant against an isolated `cp -R` of the
tree and executes the target test file.

## Architecture

- `staging/plugin/scripts/tests/plant-check.sh` — the registry runner. Collects declarations with a
  column-anchored `grep '^# plant:'`, applies each mutation in a sandbox, runs the target file, and
  decides the plant fired by matching the harness output.
- The declarations themselves live beside their assertions across the `*.test.sh` corpus, in the
  form `# plant: <assertion-id> | <path-relative-to-staging> | <needle> | <replacement>`.
- `PC1` (every declared plant fired) and `PC2` (every declaration resolved to exactly one site) are
  the registry's own self-checks and must continue to hold.

## Data model

None beyond the declaration record already in use: `{assertion-id, path, needle, replacement}`.

## API / Interfaces

`plant-check.sh` is invoked with no arguments and reports on stdout. It is a harness, not a library;
the change is internal to its verdict step.

## UI flows

None.

## Edge cases

- **Sibling ids that legitimately share a prefix**, measured in the issue: `SP5` against
  `SP5b`/`SP5c`/`SP5d`; `TC1` against `TC10`–`TC13`; `G1` against `G10`/`G10b`/`G11`/`G11b`; `F1`
  against `F10`–`F13`; `RB1` against `RB10`/`RB11`; plus `MES2`/`MES2b`, `MES8`/`MES8a`,
  `MESF2`/`MESF2a`, `G7`/`G7b`, `RJ13`/`RJ13b`, `TC8`/`TC8b`, `H3`/`H3b`. **26 of 166** declared
  plants sit on at least one such collision.
- **A plant that stops firing once the match is anchored** is the expected and desired outcome, not
  a regression: it means that plant was pinning nothing and the assertion needs work.
- **Anchoring form** — `^FAIL: <id>[: ]` or an exact-token compare. The issue names both; the
  choice must not admit a longer id as a match.
- **The recursion is real**: a change to `plant-check.sh` is a change to the thing that validates
  plants, so how the change itself is verified has to be stated explicitly rather than assumed.
- **New assertion ids should avoid prefix collisions until this ships.**
  `nightly-guard-disarm.test.sh` already names its eighth assertion `CP8` rather than `CP7b` for
  this reason, with the rationale recorded at the declaration site.

## Success criteria

- [ ] R-01 — `plant-check.sh` credits a fired plant only to the assertion id it was declared for;
  a sibling whose id extends that prefix no longer satisfies it.
- [ ] R-02 — every declared plant in the corpus is re-verified against the anchored match, and any
  plant that stops firing is named rather than silently dropped or re-pointed.
- [ ] R-03 — `PC1` and `PC2` still hold after the change.
- [ ] R-04 — the verification of the change to `plant-check.sh` itself is stated explicitly, since
  the script under change is the one that validates plants.
- [ ] R-05 — the twelve collisions the issue measures are covered by the re-verification, and the
  count of plants that were only ever credited to a sibling is recorded.
