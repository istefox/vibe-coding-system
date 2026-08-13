# Order the manifest `completed` transition before the Step 7 commit

**Topic slug:** 410-order-the-manifest-completed-transit

Issue #410. `concept-to-code` Step 7 invokes the `commit` skill and only afterwards transitions the
manifest to `completed`. The manifest is therefore committed while it is still `step_7_commit` /
`in_progress`, and the transition that follows leaves an uncommitted change nothing ever commits.

## Objective

Make the committed manifest terminal, on every path that commits one, by ordering the transition
ahead of the `commit` invocation — and record the general rule that ordering implies, so the next
manifest write added below the commit does not reintroduce the class.

## Why it matters

`manifest-validate.sh` invariant 4 requires `project_root` to be an existing directory unless the
chain is terminal (ADR-0078, extended to both terminality axes by ADR-0113). `project_root` is an
absolute machine-specific path. So a committed non-terminal manifest:

- validates on the machine that produced it, where the directory exists;
- fails invariant 4 on every other machine.

`manifest-project-root-terminal.test.sh` `C1` asserts the whole corpus validates, so this reddens
CI for any repository that commits its manifests while staying green locally — which is why it went
unnoticed until `shell-tests` became a required check on `main`.

Observed on PR #409:

```
FAIL: C1: 2 of 56 still invalid — 2026-08-11-399-bound-phase-p-step-3-to-roadmap-stat.manifest.yml
                                  2026-08-11-a-per-file-budget-ceiling-is-parsed-and.manifest.yml
```

The full suite was 76/0 locally at the same commit. Both manifests were then transitioned by hand.

## Measurements taken before design

Stated so a later reader can re-derive rather than trust. All figures 2026-08-12.

| Fact | Value |
|---|---|
| Manifests in `docs/manifests/` | 57 (56 tracked; the 57th is this chain's own) |
| `chain_path` distribution | 36 `standard`, 19 `null` (legacy), **0 `express`, 0 `hybrid`** |
| Commit-invoking steps in `concept-to-code/SKILL.md` | 3 — Step 7 (Standard), E4 (Express), H5 (Hybrid) |
| Standard Step 7 transition | `SKILL.md:2796`, **prose only**: *"Transition to `completed`. Write final report."* |
| Express E4 transition | `SKILL.md:2879-2882`, a command, **after** the commit invocation |
| Hybrid H5 transition | `SKILL.md:2986`, **prose only**, after the commit invocation |
| Manifest passed to `commit --include` | Standard Step 7 only (`SKILL.md:2729`) |
| `manifest-set-artifact.sh` terminal guard | **none** — it writes to a terminal manifest without complaint |
| `manifest-transition.sh` | validates the manifest before transitioning |

Three consequences of that table shaped the scope:

1. **The Standard path's transition is not a command at all.** It cannot be ordered relative to an
   invocation because it is prose. This is the PATH-RULE class ADR-0028 and ADR-0117 already fixed
   elsewhere in this same file, and it is plausibly *why* the ordering drifted: there was no
   instruction to order.
2. **E4 and H5 have never run here.** Zero Express or Hybrid manifests exist. Fixing them is a
   forward guard, not a repair of observed damage.
3. **On E4 and H5 the manifest is never committed at all** — no Gate 4.0, no `--include`, and
   `commit` never stages untracked files. The reported ordering defect cannot currently manifest
   there; a different gap sits in its place. That gap is filed separately, not fixed here.

## Scope

**In scope**

- The `completed` transition ordering at all three commit-invoking steps (Step 7, E4, H5).
- Turning the Standard-path and Hybrid-path prose into explicit `manifest-transition.sh`
  invocations carrying the absolute helper path.
- The behaviour when `commit` returns without having committed.
- A stated invariant covering every manifest write in a commit-invoking step.
- A derived guard, plus its plants.

**Out of scope, and named rather than silently dropped**

- The E4/H5 uncommitted-manifest gap → its own issue.
- Any change to `manifest-transition.sh`'s legal-pair table. No new pair is added; in particular no
  `completed → step_7_commit` rollback, because ADR-0078's exemption for invariant 4 rests on the
  terminal states being absorbing.
- Any change to the shared manifest helpers. Making them refuse a write once terminal would reach
  every step and `autopilot-build`; its blast radius is far wider than this issue.
- Gate 4.0's commit of an in-flight manifest, which is correct and must keep working.
- The 57 existing manifests, which stay byte-unchanged.

## Stack

Markdown (`SKILL.md` instructions) and bash 3.2 (`*.test.sh` harness). No runtime code, no
dependencies, no build.

## Architecture

### The ordering

Step 7's sequence becomes, in this order:

1. **7.0** — collapse the Step 5 snapshots (ADR-0104), unchanged.
2. **7.0b** — archive this chain's SPEC and repoint `artifacts.spec` (ADR-0106), unchanged.
3. **new** — transition to `completed`, so the repointed value is inside the transition's own write
   and the manifest is final.
4. `commit` invocation with `--include <archived-spec-path>,<manifest-path>`, unchanged.
5. Post-commit actions — conditional push, PROJECT.md update, cost snapshot, final report.

Step 3 must follow step 2: `manifest-set-artifact.sh` has no terminal guard, so a repoint after the
transition would succeed silently and land outside the commit — the same defect one write over.

None of the post-commit actions in step 5 writes the manifest. Verified, not assumed; that is what
makes the manifest final at commit time rather than merely usually-final.

### The invariant

Stated in Step 7 in one line, because the transition is only the instance:

> Every manifest write in this step precedes the `commit` invocation, and the transition to
> `completed` is the last of them. A manifest write after `commit` is an uncommitted change nothing
> ever commits.

### Declined-commit behaviour

`commit` carries its own HITL gate. Once the transition moves ahead of it, declining that gate
leaves a terminal manifest over an uncommitted tree, and terminal states are absorbing — there is
no legal way back.

The chain **stops and reports it**, in those words, naming the manifest path and the fact that the
tree is uncommitted. It does not attempt a rollback, does not invent a transition pair, and does not
proceed to the post-commit actions. An edge case reported loudly beats a state machine weakened to
accommodate it.

### The guard

A derived assertion over `concept-to-code/SKILL.md`, anchored on **the two mechanisms themselves** —
every `manifest-transition.sh … completed completed` invocation and every `commit` skill
invocation — never on headings or block delimiters.

That choice is load-bearing and has history behind it. ADR-0083 §D3 measured heading-anchored
extractors going silently vacuous: `plan-task-count` went 43/0 → 35 passed/2 failed with **six
assertions simply vanishing**, and `scope-guards` misattributed its failure to the guard it was
checking. Anchoring on the mechanism removes the failure mode by construction — a rename that breaks
the guard is the same rename that breaks the thing being guarded.

The population is derived at run time, so a fourth commit-invoking step added later is included
without editing the guard. A count guard fails loudly if fewer than three pairs resolve, rather than
passing vacuously.

## Data model

No manifest field is added, changed or removed. No schema version bump. `manifest_schema_version`
stays `1.3`.

## API

No script gains, loses or changes an argument, an exit code or an output token.

## UI flows

One new operator-visible message, on the declined-commit path only. Every other run is unchanged in
what it prints.

## Edge cases

- **Commit declined or aborted at its own gate** — handled above: stop and report, no rollback.
- **Gate 4.0's in-flight commit** — must keep working. The rule is about writes inside a
  *commit-invoking step*, not a ban on ever committing a non-terminal manifest.
- **`gate_e3_verify → completed` ("Commit later") and the abort branches** — these transition to a
  terminal state without invoking `commit`, so they have no ordering to get wrong and must not trip
  the guard.
- **A resumed or already-committed run where `commit` reports nothing to commit** — that is a pass,
  not a decline, and must not trigger the stop-and-report path.
- **`commit --autopilot`** — skips its own gate, so the declined-commit path cannot fire there; the
  ordering change is otherwise identical.
- **A fourth commit-invoking step added later** — included in the guard's population by
  construction, not by someone remembering to add it.
- **This chain's own Step 7** — the first run of the new ordering, and its own evidence.

## Success criteria

- [ ] R-01 — The Standard path's Step 7 transition to `completed` is an explicit
  `manifest-transition.sh` invocation carrying the absolute `~/.claude/skills/concept-to-code/scripts/`
  prefix, not prose.
- [ ] R-02 — The Hybrid path's Step H5 transition is likewise an explicit invocation, not prose.
- [ ] R-03 — At all three commit-invoking steps (Step 7, E4, H5) the `completed` transition precedes
  the `commit` skill invocation.
- [ ] R-04 — On the Standard path the transition occurs after Step 7.0b's `artifacts.spec` repoint,
  so the repointed value is inside the committed manifest.
- [ ] R-05 — Step 7 states the invariant that every manifest write in the step precedes the `commit`
  invocation and that the transition is the last of them.
- [ ] R-06 — When `commit` returns without having committed, the chain stops and reports that the
  manifest is terminal while the tree is uncommitted; no rollback is attempted, no transition pair is
  added, and the post-commit actions do not run.
- [ ] R-07 — `commit` reporting nothing to commit on a resumed or already-committed run is treated as
  a pass, distinct from a decline.
- [ ] R-08 — Gate 4.0's commit of an in-flight manifest is unchanged and still works.
- [ ] R-09 — A derived guard asserts, for every commit-invoking step in `concept-to-code/SKILL.md`,
  that the `completed` transition precedes that step's `commit` invocation.
- [ ] R-10 — The guard is anchored on the transition and commit invocations themselves, not on
  headings or block delimiters, and derives its population from the file at run time.
- [ ] R-11 — The guard carries a count guard that fails loudly when fewer than three pairs resolve,
  so a derivation that stops matching cannot pass vacuously.
- [ ] R-12 — Terminal transitions that do not invoke `commit` (Gate E3 "Commit later", the abort
  paths) do not trip the guard.
- [ ] R-13 — `manifest-transition.sh`'s legal-pair table is unchanged; the total stays 45.
- [ ] R-14 — All 57 existing manifests are byte-unchanged.
- [ ] R-15 — Every new assertion carries a declared plant in `plant-check.sh`'s registry, and each
  plant is verified to actually fire.
- [ ] R-16 — The full harness is green, and the new guard is seen RED against the pre-fix ordering.
- [ ] R-17 — The E4/H5 uncommitted-manifest gap is filed as its own issue and referenced from the
  ADR, rather than fixed here or left unrecorded.
