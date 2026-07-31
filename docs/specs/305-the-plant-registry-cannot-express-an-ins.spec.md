# SPEC — the plant registry cannot express an insertion

Source: GitHub issue #305

## Objectives
1. Enumerate the defect shapes an insertion-plant would express and a replacement-plant cannot — a
   deleted transition pair, a removed `VALID_STEPS` entry, a dropped assertion — and count how many
   existing assertions guard against a deletion and therefore have no plant today.
2. Extend the plant registry so a deletion-shaped defect is expressible as a plant.
3. Keep the registry's two safety properties intact for both plant forms: the exactly-one-match
   requirement, and execution against an isolated copy that can never touch the real tree.

## Scope
In: `staging/plugin/scripts/tests/plant-check.sh` — the declaration syntax, the collector, the
one-match validation, the isolated-copy mutation and the runner; the plant declarations
(`# plant: …` lines) across the harness that would newly become expressible; the measurement of
deletion-guarding assertions with no plant.

Out: rewriting existing assertions. The registry's role stays mutation testing of assertions already
written — it does not become a linter, a static needle detector (measured and ruled out in ADR-0108:
77 of 181 resolvable assertions flagged, and only 181 of 543 resolvable at all), or a shared helper
across the hermetic test files. The `*.test.sh` harness's own pass/fail signal stays separate from
the registry's.

## Stack
Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture
- `staging/plugin/scripts/tests/plant-check.sh` — the registry. Collects `^# plant:` lines from
  every `staging/plugin/scripts/tests/*.test.sh`, count-guards the declaration corpus (`PC0`),
  copies `staging/` and `docs/` into a temp tree, applies the mutation, re-runs the owning test, and
  reports whether the named assertion went RED (`PC1` names a plant that did not fire; `PC3` guards
  the denominator). It is deliberately not a `*.test.sh`, so `.claude/test-cmd`'s glob does not pick
  it up.
- `.github/workflows/docs-ci.yml` — runs the registry last and separately, because "an assertion
  pins nothing" is a different signal from a harness going red.
- Candidate deletion-shaped targets named by the issue, for the measurement:
  `staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh` (the legal transition-pair
  table, guarded by `transition-producer.test.sh` and `tracer-bullet-probe.test.sh`),
  `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` (`VALID_STEPS` and the
  invariants), and any assertion whose subject is the continued *existence* of a line — for example
  `gate5-state-removal.test.sh`, `spec-pointer-archive.test.sh`, `fence-contract-coverage.test.sh`
  `F9`/`F10`, `pairs-completeness.test.sh` `DO1`–`DO5`.
- `docs/architecture/ADR-0108-284-plant-registry.md` — the source; the quoted "Replacement only in
  v1" line will have moved.
- `docs/architecture/ADR-0099-238-hitl-gate-audit-trail.md` (`P4`/`P5`) and
  `docs/architecture/ADR-0104-249-step7-snapshot-collapse.md` (`P2`) — the two occasions a plant hit
  the wrong number of sites, which is why the one-match rule exists.

## Data model
The plant declaration, one line, in the test file beside the assertion it proves:

`# plant: <assertion-id> | <path-relative-to-staging> | <needle> | <replacement>`

Fields: assertion id; path under `staging/`; needle (words joined on `\s+` when matched, so a
wrapped clause is still found); replacement. A ` | ` sequence cannot appear inside a field — the one
deliberate syntax limit. This feature adds a second form capable of expressing a deletion; the
existing four-field replacement form must keep working unchanged.

## API / Interfaces
- The `# plant:` declaration line — the sole authoring interface, read by the collector.
- `plant-check.sh` invocation: `bash plant-check.sh`, run from
  `staging/plugin/scripts/tests/`, reporting `PASS`/`FAIL` per plant plus the `PC0`/`PC1`/`PC3`
  meta-assertions.
- The isolated working tree: `cp -R` of `staging/` and `docs/` into `mktemp -d`, with tests
  resolving their root from `$(dirname "$0")` so a copied tree redirects with no change to any test.

## UI flows
None. The registry reports on stdout in the harness's `PASS:`/`FAIL:` format.

## Edge cases
- A deletion plant whose needle matches zero lines — the needle rotted, and the plant is the defect.
- A deletion plant whose needle matches more than one line — the plant hits sites it did not intend;
  both directions already bit on the day the registry was designed.
- A deletion that leaves the mutated file syntactically invalid, so the owning test fails at parse
  time rather than at the named assertion — a RED for the wrong reason, indistinguishable from
  evidence unless the runner distinguishes them.
- A deletion of a line the owning test never reads: the plant does not fire, which is evidence about
  the assertion, not a formality to get past.
- Backward compatibility: every existing replacement-form declaration must keep parsing and firing.
- The registry is itself an assertion corpus with no plants of its own; `PC0`/`PC3` guard its
  denominator and the regress stops there.
- Per the repository's standing rules: any new assertion added here must itself be seen RED against
  a declared plant, and both directions per contract.

## Success criteria
- [ ] R-01 — a deletion-shaped defect is expressible as a plant.
- [ ] R-02 — the exactly-one-match requirement survives for both forms; zero means the needle
      rotted, more than one means the plant hits sites it did not intend, and both happened the day
      the registry was designed.
- [ ] R-03 — each plant still runs against an isolated copy; nothing may touch the real tree.
