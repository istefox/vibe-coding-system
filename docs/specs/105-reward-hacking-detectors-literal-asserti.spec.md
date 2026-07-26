# SPEC — Reward-hacking detectors: literal assertions, deleted symbols, swallowed errors

Source: GitHub issue #105

Runs after issue #101, which puts `weakening-scan.sh` on every path; this feature adds detectors to a scanner already being called everywhere.

## Objectives
1. Detect tests forced green by a hardcoded expected value.
2. Detect tests that assert nothing meaningful.
3. Detect deletion of a public symbol outside the declared task scope.
4. Detect a swallowed error.

## Scope
In: four new report-only detector outputs in `weakening-scan.sh`; extension of its existing harness.
Out: making any of them blocking; auto-fixing anything.

## Stack
Bash 3.2 + awk, matching the existing implementation of `weakening-scan.sh`, which is a single awk program over a unified diff.

## Architecture
Modified: `staging/plugin/skills/review-triage-fix/scripts/weakening-scan.sh` and its harness. Language gating for the error-path detector follows the four stacks declared in `staging/user/rules/`.

## Data model
Four new output lines, same shape as the existing `WEAKENED` line:
`SUSPECT<TAB><file><TAB>literal-assertion-added|zero-assertion-test|deleted-public-symbol|swallowed-error`

## API / Interfaces
Unchanged: unified diff on stdin, exit 0 always, `CLEAN` when nothing is found. `SUSPECT` is advisory and distinct from `WEAKENED`, so callers can treat the two severities differently.

## UI flows
None.

## Edge cases
- A parameterised test using literal table values must NOT trigger `literal-assertion-added` — this is the documented false-positive corpus and needs an explicit negative fixture.
- A symbol removal accompanied by a `PATTERN: REMOVE` header with a zero-hit caller check must not fire.
- A catch block that rethrows, or that logs, must not fire.
- The existing `CLEAN` contract and `WEAKENED` behaviour must be byte-identical for inputs that contain no new-detector matches.

## Success criteria
- [ ] Each of the four detectors fires on a positive fixture.
- [ ] Each stays silent on a negative fixture.
- [ ] A parameterised test does not trigger `literal-assertion-added`.
- [ ] Existing `WEAKENED` and `CLEAN` behaviour is unchanged.
- [ ] Every new assertion has been seen RED before being made green.
- [ ] Any new test file is registered in BOTH CI registries.
