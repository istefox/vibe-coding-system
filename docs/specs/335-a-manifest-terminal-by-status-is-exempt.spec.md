# SPEC — a manifest terminal by status is exempt from invariant 4 and the state machine still lets it transition

Source: GitHub issue #335

## Objectives

1. Decide, and record at the transition site, whether a manifest that is terminal by `status` may
   still transition — either as a refusal or as an explicit non-refusal with its reason.
2. Preserve Form C's abort path, which makes `status` and `current_step` disagree on purpose.
3. Establish the cost of a refusal against the stored manifest corpus before choosing.

## Scope

In:

- `concept-to-code/scripts/manifest-transition.sh` — the pair table and the transition decision.
- `manifest-validate.sh` invariant 4, as ADR-0113 left it (the two-axis terminality exemption).

Out:

- Invariant 4's exemption itself. ADR-0113 shipped it deliberately and this issue does not reopen
  it; what is open is the state machine's silence about the same axis.
- ADR-0078's first-axis proof, which is mechanical and stands.

## Stack

Documentation and blueprint repository: markdown plus bash 3.2 scripts and hermetic `*.test.sh`
harnesses. No build or package manager. Manifests are YAML under `docs/manifests/`.

## Architecture

- `manifest-transition.sh` holds the legal-pair table. ADR-0078's proof for the `current_step` axis
  is mechanical: no exempt state appears as a SOURCE in that table, so a manifest in one can never
  move again.
- **That proof does not cover `status`, and ADR-0113 says so rather than inheriting it.** `status`
  is not in the pair table at all: the script validates a **new** status passed as an argument and
  never inspects the one on disk.
- So a manifest with `status: aborted` and `current_step: step_5_implementation` is exempt from
  invariant 4 as a declared end, and is still legally transitionable by the state machine.
- Form C is the writer that creates the disagreement, setting `status: aborted` and leaving
  `current_step` untouched.

## Data model

Manifest fields `current_step` and `status`, and the terminal set shared between
`manifest-validate.sh` and `manifest-entry-state.sh`.

## API / Interfaces

`manifest-transition.sh` is a checker invoked with the manifest path and the new state; callers
branch on its exit code. Any refusal added here changes that contract for every caller.

## UI flows

None.

## Edge cases

- **Nothing observed has gone wrong.** This is a state the exemption covers and the machine does
  not refuse, recorded rather than fixed because ADR-0047 §A2's blast-radius argument applies: a
  new refusal inside a 48-pair machine that touches no git today gains a failure mode on every
  transition.
- **The state may be unreachable in practice.** Whether any caller can actually reach a transition
  on a status-terminal manifest, or whether every path checks `current_step` first, must be
  measured. If unreachable, the correct outcome is a documentation line at the transition site, not
  a refusal.
- **Form C must not break.** It makes the two fields disagree on purpose, and any refusal must not
  break the abort path it exists to record.
- **The corpus is the cost test.** Run any candidate refusal over every stored manifest before
  deciding.
- **"Did not run" must stay distinguishable from "found nothing"** (exit 3), as everywhere else in
  this codebase.

## Success criteria

- [ ] R-01 — the answer to "can a status-terminal manifest still transition" is decided and
  recorded at the transition site, either as a refusal or as an explicit non-refusal with its
  reason.
- [ ] R-02 — if a refusal ships, Form C's abort path is asserted to still work, seen RED first.
- [ ] R-03 — no existing manifest in the corpus changes verdict, or every one that does is named.
