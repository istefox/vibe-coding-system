# SPEC — fence_is_abort_capable is lexical and four measured fences abort from outside it

Source: GitHub issue #299

## Objectives

1. Re-derive the population: determine what `fence_is_abort_capable` is still used for after
   ADR-0107 moved the checked set from the abort-capable subset to the declaration set, and whether
   the four known examples are the whole set or only the ones that happened to be noticed.
2. Either define the population by what a fence can do rather than by which literals it contains, or
   state the lexical limit with the four examples named and add a guard that fails when a fifth
   appears.
3. Leave `F3`, `F5` and `F8` on their deliberately narrow population.

## Scope

In: `fence_is_abort_capable` in `fence-contract-coverage.test.sh` — what it classifies, which
assertions still consume it after ADR-0107, and the four measured fences that abort via a called
script's exit code and are invisible to it.

Out: the declaration set derivation, which ADR-0107 already corrected (`CONTRACT_IDS` now derives
from every declaration, not from `ABORT_LIST`). The `fence-illustration` escape hatch's rules.
`F3`, `F5` and `F8`'s population, which R-02 protects rather than changes.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/scripts/tests/fence-contract-coverage.test.sh` — the whole change. It carries
  `enumerate_fences`, `fence_is_abort_capable` (a word-boundary `exit 1|2` or the standalone word
  `abort`), `ABORT_LIST`, `ALL_FENCES`, `CONTRACT_IDS`, and the `F*` and `S*` assertions. `F3`,
  `F5` and `F8` still read `ABORT_LIST` deliberately; `F4`, `F6`, `F7` and `F9` read the declaration
  set. It is instance 2 of 6 of the derived-guard pattern (ADR-0086), so it is not a candidate for
  extraction into a shared helper.
- The four measured fences outside the classifier, each executed by its own test file:
  - the `spec-archive.sh` invocation fence in `staging/plugin/skills/concept-to-code/SKILL.md`
    Step 1 (ends `exit "$_rc"`; its abort belongs to the caller) — executed by
    `staging/plugin/scripts/tests/spec-archive.test.sh`.
  - the Gate 2b trust-probe fence in the same SKILL.md (no literal `exit 1|2`, no "abort") —
    executed by `staging/plugin/scripts/tests/gate2b-trust-probe.test.sh`.
  - the recovery-baseline check fence (never halts by design) — executed by
    `staging/plugin/scripts/tests/recovery-baseline-rebase.test.sh`.
  - the Step 7.0 collapse fence (`COLLAPSE_NOREPO`, exit 3) — executed by
    `staging/plugin/scripts/tests/step7-snapshot-collapse.test.sh`.
- `staging/plugin/skills/*/SKILL.md` — the fence corpus the enumeration runs over.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0083-206-fence-contract-coverage.md` (the source, quoted line number will
  have moved), `docs/architecture/ADR-0107-281-fence-contract-population.md` (§D2 states why
  widening `F3`/`F5`/`F8` breaks `F8`'s meaning), and ADR-0096, ADR-0102, ADR-0103, ADR-0104 (the
  four disclosures).

## Data model

Three populations that must stay distinguishable:

- every fenced block in the corpus (`enumerate_fences`),
- the abort-capable subset (`ABORT_LIST`, produced by the lexical classifier),
- the declaration set (`CONTRACT_IDS`, every `fence-contract:` marker), which ADR-0107 made the
  checked set.

If R-01's second branch is taken, a fourth artifact is needed: a declared list of the known
lexically-invisible fences, with a guard that fails when a fifth appears.

## API / Interfaces

`fence_is_abort_capable <body-file>` — a shell function returning 0 or 1, internal to the harness
file. `enumerate_fences <file>` — emits one record per fence. The `<!-- fence-contract: <id> -->`
and `<!-- fence-illustration: <reason> -->` markers are the corpus-facing interface and are also the
extraction anchors (ADR-0083 §D3).

## UI flows

None.

## Edge cases

- A fence that aborts only through a called script's exit code — the class, and all four known
  examples.
- A fence ending `exit "$_rc"`, where the value is not a literal.
- A fence that never halts by design (`recovery-baseline-rebase`), which is correctly outside the
  abort-capable set and still needs execution by a test.
- `exit 3` for "did not run" — a checker's third state, which is not an abort in the `F3` sense.
- A fence whose only abort path is a helper resolution failure.
- `F8` measures the escape hatch from `F3` and there is exactly one illustration in the corpus,
  inside the narrow subset; ADR-0107 records what would have to change if a second appeared outside
  it.
- The enumeration must stay indentation-tolerant: two markers sit inside indented list items, which
  is why an earlier count said 101 instead of 138.
- Per the standing rules in the issue footer, a guard's denominator needs its own protection — an
  enumeration that stops matching empties every assertion riding on it, and silent passes read as
  coverage.

## Success criteria

- [ ] R-01 — the population is defined by what a fence can do, not by which literals it contains,
      or the lexical limit is stated with the four examples named and a guard that fails when a
      fifth appears.
- [ ] R-02 — `F3`, `F5` and `F8` keep their deliberately narrow population (ADR-0107 §D2 states why
      widening them for consistency breaks `F8`'s meaning).
