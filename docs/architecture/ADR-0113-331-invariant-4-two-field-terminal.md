# ADR-0113 — Invariant 4 read one field where the state lives in two

- **Status:** Accepted
- **Date:** 2026-08-01
- **Issues:** #331 (closes)
- **Amends:** ADR-0078 (issue #197) in part — the terminality reading of invariant 4 only
- **Related:** ADR-0109 (`manifest-entry-state.sh`, the two-field reading), ADR-0111 (the same
  reading applied to `project-conductor` branch C), ADR-0076 (absent / invalid / unreadable are
  three states), ADR-0086 (extract only when two answers would be a defect), ADR-0043 (a list
  cannot see what it omits), ADR-0092 (a derived guard over a value domain), ADR-0108 (plants)

## Context

`manifest-validate.sh` invariant 4 exempts a dead `project_root` when the chain is terminal, because
on a finished chain the path is a historical record rather than a live precondition (ADR-0078). It
decides terminal by reading **`current_step` alone**.

Form C (abort) sets `status: aborted` and leaves `current_step` untouched. So an aborted chain is
terminal by one field and live by the other, the exemption does not apply, and the manifest fails
invariant 4 on any machine where its `project_root` does not exist — which is every machine except
the one that produced it. That is exactly the machine-dependence ADR-0078 exists to remove.

Found by committing a manifest. PR #328 records the orphaned
`2026-07-31-the-sixth-bare-manifest-set-flag-sh-ment.manifest.yml` (`current_step: step_0_init`,
`status: aborted`). It validates locally and fails on CI, and the difference is not the manifest.

**This is the third site of one defect and the other two are already fixed.** ADR-0109 built
`manifest-entry-state.sh` to read both fields for exactly this reason; ADR-0111 applied the same
reading to `project-conductor` branch C, whose message reported this same orphan as `step_0_init`.

## What was measured, 2026-08-01

**M1 — the claim holds, and the widening is smaller than it looks.** All 41 corpus manifests are
`completed | completed` on the two fields, so every one already takes the exemption through
`current_step`. Widening changes the verdict of **exactly one file**: the 42nd, the one PR #328 adds.

**M2 — invariant 4 is the only site of this class.** Invariants 7 (`status=completed` → artifacts
non-null) and 8 (`status=failed` → `failed_step` non-null) also read one field, but their condition
*is about that field by name* — they are not asking "is this chain over". Invariant 4 is the only
invariant in the file that asks that question, so there is no fourth site to convert.

**M3 — and this is what changed the design: "terminal by `status`" is NOT absorbing in the same
mechanical sense.** ADR-0078's whole argument is that the exempt states never appear as a SOURCE in
`manifest-transition.sh`'s pair table, so a manifest in one can never move again. `status` is not in
that table at all — the script validates a **new** status passed as its third argument and never
inspects the one on disk. A manifest with `status: aborted` and `current_step:
step_5_implementation` can therefore still be transitioned.

**M4 — the shared-answer question has a cycle, so it answers itself.** `manifest-entry-state.sh`
already reads both fields, with the Form C reason written out. But it **derives its state enum from
`manifest-validate.sh`**, so a dependency in the other direction closes a loop.

**M5 — found on the way, in the same class, one list over: four harnesses had never run in CI.**
`docs-ci.yml`'s `shell-tests` job enumerates the harnesses by name, and the enumeration had drifted
by four — `manifest-entry-state`, `permission-mode-state`, `conductor-entry-failure-split`,
`nightly-guard-disarm`, one from each of the last four merged PRs. Their assertions ran on the
author's machine and nowhere else, and nothing reported it.

## Decision

### D1 — Invariant 4 exempts on `current_step` OR `status`

Presence of `project_root` stays required in every state; only the *existence* half is conditional,
exactly as before. Two `case` statements over the two fields set one flag.

### D2 — The two axes are exempt for two different reasons, and the source says so

Writing "terminal means absorbing" over both would certify a premise that is false of one of them
(M3). Axis 1 keeps ADR-0078's proof. Axis 2 rests on `completed|failed|aborted` being a **declared
end** — declared by the chain or by a human running Form C — which is the reading ADR-0109 makes for
its `TERMINAL` token and ADR-0111 acts on. The comment block says which argument covers which axis
and instructs the next reader not to restate the first over the second.

### D3 — Two copies pinned by a derived guard, not an extraction

ADR-0086's criterion says extract when two copies giving different answers would be a defect, and
here they would. The cycle in M4 forbids extraction in the only direction that would help, so the
validator keeps its own read and `A6` derives the terminal set from **both** files at run time and
requires them equal, count-guarded on both sides (ADR-0092 §V's shape).

### D4 — `docs-ci.yml`'s harness list gets the reverse check this repository already has for PAIRS

The four missing names are added, and `pairs-completeness.test.sh` — the file whose whole subject is
*a file that exists but is in no list* — gains `CI0`/`CI0b`/`CI1`/`CI2`. A harness that genuinely
must not run in CI declares `# ci-dark-exempt: <reason ≥ 40 chars>` in its own header, so the waiver
travels with the file (ADR-0077) rather than sitting in a list inside the test.

Both denominators are guarded, and **the reason is asymmetric**: a `for t in` line that stops
matching yields an empty list and makes every harness read as uncovered — loud. An empty file glob
yields nothing to check and reads as full coverage — silent. The second is the one that matters.

## Consequences

- **The exemption passes on strictly more inputs.** Bounded to manifests already declared over by
  one field or the other; a manifest live on both axes with a dead root still fails, and `B4` and
  `D2` assert that from the two sides.
- **`mk()` gained a status argument, and an existing fixture was corrected rather than an assertion
  relaxed.** Before #331 every fixture inherited BASE's `status: "completed"` while patching
  `current_step` alone, so a fixture *named* in-flight was terminal on the axis nothing was reading
  yet. `B4` went red the moment invariant 4 started reading both fields: the assertion was right,
  the fixture was under-specified, and the coupling it relied on had never been stated.
- **`A1`'s derivation needed `s/).*//` rather than `s/)//`.** The case arm now carries its body on
  the same line, and dropping only the paren left the body glued to the last state name — three
  assertions then compared against a list containing `abortedproject_root_terminal=1;;` and reported
  a disagreement that did not exist. A derivation written against one syntactic shape, which is the
  ADR-0077 `compliant()` lesson in a new place.
- **`CI1` carries no plant, deliberately.** `plant-check.sh` mutates an isolated copy of `staging/`
  and `docs/`; `.github/workflows/docs-ci.yml` is in neither, so the mechanism cannot be reached and
  a sandbox run reads the real file. What it has instead is live red evidence — its first run failed
  naming the four real harnesses. Recorded at the site so the absence does not read as an oversight.

## Recorded, not fixed

- **`manifest-transition.sh` can still transition a manifest that is terminal by `status`** (M3).
  The exemption now covers a state the state machine does not refuse. Closing it means a new refusal
  in a 48-pair machine — ADR-0047 §A2's blast-radius argument, which is why it is a follow-up issue
  and not this one. Nothing consumes it today: every consumer reads an in-flight manifest, and
  ADR-0109's classifier already routes a status-terminal manifest to `TERMINAL`.
- **Nothing asserts the two fields agree, and nothing should.** Form C deliberately makes them
  disagree; an invariant requiring consistency would reject the state this ADR exists to accept.
- **The `ci-dark-exempt` waiver is a sentence a human wrote.** `CI1` checks it is long, never that
  it is true — the same limit ADR-0077 §T4 states for its own exemptions.

## Verification

The acceptance evidence is the real file, not a fixture: the orphan manifest from PR #328's branch,
with its `project_root` rewritten to a path that does not exist, **fails the pre-#331 validator with
`project_root '...' is not an existing directory` and validates cleanly under the new one.** That is
the CI failure reproduced and closed end to end.

Harness: `manifest-project-root-terminal.test.sh` 22/22 with a `Z1` floor it did not have; four
plants declared where it had none, all four seen firing. `pairs-completeness.test.sh` 265/265, with
`CI1` seen RED on the live defect before the four names were added.

## References

- Issue #331
- `docs/architecture/ADR-0078-197-project-root-terminal.md` § Correction
- `docs/architecture/ADR-0109-319-manifest-entry-state.md` — the classifier that already reads both
- `staging/plugin/skills/concept-to-code/scripts/manifest-validate.sh` invariant 4
- `staging/plugin/scripts/tests/manifest-project-root-terminal.test.sh` sections A4–A6, D
- `staging/plugin/scripts/tests/pairs-completeness.test.sh` section CI
